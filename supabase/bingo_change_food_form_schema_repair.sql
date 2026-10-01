-- Applied to Bingo App Kenya on 1 October 2026 after live schema inspection.
-- Add only fields already sent/read by the Food business form. Existing
-- rows, status rules, payment behavior and RLS policies are unchanged.
alter table public.food_businesses
  add column if not exists category text,
  add column if not exists delicacies text,
  add column if not exists delivery_area text,
  add column if not exists price_range text,
  add column if not exists delivery_available boolean not null default false,
  add column if not exists subscription_expires_at timestamptz;
notify pgrst, 'reload schema';
