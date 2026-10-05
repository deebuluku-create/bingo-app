/* Bingo Live+ · Weekly Crown Targets · Context Guide — surgical add-on (05 Oct 2026, BINGO 4107).
   No master HTML edits. Backend: supabase/migrations/20261005_bingo_voice_live_crown_targets.sql
   (who may go live, speak, invite, mute, remove and end is enforced there).

   ONE Live+ state machine, three modes:
     voice     audio-first room on a live post the host creates (mic + waveform stage)
     video     camera broadcast on a live post the host creates (Flip / Dual Cam / Mic)
     on_video  voice over the owner's own uploaded video — the SAME player keeps playing,
               original sound on / reduced / muted
   Transport: host-star WebRTC. Listeners receive one stream from the host; approved speakers send
   their mic to the host only after the host redeems their one-time backend ticket. Host control
   messages are signed (ECDSA P-256, public key stored on the session) and verified by listeners.
   Clean screen: LIVE · listeners · Mic · Crown · comments · ⚙ Live Setup · End. Everything else
   lives in the Live tools flap or Live Setup; every temporary panel closes on an outside tap and
   that tap is consumed. */
(function(){'use strict';
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05: no-op marker to retrigger the established Git-connected deployment after Live+ update. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_1003_EAT: same established branch route; served asset hash changes without rewriting the verified master. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_HOME_STABILITY: retrigger Git-connected preview after surgical Home render/media repair. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_CATEGORIES_DIRECT: publish retired Auto Market route -> Categories repair. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_SINGLE_TEXT_STAGE1: publish one-post-text repair and 10-crown Stage 1 style entitlement. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_WALL_LIGHT: publish white/orange Bingo Wall theme; Home feed untouched. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_WALL_BLANK_FIX: publish scoped Wall shell repair after white blank regression. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_WALL_REFERENCE_PALETTE: publish approved white/light-gray/navy/gold Wall palette; geometry unchanged. */
/* BINGO_GITHUB_DEPLOY_PULSE_2026_10_05_WALL_PREMIUM_FINISH: publish full approved premium Wall skin; layout/functions unchanged. */
if(window.BingoVoiceLive)return;
const W=window,D=document;
const S=()=>W.state||{};
const me=()=>String(S().user?.id||'');
const client=()=>{try{return typeof sb!=='undefined'&&sb?sb:null}catch(e){return null}};
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=n=>Number(n||0).toLocaleString('en-KE');
const short=n=>{n=Number(n||0);return n>=1e6?(n/1e6).toFixed(1).replace(/\.0$/,'')+'M':n>=1e3?(n/1e3).toFixed(1).replace(/\.0$/,'')+'K':String(n)};
const say=(m,k)=>{try{if(typeof toast==='function')toast(m,k)}catch(e){}};
const uuid=()=>{try{return crypto.randomUUID()}catch(e){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16)})}};
const missingFn=e=>/PGRST202|42883|Could not find the function|does not exist/i.test(String(e?.code||'')+' '+String(e?.message||e||''));
async function rpc(fn,args){const c=client();if(!c)throw new Error('No live connection');const {data,error}=await c.rpc(fn,args||{});if(error)throw error;return data}
const lsGet=(k,d)=>{try{const v=localStorage.getItem(k);return v?JSON.parse(v):d}catch(e){return d}};
const lsSet=(k,v)=>{try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}};
const ssGet=(k,d)=>{try{const v=sessionStorage.getItem(k);return v?JSON.parse(v):d}catch(e){return d}};
const ssSet=(k,v)=>{try{if(v==null)sessionStorage.removeItem(k);else sessionStorage.setItem(k,JSON.stringify(v))}catch(e){}};
const MODE_NAME={voice:'Voice Live',video:'Video Live',on_video:'Live on My Video'};
const VOL={on:1,ducked:0.25,muted:0};

/* ------------------------------------------------------------------ icons (white line glyphs) + 3D crowns */
const ICON={
 mic:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
 micOff:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 11.5 5.3M12 18v3M3 3l18 18"/></svg>',
 flip:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 12a8 8 0 0 1 13.7-5.6L20 9M20 4v5h-5M20 12a8 8 0 0 1-13.7 5.6L4 15M4 20v-5h5"/></svg>',
 dual:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="13" height="13" rx="2"/><rect x="9" y="9" width="12" height="12" rx="2"/></svg>',
 gear:'<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3.2"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/></svg>',
 x:'<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
 eye:'<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
 send:'<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M3 20.5 21 12 3 3.5l.01 6.6L15 12 3.01 13.9z"/></svg>',
 sound:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/></svg>',
 invite:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10" cy="8" r="4"/><path d="M2.5 20a7.5 7.5 0 0 1 15 0M19 8v6M16 11h6"/></svg>',
 people:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><circle cx="17" cy="9" r="2.6"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M15 14.5a5 5 0 0 1 6.5 5"/></svg>',
 more:'<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><circle cx="5" cy="12" r="2.2"/><circle cx="12" cy="12" r="2.2"/><circle cx="19" cy="12" r="2.2"/></svg>',
 end:'<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M12 9c-3.6 0-7 1.1-9.3 3.1-.6.5-.7 1.4-.2 2l1.4 1.6c.5.6 1.4.7 2 .3l2.2-1.5c.5-.3.7-.9.6-1.4l-.3-1.6c2.4-.8 4.9-.8 7.3 0l-.3 1.6c-.1.5.1 1.1.6 1.4l2.2 1.5c.6.4 1.5.3 2-.3l1.4-1.6c.5-.6.4-1.5-.2-2C19 10.1 15.6 9 12 9z"/></svg>',
 hand:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4a1.5 1.5 0 0 1 3 0v6M14 10V5.5a1.5 1.5 0 0 1 3 0V13M17 11a1.5 1.5 0 0 1 3 0v3a7 7 0 0 1-7 7h-1a6 6 0 0 1-5-2.7L4 14.5a1.5 1.5 0 0 1 2.4-1.8L8 14.5"/></svg>',
 chevron:'<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 15l6-6 6 6"/></svg>',
 cam:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><rect x="2.5" y="6" width="13" height="12" rx="2"/><path d="M15.5 10.5 21.5 7v10l-6-3.5"/></svg>',
 film:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M10 9l5 3-5 3z" fill="currentColor"/></svg>'
};
/* one crown silhouette; paid tiers get metallic gradients, specular highlights and a contact shadow */
const CROWN_DEFS='<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false"><defs>'+
 [['B',['#ffe1c2','#f0a065','#b5602a','#6b3010','#3d1a07','#c97a3f']],['S',['#ffffff','#eef1f5','#b9c0c9','#6c747e','#2f353c','#cfd5dc']],['G',['#fff8cf','#ffe066','#f2b417','#a86a00','#5c3a00','#ffd23a']]].map(([k,c])=>
 '<linearGradient id="bvlCr'+k+'" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="'+c[0]+'"/><stop offset=".22" stop-color="'+c[1]+'"/><stop offset=".55" stop-color="'+c[2]+'"/><stop offset=".82" stop-color="'+c[3]+'"/><stop offset="1" stop-color="'+c[4]+'"/></linearGradient>'+
 '<linearGradient id="bvlCrBand'+k+'" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="'+c[3]+'"/><stop offset=".3" stop-color="'+c[5]+'"/><stop offset=".5" stop-color="'+c[0]+'"/><stop offset=".72" stop-color="'+c[2]+'"/><stop offset="1" stop-color="'+c[4]+'"/></linearGradient>'+
 '<radialGradient id="bvlCrBall'+k+'" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#fff"/><stop offset=".35" stop-color="'+c[1]+'"/><stop offset="1" stop-color="'+c[4]+'"/></radialGradient>').join('')+
 '<radialGradient id="bvlJewel" cx=".35" cy=".3" r=".9"><stop offset="0" stop-color="#ff8a95"/><stop offset=".45" stop-color="#d1121f"/><stop offset="1" stop-color="#5a0008"/></radialGradient></defs></svg>';
function crownSVG(tier,size){size=size||34;const h=Math.round(size*.82);
 if(tier==='normal')return '<svg class="bvl-crown bvl-crown-normal" width="'+size+'" height="'+h+'" viewBox="0 0 64 52" aria-hidden="true"><path d="M7 19l11.5 12L32 9l13.5 22L57 19l-5 24H12z" fill="#ffc928"/><rect x="12" y="41" width="40" height="7" rx="3" fill="#ffb800"/><circle cx="7" cy="17" r="4" fill="#ffc928"/><circle cx="32" cy="7" r="4.4" fill="#ffc928"/><circle cx="57" cy="17" r="4" fill="#ffc928"/></svg>';
 const k={bronze:'B',silver:'S',gold:'G'}[tier];
 return '<svg class="bvl-crown bvl-crown-'+tier+'" width="'+size+'" height="'+h+'" viewBox="0 0 64 52" aria-hidden="true">'+
  '<ellipse cx="32" cy="50" rx="21" ry="2.2" fill="rgba(0,0,0,.45)"/>'+
  '<path d="M7 19l11.5 12L32 9l13.5 22L57 19l-5 24H12z" fill="url(#bvlCr'+k+')" stroke="rgba(0,0,0,.35)" stroke-width=".8"/>'+
  '<path d="M9.5 21.5 18 30.5 32 12l1 2.6-14.4 18.6L11 24z" fill="rgba(255,255,255,.55)"/>'+
  '<path d="M33.5 13.5 45.5 31 55 21.5l-.6 3-9 8.6z" fill="rgba(255,255,255,.22)"/>'+
  '<rect x="11.5" y="40" width="41" height="8.5" rx="3.6" fill="url(#bvlCrBand'+k+')" stroke="rgba(0,0,0,.35)" stroke-width=".8"/>'+
  '<rect x="14" y="41.2" width="36" height="1.6" rx=".8" fill="rgba(255,255,255,.6)"/>'+
  (tier==='gold'?'<path d="M32 24.5l4.6 5.5-4.6 5.5-4.6-5.5z" fill="url(#bvlJewel)"/><circle cx="20" cy="44.3" r="1.9" fill="url(#bvlJewel)"/><circle cx="44" cy="44.3" r="1.9" fill="url(#bvlJewel)"/>':'')+
  '<circle cx="7" cy="17" r="4.2" fill="url(#bvlCrBall'+k+')"/><circle cx="32" cy="7" r="4.7" fill="url(#bvlCrBall'+k+')"/><circle cx="57" cy="17" r="4.2" fill="url(#bvlCrBall'+k+')"/></svg>'}
const TIERS={normal:{label:'Normal Crown',note:'Send a free Crown to show support'},bronze:{name:'Bronze Crown',note:'Send a Bronze Crown'},silver:{name:'Silver Crown',note:'Send a Silver Crown'},gold:{name:'Gold Crown',note:'Send a Gold Crown'}};
const tierPrice=t=>{try{return W.BingoPaidCrowns?.tiers?.[t]?.amount||({bronze:5,silver:25,gold:50})[t]}catch(e){return ({bronze:5,silver:25,gold:50})[t]}};

/* ------------------------------------------------------------------ styles */
const css=D.createElement('style');css.id='bingoLivePlusCss';css.textContent=`
#bvlRoot{position:fixed;left:0;top:0;width:0;height:0;z-index:2147482990;pointer-events:none;font:13px/1.25 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff;--gold:#ffc928;--glass:rgba(6,12,24,.62);--glass2:rgba(8,16,30,.86)}
#bvlRoot[hidden],#bvlRoot [hidden],#bvlModal[hidden],#bvlModal [hidden],#bingoGuide[hidden],#bvlBanner[hidden],#bvlReturn[hidden]{display:none!important}
#bvlRoot .bvl-pe,#bvlRoot button,#bvlRoot input{pointer-events:auto}
#bvlRoot button:not(#bingo-flat-guard),#bvlModal button:not(#bingo-flat-guard),#bingoGuide button:not(#bingo-flat-guard),#bvlBanner button:not(#bingo-flat-guard),#bvlReturn:not(#bingo-flat-guard),.bct-card button:not(#bingo-flat-guard){font:inherit!important;font-weight:800!important;letter-spacing:0!important;text-transform:none!important;min-height:0!important;margin:0!important;cursor:pointer;-webkit-tap-highlight-color:transparent}
#auto-arcade-widget.bvl-on-air .bingo-rc-lane{display:none!important}
#bvlRoot .bvl-catch{position:fixed;inset:0;pointer-events:auto;z-index:1;background:transparent}
.bvl-head{position:absolute;left:10px;top:var(--bvl-head-top,12px);right:150px;display:flex;flex-direction:column;gap:5px;z-index:2}
.bvl-head-row{display:flex;align-items:center;gap:6px;flex-wrap:wrap}
.bvl-ava{width:30px;height:30px;border-radius:50%;object-fit:cover;border:1.5px solid var(--gold);background:#13233a;flex:none}
.bvl-live{display:inline-flex;align-items:center;padding:3px 10px;border-radius:999px;background:#ff1f3d;font-weight:900;font-size:12px;letter-spacing:.06em;box-shadow:0 0 10px rgba(255,31,61,.55)}
.bvl-pill{display:inline-flex;align-items:center;gap:5px;padding:3px 9px;border-radius:999px;background:var(--glass);border:1px solid rgba(255,255,255,.14);font-weight:800;font-size:12px;white-space:nowrap}
.bvl-name{font-weight:800;font-size:12.5px;text-shadow:0 1px 3px #000;max-width:46vw;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#bvlRoot .bvl-meter:not(#bingo-flat-guard){border:1px solid rgba(255,201,40,.55)!important;color:#ffe28a!important;background:var(--glass)!important;padding:3px 9px!important;border-radius:999px!important;font-size:11.5px!important}
#bvlRoot .bvl-meter.hit:not(#bingo-flat-guard){background:var(--gold)!important;color:#071323!important}
.bvl-tr{position:absolute;top:12px;right:66px;display:flex;gap:6px;z-index:2}
#bvlRoot .bvl-sq:not(#bingo-flat-guard){width:36px!important;height:36px!important;padding:0!important;display:grid!important;place-items:center;border-radius:11px!important;background:var(--glass2)!important;border:1px solid var(--gold)!important;color:#fff!important;box-shadow:0 0 8px rgba(255,201,40,.22)!important}
.bvl-rail{position:absolute;right:10px;top:156px;display:flex;flex-direction:column;align-items:center;gap:9px;z-index:2}
#bvlRoot .bvl-rb:not(#bingo-flat-guard){width:54px!important;min-height:54px!important;padding:6px 2px 5px!important;display:flex!important;flex-direction:column;align-items:center;justify-content:center;gap:2px;border-radius:14px!important;background:var(--glass2)!important;border:1.5px solid var(--gold)!important;color:#fff!important;font-size:10.5px!important;box-shadow:0 0 9px rgba(255,201,40,.25),inset 0 1px 0 rgba(255,255,255,.08)!important}
#bvlRoot .bvl-rb.off:not(#bingo-flat-guard){border-color:#ff4d6d!important;box-shadow:0 0 9px rgba(255,77,109,.35)!important}
#bvlRoot .bvl-rb.on:not(#bingo-flat-guard){border-color:#3be15e!important;box-shadow:0 0 10px rgba(59,225,94,.4)!important}
.bvl-stage{position:absolute;inset:0;overflow:hidden;background:radial-gradient(120% 80% at 50% 30%,#13284a 0%,#071224 55%,#030810 100%);pointer-events:none}
#auto-arcade-widget .aa360-item .bvl-stage video{position:absolute!important;inset:0!important;display:block!important;width:100%!important;height:100%!important;max-height:none!important;object-fit:cover!important;background:#000!important;border-radius:0!important}
#auto-arcade-widget .aa360-item .bvl-stage video[hidden],#auto-arcade-widget .aa360-item .bvl-stage [hidden]{display:none!important}
#auto-arcade-widget .aa360-item .bvl-stage video.mirror{transform:scaleX(-1)}
#auto-arcade-widget .aa360-item .bvl-stage video.bvl-pip{inset:auto!important;left:12px!important;top:96px!important;width:28%!important;height:auto!important;aspect-ratio:3/4;border-radius:12px!important;border:1.5px solid #ffc928;box-shadow:0 6px 18px rgba(0,0,0,.6)}
.bvl-voice{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;color:#fff;transform:translateY(-6%)}
.bvl-voice-mic{width:96px;height:96px;border-radius:50%;display:grid;place-items:center;border:2px solid rgba(255,255,255,.85);box-shadow:0 0 24px rgba(43,198,229,.45),inset 0 0 18px rgba(43,198,229,.25)}
.bvl-voice-mic svg{width:44px;height:44px}
.bvl-wave{display:flex;align-items:center;gap:3px;height:44px}
.bvl-wave i{width:4px;height:8px;border-radius:3px;background:linear-gradient(#7de8ff,#2b8cff);opacity:.85}
.bvl-stage.on .bvl-wave i{animation:bvlWave 1s ease-in-out infinite}
.bvl-wave i:nth-child(3n){animation-delay:.15s!important}.bvl-wave i:nth-child(3n+1){animation-delay:.32s!important}.bvl-wave i:nth-child(4n){animation-delay:.5s!important}
@keyframes bvlWave{50%{height:40px}}
.bvl-voice b{font-size:16px}.bvl-voice small{color:#9fb3cf;font-weight:700;letter-spacing:.06em;text-transform:uppercase;font-size:11px}
.bvl-audio-only{position:absolute;left:50%;top:44%;transform:translate(-50%,-50%);padding:8px 12px;border-radius:12px;background:var(--glass2,rgba(8,16,30,.86));font-weight:800;font-size:12px}
.bvl-dock{position:absolute;left:10px;right:76px;bottom:var(--bvl-dock,180px);display:flex;flex-direction:column;align-items:stretch;gap:6px;z-index:2}
.bvl-lane{display:flex;flex-direction:column;justify-content:flex-end;gap:8px;max-height:min(38vh,320px);overflow:hidden;pointer-events:none;-webkit-mask-image:linear-gradient(to top,#000 70%,transparent);mask-image:linear-gradient(to top,#000 70%,transparent)}
.bvl-c{display:flex;align-items:flex-start;gap:8px;max-width:100%;animation:bvlRise var(--life,9s) linear forwards;text-shadow:0 1px 3px rgba(0,0,0,.85)}
.bvl-c img{width:26px;height:26px;border-radius:50%;object-fit:cover;background:#13233a;flex:none;border:1px solid rgba(255,255,255,.4)}
.bvl-c .bvl-cb{min-width:0}
.bvl-c .bvl-cn{font-weight:800;font-size:12.5px;color:#cfe3ff}.bvl-c .bvl-ct{font-size:11px;color:#9fb0c6;margin-left:6px;font-weight:600}
.bvl-c .bvl-cx{font-size:15.5px;line-height:1.3;word-break:break-word}
.bvl-c.host img{width:38px;height:38px;border:2px solid var(--gold);box-shadow:0 0 10px rgba(255,201,40,.55)}
.bvl-c.host .bvl-cn{color:#ffe28a;font-size:14px}
.bvl-c.host .bvl-cx{font-size:clamp(20px,6vw,25px);line-height:1.22}
.bvl-c.host .bvl-cb{padding-left:8px;border-left:2px solid rgba(255,201,40,.8)}
.bvl-host-tag{display:inline-block;margin-left:6px;padding:1px 6px;border-radius:6px;background:var(--gold);color:#071323;font-size:10px;font-weight:900;letter-spacing:.06em;vertical-align:1px;text-shadow:none}
@keyframes bvlRise{0%{opacity:0;transform:translateY(14px)}6%{opacity:1;transform:translateY(0)}78%{opacity:1}100%{opacity:0;transform:translateY(-46px)}}
.bvl-flap-row{display:flex;justify-content:center}
#bvlRoot .bvl-flap:not(#bingo-flat-guard){display:inline-flex!important;align-items:center;gap:5px;padding:3px 14px!important;border-radius:12px 12px 6px 6px!important;background:var(--glass2)!important;border:1px solid rgba(255,201,40,.7)!important;color:#ffe28a!important;font-size:11px!important;box-shadow:0 0 8px rgba(255,201,40,.2)!important}
#bvlRoot .bvl-flap.open svg{transform:rotate(180deg)}
.bvl-tray{position:relative;z-index:3;display:flex;justify-content:space-between;gap:4px;padding:10px 8px 8px;border-radius:18px;background:var(--glass2);border:1px solid rgba(255,201,40,.75);box-shadow:0 0 14px rgba(255,201,40,.18);animation:bvlUp .18s ease-out}
@keyframes bvlUp{from{opacity:0;transform:translateY(10px)}}
#bvlRoot .bvl-tb:not(#bingo-flat-guard){display:flex!important;flex-direction:column;align-items:center;gap:4px;background:none!important;border:0!important;padding:0!important;color:#fff!important;font-size:10px!important;flex:1;min-width:0}
.bvl-tb i{width:42px;height:42px;border-radius:50%;display:grid;place-items:center;font-style:normal;background:var(--c);box-shadow:0 0 10px var(--c),inset 0 2px 0 rgba(255,255,255,.28),inset 0 -3px 6px rgba(0,0,0,.3)}
.bvl-tb span{white-space:normal;text-align:center;line-height:1.1;font-size:9.5px;max-width:100%}
.bvl-tb.dim i{filter:saturate(.35) brightness(.7)}
.bvl-compose{display:flex;align-items:center;gap:6px}
.bvl-cap{flex:1;min-width:0;display:flex;align-items:center;gap:6px;padding:4px 5px 4px 4px;border-radius:999px;background:rgba(5,12,24,.72);border:1.5px solid #2bc6e5;box-shadow:0 0 10px rgba(43,198,229,.3)}
.bvl-cap img{width:28px;height:28px;border-radius:50%;object-fit:cover;background:#13233a;flex:none}
#bvlRoot .bvl-cap input{flex:1;min-width:0;border:0;outline:0;background:transparent;color:#fff;font-size:16px;line-height:1.2;padding:5px 2px;height:30px}
#bvlRoot .bvl-cap input::placeholder{color:#9fb0c6}
#bvlRoot .bvl-aa:not(#bingo-flat-guard){width:30px!important;height:30px!important;padding:0!important;border-radius:50%!important;border:1px solid rgba(255,255,255,.35)!important;background:transparent!important;color:#fff!important;font-size:12px!important}
#bvlRoot .bvl-send:not(#bingo-flat-guard){width:42px!important;height:42px!important;padding:0!important;display:grid!important;place-items:center;border-radius:13px!important;background:var(--glass2)!important;border:1.5px solid #2bc6e5!important;color:#fff!important;box-shadow:0 0 10px rgba(43,198,229,.35)!important}
#bvlRoot .bvl-chip:not(#bingo-flat-guard){border:1px solid #3b4d66!important;background:#0b192b!important;color:#fff!important;border-radius:999px!important;padding:6px 12px!important;font-size:12px!important;line-height:1.2!important}
#bvlRoot .bvl-chip.gold:not(#bingo-flat-guard){background:var(--gold)!important;border-color:var(--gold)!important;color:#071323!important}
.bvl-card{display:flex;flex-wrap:wrap;align-items:center;gap:7px 6px;max-width:100%;padding:9px 11px;border-radius:14px;background:var(--glass2);border:1px solid var(--gold);box-shadow:0 0 14px rgba(255,201,40,.22)}
.bvl-card b{flex:1 1 auto;font-size:13.5px}
.bvl-card .bvl-br{flex-basis:100%;height:0}
#bvlRoot .bvl-help:not(#bingo-flat-guard),#bvlModal .bvl-help:not(#bingo-flat-guard),.bct-card .bvl-help:not(#bingo-flat-guard){width:22px!important;height:22px!important;padding:0!important;border-radius:50%!important;border:1px solid #5c6c82!important;background:#0b192b!important;color:#cfe0ff!important;font-size:12px!important;line-height:20px!important;text-align:center}
.bvl-pop{position:absolute;right:74px;top:150px;z-index:3;width:min(272px,calc(100% - 96px));padding:8px;border-radius:16px;background:rgba(5,10,20,.94);border:1px solid var(--gold);box-shadow:0 0 18px rgba(255,201,40,.25),0 10px 30px rgba(0,0,0,.6);display:flex;flex-direction:column;gap:6px;animation:bvlUp .16s ease-out}
.bvl-cr{display:flex;align-items:center;gap:9px;padding:7px 8px;border-radius:12px;background:linear-gradient(180deg,#121b2b,#0a111d);border:1px solid #273449}
.bvl-cr.first{border-color:var(--gold);box-shadow:inset 0 0 12px rgba(255,201,40,.12)}
.bvl-cr .bvl-crown{flex:none}
.bvl-crown-bronze{filter:drop-shadow(0 2px 2px rgba(0,0,0,.6)) drop-shadow(0 0 5px rgba(224,128,60,.45))}
.bvl-crown-silver{filter:drop-shadow(0 2px 2px rgba(0,0,0,.6)) drop-shadow(0 0 4px rgba(200,225,255,.35))}
.bvl-crown-gold{filter:drop-shadow(0 2px 2px rgba(0,0,0,.6)) drop-shadow(0 0 8px rgba(255,196,0,.6))}
.bvl-crown-normal{filter:drop-shadow(0 0 4px rgba(255,201,40,.5))}
.bvl-cr div{flex:1;min-width:0}.bvl-cr b{display:block;font-size:13px}.bvl-cr small{display:block;color:#9fb0c6;font-size:10.5px;margin-top:2px}
.bvl-price{display:inline-block;margin-top:3px;padding:1px 8px;border-radius:999px;border:1px solid currentColor;font-size:11px;font-weight:900}
.bvl-cr.bronze .bvl-price{color:#f0a065}.bvl-cr.silver .bvl-price{color:#e6ebf1}.bvl-cr.gold .bvl-price{color:#ffd23a}
.bvl-cr.pick{animation:bvlSweep .6s ease-out}
@keyframes bvlSweep{40%{box-shadow:inset 0 0 22px rgba(255,255,255,.22),0 0 12px rgba(255,201,40,.4)}}
.bvl-pop-msg{font-size:11.5px;color:#cfe0ff;padding:2px 4px;min-height:14px}
.bvl-float{position:absolute;right:16px;bottom:var(--bvl-dock,180px);z-index:2;pointer-events:none;animation:bvlFloat 2.6s ease-out forwards}
@keyframes bvlFloat{0%{opacity:0;transform:translateY(0) scale(.6)}12%{opacity:1;transform:translateY(-20px) scale(1)}100%{opacity:0;transform:translateY(-260px) scale(1.05)}}
.bvl-sent{position:absolute;left:50%;top:40%;transform:translate(-50%,-50%);z-index:4;display:flex;flex-direction:column;align-items:center;gap:6px;padding:14px 18px;border-radius:16px;background:rgba(5,10,20,.9);border:1px solid var(--gold);font-weight:900}
.bvl-sent .bvl-spark{position:absolute;inset:-12px;pointer-events:none;background:radial-gradient(circle,#fff6 1px,transparent 2px) 0 0/22px 22px;animation:bvlSpark .9s ease-out forwards}
@keyframes bvlSpark{from{opacity:1;transform:scale(.8)}to{opacity:0;transform:scale(1.3)}}
#bvlModal{position:fixed;inset:0;z-index:2147483300;background:rgba(0,0,0,.42);display:flex;align-items:flex-end;justify-content:center;font:13px/1.3 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff}
#bvlModal .bvl-sheet{width:min(440px,100%);max-height:82vh;display:flex;flex-direction:column;background:linear-gradient(180deg,#0b1424,#060b15);border:1px solid #ffc928;border-bottom:0;border-radius:20px 20px 0 0;padding:14px 14px calc(14px + env(safe-area-inset-bottom,0px));box-shadow:0 -6px 30px rgba(0,0,0,.6),0 0 18px rgba(255,201,40,.15);animation:bvlUp .2s ease-out;box-sizing:border-box}
#bvlModal .bvl-dialog{margin:auto;width:min(360px,calc(100% - 32px));background:#071323;border:1px solid #ffc928;border-radius:18px;padding:16px;box-shadow:0 0 22px rgba(255,201,40,.2);box-sizing:border-box}
#bvlModal h3{margin:0 0 10px;font-size:16px;display:flex;justify-content:space-between;align-items:center;gap:8px}
#bvlModal h3 span{display:flex;align-items:center;gap:8px}
#bvlModal .bvl-x:not(#bingo-flat-guard){border:0!important;background:none!important;color:#fff!important;font-size:22px!important;padding:0 4px!important;line-height:1!important}
#bvlModal .bvl-scroll{overflow:auto;display:flex;flex-direction:column;gap:6px;min-height:40px}
#bvlModal input.bvl-search,#bvlModal input.bvl-field{width:100%;box-sizing:border-box;border:1px solid #3b4d66;background:#030b16;color:#fff;border-radius:12px;padding:9px 12px;font-size:16px;margin:2px 0 6px}
#bvlModal .bvl-sec{font-size:11px;color:#9caecc;text-transform:uppercase;letter-spacing:.06em;margin:8px 0 2px}
#bvlModal .bvl-row{display:flex;align-items:center;gap:9px;padding:6px 2px}
#bvlModal .bvl-row img{width:32px;height:32px;border-radius:50%;object-fit:cover;background:#13233a;flex:none}
#bvlModal .bvl-row span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:700}
#bvlModal .bvl-row small{color:#9caecc;font-weight:600}
#bvlModal .bvl-btn:not(#bingo-flat-guard){border:1px solid #3b4d66!important;background:#0b192b!important;color:#fff!important;border-radius:999px!important;padding:6px 12px!important;font-size:12px!important}
#bvlModal .bvl-btn.gold:not(#bingo-flat-guard){background:#ffc928!important;border-color:#ffc928!important;color:#071323!important}
#bvlModal .bvl-btn.red:not(#bingo-flat-guard){border-color:#ff2d55!important;color:#ffb3c1!important}
#bvlModal .bvl-btn.wide:not(#bingo-flat-guard){display:block!important;width:100%!important;padding:11px!important;font-size:14px!important;border-radius:14px!important;margin-top:8px!important}
#bvlModal .bvl-btn.endbig:not(#bingo-flat-guard){display:block!important;width:100%!important;padding:12px!important;font-size:15px!important;border-radius:999px!important;margin-top:10px!important;background:#ff1f3d!important;border-color:#ff1f3d!important;color:#fff!important;box-shadow:0 0 14px rgba(255,31,61,.45)!important}
#bvlModal .bvl-note{color:#9caecc;font-size:12px;margin:6px 0 0}
#bvlModal .bvl-empty{color:#9caecc;padding:10px 2px}
#bvlModal .bvl-seg{display:flex;gap:4px;padding:3px;border-radius:12px;background:#030b16;border:1px solid #273449}
#bvlModal .bvl-seg button:not(#bingo-flat-guard){flex:1!important;border:0!important;border-radius:9px!important;background:transparent!important;color:#cfd8e6!important;padding:8px 4px!important;font-size:12px!important}
#bvlModal .bvl-seg button.sel:not(#bingo-flat-guard){background:#ffc928!important;color:#071323!important}
#bvlModal .bvl-seg button[disabled]:not(#bingo-flat-guard){opacity:.45;cursor:not-allowed}
#bvlModal .bvl-acc{border:1px solid #1f2d42;border-radius:12px;background:#0a1322;overflow:hidden;flex:none}
#bvlModal .bvl-acc>button:not(#bingo-flat-guard){display:flex!important;width:100%!important;align-items:center;gap:10px;padding:11px 12px!important;border:0!important;background:transparent!important;color:#fff!important;font-size:13.5px!important;text-align:left}
#bvlModal .bvl-acc>button span{flex:1}
#bvlModal .bvl-acc-ic{width:22px;display:grid;place-items:center;font-style:normal;flex:none}
#bvlModal .bvl-acc>button svg:last-child{transform:rotate(180deg);transition:transform .15s}
#bvlModal .bvl-acc.open>button svg:last-child{transform:rotate(0)}
#bvlModal .bvl-acc-body{padding:2px 12px 12px;display:flex;flex-direction:column;gap:8px}
#bvlModal .bvl-line{display:flex;align-items:center;justify-content:space-between;gap:8px;font-size:12.5px;flex-wrap:wrap}
#bvlModal button.bvl-mode:not(#bingo-flat-guard){display:flex!important;align-items:center;gap:11px;width:100%!important;padding:11px!important;border-radius:14px!important;border:1px solid rgba(255,201,40,.55)!important;background:linear-gradient(180deg,#0f1a2c,#0a111e)!important;color:#fff!important;text-align:left;flex:none}
#bvlModal button.bvl-mode.sel:not(#bingo-flat-guard){border-color:#ffc928!important;box-shadow:0 0 14px rgba(255,201,40,.3)!important}
#bvlModal .bvl-mode i{width:42px;height:42px;border-radius:12px;display:grid;place-items:center;flex:none;background:#030b16;border:1px solid #2b3b50;font-style:normal}
#bvlModal .bvl-mode b{display:block;font-size:14px}#bvlModal .bvl-mode small{display:block;color:#9caecc;font-size:11.5px;margin-top:2px;font-weight:600}
#bingoGuide{position:fixed;inset:0;z-index:2147483400;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px;font:14px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff}
#bingoGuide .bg-card{position:relative;width:min(340px,100%);background:#071323;border:1px solid #ffc928;border-radius:18px;padding:16px 16px 14px;box-shadow:0 0 30px rgba(255,201,40,.18)}
#bingoGuide .bg-icon{font-size:28px;line-height:1}
#bingoGuide h4{margin:8px 0 6px;font-size:17px}
#bingoGuide p{margin:0;color:#d6e2f3;font-size:13.5px}
#bingoGuide .bg-x:not(#bingo-flat-guard){position:absolute!important;right:10px;top:8px;border:0!important;background:none!important;color:#fff!important;font-size:22px!important;padding:2px 6px!important;line-height:1!important}
#bingoGuide .bg-ok:not(#bingo-flat-guard){display:block!important;width:100%!important;margin-top:14px!important;padding:10px!important;border:1px solid #ffc928!important;background:#ffc928!important;color:#071323!important;border-radius:12px!important;font-size:14px!important}
#bvlBanner{position:fixed;left:50%;top:calc(10px + env(safe-area-inset-top,0px));transform:translateX(-50%);z-index:2147483350;max-width:calc(100% - 24px);display:flex;align-items:center;gap:8px;padding:8px 8px 8px 12px;border-radius:14px;background:#071323;border:1px solid #ffc928;color:#fff;font:700 13px/1.3 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.45)}
#bvlBanner.ready{border-color:#22c55e}
#bvlBanner button:not(#bingo-flat-guard){border:1px solid #3b4d66!important;background:#0b192b!important;color:#fff!important;border-radius:999px!important;padding:5px 10px!important;font-size:12px!important}
#bvlReturn:not(#bingo-flat-guard){position:fixed!important;right:12px;top:calc(64px + env(safe-area-inset-top,0px));z-index:2147483000;border:1px solid #ff1f3d!important;background:#ff1f3d!important;color:#fff!important;border-radius:999px!important;padding:6px 12px!important;font:800 12px system-ui,sans-serif!important}
.bct-card{background:var(--panel,#0b1324);border:1px solid rgba(245,185,30,.35);border-radius:14px;padding:12px 14px;margin-bottom:12px;color:#fff}
.bct-head{display:flex;align-items:center;justify-content:space-between;gap:8px;font-weight:900;font-size:14px}
.bct-ind{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;font-weight:900;font-size:12.5px;border:1px solid #3b4d66;color:#8ea0bb;background:#0b192b}
.bct-ind.pending{color:#ffd34e;border-color:#ffc928;background:rgba(255,201,40,.08)}
.bct-ind.available{color:#06240f;background:#22c55e;border-color:#22c55e}
.bct-line{margin-top:8px;font-size:12.5px;color:#d6e2f3}
.bct-track{height:8px;margin-top:6px;background:#050a16;border:1px solid #223248;border-radius:999px;overflow:hidden}
.bct-track span{display:block;height:100%;background:linear-gradient(90deg,#b8860b,#ffc928);border-radius:999px}
.bct-day{margin-top:6px;font-size:11.5px;color:#9caecc}
.bct-list{margin-top:8px;display:flex;flex-direction:column;gap:4px}
.bct-entry{display:flex;justify-content:space-between;gap:8px;font-size:12px;padding:5px 8px;border-radius:9px;background:#071323;border:1px solid #1d2c42}
.bct-entry.EARNED_PENDING b{color:#ffd34e}.bct-entry.AVAILABLE{border-color:#22c55e}.bct-entry.AVAILABLE b{color:#4ade80}.bct-entry.WITHDRAWN b,.bct-entry.WITHDRAWAL_PENDING b{color:#9caecc}
.bct-wd{display:flex;gap:6px;margin-top:8px}
.bct-wd input{flex:1;min-width:0;border:1px solid #3b4d66;background:#030b16;color:#fff;border-radius:10px;padding:8px 10px;font-size:16px}
.bct-card .bct-go:not(#bingo-flat-guard){border:1px solid #22c55e!important;background:#22c55e!important;color:#06240f!important;border-radius:10px!important;padding:8px 12px!important;font-size:13px!important}
.bct-note{margin-top:6px;font-size:11.5px;color:#9caecc}
`;D.head.appendChild(css);

/* ------------------------------------------------------------------ hosts (created once) */
const root=D.createElement('div');root.id='bvlRoot';root.hidden=true;
root.innerHTML='<div class="bvl-catch" hidden></div><div class="bvl-head"></div><div class="bvl-tr"></div><div class="bvl-rail"></div><div class="bvl-pop" hidden></div><div class="bvl-dock"><div class="bvl-lane" aria-live="polite"></div><div class="bvl-tray" hidden></div><div class="bvl-flap-row" hidden></div><div class="bvl-card bvl-pe bvl-prompt" hidden></div><div class="bvl-invite-slot"></div><div class="bvl-compose bvl-pe" hidden></div></div><div class="bvl-fx"></div><audio id="bvlAudio" autoplay playsinline></audio>'+CROWN_DEFS;
const modal=D.createElement('div');modal.id='bvlModal';modal.hidden=true;
const guideHost=D.createElement('div');guideHost.id='bingoGuide';guideHost.hidden=true;
const banner=D.createElement('div');banner.id='bvlBanner';banner.hidden=true;
const returnBtn=D.createElement('button');returnBtn.id='bvlReturn';returnBtn.type='button';returnBtn.hidden=true;returnBtn.textContent='● LIVE · Return';
function mountHosts(){if(root.isConnected)return;D.body.append(root,modal,guideHost,banner,returnBtn)}
const $=s=>root.querySelector(s);
const $p=()=>$('.bvl-prompt'),$head=()=>$('.bvl-head'),$tr=()=>$('.bvl-tr'),$rail=()=>$('.bvl-rail'),$pop=()=>$('.bvl-pop'),$lane=()=>$('.bvl-lane'),$tray=()=>$('.bvl-tray'),$flap=()=>$('.bvl-flap-row'),$comp=()=>$('.bvl-compose'),$inv=()=>$('.bvl-invite-slot'),$catch=()=>$('.bvl-catch'),$fx=()=>$('.bvl-fx'),$audio=()=>$('#bvlAudio');

/* ================================================================== CONTEXT GUIDE */
const GUIDES={
 voice_live_intro_v1:{icon:'🎙',title:'Bingo Live+',text:'Choose Voice Live, Video Live, or go live with your voice over one of your existing uploaded videos. Talk with viewers, invite speakers, receive Crowns and build your weekly Crown target.'},
 weekly_crown_target_intro_v1:{icon:'👑',title:'Weekly Crown Target',text:'Every 1,000 qualifying Crowns earns KSh 1,000. Passing the target automatically begins another target. Rewards remain pending until the applicable seven-day period is completed. GREEN means the money is ready for withdrawal.'},
 crown_wallet_intro_v1:{icon:'💰',title:'Crown Wallet',text:'Every completed 1,000 qualifying Crowns earns KSh 1,000. Pending rewards cannot yet be withdrawn. When a reward becomes available, its indicator turns GREEN.'},
 speaker_intro_v1:{icon:'✋',title:'Speak in a Live',text:'Tap Request to Speak. If the host accepts, turn on your mic to join the discussion as an audio speaker. You can mute, unmute or leave at any time.'},
 trending_intro_v1:{icon:'🔥',title:'Trending',text:'Genuine current activity—including watch time, Crowns, comments, shares and Live participation—can increase your post\'s distribution and help more people discover it.'}
};
const ACK_KEY='bingo_guide_acks_v1';
let acks=lsGet(ACK_KEY,{}),acksSyncedFor='';
async function syncAcks(){const uid=me(),c=client();if(!uid||!c||acksSyncedFor===uid)return;acksSyncedFor=uid;try{const {data,error}=await c.from('bingo_guide_acks').select('guide_key').eq('user_id',uid);if(!error&&Array.isArray(data)){data.forEach(r=>{acks[uid+':'+r.guide_key]=1});lsSet(ACK_KEY,acks)}}catch(e){}}
const ackId=k=>(me()||'guest')+':'+k;
const seen=k=>!!acks[ackId(k)];
function ack(k){acks[ackId(k)]=1;lsSet(ACK_KEY,acks);const uid=me(),c=client();if(uid&&c){try{c.from('bingo_guide_acks').insert({user_id:uid,guide_key:k}).then(()=>{},()=>{})}catch(e){}}}
let guideOpenKey=null,guideQueue=[],guideOk=null;
/* Guides appear when the member does the thing they explain (never pushed over the feed on their own).
   onOk runs only for "Got It"; X / outside tap / Escape simply close. */
function guideShow(k,force,onOk){const g=GUIDES[k];if(!g)return false;if(!force&&seen(k))return false;mountHosts();if(guideOpenKey){if(guideOpenKey!==k&&!guideQueue.includes(k))guideQueue.push(k);return true}
 guideOpenKey=k;guideOk=typeof onOk==='function'?onOk:null;guideHost.innerHTML='<div class="bg-card" role="dialog" aria-modal="true" aria-labelledby="bgTitle"><button type="button" class="bg-x" aria-label="Close">×</button><div class="bg-icon">'+g.icon+'</div><h4 id="bgTitle">'+esc(g.title)+'</h4><p>'+esc(g.text)+'</p><button type="button" class="bg-ok">Got It</button></div>';guideHost.hidden=false;return true}
function guideClose(ok){if(!guideOpenKey)return;ack(guideOpenKey);guideOpenKey=null;const cont=ok?guideOk:null;guideOk=null;guideHost.hidden=true;guideHost.innerHTML='';if(cont){try{cont()}catch(e){}}const next=guideQueue.shift();if(next)setTimeout(()=>guideShow(next),250)}
function firstExplain(k,run){if(seen(k))return run();if(!guideShow(k,false,run))run()}
guideHost.addEventListener('pointerdown',e=>e.stopPropagation());
guideHost.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();if(e.target.closest('.bg-ok'))guideClose(true);else if(e.target===guideHost||e.target.closest('.bg-x'))guideClose(false)});
D.addEventListener('keydown',e=>{if(e.key!=='Escape')return;if(guideOpenKey)guideClose(false);else if(!modal.hidden&&modal.dataset.kind!=='end')closeModal();else if(transient)closeTransient()});
const helpBtn=k=>'<button type="button" class="bvl-help" data-guide="'+k+'" aria-label="Help">?</button>';
D.addEventListener('click',e=>{const h=e.target.closest?.('[data-guide]');if(!h)return;e.preventDefault();e.stopPropagation();guideShow(h.dataset.guide,true)},true);

/* ================================================================== CAPABILITY + LIVE INDEX */
let cap={live:null};
const liveIndex=new Map();   /* topicId -> {session_id, host_id} */
function setLiveIndex(rows){liveIndex.clear();(rows||[]).forEach(r=>{if(r&&r.topic_id)liveIndex.set(String(r.topic_id),{session_id:String(r.session_id),host_id:String(r.host_id)})});if(live)liveIndex.set(String(live.topicId),{session_id:live.sid,host_id:live.hostId})}
let indexAt=0,indexBusy=false;
async function probeLive(){if(cap.live!==null)return cap.live;try{const rows=await rpc('bingo_voice_live_active',{p_limit:100});cap.live=Array.isArray(rows);setLiveIndex(rows);indexAt=Date.now();if(cap.live)setTimeout(discoverLivePosts,1500)}catch(e){cap.live=missingFn(e)?false:null}return cap.live}
/* Discovery is a light REST read (slide change at most every 15 s, and every 45 s on Home): no
   Realtime connection is opened for anyone not actually hosting or watching a Live. */
async function refreshIndex(){if(cap.live!==true||indexBusy)return;indexBusy=true;try{setLiveIndex(await rpc('bingo_voice_live_active',{p_limit:100}));indexAt=Date.now();discoverLivePosts();scheduleCheck()}catch(e){}finally{indexBusy=false}}
/* A Voice/Video Live started after this feed loaded is fetched by id and placed right AFTER the slide the
   viewer is on (never above it, so nothing shifts under them); the next swipe meets the Live. */
const livePlacement=new Map();   /* topicId -> feed item id it follows */
let discovering=false;
async function discoverLivePosts(){const c=client();if(!c||discovering||!Array.isArray(S().wallTopics))return;const have=new Set(S().wallTopics.map(t=>String(t.id)));
 const missing=[...liveIndex.keys()].filter(id=>!have.has(id)).slice(0,10);if(!missing.length)return;discovering=true;
 try{const {data,error}=await c.from('bingo_topics').select('*').in('id',missing);if(error||!Array.isArray(data))return;
  const anchor=activeItem()?.dataset?.aaFeedId||'';  /* geometric fallback while a render has no active class */let added=0;
  for(const row of data){const id=String(row.id);if(!missing.includes(id)||row.moderation_status!=='visible'||S().wallTopics.some(t=>String(t.id)===id))continue;S().wallTopics.push(aaMapBingoTopicRow(row));if(anchor)livePlacement.set(id,anchor);added++}
  if(added&&typeof aaRequestRender==='function')aaRequestRender()}catch(e){}finally{discovering=false}}

/* ================================================================== TRANSPORT */
function supaTransport(name,key,meta,onMsg,onPresence,opts){
 const c=client();if(!c)return null;
 const ch=c.channel(name,{config:{broadcast:{self:false},presence:{key}}});
 ch.on('broadcast',{event:'m'},({payload})=>{try{onMsg&&onMsg(payload||{})}catch(e){console.warn('Bingo Live+',e)}});
 if(opts?.presence!==false)ch.on('presence',{event:'sync'},()=>{try{onPresence&&onPresence(ch.presenceState())}catch(e){}});
 let readyResolve;const ready=new Promise(r=>readyResolve=r);
 ch.subscribe(async st=>{if(st==='SUBSCRIBED'){if(meta&&opts?.presence!==false){try{await ch.track(meta)}catch(e){}}readyResolve(true)}else if(st==='CHANNEL_ERROR'||st==='TIMED_OUT')readyResolve(false)});
 return {ready,send:p=>{try{ch.send({type:'broadcast',event:'m',payload:p})}catch(e){}},close:()=>{try{ch.untrack?.()}catch(e){}try{c.removeChannel(ch)}catch(e){}}};
}
function openChannel(name,key,meta,onMsg,onPresence,opts){const f=W.BINGO_VOICE_LIVE_TRANSPORT||supaTransport;return f(name,key,meta,onMsg,onPresence,opts||{})}
const ICE=()=>{try{return typeof aaCallIceServers==='function'?aaCallIceServers():[]}catch(e){return []}};

/* ------------------------------------------------------------------ signed host messages */
const HOST_KINDS=new Set(['offer','sync','mode','meter','ended','roster','speak-answer','speak-deny','full','host-ready','host-comment']);
const enc=s=>new TextEncoder().encode(s);
const b64=buf=>{const u=new Uint8Array(buf);let s='';for(let i=0;i<u.length;i++)s+=String.fromCharCode(u[i]);return btoa(s)};
const unb64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const canon=p=>JSON.stringify(Object.keys(p).filter(k=>k!=='sig').sort().reduce((o,k)=>(o[k]=p[k],o),{}));
async function makeHostKeys(){try{const k=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);return {priv:k.privateKey,pub:JSON.stringify(await crypto.subtle.exportKey('jwk',k.publicKey))}}catch(e){return null}}
async function signMsg(L,p){p.ts=Date.now();if(L?.keys){try{p.sig=b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},L.keys.priv,enc(canon(p))))}catch(e){}}return p}
async function hostSend(p){const L=live;if(!L?.ch)return;const m=await signMsg(L,JSON.parse(JSON.stringify(p)));if(L.ch)L.ch.send(m)}
async function importHostKey(jwk){try{return await crypto.subtle.importKey('jwk',JSON.parse(jwk),{name:'ECDSA',namedCurve:'P-256'},false,['verify'])}catch(e){return null}}
async function verifyHost(V,m){if(!V.hostKeyRequired)return true;if(!V.hostKey||!m.sig||Math.abs(Date.now()-(m.ts||0))>120000)return false;try{return await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},V.hostKey,unb64(m.sig),enc(canon(m)))}catch(e){return false}}

/* ================================================================== HOME FEED HELPERS */
/* The feed marks its visible slide .bingo-media-active; right after a re-render that mark can be missing for
   a moment (longer in a background tab), so the slide covering the middle of the screen is used instead.
   A Live is never dropped just because the app re-rendered. */
function activeItem(){if(S().view!=='home')return null;const a=D.querySelector('#auto-arcade-widget .aa360-feed .aa360-item.bingo-media-active');if(a)return a;
 const mid=innerHeight/2;for(const it of D.querySelectorAll('#auto-arcade-widget .aa360-feed .aa360-item')){const r=it.getBoundingClientRect();if(r.height>0&&r.top<=mid&&r.bottom>=mid)return it}return null}
const topicIdOf=item=>{const c=item?.dataset?.canon||'';return c.startsWith('topic:')?c.slice(6):''};
function topicById(id){try{return (typeof aaTopics==='function'?aaTopics():[]).find(t=>String(t.id)===String(id))||null}catch(e){return null}}
function itemFor(topicId){return topicId?D.querySelector('#auto-arcade-widget .aa360-feed .aa360-item[data-canon="topic:'+CSS.escape(String(topicId))+'"]'):null}
function videoFor(topicId){return itemFor(topicId)?.querySelector('video.aa360-video')||null}
function myName(){try{return typeof aaOwnProfileName==='function'?aaOwnProfileName():(S().user?.firstName||'Me')}catch(e){return 'Me'}}
function myPhoto(){return String(S().user?.photo_url||'')}
function memberMeta(uid){try{return typeof aaResolveMemberMeta==='function'?aaResolveMemberMeta(uid,''):{name:'',photo:''}}catch(e){return {name:'',photo:''}}}
function photoSrc(p){try{return typeof aaProfilePhoto==='function'?aaProfilePhoto(p):p}catch(e){return p||''}}
const isActive=it=>!!it&&(it.classList.contains('bingo-media-active')||activeItem()===it);

/* ================================================================== TRANSIENT PANELS (tray, crown selector, host target)
   One open at a time; a transparent catch layer takes the outside tap so it closes the panel and
   never reaches the video, Crown, navigation or any control underneath. */
let transient=null;
function openTransient(kind,el,onClose){closeTransient();transient={kind,el,onClose};el.hidden=false;$catch().hidden=false}
function closeTransient(){const t=transient;if(!t)return;transient=null;t.el.hidden=true;$catch().hidden=true;try{t.onClose&&t.onClose()}catch(e){}}

/* overlay follows the live slide; only runs while something is shown */
let placeQueued=false;
const rootItem=()=>itemFor(live?live.topicId:view?view.topicId:(prompt.topicId||joinFor));
/* while the visible slide is Live, its comments run in the Live lane only (no second comment stream) */
function onAir(on){const w=D.getElementById('auto-arcade-widget');if(w&&w.classList.contains('bvl-on-air')!==on)w.classList.toggle('bvl-on-air',on)}
function place(){placeQueued=false;if(!live&&!view&&$p().hidden&&!joinFor){onAir(false);if(!root.hidden)root.hidden=true;if(!returnBtn.hidden)returnBtn.hidden=true;return}
 const it=rootItem();const show=!!it&&S().view==='home';
 if(!show){onAir(false);root.hidden=true;returnBtn.hidden=!live;return}
 const r=it.getBoundingClientRect();if(r.bottom<=40||r.top>=innerHeight-40){onAir(false);root.hidden=true;returnBtn.hidden=!live;closeTransient();return}
 onAir(!!(live||view)&&isActive(it));
 root.hidden=false;returnBtn.hidden=true;Object.assign(root.style,{left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px'});
 /* the dock sits just above the post's own caption/actions on this device */
 const info=it.querySelector('.aa360-info');const top=info?info.getBoundingClientRect().top-r.top:r.height*.72;root.style.setProperty('--bvl-dock',Math.max(90,Math.round(r.height-top+8))+'px');
 /* the original Bingo logo (and its views · crowns chip) keeps its place: when it is pinned where the
    LIVE header would sit, the header moves just below it instead of covering it */
 let headTop=12;const hh=($head().offsetHeight||60)+4;const obs=[...D.querySelectorAll('.bingo-home-logo-anchor,.bingo-home-top-logo-box,.bingo-home-view-crowns,#bingoPressHere,#auto-arcade-widget [data-bingo-stats]')].map(o=>o.getBoundingClientRect()).filter(q=>q.width&&q.height&&q.left<r.left+270);
 for(let moved=true,n=0;moved&&n<4;n++){moved=false;for(const q of obs){const top=q.top-r.top,bot=q.bottom-r.top;if(top<headTop+hh&&bot>headTop){headTop=Math.round(bot+6);moved=true}}}
 root.style.setProperty('--bvl-head-top',headTop+'px')}
function schedulePlace(){if(placeQueued)return;placeQueued=true;requestAnimationFrame(place)}
returnBtn.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();goToLiveItem()});
function goToLiveItem(){if(!live)return;if(S().view!=='home'){S().view='home';try{render()}catch(x){}}const go=n=>{const items=[...D.querySelectorAll('#auto-arcade-widget .aa360-feed .aa360-item')];const i=items.findIndex(x=>x.dataset.canon==='topic:'+live?.topicId);if(i>=0&&typeof aaFeedGoTo==='function')aaFeedGoTo(i,'auto');else if(n>0)setTimeout(()=>go(n-1),150)};setTimeout(()=>go(20),60)}

/* ================================================================== STAGE (voice / video) — lives inside the post slide */
function stageNode(L){if(L.stage)return L.stage;const st=D.createElement('div');st.className='bvl-stage';
 /* the stage videos are Live+ streams, not feed posts: the feed's video controller must leave them alone */
 if(L.mode==='video'){const v=D.createElement('video');v.className='bvl-main';v.dataset.bingoViewportVideo='live';v.playsInline=true;v.autoplay=true;v.muted=true;v.setAttribute('playsinline','');st.appendChild(v);const pip=D.createElement('video');pip.className='bvl-pip';pip.dataset.bingoViewportVideo='live';pip.playsInline=true;pip.autoplay=true;pip.muted=true;pip.hidden=true;st.appendChild(pip);const ao=D.createElement('div');ao.className='bvl-audio-only';ao.hidden=true;ao.textContent='🔊 Audio only — the video is full right now';st.appendChild(ao)}
 else{st.innerHTML='<div class="bvl-voice"><div class="bvl-voice-mic">'+ICON.mic+'</div><div class="bvl-wave">'+'<i></i>'.repeat(16)+'</div><b class="bvl-voice-name"></b><small>Voice Live</small></div>'}
 L.stage=st;return st}
function ensureStage(){const L=live||view;if(!L||L.mode==='on_video')return;const it=itemFor(L.topicId);if(!it)return;const st=stageNode(L);
 if(st.parentNode!==it){const media=it.querySelector(':scope > .aa360-video');if(media)media.after(st);else it.prepend(st)}
 if(L.mode==='video'){const v=st.querySelector('video.bvl-main');const src=live?L.cam:L.stream;if(src&&v.srcObject!==src){v.srcObject=src;v.play?.().catch(()=>{})}v.classList.toggle('mirror',!!live&&L.facing==='user');
  const pip=st.querySelector('.bvl-pip');if(live&&L.dualStream){if(pip.srcObject!==L.dualStream){pip.srcObject=L.dualStream;pip.play?.().catch(()=>{})}pip.hidden=false}else{pip.hidden=true;if(pip.srcObject)pip.srcObject=null}
  const ao=st.querySelector('.bvl-audio-only');if(ao)ao.hidden=!(view&&L.audioOnly)}
 else{const n=st.querySelector('.bvl-voice-name');const nm=live?myName():(view?.hostName||'');if(n&&n.textContent!==nm)n.textContent=nm;st.classList.toggle('on',live?!!L.micOn:!!view?.audioOK)}}
function removeStage(L){if(!L?.stage)return;L.stage.querySelectorAll('video').forEach(v=>{try{v.pause()}catch(e){}v.srcObject=null});L.stage.remove();L.stage=null}

/* ================================================================== GO LIVE ON THIS VIDEO prompt (owner, own video) */
const prompt={topicId:null,timer:0};
const dismissed=new Set();
function hidePrompt(){clearTimeout(prompt.timer);prompt.timer=0;if(prompt.topicId===null&&$p().hidden)return;prompt.topicId=null;const p=$p();p.hidden=true;p.innerHTML='';schedulePlace()}
function maybePrompt(item){
 if(live||view||cap.live!==true||!S().isLoggedIn)return hidePrompt();
 const id=topicIdOf(item);if(!id||dismissed.has(id))return hidePrompt();
 const t=topicById(id);if(!t||String(t.authorId||t.user_id||'')!==me())return hidePrompt();
 const v=item.querySelector('video.aa360-video');if(!v)return hidePrompt();
 if(prompt.topicId===id)return;
 hidePrompt();prompt.topicId=id;
 prompt.timer=setTimeout(()=>{if(prompt.topicId!==id||!isActive(itemFor(id))||live)return;const vv=videoFor(id);if(!vv||vv.paused)return hidePrompt();showPromptNow()},1500);
}
function showPromptNow(){const p=$p();p.innerHTML='<b>🎙 Go Live on this video?</b>'+helpBtn('voice_live_intro_v1')+'<span class="bvl-br"></span><button type="button" class="bvl-chip" data-act="not-now">Not Now</button><button type="button" class="bvl-chip gold" data-act="go-live">Go Live</button>';p.hidden=false;schedulePlace()}

/* ================================================================== HOST */
let live=null;   /* the one authoritative Live+ state (host side) */
let starting=false;
async function startLive(opts){
 if(live||starting){if(live)say('You are already live.');return false}
 if(!S().isLoggedIn){try{openAuth('login')}catch(e){}return false}
 if(cap.live!==true){say('Bingo Live+ is not active on this server yet.');return false}
 if(!navigator.mediaDevices?.getUserMedia||!W.RTCPeerConnection){say('Bingo Live+ needs a browser with microphone and WebRTC support.');return false}
 starting=true;try{return await startLiveInner(opts)}finally{starting=false}}
async function startLiveInner(opts){
 const mode=opts.mode;let topicId=opts.topicId||null;
 const AUDIO={echoCancellation:true,noiseSuppression:true,autoGainControl:true};
 let mic=null,cam=null;
 try{mic=await navigator.mediaDevices.getUserMedia({audio:AUDIO,video:false})}catch(e){say('Microphone permission is needed to go live.');return false}
 if(mode==='video'){try{cam=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:opts.facing||'user'},width:{ideal:720},height:{ideal:1280}}})}catch(e){mic.getTracks().forEach(t=>t.stop());say('Camera permission is needed for Video Live.');return false}}
 const stopAll=()=>{mic?.getTracks().forEach(t=>t.stop());cam?.getTracks().forEach(t=>t.stop())};
 const keys=await makeHostKeys();
 let created=null;
 if(mode!=='on_video'){try{created=await createLivePost(mode,opts.title);topicId=created.id}catch(e){stopAll();say(String(e?.message||'Could not create the live post'));return false}}
 let sess=null;
 try{sess=await rpc('bingo_voice_live_start',{p_topic:topicId,p_original_audio:'ducked',p_mode:mode,p_host_key:keys?.pub||null})}
 catch(e){stopAll();if(created)hideLivePost(created.id);say(missingFn(e)?'Bingo Live+ is not active on this server yet.':String(e?.message||'Could not start the Live'));return false}
 const AC=W.AudioContext||W.webkitAudioContext;const ctx=new AC();try{await ctx.resume()}catch(e){}
 const micSrc=ctx.createMediaStreamSource(mic),micGain=ctx.createGain();micSrc.connect(micGain);
 const mainDest=ctx.createMediaStreamDestination();micGain.connect(mainDest);
 const an=ctx.createAnalyser();an.fftSize=256;micGain.connect(an);
 live={sid:String(sess.id),topicId:String(topicId),hostId:me(),mode,title:(opts.title||'').trim(),startedAt:Date.now(),origMode:'ducked',micOn:true,mic,cam,camOn:true,facing:opts.facing||'user',dualStream:null,quality:720,
  ctx,micSrc,micGain,mainDest,analyser:an,keys,created:!!created,
  peers:new Map(),speakers:new Map(),listeners:new Map(),roster:[],requests:0,meter:null,celebrateUntil:0,tick:0,timer:0,ch:null,rec:null,stage:null,
  prevSound:S().aaFeedSoundOn,videoEl:null};
 hidePrompt();
 if(mode==='on_video'){const v=videoFor(topicId);live.videoEl=v;S().aaFeedSoundOn=true;applyHostVideo();try{if(v&&v.paused)v.play().catch(()=>{})}catch(e){}}
 live.ch=openChannel('bingo_voicelive_'+live.sid,'h:'+me(),{uid:me(),role:'host',name:myName(),photo:myPhoto()},hostMsg,hostPresence);
 live.ch&&live.ch.ready.then(ok=>{if(ok&&live)hostSend({kind:'host-ready'})});
 liveIndex.set(String(topicId),{session_id:live.sid,host_id:me()});
 const L0=live;
 if(mode==='on_video'){corsReady(live.videoEl).then(ok=>{if(live===L0){applyHostVideo();if(ok)startRecorder();renderLive()}})}
 else{ensureStage();startRecorder();goToLiveItem()}
 live.timer=setInterval(hostTick,4000);
 renderLive();restoreDraft();refreshMeter();schedulePlace();
 return true}
async function createLivePost(mode,title){const c=client();if(!c)throw new Error('No live connection');const id=uuid();const label=String(title||'').trim().slice(0,90)||(mode==='voice'?'Voice Live':'Video Live');
 const row={id,user_id:me(),title:'🔴 LIVE · '+label,body:(mode==='voice'?'🎙 Bingo Live+ Voice Live':'🎥 Bingo Live+ Video Live')+' — tap to join',category:'General',media:[],moderation_status:'visible'};
 const ins=await c.from('bingo_topics').insert(row).select().maybeSingle();if(ins.error)throw new Error(ins.error.message||'Could not create the live post');
 const saved=ins.data||row;try{if(Array.isArray(S().wallTopics)&&typeof aaMapBingoTopicRow==='function'&&!S().wallTopics.some(t=>String(t.id)===id))S().wallTopics.unshift(aaMapBingoTopicRow(saved))}catch(e){}
 if(S().view!=='home')S().view='home';try{render()}catch(e){}
 return {id,label}}
async function hideLivePost(id){const c=client();if(!c||!id)return;try{await c.from('bingo_topics').update({moderation_status:'hidden'}).eq('id',id)}catch(e){}try{const t=topicById(id);if(t)t.hiddenFromPublic=true;render()}catch(e){}}
/* the existing player is reloaded once with CORS so the replay can capture it (same element, same position) */
function corsReady(v){return new Promise(res=>{if(!v||v.crossOrigin){res(true);return}const src=v.currentSrc||v.getAttribute('src')||'';if(!src||/^blob:|^data:/.test(src)){res(true);return}
 const t=v.currentTime,wasPlaying=!v.paused;let done=false;const fin=ok=>{if(done)return;done=true;v.removeEventListener('loadedmetadata',okH);v.removeEventListener('error',errH);res(ok)};
 const resume=()=>{try{if(t<(v.duration||Infinity))v.currentTime=t}catch(e){}if(wasPlaying)v.play?.().catch(()=>{})};
 const okH=()=>{resume();fin(true)};const errH=()=>{v.removeAttribute('crossorigin');v.src=src;v.addEventListener('loadedmetadata',resume,{once:true});fin(false)};
 v.addEventListener('loadedmetadata',okH);v.addEventListener('error',errH);v.crossOrigin='anonymous';v.src=src;try{v.load()}catch(e){}setTimeout(()=>fin(!!v.crossOrigin&&v.readyState>=1),6000)})}
function hostVideo(){if(!live||live.mode!=='on_video')return null;const v=videoFor(live.topicId);if(v&&v!==live.videoEl){live.videoEl=v;applyHostVideo()}return live.videoEl}
function applyHostVideo(){const v=live?.videoEl;if(!v)return;try{v.muted=false;v.volume=VOL[live.origMode]}catch(e){}}
function hostTick(){if(!live)return;live.tick++;
 if(live.mode==='on_video'){const v=hostVideo();if(v)hostSend({kind:'sync',t:v.currentTime,paused:v.paused,mode:live.origMode})}
 if(live.tick%5===0){rpc('bingo_voice_live_heartbeat',{p_session:live.sid,p_listeners:live.listeners.size,p_original_audio:live.origMode}).catch(()=>{});refreshMeter()}
 if(live.rec&&live.rec.bytes>=110*1024*1024)stopRecorder('cap');
 if(!modal.hidden&&modal.dataset.kind==='setup')renderSetup()}
let meterBusy=0;
async function refreshMeter(){if(!live||meterBusy)return;meterBusy=1;try{const m=await rpc('bingo_crown_target_meter',{p_user:live.hostId});if(!live)return;setMeter(m);hostSend({kind:'meter',m})}catch(e){}finally{meterBusy=0}}
function hostPresence(state){if(!live)return;const keys=new Set();for(const [k,arr] of Object.entries(state||{})){if(!k.startsWith('v:'))continue;keys.add(k);const m=(arr&&arr[0])||{};live.listeners.set(k,{uid:String(m.uid||''),name:m.name||'',photo:m.photo||''})}
 for(const k of [...live.listeners.keys()])if(!keys.has(k)){live.listeners.delete(k);closePeer(k)}
 renderHead();if(transient?.kind==='tray')renderTray()}
const pendingIce=new Map();
function bufIce(k,c){if(!pendingIce.has(k))pendingIce.set(k,[]);const l=pendingIce.get(k);if(l.length<60)l.push(c)}
async function flushIce(k,pc){const l=pendingIce.get(k);pendingIce.delete(k);if(!l)return;for(const c of l)try{await pc.addIceCandidate(c)}catch(e){}}
let meterNudge=0;
async function hostMsg(m){if(!live)return;
 switch(m.kind){
  case 'join':return offerTo(m.from,m.uid);
  case 'answer':{const p=live.peers.get(m.from);if(p)try{await p.pc.setRemoteDescription(m.sdp);await flushIce(m.from+'|down',p.pc)}catch(e){}return}
  case 'ice':{if(m.to!=='host'||!m.cand)return;const ch=m.ch==='up'?'up':'down';const target=ch==='up'?[...live.speakers.values()].find(s=>s.key===m.from)?.pc:live.peers.get(m.from)?.pc;if(target&&target.remoteDescription){try{await target.addIceCandidate(m.cand)}catch(e){}}else bufIce(m.from+'|'+ch,m.cand);return}
  case 'leave':live.listeners.delete(m.from);closePeer(m.from);renderHead();return
  case 'req':case 'roster':return refreshRoster()
  case 'speak-offer':return admitSpeaker(m)
  case 'comment':return pushComment(m,false)
  case 'crown':floatCrown(m.tier);clearTimeout(meterNudge);meterNudge=setTimeout(refreshMeter,2500);return
 }}
const VIDEO_CAP=12,PEER_CAP=40;
async function offerTo(key,uid){if(!live||!key)return;if(live.peers.size>=PEER_CAP&&!live.peers.has(key)){hostSend({kind:'full',to:key});return}
 closePeer(key);const pc=new RTCPeerConnection({iceServers:ICE()});const entry={pc,uid:String(uid||''),dest:null,video:false};live.peers.set(key,entry);
 const d=mixFor(entry);pc.addTrack(d.stream.getAudioTracks()[0],d.stream);
 /* video goes to the first VIDEO_CAP viewers; beyond that the host's upload would saturate, so audio only */
 if(live.mode==='video'){const withVideo=[...live.peers.values()].filter(p=>p.video).length;if(withVideo<VIDEO_CAP){const vt=outgoingVideoTrack();if(vt){const snd=pc.addTrack(vt,new MediaStream([vt]));entry.video=true;try{const prm=snd.getParameters();if(prm.encodings&&prm.encodings[0]){prm.encodings[0].maxBitrate=900000;snd.setParameters(prm).catch(()=>{})}}catch(e){}}}}
 pc.onicecandidate=e=>{if(e.candidate)live?.ch?.send({kind:'ice',to:key,from:'host',ch:'down',cand:e.candidate.toJSON?e.candidate.toJSON():e.candidate})};
 pc.onconnectionstatechange=()=>{if(['failed','closed'].includes(pc.connectionState))closePeer(key)};
 try{const o=await pc.createOffer();await pc.setLocalDescription(o);await hostSend({kind:'offer',to:key,sdp:{type:pc.localDescription.type,sdp:pc.localDescription.sdp},mode:live.mode,origMode:live.origMode,audioOnly:live.mode==='video'&&!entry.video,t:hostVideo()?.currentTime||0});if(live?.meter)hostSend({kind:'meter',m:live.meter.raw})}catch(e){closePeer(key)}}
function closePeer(key){pendingIce.delete(key+'|down');pendingIce.delete(key+'|up');const p=live?.peers.get(key);if(!p)return;try{p.pc.close()}catch(e){}live.peers.delete(key)}
function mixFor(entry){if(!live)return null;const sp=entry.uid&&live.speakers.get(entry.uid);if(!sp)return live.mainDest;if(!entry.dest){entry.dest=live.ctx.createMediaStreamDestination();live.micGain.connect(entry.dest);for(const [uid,o] of live.speakers)if(uid!==entry.uid&&o.gain)o.gain.connect(entry.dest)}return entry.dest}
function rebuildMixes(){if(!live)return;for(const [,entry] of live.peers){const isSp=entry.uid&&live.speakers.has(entry.uid);if(entry.dest){try{live.micGain.disconnect(entry.dest)}catch(e){}for(const o of live.speakers.values())try{o.gain&&o.gain.disconnect(entry.dest)}catch(e){}entry.dest=null}
  const d=isSp?mixFor(entry):live.mainDest;const sender=entry.pc.getSenders().find(s=>s.track&&s.track.kind==='audio');if(sender){try{sender.replaceTrack(d.stream.getAudioTracks()[0])}catch(e){}}}}
async function admitSpeaker(m){if(!live||!m.ticket||!m.sdp)return;
 let who=null;try{who=await rpc('bingo_voice_live_redeem_ticket',{p_session:live.sid,p_ticket:String(m.ticket)})}catch(e){hostSend({kind:'speak-deny',to:m.from,reason:String(e?.message||'Not allowed')});return}
 if(!live)return;const uid=String(who.user_id);dropSpeaker(uid);
 const pc=new RTCPeerConnection({iceServers:ICE()});const sp={pc,key:m.from,stream:null,el:null,src:null,gain:null,muted:!!(who.muted||who.muted_by_host)};live.speakers.set(uid,sp);
 pc.onicecandidate=e=>{if(e.candidate)live?.ch?.send({kind:'ice',to:m.from,from:'host',ch:'up',cand:e.candidate.toJSON?e.candidate.toJSON():e.candidate})};
 pc.ontrack=e=>{if(!live||sp.src)return;sp.stream=e.streams[0]||new MediaStream([e.track]);
  sp.el=new Audio();sp.el.muted=true;sp.el.srcObject=sp.stream;sp.el.play?.().catch(()=>{});   /* Chrome only feeds remote audio to WebAudio while an element plays it */
  sp.src=live.ctx.createMediaStreamSource(sp.stream);sp.gain=live.ctx.createGain();sp.gain.gain.value=sp.muted?0:1;sp.src.connect(sp.gain);
  sp.gain.connect(live.mainDest);sp.gain.connect(live.ctx.destination);if(live.rec?.dest)sp.gain.connect(live.rec.dest);rebuildMixes();renderHead()};
 pc.onconnectionstatechange=()=>{if(['failed','closed'].includes(pc.connectionState)&&live?.speakers.get(uid)===sp){dropSpeaker(uid);renderHead()}};
 try{await pc.setRemoteDescription(m.sdp);await flushIce(m.from+'|up',pc);const a=await pc.createAnswer();await pc.setLocalDescription(a);await hostSend({kind:'speak-answer',to:m.from,sdp:{type:pc.localDescription.type,sdp:pc.localDescription.sdp}})}catch(e){dropSpeaker(uid)}
 refreshRoster()}
function dropSpeaker(uid){const sp=live?.speakers.get(uid);if(!sp)return;try{sp.pc.close()}catch(e){}try{sp.gain&&sp.gain.disconnect()}catch(e){}try{sp.src&&sp.src.disconnect()}catch(e){}if(sp.el){sp.el.srcObject=null}sp.stream?.getTracks().forEach(t=>t.stop());live.speakers.delete(uid);rebuildMixes()}
async function refreshRoster(){if(!live)return;try{const s=await rpc('bingo_voice_live_state',{p_session:live.sid});if(!live)return;live.roster=Array.isArray(s?.participants)?s.participants:[];
  /* the backend roster is the authority: mute/unmute gains, disconnect anyone no longer a speaker */
  for(const [uid,sp] of live.speakers){const r=live.roster.find(x=>String(x.user_id)===uid);if(!r||r.state!=='speaker'){dropSpeaker(uid);continue}sp.muted=!!r.muted;if(sp.gain)sp.gain.gain.value=sp.muted?0:1}
  live.requests=live.roster.filter(x=>x.state==='requested').length;renderLive();if(modal.dataset.kind==='people')renderPeople();if(modal.dataset.kind==='setup')renderSetup()}catch(e){}}
/* ---------------- host controls */
function hostMic(){if(!live)return;live.micOn=!live.micOn;live.mic.getAudioTracks().forEach(t=>t.enabled=live.micOn);renderLive();ensureStage();if(modal.dataset.kind==='setup')renderSetup()}
function setOrig(m){if(!live||live.mode!=='on_video'||!Object.prototype.hasOwnProperty.call(VOL,m))return;live.origMode=m;applyHostVideo();if(live.rec?.origGain)live.rec.origGain.gain.value=VOL[m];hostSend({kind:'mode',mode:m});renderLive();if(modal.dataset.kind==='setup')renderSetup()}
function cycleOrig(){if(!live)return;setOrig({on:'ducked',ducked:'muted',muted:'on'}[live.origMode])}
function outgoingVideoTrack(){if(!live)return null;if(live.dualStream&&live.rec?.canvasTrack)return live.rec.canvasTrack;return live.cam?.getVideoTracks()[0]||null}
function replaceOutgoingVideo(){const t=outgoingVideoTrack();if(!t||!live)return;for(const p of live.peers.values()){const s=p.pc.getSenders().find(x=>x.track&&x.track.kind==='video');if(s)try{s.replaceTrack(t)}catch(e){}}}
const DIMS={480:[480,854],720:[720,1280],1080:[1080,1920]};
async function flipCamera(){if(!live||live.mode!=='video')return;const want=live.facing==='user'?'environment':'user';const d=DIMS[live.quality]||DIMS[720];
 try{const ns=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:want},width:{ideal:d[0]},height:{ideal:d[1]}}});if(!live){ns.getTracks().forEach(t=>t.stop());return}
  const old=live.cam;ns.getVideoTracks()[0].enabled=live.camOn;live.cam=ns;live.facing=want;old?.getTracks().forEach(t=>t.stop());replaceOutgoingVideo();ensureStage();renderLive();if(modal.dataset.kind==='setup')renderSetup()}
 catch(e){say('Could not switch camera on this device.')}}
async function toggleDual(){if(!live||live.mode!=='video')return;
 if(live.dualStream){live.dualStream.getTracks().forEach(t=>t.stop());live.dualStream=null;replaceOutgoingVideo();ensureStage();renderLive();if(modal.dataset.kind==='setup')renderSetup();return}
 try{/* a genuinely different camera: by device id when the browser lists one, otherwise by facing */
  const cur=live.cam?.getVideoTracks()[0]?.getSettings?.().deviceId||'';let devs=[];try{devs=(await navigator.mediaDevices.enumerateDevices()).filter(d=>d.kind==='videoinput'&&d.deviceId&&d.deviceId!==cur)}catch(e){}
  const other=live.facing==='user'?'environment':'user';
  const ds=await navigator.mediaDevices.getUserMedia({audio:false,video:devs.length?{deviceId:{exact:devs[0].deviceId},width:{ideal:480}}:{facingMode:{exact:other},width:{ideal:480}}});if(!live){ds.getTracks().forEach(t=>t.stop());return}
  if(cur&&ds.getVideoTracks()[0]?.getSettings?.().deviceId===cur){ds.getTracks().forEach(t=>t.stop());say('Dual Cam is not supported on this device.');return}
  live.dualStream=ds;replaceOutgoingVideo();ensureStage();renderLive();if(modal.dataset.kind==='setup')renderSetup()}
 catch(e){say('Dual Cam is not supported on this device.')}}
function toggleCam(){if(!live||!live.cam)return;live.camOn=!live.camOn;live.cam.getVideoTracks().forEach(t=>t.enabled=live.camOn);renderLive();if(modal.dataset.kind==='setup')renderSetup()}
async function setQuality(q){if(!live||!live.cam||!DIMS[q])return;live.quality=q;const t=live.cam.getVideoTracks()[0];const d=DIMS[q];try{await t.applyConstraints({width:{ideal:d[0]},height:{ideal:d[1]}})}catch(e){}if(modal.dataset.kind==='setup')renderSetup()}

/* ---------------- replay recording */
function startRecorder(){if(!live||!W.MediaRecorder)return;
 try{
  const dest=live.ctx.createMediaStreamDestination();live.micGain.connect(dest);for(const sp of live.speakers.values())sp.gain&&sp.gain.connect(dest);
  let vtrack=null,origGain=null,canvas=null,canvasTrack=null,raf=0,iv=0;
  if(live.mode==='on_video'){const v=hostVideo();if(!v)return;const cap=v.captureStream?v.captureStream():null;
   if(cap){vtrack=cap.getVideoTracks()[0]||null;const at=cap.getAudioTracks()[0];if(at){const s=live.ctx.createMediaStreamSource(new MediaStream([at]));origGain=live.ctx.createGain();origGain.gain.value=VOL[live.origMode];s.connect(origGain);origGain.connect(dest)}}
   if(!vtrack){canvas=D.createElement('canvas');canvas.width=Math.min(720,v.videoWidth||720);canvas.height=Math.round(canvas.width*((v.videoHeight||1280)/(v.videoWidth||720)));const g=canvas.getContext('2d');const draw=()=>{const cur=hostVideo();if(cur&&cur.readyState>=2)try{g.drawImage(cur,0,0,canvas.width,canvas.height)}catch(e){}raf=requestAnimationFrame(draw)};draw();vtrack=canvas.captureStream(30).getVideoTracks()[0]}}
  else if(live.mode==='video'){
   /* one compositor: camera (+ Dual Cam picture-in-picture); also feeds viewers while Dual Cam is on */
   canvas=D.createElement('canvas');canvas.width=720;canvas.height=1280;const g=canvas.getContext('2d');
   const draw=()=>{const st=live?.stage;const v=st?.querySelector('video.bvl-main');g.fillStyle='#000';g.fillRect(0,0,720,1280);
    if(v&&v.readyState>=2&&live.camOn){const vw=v.videoWidth||720,vh=v.videoHeight||1280,s=Math.max(720/vw,1280/vh),w=vw*s,h=vh*s;g.save();if(live.facing==='user'){g.translate(720,0);g.scale(-1,1)}g.drawImage(v,(720-w)/2,(1280-h)/2,w,h);g.restore()}
    const p=st?.querySelector('.bvl-pip');if(live?.dualStream&&p&&p.readyState>=2){const pw=200,ph=Math.round(pw*(p.videoHeight||640)/(p.videoWidth||480));g.drawImage(p,24,120,pw,ph);g.strokeStyle='#ffc928';g.lineWidth=4;g.strokeRect(24,120,pw,ph)}
    raf=requestAnimationFrame(draw)};draw();canvasTrack=canvas.captureStream(30).getVideoTracks()[0];vtrack=canvasTrack}
  else{
   /* voice: a light 15 fps waveform card so the replay is a normal playable video post */
   canvas=D.createElement('canvas');canvas.width=720;canvas.height=1280;const g=canvas.getContext('2d');const buf=new Uint8Array(live.analyser.frequencyBinCount);const nm=myName(),tt=live.title||'Voice Live';const L=live;
   const draw=()=>{if(live!==L)return;const gr=g.createRadialGradient(360,520,40,360,520,760);gr.addColorStop(0,'#13284a');gr.addColorStop(.6,'#071224');gr.addColorStop(1,'#030810');g.fillStyle=gr;g.fillRect(0,0,720,1280);
    g.strokeStyle='rgba(255,255,255,.85)';g.lineWidth=5;g.beginPath();g.arc(360,470,100,0,Math.PI*2);g.stroke();g.fillStyle='#fff';g.beginPath();g.roundRect?g.roundRect(330,410,60,100,30):g.rect(330,410,60,100);g.fill();g.lineWidth=8;g.strokeStyle='#fff';g.beginPath();g.arc(360,480,62,0.15*Math.PI,0.85*Math.PI);g.stroke();g.fillRect(356,540,8,26);
    L.analyser.getByteFrequencyData(buf);for(let i=0;i<24;i++){const v=buf[2+i*2]/255,h=16+v*170;const x=360-24*14+i*28;const lg=g.createLinearGradient(0,660-h/2,0,660+h/2);lg.addColorStop(0,'#7de8ff');lg.addColorStop(1,'#2b8cff');g.fillStyle=lg;g.fillRect(x,660-h/2,14,h)}
    g.textAlign='center';g.fillStyle='#fff';g.font='bold 40px system-ui,sans-serif';g.fillText(nm,360,820);g.fillStyle='#9fb3cf';g.font='bold 26px system-ui,sans-serif';g.fillText('BINGO LIVE+ · VOICE LIVE',360,872);g.fillStyle='#ffe28a';g.font='600 30px system-ui,sans-serif';g.fillText(tt.slice(0,40),360,930)};
   draw();iv=setInterval(draw,66);vtrack=canvas.captureStream(15).getVideoTracks()[0]}
  const mime=['video/mp4;codecs=avc1,mp4a','video/mp4','video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/webm'].find(t=>{try{return MediaRecorder.isTypeSupported(t)}catch(e){return false}})||'';
  const stream=new MediaStream([vtrack,...dest.stream.getAudioTracks()].filter(Boolean));
  const mr=new MediaRecorder(stream,mime?{mimeType:mime,videoBitsPerSecond:2500000,audioBitsPerSecond:128000}:{});
  const rec={mr,dest,origGain,canvas,canvasTrack,raf:()=>raf,iv,chunks:[],bytes:0,mime:mr.mimeType||mime||'video/webm',stopped:false,capped:false};
  mr.ondataavailable=e=>{if(e.data&&e.data.size){rec.chunks.push(e.data);rec.bytes+=e.data.size}};
  mr.start(1000);live.rec=rec;if(live.dualStream)replaceOutgoingVideo();
 }catch(e){console.warn('Bingo Live+ replay recording unavailable:',e?.message||e);if(live)live.rec=null}}
function stopDrawing(rec){try{cancelAnimationFrame(rec.raf())}catch(e){}clearInterval(rec.iv)}
function stopRecorder(why){const rec=live?.rec;if(!rec||rec.stopped)return Promise.resolve(rec);rec.stopped=true;if(why==='cap'){rec.capped=true;say('Replay recording reached its size limit. The Live continues.')}
 return new Promise(res=>{try{rec.mr.onstop=()=>res(rec);rec.mr.stop()}catch(e){res(rec)}setTimeout(()=>res(rec),3000)}).then(r=>{if(!live?.dualStream)stopDrawing(rec);return r})}

/* ---------------- End Live */
function openEnd(){if(!live)return;closeTransient();const canSave=!!live.rec;
 openModal('end','<div class="bvl-dialog" role="dialog" aria-modal="true"><h3>End Live?<button type="button" class="bvl-x" data-m="close" aria-label="Keep the Live going">×</button></h3>'+
  (canSave?'<button type="button" class="bvl-btn gold wide" data-m="post">Save &amp; Post</button><button type="button" class="bvl-btn wide" data-m="draft">Save as Draft</button>':'<p class="bvl-note">A replay could not be recorded on this device.</p>')+
  '<button type="button" class="bvl-btn red wide" data-m="discard">End Without Saving</button><p class="bvl-note bvl-end-msg"></p></div>','center')}
async function endLive(action){if(!live)return;const L=live;const msg=modal.querySelector('.bvl-end-msg');modal.querySelectorAll('button').forEach(b=>b.disabled=true);
 let replayId=null;
 if(action!=='discarded'){if(msg)msg.textContent='Saving your replay…';const rec=await stopRecorder();
  try{replayId=await saveReplay(L,rec,action==='draft')}catch(e){if(msg)msg.textContent=String(e?.message||'Could not save the replay.');modal.querySelectorAll('button').forEach(b=>b.disabled=false);return}}
 else if(L.created)hideLivePost(L.topicId);   /* hidden, never deleted: comments made during the Live are kept */
 try{await rpc('bingo_voice_live_end',{p_session:L.sid,p_action:action,p_replay_topic:replayId})}catch(e){}
 await hostSend({kind:'ended',action});liveIndex.delete(String(L.topicId));
 teardownHost();closeModal();
 if(action==='posted'){say('Replay posted.','success');setTimeout(()=>guideShow('trending_intro_v1'),600)}else if(action==='draft')say('Replay saved as a draft on your profile.','success');else say('Live ended.')}
async function saveReplay(L,rec,draft){const c=client();if(!c)throw new Error('No live connection');if(!rec||!rec.chunks.length)throw new Error('Nothing was recorded.');
 const type=String(rec.mime||'video/webm').split(';')[0];const ext=/mp4/.test(type)?'mp4':'webm';const blob=new Blob(rec.chunks,{type});
 const file=new File([blob],'bingo-live-replay-'+Date.now()+'.'+ext,{type});
 if(typeof aaValidateTopicMediaFile==='function'){const err=aaValidateTopicMediaFile(file);if(err)throw new Error(err)}
 const src=topicById(L.topicId)||{};
 if(L.created){
  /* Voice / Video Live: the live post itself becomes the replay (no second post) */
  const up=typeof aaUploadTopicMedia==='function'?await aaUploadTopicMedia([file],L.hostId,L.topicId):{error:new Error('Upload is unavailable')};
  if(up.error){if(up.paths?.length&&typeof aaDeleteUploadedTopicMedia==='function')aaDeleteUploadedTopicMedia(up.paths);throw up.error}
  const label=String(src.title||'').replace(/^🔴 LIVE · /,'')||MODE_NAME[L.mode];
  const upd=await c.from('bingo_topics').update({media:up.media,title:(L.mode==='voice'?'🎙 Live replay · ':'🎥 Live replay · ')+label,body:(L.mode==='voice'?'Bingo Live+ Voice Live replay':'Bingo Live+ Video Live replay'),moderation_status:draft?'hidden':'visible'}).eq('id',L.topicId);
  if(upd.error)throw new Error(upd.error.message||'Could not attach the replay');
  try{if(typeof aaLoadBingoWall==='function')aaLoadBingoWall()}catch(e){}
  return L.topicId}
 const id=uuid();
 const title=('🎙 Live replay · '+String(src.title||'Bingo Live+').replace(/^(?:🎙|🎥|🔴) (?:Live replay|LIVE) · /,'')).slice(0,140);
 const row={id,user_id:L.hostId,title,body:String(src.body||'').slice(0,4000)||'Bingo Live+ replay',category:src.category||'General',media:[],moderation_status:draft?'hidden':'visible'};
 const ins=await c.from('bingo_topics').insert(row).select().maybeSingle();if(ins.error)throw new Error(ins.error.message||'Could not create the replay post');
 const up=typeof aaUploadTopicMedia==='function'?await aaUploadTopicMedia([file],L.hostId,id):{error:new Error('Upload is unavailable')};
 if(up.error){try{await c.from('bingo_topics').delete().eq('id',id)}catch(e){}if(up.paths?.length&&typeof aaDeleteUploadedTopicMedia==='function')aaDeleteUploadedTopicMedia(up.paths);throw up.error}
 const upd=await c.from('bingo_topics').update({media:up.media}).eq('id',id);if(upd.error)throw new Error(upd.error.message||'Could not attach the replay');
 try{if(typeof aaLoadBingoWall==='function')aaLoadBingoWall()}catch(e){}
 return id}
function teardownHost(){const L=live;if(!L)return;live=null;clearInterval(L.timer);pendingIce.clear();closeTransient();
 for(const p of L.peers.values()){try{p.pc.close()}catch(e){}}L.peers.clear();
 for(const sp of L.speakers.values()){try{sp.pc.close()}catch(e){}if(sp.el)sp.el.srcObject=null;sp.stream?.getTracks().forEach(t=>t.stop())}L.speakers.clear();
 if(L.rec){try{if(L.rec.mr.state!=='inactive')L.rec.mr.stop()}catch(e){}stopDrawing(L.rec);try{L.rec.canvasTrack?.stop()}catch(e){}L.rec.chunks=[];L.rec=null}
 L.mic.getTracks().forEach(t=>t.stop());L.cam?.getTracks().forEach(t=>t.stop());L.dualStream?.getTracks().forEach(t=>t.stop());
 try{L.micSrc.disconnect()}catch(e){}try{L.ctx.close()}catch(e){}
 try{L.ch?.close()}catch(e){}L.ch=null;
 removeStage(L);
 const v=L.videoEl;if(v){try{v.volume=1}catch(e){}}if(L.mode==='on_video'){S().aaFeedSoundOn=L.prevSound;if(v){try{v.muted=!(L.prevSound===true)}catch(e){}}}
 L.listeners.clear();ssSet('bvl_draft:'+L.sid,null);
 clearLiveUi();dismissed.add(String(L.topicId));schedulePlace();scheduleCheck()}
function clearLiveUi(){$head().innerHTML='';delete $head().dataset.join;$tr().innerHTML='';$rail().innerHTML='';$lane().innerHTML='';$tray().innerHTML='';$tray().hidden=true;$flap().innerHTML='';$flap().hidden=true;$comp().innerHTML='';$comp().hidden=true;$inv().innerHTML='';$pop().innerHTML='';$pop().hidden=true;$fx().innerHTML='';closeTransient()}

/* ================================================================== VIEWER */
let view=null;   /* at most one Live attached per device */
const stats={attach:0,detach:0,lastDetach:''};
let joinFor=null;   /* a Live the viewer closed with X: a compact "Join Live" pill is offered instead */
const closedLives=new Set();
function attachViewer(topicId,info){if(view?.topicId===topicId)return;detachViewer('switch');stats.attach++;
 const key='v:'+(me()||'g')+':'+uuid().slice(0,8);
 const V={topicId,sid:info.session_id,hostId:info.host_id,mode:'on_video',hostName:'',hostPhoto:'',key,pc:null,up:null,mic:null,ch:null,ice:{down:[],up:[]},listeners:0,origMode:'ducked',my:null,meter:null,audioOK:false,celebrateUntil:0,stream:null,audioOnly:false,hostKey:null,hostKeyRequired:false,q:Promise.resolve(),stage:null};
 view=V;joinFor=null;hidePrompt();
 const mm=memberMeta(V.hostId);V.hostName=mm.name||'';V.hostPhoto=mm.photo||'';
 /* the session (mode + host public key) is read before any host message is trusted */
 V.ready=rpc('bingo_voice_live_state',{p_session:V.sid}).then(async s=>{if(view!==V)return;if(!s||s.status==='ended'){liveIndex.delete(String(topicId));detachViewer();scheduleCheck();return}
  V.mode=s.mode||'on_video';if(s.host_key){V.hostKeyRequired=true;V.hostKey=await importHostKey(s.host_key)}
  V.my=(s.participants||[]).find(x=>String(x.user_id)===me())||null;ensureStage();renderLive()}).catch(()=>{});
 V.ch=openChannel('bingo_voicelive_'+V.sid,key,{uid:me(),role:'viewer',name:me()?myName():'',photo:me()?myPhoto():''},m=>{V.q=V.q.then(()=>viewerMsg(V,m)).catch(()=>{})},viewerPresence);
 V.ch&&Promise.all([V.ch.ready,V.ready]).then(([ok])=>{if(ok&&view===V)V.ch.send({kind:'join',from:key,uid:me()})});
 renderLive();restoreDraft();schedulePlace()}
function detachViewer(why){const V=view;if(!V)return;view=null;stats.detach++;stats.lastDetach=String(why||'');
 try{V.ch?.send({kind:'leave',from:V.key})}catch(e){}
 try{V.pc?.close()}catch(e){}try{V.up?.close()}catch(e){}V.mic?.getTracks().forEach(t=>t.stop());
 try{V.ch?.close()}catch(e){}
 const a=$audio();try{a.pause()}catch(e){}a.srcObject=null;
 removeStage(V);V.stream=null;
 const v=videoFor(V.topicId);if(v&&V.mode==='on_video'){try{v.volume=1;v.muted=!(typeof aaFeedWantsSound==='function'&&aaFeedWantsSound())}catch(e){}}
 clearLiveUi();schedulePlace()}
function viewerPresence(state){if(!view)return;view.listeners=Object.keys(state||{}).filter(k=>k.startsWith('v:')).length;renderHead()}
async function viewerMsg(V,m){if(view!==V)return;
 if(HOST_KINDS.has(m.kind)){await V.ready;if(view!==V)return;if(!(await verifyHost(V,m)))return}   /* forged host messages are ignored */
 switch(m.kind){
  case 'host-ready':V.ch?.send({kind:'join',from:V.key,uid:me()});return
  case 'offer':{if(m.to!==V.key)return;try{V.pc?.close()}catch(e){}V.ice.down=[];const pc=new RTCPeerConnection({iceServers:ICE()});V.pc=pc;V.audioOnly=!!m.audioOnly;
   pc.onicecandidate=e=>{if(e.candidate)V.ch?.send({kind:'ice',to:'host',from:V.key,ch:'down',cand:e.candidate.toJSON?e.candidate.toJSON():e.candidate})};
   const ms=new MediaStream();V.stream=ms;
   pc.ontrack=e=>{if(view!==V)return;ms.addTrack(e.track);if(e.track.kind==='audio'){const a=$audio();a.srcObject=ms;playAudio()}if(V.stage){const sv=V.stage.querySelector('video.bvl-main');if(sv){sv.srcObject=null}}ensureStage();renderLive()};
   if(m.mode)V.mode=m.mode;if(m.origMode)V.origMode=m.origMode;
   try{await pc.setRemoteDescription(m.sdp);for(const c of V.ice.down.splice(0))try{await pc.addIceCandidate(c)}catch(e){}const ans=await pc.createAnswer();await pc.setLocalDescription(ans);V.ch?.send({kind:'answer',from:V.key,sdp:{type:pc.localDescription.type,sdp:pc.localDescription.sdp}})}catch(e){}
   syncVideo(m.t);ensureStage();return}
  case 'ice':{if(m.to!==V.key||!m.cand)return;const ch=m.ch==='up'?'up':'down';const pc=ch==='up'?V.up:V.pc;if(pc&&pc.remoteDescription){try{await pc.addIceCandidate(m.cand)}catch(e){}}else if(V.ice[ch].length<60)V.ice[ch].push(m.cand);return}
  case 'sync':V.origMode=m.mode||V.origMode;applyViewerVideo();syncVideo(m.t);return
  case 'mode':V.origMode=m.mode||V.origMode;applyViewerVideo();return
  case 'meter':setMeter(m.m);return
  case 'comment':pushComment(m,false);return
  case 'host-comment':pushComment(m,true);return
  case 'crown':floatCrown(m.tier);return
  case 'roster':refreshMine();return
  case 'speak-answer':if(m.to===V.key&&V.up)try{await V.up.setRemoteDescription(m.sdp);for(const c of V.ice.up.splice(0))try{await V.up.addIceCandidate(c)}catch(e){}}catch(e){}return
  case 'speak-deny':if(m.to===V.key){stopMyMic();say(m.reason||'The host did not admit you as a speaker.')}return
  case 'full':if(m.to===V.key)say('This Live is full right now.');return
  case 'ended':{let s=null;try{s=await rpc('bingo_voice_live_state',{p_session:V.sid})}catch(e){}if(s&&s.status==='live')return;liveIndex.delete(String(V.topicId));detachViewer();say('The Live has ended.');scheduleCheck();return}
 }}
function playAudio(){const a=$audio();const p=a.play?.();if(p&&p.then)p.then(()=>{if(view){view.audioOK=true;applyViewerVideo();ensureStage();renderHead()}}).catch(()=>{if(view){view.audioOK=false;renderHead()}});else if(view){view.audioOK=true;applyViewerVideo()}}
function applyViewerVideo(){if(!view||view.mode!=='on_video')return;const v=videoFor(view.topicId);if(!v)return;if(view.audioOK){try{v.muted=false;v.volume=VOL[view.origMode]??0.25}catch(e){}}}
function syncVideo(t){if(!view||view.mode!=='on_video'||typeof t!=='number')return;const v=videoFor(view.topicId);if(!v||!isFinite(v.duration)||!v.duration)return;const target=t%v.duration;if(Math.abs(v.currentTime-target)>1.0)try{v.currentTime=target}catch(e){}}
async function refreshMine(){if(!view)return;const V=view;try{const s=await rpc('bingo_voice_live_state',{p_session:V.sid});if(view!==V)return;if(!s||s.status==='ended'){liveIndex.delete(String(V.topicId));detachViewer();scheduleCheck();return}if(!me())return renderLive();
 const mine=(s?.participants||[]).find(x=>String(x.user_id)===me())||null;const was=V.my?.state;V.my=mine;
 if(V.mic&&(!mine||mine.state!=='speaker')){stopMyMic();if(was==='speaker')say(mine?.state==='removed'?'The host removed you from speaking.':'You are no longer speaking.')}
 if(V.mic&&mine?.state==='speaker'){const on=!mine.muted;V.mic.getAudioTracks().forEach(t=>t.enabled=on)}
 renderLive()}catch(e){renderLive()}}
async function viewerRequest(){if(!view)return;try{const s=await rpc('bingo_voice_live_request',{p_session:view.sid});view.my=(s?.participants||[]).find(x=>String(x.user_id)===me())||view.my;view.ch?.send({kind:'req',uid:me()});if(view.my?.state==='speaker')await micOn();renderLive()}catch(e){say(String(e?.message||'Could not send your request'))}}
async function respondInvite(accept){if(!view)return;try{await rpc('bingo_voice_live_respond',{p_session:view.sid,p_user:me(),p_accept:accept});view.ch?.send({kind:'roster'});await refreshMine();if(accept)await micOn()}catch(e){say(String(e?.message||'Could not answer the invitation'))}}
async function micOn(){if(!view||view.mic)return;const V=view;let mic;
 try{mic=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true},video:false})}catch(e){say('Microphone permission is needed to speak.');return}
 if(view!==V){mic.getTracks().forEach(t=>t.stop());return}
 let ticket;try{ticket=await rpc('bingo_voice_live_speak_ticket',{p_session:V.sid})}catch(e){mic.getTracks().forEach(t=>t.stop());say(String(e?.message||'You are not a speaker yet'));return}
 V.mic=mic;V.ice.up=[];const pc=new RTCPeerConnection({iceServers:ICE()});V.up=pc;mic.getAudioTracks().forEach(t=>{t.enabled=!(V.my?.muted);pc.addTrack(t,mic)});
 pc.onicecandidate=e=>{if(e.candidate)V.ch?.send({kind:'ice',to:'host',from:V.key,ch:'up',cand:e.candidate.toJSON?e.candidate.toJSON():e.candidate})};
 pc.onconnectionstatechange=()=>{if(['failed','closed'].includes(pc.connectionState)&&view===V&&V.up===pc)stopMyMic()};
 try{const o=await pc.createOffer();await pc.setLocalDescription(o);V.ch?.send({kind:'speak-offer',from:V.key,uid:me(),ticket,sdp:{type:pc.localDescription.type,sdp:pc.localDescription.sdp}})}catch(e){stopMyMic()}
 renderLive()}
function stopMyMic(){if(!view)return;try{view.up?.close()}catch(e){}view.up=null;view.mic?.getTracks().forEach(t=>t.stop());view.mic=null;renderLive()}
async function selfAction(a){if(!view)return;try{const s=await rpc('bingo_voice_live_self',{p_session:view.sid,p_action:a});view.my=(s?.participants||[]).find(x=>String(x.user_id)===me())||null;if(a==='leave')stopMyMic();else if(view.mic)view.mic.getAudioTracks().forEach(t=>t.enabled=!view.my?.muted);view.ch?.send({kind:'roster'});renderLive()}catch(e){say(String(e?.message||'Not allowed'))}}
function viewerClose(){if(!view)return;const id=view.topicId;closedLives.add(id);detachViewer();joinFor=id;renderJoin();schedulePlace()}
function renderJoin(){if(live||view)return;if(!joinFor){if($head().dataset.join){$head().innerHTML='';delete $head().dataset.join}return}$head().dataset.join='1';$head().innerHTML='<div class="bvl-head-row"><span class="bvl-live">LIVE</span><button type="button" class="bvl-chip gold" data-act="rejoin">Join Live</button></div>'}

/* ================================================================== RENDERING (clean screen) */
function renderLive(){if(!live&&!view)return;renderHead();renderTr();renderRail();renderFlap();renderCompose();schedulePlace()}
function renderHead(){const L=live||view;if(!L)return;delete $head().dataset.join;
 const name=live?myName():(view.hostName||memberMeta(view.hostId).name||'Bingo Live+');const photo=live?myPhoto():(view.hostPhoto||memberMeta(view.hostId).photo||'');
 const count=live?live.listeners.size:view.listeners;
 const speakers=live?live.speakers.size:0;
 $head().innerHTML='<div class="bvl-head-row"><img class="bvl-ava" src="'+esc(photoSrc(photo))+'" alt="" onerror="this.style.visibility=\'hidden\'"><span class="bvl-live">LIVE</span><span class="bvl-pill bvl-count" title="Listening now">'+ICON.eye+' '+short(count)+'</span>'+(speakers?'<span class="bvl-pill">🎙 '+speakers+'</span>':'')+'</div>'+
  '<div class="bvl-head-row"><span class="bvl-name">'+esc(name)+' 👑</span>'+meterHTML()+(view&&!view.audioOK&&$audio().srcObject?'<button type="button" class="bvl-chip gold" data-act="listen">🔊 Tap to listen</button>':'')+'</div>'}
function renderTr(){$tr().innerHTML=(live?'<button type="button" class="bvl-sq" data-act="setup" aria-label="Live Setup" title="Live Setup">'+ICON.gear+'</button>':'')+'<button type="button" class="bvl-sq" data-act="'+(live?'end':'close-view')+'" aria-label="'+(live?'End Live':'Close Live')+'" title="'+(live?'End Live':'Close')+'">'+ICON.x+'</button>'}
function rb(act,icon,label,cls,aria){return '<button type="button" class="bvl-rb '+(cls||'')+'" data-act="'+act+'" aria-label="'+esc(aria||label)+'">'+icon+'<span>'+esc(label)+'</span></button>'}
function renderRail(){let h='';
 if(live){if(live.mode==='video'){h+=rb('flip',ICON.flip,'Flip','','Flip camera');h+=rb('dual',ICON.dual,'Dual Cam',live.dualStream?'on':'')}
  h+=rb('mic',live.micOn?ICON.mic:ICON.micOff,'Mic',live.micOn?'':'off',live.micOn?'Mic on — tap to mute':'Mic off — tap to unmute');
  h+=rb('crowns',crownSVG('normal',30),'Crowns','','Crown target')}
 else if(view){h+=rb('crowns',crownSVG('normal',30),'Crown','','Send a Crown');const my=view.my;
  if(my?.state==='speaker'&&view.mic)h+=rb('self-mute',my.muted?ICON.micOff:ICON.mic,my.muted?'Unmute':'Mute',my.muted?'off':'on')+rb('leave-speak',ICON.x,'Leave');
  else if(my?.state==='speaker')h+=rb('mic-on',ICON.mic,'Speak','on','You can speak — turn on mic')+rb('leave-speak',ICON.x,'Leave');
  else if(my?.state==='requested')h+=rb('noop',ICON.hand,'Sent','','Request sent');
  else if(my?.state!=='invited'&&my?.state!=='removed')h+=rb(me()?'request':'login',ICON.hand,'Speak','','Request to Speak')}
 $rail().innerHTML=h}
function renderFlap(){if(!live){$flap().hidden=true;$flap().innerHTML='';return}$flap().hidden=false;$flap().innerHTML='<button type="button" class="bvl-flap'+(transient?.kind==='tray'?' open':'')+'" data-act="tray" aria-label="Live tools" aria-expanded="'+(transient?.kind==='tray')+'">'+ICON.chevron+'Live tools'+(live.requests?' · ✋'+live.requests:'')+'</button>';if(transient?.kind==='tray')renderTray()}
function tb(act,color,icon,label,cls){return '<button type="button" class="bvl-tb '+(cls||'')+'" data-act="'+act+'" style="--c:'+color+'"><i>'+icon+'</i><span>'+esc(label)+'</span></button>'}
function renderTray(){if(!live)return;$tray().innerHTML=tb('mic','#1fb85a',live.micOn?ICON.mic:ICON.micOff,live.micOn?'Mic On':'Mic Off',live.micOn?'':'dim')+(live.mode==='on_video'?tb('orig','#8b3fe0',ICON.sound,{on:'Sound On',ducked:'Reduced',muted:'Muted'}[live.origMode]):'')+tb('invite','#1f6ff0',ICON.invite,'Invite'+(live.requests?' ✋'+live.requests:''))+tb('listeners','#3a4a63',ICON.people,'Listeners ('+short(live.listeners.size)+')')+tb('setup','#262d38',ICON.more,'More Tools')+tb('end','#e5132f',ICON.end,'End Live')}
function renderCompose(){const L=live||view;const el=$comp();if(!L){el.hidden=true;el.innerHTML='';$inv().innerHTML='';return}
 $inv().innerHTML=view&&view.my?.state==='invited'?'<div class="bvl-card bvl-pe"><b>🎙 Invited to speak</b><button type="button" class="bvl-chip gold" data-act="accept-invite">Accept</button><button type="button" class="bvl-chip" data-act="decline-invite">Decline</button></div>':'';
 if(!el.querySelector('#bvlComposeInput')){el.innerHTML='<div class="bvl-cap"><img src="'+esc(photoSrc(myPhoto()))+'" alt="" onerror="this.style.visibility=\'hidden\'"><input id="bvlComposeInput" type="text" maxlength="160" placeholder="Post your view today…" aria-label="Live comment" enterkeyhint="send" autocomplete="off"><button type="button" class="bvl-aa bingo50-trigger" data-act="style" aria-label="Text style">Aa</button></div><button type="button" class="bvl-send" data-act="send" aria-label="Send">'+ICON.send+'</button>';restoreDraft()}
 el.hidden=false}
/* ---------------- meter */
function setMeter(m){if(!m)return;const holder=live||view;if(!holder)return;const prev=holder.meter;holder.meter={q:+m.qualifying_crowns||0,p:+m.progress||0,n:+m.targets_completed||0,raw:m};
 if(prev&&holder.meter.n>prev.n){holder.celebrateUntil=Date.now()+4000;setTimeout(()=>{if(live||view)renderHead()},4100)}
 renderHead();if(transient?.kind==='target')renderTargetPop()}
function meterHTML(){const h=live||view;const m=h?.meter;if(!m)return '<button type="button" class="bvl-meter" data-guide="weekly_crown_target_intro_v1">👑 …/1K</button>';
 if(Date.now()<(h.celebrateUntil||0))return '<button type="button" class="bvl-meter hit" data-guide="weekly_crown_target_intro_v1">🏆 TARGET REACHED · KSh 1,000 earned</button>';
 let extra='';if(m.p>=900)extra=' · '+(1000-m.p)+' left';else if(m.n>0)extra=' · Next KSh 1,000';
 return '<button type="button" class="bvl-meter" data-guide="weekly_crown_target_intro_v1">👑 '+fmt(m.p)+'/1K'+extra+'</button>'}
/* ---------------- comments lane (rise, fade; host comments larger with HOST tag) */
function timeAgo(ts){const s=Math.max(0,Math.round((Date.now()-(ts||Date.now()))/1000));return s<20?'now':s<60?s+'s':Math.round(s/60)+'m'}
function sanitizeStyle(s){if(!s||typeof s!=='object')return null;const F=W.Bingo50Style?.fonts||[];const font=Math.max(0,Math.min(Math.max(0,F.length-1),Number(s.font)||0));const color=/^#[0-9a-fA-F]{6}$/.test(String(s.color||''))?s.color:'#ffffff';return {font,color,bold:!!s.bold,italic:!!s.italic,underline:!!s.underline,effect:/^[a-z]{3,14}$/.test(String(s.effect||''))?s.effect:null}}
function pushComment(m,isHost){const L=live||view;if(!L||!m.text)return;const lane=$lane();
 const el=D.createElement('div');el.className='bvl-c'+(isHost?' host':'');el.style.setProperty('--life',isHost?'14s':'9s');
 el.innerHTML='<img src="'+esc(photoSrc(m.photo||''))+'" alt="" onerror="this.style.visibility=\'hidden\'"><div class="bvl-cb"><div><span class="bvl-cn"></span>'+(isHost?'<span class="bvl-host-tag">HOST</span>':'')+'<span class="bvl-ct">'+timeAgo(m.ts)+'</span></div><div class="bvl-cx"></div></div>';
 el.querySelector('.bvl-cn').textContent=String(m.name||'Bingo Member').slice(0,40);
 const tx=el.querySelector('.bvl-cx');tx.textContent=String(m.text).slice(0,160);
 const st=sanitizeStyle(m.style);if(st&&W.Bingo50Style?.apply){try{W.Bingo50Style.apply(tx,st)}catch(e){}}
 el.addEventListener('animationend',()=>el.remove(),{once:true});
 lane.appendChild(el);while(lane.children.length>6)lane.firstElementChild.remove()}
/* composer draft + style survive closing and reopening (per Live) */
const draftKey=()=>{const L=live||view;return L?'bvl_draft:'+L.sid:null};
function composeStyle(){const inp=D.getElementById('bvlComposeInput');try{return inp?.dataset.bingoStyle?sanitizeStyle(JSON.parse(inp.dataset.bingoStyle)):null}catch(e){return null}}
function saveDraft(){const k=draftKey(),inp=D.getElementById('bvlComposeInput');if(!k||!inp)return;ssSet(k,{text:inp.value||'',style:composeStyle()})}
function restoreDraft(){const k=draftKey(),inp=D.getElementById('bvlComposeInput');if(!k||!inp)return;const d=ssGet(k,null);if(!d)return;if(!inp.value)inp.value=d.text||'';if(d.style&&!inp.dataset.bingoStyle){inp.dataset.bingoStyle=JSON.stringify(d.style);try{W.Bingo50Style?.apply(inp,sanitizeStyle(d.style))}catch(e){}}}
root.addEventListener('input',e=>{if(e.target.id==='bvlComposeInput')saveDraft()});
new MutationObserver(()=>saveDraft()).observe(root,{subtree:true,attributes:true,attributeFilter:['data-bingo-style']});
/* the 50-font panel reads its starting style for our field here (the same reader every other field uses) */
function wrapStyleReader(){if(typeof W.aaBingo50ReadTopic!=='function'||W.aaBingo50ReadTopic.__bvl)return;const o=W.aaBingo50ReadTopic;const w=function(id){if(id==='bvlComposeInput')return composeStyle()||{font:0,color:'#ffffff',bold:false,italic:false,underline:false};return o.apply(this,arguments)};w.__bvl=1;W.aaBingo50ReadTopic=w}
async function sendComment(){const L=live||view;const inp=D.getElementById('bvlComposeInput');const text=String(inp?.value||'').trim();if(!L||!text)return;if(!S().isLoggedIn){try{openAuth('login')}catch(e){}return}
 const style=composeStyle();inp.value='';saveDraft();
 const payload={kind:live?'host-comment':'comment',name:myName(),uid:me(),photo:myPhoto(),text,style};
 if(live)await hostSend(payload);else L.ch?.send({...payload,ts:Date.now()});
 pushComment({...payload,ts:Date.now()},!!live);
 /* the same real comment the post's Comments shows (bingo_topic_comments via aaTopicComment), with the chosen style */
 try{if(typeof aaCommentDraftText!=='undefined'&&typeof aaTopicComment==='function'){const id=L.topicId;const el=D.getElementById('topicComment_'+id);aaCommentDraftText[id]=text;if(el)el.value=text;
  if(style&&typeof aaCommentDraftFmt!=='undefined')aaCommentDraftFmt[id]={font:'bingo50_'+style.font,color:'custom',customColor:style.color,bold:style.bold,italic:style.italic,underline:style.underline};
  await aaTopicComment(id)}}catch(e){}}
root.addEventListener('keydown',e=>{if(e.key==='Enter'&&e.target.id==='bvlComposeInput'){e.preventDefault();sendComment()}});

/* ================================================================== CROWNS (selector, sending states, floating crowns) */
function floatCrown(tier){const t=['normal','bronze','silver','gold'].includes(tier)?tier:'normal';const fx=$fx();if(fx.children.length>6)fx.firstElementChild.remove();const el=D.createElement('div');el.className='bvl-float';el.style.right=(12+Math.round(Math.random()*20))+'px';el.innerHTML=crownSVG(t,t==='normal'?30:38);el.addEventListener('animationend',()=>el.remove(),{once:true});fx.appendChild(el)}
function crownSent(tier){const fx=$fx();const el=D.createElement('div');el.className='bvl-sent';el.innerHTML='<div class="bvl-spark"></div>'+crownSVG(tier,tier==='normal'?40:52)+'<span>Crown Sent!</span>';fx.appendChild(el);setTimeout(()=>el.remove(),1600)}
function openCrowns(){if(!view)return;const p=$pop();p.innerHTML=['normal','bronze','silver','gold'].map((t,i)=>'<div class="bvl-cr '+t+(i===0?' first':'')+'">'+crownSVG(t,t==='normal'?36:42)+'<div><b>'+esc(i===0?TIERS.normal.label:TIERS[t].name)+'</b>'+(t==='normal'?'<small>'+TIERS.normal.note+'</small>':'<span class="bvl-price">KSh '+tierPrice(t)+'</span><small>'+TIERS[t].note+'</small>')+'</div><button type="button" class="bvl-chip gold" data-act="send-crown" data-tier="'+t+'" aria-label="Send '+esc(i===0?TIERS.normal.label:TIERS[t].name)+'">Send</button></div>').join('')+'<div class="bvl-pop-msg" role="status"></div>';
 openTransient('crowns',p,()=>{p.innerHTML=''})}
let payWatch=null;
async function sendCrown(tier,row){if(!view)return;const V=view;const msg=$pop().querySelector('.bvl-pop-msg');row?.classList.add('pick');
 if(!S().isLoggedIn){closeTransient();try{openAuth('login')}catch(e){}return}
 if(tier==='normal'){const t=topicById(V.topicId);try{if(t&&typeof aaTopicHasMyLove==='function'&&aaTopicHasMyLove(t)){if(msg)msg.textContent='You already crowned this Live.';return}if(typeof aaTopicLove==='function')await aaTopicLove(V.topicId)}catch(e){}
  V.ch?.send({kind:'crown',tier:'normal',name:myName(),ts:Date.now()});floatCrown('normal');crownSent('normal');closeTransient();return}
 if(!W.BingoPaidCrowns?.open){if(msg)msg.textContent='Paid Crowns are not available right now.';return}
 if(msg)msg.textContent='Opening M-Pesa…';
 /* the existing paid-Crown checkout (M-Pesa STK) is reused unchanged; only the tier is preselected */
 await W.BingoPaidCrowns.open(V.hostId,V.topicId);
 const pay=D.getElementById('bingoCrownPay');if(!pay||pay.hidden){if(msg)msg.textContent='';return}
 pay.querySelector('[data-tier="'+tier+'"]')?.click();closeTransient();
 watchPayment(pay,tier,V)}
function watchPayment(pay,tier,V){if(payWatch){payWatch.disconnect();payWatch=null}const box=pay.querySelector('.bc-msg');if(!box)return;let done=false;
 const fin=()=>{done=true;payWatch?.disconnect();payWatch=null};
 payWatch=new MutationObserver(()=>{if(done)return;const t=box.textContent||'';
  if(/Crown awarded successfully/i.test(t)){fin();if(view===V){V.ch?.send({kind:'crown',tier,name:myName(),ts:Date.now()});floatCrown(tier);crownSent(tier)}}
  else if(/not completed|Unable to/i.test(t)){fin()}});
 payWatch.observe(box,{childList:true,characterData:true,subtree:true});setTimeout(()=>{if(!done)fin()},75000)}
function renderTargetPop(){if(!live)return;const m=live.meter||{p:0,n:0,q:0};const p=$pop();
 p.innerHTML='<div class="bvl-cr first">'+crownSVG('gold',42)+'<div><b>Weekly Crown Target</b><small>👑 '+fmt(m.p)+' / 1,000 qualifying Crowns · KSh '+fmt(m.p)+' progress'+(m.n?' · '+m.n+' target'+(m.n>1?'s':'')+' this week':'')+'</small></div>'+helpBtn('weekly_crown_target_intro_v1')+'</div><div class="bvl-pop-msg">Viewers send you Crowns from their Crown button. Only paid, genuine Crowns count.</div><button type="button" class="bvl-chip" data-act="open-wallet">Open Crown Wallet</button>'}
function openTargetPop(){if(!live)return;renderTargetPop();openTransient('target',$pop(),()=>{$pop().innerHTML=''})}

/* ================================================================== MODAL SHEETS: launcher, Live Setup, speakers, end */
function openModal(kind,html,layout){mountHosts();closeTransient();modal.dataset.kind=kind;modal.innerHTML=html;modal.style.alignItems=layout==='center'?'center':'flex-end';modal.hidden=false}
function closeModal(){modal.hidden=true;modal.innerHTML='';delete modal.dataset.kind;delete modal.dataset.acc}
modal.addEventListener('pointerdown',e=>e.stopPropagation());
modal.addEventListener('click',e=>{e.stopPropagation();const b=e.target.closest('[data-m]');if(e.target===modal){e.preventDefault();closeModal();return}if(!b||b.disabled)return;e.preventDefault();
 const m=b.dataset.m,uid=b.dataset.uid;
 if(m==='close')return closeModal();
 if(m==='post')return endLive('posted');if(m==='draft')return endLive('draft');if(m==='discard')return endLive('discarded');
 if(m==='tab'){modal.dataset.tab=b.dataset.tab;return renderPeople()}
 if(['invite','accept','decline','mute','unmute','remove'].includes(m))return hostPeopleAction(m,uid);
 if(m==='acc'){const sec=b.closest('.bvl-acc').dataset.sec;modal.dataset.acc=modal.dataset.acc===sec?'':sec;return renderSetup()}
 if(m==='mic'){if((b.dataset.v==='on')!==!!live?.micOn)hostMic();return}
 if(m==='cam'){if((b.dataset.v==='on')!==!!live?.camOn)toggleCam();return}
 if(m==='orig')return setOrig(b.dataset.v);if(m==='flip')return flipCamera();if(m==='dual')return toggleDual();if(m==='quality')return setQuality(+b.dataset.v);
 if(m==='people')return openPeople(b.dataset.tab||'invite');
 if(m==='end')return openEnd();
 if(m==='pick-mode'){modal.dataset.mode=b.dataset.mode;return renderLauncher()}
 if(m==='facing'){modal.dataset.facing=b.dataset.v;return renderLauncher()}
 if(m==='start'){const mode=modal.dataset.mode;const title=modal.querySelector('.bvl-field')?.value||'';const facing=modal.dataset.facing||'user';closeModal();return startLive({mode,title,facing})}
 if(m==='start-on'){const id=b.dataset.topic;closeModal();return startOnMyVideo(id)}
 if(m==='wallet'){closeModal();return openWallet()}});
let searchTimer=0,searchRows=[];
modal.addEventListener('input',e=>{if(!e.target.closest('.bvl-search'))return;clearTimeout(searchTimer);const q=e.target.value.trim();searchTimer=setTimeout(()=>searchPeople(q),300)});
/* ---------------- launcher: Bingo Live+ with three modes */
function openLauncher(pre){if(live){openSetup();return}if(!S().isLoggedIn){try{openAuth('login')}catch(e){}return}
 if(cap.live===false){say('Bingo Live+ is not active on this server yet.');return}
 firstExplain('voice_live_intro_v1',()=>{openModal('launch','<div class="bvl-sheet" role="dialog" aria-modal="true" aria-label="Bingo Live+"></div>');modal.dataset.mode=pre||'';renderLauncher()})}
function myVideoPosts(){try{return (typeof aaTopics==='function'?aaTopics():[]).filter(t=>String(t.authorId||'')===me()&&!t.hiddenFromPublic&&Array.isArray(t.media)&&t.media[0]?.type==='video'&&!/^🔴 LIVE · /.test(t.title||'')).slice(0,30)}catch(e){return []}}
function renderLauncher(){const sh=modal.querySelector('.bvl-sheet');if(!sh||modal.dataset.kind!=='launch')return;const sel=modal.dataset.mode||'';const keepTitle=sh.querySelector('.bvl-field')?.value||'';
 const card=(m,icon,title,sub)=>'<button type="button" class="bvl-mode'+(sel===m?' sel':'')+'" data-m="pick-mode" data-mode="'+m+'"><i>'+icon+'</i><span><b>'+title+'</b><small>'+sub+'</small></span></button>';
 let body='';
 if(sel==='voice'||sel==='video'){body='<div class="bvl-sec">'+MODE_NAME[sel]+'</div><input class="bvl-field" type="text" maxlength="90" placeholder="What is this Live about? (optional)" value="'+esc(keepTitle)+'">'+(sel==='video'?'<div class="bvl-seg" role="group" aria-label="Camera"><button type="button" class="'+((modal.dataset.facing||'user')==='user'?'sel':'')+'" data-m="facing" data-v="user">Front camera</button><button type="button" class="'+(modal.dataset.facing==='environment'?'sel':'')+'" data-m="facing" data-v="environment">Back camera</button></div>':'')+'<button type="button" class="bvl-btn gold wide" data-m="start">🔴 Go Live</button>'}
 else if(sel==='on_video'){const vids=myVideoPosts();body='<div class="bvl-sec">Choose one of your uploaded videos</div>'+(vids.length?vids.map(t=>'<div class="bvl-row"><span>🎬 '+esc(t.title||t.body||'My video')+'</span><button type="button" class="bvl-btn gold" data-m="start-on" data-topic="'+esc(t.id)+'">Go Live</button></div>').join(''):'<div class="bvl-empty">You have no uploaded videos yet. Post a video first, then go live on it.</div>')}
 sh.innerHTML='<h3><span>Bingo Live+ '+helpBtn('voice_live_intro_v1')+'</span><button type="button" class="bvl-x" data-m="close" aria-label="Close">×</button></h3><div class="bvl-scroll">'+
  card('voice',ICON.mic,'Voice Live','Audio discussion with viewers')+card('video',ICON.cam,'Video Live','Live camera broadcast')+card('on_video',ICON.film,'Live on My Video','Add live voice to your uploaded video')+body+'</div>'}
async function startOnMyVideo(topicId){if(S().view!=='home'){S().view='home';try{render()}catch(e){}}
 for(let k=0;k<20&&!itemFor(topicId);k++)await new Promise(r=>setTimeout(r,100));
 const items=[...D.querySelectorAll('#auto-arcade-widget .aa360-feed .aa360-item')];const i=items.findIndex(x=>x.dataset.canon==='topic:'+topicId);if(i>=0&&typeof aaFeedGoTo==='function')aaFeedGoTo(i,'auto');
 for(let k=0;k<20&&!videoFor(topicId);k++)await new Promise(r=>setTimeout(r,100));
 if(!videoFor(topicId)){say('That video is not in your Home feed right now.');return false}
 return startLive({mode:'on_video',topicId})}
/* ---------------- Live Setup (compact accordion; only what fits the current mode) */
function openSetup(){if(!live)return;openModal('setup','<div class="bvl-sheet" role="dialog" aria-modal="true" aria-label="Live Setup"></div>');renderSetup()}
function renderSetup(){const sh=modal.querySelector('.bvl-sheet');if(!sh||modal.dataset.kind!=='setup'||!live)return;const L=live;const open=modal.dataset.acc||'';const scrollTop=sh.querySelector('.bvl-scroll')?.scrollTop||0;
 const acc=(sec,icon,title,body)=>'<div class="bvl-acc'+(open===sec?' open':'')+'" data-sec="'+sec+'"><button type="button" data-m="acc" aria-expanded="'+(open===sec)+'"><i class="bvl-acc-ic">'+icon+'</i><span>'+title+'</span>'+ICON.chevron+'</button>'+(open===sec?'<div class="bvl-acc-body">'+body+'</div>':'')+'</div>';
 const seg=(m,cur,opts)=>'<div class="bvl-seg">'+opts.map(([v,l])=>'<button type="button" class="'+(String(cur)===String(v)?'sel':'')+'" data-m="'+m+'" data-v="'+v+'">'+l+'</button>').join('')+'</div>';
 const el=Math.floor((Date.now()-L.startedAt)/1000);const m=L.meter||{p:0,n:0};
 let h='<h3><span>Live Setup</span><button type="button" class="bvl-x" data-m="close" aria-label="Close">×</button></h3><div class="bvl-scroll"><div class="bvl-sec">Live Mode</div><div class="bvl-seg">'+['voice','video','on_video'].map(x=>'<button type="button" class="'+(L.mode===x?'sel':'')+'"'+(L.mode===x?'':' disabled')+'>'+(x==='on_video'?'On My Video':MODE_NAME[x])+'</button>').join('')+'</div><div class="bvl-note">End this Live to switch mode.</div>';
 h+=acc('sound',ICON.mic,'Microphone &amp; Sound','<div class="bvl-line"><span>Microphone</span></div>'+seg('mic',L.micOn?'on':'off',[['on','On'],['off','Off']])+(L.mode==='on_video'?'<div class="bvl-line"><span>Original video sound</span></div>'+seg('orig',L.origMode,[['on','Normal'],['ducked','Reduced'],['muted','Muted']]):''));
 if(L.mode==='video')h+=acc('camera',ICON.cam,'Camera','<div class="bvl-line"><span>Camera</span></div>'+seg('cam',L.camOn?'on':'off',[['on','On'],['off','Off']])+'<div class="bvl-line"><span>'+(L.facing==='user'?'Front camera':'Back camera')+'</span><button type="button" class="bvl-btn" data-m="flip">Flip camera</button></div><div class="bvl-line"><span>Dual Cam</span><button type="button" class="bvl-btn'+(L.dualStream?' gold':'')+'" data-m="dual">'+(L.dualStream?'On':'Off')+'</button></div><div class="bvl-line"><span>Quality</span></div>'+seg('quality',L.quality,[[480,'480p'],[720,'720p'],[1080,'1080p']]));
 h+=acc('speakers',ICON.people,'Speakers'+(L.requests?' · ✋'+L.requests:''),'<div class="bvl-line"><span>'+L.speakers.size+' speaking · '+L.listeners.size+' listening</span></div><div class="bvl-line"><button type="button" class="bvl-btn gold" data-m="people" data-tab="invite">Invite Speaker</button><button type="button" class="bvl-btn" data-m="people" data-tab="listeners">Listeners</button></div>');
 h+=acc('recording','<b style="color:#ff1f3d">●</b>','Recording','<div class="bvl-line"><span>Replay</span><b>'+(L.rec?(L.rec.stopped?(L.rec.capped?'Stopped at size limit':'Stopped'):'Recording')+' · '+(L.rec.bytes/1048576).toFixed(1)+' MB':'Not available on this device')+'</b></div><div class="bvl-note">When you end, choose Save &amp; Post, Save as Draft or End Without Saving.</div>');
 h+=acc('info','<b>ℹ</b>','Live Information','<div class="bvl-line"><span>Mode</span><b>'+MODE_NAME[L.mode]+'</b></div><div class="bvl-line"><span>Time live</span><b>'+Math.floor(el/60)+':'+String(el%60).padStart(2,'0')+'</b></div><div class="bvl-line"><span>Listening now</span><b>'+L.listeners.size+'</b></div><div class="bvl-line"><span>Weekly Crown target</span><b>👑 '+fmt(m.p)+'/1K</b></div><div class="bvl-line"><button type="button" class="bvl-btn" data-m="wallet">Crown Wallet</button><span style="display:flex;gap:6px">'+helpBtn('weekly_crown_target_intro_v1')+helpBtn('voice_live_intro_v1')+'</span></div>');
 h+='</div><button type="button" class="bvl-btn endbig" data-m="end">End Live</button>';
 sh.innerHTML=h;const sc=sh.querySelector('.bvl-scroll');if(sc)sc.scrollTop=scrollTop}
/* ---------------- speakers drawer */
async function searchPeople(q){const c=client();if(!c||q.length<2){searchRows=[];return renderPeople()}
 try{const {data,error}=await c.from('profiles').select('*').ilike('full_name','%'+q.replace(/[%_,()]/g,' ')+'%').limit(12);searchRows=error?[]:(data||[]).filter(r=>String(r.id)!==me())}catch(e){searchRows=[]}renderPeople()}
function openPeople(tab){if(!live)return;openModal('people','<div class="bvl-sheet" role="dialog" aria-modal="true"><h3><span>Speakers &amp; Listeners</span><button type="button" class="bvl-x" data-m="close" aria-label="Close">×</button></h3><div style="display:flex;gap:6px;margin-bottom:8px"><button type="button" class="bvl-btn" data-m="tab" data-tab="invite">➕ Invite Speaker</button><button type="button" class="bvl-btn" data-m="tab" data-tab="listeners">👥 Listeners</button></div><input class="bvl-search" type="search" placeholder="Search people to invite" aria-label="Search people"><div class="bvl-scroll bvl-list"></div></div>');modal.dataset.tab=tab;searchRows=[];renderPeople();refreshRoster()}
function personRow(uid,name,photo,buttons,sub){return '<div class="bvl-row"><img src="'+esc(photoSrc(photo))+'" alt="" onerror="this.style.visibility=\'hidden\'"><span>'+esc(name||'Bingo Member')+(sub?' <small>'+esc(sub)+'</small>':'')+'</span>'+buttons+'</div>'}
function renderPeople(){if(!live||modal.dataset.kind!=='people')return;const list=modal.querySelector('.bvl-list');if(!list)return;const tab=modal.dataset.tab||'invite';
 const search=modal.querySelector('.bvl-search');if(search)search.hidden=tab!=='invite';
 const byUid=uid=>live.roster.find(x=>String(x.user_id)===String(uid));const nm=uid=>{const l=[...live.listeners.values()].find(x=>x.uid===uid);if(l&&l.name)return {name:l.name,photo:l.photo};const mm=memberMeta(uid);return {name:mm.name,photo:mm.photo}};
 let h='';const req=live.roster.filter(x=>x.state==='requested'),spk=live.roster.filter(x=>x.state==='speaker'),inv=live.roster.filter(x=>x.state==='invited');
 if(req.length)h+='<div class="bvl-sec">Requests to speak</div>'+req.map(r=>{const p=nm(r.user_id);return personRow(r.user_id,p.name,p.photo,'<button type="button" class="bvl-btn gold" data-m="accept" data-uid="'+esc(r.user_id)+'">Accept</button><button type="button" class="bvl-btn" data-m="decline" data-uid="'+esc(r.user_id)+'">Decline</button>')}).join('');
 if(spk.length)h+='<div class="bvl-sec">Speakers</div>'+spk.map(r=>{const p=nm(r.user_id);const connected=live.speakers.has(String(r.user_id));return personRow(r.user_id,p.name,p.photo,'<button type="button" class="bvl-btn" data-m="'+(r.muted?'unmute':'mute')+'" data-uid="'+esc(r.user_id)+'">'+(r.muted?'Unmute':'Mute')+'</button><button type="button" class="bvl-btn red" data-m="remove" data-uid="'+esc(r.user_id)+'">Remove</button>',connected?'🎙 live':'joining…')}).join('');
 if(tab==='invite'){
  if(inv.length)h+='<div class="bvl-sec">Invited</div>'+inv.map(r=>{const p=nm(r.user_id);return personRow(r.user_id,p.name,p.photo,'<button type="button" class="bvl-btn red" data-m="remove" data-uid="'+esc(r.user_id)+'">Cancel</button>')}).join('');
  const shown=new Set(live.roster.map(x=>String(x.user_id)));
  const listenerPeople=[...live.listeners.values()].filter(l=>l.uid&&!shown.has(l.uid));
  const results=searchRows.filter(r=>!shown.has(String(r.id)));
  const q=String(modal.querySelector('.bvl-search')?.value||'').trim();
  if(results.length)h+='<div class="bvl-sec">People</div>'+results.map(r=>{let p={name:'',photo:''};try{p=typeof aaProfileFromRow==='function'?aaProfileFromRow(r,r.id,{}):{name:r.full_name,photo:r.photo_url}}catch(e){}return personRow(r.id,p.name,p.photo||r.photo_url,'<button type="button" class="bvl-btn gold" data-m="invite" data-uid="'+esc(r.id)+'">Invite</button>')}).join('');
  else if(q.length>=2)h+='<div class="bvl-empty">No people found for “'+esc(q)+'”.</div>';
  if(listenerPeople.length)h+='<div class="bvl-sec">Listening now</div>'+listenerPeople.map(l=>personRow(l.uid,l.name,l.photo,'<button type="button" class="bvl-btn gold" data-m="invite" data-uid="'+esc(l.uid)+'">Invite</button>')).join('');
  if(!h)h='<div class="bvl-empty">Search for someone to invite as an audio speaker.</div>'}
 else{const ls=[...live.listeners.values()];h+='<div class="bvl-sec">Listening now · '+ls.length+'</div>'+(ls.length?ls.map(l=>personRow(l.uid,l.name||'Guest listener',l.photo,l.uid&&!byUid(l.uid)?'<button type="button" class="bvl-btn gold" data-m="invite" data-uid="'+esc(l.uid)+'">Invite</button>':'')).join(''):'<div class="bvl-empty">No listeners yet.</div>')}
 list.innerHTML=h}
async function hostPeopleAction(m,uid){if(!live||!uid)return;try{
  if(m==='invite')await rpc('bingo_voice_live_invite',{p_session:live.sid,p_user:uid});
  else if(m==='accept'||m==='decline')await rpc('bingo_voice_live_respond',{p_session:live.sid,p_user:uid,p_accept:m==='accept'});
  else{await rpc('bingo_voice_live_moderate',{p_session:live.sid,p_user:uid,p_action:m});if(m==='remove')dropSpeaker(String(uid));const sp=live.speakers.get(String(uid));if(sp&&sp.gain&&m!=='remove')sp.gain.gain.value=m==='mute'?0:1}
  hostSend({kind:'roster'});await refreshRoster()}catch(e){say(String(e?.message||'Not allowed'))}}

/* ================================================================== ACTION DISPATCH (the catch layer consumes outside taps) */
root.addEventListener('pointerdown',e=>{if(e.target.closest('.bvl-catch')){e.preventDefault();e.stopPropagation();return}if(e.target.closest('button,input,[data-act]'))e.stopPropagation()});
/* window-capture so Live+ controls act before any page-wide click handler (e.g. the paid-Crown checkout,
   which otherwise claims every button whose label mentions "Crown") */
W.addEventListener('click',e=>{const t=e.target;if(!(t instanceof Element)||!root.contains(t))return;if(t.closest('.bvl-catch')){e.preventDefault();e.stopImmediatePropagation();closeTransient();renderFlap();return}
 if(t.closest('[data-guide]'))return;const b=t.closest('[data-act]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();act(b.dataset.act,b)},true);
function act(a,b){switch(a){
 case 'not-now':if(prompt.topicId)dismissed.add(prompt.topicId);return hidePrompt();
 case 'go-live':{const id=prompt.topicId;if(!id)return;return firstExplain('voice_live_intro_v1',()=>startLive({mode:'on_video',topicId:id}))}
 case 'mic':return live?hostMic():null;
 case 'orig':return cycleOrig();
 case 'flip':return flipCamera();case 'dual':return toggleDual();
 case 'invite':closeTransient();return openPeople('invite');case 'listeners':closeTransient();return openPeople('listeners');
 case 'setup':closeTransient();return openSetup();
 case 'end':return openEnd();
 case 'tray':if(transient?.kind==='tray'){closeTransient();renderFlap();return}renderTray();openTransient('tray',$tray(),()=>{$tray().innerHTML=''});renderFlap();return;
 case 'crowns':return live?(transient?.kind==='target'?closeTransient():openTargetPop()):(transient?.kind==='crowns'?closeTransient():openCrowns());
 case 'send-crown':return sendCrown(b.dataset.tier,b.closest('.bvl-cr'));
 case 'open-wallet':closeTransient();return openWallet();
 case 'listen':return playAudio();
 case 'login':try{openAuth('login')}catch(e){}return;
 case 'request':return firstExplain('speaker_intro_v1',viewerRequest);
 case 'accept-invite':return respondInvite(true);case 'decline-invite':return respondInvite(false);
 case 'mic-on':return micOn();
 case 'self-mute':return selfAction(view?.my?.muted?'unmute':'mute');
 case 'leave-speak':return selfAction('leave');
 case 'close-view':return viewerClose();
 case 'rejoin':{const id=joinFor;joinFor=null;if(id){closedLives.delete(id);const info=liveIndex.get(id);if(info)attachViewer(id,info)}scheduleCheck();return}
 case 'style':{const inp=D.getElementById('bvlComposeInput');if(inp&&W.Bingo50Style?.open){wrapStyleReader();W.Bingo50Style.open(inp,'text')}return}
 case 'send':return sendComment();
}}

/* ================================================================== ACTIVE-SLIDE WATCH (no per-render timers) */
let checkQueued=0,lastActiveKey='',leaveTimer=0;
function scheduleCheck(){if(checkQueued)return;checkQueued=setTimeout(check,120)}
function check(){checkQueued=0;const it=activeItem();const id=topicIdOf(it);const key=(S().view||'')+'|'+id;
 /* swiping away detaches from the Live — but only once the new slide has settled: a re-render restores the
    feed's scroll position over a few frames and must not drop and re-connect the Live */
 if(view&&view.topicId!==id){if(!leaveTimer)leaveTimer=setTimeout(()=>{leaveTimer=0;const nid=topicIdOf(activeItem());if(view&&view.topicId!==nid){detachViewer('swipe:'+nid+':'+(S().view||''));scheduleCheck()}},700);schedulePlace();return}
 if(leaveTimer){clearTimeout(leaveTimer);leaveTimer=0}
 if(joinFor&&joinFor!==id){joinFor=null;renderJoin()}
 if(key!==lastActiveKey&&id&&cap.live===true&&!live&&Date.now()-indexAt>15000)refreshIndex();
 if(id&&cap.live===true&&!live&&!view){const info=liveIndex.get(id);if(info&&info.host_id!==me()){if(closedLives.has(id)){if(joinFor!==id){joinFor=id;renderJoin()}}else attachViewer(id,info)}}
 if(key!==lastActiveKey||(!view&&!live)){lastActiveKey=key;if(it&&!live&&!view&&!joinFor)maybePrompt(it);else if(!it||live||view)hidePrompt()}
 if(view&&id===view.topicId)applyViewerVideo();
 if(live&&live.mode==='on_video')applyHostVideo();
 ensureStage();schedulePlace()}
function watchFeed(){const w=D.getElementById('auto-arcade-widget');if(!w){setTimeout(watchFeed,500);return}
 /* a re-render rebuilds the slide: the stage (same element, same stream) is put back at once */
 new MutationObserver(()=>{if(live||view)ensureStage();scheduleCheck()}).observe(w,{subtree:true,attributes:true,attributeFilter:['class'],childList:true});
 W.addEventListener('scroll',schedulePlace,{capture:true,passive:true});W.addEventListener('resize',schedulePlace,{passive:true});
 scheduleCheck()}
W.addEventListener('pagehide',()=>{detachViewer();if(live){try{rpc('bingo_voice_live_end',{p_session:live.sid,p_action:'discarded'})}catch(e){}teardownHost()}});

/* ================================================================== ENTRY POINTS (existing Go Live controls open Bingo Live+) */
const externalStream=()=>!!(W.BINGO_LIVE_API||W.AUTO_ARCADE_LIVE_API);
function wrapEntryPoints(){
 /* Cockpit "Go Live" tile → Bingo Live+ (Live Studio / Record Video keep their own behaviour) */
 if(typeof W.aa92OpenLiveStudio==='function'&&!W.aa92OpenLiveStudio.__bvl){const o=W.aa92OpenLiveStudio;const w=function(mode){if(mode==='live'&&!externalStream()&&cap.live===true)return openLauncher();return o.apply(this,arguments)};w.__bvl=1;W.aa92OpenLiveStudio=w}
 /* Live Studio's own GO LIVE posted to a streaming server that does not exist in this deployment; route it to Video Live */
 if(typeof W.aa92LiveStart==='function'&&!W.aa92LiveStart.__bvl){const o=W.aa92LiveStart;const w=async function(){if(!externalStream()&&cap.live===true){D.getElementById('aa82CameraClose')?.click();return openLauncher('video')}return o.apply(this,arguments)};w.__bvl=1;W.aa92LiveStart=w}}
D.addEventListener('click',e=>{const b=e.target.closest?.('#aa92ShareLive');if(!b||externalStream()||cap.live!==true)return;e.preventDefault();e.stopImmediatePropagation();D.getElementById('aa82CameraClose')?.click();openLauncher('video')},true);

/* ================================================================== WEEKLY CROWN TARGET (wallet card + notices) */
let target={data:null,at:0,loading:false,missing:false,msg:''};
async function loadTarget(force){if(!S().isLoggedIn||!client())return null;if(target.loading)return target.data;if(!force&&target.data&&Date.now()-target.at<60000)return target.data;
 target.loading=true;try{target.data=await rpc('bingo_crown_target_status');target.at=Date.now();target.missing=false;notices(target.data)}catch(e){target.missing=missingFn(e);if(!target.missing)console.warn('Crown target:',e?.message||e)}finally{target.loading=false}
 try{if(typeof aaRequestRender==='function')aaRequestRender()}catch(e){}return target.data}
const NOTE_KEY='bingo_crown_target_notes_v1';
function notices(d){if(!d||!d.period)return;const seenN=lsGet(NOTE_KEY,{}),uid=me(),pid=d.period.id;const k=x=>uid+':'+pid+':'+x;let shown=false;const show=(id,html,ready)=>{if(seenN[k(id)]||shown)return;seenN[k(id)]=1;shown=true;showBanner(html,ready)};
 (d.rewards||[]).filter(r=>r.status==='AVAILABLE').forEach(r=>{const id='ready:'+r.id;if(!seenN[uid+':'+id]){seenN[uid+':'+id]=1;if(!shown){shown=true;showBanner('🟢 KSh '+fmt(r.reward_amount)+' READY — your Crown reward can be withdrawn',true)}}});
 if(d.targets_completed>0)show('reached:'+d.targets_completed,'🏆 Target reached — KSh 1,000 earned (pending until the week ends)');
 if(d.progress>=750)show('near:'+(d.targets_completed+1),'👑 '+fmt(d.progress)+' / 1,000 Crowns — '+(1000-d.progress)+' to your next KSh 1,000');
 lsSet(NOTE_KEY,seenN)}
let bannerTimer=0;
function showBanner(text,ready){mountHosts();banner.className=ready?'ready':'';banner.innerHTML='<span>'+esc(text)+'</span><button type="button" data-b="wallet">Open wallet</button><button type="button" data-b="x" aria-label="Dismiss">×</button>';banner.hidden=false;clearTimeout(bannerTimer);bannerTimer=setTimeout(()=>{banner.hidden=true},9000)}
banner.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();const b=e.target.closest('[data-b]');banner.hidden=true;if(b?.dataset.b==='wallet'||!b)openWallet()});
function openWallet(){try{if(typeof aaBpMenuGo==='function'){aaBpMenuGo('crown-agent');if(S().profileDrawer!=='crown-agent'&&typeof aaProfileDrawerOpen==='function')aaProfileDrawerOpen('crown-agent')}}catch(e){}loadTarget(true)}
function walletGuides(){guideShow('crown_wallet_intro_v1');guideShow('weekly_crown_target_intro_v1')}
function indicatorHTML(d){if(!d)return '<span class="bct-ind">○ 0 / 1,000</span>';
 if(d.indicator==='available')return '<span class="bct-ind available">🟢 KSh '+fmt(d.available_amount)+' READY</span>';
 if(d.indicator==='pending')return '<span class="bct-ind pending">● KSh '+fmt(d.pending_amount)+' Pending</span>';
 return '<span class="bct-ind">○ '+fmt(d.progress)+' / 1,000</span>'}
const STATUS_TXT={EARNED_PENDING:'Pending',AVAILABLE:'READY',WITHDRAWAL_PENDING:'Withdrawal requested',WITHDRAWN:'Withdrawn'};
function targetCardHTML(){if(!S().isLoggedIn)return '';const d=target.data;if(!d&&!target.missing&&!target.loading)loadTarget();
 if(!d&&target.missing)return '<div class="bct-card"><div class="bct-head"><span>👑 Weekly Crown Target</span>'+helpBtn('weekly_crown_target_intro_v1')+'</div><div class="bct-line">'+indicatorHTML(null)+'</div><div class="bct-note">The weekly Crown target activates once the 05 Oct 2026 database update is applied on the server.</div></div>';
 if(!d)return '<div class="bct-card"><div class="bct-head"><span>👑 Weekly Crown Target</span>'+helpBtn('weekly_crown_target_intro_v1')+'</div><div class="bct-line">Loading your target…</div></div>';
 const pct=Math.min(100,d.progress/10);const rewards=(d.rewards||[]).slice(0,12);
 const list=rewards.length?'<div class="bct-list">'+rewards.map(r=>'<div class="bct-entry '+esc(r.status)+'"><span>KSh '+fmt(r.reward_amount)+' · Target '+r.target_number+'</span><b>'+esc(STATUS_TXT[r.status]||r.status)+(r.status==='EARNED_PENDING'?' · '+r.pending_days+(r.pending_days===1?' day':' days')+' left':'')+'</b></div>').join('')+'</div>':'';
 const wd=d.available_amount>0?'<div class="bct-wd"><input type="tel" inputmode="tel" placeholder="M-Pesa number e.g. 0712345678" aria-label="M-Pesa number" class="bct-phone"><button type="button" class="bct-go" data-bct="withdraw">Withdraw KSh '+fmt(d.available_amount)+'</button></div>':'';
 return '<div class="bct-card"><div class="bct-head"><span>👑 Weekly Crown Target</span><span style="display:flex;gap:6px;align-items:center">'+indicatorHTML(d)+helpBtn('crown_wallet_intro_v1')+'</span></div>'+
  '<div class="bct-line">👑 '+fmt(d.progress)+' / 1,000 Crowns · KSh '+fmt(d.progress)+' progress'+(d.targets_completed?' · '+d.targets_completed+' target'+(d.targets_completed>1?'s':'')+' completed this week':'')+'</div>'+
  '<div class="bct-track"><span style="width:'+pct+'%"></span></div><div class="bct-day">Weekly Crown Period · Day '+(d.period?.day||1)+' of 7</div>'+list+wd+
  (d.pending_amount>0?'<div class="bct-note">Pending rewards cannot yet be withdrawn. They turn GREEN when the weekly period ends.</div>':'')+(d.withdrawal_pending_amount>0?'<div class="bct-note">KSh '+fmt(d.withdrawal_pending_amount)+' withdrawal requested — awaiting payout.</div>':'')+(target.msg?'<div class="bct-note">'+esc(target.msg)+'</div>':'')+'</div>'}
D.addEventListener('click',async e=>{const b=e.target.closest?.('[data-bct="withdraw"]');if(!b)return;e.preventDefault();e.stopPropagation();const phone=b.closest('.bct-card')?.querySelector('.bct-phone')?.value||'';
 if(String(phone).replace(/\D/g,'').length<9){target.msg='Enter your M-Pesa number first.';try{render()}catch(x){}return}
 b.disabled=true;try{const r=await rpc('bingo_crown_reward_request_withdrawal',{p_phone:phone});target.msg='Withdrawal of KSh '+fmt(r?.amount)+' requested. It will be paid after review.';await loadTarget(true)}catch(x){target.msg=String(x?.message||'Could not request the withdrawal')}finally{b.disabled=false;try{render()}catch(x){}}},true);
let legacyDashFailed=false;
function wrapDashboard(){if(typeof W.aaCreatorCrownAgentDashboardHTML!=='function'||W.aaCreatorCrownAgentDashboardHTML.__bct)return;const orig=W.aaCreatorCrownAgentDashboardHTML;
 const wrapped=function(){let html='';try{html=orig.apply(this,arguments)}catch(e){html=''}
  if(legacyDashFailed&&/Loading your Crown Agent Dashboard/.test(html))html='';   /* legacy RPC not on the server: no permanent "Loading…" */
  if(S().isLoggedIn&&(!seen('crown_wallet_intro_v1')||!seen('weekly_crown_target_intro_v1')))setTimeout(walletGuides,300);
  return targetCardHTML()+html};wrapped.__bct=1;W.aaCreatorCrownAgentDashboardHTML=wrapped;
 if(typeof W.aaCreatorDashboardLoad==='function'&&!W.aaCreatorDashboardLoad.__bct){const ol=W.aaCreatorDashboardLoad;const wl=async function(){const r=await ol.apply(this,arguments);legacyDashFailed=r==null&&!!S().isLoggedIn;if(legacyDashFailed)try{render()}catch(e){}return r};wl.__bct=1;W.aaCreatorDashboardLoad=wl}}
const NOTICE_RX=/KSh 1,000 READY|Target reached — KSh 1,000|\/ 1,000 Crowns|Open your Crown Wallet/;
D.addEventListener('click',e=>{if(S().view!=='inbox')return;let el=e.target;for(let i=0;el&&i<5;i++,el=el.parentElement){const t=el.textContent||'';if(t.length>600)return;if(NOTICE_RX.test(t)){setTimeout(openWallet,0);return}}});

/* ================================================================== SMART TRENDING (stable per session) */
const TREND_KEY='bingo_trending_v1';
const trendCache=lsGet(TREND_KEY,null);
const trendMap=new Map(trendCache&&Date.now()-trendCache.at<6*3600e3?(trendCache.rows||[]).map(r=>[String(r.topic_id),+r.score||0]):[]);
async function refreshTrending(){try{const rows=await rpc('bingo_topic_trending_scores',{p_limit:200,p_hours:168});lsSet(TREND_KEY,{at:Date.now(),rows:(rows||[]).slice(0,200)})}catch(e){}}
function wrapFeedOrder(){if(typeof W.aaMixedFeedItems!=='function'||W.aaMixedFeedItems.__trend)return;const orig=W.aaMixedFeedItems;
 /* scores come from the previous session's cache, so the order never shifts under the viewer mid-session */
 const wrapped=function(){let all=orig.apply(this,arguments);if(!Array.isArray(all))return all;
  if(trendMap.size){const keyed=all.map((x,i)=>{let lift=0;if(x&&x.kind==='topic'&&!x._promoType){const s=trendMap.get(String(x._topicId||x.source?.id||''))||0;if(s>0)lift=Math.min(8,Math.round(Math.log2(1+s)*1.5))}return {x,k:i-lift,i}});
   keyed.sort((a,b)=>a.k-b.k||a.i-b.i);all=keyed.map(o=>o.x)}
  if(livePlacement.size){for(const [tid,anchor] of livePlacement){const i=all.findIndex(x=>x&&x.kind==='topic'&&String(x._topicId)===tid);const a=all.findIndex(x=>x&&String(x.id)===anchor);if(i<0||a<0||i===a+1)continue;const [it]=all.splice(i,1);const a2=all.findIndex(x=>x&&String(x.id)===anchor);all.splice(a2+1,0,it)}}
  return all};wrapped.__trend=1;W.aaMixedFeedItems=wrapped}

/* ================================================================== BOOT */
function boot(){mountHosts();wrapDashboard();wrapFeedOrder();wrapEntryPoints();wrapStyleReader();watchFeed();
 const tryLive=async()=>{if(!client()){setTimeout(tryLive,1500);return}const ok=await probeLive();if(ok)scheduleCheck();wrapEntryPoints();refreshTrending()};
 setTimeout(tryLive,1200);
 let lastUid='';
 setInterval(()=>{if(D.visibilityState!=='visible')return;if(S().view==='home'&&cap.live===true)refreshIndex();const uid=me();if(uid!==lastUid){lastUid=uid;target={data:null,at:0,loading:false,missing:false,msg:''};if(uid){syncAcks();loadTarget(true)}}else if(uid&&Date.now()-target.at>300000)loadTarget(true)},45000);
 setTimeout(()=>{const uid=me();lastUid=uid;if(uid){syncAcks();loadTarget(true)}},2500)}
if(D.readyState==='loading')D.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

W.BingoVoiceLive={version:'2026-10-05-live-plus',
 status:()=>({backend:cap.live,live:live?{session:live.sid,topic:live.topicId,mode:live.mode,listeners:live.listeners.size,speakers:[...live.speakers.keys()],peers:live.peers.size,videoPeers:[...live.peers.values()].filter(p=>p.video).length,origMode:live.origMode,mic:live.micOn,cam:live.camOn,facing:live.facing,dual:!!live.dualStream,quality:live.quality,recording:!!live.rec,recordedBytes:live.rec?.bytes||0,signed:!!live.keys}:null,
  viewer:view?{session:view.sid,topic:view.topicId,mode:view.mode,connected:!!view.pc,audio:view.audioOK,video:!!view.stream?.getVideoTracks().length,audioOnly:view.audioOnly,speaking:!!view.mic,state:view.my?.state||null,listeners:view.listeners,verified:!!view.hostKey}:null,
  prompt:prompt.topicId,joinFor,stats:{...stats},liveTopics:[...liveIndex.keys()],target:target.data,targetMissing:target.missing,transient:transient?.kind||null,modal:modal.hidden?null:modal.dataset.kind}),
 openLauncher,startLive,refreshIndex,loadTarget,openWallet,guide:{show:guideShow,keys:Object.keys(GUIDES),seen},_probe:()=>{cap.live=null;return probeLive()},
 _refreshMeter:()=>refreshMeter(),
 _forcePrompt:want=>{if(live||view||cap.live!==true)return false;const id=topicIdOf(activeItem());if(want&&id!==want)return false;dismissed.clear();hidePrompt();const t=topicById(id);if(!t||String(t.authorId||t.user_id||'')!==me())return false;prompt.topicId=id;showPromptNow();return true}};
W.BingoGuide={show:k=>guideShow(k,true),showOnce:k=>guideShow(k,false),seen,keys:Object.keys(GUIDES)};
})();
