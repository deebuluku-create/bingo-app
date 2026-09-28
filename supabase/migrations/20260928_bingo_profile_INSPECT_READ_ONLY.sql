-- ============================================================
-- BINGO PROFILE - READ-ONLY inspection for the redesigned profile page
-- STATUS: queries only. Nothing here changes data, schema or policies.
-- Run in the Supabase SQL editor and send back the output. No profile
-- migration is proposed until this output confirms a missing capability.
--
-- What the new profile reads today (BINGO_MASTER_CURRENT_VERIFIED.html,
-- aaProfileDestyHTML / aaBpItems / aaResolveMemberMeta):
--   profiles: id, full_name / username / first_name / last_name /
--     company_name, photo_url / avatar_url, bio, town / location,
--     show_phone, phone, is_gold_member / membership_status, created_at,
--     crown_status / crown_awarded_at
--   bingo_follows: follower / following counts and the follow toggle
--   vehicle_listings, property_listings, food_businesses (+ their media)
--     filtered by the profile owner's id
-- What it deliberately does NOT show, pending this inspection:
--   a verification badge, a cover photo, social handles, stories,
--   tagged posts, liked posts, wallet balances, profile QR codes.
-- ============================================================

-- 1. profiles: every column (look for verification / cover / social / tagline fields)
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='profiles'
order by ordinal_position;

-- 2. profiles RLS: a visitor must not be able to UPDATE someone else's row
select c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c where c.oid='public.profiles'::regclass;
select policyname, cmd, roles, qual, with_check
from pg_policies where schemaname='public' and tablename='profiles'
order by cmd, policyname;
select grantee, string_agg(privilege_type, ',' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema='public' and table_name='profiles' and grantee in ('anon','authenticated')
group by grantee;
-- columns readable by anon/authenticated (owner-only data such as phone/email must not leak
-- to visitors unless intended - compare with show_phone handling)
select grantee, column_name, privilege_type
from information_schema.column_privileges
where table_schema='public' and table_name='profiles' and grantee in ('anon','authenticated')
order by grantee, column_name;

-- 3. bingo_follows contract (reused for follow/unfollow and the counts)
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='bingo_follows'
order by ordinal_position;
select policyname, cmd, roles, qual, with_check
from pg_policies where schemaname='public' and tablename='bingo_follows'
order by cmd, policyname;
select conname, pg_get_constraintdef(oid)
from pg_constraint where conrelid='public.bingo_follows'::regclass;

-- 4. Anything that could back the sections shown as "not available yet"
select table_name
from information_schema.tables
where table_schema='public'
  and (table_name ilike '%stor%' or table_name ilike '%highlight%' or table_name ilike '%tag%'
    or table_name ilike '%like%' or table_name ilike '%wallet%' or table_name ilike '%earning%'
    or table_name ilike '%verif%' or table_name ilike '%social%' or table_name ilike '%saved%'
    or table_name ilike '%favorit%' or table_name ilike '%qr%')
order by table_name;

-- 5. Profile / follow / analytics functions that already exist
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer, pg_get_function_result(p.oid) as returns
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and (p.proname ilike '%profile%' or p.proname ilike '%follow%' or p.proname ilike '%insight%'
    or p.proname ilike '%analytic%' or p.proname ilike '%crown%' or p.proname ilike '%verif%')
order by p.proname;

-- 6. Owner columns of the listing tables the profile grid reads
select table_name, column_name, data_type
from information_schema.columns
where table_schema='public'
  and table_name in ('vehicle_listings','property_listings','food_businesses','posts')
  and (column_name ilike '%user%' or column_name ilike '%owner%' or column_name ilike '%seller%'
    or column_name ilike '%status%' or column_name ilike '%deleted%')
order by table_name, column_name;

-- 7. Profile image storage
select id, public, file_size_limit, allowed_mime_types
from storage.buckets where id in ('profile-images','avatars','covers');

-- 8. Cover photo support (profile directive, 28 Sep): do these columns exist?
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='profiles'
  and column_name in ('cover_url','cover_position','photo_url','avatar_url')
order by column_name;

-- 9. profile-images Storage policies: are writes limited to the owner's own
--    folder (first path segment = auth.uid())? The cover uses <uid>/cover-*.jpg
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='storage' and tablename='objects'
  and (qual ilike '%profile-images%' or with_check ilike '%profile-images%')
order by cmd, policyname;
