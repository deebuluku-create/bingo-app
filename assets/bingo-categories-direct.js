/* Bingo Categories routing repair — surgical add-on, verified master untouched.
   Retires the Auto Market / Spare Parts intermediate screen while preserving its
   Spare Parts and Household Items destinations inside the existing Categories UI. */
(function(){
'use strict';
if(window.__bingoCategoriesDirectRepair)return;window.__bingoCategoriesDirectRepair=true;
const norm=s=>(s||'').replace(/\s+/g,' ').trim().toLowerCase();
const isAutoPage=()=>/auto market/.test(norm(document.body&&document.body.innerText))&&
  /spare parts/.test(norm(document.body&&document.body.innerText))&&
  /household items/.test(norm(document.body&&document.body.innerText));

function findCategoriesTrigger(){
  return [...document.querySelectorAll('button,a,[role="button"]')].find(e=>{
    const t=norm(e.textContent), a=norm(e.getAttribute('aria-label')), title=norm(e.getAttribute('title'));
    return t==='categories'||a==='categories'||title==='categories';
  });
}
function openCategories(){
  const b=findCategoriesTrigger();
  if(b){b.click();return true}
  /* Use only existing app routing functions/state if the visible trigger is not mounted. */
  const candidates=['openCategories','showCategories','goCategories','aaOpenCategories','bgcOpenCategories'];
  for(const k of candidates)if(typeof window[k]==='function'){try{window[k]();return true}catch(_){}}
  if(window.state){
    const views=['categories','all_categories','category'];
    for(const v of views){
      try{
        const old=state.view;state.view=v;
        if(typeof window.render==='function'){window.render();if(findCategoriesTrigger()||/categor/.test(norm(document.body.innerText)))return true}
        state.view=old;
      }catch(_){}
    }
  }
  return false;
}
function addCategoryEntries(){
  /* Do not manufacture a second category system. Only augment the already-open Categories directory. */
  const body=norm(document.body&&document.body.innerText);
  if(!/categor/.test(body))return;
  const hosts=[...document.querySelectorAll('[id*="cat" i],[class*="cat" i]')].filter(e=>e.querySelectorAll('button,a,[role="button"]').length);
  const host=hosts.sort((a,b)=>b.querySelectorAll('button,a,[role="button"]').length-a.querySelectorAll('button,a,[role="button"]').length)[0];
  if(!host)return;
  const existing=[...host.querySelectorAll('button,a,[role="button"]')];
  function ensure(label,match){
    if(existing.some(e=>norm(e.textContent).includes(match)))return;
    /* Clone a category control so the existing appearance/shape/style is inherited exactly. */
    const seed=existing.find(e=>norm(e.textContent)&&!['categories','back'].includes(norm(e.textContent)));
    if(!seed)return;
    const n=seed.cloneNode(true);n.removeAttribute('id');n.dataset.bingoMovedCategory=match;
    const leaf=[...n.querySelectorAll('*')].reverse().find(e=>e.children.length===0&&norm(e.textContent))||n;
    leaf.textContent=label;
    n.onclick=function(ev){
      ev.preventDefault();ev.stopPropagation();
      /* Reuse the retired page's own tab destination without exposing the intermediate screen. */
      const all=[...document.querySelectorAll('button,a,[role="button"]')];
      const target=all.find(e=>e!==n&&norm(e.textContent)===match);
      if(target)target.click();
      else document.dispatchEvent(new CustomEvent('bingo:open-category',{detail:{category:label}}));
    };
    host.appendChild(n);
  }
  ensure('Spare Parts','spare parts');ensure('Household Items','household items');
}
let handling=false;
function repair(){
  if(handling)return;
  if(isAutoPage()){
    handling=true;
    requestAnimationFrame(()=>{openCategories();setTimeout(()=>{handling=false;addCategoryEntries()},250)});
    return;
  }
  addCategoryEntries();
}
document.addEventListener('click',e=>{
  const b=e.target.closest&&e.target.closest('button,a,[role="button"]');if(!b)return;
  const t=norm(b.textContent);
  /* If a navigation control explicitly points at the retired Auto Market screen,
     allow the app to resolve it, then immediately replace it with Categories. */
  if(t==='categories'||/auto market/.test(t))setTimeout(repair,0);
},true);
let q=0;new MutationObserver(()=>{clearTimeout(q);q=setTimeout(repair,180)})
 .observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',repair,{once:true});else repair();
})();