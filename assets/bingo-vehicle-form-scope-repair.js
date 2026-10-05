/* Bingo vehicle form scope repair — surgical only.
   The vehicle upload page must contain vehicle controls only.
   Category directory routing remains in the Categories page. */
(function(){'use strict';
if(window.__bingoVehicleFormScopeRepair)return;window.__bingoVehicleFormScopeRepair=true;
function repair(){
 const title=document.getElementById('vTitle');
 if(!title)return;
 const form=title.closest('.modal'); if(!form)return;
 /* Restore the canonical vehicle form title/instruction that already exists in addHTML(). */
 const h=form.querySelector('h2');
 if(h&&/create bingo master listing/i.test(h.textContent||''))h.textContent='Post a Vehicle';
 const intro=h&&h.nextElementSibling;
 if(intro&&intro.tagName==='P'&&/post about|structured details|viewed as/i.test(intro.textContent||'')){
   intro.textContent='Choose For Sale or For Hire, then choose exactly one media format: one video OR up to six photos.';
 }
 /* Remove only the cross-category switcher injected into the vehicle form.
    Do not touch the real vehicle Category select (SUV/Saloon/Pickup/etc.). */
 form.querySelectorAll('[data-du1-inline-cat]').forEach(btn=>{
   const box=btn.closest('.du1-clean-card');
   if(box&&/post about/i.test(box.textContent||''))box.remove();
 });
}
let q=0;
new MutationObserver(()=>{clearTimeout(q);q=setTimeout(repair,40)}).observe(document.documentElement,{subtree:true,childList:true});
document.addEventListener('click',()=>setTimeout(repair,0),true);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',repair,{once:true});else repair();
})();