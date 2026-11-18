-- AHSAN SPORT: ثبت فرۆشتن و کەمکردنەوەی کۆگا بە یەک transaction
create or replace function public.submit_sale(
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_model text,
  p_color text,
  p_size integer,
  p_quantity integer,
  p_sale_price_iqd integer,
  p_delivery_fee_iqd integer,
  p_employee_profit_iqd integer,
  p_shoe_image_path text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_match_count integer;
  v_variant_id uuid;
  v_product_id uuid;
  v_stock integer;
  v_order_id uuid;
begin
  if v_user_id is null then
    raise exception 'پێویستە بچیتە ژوورەوە';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and active = true
  ) then
    raise exception 'هەژمارەکەت چالاک نییە';
  end if;

  if coalesce(trim(p_customer_name), '') = ''
     or coalesce(trim(p_customer_phone), '') = ''
     or coalesce(trim(p_delivery_address), '') = ''
     or coalesce(trim(p_model), '') = ''
     or coalesce(trim(p_color), '') = ''
     or p_size not between 20 and 55
     or p_quantity < 1
     or p_sale_price_iqd < 0
     or p_delivery_fee_iqd < 0
     or p_employee_profit_iqd < 0
     or coalesce(trim(p_shoe_image_path), '') = '' then
    raise exception 'زانیارییەکانی فرۆشتن دروست نین';
  end if;

  select count(*) into v_match_count
  from public.inventory_variants v
  join public.products p on p.id = v.product_id
  where p.active = true
    and lower(trim(p.model)) = lower(trim(p_model))
    and lower(trim(v.color)) = lower(trim(p_color))
    and v.size = p_size;

  if v_match_count > 1 then
    raise exception 'زیاتر لە یەک کاڵای هاوشێوە لە کۆگادا هەیە؛ تکایە خاوەن پێداچوونەوە بکات';
  elsif v_match_count = 1 then
    select v.id, v.product_id, v.quantity
      into v_variant_id, v_product_id, v_stock
    from public.inventory_variants v
    join public.products p on p.id = v.product_id
    where p.active = true
      and lower(trim(p.model)) = lower(trim(p_model))
      and lower(trim(v.color)) = lower(trim(p_color))
      and v.size = p_size
    for update of v;

    if v_stock < p_quantity then
      raise exception 'ژمارەی پێڵاوی ماوە لە کۆگا بەشی ئەم فرۆشتنە ناکات';
    end if;

    update public.inventory_variants
    set quantity = quantity - p_quantity
    where id = v_variant_id;
  end if;

  insert into public.orders (
    staff_id, customer_name, customer_phone, delivery_address,
    product_id, variant_id, model, color, size, quantity,
    sale_price_iqd, delivery_fee_iqd, employee_profit_iqd,
    shoe_image_path, notes, status
  ) values (
    v_user_id, trim(p_customer_name), trim(p_customer_phone), trim(p_delivery_address),
    v_product_id, v_variant_id, trim(p_model), trim(p_color), p_size, p_quantity,
    p_sale_price_iqd, p_delivery_fee_iqd, p_employee_profit_iqd,
    p_shoe_image_path, nullif(trim(coalesce(p_notes, '')), ''), 'awaiting_delivery'
  )
  returning id into v_order_id;

  return v_order_id;
end;
$$;

revoke all on function public.submit_sale(text,text,text,text,text,integer,integer,integer,integer,integer,text,text) from public;
grant execute on function public.submit_sale(text,text,text,text,text,integer,integer,integer,integer,integer,text,text) to authenticated;
