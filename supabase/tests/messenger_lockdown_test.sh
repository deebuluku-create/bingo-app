#!/bin/bash
# Full-flow test of the reviewed application order on a SCRATCH Postgres 16
# (socket /tmp, port 54329, user postgres, trust auth). Never run against live.
#   harness (replica of the reported live contract)
#   -> 1. direct_conversation_rpc  -> 2. membership_lockdown  -> 3. revoke_truncate
# Every client check runs under the real Postgres roles anon / authenticated
# with a Supabase-style JWT sub, so RLS and grants are genuinely enforced.
T=$(cd "$(dirname "$0")" && pwd); M=$T/../migrations
A=aaaaaaaa-1111-4111-8111-111111111111; B=bbbbbbbb-2222-4222-8222-222222222222; C=cccccccc-3333-4333-8333-333333333333
PSQL="psql -h /tmp -p 54329 -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then echo "PASS  $1  ($2)"; pass=$((pass+1)); else echo "FAIL  $1  expected [$3] got [$2]"; fail=$((fail+1)); fi; }
as(){ local who=$1; shift
  if [ "$who" = anon ]; then $PSQL -c "begin; set local role anon; $*; commit;" 2>&1
  else $PSQL -c "begin; set local role authenticated; set local request.jwt.claims='{\"sub\":\"$who\"}'; $*; commit;" 2>&1; fi; }
denied(){ grep -cE 'row-level security|permission denied'; }
count(){ $PSQL -c "select (select count(*) from public.conversations)||'/'||(select count(*) from public.conversation_members)||'/'||(select count(*) from public.messages)"; }

$PSQL -f $T/messenger_local_harness.sql >/dev/null
echo "== baseline (live contract, before any change): the hole is real"
X=$(cat /proc/sys/kernel/random/uuid)   # a client supplies its own id (RETURNING would need SELECT, which RLS denies a non-member)
ok "client can create an empty conversation" "$(as $A "insert into public.conversations(id) values ('$X')" | denied)" "0"
as $A "insert into public.conversation_members(conversation_id,user_id) values ('$X','$A')" >/dev/null
as $A "insert into public.messages(conversation_id,sender_id,message) values ('$X','$A','secret')" >/dev/null
ok "C self-joins by conversation id" "$(as $C "insert into public.conversation_members(conversation_id,user_id) values ('$X','$C')" | denied)" "0"
ok "...and C can then read the messages" "$(as $C "select message from public.messages where conversation_id='$X'" | tail -1)" "secret"
$PSQL -c "truncate public.messages, public.conversation_members, public.conversations"

echo "== apply in the reviewed order"
$PSQL -f $M/20260928_bingo_messenger_direct_conversation_rpc_REVIEW_NOT_APPLIED.sql >/dev/null && echo "1 rpc applied"
$PSQL -f $M/20260928_bingo_messenger_membership_lockdown_REVIEW_NOT_APPLIED.sql >/dev/null && echo "2 lockdown applied"
$PSQL -f $M/20260928_bingo_messaging_revoke_truncate_REVIEW_NOT_APPLIED.sql >/dev/null && echo "3 truncate revoke applied"
ok "lockdown is re-runnable" "$($PSQL -f $M/20260928_bingo_messenger_membership_lockdown_REVIEW_NOT_APPLIED.sql >/dev/null 2>&1 && echo ok)" "ok"
echo "   policies now:"; $PSQL -F' ' -c "select '   '||tablename, policyname, cmd from pg_policies where schemaname='public' order by 1,3,2"

echo "== A starts a chat with B; B receives and replies"
CID=$(as $A "select public.bingo_get_or_create_direct_conversation('$B')" | tail -1)
ok "A gets a conversation id" "$(echo $CID | grep -cE '^[0-9a-f-]{36}$')" "1"
ok "RPC created conversation + both members" "$(count)" "1/2/0"
as $A "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$A','hello B')" >/dev/null
ok "B receives: sees conversation members" "$(as $B "select string_agg(user_id::text,',' order by user_id) from public.bingo_my_conversation_members() where conversation_id='$CID'" | tail -1)" "$A,$B"
ok "B receives: reads A's message" "$(as $B "select message from public.messages where conversation_id='$CID'" | tail -1)" "hello B"
as $B "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$B','hi A')" >/dev/null
ok "A reads B's reply" "$(as $A "select string_agg(message,'|' order by created_at) from public.messages where conversation_id='$CID'" | tail -1)" "hello B|hi A"
ok "repeat call reuses the conversation" "$(as $B "select public.bingo_get_or_create_direct_conversation('$A')" | tail -1)" "$CID"

echo "== C cannot join or read"
ok "C cannot join by supplying the conversation id" "$(as $C "insert into public.conversation_members(conversation_id,user_id) values ('$CID','$C')" | denied)" "1"
ok "C cannot insert a row for someone else either" "$(as $C "insert into public.conversation_members(conversation_id,user_id) values ('$CID','$A')" | denied)" "1"
ok "C cannot create an empty conversation" "$(as $C "insert into public.conversations default values" | denied)" "1"
ok "C sees no members (member function)" "$(as $C "select count(*) from public.bingo_my_conversation_members() where conversation_id='$CID'" | tail -1)" "0"
ok "C sees no members (table)" "$(as $C "select count(*) from public.conversation_members where conversation_id='$CID'" | tail -1)" "0"
ok "C reads no messages" "$(as $C "select count(*) from public.messages where conversation_id='$CID'" | tail -1)" "0"
ok "C cannot post" "$(as $C "insert into public.messages(conversation_id,sender_id,message) values ('$CID','$C','x')" | denied)" "1"
ok "C cannot use the RPC to enter A-B (only creates C's own pair)" "$(as $C "select public.bingo_get_or_create_direct_conversation('$A')" | tail -1 | grep -c "$CID")" "0"
ok "anon cannot call the RPCs" "$(as anon "select public.bingo_get_or_create_direct_conversation('$B')" | denied)" "1"
ok "anon reads nothing" "$(as anon "select count(*) from public.messages" | denied)$(as anon "select count(*) from public.messages" | tail -1 | grep -c '^0$')" "01"

echo "== existing users keep their reads and updates"
ok "A still reads own member row" "$(as $A "select count(*) from public.conversation_members where conversation_id='$CID'" | tail -1)" "1"
ok "A can still update own archived flag" "$(as $A "update public.conversation_members set archived=true where conversation_id='$CID' and user_id='$A' returning archived" | tail -1)" "t"
ok "A cannot update B's row" "$(as $A "update public.conversation_members set archived=true where conversation_id='$CID' and user_id='$B' returning 1" | tail -1 | grep -c 1)" "0"
ok "A still reads the conversation row" "$(as $A "select count(*) from public.conversations where id='$CID'" | tail -1)" "1"

echo "== TRUNCATE"
for r in anon $A; do for t in conversations conversation_members messages; do
  ok "$( [ $r = anon ] && echo anon || echo authenticated ) cannot TRUNCATE $t" "$(as $r "truncate public.$t" | grep -c 'permission denied')" "1"; done; done
ok "rows intact after TRUNCATE attempts" "$(count)" "2/4/2"
echo "   grants now (anon/authenticated):"; $PSQL -F' ' -c "select '   '||table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and table_name in ('conversations','conversation_members','messages') and grantee in ('anon','authenticated') group by 1,2 order by 1,2"
echo "RESULT: $pass passed, $fail failed"
