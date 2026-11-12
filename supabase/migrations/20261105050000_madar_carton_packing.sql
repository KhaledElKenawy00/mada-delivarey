-- تعبئة الكرتونة: لو موجودة، الكرتونة = unit × units_per_carton.
-- كل الكميات في warehouse_stock/rep_stock/stock_issue_items/sale_items
-- متسجلة بوحدة unit (العبوة) دايماً — الكرتونة تحويل في الواجهة بس.
alter table products add column if not exists carton_unit text;
alter table products add column if not exists units_per_carton numeric(12,2) not null default 1;

create or replace function warehouse_live(p_wh uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; v_wh uuid; w warehouses;
begin
  me := assert_active();
  v_wh := coalesce(p_wh, me.warehouse_id);
  select * into w from warehouses where id = v_wh;
  if w.id is null then raise exception 'NOT_FOUND'; end if;
  if me.role = 'rep' then raise exception 'FORBIDDEN'; end if;
  if me.role = 'keeper' and me.warehouse_id <> v_wh then raise exception 'FORBIDDEN'; end if;
  if me.role = 'manager' and w.company_id <> me.company_id then raise exception 'FORBIDDEN'; end if;

  return jsonb_build_object(
    'warehouse', jsonb_build_object('id', w.id, 'name', w.name, 'address', w.address,
                                    'lat', w.lat, 'lng', w.lng, 'max_reps', w.max_reps),
    'keeper', (select jsonb_build_object('name', p.full_name, 'phone', p.phone,
                                         'device', l.device_name, 'activated', l.fingerprint is not null)
                 from profiles p left join licenses l on l.profile_id = p.id
                where p.warehouse_id = v_wh and p.role = 'keeper' limit 1),
    'reps', reps_live(v_wh),
    'stock', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', pr.id, 'code', pr.code, 'name', pr.name, 'unit', pr.unit, 'price', pr.price,
        'carton_unit', pr.carton_unit, 'units_per_carton', pr.units_per_carton,
        'in_stock', coalesce(ws.qty, 0),
        'with_reps', coalesce((
          select sum(rs.qty_issued - rs.qty_sold - rs.qty_returned)
            from rep_stock rs join work_sessions s on s.id = rs.session_id
           where s.warehouse_id = v_wh and s.status <> 'closed' and rs.product_id = pr.id), 0)
      ) order by pr.name)
      from products pr
      left join warehouse_stock ws on ws.product_id = pr.id and ws.warehouse_id = v_wh
      where pr.company_id = w.company_id and pr.active), '[]'::jsonb),
    'feed', coalesce((
      select jsonb_agg(f order by f->>'at' desc) from (
        select f from (
          select jsonb_build_object('kind', 'sale', 'no', sa.no, 'at', sa.created_at, 'amount', sa.total,
                                    'title', c.name, 'rep', p.full_name) f
            from sales sa join customers c on c.id = sa.customer_id join profiles p on p.id = sa.rep_id
           where sa.warehouse_id = v_wh and local_date(sa.created_at) = local_date(now()) and not sa.voided
          union all
          select jsonb_build_object('kind', 'collection', 'no', co.no, 'at', co.created_at, 'amount', co.amount,
                                    'title', c.name, 'rep', p.full_name)
            from collections co join customers c on c.id = co.customer_id join profiles p on p.id = co.rep_id
           where co.warehouse_id = v_wh and local_date(co.created_at) = local_date(now())
          union all
          select jsonb_build_object('kind', 'issue', 'no', si.no, 'at', si.created_at, 'amount', si.total,
                                    'title', p.full_name, 'rep', p.full_name)
            from stock_issues si join profiles p on p.id = si.rep_id
           where si.warehouse_id = v_wh and local_date(si.created_at) = local_date(now())
        ) u order by f->>'at' desc limit 12
      ) t), '[]'::jsonb)
  );
end $$;

create or replace function session_json(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'session_id',   s.id,
    'status',       s.status,
    'started_at',   s.started_at,
    'submitted_at', s.submitted_at,
    'rep_id',       p.id,
    'rep_name',     p.full_name,
    'issue_no',     (select no from stock_issues where session_id = s.id order by created_at limit 1),
    'totals',       session_totals(s.id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', pr.id, 'name', pr.name, 'unit', pr.unit, 'price', rs.price,
        'carton_unit', pr.carton_unit, 'units_per_carton', pr.units_per_carton,
        'issued', rs.qty_issued, 'sold', rs.qty_sold, 'returned', rs.qty_returned
      ) order by pr.name)
      from rep_stock rs join products pr on pr.id = rs.product_id
      where rs.session_id = s.id), '[]'::jsonb),
    'settlement', (select to_jsonb(st) from settlements st where st.session_id = s.id)
  )
  from work_sessions s join profiles p on p.id = s.rep_id
  where s.id = p_session
$$;
