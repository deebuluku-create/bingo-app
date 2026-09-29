-- READ-ONLY addendum to 20260928's inspection. Runs no writes. Paste into
-- the Supabase SQL editor and share the output.
--
-- The previous inspection (2a928a9) checked direct grants to 'anon' and
-- 'authenticated' via information_schema.role_table_grants, which is what
-- surfaced the reported TRUNCATE grant. That view does NOT show privileges
-- a role holds only through role membership/inheritance (e.g. if
-- authenticated is itself a member of some other role that was granted
-- TRUNCATE, or if a default-privileges rule applies it automatically to
-- every future table). These three queries close that gap.

-- 1) Does anon/authenticated inherit privileges from any other role, and
--    is inheritance even switched on for them? (rolinherit=false would mean
--    membership alone doesn't grant privileges automatically.)
select rolname, rolinherit
from pg_roles
where rolname in ('anon','authenticated');

-- 2) Which roles is anon/authenticated a MEMBER of? Any role listed here
--    that separately holds TRUNCATE on bingo_user_roles would also apply,
--    even if direct grants (query 1 from the first script) show none.
select r.rolname as member_role, g.rolname as inherits_privileges_from
from pg_auth_members m
join pg_roles r on r.oid = m.member
join pg_roles g on g.oid = m.roleid
where r.rolname in ('anon','authenticated');

-- 3) Was this GRANT applied to this one table specifically, or is there a
--    default-privileges rule that would silently re-apply TRUNCATE to
--    every new table created in public going forward (which the proposed
--    REVOKE in 20260929's draft would NOT fix, since it only targets the
--    one existing table)?
select defaclrole::regrole as default_grant_owner, defaclnamespace::regnamespace as schema,
       defaclobjtype, defaclacl
from pg_default_acl
where defaclnamespace = 'public'::regnamespace;
