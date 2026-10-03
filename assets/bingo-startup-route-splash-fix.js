/* Bingo startup-only repair — 2026-10-03.
   Scope: prevent a stale session route from overriding the default Home
   destination during bingoBoot(), and suppress/remove the detached
   post-splash #bingoWelcomeMark. No feed/layout/feature logic lives here. */
(function(){
  "use strict";
  try{ sessionStorage.removeItem("aa_current_route"); }catch(e){}

  var style=document.createElement("style");
  style.id="bingo-startup-route-splash-fix-style";
  style.textContent="#bingoWelcomeMark{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important}";
  (document.head||document.documentElement).appendChild(style);

  function removeWelcomeMark(){
    var mark=document.getElementById("bingoWelcomeMark");
    if(mark) mark.remove();
  }
  removeWelcomeMark();

  var observer=new MutationObserver(function(){
    removeWelcomeMark();
  });
  observer.observe(document.documentElement,{childList:true,subtree:true});
  window.setTimeout(function(){
    removeWelcomeMark();
    observer.disconnect();
  },5000);
})();
