/* Messenger white/colorful presentation activator. No data/backend mutations. */
(function(){
 function sync(){
  try{
   var s=window.state||{};
   var v=String(s.view||'').toLowerCase();
   var on=v==='inbox'||v==='chat'||v==='messenger'||!!document.querySelector('#auto-arcade-widget .msg-thread');
   document.body&&document.body.classList.toggle('bingo-messenger-white-mode',on);
  }catch(e){}
 }
 sync();
 new MutationObserver(sync).observe(document.documentElement,{childList:true,subtree:true});
 addEventListener('click',function(){setTimeout(sync,0)},true);
})();
