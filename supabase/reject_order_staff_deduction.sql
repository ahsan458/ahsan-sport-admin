-- AHSAN SPORT: reject a customer-refused order, restore matched stock, and debit staff once.
create table if not exists public.staff_order_deductions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete restrict,
  staff_id uuid not null references public.profiles(id) on delete restrict,
  amount_iqd bigint not null check (amount_iqd >= 0),
  reason text not null default 'customer_rejected',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.staff_order_deductions enable row level security;
drop policy if exists "owner reads staff order deductions" on public.staff_order_deductions;
create policy "owner reads staff order deductions"
on public.staff_order_deductions for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'owner' and p.active = true
  )
);

revoke all on public.staff_order_deductions from anon, authenticated;
grant select on public.staff_order_deductions to authenticated;

create or replace function public.reject_order_and_debit_staff(p_order_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_amount bigint;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'owner' and active = true
  ) then
    raise exception 'تەنها خاوەن دەتوانێت داواکاری ڕەت بکاتەوە';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'داواکارییەکە نەدۆزرایەوە';
  end if;

  if v_order.status <> 'awaiting_delivery' then
    raise exception 'تەنها داواکاریی چاوەڕوان دەتوانرێت ڕەت بکرێتەوە';
  end if;

  v_amount :=
    (coalesce(v_order.sale_price_iqd, 0)::bigint
      * greatest(coalesce(v_order.quantity, 1), 1))
    + coalesce(v_order.delivery_fee_iqd, 0)::bigint;

  -- Return stock only when this order originally matched an inventory variant.
  if v_order.variant_id is not null then
    update public.inventory_variants
    set quantity = quantity + greatest(coalesce(v_order.quantity, 1), 1)
    where id = v_order.variant_id;

    if not found then
      raise exception 'کاڵای پەیوەندیدار لە کۆگادا نەدۆزرایەوە؛ داواکاری ڕەت نەکراوەتەوە';
    end if;
  end if;

  update public.orders
  set status = 'cancelled'
  where id = p_order_id;

  insert into public.staff_order_deductions (
    order_id, staff_id, amount_iqd, reason, created_by
  )
  values (
    p_order_id, v_order.staff_id, v_amount, 'customer_rejected', auth.uid()
  )
  on conflict (order_id) do nothing;

  return v_amount;
end;
$$;

revoke all on function public.reject_order_and_debit_staff(uuid) from public;
grant execute on function public.reject_order_and_debit_staff(uuid) to authenticated;
