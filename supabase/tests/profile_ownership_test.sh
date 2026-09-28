#!/bin/bash
# Profile ownership under real RLS on a SCRATCH Postgres 16 (socket /tmp,
# port 54329, trust auth). Never run against live. Exercises:
#   * the live-check script (profile_ownership_LIVE_CHECK_ROLLBACK.sql) itself,
#   * an INSECURE policy set (the case the correction exists for),
#   * a typical own-row policy set,
#   * the review-only correction applied on top of the insecure set.
# Clients act as the real roles anon / authenticated with a JWT "sub".
T=$(cd "$(dirname "$0")" && pwd); M=$T/../migrations
A=aaaaaaaa-1111-4111-8111-111111111111; B=bbbbbbbb-2222-4222-8222-222222222222
PSQL="psql -h /tmp -p 54329 -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then echo "PASS  $1  ($2)"; pass=$((pass+1)); else echo "FAIL  $1  expected [$3] got [$2]"; fail=$((fail+1)); fi; }
as(){ local who=$1; shift
  if [ "$who" = anon ]; then $PSQL -c "begin; set local role anon; $*; commit;" 2>&1
  else $PSQL -c "begin; set local role authenticated; set local request.jwt.claims='{\"sub\":\"$who\"}'; $*; commit;" 2>&1; fi; }
rows(){ as "$1" "with u as ($2 returning 1) select count(*) from u" | tail -1; }
rls(){ grep -cE 'row-level security'; }
name(){ $PSQL -c "select full_name from public.profiles where id='$1'"; }
livecheck(){ sed "s/00000000-0000-0000-0000-00000000000A/$A/; s/00000000-0000-0000-0000-00000000000B/$B/" $T/profile_ownership_LIVE_CHECK_ROLLBACK.sql \
  | psql -h /tmp -p 54329 -U postgres -d postgres -qtA 2>&1 | grep -E 'step [123]|ERROR' | sed 's/^/     /'; }

setup(){  # $1 = insecure | ownrow
$PSQL -f $T/messenger_local_harness.sql >/dev/null
$PSQL <<SQL >/dev/null
insert into auth.users values ('$A'),('$B') on conflict do nothing;
create table public.profiles(id uuid primary key references auth.users(id), full_name text, first_name text, last_name text,
  email text, phone text, town text, bio text, photo_url text, show_phone boolean default true, updated_at timestamptz default now());
grant all on public.profiles to anon, authenticated, service_role;
alter table public.profiles enable row level security;
insert into public.profiles(id,full_name,bio) values ('$A','Alice Owner','A bio'),('$B','Bob Other','B bio');
SQL
if [ "$1" = insecure ]; then
 $PSQL -c "create policy p_select on public.profiles for select using (true);
           create policy p_insert on public.profiles for insert to authenticated with check (true);
           create policy p_update on public.profiles for update to authenticated using (true) with check (true);" >/dev/null
else
 $PSQL -c "create policy p_select on public.profiles for select using (true);
           create policy p_insert on public.profiles for insert to authenticated with check (auth.uid() = id);
           create policy p_update on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);" >/dev/null
fi; }

UPSERT_A="insert into public.profiles(id,full_name,first_name,last_name,email,phone,updated_at) values ('$A','HIJACKED','x','y','','',now()) on conflict (id) do update set full_name=excluded.full_name"

echo "== 1. INSECURE policies (update using true): the hole the correction targets"
setup insecure
ok "B updates A's profile directly" "$(rows $B "update public.profiles set bio='hijacked' where id='$A'")" "1"
as $B "$UPSERT_A" >/dev/null; ok "B upserts with A's id (the app's save path)" "$(name $A)" "HIJACKED"
echo "   live-check script output against this database:"; livecheck
echo "== 2. apply the review-only correction on top of the insecure policies"
setup insecure
$PSQL -f $M/20260928_bingo_profile_ownership_REVIEW_NOT_APPLIED.sql >/dev/null && echo "   correction applied"
ok "correction is re-runnable" "$($PSQL -f $M/20260928_bingo_profile_ownership_REVIEW_NOT_APPLIED.sql >/dev/null 2>&1 && echo ok)" "ok"
ok "B updates A's profile -> 0 rows" "$(rows $B "update public.profiles set bio='hijacked' where id='$A'")" "0"
ok "B upsert with A's id -> RLS error" "$(as $B "$UPSERT_A" | rls)" "1"
ok "...A's profile unchanged" "$(name $A)" "Alice Owner"
ok "B cannot create a profile row for someone else" "$(as $B "insert into public.profiles(id,full_name) values ('$A','x') on conflict do nothing" | rls)" "1"
ok "B cannot move own row onto another id" "$(as $B "update public.profiles set id='$A' where id='$B'" | grep -cE 'row-level security|duplicate key')" "1"
ok "B cannot delete A's profile" "$(rows $B "delete from public.profiles where id='$A'")" "0"
ok "anon cannot update any profile" "$(rows anon "update public.profiles set bio='x' where id='$A'")" "0"
ok "A still updates own profile" "$(rows $A "update public.profiles set bio='new A bio' where id='$A'")" "1"
as $A "insert into public.profiles(id,full_name,first_name,last_name,email,phone,updated_at) values ('$A','Alice Renamed','a','o','','',now()) on conflict (id) do update set full_name=excluded.full_name" >/dev/null
ok "A's own upsert (app save path) still works" "$(name $A)" "Alice Renamed"
ok "public profile reads unchanged (B reads A)" "$(as $B "select full_name from public.profiles where id='$A'" | tail -1)" "Alice Renamed"
ok "guest reads unchanged" "$(as anon "select count(*) from public.profiles" | tail -1)" "2"
echo "   live-check script output after the correction:"; livecheck
echo "== 3. TYPICAL own-row policies (no correction needed)"
setup ownrow
ok "B updates A's profile -> 0 rows" "$(rows $B "update public.profiles set bio='hijacked' where id='$A'")" "0"
ok "B upsert with A's id -> RLS error" "$(as $B "$UPSERT_A" | rls)" "1"
ok "A updates own profile" "$(rows $A "update public.profiles set bio='x' where id='$A'")" "1"
echo "   live-check script output:"; livecheck
echo "== 4. correction refuses to run when RLS is disabled (would hide all profiles)"
setup ownrow; $PSQL -c "alter table public.profiles disable row level security" >/dev/null
ok "stops with an explanation" "$($PSQL -f $M/20260928_bingo_profile_ownership_REVIEW_NOT_APPLIED.sql 2>&1 | grep -c 'RLS is DISABLED')" "1"
echo "RESULT $pass passed, $fail failed"
