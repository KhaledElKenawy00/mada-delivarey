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
  delete from gps_locations where company_id = p_company;
  delete from customers where company_id = p_company;
  delete from products where company_id = p_company;
  delete from licenses where company_id = p_company;
  delete from profiles where company_id = p_company;
  delete from warehouses where company_id = p_company;
  delete from companies where id = p_company;
end $$;
revoke execute on function admin_delete_company(uuid) from public, anon, authenticated;
grant execute on function admin_delete_company(uuid) to service_role;
