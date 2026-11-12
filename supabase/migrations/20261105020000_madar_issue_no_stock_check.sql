create or replace function create_stock_issue(p_rep uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles; v_rep profiles; v_session uuid; v_issue uuid; v_no text;
  it jsonb; pr products; v_qty numeric; v_price numeric; v_total numeric := 0;
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
    insert into stock_issue_items(issue_id, product_id, qty, price) values (v_issue, pr.id, v_qty, v_price);
    insert into rep_stock(session_id, product_id, price, qty_issued) values (v_session, pr.id, v_price, v_qty);
    insert into stock_movements(company_id, warehouse_id, product_id, qty_change, kind, ref_id, created_by)
    values (me.company_id, me.warehouse_id, pr.id, -v_qty, 'issue', v_issue, me.id);
    v_total := v_total + v_qty * v_price;
  end loop;

  update stock_issues set total = v_total where id = v_issue;
  return jsonb_build_object('issue_id', v_issue, 'no', v_no, 'session_id', v_session, 'total', v_total);
end $$;
