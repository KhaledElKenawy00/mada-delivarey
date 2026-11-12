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
  delete from customers where company_id = v_company;
  delete from products where company_id = v_company;
end $$;
