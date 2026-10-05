/* Bingo Vehicles category routing — surgical 2026-10-05.
   Categories > Vehicles is BROWSE ONLY. Vehicle upload remains available only
   from explicit Post/Add/Sell vehicle controls. No master-file rewrite. */
(function(){'use strict';
if(window.__bingoVehicleCategoryBrowseRepair)return;window.__bingoVehicleCategoryBrowseRepair=true;
const norm=s=>(s||'').replace(/\s+/g,' ').trim().toLowerCase();
const uploadWords=/\b(post|add|upload|sell|create|publish|list)\b/;
const categoryWords=/\b(categories|all categories|category)\b/;
function isVehicleUploadOpen(){return !!document.getElementById('vTitle')||[...document.querySelectorAll('h1,h2,h3')].some(e=>/post a vehicle|add vehicle|create.*vehicle/i.test(e.textContent||''));}
function inCategories(el){
  const box=el.closest('[id*="cat" i],[class*="cat" i],main,section,.modal,.drawer');
  const txt=norm(box&&box.innerText);
  return categoryWords.test(txt)||/all categories/.test(norm(document.body&&document.body.innerText));
}
function isVehiclesCategoryControl(el){
  if(!el)return false; const t=norm(el.textContent||el.getAttribute('aria-label')||el.getAttribute('title'));
  if(!(t==='vehicles'||t==='vehicle'||t==='cars & vehicles'||t==='cars and vehicles'))return false;
  if(uploadWords.test(t))return false;
  return inCategories(el);
}
function clickNativeBrowse(exclude){
  const controls=[...document.querySelectorAll('button,a,[role="button"]')];
  const exact=['browse vehicles','view vehicles','vehicle marketplace','all vehicles','vehicles for sale','cars for sale'];
  for(const label of exact){
    const x=controls.find(e=>e!==exclude&&norm(e.textContent)===label&&!uploadWords.test(norm(e.textContent)));
    if(x){x.click();return true}
  }
  return false;
}
function tryExistingRoute(){
  if(!window.state||typeof window.render!=='function')return false;
  const old=state.view;
  for(const v of ['vehicles','vehicle_listings','browse_vehicles','vehicle-marketplace']){
    try{
      state.view=v; window.render();
      if(!isVehicleUploadOpen() && /vehicle|car/i.test(document.body.innerText||''))return true;
    }catch(_){}
  }
  try{state.view=old;window.render()}catch(_){}
  return false;
}
function openVehicleBrowse(source){
  if(clickNativeBrowse(source))return;
  if(tryExistingRoute())return;
  /* Last-resort: return to the existing Categories directory instead of ever
     misleading the user by opening an upload form. */
  const cat=[...document.querySelectorAll('button,a,[role="button"]')].find(e=>norm(e.textContent)==='categories');
  if(cat&&cat!==source)cat.click();
}
document.addEventListener('click',function(e){
  const c=e.target.closest&&e.target.closest('button,a,[role="button"]');
  if(!isVehiclesCategoryControl(c))return;
  e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
  openVehicleBrowse(c);
},true);

/* Keep non-vehicle directory categories out of the vehicle-upload surface.
   This only targets explicit cross-category controls; it does not alter fields
   such as make/model/year/fuel/transmission/body type. */
const foreign=/^(property|properties|food|restaurants?|jobs?|cvs?|electronics|household items|spare parts|services|fashion|beauty|events|stay|stays)$/;
function cleanVehicleUpload(){
  const title=document.getElementById('vTitle'); if(!title)return;
  const form=title.closest('.modal')||title.closest('form')||title.parentElement; if(!form)return;
  form.querySelectorAll('[data-du1-inline-cat],button,a,[role="button"]').forEach(el=>{
    if(foreign.test(norm(el.textContent))){
      const card=el.closest('[data-du1-inline-cat],.du1-clean-card');
      if(card&&card!==form)card.remove(); else if(el.hasAttribute('data-du1-inline-cat'))el.remove();
    }
  });
}
let timer=0;new MutationObserver(()=>{clearTimeout(timer);timer=setTimeout(cleanVehicleUpload,50)})
.observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',cleanVehicleUpload,{once:true});else cleanVehicleUpload();
})();