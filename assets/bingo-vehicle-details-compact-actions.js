/* Bingo Vehicle Details compact action cleanup — 2026-10-05.
   Surgical presentation only: de-duplicates repeated actions, compacts approved neon controls,
   and moves owner edit/delete into a three-dot Settings menu. Existing button nodes/click wiring are preserved. */
(function(){'use strict';if(window.__bingoVehicleActionCleanup)return;window.__bingoVehicleActionCleanup=1;
const ROOT='#auto-arcade-widget', N=s=>(s||'').replace(/\s+/g,' ').trim(), low=e=>N(e.textContent).toLowerCase();
const css=document.createElement('style');css.textContent=`
.bingo-vehicle-actions-compact{display:flex!important;gap:8px!important;align-items:center!important;flex-wrap:wrap!important}
.bingo-vehicle-actions-compact>button,.bingo-vehicle-actions-compact>a,.bingo-vehicle-actions-compact>[role=button]{width:auto!important;min-width:0!important;min-height:38px!important;padding:8px 12px!important;margin:0!important;border-radius:13px!important;font-size:14px!important;line-height:1.1!important;box-shadow:0 0 9px rgba(245,189,0,.24)!important}
.bingo-vehicle-settings-wrap{position:relative!important;display:inline-flex!important}
.bingo-vehicle-settings-trigger{width:40px!important;height:38px!important;min-width:40px!important;padding:0!important;border:1px solid #f5bd00!important;border-radius:13px!important;background:#081426!important;color:#fff!important;font-size:22px!important;box-shadow:0 0 10px rgba(245,189,0,.3)!important}
.bingo-vehicle-settings-menu{display:none;position:absolute;right:0;bottom:46px;z-index:2147481000;min-width:175px;padding:7px;border:1px solid #f5bd00;border-radius:14px;background:#071222;box-shadow:0 0 18px rgba(0,0,0,.55)}
.bingo-vehicle-settings-menu.open{display:flex;flex-direction:column;gap:6px}
.bingo-vehicle-settings-menu>button,.bingo-vehicle-settings-menu>a{width:100%!important;min-height:36px!important;padding:7px 10px!important;margin:0!important;border-radius:10px!important;font-size:13px!important}
.bingo-vehicle-action-hidden{display:none!important}
`;document.head.appendChild(css);
function vehiclePage(){const r=document.querySelector(ROOT)||document.body;const t=N(r.innerText).toLowerCase();return t.includes('vehicle details')&&(/listing|mileage|transmission|fuel/.test(t))}
function buttons(){return [...document.querySelectorAll(ROOT+' button,'+ROOT+' a,'+ROOT+' [role="button"]')].filter(e=>e.offsetParent!==null)}
function key(e){let t=low(e).replace(/[♡♥☎✉✎↻↓↑←→]/g,'').trim();if(t==='call'||t==='call seller')return'call';if(t==='message'||t==='message seller')return'message';if(t==='whatsapp'||t==='whatsapp seller')return'whatsapp';if(t==='boost'||t==='boost / promote')return'boost';if(/^share/.test(t))return'share';if(t.includes('favourite')||t.includes('favorite'))return'favourite';return t}
function apply(){
 if(!vehiclePage())return;const bs=buttons(), groups={};bs.forEach(b=>{const k=key(b);(groups[k]||(groups[k]=[])).push(b)});
 ['call','message','whatsapp','boost'].forEach(k=>{const a=groups[k]||[];a.slice(1).forEach(e=>e.classList.add('bingo-vehicle-action-hidden'))});
 const primary=['call','whatsapp','message','share','favourite','boost'].map(k=>(groups[k]||[])[0]).filter(Boolean);
 if(primary.length){let host=primary[0].parentElement;host.classList.add('bingo-vehicle-actions-compact');primary.forEach(e=>{if(e.parentElement!==host)host.appendChild(e)})}
 const edit=bs.find(e=>low(e).includes('edit my post')), del=bs.find(e=>low(e).includes('delete my post'));
 if((edit||del)&&!document.querySelector('.bingo-vehicle-settings-wrap')){
   const anchor=(primary[0]&&primary[0].parentElement)||(edit||del).parentElement,w=document.createElement('span');w.className='bingo-vehicle-settings-wrap';
   const trigger=document.createElement('button');trigger.type='button';trigger.className='bingo-vehicle-settings-trigger';trigger.setAttribute('aria-label','Listing settings');trigger.textContent='⋮';
   const menu=document.createElement('span');menu.className='bingo-vehicle-settings-menu';[edit,del].filter(Boolean).forEach(e=>menu.appendChild(e));
   trigger.addEventListener('click',ev=>{ev.stopPropagation();menu.classList.toggle('open')});document.addEventListener('click',()=>menu.classList.remove('open'));
   w.append(trigger,menu);anchor.appendChild(w);
 }
 /* The standalone current-photo download control duplicates Save/Download behavior and is not a listing action. Hide presentation only. */
 bs.filter(e=>low(e).includes('download current photo')).forEach(e=>e.classList.add('bingo-vehicle-action-hidden'));
}
let q=0;new MutationObserver(()=>{clearTimeout(q);q=setTimeout(apply,120)}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();