-- =====================================================================
-- مدار (Madar) — Van Sales Management System
-- Supabase / PostgreSQL schema: tables, RLS, business RPCs, reports
-- شغّل الملف ده كله مرة واحدة من Supabase Dashboard › SQL Editor
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('super_admin', 'manager', 'keeper', 'rep');
exception when duplicate_object then null; end $$;

do $$ begin
  create type session_status as enum ('open', 'pending', 'closed');
exception when duplicate_object then null; end $$;

create sequence if not exists issue_seq;
create sequence if not exists sale_seq;
create sequence if not exists collection_seq;
create sequence if not exists return_seq;
create sequence if not exists company_seq;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table if not exists companies (
  id             uuid primary key default gen_random_uuid(),
  code           text unique not null,
  name           text not null,
  manager_name   text,
  active         boolean not null default true,
  expires_at     timestamptz not null,
  max_warehouses int not null default 1,
  allow_credit   boolean not null default true,
  created_at     timestamptz not null default now()
);

create table if not exists warehouses (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  address    text,
  max_reps   int not null default 5,
  lat        double precision,
  lng        double precision,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  company_id   uuid references companies(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete set null,
  role         user_role not null,
  full_name    text not null,
  phone        text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- ترخيص واحد لكل حساب، ويتربط بجهاز واحد (fingerprint) أول مرة
create table if not exists licenses (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid references companies(id) on delete cascade,
  profile_id    uuid unique not null references profiles(id) on delete cascade,
  license_key   text unique not null,
  fingerprint   text,
  device_serial text,
  device_name   text,
  platform      text,
  activated_at  timestamptz,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists products (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  code       text not null,
  name       text not null,
  unit       text not null default 'كرتونة',
  price      numeric(12,2) not null default 0,
  cost       numeric(12,2),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code)
);

create table if not exists warehouse_stock (
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  product_id   uuid not null references products(id) on delete cascade,
  qty          numeric(12,2) not null default 0,
  primary key (warehouse_id, product_id)
);

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

create table if not exists customers (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete set null,
  rep_id       uuid references profiles(id) on delete set null,
  code         text,
  name         text not null,
  phone        text,
  address      text,
  area         text,
  lat          double precision,
  lng          double precision,
  credit_limit numeric(12,2) not null default 0,
  balance      numeric(12,2) not null default 0,  -- موجب = على العميل
  created_at   timestamptz not null default now()
);

create table if not exists work_sessions (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  rep_id       uuid not null references profiles(id) on delete cascade,
  status       session_status not null default 'open',
  started_at   timestamptz not null default now(),
  submitted_at timestamptz,
  closed_at    timestamptz
);
-- مندوب واحد = يوم مفتوح واحد بس
create unique index if not exists one_open_session_per_rep
  on work_sessions(rep_id) where status <> 'closed';

create table if not exists stock_issues (
  id           uuid primary key default gen_random_uuid(),
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  rep_id       uuid not null references profiles(id),
  session_id   uuid not null references work_sessions(id) on delete cascade,
  created_by   uuid not null references profiles(id),
  total        numeric(12,2) not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists stock_issue_items (
  id         uuid primary key default gen_random_uuid(),
  issue_id   uuid not null references stock_issues(id) on delete cascade,
  product_id uuid not null references products(id),
  qty        numeric(12,2) not null check (qty > 0),
  price      numeric(12,2) not null
);

-- عهدة المندوب في اليوم
create table if not exists rep_stock (
  session_id   uuid not null references work_sessions(id) on delete cascade,
  product_id   uuid not null references products(id),
  price        numeric(12,2) not null,
  qty_issued   numeric(12,2) not null default 0,
  qty_sold     numeric(12,2) not null default 0,
  qty_returned numeric(12,2) not null default 0,
  primary key (session_id, product_id),
  check (qty_sold + qty_returned <= qty_issued)
);

create table if not exists sales (
  id           uuid primary key default gen_random_uuid(),
  client_uuid  uuid unique not null,          -- يمنع تكرار الفاتورة عند الرفع بعد الأوفلاين
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id),
  session_id   uuid not null references work_sessions(id),
  rep_id       uuid not null references profiles(id),
  customer_id  uuid not null references customers(id),
  total        numeric(12,2) not null default 0,
  paid         numeric(12,2) not null default 0,
  credit       numeric(12,2) not null default 0,
  voided       boolean not null default false,
  created_at   timestamptz not null default now()
);

create table if not exists sale_items (
  id         uuid primary key default gen_random_uuid(),
  sale_id    uuid not null references sales(id) on delete cascade,
  product_id uuid not null references products(id),
  qty        numeric(12,2) not null check (qty > 0),
  price      numeric(12,2) not null
);

create table if not exists collections (
  id           uuid primary key default gen_random_uuid(),
  client_uuid  uuid unique not null,
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id),
  session_id   uuid not null references work_sessions(id),
  rep_id       uuid not null references profiles(id),
  customer_id  uuid not null references customers(id),
  amount       numeric(12,2) not null check (amount > 0),
  created_at   timestamptz not null default now()
);

create table if not exists returns (
  id           uuid primary key default gen_random_uuid(),
  no           text unique not null,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id),
  session_id   uuid not null references work_sessions(id),
  rep_id       uuid not null references profiles(id),
  approved_by  uuid not null references profiles(id),
  created_at   timestamptz not null default now()
);

create table if not exists return_items (
  id         uuid primary key default gen_random_uuid(),
  return_id  uuid not null references returns(id) on delete cascade,
  product_id uuid not null references products(id),
  qty        numeric(12,2) not null,
  price      numeric(12,2) not null
);

create table if not exists settlements (
  session_id     uuid primary key references work_sessions(id) on delete cascade,
  company_id     uuid not null references companies(id) on delete cascade,
  warehouse_id   uuid not null references warehouses(id),
  rep_id         uuid not null references profiles(id),
  issued_value   numeric(12,2) not null,
  returned_value numeric(12,2) not null,
  missing_value  numeric(12,2) not null,
  sales_value    numeric(12,2) not null,
  cash_sales     numeric(12,2) not null,
  credit_sales   numeric(12,2) not null,
  collections    numeric(12,2) not null,
  expected_cash  numeric(12,2) not null,
  received_cash  numeric(12,2) not null,
  diff           numeric(12,2) not null,  -- سالب = عجز
  approved_by    uuid not null references profiles(id),
  created_at     timestamptz not null default now()
);

create table if not exists gps_locations (
  id          bigserial primary key,
  company_id  uuid not null references companies(id) on delete cascade,
  rep_id      uuid not null references profiles(id) on delete cascade,
  session_id  uuid references work_sessions(id) on delete set null,
  lat         double precision not null,
  lng         double precision not null,
  accuracy    double precision,
  speed       double precision,
  recorded_at timestamptz not null default now()
);
create index if not exists gps_rep_time on gps_locations(rep_id, recorded_at desc);

-- سجل حركات مستقل لأي تغيير في المخزون
create table if not exists stock_movements (
  id           bigserial primary key,
  company_id   uuid not null references companies(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id),
  product_id   uuid not null references products(id),
  qty_change   numeric(12,2) not null,
  kind         text not null,   -- receive | issue | return | adjust
  ref_id       uuid,
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------
create or replace function local_date(ts timestamptz) returns date
language sql immutable as $$ select (ts at time zone 'Africa/Cairo')::date $$;

create or replace function my_role() returns user_role
language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() $$;

create or replace function my_company() returns uuid
language sql stable security definer set search_path = public as
$$ select company_id from profiles where id = auth.uid() $$;

create or replace function my_warehouse() returns uuid
language sql stable security definer set search_path = public as
$$ select warehouse_id from profiles where id = auth.uid() $$;

create or replace function gen_license_key() returns text
language plpgsql volatile as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  k text;
  i int;
begin
  loop
    k := 'MDR';
    for i in 1..3 loop
      k := k || '-' ||
        substr(alphabet, 1 + floor(random() * 32)::int, 1) ||
        substr(alphabet, 1 + floor(random() * 32)::int, 1) ||
        substr(alphabet, 1 + floor(random() * 32)::int, 1) ||
        substr(alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from licenses where license_key = k);
  end loop;
  return k;
end $$;

-- بيرمي exception لو المستخدم/الشركة/الترخيص موقوف أو منتهي
create or replace function assert_active() returns profiles
language plpgsql stable security definer set search_path = public as $$
declare
  p profiles;
  c companies;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then raise exception 'NO_PROFILE'; end if;
  if not p.active then raise exception 'USER_SUSPENDED'; end if;
  if p.role <> 'super_admin' then
    select * into c from companies where id = p.company_id;
    if c.id is null or not c.active then raise exception 'COMPANY_SUSPENDED'; end if;
    if c.expires_at < now() then raise exception 'LICENSE_EXPIRED'; end if;
  end if;
  if not exists (select 1 from licenses l
                 where l.profile_id = p.id and l.active and l.fingerprint is not null) then
    raise exception 'LICENSE_INACTIVE';
  end if;
  return p;
end $$;

create or replace function assert_super() returns profiles
language plpgsql stable security definer set search_path = public as $$
declare p profiles;
begin
  p := assert_active();
  if p.role <> 'super_admin' then raise exception 'FORBIDDEN'; end if;
  return p;
end $$;

-- إجماليات يوم مندوب
create or replace function session_totals(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'issued',      coalesce((select sum(qty_issued * price) from rep_stock where session_id = p_session), 0),
    'sold',        coalesce((select sum(total)  from sales where session_id = p_session and not voided), 0),
    'cash',        coalesce((select sum(paid)   from sales where session_id = p_session and not voided), 0),
    'credit',      coalesce((select sum(credit) from sales where session_id = p_session and not voided), 0),
    'collections', coalesce((select sum(amount) from collections where session_id = p_session), 0),
    'returned',    coalesce((select sum(qty_returned * price) from rep_stock where session_id = p_session), 0),
    'remaining',   coalesce((select sum((qty_issued - qty_sold - qty_returned) * price) from rep_stock where session_id = p_session), 0),
    'invoices',    (select count(*) from sales where session_id = p_session and not voided)
  )
$$;

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
        'issued', rs.qty_issued, 'sold', rs.qty_sold, 'returned', rs.qty_returned
      ) order by pr.name)
      from rep_stock rs join products pr on pr.id = rs.product_id
      where rs.session_id = s.id), '[]'::jsonb),
    'settlement', (select to_jsonb(st) from settlements st where st.session_id = s.id)
  )
  from work_sessions s join profiles p on p.id = s.rep_id
  where s.id = p_session
$$;

-- حالة كل مندوب في مخزن (لوحة الأمين + المدير)
create or replace function reps_live(p_wh uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'sold')::numeric desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'name', p.full_name, 'phone', p.phone, 'device', l.device_name,
      'user_active', p.active,
      'session_id', s.id, 'session_status', s.status, 'started_at', s.started_at,
      'last_seen', g.recorded_at, 'lat', g.lat, 'lng', g.lng,
      'status', case
        when s.id is null then 'idle'
        when s.status = 'closed' then 'done'
        when s.status = 'pending' then 'pending'
        when g.recorded_at is null or g.recorded_at < now() - interval '10 minutes' then 'lost'
        when coalesce(g.speed, 0) < 0.5 then 'stopped'
        else 'moving' end
    ) || session_totals(s.id) as x
    from profiles p
    left join licenses l on l.profile_id = p.id
    left join lateral (
      select * from work_sessions ws
      where ws.rep_id = p.id
        and (ws.status <> 'closed' or local_date(ws.started_at) = local_date(now()))
      order by ws.started_at desc limit 1) s on true
    left join lateral (
      select * from gps_locations gl where gl.rep_id = p.id
      order by gl.recorded_at desc limit 1) g on true
    where p.warehouse_id = p_wh and p.role = 'rep'
  ) t
$$;

revoke execute on function session_totals(uuid) from public, anon, authenticated;
revoke execute on function session_json(uuid)   from public, anon, authenticated;
revoke execute on function reps_live(uuid)      from public, anon, authenticated;
revoke execute on function gen_license_key()    from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- License check (التطبيق بيناديها كل ما يفتح وكل 10 دقايق)
-- ---------------------------------------------------------------------
create or replace function check_license(p_fingerprint text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p profiles; c companies; l licenses; w warehouses;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then return jsonb_build_object('ok', false, 'reason', 'NO_PROFILE'); end if;
  select * into l from licenses where profile_id = p.id;
  if l.id is null then return jsonb_build_object('ok', false, 'reason', 'NO_LICENSE'); end if;
  if l.fingerprint is null then return jsonb_build_object('ok', false, 'reason', 'UNBOUND'); end if;
  if l.fingerprint <> p_fingerprint then return jsonb_build_object('ok', false, 'reason', 'OTHER_DEVICE'); end if;
  if not l.active then return jsonb_build_object('ok', false, 'reason', 'LICENSE_SUSPENDED'); end if;
  if not p.active then return jsonb_build_object('ok', false, 'reason', 'USER_SUSPENDED'); end if;
  if p.role <> 'super_admin' then
    select * into c from companies where id = p.company_id;
    if not c.active then return jsonb_build_object('ok', false, 'reason', 'COMPANY_SUSPENDED'); end if;
    if c.expires_at < now() then return jsonb_build_object('ok', false, 'reason', 'LICENSE_EXPIRED'); end if;
  end if;
  select * into w from warehouses where id = p.warehouse_id;
  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object(
      'id', p.id, 'role', p.role, 'full_name', p.full_name,
      'company_id', p.company_id, 'company_name', c.name, 'expires_at', c.expires_at,
      'allow_credit', coalesce(c.allow_credit, true),
      'warehouse_id', p.warehouse_id, 'warehouse_name', w.name,
      'license_key', l.license_key, 'device_name', l.device_name));
end $$;

-- ---------------------------------------------------------------------
-- Keeper RPCs
-- ---------------------------------------------------------------------
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
  it jsonb; pr products; v_stock numeric; v_qty numeric; v_price numeric; v_total numeric := 0;
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

    select qty into v_stock from warehouse_stock
     where warehouse_id = me.warehouse_id and product_id = pr.id for update;
    if coalesce(v_stock, 0) < v_qty then raise exception 'INSUFFICIENT_STOCK:%', pr.name; end if;

    update warehouse_stock set qty = qty - v_qty
     where warehouse_id = me.warehouse_id and product_id = pr.id;

    -- خصم من الدفعات بالأقرب للانتهاء أولاً (FEFO) علشان تنبيه الصلاحية يفضل دقيق.
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

create or replace function settlement_data(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; s work_sessions;
begin
  me := assert_active();
  select * into s from work_sessions where id = p_session;
  if s.id is null then raise exception 'NOT_FOUND'; end if;
  if not (
    (me.role = 'keeper'  and s.warehouse_id = me.warehouse_id) or
    (me.role = 'manager' and s.company_id = me.company_id) or
    (me.role = 'rep'     and s.rep_id = me.id) or
    me.role = 'super_admin') then
    raise exception 'FORBIDDEN';
  end if;
  return session_json(p_session);
end $$;

-- تسوية العهدة: مرتجع فعلي + نقدية مستلمة → يقفل يوم المندوب
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
      insert into return_items(return_id, product_id, qty, price) values (v_ret_id, rs.product_id, v_ret, rs.price);
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

  -- البضاعة الناقصة بتتحسب على المندوب بسعر البيع
  v_expected := v_cash + v_coll + v_missing;

  insert into settlements(session_id, company_id, warehouse_id, rep_id, issued_value, returned_value,
    missing_value, sales_value, cash_sales, credit_sales, collections, expected_cash, received_cash, diff, approved_by)
  values (s.id, s.company_id, s.warehouse_id, s.rep_id, v_issued, v_returned, v_missing, v_sales, v_cash,
    v_credit, v_coll, v_expected, p_received, p_received - v_expected, me.id);

  update work_sessions set status = 'closed', closed_at = now() where id = s.id;
  return session_json(s.id);
end $$;

-- ---------------------------------------------------------------------
-- Rep RPCs
-- ---------------------------------------------------------------------
create or replace function my_custody() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; v_session uuid;
begin
  me := assert_active();
  if me.role <> 'rep' then raise exception 'ONLY_REP'; end if;
  select id into v_session from work_sessions
   where rep_id = me.id and status <> 'closed' order by started_at desc limit 1;
  if v_session is null then return null; end if;
  return session_json(v_session);
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
    insert into sale_items(sale_id, product_id, qty, price) values (v_sale, rs.product_id, v_qty, rs.price);
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

create or replace function create_collection(p_client_uuid uuid, p_customer uuid, p_amount numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me profiles; s work_sessions; v_id uuid; v_no text;
begin
  me := assert_active();
  if me.role <> 'rep' then raise exception 'ONLY_REP'; end if;
  select id, no into v_id, v_no from collections where client_uuid = p_client_uuid;
  if v_id is not null then return jsonb_build_object('id', v_id, 'no', v_no, 'duplicate', true); end if;
  select * into s from work_sessions where rep_id = me.id and status = 'open';
  if s.id is null then raise exception 'NO_OPEN_SESSION'; end if;
  if not exists (select 1 from customers where id = p_customer and company_id = me.company_id) then
    raise exception 'BAD_CUSTOMER';
  end if;
  v_no := 'COL-' || lpad(nextval('collection_seq')::text, 6, '0');
  insert into collections(client_uuid, no, company_id, warehouse_id, session_id, rep_id, customer_id, amount)
  values (p_client_uuid, v_no, me.company_id, s.warehouse_id, s.id, me.id, p_customer, p_amount)
  returning id into v_id;
  update customers set balance = balance - p_amount where id = p_customer;
  return jsonb_build_object('id', v_id, 'no', v_no);
end $$;

create or replace function submit_day_end() returns void
language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := assert_active();
  if me.role <> 'rep' then raise exception 'ONLY_REP'; end if;
  update work_sessions set status = 'pending', submitted_at = now()
   where rep_id = me.id and status = 'open';
end $$;

-- ---------------------------------------------------------------------
-- Warehouse / company views (keeper + manager)
-- ---------------------------------------------------------------------
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

-- تقرير مندوب لفترة (يومي = نفس اليوم، شهري = أول الشهر لآخره)
create or replace function rep_report(p_rep uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me profiles; r profiles;
begin
  me := assert_active();
  select * into r from profiles where id = p_rep and role = 'rep';
  if r.id is null then raise exception 'NOT_FOUND'; end if;
  if not (
    me.id = r.id or
    (me.role = 'keeper'  and me.warehouse_id = r.warehouse_id) or
    (me.role = 'manager' and me.company_id = r.company_id) or
    me.role = 'super_admin') then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'rep', jsonb_build_object('id', r.id, 'name', r.full_name,
           'warehouse', (select name from warehouses where id = r.warehouse_id),
           'device', (select device_name from licenses where profile_id = r.id)),
    'from', p_from, 'to', p_to,
    'sales',   coalesce((select sum(total)  from sales where rep_id = r.id and not voided and local_date(created_at) between p_from and p_to), 0),
    'cash',    coalesce((select sum(paid)   from sales where rep_id = r.id and not voided and local_date(created_at) between p_from and p_to), 0),
    'credit',  coalesce((select sum(credit) from sales where rep_id = r.id and not voided and local_date(created_at) between p_from and p_to), 0),
    'invoices', (select count(*) from sales where rep_id = r.id and not voided and local_date(created_at) between p_from and p_to),
    'collections', coalesce((select sum(amount) from collections where rep_id = r.id and local_date(created_at) between p_from and p_to), 0),
    'returned', coalesce((select sum(rs.qty_returned * rs.price) from rep_stock rs join work_sessions s on s.id = rs.session_id
                           where s.rep_id = r.id and local_date(s.started_at) between p_from and p_to), 0),
    'deficit', coalesce((select sum(least(st.diff, 0)) from settlements st join work_sessions s on s.id = st.session_id
                          where s.rep_id = r.id and local_date(s.started_at) between p_from and p_to), 0),
    'days_worked', (select count(distinct local_date(started_at)) from work_sessions
                     where rep_id = r.id and local_date(started_at) between p_from and p_to),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('name', pr.name, 'issued', a.i, 'sold', a.s, 'returned', a.r, 'value', a.v) order by a.v desc)
        from (select rs.product_id, sum(rs.qty_issued) i, sum(rs.qty_sold) s, sum(rs.qty_returned) r, sum(rs.qty_sold * rs.price) v
                from rep_stock rs join work_sessions s on s.id = rs.session_id
               where s.rep_id = r.id and local_date(s.started_at) between p_from and p_to
               group by rs.product_id) a
        join products pr on pr.id = a.product_id), '[]'::jsonb),
    'invoices_list', coalesce((
      select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('no', sa.no, 'at', sa.created_at, 'customer', c.name,
                                  'total', sa.total, 'paid', sa.paid, 'credit', sa.credit) x
          from sales sa join customers c on c.id = sa.customer_id
         where sa.rep_id = r.id and not sa.voided and local_date(sa.created_at) between p_from and p_to
         order by sa.created_at desc limit 100) t), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('day', a.d, 'sales', a.v, 'deficit', coalesce(b.x, 0)) order by a.d)
        from (select local_date(created_at) d, sum(total) v from sales
               where rep_id = r.id and not voided and local_date(created_at) between p_from and p_to group by 1) a
        left join (select local_date(s.started_at) d2, sum(least(st.diff, 0)) x
                     from settlements st join work_sessions s on s.id = st.session_id
                    where s.rep_id = r.id group by 1) b on b.d2 = a.d), '[]'::jsonb),
    'top_customers', coalesce((
      select jsonb_agg(jsonb_build_object('name', t.name, 'total', t.tot, 'balance', t.balance) order by t.tot desc)
        from (select c.name, c.balance, sum(sa.total) tot from sales sa join customers c on c.id = sa.customer_id
               where sa.rep_id = r.id and not sa.voided and local_date(sa.created_at) between p_from and p_to
               group by c.id, c.name, c.balance order by tot desc limit 5) t), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------
-- Super admin RPCs (إنشاء الحسابات نفسها في Edge Function "admin")
-- ---------------------------------------------------------------------
create or replace function admin_companies() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_super();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'code', c.code, 'name', c.name, 'manager_name', c.manager_name,
      'active', c.active, 'expires_at', c.expires_at, 'created_at', c.created_at,
      'max_warehouses', c.max_warehouses,
      'warehouses', (select count(*) from warehouses where company_id = c.id),
      'max_reps', (select coalesce(sum(max_reps), 0) from warehouses where company_id = c.id),
      'reps', (select count(*) from profiles where company_id = c.id and role = 'rep'),
      'devices_total', (select count(*) from licenses where company_id = c.id),
      'devices_active', (select count(*) from licenses where company_id = c.id and fingerprint is not null and active)
    ) order by c.created_at desc) from companies c), '[]'::jsonb);
end $$;

create or replace function admin_company_licenses(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c companies;
begin
  perform assert_super();
  select * into c from companies where id = p_company;
  if c.id is null then raise exception 'NOT_FOUND'; end if;
  return jsonb_build_object(
    'company', to_jsonb(c),
    'warehouses', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'max_reps', max_reps) order by created_at)
                              from warehouses where company_id = c.id), '[]'::jsonb),
    'licenses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'profile_id', p.id, 'name', p.full_name, 'phone', p.phone, 'role', p.role,
        'warehouse', w.name, 'license_key', l.license_key, 'device_name', l.device_name,
        'device_serial', l.device_serial, 'platform', l.platform, 'activated_at', l.activated_at,
        'bound', l.fingerprint is not null, 'active', l.active and p.active)
        order by case p.role when 'manager' then 0 when 'keeper' then 1 else 2 end, w.name, p.full_name)
      from licenses l join profiles p on p.id = l.profile_id left join warehouses w on w.id = p.warehouse_id
      where l.company_id = c.id), '[]'::jsonb));
end $$;

create or replace function admin_set_company_active(p_company uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_super();
  update companies set active = p_active where id = p_company;
end $$;

create or replace function admin_extend_company(p_company uuid, p_interval interval) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v timestamptz;
begin
  perform assert_super();
  update companies set expires_at = greatest(expires_at, now()) + p_interval
   where id = p_company returning expires_at into v;
  return v;
end $$;

create or replace function admin_set_license_active(p_license uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_super();
  update licenses set active = p_active where id = p_license;
  update profiles set active = p_active where id = (select profile_id from licenses where id = p_license);
end $$;

-- فك الربط: المفتاح يتفعل على جهاز جديد، والجهاز القديم بيتقفل في أول check_license
create or replace function admin_unbind_license(p_license uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_super();
  update licenses set fingerprint = null, device_serial = null, device_name = null,
                      platform = null, activated_at = null
   where id = p_license;
end $$;

create or replace function admin_regenerate_key(p_license uuid) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  perform assert_super();
  k := gen_license_key();
  update licenses set license_key = k, fingerprint = null, device_serial = null,
                      device_name = null, platform = null, activated_at = null
   where id = p_license;
  return k;
end $$;

create or replace function admin_update_profile(p_profile uuid, p_name text, p_phone text) returns void
language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := assert_active();
  if not (me.role = 'super_admin' or
          (me.role = 'manager' and exists (select 1 from profiles where id = p_profile and company_id = me.company_id))) then
    raise exception 'FORBIDDEN';
  end if;
  update profiles set full_name = p_name, phone = p_phone where id = p_profile;
end $$;

-- ---------------------------------------------------------------------
-- Row Level Security (القراءة المباشرة — الكتابة كلها من خلال الـ RPCs)
-- ---------------------------------------------------------------------
alter table companies         enable row level security;
alter table warehouses        enable row level security;
alter table profiles          enable row level security;
alter table licenses          enable row level security;
alter table products          enable row level security;
alter table warehouse_stock   enable row level security;
alter table suppliers         enable row level security;
alter table stock_batches     enable row level security;
alter table customers         enable row level security;
alter table work_sessions     enable row level security;
alter table stock_issues      enable row level security;
alter table stock_issue_items enable row level security;
alter table rep_stock         enable row level security;
alter table sales             enable row level security;
alter table sale_items        enable row level security;
alter table collections       enable row level security;
alter table returns           enable row level security;
alter table return_items      enable row level security;
alter table settlements       enable row level security;
alter table gps_locations     enable row level security;
alter table stock_movements   enable row level security;

drop policy if exists sel on companies;
create policy sel on companies for select using (my_role() = 'super_admin' or id = my_company());

drop policy if exists sel on warehouses;
create policy sel on warehouses for select using (my_role() = 'super_admin' or company_id = my_company());

drop policy if exists sel on profiles;
create policy sel on profiles for select using (
  id = auth.uid() or my_role() = 'super_admin' or
  (company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse())));

drop policy if exists sel on licenses;
create policy sel on licenses for select using (profile_id = auth.uid() or my_role() = 'super_admin');

drop policy if exists sel on products;
create policy sel on products for select using (company_id = my_company() or my_role() = 'super_admin');
drop policy if exists ins on products;
create policy ins on products for insert with check (company_id = my_company() and my_role() in ('manager', 'keeper'));
drop policy if exists upd on products;
create policy upd on products for update using (company_id = my_company() and my_role() in ('manager', 'keeper'));

drop policy if exists sel on warehouse_stock;
create policy sel on warehouse_stock for select using (
  exists (select 1 from warehouses w where w.id = warehouse_id and w.company_id = my_company()));

drop policy if exists sel on suppliers;
create policy sel on suppliers for select using (company_id = my_company() or my_role() = 'super_admin');
drop policy if exists ins on suppliers;
create policy ins on suppliers for insert with check (company_id = my_company() and my_role() in ('manager', 'keeper'));
drop policy if exists upd on suppliers;
create policy upd on suppliers for update using (company_id = my_company() and my_role() in ('manager', 'keeper'));

drop policy if exists sel on stock_batches;
create policy sel on stock_batches for select using (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));

drop policy if exists sel on customers;
create policy sel on customers for select using (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));
drop policy if exists ins on customers;
create policy ins on customers for insert with check (
  company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()));
drop policy if exists upd on customers;
create policy upd on customers for update using (
  company_id = my_company() and my_role() in ('manager', 'keeper')
  and (my_role() = 'manager' or warehouse_id = my_warehouse()));

-- جداول الحركات: قراءة حسب الشركة/المخزن/المندوب
do $$
declare t text;
begin
  foreach t in array array['work_sessions', 'stock_issues', 'sales', 'collections', 'returns', 'settlements', 'gps_locations', 'stock_movements'] loop
    execute format('drop policy if exists sel on %I', t);
    if t = 'stock_movements' then
      execute format($p$create policy sel on %I for select using (
        company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse()))$p$, t);
    elsif t = 'gps_locations' then
      execute format($p$create policy sel on %I for select using (
        rep_id = auth.uid() or (company_id = my_company() and my_role() in ('manager', 'keeper')))$p$, t);
    else
      execute format($p$create policy sel on %I for select using (
        rep_id = auth.uid() or
        (company_id = my_company() and (my_role() = 'manager' or warehouse_id = my_warehouse())))$p$, t);
    end if;
  end loop;
end $$;

drop policy if exists ins on gps_locations;
create policy ins on gps_locations for insert with check (
  rep_id = auth.uid() and company_id = my_company() and my_role() = 'rep');

drop policy if exists sel on rep_stock;
create policy sel on rep_stock for select using (
  exists (select 1 from work_sessions s where s.id = session_id));   -- يرث صلاحية work_sessions
drop policy if exists sel on stock_issue_items;
create policy sel on stock_issue_items for select using (
  exists (select 1 from stock_issues i where i.id = issue_id));
drop policy if exists sel on sale_items;
create policy sel on sale_items for select using (
  exists (select 1 from sales s where s.id = sale_id));
drop policy if exists sel on return_items;
create policy sel on return_items for select using (
  exists (select 1 from returns r where r.id = return_id));

-- ---------------------------------------------------------------------
-- Bootstrap: أول سوبر أدمن
-- 1) اعمل مستخدم من Authentication › Users (إيميل + باسورد)
-- 2) شغّل:  select bootstrap_super_admin('the-user-uuid', 'اسمك');
--    هيرجع لك مفتاح التفعيل بتاعك تكتبه في تطبيق الديسكتوب
-- ---------------------------------------------------------------------
create or replace function bootstrap_super_admin(p_user uuid, p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  insert into profiles(id, role, full_name) values (p_user, 'super_admin', p_name)
  on conflict (id) do update set role = 'super_admin', full_name = excluded.full_name;
  k := gen_license_key();
  insert into licenses(profile_id, license_key) values (p_user, k)
  on conflict (profile_id) do update set license_key = excluded.license_key, fingerprint = null;
  return k;
end $$;
revoke execute on function bootstrap_super_admin(uuid, text) from public, anon, authenticated;

-- بتستخدمها Edge Function "admin" لترقيم أكواد الشركات
create or replace function nextval_company() returns bigint
language sql security definer set search_path = public as $$ select nextval('company_seq') $$;
revoke execute on function nextval_company() from public, anon, authenticated;
grant execute on function nextval_company() to service_role;

-- =====================================================================
-- استيراد من Excel (أمين المخزن / المدير)
-- =====================================================================
create or replace function import_products(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; r jsonb; v_id uuid; v_ins int := 0; v_upd int := 0; v_skip int := 0; v_qty numeric;
begin
  me := assert_active();
  if me.role not in ('keeper', 'manager') then raise exception 'FORBIDDEN'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(trim(r->>'code'), '') = '' or coalesce(trim(r->>'name'), '') = '' then
      v_skip := v_skip + 1;
      continue;
    end if;
    select id into v_id from products where company_id = me.company_id and code = trim(r->>'code');
    if v_id is null then
      insert into products(company_id, code, name, unit, price, cost)
      values (me.company_id, trim(r->>'code'), trim(r->>'name'), coalesce(nullif(trim(r->>'unit'), ''), 'كرتونة'),
              coalesce((r->>'price')::numeric, 0), (r->>'cost')::numeric)
      returning id into v_id;
      v_ins := v_ins + 1;
    else
      update products set name = trim(r->>'name'),
                          unit = coalesce(nullif(trim(r->>'unit'), ''), unit),
                          price = coalesce((r->>'price')::numeric, price),
                          cost = coalesce((r->>'cost')::numeric, cost),
                          active = true
       where id = v_id;
      v_upd := v_upd + 1;
    end if;
    -- الكمية الافتتاحية بتدخل رصيد مخزن الأمين بس
    v_qty := (r->>'opening_qty')::numeric;
    if me.role = 'keeper' and v_qty is not null and v_qty > 0 then
      insert into warehouse_stock(warehouse_id, product_id, qty) values (me.warehouse_id, v_id, v_qty)
      on conflict (warehouse_id, product_id) do update set qty = warehouse_stock.qty + excluded.qty;
      insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, created_by)
      values (me.company_id, me.warehouse_id, v_id, v_qty, 'receive', me.id);
    end if;
  end loop;
  return jsonb_build_object('inserted', v_ins, 'updated', v_upd, 'skipped', v_skip);
end $$;

create or replace function import_customers(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; r jsonb; v_id uuid; v_ins int := 0; v_upd int := 0; v_skip int := 0; v_code text;
begin
  me := assert_active();
  if me.role <> 'keeper' then raise exception 'ONLY_KEEPER'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(trim(r->>'name'), '') = '' then
      v_skip := v_skip + 1;
      continue;
    end if;
    v_code := nullif(trim(r->>'code'), '');
    v_id := null;
    if v_code is not null then
      select id into v_id from customers where company_id = me.company_id and code = v_code;
    else
      select id into v_id from customers
       where company_id = me.company_id and warehouse_id = me.warehouse_id and name = trim(r->>'name') limit 1;
    end if;
    if v_id is null then
      insert into customers(company_id, warehouse_id, code, name, phone, area, address, credit_limit, balance)
      values (me.company_id, me.warehouse_id, v_code, trim(r->>'name'), nullif(r->>'phone', ''), nullif(r->>'area', ''),
              nullif(r->>'address', ''), coalesce((r->>'credit_limit')::numeric, 0), coalesce((r->>'opening_balance')::numeric, 0));
      v_ins := v_ins + 1;
    else
      -- الرصيد الحالي ماينفعش يتكتب فوقه من Excel (بيتغير من الفواتير والتحصيل)
      update customers set name = trim(r->>'name'),
                           phone = coalesce(nullif(r->>'phone', ''), phone),
                           area = coalesce(nullif(r->>'area', ''), area),
                           address = coalesce(nullif(r->>'address', ''), address),
                           credit_limit = coalesce((r->>'credit_limit')::numeric, credit_limit)
       where id = v_id;
      v_upd := v_upd + 1;
    end if;
  end loop;
  return jsonb_build_object('inserted', v_ins, 'updated', v_upd, 'skipped', v_skip);
end $$;
