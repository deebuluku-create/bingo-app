#!/bin/bash
# Usage: start a scratch Postgres 16 on socket /tmp port 54329 (user postgres, trust auth),
# then: bash supabase/tests/messenger_rpc_test.sh   -- never point this at the live project.
# SQL-level tests of the proposed migration on local Postgres 16 (harness replica).
S=$(cd "$(dirname "$0")" && pwd)
M=$S/../migrations
A=aaaaaaaa-1111-4111-8111-111111111111; B=bbbbbbbb-2222-4222-8222-222222222222; C=cccccccc-3333-4333-8333-333333333333
PSQL="psql -h /tmp -p 54329 -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then echo "PASS  $1  ($2)"; pass=$((pass+1)); else echo "FAIL  $1  expected [$3] got [$2]"; fail=$((fail+1)); fi; }
as(){ # as <uid|anon> <sql>  -> runs in one transaction under RLS
  local who=$1; shift
  if [ "$who" = anon ]; then $PSQL -c "begin; set local role anon; $*; commit;" 2>&1
  else $PSQL -c "begin; set local role authenticated; set local request.jwt.claims='{\"sub\":\"$who\"}'; $*; commit;" 2>&1; fi
}
$PSQL -f $S/messenger_local_harness.sql >/dev/null
echo "== grants BEFORE (harness uses Supabase default grants)"
$PSQL -F' | ' -c "select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and table_name in ('conversations','conversation_members','messages') and grantee in ('anon','authenticated') group by 1,2 order by 1,2"
ok "anon can TRUNCATE messages before" "$($PSQL -c "select has_table_privilege('anon','public.messages','TRUNCATE')")" "t"

echo "== contract confirms client limits (no migration yet)"
r=$(as $A "insert into public.conversations default values returning id" | tail -1); CID0=$r
ok "client cannot add another user as member" "$(as $A "insert into public.conversation_members(conversation_id,user_id) values ('$CID0','$B')" | grep -c 'row-level security')" "1"

echo "== apply proposed migrations (requests first, then the conversation RPC)"
$PSQL -f $M/20260928_bingo_messenger_communication_requests_REVIEW_NOT_APPLIED.sql >/dev/null && echo "requests applied"
$PSQL -f $M/20260928_bingo_messenger_direct_conversation_rpc_REVIEW_NOT_APPLIED.sql >/dev/null && echo "rpc applied"
ok "RPC refuses pairs without an accepted request" "$(as $A "select public.bingo_get_or_create_direct_conversation('$B')" | grep -c 'request to communicate required')" "1"
# test setup (as the owner, not a client): accepted requests for the pairs exercised below
$PSQL -c "insert into public.bingo_communication_requests(requester_id,recipient_id,status,responded_at) values ('$A','$B','accepted',now()),('$A','$C','accepted',now()),('$C','eeeeeeee-5555-4555-8555-555555555555','accepted',now())"
$PSQL -c "delete from public.conversations"   # drop the stray row from the limit check

echo "== A creates, B receives and replies"
CID=$(as $A "select public.bingo_get_or_create_direct_conversation('$B')" | tail -1)
ok "A gets a conversation id" "$(echo $CID | grep -cE '^[0-9a-f-]{36}$')" "1"
ok "both member rows exist" "$($PSQL -c "select count(*) from public.conversation_members where conversation_id='$CID'")" "2"
as $A "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$A','hello B')" >/dev/null
ok "B sees the conversation via member function" "$(as $B "select count(*) from public.bingo_my_conversation_members() where conversation_id='$CID'" | tail -1)" "2"
ok "B still sees only own row via table (policy unchanged)" "$(as $B "select count(*) from public.conversation_members" | tail -1)" "1"
ok "B reads A's message" "$(as $B "select message from public.messages where conversation_id='$CID'" | tail -1)" "hello B"
as $B "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$B','hi A')" >/dev/null
ok "A reads B's reply" "$(as $A "select string_agg(message,'|' order by created_at) from public.messages where conversation_id='$CID'" | tail -1)" "hello B|hi A"

echo "== duplicate prevention"
ok "A again -> same conversation" "$(as $A "select public.bingo_get_or_create_direct_conversation('$B')" | tail -1)" "$CID"
ok "B -> A -> same conversation" "$(as $B "select public.bingo_get_or_create_direct_conversation('$A')" | tail -1)" "$CID"
$PSQL -c "delete from public.conversations where id<>'$CID'"
# concurrent: 20 parallel callers, A->C and C->A interleaved; all must get one id
for i in $(seq 1 10); do (as $A "select public.bingo_get_or_create_direct_conversation('$C')" | tail -1 > /tmp/bm_par_a_$i) & (as $C "select public.bingo_get_or_create_direct_conversation('$A')" | tail -1 > /tmp/bm_par_c_$i) & done; wait
ok "20 concurrent A<->C calls -> 1 distinct id" "$(cat /tmp/bm_par_a_* /tmp/bm_par_c_* | sort -u | wc -l)" "1"
ok "A<->C has exactly 1 conversation, 2 members" "$($PSQL -c "select count(distinct conversation_id)||'/'||count(*) from public.conversation_members m where exists(select 1 from public.conversation_members x where x.conversation_id=m.conversation_id and x.user_id='$C')")" "1/2"
CAC=$(cat /tmp/bm_par_a_1)

echo "== unauthorised access"
ok "anon cannot call create" "$(as anon "select public.bingo_get_or_create_direct_conversation('$B')" | grep -c 'permission denied')" "1"
ok "anon cannot call member lookup" "$(as anon "select * from public.bingo_my_conversation_members()" | grep -c 'permission denied')" "1"
ok "C sees no A-B members" "$(as $C "select count(*) from public.bingo_my_conversation_members() where conversation_id='$CID'" | tail -1)" "0"
ok "C reads no A-B messages" "$(as $C "select count(*) from public.messages where conversation_id='$CID'" | tail -1)" "0"
ok "C cannot post into A-B" "$(as $C "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$C','x')" | grep -c 'row-level security')" "1"
ok "FINDING: C CAN self-join A-B via the live INSERT policy (0 = insert succeeded)" "$(as $C "insert into public.conversation_members(conversation_id,user_id) values ('$CID','$C')" 2>&1 | grep -c 'row-level security')" "0"
$PSQL -c "delete from public.conversation_members where conversation_id='$CID' and user_id='$C'"
ok "A cannot spoof sender" "$(as $A "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$B','spoof')" | grep -c 'row-level security')" "1"
ok "self as recipient rejected" "$(as $A "select public.bingo_get_or_create_direct_conversation('$A')" | grep -c 'invalid recipient')" "1"
ok "unknown recipient rejected" "$(as $A "select public.bingo_get_or_create_direct_conversation('ffffffff-6666-4666-8666-666666666666')" | grep -c 'recipient not found')" "1"
ok "unauthenticated (no sub) rejected" "$($PSQL -c "begin; set local role authenticated; select public.bingo_get_or_create_direct_conversation('$B'); commit;" 2>&1 | grep -c 'not authenticated')" "1"
ok "blocked pair: reuse refused" "$(as $C "select public.bingo_block_member('$A')" >/dev/null; as $A "select public.bingo_get_or_create_direct_conversation('$C')" | grep -c 'blocked')" "1"
as $C "select public.bingo_unblock_member('$A')" >/dev/null; $PSQL -c "insert into public.bingo_communication_requests(requester_id,recipient_id,status,responded_at) values ('$A','$C','accepted',now())"

echo "== failure rollback"
before="$($PSQL -c "select (select count(*) from public.conversations)||'/'||(select count(*) from public.conversation_members)")"
$PSQL -c "create function public._fail_second() returns trigger language plpgsql as \$\$ begin if new.user_id='$C' then raise exception 'injected failure on second member'; end if; return new; end \$\$; create trigger _fail before insert on public.conversation_members for each row execute function public._fail_second();"
true  # E and the accepted C-E request are seeded above
ok "injected failure surfaces" "$(as $C "select public.bingo_get_or_create_direct_conversation('eeeeeeee-5555-4555-8555-555555555555')" | grep -c 'injected failure')" "1"
ok "nothing left behind (conversations/members)" "$($PSQL -c "select (select count(*) from public.conversations)||'/'||(select count(*) from public.conversation_members)")" "$before"
$PSQL -c "drop trigger _fail on public.conversation_members; drop function public._fail_second();"

echo "== function hardening"
ok "both functions SECURITY DEFINER with empty search_path" "$($PSQL -c "select string_agg(proname||':'||prosecdef||':'||array_to_string(proconfig,','),' ' order by proname) from pg_proc where proname in ('bingo_get_or_create_direct_conversation','bingo_my_conversation_members')")" "bingo_get_or_create_direct_conversation:true:search_path=\"\" bingo_my_conversation_members:true:search_path=\"\""

echo "== TRUNCATE correction"
$PSQL -f $M/20260928_bingo_messaging_revoke_truncate_REVIEW_NOT_APPLIED.sql >/dev/null
echo "== grants AFTER"
$PSQL -F' | ' -c "select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and table_name in ('conversations','conversation_members','messages') and grantee in ('anon','authenticated') group by 1,2 order by 1,2"
ok "anon/authenticated TRUNCATE revoked on all 3" "$($PSQL -c "select bool_or(has_table_privilege('anon',c.oid,'TRUNCATE') or has_table_privilege('authenticated',c.oid,'TRUNCATE')) from pg_class c where c.oid in ('public.conversations'::regclass,'public.conversation_members'::regclass,'public.messages'::regclass)")" "f"
ok "authenticated TRUNCATE now refused" "$(as $A "truncate public.messages" | grep -c 'permission denied')" "1"
ok "SELECT/INSERT still granted" "$($PSQL -c "select has_table_privilege('authenticated','public.messages','SELECT,INSERT')")" "t"
echo "RESULT: $pass passed, $fail failed"
