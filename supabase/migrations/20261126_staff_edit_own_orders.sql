-- AHSAN SPORT: allow active staff to edit only orders they created.
-- Run this migration once in the Supabase SQL Editor.

create or replace function public.ahsan_staff_can_edit_order(p_staff_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.id = p_staff_id
      and p.active is true
      and p.role <> 'owner'
  );
$$;

revoke all on function public.ahsan_staff_can_edit_order(uuid) from public;
grant execute on function public.ahsan_staff_can_edit_order(uuid) to authenticated;

drop policy if exists "Staff can update own orders" on public.orders;
create policy "Staff can update own orders"
on public.orders
for update
to authenticated
using (public.ahsan_staff_can_edit_order(staff_id))
with check (public.ahsan_staff_can_edit_order(staff_id));

grant update on table public.orders to authenticated;

-- Staff may edit order details, but not transfer ownership or change
-- the owner's review/receipt workflow or the original creation timestamp.
create or replace function public.ahsan_protect_order_control_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  if auth.uid() is not null then
    select p.role into v_role
    from public.profiles p
    where p.id = auth.uid();

    if coalesce(v_role, '') <> 'owner' then
      if new.id is distinct from old.id
        or new.staff_id is distinct from old.staff_id
        or new.status is distinct from old.status
        or new.viewed_at is distinct from old.viewed_at
        or new.receipt_recorded_at is distinct from old.receipt_recorded_at
        or new.created_at is distinct from old.created_at then
        raise exception 'Staff may edit only order details on their own orders';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ahsan_protect_order_control_fields on public.orders;
create trigger ahsan_protect_order_control_fields
before update on public.orders
for each row
execute function public.ahsan_protect_order_control_fields();
