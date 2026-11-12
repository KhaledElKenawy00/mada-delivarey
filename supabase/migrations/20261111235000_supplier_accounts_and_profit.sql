-- =====================================================================
-- مدار (Madar) — حساب الموردين (دين + دفعات) + تكلفة دقيقة لكل دفعة (FEFO)
-- + تقرير أرباح + كشف حركة صنف. بناء على migration الموردين/الصلاحية السابقة.
-- =====================================================================

create sequence if not exists receipt_seq;
create sequence if not exists payment_seq;

alter table suppliers add column if not exists balance numeric(12,2) not null default 0;

-- إذن استلام من مورد: رأس فاتورة الاستلام (إجمالي/مدفوع/آجل).
create table if not exists supplier_receipts (
  id           uuid primary key default gen_random_uuid(),
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  supplier_id  uuid references suppliers(id) on delete set null,
  total        numeric(12,2) not null default 0,
  paid         numeric(12,2) not null default 0,
  credit       numeric(12,2) not null default 0,
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

-- دفعة لمورد — بتخصم من الدين وتتسجل بتاريخها (زي collections للعملاء بالعكس)
create table if not exists supplier_payments (
  id           uuid primary key default gen_random_uuid(),
  client_uuid  uuid unique not null,
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id),
  supplier_id  uuid not null references suppliers(id),
  amount       numeric(12,2) not null check (amount > 0),
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

alter table stock_batches     add column if not exists receipt_id uuid references supplier_receipts(id) on delete set null;
alter table stock_batches     add column if not exists cost_price numeric(12,2) not null default 0;
alter table stock_issue_items add column if not exists cost_price numeric(12,2) not null default 0;
alter table rep_stock         add column if not exists cost_price numeric(12,2) not null default 0;
alter table sale_items        add column if not exists cost_price numeric(12,2) not null default 0;
alter table return_items      add column if not exists cost_price numeric(12,2) not null default 0;

-- الإصدار القديم باراميترين بس (p_items, p_supplier) — نشيله الأول علشان مانسيبش
-- overload قديم يتعارض مع النسخة الجديدة اللي ضايفة p_paid.
drop function if exists receive_stock(jsonb, uuid);

create or replace function receive_stock(p_items jsonb, p_supplier uuid default null, p_paid numeric default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; pr products; it jsonb; v_qty numeric; v_product uuid; v_cost numeric;
  v_receipt uuid; v_no text; v_total numeric := 0; v_paid numeric; v_credit numeric;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  if p_supplier is not null and not exists (select 1 from suppliers where id = p_supplier and company_id = me.company_id) then
    raise exception 'BAD_SUPPLIER';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'EMPTY_RECEIPT'; end if;

  v_no := 'REC-' || lpad(nextval('receipt_seq')::text, 5, '0');
  insert into supplier_receipts(no, company_id, warehouse_id, supplier_id, created_by)
  values (v_no, me.company_id, me.warehouse_id, p_supplier, me.id)
  returning id into v_receipt;

  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := (it->>'qty')::numeric;
    v_product := (it->>'product_id')::uuid;
    select * into pr from products where id = v_product and company_id = me.company_id;
    if pr.id is null then raise exception 'BAD_PRODUCT'; end if;
    v_cost := coalesce((it->>'cost_price')::numeric, pr.cost, 0);

    insert into warehouse_stock(warehouse_id, product_id, qty)
    values (me.warehouse_id, v_product, v_qty)
    on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty + excluded.qty;
    insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, ref_id, created_by)
    values (me.company_id, me.warehouse_id, v_product, v_qty, 'receive', v_receipt, me.id);
    insert into stock_batches(company_id, warehouse_id, product_id, supplier_id, receipt_id,
                               production_date, expiry_date, cost_price, qty, created_by)
    values (me.company_id, me.warehouse_id, v_product, p_supplier, v_receipt,
            (it->>'production_date')::date, (it->>'expiry_date')::date, v_cost, v_qty, me.id);
    v_total := v_total + v_qty * v_cost;
  end loop;

  if p_supplier is null then
    v_paid := v_total;
    v_credit := 0;
  else
    v_paid := least(greatest(coalesce(p_paid, v_total), 0), v_total);
    v_credit := v_total - v_paid;
  end if;

  update supplier_receipts set total = v_total, paid = v_paid, credit = v_credit where id = v_receipt;
  if v_credit > 0 then update suppliers set balance = balance + v_credit where id = p_supplier; end if;

  return jsonb_build_object('receipt_id', v_receipt, 'no', v_no, 'total', v_total, 'paid', v_paid, 'credit', v_credit);
end $$;

create or replace function create_stock_issue(p_rep uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; v_rep profiles; v_session uuid; v_issue uuid; v_no text;
  it jsonb; pr products; v_qty numeric; v_price numeric; v_total numeric := 0;
  b stock_batches; v_remaining numeric; v_take numeric; v_cost_sum numeric; v_unit_cost numeric;
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

    insert into warehouse_stock(warehouse_id, product_id, qty) values (me.warehouse_id, pr.id, -v_qty)
    on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty - v_qty;

    v_remaining := v_qty;
    v_cost_sum := 0;
    for b in
      select * from stock_batches
       where warehouse_id = me.warehouse_id and product_id = pr.id and qty > 0
       order by expiry_date asc nulls last, created_at asc
       for update
    loop
      exit when v_remaining <= 0;
      v_take := least(b.qty, v_remaining);
      update stock_batches set qty = qty - v_take where id = b.id;
      v_cost_sum := v_cost_sum + v_take * b.cost_price;
      v_remaining := v_remaining - v_take;
    end loop;
    if v_remaining > 0 then
      v_cost_sum := v_cost_sum + v_remaining * coalesce(pr.cost, 0);
    end if;
    v_unit_cost := case when v_qty > 0 then v_cost_sum / v_qty else 0 end;

    insert into stock_issue_items(issue_id, product_id, qty, price, cost_price) values (v_issue, pr.id, v_qty, v_price, v_unit_cost);
    insert into rep_stock(session_id, product_id, price, cost_price, qty_issued) values (v_session, pr.id, v_price, v_unit_cost, v_qty);
    insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, ref_id, created_by)
    values (me.company_id, me.warehouse_id, pr.id, -v_qty, 'issue', v_issue, me.id);
    v_total := v_total + v_qty * v_price;
  end loop;

  update stock_issues set total = v_total where id = v_issue;
  return jsonb_build_object('issue_id', v_issue, 'no', v_no, 'session_id', v_session, 'total', v_total);
end $$;

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
  delete from supplier_payments where company_id = v_company;
  delete from supplier_receipts where company_id = v_company;
  delete from customers where company_id = v_company;
  delete from products where company_id = v_company;
  delete from suppliers where company_id = v_company;
end $$;

-- دفعة لمورد: بتخصم من الدين وتتسجل بتاريخها (زي create_collection بالعكس)
create or replace function create_supplier_payment(p_client_uuid uuid, p_supplier uuid, p_amount numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me profiles; v_id uuid; v_no text;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  select id, no into v_id, v_no from supplier_payments where client_uuid = p_client_uuid;
  if v_id is not null then return jsonb_build_object('id', v_id, 'no', v_no, 'duplicate', true); end if;
  if not exists (select 1 from suppliers where id = p_supplier and company_id = me.company_id) then
    raise exception 'BAD_SUPPLIER';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'BAD_AMOUNT'; end if;
  v_no := 'PAY-' || lpad(nextval('payment_seq')::text, 6, '0');
  insert into supplier_payments(client_uuid, no, company_id, warehouse_id, supplier_id, amount, created_by)
  values (p_client_uuid, v_no, me.company_id, me.warehouse_id, p_supplier, p_amount, me.id)
  returning id into v_id;
  update suppliers set balance = balance - p_amount where id = p_supplier;
  return jsonb_build_object('id', v_id, 'no', v_no);
end $$;

create or replace function approve_settlement(p_session uuid, p_returns jsonb, p_received numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; s work_sessions; rs record; v_ret numeric; v_ret_id uuid;
  v_issued numeric; v_returned numeric; v_missing numeric;
  v_sales numeric; v_cash numeric; v_credit numeric; v_coll numeric; v_expected numeric;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  select * into s from work_sessions where id = p_session for update;
  if s.id is null or s.warehouse_id <> me.warehouse_id then raise exception 'FORBIDDEN'; end if;
  if s.status = 'closed' then raise exception 'ALREADY_CLOSED'; end if;

  insert into returns(no, company_id, warehouse_id, session_id, rep_id, approved_by)
  values ('RET-' || lpad(nextval('return_seq')::text, 5, '0'), s.company_id, s.warehouse_id, s.id, s.rep_id, me.id)
  returning id into v_ret_id;

  for rs in select * from rep_stock where session_id = s.id for update loop
    select (e->>'qty')::numeric into v_ret
      from jsonb_array_elements(coalesce(p_returns, '[]'::jsonb)) e
     where (e->>'product_id')::uuid = rs.product_id;
    v_ret := coalesce(v_ret, rs.qty_issued - rs.qty_sold);
    if v_ret < 0 or v_ret > rs.qty_issued - rs.qty_sold then raise exception 'BAD_RETURN_QTY'; end if;

    update rep_stock set qty_returned = v_ret where session_id = s.id and product_id = rs.product_id;
    if v_ret > 0 then
      insert into warehouse_stock(warehouse_id, product_id, qty) values (s.warehouse_id, rs.product_id, v_ret)
      on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty + excluded.qty;
      insert into return_items(return_id, product_id, qty, price, cost_price) values (v_ret_id, rs.product_id, v_ret, rs.price, rs.cost_price);
      insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, ref_id, created_by)
      values (s.company_id, s.warehouse_id, rs.product_id, v_ret, 'return', v_ret_id, me.id);
    end if;
  end loop;

  select coalesce(sum(qty_issued * price), 0),
         coalesce(sum(qty_returned * price), 0),
         coalesce(sum((qty_issued - qty_sold - qty_returned) * price), 0)
    into v_issued, v_returned, v_missing
    from rep_stock where session_id = s.id;
  select coalesce(sum(total), 0), coalesce(sum(paid), 0), coalesce(sum(credit), 0)
    into v_sales, v_cash, v_credit
    from sales where session_id = s.id and not voided;
  select coalesce(sum(amount), 0) into v_coll from collections where session_id = s.id;

  v_expected := v_cash + v_coll + v_missing;

  insert into settlements(session_id, company_id, warehouse_id, rep_id, issued_value, returned_value,
    missing_value, sales_value, cash_sales, credit_sales, collections, expected_cash, received_cash, diff, approved_by)
  values (s.id, s.company_id, s.warehouse_id, s.rep_id, v_issued, v_returned, v_missing, v_sales, v_cash,
    v_credit, v_coll, v_expected, p_received, p_received - v_expected, me.id);

  update work_sessions set status = 'closed', closed_at = now() where id = s.id;
  return session_json(s.id);
end $$;

create or replace function create_sale(p_client_uuid uuid, p_customer uuid, p_items jsonb, p_paid numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; s work_sessions; c customers; co companies; v_sale uuid; v_no text;
  it jsonb; rs rep_stock; v_qty numeric; v_total numeric := 0; v_paid numeric; v_credit numeric;
begin
  me := assert_active();
  if me.role <> 'rep' then raise exception 'ONLY_REP'; end if;

  select id, no into v_sale, v_no from sales where client_uuid = p_client_uuid;
  if v_sale is not null then
    return jsonb_build_object('sale_id', v_sale, 'no', v_no, 'duplicate', true);
  end if;

  select * into s from work_sessions where rep_id = me.id and status = 'open';
  if s.id is null then raise exception 'NO_OPEN_SESSION'; end if;
  select * into c from customers where id = p_customer and company_id = me.company_id;
  if c.id is null then raise exception 'BAD_CUSTOMER'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'EMPTY_SALE'; end if;

  v_no := 'INV-' || lpad(nextval('sale_seq')::text, 6, '0');
  insert into sales(client_uuid, no, company_id, warehouse_id, session_id, rep_id, customer_id)
  values (p_client_uuid, v_no, me.company_id, s.warehouse_id, s.id, me.id, c.id)
  returning id into v_sale;

  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := (it->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'BAD_QTY'; end if;
    select * into rs from rep_stock
     where session_id = s.id and product_id = (it->>'product_id')::uuid for update;
    if rs.session_id is null then raise exception 'NOT_IN_CUSTODY'; end if;
    if v_qty > rs.qty_issued - rs.qty_sold - rs.qty_returned then
      raise exception 'EXCEEDS_CUSTODY:%', (select name from products where id = rs.product_id);
    end if;
    update rep_stock set qty_sold = qty_sold + v_qty
     where session_id = s.id and product_id = rs.product_id;
    insert into sale_items(sale_id, product_id, qty, price, cost_price) values (v_sale, rs.product_id, v_qty, rs.price, rs.cost_price);
    v_total := v_total + v_qty * rs.price;
  end loop;

  v_paid := least(greatest(coalesce(p_paid, v_total), 0), v_total);
  v_credit := v_total - v_paid;
  select * into co from companies where id = me.company_id;
  if v_credit > 0 and not co.allow_credit then raise exception 'CREDIT_NOT_ALLOWED'; end if;

  update sales set total = v_total, paid = v_paid, credit = v_credit where id = v_sale;
  if v_credit > 0 then update customers set balance = balance + v_credit where id = c.id; end if;

  return jsonb_build_object('sale_id', v_sale, 'no', v_no, 'total', v_total, 'paid', v_paid, 'credit', v_credit);
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
        'product_id', pr.id, 'name', pr.name, 'unit', pr.unit, 'price', rs.price, 'cost_price', rs.cost_price,
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

-- تقرير أرباح لفترة: سعر البيع - سعر التكلفة الحقيقي (FEFO، من sale_items.cost_price).
create or replace function profit_report(p_from date, p_to date, p_warehouse uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; v_wh uuid;
begin
  me := assert_active();
  if me.role not in ('keeper', 'manager', 'super_admin') then raise exception 'FORBIDDEN'; end if;
  if me.role = 'keeper' then
    v_wh := me.warehouse_id;
  elsif p_warehouse is not null then
    if not exists (select 1 from warehouses where id = p_warehouse and (me.role = 'super_admin' or company_id = me.company_id)) then
      raise exception 'FORBIDDEN';
    end if;
    v_wh := p_warehouse;
  end if;

  return jsonb_build_object(
    'from', p_from, 'to', p_to,
    'revenue', coalesce((
      select sum(si.qty * si.price) from sale_items si join sales sa on sa.id = si.sale_id
       where not sa.voided and local_date(sa.created_at) between p_from and p_to
         and (me.role = 'super_admin' or sa.company_id = me.company_id)
         and (v_wh is null or sa.warehouse_id = v_wh)), 0),
    'cost', coalesce((
      select sum(si.qty * si.cost_price) from sale_items si join sales sa on sa.id = si.sale_id
       where not sa.voided and local_date(sa.created_at) between p_from and p_to
         and (me.role = 'super_admin' or sa.company_id = me.company_id)
         and (v_wh is null or sa.warehouse_id = v_wh)), 0),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('day', a.d, 'revenue', a.rev, 'cost', a.cst, 'profit', a.rev - a.cst) order by a.d)
        from (select local_date(sa.created_at) d, sum(si.qty * si.price) rev, sum(si.qty * si.cost_price) cst
                from sale_items si join sales sa on sa.id = si.sale_id
               where not sa.voided and local_date(sa.created_at) between p_from and p_to
                 and (me.role = 'super_admin' or sa.company_id = me.company_id)
                 and (v_wh is null or sa.warehouse_id = v_wh)
               group by 1) a), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('name', pr.name, 'qty', a.q, 'revenue', a.rev, 'cost', a.cst, 'profit', a.rev - a.cst)
                       order by (a.rev - a.cst) desc)
        from (select si.product_id, sum(si.qty) q, sum(si.qty * si.price) rev, sum(si.qty * si.cost_price) cst
                from sale_items si join sales sa on sa.id = si.sale_id
               where not sa.voided and local_date(sa.created_at) between p_from and p_to
                 and (me.role = 'super_admin' or sa.company_id = me.company_id)
                 and (v_wh is null or sa.warehouse_id = v_wh)
               group by si.product_id) a
        join products pr on pr.id = a.product_id), '[]'::jsonb)
  );
end $$;

-- كشف حركة صنف واحد من البداية: استلام (من أي مورد) + صرف للمناديب + مرتجع + بيع فعلي للعميل.
create or replace function product_movements(p_product uuid, p_from date, p_to date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; pr products; v_wh uuid;
begin
  me := assert_active();
  if me.role not in ('keeper', 'manager', 'super_admin') then raise exception 'FORBIDDEN'; end if;
  select * into pr from products where id = p_product;
  if pr.id is null then raise exception 'NOT_FOUND'; end if;
  if not (me.role = 'super_admin' or pr.company_id = me.company_id) then raise exception 'FORBIDDEN'; end if;
  if me.role = 'keeper' then v_wh := me.warehouse_id; end if;

  return jsonb_build_object(
    'product', jsonb_build_object('id', pr.id, 'name', pr.name, 'unit', pr.unit, 'price', pr.price, 'cost', pr.cost),
    'from', p_from, 'to', p_to,
    'in_stock', coalesce((select sum(qty) from warehouse_stock where product_id = pr.id and (v_wh is null or warehouse_id = v_wh)), 0),
    'received', coalesce((select sum(qty_change) from stock_movements
                 where product_id = pr.id and kind = 'receive' and local_date(created_at) between p_from and p_to
                   and (v_wh is null or warehouse_id = v_wh)), 0),
    'issued', coalesce((select sum(-qty_change) from stock_movements
                 where product_id = pr.id and kind = 'issue' and local_date(created_at) between p_from and p_to
                   and (v_wh is null or warehouse_id = v_wh)), 0),
    'returned', coalesce((select sum(qty_change) from stock_movements
                 where product_id = pr.id and kind = 'return' and local_date(created_at) between p_from and p_to
                   and (v_wh is null or warehouse_id = v_wh)), 0),
    'sold', coalesce((select sum(si.qty) from sale_items si join sales sa on sa.id = si.sale_id
                 where si.product_id = pr.id and not sa.voided and local_date(sa.created_at) between p_from and p_to
                   and (v_wh is null or sa.warehouse_id = v_wh)), 0),
    'movements', coalesce((
      select jsonb_agg(f order by f->>'at' desc) from (
        select f from (
          select jsonb_build_object('kind', m.kind, 'at', m.created_at, 'qty', m.qty_change,
                 'title', case m.kind
                   when 'receive' then coalesce((select s.name from supplier_receipts r join suppliers s on s.id = r.supplier_id where r.id = m.ref_id), 'استلام')
                   when 'issue' then coalesce((select p2.full_name from stock_issues i join profiles p2 on p2.id = i.rep_id where i.id = m.ref_id), 'صرف')
                   when 'return' then coalesce((select p2.full_name from returns rt join profiles p2 on p2.id = rt.rep_id where rt.id = m.ref_id), 'مرتجع')
                   else m.kind end) f
            from stock_movements m
           where m.product_id = pr.id and local_date(m.created_at) between p_from and p_to
             and (v_wh is null or m.warehouse_id = v_wh)
          union all
          select jsonb_build_object('kind', 'sale', 'at', sa.created_at, 'qty', -si.qty,
                 'title', c.name, 'price', si.price, 'cost_price', si.cost_price) f
            from sale_items si join sales sa on sa.id = si.sale_id join customers c on c.id = sa.customer_id
           where si.product_id = pr.id and not sa.voided and local_date(sa.created_at) between p_from and p_to
             and (v_wh is null or sa.warehouse_id = v_wh)
        ) u order by f->>'at' desc limit 300
      ) t), '[]'::jsonb)
  );
end $$;

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
  delete from supplier_payments where company_id = p_company;
  delete from supplier_receipts where company_id = p_company;
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

alter table supplier_receipts enable row level security;
alter table supplier_payments enable row level security;

drop policy if exists sel on supplier_receipts;
create policy sel on supplier_receipts for select using (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));

drop policy if exists sel on supplier_payments;
create policy sel on supplier_payments for select using (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));
