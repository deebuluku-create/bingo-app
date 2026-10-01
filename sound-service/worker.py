#!/usr/bin/env python3
"""Trusted Bingo sound queue consumer. Requires Python 3.11+, FFmpeg/Chromaprint.
Run OUTSIDE the public webroot with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
Never put the service key in HTML or git. Singleton claim prevents credit races.
"""
import threading,datetime,os,json,time,tempfile,subprocess,hashlib,struct,uuid,urllib.request,urllib.parse
from pathlib import Path
URL=os.environ.get('SUPABASE_URL','').rstrip('/')
KEY=os.environ.get('SUPABASE_SERVICE_ROLE_KEY','')
MAX=75*1024*1024

def request(path,data=None,method=None,mime='application/json'):
 req=urllib.request.Request(URL+path,data=data,method=method,headers={'apikey':KEY,'Authorization':'Bearer '+KEY,'Content-Type':mime,'Prefer':'return=representation'})
 with urllib.request.urlopen(req,timeout=60) as r:
  raw=r.read(MAX+1)
  if len(raw)>MAX:raise ValueError('Media exceeds 75 MB limit')
  return json.loads(raw) if 'json' in r.headers.get('Content-Type','') else raw

def rpc(name,args={}):return request('/rest/v1/rpc/'+name,json.dumps(args).encode(),'POST')
def table(name,query=''):return request('/rest/v1/'+name+query)
def update(name,id,values):return request('/rest/v1/'+name+'?id=eq.'+str(id),json.dumps(values).encode(),'PATCH')
def storage(bucket,path,data=None,mime='application/octet-stream'):
 return request('/storage/v1/object/'+bucket+'/'+urllib.parse.quote(path,safe='/'),data,'POST' if data is not None else 'GET',mime)
def run(args):
 p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=180)
 if p.returncode:raise ValueError(p.stderr.decode(errors='replace')[-800:])
 return p.stdout

def probe(path):return json.loads(run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
def similarity(a,b):
 if min(len(a),len(b))<20:return 0
 best=0
 for off in range(-min(80,len(b)-20),min(80,len(a)-20)+1):
  x=a[max(0,off):];y=b[max(0,-off):];n=min(len(x),len(y))
  if n>=20 and n/min(len(a),len(b))>=.75:best=max(best,1-sum((x[i]^y[i]).bit_count() for i in range(n))/(32*n))
 return best

def process(job):
 with tempfile.TemporaryDirectory() as folder:
  root=Path(folder)
  if job['kind']=='recognise':
   source=table('bingo_topics','?id=eq.'+job['source_topic_id'])[0]
   if source['moderation_status']!='visible':raise ValueError('Original source is no longer public')
   item=next(m for m in source['media'] if m.get('type')=='video' and m.get('path'))
   inp=root/'source.bin';inp.write_bytes(storage('topic-media',item['path']))
   info=probe(inp);duration=float(info['format'].get('duration',0))
   if not 0<duration<=180:raise ValueError('Sound must be between 0 and 180 seconds')
   pcm=run(['ffmpeg','-v','error','-i',str(inp),'-map','0:a:0','-ac','1','-ar','11025','-f','s16le','pipe:1'])
   if not pcm:raise ValueError('No decodable soundtrack found')
   digest=hashlib.sha256(pcm).hexdigest()
   raw=run(['ffmpeg','-v','error','-i',str(inp),'-map','0:a:0','-ac','1','-ar','11025','-f','chromaprint','-fp_format','raw','pipe:1'])
   fp=list(struct.unpack('<'+'I'*(len(raw)//4),raw))
   sounds=table('bingo_sounds','?select=*&order=created_at.asc&limit=10001')
   if len(sounds)>10000:raise ValueError('Recognition index capacity requires review; no credit assigned')
   exact=next((s for s in sounds if s['pcm_hash']==digest),None)
   matches=sorted([(similarity(fp,s['fingerprint']),s) for s in sounds],key=lambda a:-a[0])
   near=[s for score,s in matches if score>=.96]
   if exact:sound=exact
   elif len(near)==1:sound=near[0]
   elif len(near)>1 or len(fp)<20 or (matches and matches[0][0]>=.80):
    update('bingo_sound_jobs',job['id'],{'state':'review','error':'Sound recognition needs review; no new credit accepted'});return
   else:
    sid=str(uuid.uuid4());out=root/'sound.m4a'
    run(['ffmpeg','-v','error','-i',str(inp),'-map','0:a:0','-vn','-c:a','aac','-b:a','160k',str(out)])
    storage('sound-audio',sid+'.m4a',out.read_bytes(),'audio/mp4')
    sound=request('/rest/v1/bingo_sounds',json.dumps({'id':sid,'original_uploader_id':source['user_id'],'source_topic_id':source['id'],'title':('Original sound · '+source['title'])[:80],'pcm_hash':digest,'fingerprint':fp,'duration':duration,'audio_path':sid+'.m4a'}).encode(),'POST')[0]
   update('bingo_topics',source['id'],{'sound_id':sound['id']})
   update('bingo_sound_jobs',job['id'],{'state':'ready','sound_id':sound['id']})
  else:
   sound=table('bingo_sounds','?id=eq.'+job['sound_id'])[0]
   source=table('bingo_topics','?id=eq.'+sound['source_topic_id'])[0]
   if source['moderation_status']!='visible':raise ValueError('Selected sound is no longer available')
   inp=root/'input';inp.write_bytes(storage('sound-inputs',job['input_path']))
   audio=root/'audio.m4a';audio.write_bytes(storage('sound-audio',sound['audio_path']))
   info=probe(inp);fmt=info['format'].get('format_name','');image='image2' in fmt or fmt in ('png_pipe','jpeg_pipe','webp_pipe')
   if not any(s['codec_type']=='video' for s in info['streams']):raise ValueError('Input must be a photo or video')
   duration=8 if image else float(info['format'].get('duration',0))
   if not 0<duration<=180:raise ValueError('Video must be at most 180 seconds')
   out=root/'output.mp4'
   run(['ffmpeg','-v','error']+(['-loop','1'] if image else [])+['-i',str(inp),'-stream_loop','-1','-i',str(audio),'-map','0:v:0','-map','1:a:0','-t',str(duration),'-vf',"scale=w='min(1280,iw)':h='min(1280,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p",'-r','30','-c:v','libx264','-preset','veryfast','-c:a','aac','-movflags','+faststart',str(out)])
   path=job['user_id']+'/'+job['id']+'/output.mp4';storage('sound-inputs',path,out.read_bytes(),'video/mp4')
   update('bingo_sound_jobs',job['id'],{'state':'ready','output_path':path})

if __name__=='__main__':
 if not URL.startswith('https://') or not KEY:raise SystemExit('Set the trusted worker Supabase URL and service-role key outside the website')
 def heartbeat():
  while True:
   try:update('bingo_sound_processor','true',{'heartbeat':datetime.datetime.now(datetime.timezone.utc).isoformat()})
   except Exception:pass
   time.sleep(20)
 threading.Thread(target=heartbeat,daemon=True).start()
 print('Bingo sound worker started',flush=True)
 while True:
  try:
   jobs=rpc('bingo_claim_sound_job')
   if jobs:
    job=jobs[0]
    try:process(job)
    except Exception as e:update('bingo_sound_jobs',job['id'],{'state':'failed','error':str(e)[:1000]})
   else:time.sleep(5)
  except Exception as e:print('Queue unavailable:',str(e),flush=True);time.sleep(10)
