-- AHSAN SPORT: employee payment ledger and owner-only payment recording
create table if not exists public.staff_payments (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles(id) on delete restrict,
  amount_iqd bigint not null check (amount_iqd > 0),
  note text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  paid_at timestamptz not null default now()
);

create index if not exists staff_payments_staff_paid_at_idx
  on public.staff_payments(staff_id, paid_at desc);

alter table public.staff_payments enable row level security;
drop policy if exists "owner reads staff payments" on public.staff_payments;
create policy "owner reads staff payments"
on public.staff_payments for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'owner' and p.active = true
  )
);

revoke all on public.staff_payments from anon, authenticated;
grant select on public.staff_payments to authenticated;

create or replace function public.record_staff_payment(
  p_staff_id uuid,
  p_amount_iqd bigint,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_earned bigint;
  v_deductions bigint;
  v_paid bigint;
  v_balance bigint;
  v_payment_id uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'owner' and active = true
  ) then
    raise exception 'تەنها خاوەن دەتوانێت پارەدانی کارمەند تۆمار بکات';
  end if;

  if p_staff_id is null or p_amount_iqd is null or p_amount_iqd <= 0 then
    raise exception 'بڕی پارەدان دروست نییە';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_staff_id and role <> 'owner'
  ) then
    raise exception 'کارمەندەکە نەدۆزرایەوە';
  end if;

  -- Serialize payment entries for this employee to prevent overpayment from concurrent requests.
  perform 1 from public.profiles where id = p_staff_id for update;

  select coalesce(sum(employee_profit_iqd::bigint * greatest(quantity, 1)), 0)
    into v_earned
  from public.orders
  where staff_id = p_staff_id and status <> 'cancelled';

  select coalesce(sum(amount_iqd), 0)
    into v_deductions
  from public.staff_order_deductions
  where staff_id = p_staff_id;

  select coalesce(sum(amount_iqd), 0)
    into v_paid
  from public.staff_payments
  where staff_id = p_staff_id;

  v_balance := v_earned - v_deductions - v_paid;

  if p_amount_iqd > v_balance then
    raise exception 'بڕی پارەدان لە بڕی ماوە زیاترە؛ بڕی ماوە: % دینار', greatest(v_balance, 0);
  end if;

  insert into public.staff_payments(staff_id, amount_iqd, note, created_by)
  values (p_staff_id, p_amount_iqd, nullif(trim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_payment_id;

  return v_payment_id;
end;
$$;

revoke all on function public.record_staff_payment(uuid,bigint,text) from public;
grant execute on function public.record_staff_payment(uuid,bigint,text) to authenticated;
