-- =====================================================================
-- مدار (Madar) — سعر كرتونة مستقل (ممكن يكون غير متناسب مع سعر الوحدة × العدد)
-- =====================================================================

alter table products add column if not exists carton_price numeric(12,2);

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
        'product_id', pr.id, 'code', pr.code, 'name', pr.name, 'unit', pr.unit, 'price', pr.price, 'cost', pr.cost,
        'carton_unit', pr.carton_unit, 'units_per_carton', pr.units_per_carton, 'carton_price', pr.carton_price,
        'in_stock', coalesce(ws.qty, 0),
        'with_reps', coalesce((
          select sum(rs.qty_issued - rs.qty_sold - rs.qty_returned)
            from rep_stock rs join work_sessions s on s.id = rs.session_id
           where s.warehouse_id = v_wh and s.status <> 'closed' and rs.product_id = pr.id), 0)
      ) order by pr.name)
      from products pr
      left join warehouse_stock ws on ws.product_id = pr.id and ws.warehouse_id = v_wh
      where pr.company_id = w.company_id and pr.active), '[]'::jsonb),
    'expiring_batches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', pr.id, 'product_name', pr.name, 'unit', pr.unit, 'qty', b.qty,
        'expiry_date', b.expiry_date, 'supplier_name', s.name)
        order by b.expiry_date asc)
        from stock_batches b
        join products pr on pr.id = b.product_id
        left join suppliers s on s.id = b.supplier_id
       where b.warehouse_id = v_wh and b.qty > 0 and b.expiry_date is not null
         and b.expiry_date <= current_date + 30), '[]'::jsonb),
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
