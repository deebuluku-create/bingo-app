/* Bingo Live Guest UI bridge — REVIEW
   Load after assets/bingo-live-guest-webrtc.js in the existing master HTML.
   It deliberately does not redesign Live Studio.
*/
(function(){
 const $=(s,r=document)=>r.querySelector(s);
 function remoteVideo(stream){
   let v=$('#bingoLiveGuestRemote');
   if(!v){v=document.createElement('video');v.id='bingoLiveGuestRemote';v.autoplay=true;v.playsInline=true;
     v.style.cssText='position:absolute;right:12px;bottom:150px;width:34%;max-width:240px;aspect-ratio:9/16;object-fit:cover;border:2px solid #d7ae28;border-radius:16px;background:#071426;z-index:20';
     (document.fullscreenElement||document.body).appendChild(v);}
   v.srcObject=stream;
 }
 window.addEventListener('bingo-live-remote-stream',e=>remoteVideo(e.detail));
 window.addEventListener('bingo-live-guest-ended',()=>{const v=$('#bingoLiveGuestRemote');if(v)v.remove();});
 window.BingoLiveGuestUI={
   async request(liveId,hostId){return window.BingoLiveGuest.requestJoin(liveId,hostId);},
   async hostListen(liveId){
     const sb=window.supabaseClient; const {data}=await sb.auth.getUser(); if(!data.user) throw Error('Sign in required');
     return window.BingoLiveGuest.subscribe(liveId,data.user.id,p=>{
       const row=p.new||p.old;
       if(row&&row.status==='pending'&&row.host_id===data.user.id)
         window.dispatchEvent(new CustomEvent('bingo-live-guest-request',{detail:row}));
     });
   },
   accept:r=>window.BingoLiveGuest.accept(r),
   decline:()=>window.BingoLiveGuest.decline(),
   remove:()=>window.BingoLiveGuest.remove(),
   leave:()=>window.BingoLiveGuest.leave()
 };
})();