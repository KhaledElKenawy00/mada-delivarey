-- =====================================================================
-- مدار (Madar) — موردين + دفعات صلاحية (FEFO) + مزامنة التعديلات القديمة
-- الميجريشن ده بيجمع تعديلين:
--  1) الفيتشر الجديد: suppliers + stock_batches + تنبيه الصلاحية + خصم FEFO.
--  2) تعديلات كانت موجودة في schema.sql بس ماكانتش راجعة للـ migration القديمة
--     (تعبئة الكرتونة على products، الصرف من غير تقييد برصيد المخزن،
--     keeper_reset_data، admin_delete_company) — فبنطبّقها هنا كمان
--     علشان الداتابيز الحقيقية تطابق الكود الحالي في lib/.
-- =====================================================================

alter table products add column if not exists carton_unit text;
alter table products add column if not exists units_per_carton numeric(12,2) not null default 1;

-- موردين: مشتركين على مستوى الشركة كلها، أي مخزن يقدر يستلم من أي مورد
create table if not exists suppliers (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  phone      text,
  address    text,
  created_at timestamptz not null default now()
);

-- دفعات الاستلام: كل استلام بضاعة بيعمل دفعة بتاريخ إنتاج/صلاحية خاص بيها،
-- علشان نقدر ننبّه قبل الانتهاء ونصرف للمناديب بالأقرب للانتهاء أولاً (FEFO).
-- qty هنا هو الباقي من الدفعة في المخزن (بينزل لما يتصرف منها للمناديب).
create table if not exists stock_batches (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  warehouse_id    uuid not null references warehouses(id) on delete cascade,
  product_id      uuid not null references products(id) on delete cascade,
  supplier_id     uuid references suppliers(id) on delete set null,
  production_date date,
  expiry_date     date,
  qty             numeric(12,2) not null default 0,
  created_at      timestamptz not null default now(),
  created_by      uuid references profiles(id)
);

-- الإصدار القديم من receive_stock باراميتر واحد بس (p_items) — نشيله الأول
-- علشان مانسيبش overload قديم يتعارض مع النسخة الجديدة (p_items + p_supplier).
drop function if exists receive_stock(jsonb);

create or replace function receive_stock(p_items jsonb, p_supplier uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare me profiles; it jsonb; v_qty numeric; v_product uuid;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  if p_supplier is not null and not exists (select 1 from suppliers where id = p_supplier and company_id = me.company_id) then
    raise exception 'BAD_SUPPLIER';
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := (it->>'qty')::numeric;
    v_product := (it->>'product_id')::uuid;
    if not exists (select 1 from products where id = v_product and company_id = me.company_id) then
      raise exception 'BAD_PRODUCT';
    end if;
    insert into warehouse_stock(warehouse_id, product_id, qty)
    values (me.warehouse_id, v_product, v_qty)
    on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty + excluded.qty;
    insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, created_by)
    values (me.company_id, me.warehouse_id, v_product, v_qty, 'receive', me.id);
    insert into stock_batches(company_id, warehouse_id, product_id, supplier_id, production_date, expiry_date, qty, created_by)
    values (me.company_id, me.warehouse_id, v_product, p_supplier,
            (it->>'production_date')::date, (it->>'expiry_date')::date, v_qty, me.id);
  end loop;
end $$;

-- إذن صرف: يفتح يوم عمل للمندوب ويحوّل البضاعة لعهدته
create or replace function create_stock_issue(p_rep uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; v_rep profiles; v_session uuid; v_issue uuid; v_no text;
  it jsonb; pr products; v_qty numeric; v_price numeric; v_total numeric := 0;
  b stock_batches; v_remaining numeric; v_take numeric;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  select * into v_rep from profiles
   where id = p_rep and role = 'rep' and warehouse_id = me.warehouse_id and active;
  if v_rep.id is null then raise exception 'REP_NOT_IN_WAREHOUSE'; end if;
  if exists (select 1 from work_sessions where rep_id = p_rep and status <> 'closed') then
    raise exception 'REP_HAS_OPEN_SESSION';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'EMPTY_ISSUE'; end if;

  insert into work_sessions(company_id, warehouse_id, rep_id)
  values (me.company_id, me.warehouse_id, p_rep) returning id into v_session;

  v_no := 'ISS-' || lpad(nextval('issue_seq')::text, 5, '0');
  insert into stock_issues(no, company_id, warehouse_id, rep_id, session_id, created_by)
  values (v_no, me.company_id, me.warehouse_id, p_rep, v_session, me.id) returning id into v_issue;

  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from products
     where id = (it->>'product_id')::uuid and company_id = me.company_id and active;
    if pr.id is null then raise exception 'BAD_PRODUCT'; end if;
    v_qty := (it->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'BAD_QTY'; end if;
    v_price := coalesce((it->>'price')::numeric, pr.price);

    -- الصرف بيتم من غير التقيد برصيد المخزن (ممكن يعدي صفر أو يفضل سالب):
    -- العهدة بتتسجل للمندوب على طول، ورصيد المخزن بيتسجل كمرجع بس.
    insert into warehouse_stock(warehouse_id, product_id, qty) values (me.warehouse_id, pr.id, -v_qty)
    on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty - v_qty;

    -- خصم من الدفعات بالأقرب للانتهاء أولاً (FEFO) علشان تنبيه الصلاحية يفضل دقيق.
    -- من غير ما يرمي خطأ لو الدفعات مش كافية — نفس فلسفة الصرف من غير تقييد.
    v_remaining := v_qty;
    for b in
      select * from stock_batches
       where warehouse_id = me.warehouse_id and product_id = pr.id and qty > 0
       order by expiry_date asc nulls last, created_at asc
       for update
    loop
      exit when v_remaining <= 0;
      v_take := least(b.qty, v_remaining);
      update stock_batches set qty = qty - v_take where id = b.id;
      v_remaining := v_remaining - v_take;
    end loop;

    insert into stock_issue_items(issue_id, product_id, qty, price) values (v_issue, pr.id, v_qty, v_price);
    insert into rep_stock(session_id, product_id, price, qty_issued) values (v_session, pr.id, v_price, v_qty);
    insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, ref_id, created_by)
    values (me.company_id, me.warehouse_id, pr.id, -v_qty, 'issue', v_issue, me.id);
    v_total := v_total + v_qty * v_price;
  end loop;

  update stock_issues set total = v_total where id = v_issue;
  return jsonb_build_object('issue_id', v_issue, 'no', v_no, 'session_id', v_session, 'total', v_total);
end $$;

-- أمين المخزن: مسح الأصناف والعملاء وكل الفواتير/العهد (مش بيلمس الحسابات ولا المخازن)
create or replace function keeper_reset_data() returns void
language plpgsql security definer set search_path = public as $$
declare me profiles; v_company uuid;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  v_company := me.company_id;

  delete from sales where company_id = v_company;
  delete from collections where company_id = v_company;
  delete from returns where company_id = v_company;
  delete from work_sessions where company_id = v_company;
  delete from stock_movements where company_id = v_company;
  delete from warehouse_stock where warehouse_id in (select id from warehouses where company_id = v_company);
  delete from stock_batches where company_id = v_company;
  delete from customers where company_id = v_company;
  delete from products where company_id = v_company;
  delete from suppliers where company_id = v_company;
end $$;

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

create or replace function company_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; c companies;
begin
  me := assert_active();
  if me.role <> 'manager' then raise exception 'ONLY_MANAGER'; end if;
  select * into c from companies where id = me.company_id;
  return jsonb_build_object(
    'company', jsonb_build_object('id', c.id, 'name', c.name, 'expires_at', c.expires_at,
                                  'max_warehouses', c.max_warehouses,
                                  'max_reps', (select coalesce(sum(max_reps), 0) from warehouses where company_id = c.id)),
    'warehouses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'name', w.name, 'address', w.address, 'max_reps', w.max_reps,
        'keeper', (select full_name from profiles where warehouse_id = w.id and role = 'keeper' limit 1),
        'reps', reps_live(w.id)) order by w.created_at)
      from warehouses w where w.company_id = c.id), '[]'::jsonb),
    'alerts', coalesce((
      select jsonb_agg(jsonb_build_object('rep', p.full_name, 'warehouse', w.name, 'diff', st.diff, 'at', st.created_at)
                       order by st.created_at desc)
        from settlements st join profiles p on p.id = st.rep_id join warehouses w on w.id = st.warehouse_id
       where st.company_id = c.id and st.diff < 0 and st.created_at > now() - interval '2 days'), '[]'::jsonb),
    'expiring', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', pr.id, 'product_name', pr.name, 'unit', pr.unit, 'qty', b.qty,
        'expiry_date', b.expiry_date, 'supplier_name', s.name, 'warehouse_name', w.name)
        order by b.expiry_date asc)
        from stock_batches b
        join products pr on pr.id = b.product_id
        join warehouses w on w.id = b.warehouse_id
        left join suppliers s on s.id = b.supplier_id
       where b.company_id = c.id and b.qty > 0 and b.expiry_date is not null
         and b.expiry_date <= current_date + 30), '[]'::jsonb)
  );
end $$;

-- حذف شركة بالكامل (بيانات + حسابات + مخازن). بترتيب يدوي صريح علشان
-- بعض الـ foreign keys (زي stock_issue_items.product_id) مش عليها
-- on delete cascade، فالاعتماد على الـ cascade التلقائي من companies لوحده
-- بيفشل بـ foreign key violation. بتستخدمها Edge Function "admin" بس
-- (service_role) بعد ما تتأكد إن اللي طالب الحذف سوبر أدمن فعلاً.
create or replace function admin_delete_company(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from sales where company_id = p_company;
  delete from collections where company_id = p_company;
  delete from returns where company_id = p_company;
  delete from work_sessions where company_id = p_company;
  delete from stock_movements where company_id = p_company;
  delete from warehouse_stock where warehouse_id in (select id from warehouses where company_id = p_company);
  delete from stock_batches where company_id = p_company;
  delete from gps_locations where company_id = p_company;
  delete from customers where company_id = p_company;
  delete from suppliers where company_id = p_company;
  delete from products where company_id = p_company;
  delete from licenses where company_id = p_company;
  delete from profiles where company_id = p_company;
  delete from warehouses where company_id = p_company;
  delete from companies where id = p_company;
end $$;
revoke execute on function admin_delete_company(uuid) from public, anon, authenticated;
grant execute on function admin_delete_company(uuid) to service_role;

alter table suppliers     enable row level security;
alter table stock_batches enable row level security;

drop policy if exists sel on suppliers;
create policy sel on suppliers for select using (company_id = my_company() or my_role() = 'super_admin');
drop policy if exists ins on suppliers;
create policy ins on suppliers for insert with check (company_id = my_company() and my_role() in ('manager', 'keeper'));
drop policy if exists upd on suppliers;
create policy upd on suppliers for update using (company_id = my_company() and my_role() in ('manager', 'keeper'));

drop policy if exists sel on stock_batches;
create policy sel on stock_batches for select using (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));
