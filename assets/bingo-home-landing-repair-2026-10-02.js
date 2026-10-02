/* Emergency removal: obsolete/broken Invite a Bingo Agent frontend UI.
   Backend tables/RPCs are intentionally untouched. */
(function(){
 'use strict';
 function containsInvite(s){return /Invite a Bingo Agent/i.test(String(s||''))}
 function purge(){
   try{if(window.state)state.agentInviteTarget=null}catch(e){}
   var nodes=document.querySelectorAll('body *');
   for(var i=nodes.length-1;i>=0;i--){
     var el=nodes[i], s=el.textContent||'';
     if(!containsInvite(s))continue;
     /* Prefer deleting the overlay/modal containing the heading. */
     var h=el.matches&&el.matches('h1,h2,h3')?el:null;
     if(!h){
       var hs=el.querySelectorAll&&el.querySelectorAll('h1,h2,h3');
       for(var j=0;hs&&j<hs.length;j++)if(containsInvite(hs[j].textContent)){h=hs[j];break}
     }
     if(!h)continue;
     var target=h.closest('.overlay,.modal,[role="dialog"]')||h.parentElement;
     if(target&&target.parentElement&&target.classList.contains('modal')&&target.parentElement.classList.contains('overlay'))target=target.parentElement;
     if(target)target.remove();
   }
 }
 function disable(){
   /* Make accidental legacy calls harmless. */
   window.aaOpenInviteAgentModal=function(){try{if(window.state)state.agentInviteTarget=null}catch(e){};purge();};
   window.aaInviteAgentModalHTML=function(){return '';};
 }
 function run(){disable();purge()}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',run,{once:true});else run();
 new MutationObserver(run).observe(document.documentElement,{childList:true,subtree:true});
 setTimeout(run,0);setTimeout(run,100);setTimeout(run,500);setTimeout(run,1500);
})();