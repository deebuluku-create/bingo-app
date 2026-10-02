/* Surgical landing repair — hide only the accidental raw Agent invitation template on root landing. */
(function(){
 'use strict';
 function rawAgentModal(el){
   if(!el||!el.textContent)return false;
   var t=el.textContent;
   return t.indexOf('Invite a Bingo Agent')>=0 && (t.indexOf('${esc(')>=0 || t.indexOf('${perms.map(')>=0 || t.indexOf('${t.foundAgent')>=0);
 }
 function repair(){
   var nodes=document.querySelectorAll('body *');
   for(var i=0;i<nodes.length;i++){
     var el=nodes[i];
     if(rawAgentModal(el)){
       var p=el;
       while(p.parentElement && p.parentElement!==document.body && p.parentElement.textContent.indexOf('Invite a Bingo Agent')>=0) p=p.parentElement;
       p.style.display='none';
       p.setAttribute('aria-hidden','true');
       try{ if(typeof window.closeModal==='function') window.closeModal(); }catch(e){}
       try{ if(window.state && (!state.view || /agent/i.test(String(state.view)))) { state.view='feed'; if(typeof window.render==='function') window.render(); } }catch(e){}
       return true;
     }
   }
   return false;
 }
 function rootLanding(){
   return location.pathname==='/' || /BINGO_MASTER_CURRENT_VERIFIED\.html$/i.test(location.pathname);
 }
 function run(){if(rootLanding())repair()}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',run,{once:true}); else run();
 var n=0,t=setInterval(function(){run();if(++n>30)clearInterval(t)},250);
 new MutationObserver(function(){if(rootLanding())repair()}).observe(document.documentElement,{childList:true,subtree:true});
})();