#!/bin/bash
# Request to Communicate: pending / rejected / accepted / blocked, each with two
# identities, under the real anon/authenticated roles on a SCRATCH Postgres 16
# (socket /tmp, port 54329). Applies the full reviewed order first. Never run live.
T=$(cd "$(dirname "$0")" && pwd); M=$T/../migrations
A=aaaaaaaa-1111-4111-8111-111111111111; B=bbbbbbbb-2222-4222-8222-222222222222; C=cccccccc-3333-4333-8333-333333333333
D=dddddddd-4444-4444-8444-444444444444; E=eeeeeeee-5555-4555-8555-555555555555
PSQL="psql -h /tmp -p 54329 -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then echo "PASS  $1  ($2)"; pass=$((pass+1)); else echo "FAIL  $1  expected [$3] got [$2]"; fail=$((fail+1)); fi; }
as(){ local who=$1; shift
  if [ "$who" = anon ]; then $PSQL -c "begin; set local role anon; $*; commit;" 2>&1
  else $PSQL -c "begin; set local role authenticated; set local request.jwt.claims='{\"sub\":\"$who\"}'; $*; commit;" 2>&1; fi; }
has(){ grep -c "$1"; }
start(){ as $1 "select public.bingo_get_or_create_direct_conversation('$2')" | tail -1; }
start_err(){ as $1 "select public.bingo_get_or_create_direct_conversation('$2')"; }
post(){ as $1 "insert into public.messages(conversation_id,sender_id,message) values ('$2','$1','$3')"; }
status(){ $PSQL -c "select coalesce((select status||coalesce(':'||case when blocked_by='$1' then 'by-first' when blocked_by='$2' then 'by-second' end,'') from public.bingo_communication_requests where least(requester_id,recipient_id)=least('$1'::uuid,'$2'::uuid) and greatest(requester_id,recipient_id)=greatest('$1'::uuid,'$2'::uuid)),'none')"; }

$PSQL -f $T/messenger_local_harness.sql >/dev/null
for f in communication_requests direct_conversation_rpc membership_lockdown; do $PSQL -f $M/20260928_bingo_messenger_${f}_REVIEW_NOT_APPLIED.sql >/dev/null; done
$PSQL -f $M/20260928_bingo_messaging_revoke_truncate_REVIEW_NOT_APPLIED.sql >/dev/null
echo "== no request (A -> B)"
ok "cannot start a conversation" "$(start_err $A $B | has 'request to communicate required')" "1"

echo "== PENDING (A -> D)"
ok "A requests D" "$(as $A "select public.bingo_request_communication('$D')" | tail -1)" "pending"
ok "requesting again is idempotent" "$(as $A "select public.bingo_request_communication('$D')" | tail -1)" "pending"
ok "A cannot start while pending" "$(start_err $A $D | has 'is pending')" "1"
ok "D cannot start while pending either" "$(start_err $D $A | has 'is pending')" "1"
ok "A cannot accept their own request" "$(as $A "select public.bingo_respond_communication_request('$D', true)" | has 'no pending request')" "1"
ok "D sees the incoming request" "$(as $D "select count(*) from public.bingo_communication_requests where requester_id='$A' and recipient_id='$D' and status='pending'" | tail -1)" "1"
ok "outsider C cannot see it" "$(as $C "select count(*) from public.bingo_communication_requests" | tail -1)" "0"
ok "A cannot forge acceptance (UPDATE)" "$(as $A "update public.bingo_communication_requests set status='accepted'" | has 'permission denied')" "1"
ok "A cannot forge an accepted row (INSERT)" "$(as $A "insert into public.bingo_communication_requests(requester_id,recipient_id,status) values ('$A','$E','accepted')" | has 'permission denied')" "1"
ok "A cannot delete it" "$(as $A "delete from public.bingo_communication_requests" | has 'permission denied')" "1"
ok "anon cannot request" "$(as anon "select public.bingo_request_communication('$D')" | has 'permission denied')" "1"
ok "status still pending" "$(status $A $D)" "pending"

echo "== REJECTED (C -> E)"
ok "C requests E" "$(as $C "select public.bingo_request_communication('$E')" | tail -1)" "pending"
ok "E declines" "$(as $E "select public.bingo_respond_communication_request('$C', false)" | tail -1)" "rejected"
ok "C cannot start" "$(start_err $C $E | has 'was declined')" "1"
ok "C cannot ask again" "$(as $C "select public.bingo_request_communication('$E')" | has 'was declined')" "1"
ok "E cannot answer twice" "$(as $E "select public.bingo_respond_communication_request('$C', true)" | has 'no pending request')" "1"
ok "E may later ask C (roles swap)" "$(as $E "select public.bingo_request_communication('$C')" | tail -1)" "pending"
ok "C accepts E's request" "$(as $C "select public.bingo_respond_communication_request('$E', true)" | tail -1)" "accepted"
ok "now they can start" "$(start $C $E | grep -cE '^[0-9a-f-]{36}$')" "1"

echo "== ACCEPTED (A -> B), two identities messaging"
ok "A requests B" "$(as $A "select public.bingo_request_communication('$B')" | tail -1)" "pending"
ok "B accepts" "$(as $B "select public.bingo_respond_communication_request('$A', true)" | tail -1)" "accepted"
CID=$(start $A $B)
ok "A starts the conversation" "$(echo $CID | grep -cE '^[0-9a-f-]{36}$')" "1"
ok "B gets the same conversation" "$(start $B $A)" "$CID"
post $A $CID "hello B" >/dev/null; post $B $CID "hi A" >/dev/null
ok "both messages stored" "$(as $A "select string_agg(message,'|' order by created_at) from public.messages where conversation_id='$CID'" | tail -1)" "hello B|hi A"
ok "mutual request counts as acceptance (D asks A back)" "$(as $D "select public.bingo_request_communication('$A')" | tail -1)" "accepted"

echo "== BLOCKED (B blocks A after chatting)"
ok "B blocks A" "$(as $B "select public.bingo_block_member('$A')" | tail -1)" "blocked"
ok "status blocked by B" "$(status $B $A)" "blocked:by-first"
ok "A can no longer post (restrictive messages policy)" "$(post $A $CID 'after block' | has 'row-level security')" "1"
ok "B can no longer post either" "$(post $B $CID 'after block' | has 'row-level security')" "1"
ok "A cannot start/reuse the conversation" "$(start_err $A $B | has 'blocked')" "1"
ok "A cannot send a new request" "$(as $A "select public.bingo_request_communication('$B')" | has 'blocked')" "1"
ok "A cannot lift B's block" "$(as $A "select public.bingo_unblock_member('$B')" | has 'have not blocked')" "1"
ok "A blocking too does not override B's block" "$(as $A "select public.bingo_block_member('$B')" >/dev/null; status $B $A)" "blocked:by-first"
ok "member rows flagged blocked for the UI" "$($PSQL -c "select bool_and(blocked) from public.conversation_members where conversation_id='$CID'")" "t"
ok "history still readable by members" "$(as $A "select count(*) from public.messages where conversation_id='$CID'" | tail -1)" "2"
ok "B unblocks" "$(as $B "select public.bingo_unblock_member('$A')" | tail -1)" "none"
ok "after unblock a new request is needed" "$(post $A $CID 'after unblock' | has 'row-level security')" "1"
ok "block with no prior relationship works (C blocks D)" "$(as $C "select public.bingo_block_member('$D')" | tail -1)" "blocked"
ok "D cannot request C" "$(as $D "select public.bingo_request_communication('$C')" | has 'blocked')" "1"

echo "== still closed from earlier files"
ok "C cannot self-join A-B" "$(as $C "insert into public.conversation_members(conversation_id,user_id) values ('$CID','$C')" | has 'permission denied')" "1"
ok "C cannot post into A-B" "$(post $C $CID x | has 'row-level security')" "1"
ok "no TRUNCATE on the requests table" "$(as $A "truncate public.bingo_communication_requests" | has 'permission denied')" "1"
ok "anon cannot read requests" "$(as anon "select count(*) from public.bingo_communication_requests" | has 'permission denied')" "1"
echo "RESULT: $pass passed, $fail failed"
