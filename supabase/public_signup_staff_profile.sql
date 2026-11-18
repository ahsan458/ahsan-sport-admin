-- AHSAN SPORT: create a safe staff profile automatically for every public signup.
-- New public accounts are staff, never owner/admin. Only the owner may promote roles.
create or replace function public.handle_new_ahsan_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, role, active)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(coalesce(new.email, 'کارمەند'), '@', 1)
    ),
    'staff',
    true
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_ahsan_auth_user_created on auth.users;

create trigger on_ahsan_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_ahsan_user();

revoke all on function public.handle_new_ahsan_user() from public;
