/* Bingo root landing + Agent Invite modal guard — surgical runtime repair.
   Public/root always lands on existing Home feed. Agent Invite remains available only
   to signed-in owners when deliberately opened, with its native X close handler. */
(function(){
 'use strict';
 function isRoot(){return location.pathname==='/'||/BINGO_MASTER_CURRENT_VERIFIED\.html$/i.test(location.pathname)}
 function text(el){return String(el&&el.textContent||'')}
 function isRawInvite(el){
   var s=text(el);
   return s.indexOf('Invite a Bingo Agent')>=0 &&
     (s.indexOf('${esc(t.searchEmail)}')>=0||s.indexOf('${t.foundAgent')>=0||s.indexOf('${perms.map')>=0);
 }
 function killRawInvite(){
   var all=document.querySelectorAll('body *');
   for(var i=0;i<all.length;i++){
     if(!isRawInvite(all[i]))continue;
     var p=all[i];
     while(p.parentElement&&p.parentElement!==document.body&&isRawInvite(p.parentElement))p=p.parentElement;
     p.remove();
     return true;
   }
   return false;
 }
 function restoreHome(){
   if(!isRoot())return;
   try{
     /* Never carry an invite modal into a fresh/root visit. */
     if(window.state){
       state.agentInviteTarget=null;
       if(!state.view||/agentinvite|inviteagent/i.test(String(state.view)))state.view='home';
     }
     killRawInvite();
     if(window.state&&state.view==='home'&&typeof window.render==='function')window.render();
   }catch(e){}
 }
 function guardNativeModal(){
   try{
     if(!window.state)return;
     /* A legitimate Agent invite can exist only after authentication and an explicit target. */
     if(state.agentInviteTarget&&!state.isLoggedIn){
       state.agentInviteTarget=null;
       if(typeof window.render==='function')window.render();
     }
   }catch(e){}
 }
 function run(){restoreHome();guardNativeModal();killRawInvite()}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',run,{once:true});else run();
 var n=0,poll=setInterval(function(){run();if(++n>40)clearInterval(poll)},250);
 new MutationObserver(function(){guardNativeModal();killRawInvite()}).observe(document.documentElement,{childList:true,subtree:true});
 /* Backdrop click closes only a legitimate Agent Invite; native X still works. */
 document.addEventListener('click',function(e){
   try{
     if(!state||!state.agentInviteTarget)return;
     var modal=e.target.closest&&e.target.closest('.modal');
     var overlay=e.target.closest&&e.target.closest('.overlay');
     if(overlay&&!modal&&typeof window.aaCloseInviteAgentModal==='function')window.aaCloseInviteAgentModal();
   }catch(_){}
 },true);
})();