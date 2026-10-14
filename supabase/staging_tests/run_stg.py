# STAGING-ONLY test harness for supabase/migrations/20261014_bingo_topics_media_status_REVIEW_NOT_APPLIED.sql
# Runs against a throwaway local PostgreSQL 16 (never production). The auth/storage
# schemas are minimal stubs (00_stubs.sql); repo policies/helpers are extracted
# verbatim from supabase/bingo_change_public_wall_topics.sql and
# supabase/bingo_change2_super_user_security.sql (10_repo_before.sql).
# Setup: a cluster listening on PORT, socket dir H, superuser 'postgres', role
# 'service_role' with bypassrls is created by 00_stubs.sql. Adjust H and PORT.
import subprocess, os, sys, json
H="/home/pgtest/pg/sock"; PORT="5499"
def psql(sql, db="stg", user="postgres", check=False):
    args=["psql","-h",H,"-p",PORT,"-U",user,"-d",db,"-X","-q","-At","-v","ON_ERROR_STOP=1"]
    p=subprocess.run(args,input=sql,capture_output=True,text=True)
    if check and p.returncode: raise SystemExit("setup failed:\n"+p.stderr)
    return p
def run_file(name,db="stg"):
    return psql(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),name)).read(),db,check=True)
A="aaaaaaaa-0000-0000-0000-000000000001"; B="bbbbbbbb-0000-0000-0000-000000000002"
TL="a0000000-0000-0000-0000-000000000001"; TM="a0000000-0000-0000-0000-000000000002"
TP="a0000000-0000-0000-0000-000000000003"; TO="a0000000-0000-0000-0000-000000000004"; TB="b0000000-0000-0000-0000-000000000005"
def as_role(role,uid,body):
    s="BEGIN;\n"
    if role!="postgres": s+=f"SET LOCAL ROLE {role};\n"
    if uid: s+=f"SELECT set_config('request.jwt.claim.sub','{uid}',true);\n"
    s+=body+"\nROLLBACK;\n"
    return s
def value(name,role,uid,expr,expect=True):
    stmt = (expr.strip().rstrip(";")+";") if expr.strip().lower().startswith(("with","select")) else f"SELECT ({expr});"
    p=psql(as_role(role,uid,stmt),check=False)
    out=p.stdout.strip().splitlines()
    got=out[-1] if out else ""
    ok = (got=="t") if expect is True else (got==str(expect))
    return (name, ok, f"got={got!r} rc={p.returncode} err={p.stderr.strip()[:200]}")
def script(name,role,uid,body):
    p=psql(as_role(role,uid,body),check=False)
    out=p.stdout.strip().splitlines(); got=out[-1] if out else ""
    return (name, p.returncode==0 and got=="t", f"got={got!r} rc={p.returncode} err={p.stderr.strip()[:200]}")
def expect_error(name,role,uid,body,needle):
    p=psql(as_role(role,uid,body),check=False)
    ok = p.returncode!=0 and needle in p.stderr
    return (name, ok, f"rc={p.returncode} err={p.stderr.strip()[-220:]}")
def fin(topic,media):
    return f"SELECT public.bingo_finalize_topic('{topic}','{media}'::jsonb);"
MEDIA_P=f'[{{"type":"video","path":"{A}/{TP}/1.webm","name":"1.webm","evil":"x"}}]'
tests=[]
tests.append(value("legacy_text_post_is_ready","postgres",None,f"select media_status='ready' from public.bingo_topics where id='{TL}'"))
tests.append(value("legacy_media_post_is_ready","postgres",None,f"select media_status='ready' from public.bingo_topics where id='{TM}'"))
tests.append(value("anon_sees_legacy_text_post","anon",None,f"select count(*)=1 from public.bingo_topics where id='{TL}'"))
tests.append(value("anon_sees_legacy_media_post","anon",None,f"select count(*)=1 from public.bingo_topics where id='{TM}'"))
tests.append(value("anon_cannot_see_pending_post","anon",None,f"select count(*)=0 from public.bingo_topics where id='{TP}'"))
tests.append(value("owner_sees_own_pending_post","authenticated",A,f"select count(*)=1 from public.bingo_topics where id='{TP}'"))
tests.append(value("other_user_cannot_see_pending_post","authenticated",B,f"select count(*)=0 from public.bingo_topics where id='{TP}'"))
tests.append(value("owner_direct_media_status_write_reverted","authenticated",A,f"with u as (update public.bingo_topics set media_status='ready' where id='{TP}' returning media_status) select media_status='pending' from u"))
tests.append(value("owner_moderation_change_still_reverted","authenticated",A,f"with u as (update public.bingo_topics set moderation_status='hidden' where id='{TL}' returning moderation_status) select moderation_status='visible' from u"))
tests.append(value("new_text_only_post_defaults_ready","authenticated",A,"with ins as (insert into public.bingo_topics(user_id,body) values ('aaaaaaaa-0000-0000-0000-000000000001','new text post') returning media_status) select media_status='ready' from ins"))
tests.append(value("finalize_ready_and_media_normalised","authenticated",A,f"select (r).media_status='ready' and jsonb_array_length((r).media)=1 from (select public.bingo_finalize_topic('{TP}','{MEDIA_P}'::jsonb) r) q"))
tests.append(value("finalize_drops_unknown_keys","authenticated",A,f"select not ((r).media->0 ? 'evil') from (select public.bingo_finalize_topic('{TP}','{MEDIA_P}'::jsonb) r) q"))
tests.append(script("finalized_post_visible_to_anon","authenticated",A,f"select public.bingo_finalize_topic('{TP}','{MEDIA_P}'::jsonb); set local role anon; select count(*)=1 from public.bingo_topics where id='{TP}';"))
tests.append(script("finalize_is_idempotent","authenticated",A,f"select public.bingo_finalize_topic('{TP}','{MEDIA_P}'::jsonb); select (public.bingo_finalize_topic('{TP}','{MEDIA_P}'::jsonb)).media_status='ready';"))
tests.append(value("storage_pending_media_hidden_from_other_user","authenticated",B,f"select count(*)=0 from storage.objects where name='{A}/{TP}/1.webm'"))
tests.append(script("storage_media_readable_by_other_after_finalize","postgres",None,f"select set_config('bingo.finalize_topic','on',true); update public.bingo_topics set media_status='ready' where id='{TP}'; set local role authenticated; select set_config('request.jwt.claim.sub','{B}',true); select count(*)=1 from storage.objects where name='{A}/{TP}/1.webm';"))
tests.append(expect_error("finalize_by_other_user_denied","authenticated",B,fin(TP,MEDIA_P),"topic not found"))
tests.append(expect_error("finalize_path_in_other_folder_denied","authenticated",A,fin(TP,f'[{{"type":"video","path":"{B}/{TB}/1.webm","name":"x"}}]'),"not inside this topic folder"))
tests.append(expect_error("finalize_path_traversal_denied","authenticated",A,fin(TP,f'[{{"type":"video","path":"{A}/{TP}/../../{B}/{TB}/1.webm","name":"x"}}]'),"not inside this topic folder"))
tests.append(expect_error("finalize_missing_object_denied","authenticated",A,fin(TP,f'[{{"type":"video","path":"{A}/{TP}/nope.webm","name":"x"}}]'),"not found in storage"))
tests.append(expect_error("finalize_empty_object_denied","authenticated",A,fin(TP,f'[{{"type":"video","path":"{A}/{TP}/empty.webm","name":"x"}}]'),"is empty"))
tests.append(expect_error("finalize_expired_post_denied","authenticated",A,fin(TO,f'[{{"type":"video","path":"{A}/{TO}/1.webm","name":"x"}}]'),"expired"))
tests.append(expect_error("finalize_invalid_type_denied","authenticated",A,fin(TP,f'[{{"type":"audio","path":"{A}/{TP}/1.webm","name":"x"}}]'),"invalid media type"))
tests.append(expect_error("finalize_anonymous_denied","anon",None,fin(TP,MEDIA_P),"permission denied"))
tests.append(value("finalize_not_executable_by_anon","postgres",None,"select not has_function_privilege('anon','public.bingo_finalize_topic(uuid,jsonb)','execute')"))
tests.append(value("finalize_executable_by_authenticated","postgres",None,"select has_function_privilege('authenticated','public.bingo_finalize_topic(uuid,jsonb)','execute')"))
tests.append(value("abandoned_list_contains_old_only","service_role",None,f"select exists(select 1 from public.bingo_abandoned_topic_uploads() where topic_id='{TO}') and not exists(select 1 from public.bingo_abandoned_topic_uploads() where topic_id='{TP}')"))
tests.append(expect_error("abandoned_list_denied_to_users","authenticated",A,"select count(*) from public.bingo_abandoned_topic_uploads()","permission denied"))
tests.append(value("delete_fresh_pending_refused","service_role",None,f"select public.bingo_delete_abandoned_topic('{TP}')=false"))
tests.append(script("delete_old_pending_allowed","service_role",None,f"select public.bingo_delete_abandoned_topic('{TO}'); select not exists(select 1 from public.bingo_topics where id='{TO}');"))
tests.append(value("client_update_without_rpc_leaves_pending","authenticated",A,f"with u as (update public.bingo_topics set media='{MEDIA_P}'::jsonb where id='{TP}' returning media_status) select media_status='pending' from u"))
tests.append(value("owner_can_delete_own_pending","authenticated",A,f"with d as (delete from public.bingo_topics where id='{TP}' returning 1) select count(*)=1 from d"))
psql("drop database if exists stg;\ncreate database stg;\n",db="postgres",check=True)
run_file("00_stubs.sql"); run_file("05_table.sql"); run_file("10_repo_before.sql")
run_file("20_fixtures.sql")
mig=psql(open("/home/claude/bingo-app/supabase/migrations/20261014_bingo_topics_media_status_REVIEW_NOT_APPLIED.sql").read())
print("migration rc:",mig.returncode, mig.stderr.strip()[:400])
run_file("30_post_fixtures.sql")
res=[]
for t in tests:
    res.append(t)
for name,ok,detail in res:
    print(("PASS " if ok else "FAIL ")+name+("" if ok else "  "+detail))
print("PASS",sum(1 for r in res if r[1]),"of",len(res))
