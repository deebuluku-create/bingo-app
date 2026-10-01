/* Bingo Live Guest WebRTC client — REVIEW MODULE
   Expects window.supabaseClient (existing Bingo authenticated client).
   Configure TURN in window.BINGO_LIVE_ICE_SERVERS before production.
*/
(function(){
  const cfg = window.BINGO_LIVE_ICE_SERVERS || [
    {urls:'stun:stun.l.google.com:19302'}
  ];
  let pc=null, channel=null, localStream=null, request=null, role=null;

  async function user(){
    const sb=window.supabaseClient;
    if(!sb) throw new Error('Bingo Supabase client unavailable');
    const {data,error}=await sb.auth.getUser();
    if(error||!data.user) throw new Error('Sign in to use Live Guests');
    return data.user;
  }
  async function subscribe(liveId, uid, onRequest){
    const sb=window.supabaseClient;
    channel=sb.channel('bingo-live-guest-'+liveId)
      .on('postgres_changes',{event:'*',schema:'public',table:'bingo_live_guest_requests',filter:'live_id=eq.'+liveId},
        p=>onRequest&&onRequest(p))
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'bingo_live_signals',filter:'recipient_id=eq.'+uid},
        p=>handleSignal(p.new))
      .subscribe();
  }
  async function requestJoin(liveId,hostId){
    const u=await user(); role='guest';
    const {data,error}=await window.supabaseClient.from('bingo_live_guest_requests')
      .insert({live_id:liveId,host_id:hostId,guest_id:u.id}).select().single();
    if(error) throw error; request=data; await subscribe(liveId,u.id); return data;
  }
  async function accept(req){
    const u=await user(); role='host'; request=req;
    const {error}=await window.supabaseClient.from('bingo_live_guest_requests')
      .update({status:'accepted',updated_at:new Date().toISOString()}).eq('id',req.id);
    if(error) throw error;
    await subscribe(req.live_id,u.id);
    await ensurePeer(u.id,req.guest_id);
    const offer=await pc.createOffer(); await pc.setLocalDescription(offer);
    await signal('offer',offer,u.id,req.guest_id);
  }
  async function ensurePeer(sender,recipient){
    if(pc) return pc;
    localStream=await navigator.mediaDevices.getUserMedia({video:true,audio:true});
    pc=new RTCPeerConnection({iceServers:cfg});
    localStream.getTracks().forEach(t=>pc.addTrack(t,localStream));
    pc.ontrack=e=>window.dispatchEvent(new CustomEvent('bingo-live-remote-stream',{detail:e.streams[0]}));
    pc.onicecandidate=e=>{ if(e.candidate) signal('ice',e.candidate,sender,recipient).catch(()=>{}); };
    window.dispatchEvent(new CustomEvent('bingo-live-local-stream',{detail:localStream}));
    return pc;
  }
  async function signal(type,payload,sender,recipient){
    const {error}=await window.supabaseClient.from('bingo_live_signals').insert({
      live_id:request.live_id,request_id:request.id,sender_id:sender,recipient_id:recipient,
      signal_type:type,payload:payload
    }); if(error) throw error;
  }
  async function handleSignal(s){
    if(!request || s.request_id!==request.id) {
      const {data}=await window.supabaseClient.from('bingo_live_guest_requests').select('*').eq('id',s.request_id).single();
      if(!data) return; request=data;
    }
    const u=await user(); const other=s.sender_id;
    await ensurePeer(u.id,other);
    if(s.signal_type==='offer'){
      await pc.setRemoteDescription(new RTCSessionDescription(s.payload));
      const ans=await pc.createAnswer(); await pc.setLocalDescription(ans);
      await signal('answer',ans,u.id,other);
    } else if(s.signal_type==='answer') await pc.setRemoteDescription(new RTCSessionDescription(s.payload));
    else if(s.signal_type==='ice') await pc.addIceCandidate(new RTCIceCandidate(s.payload));
    else if(s.signal_type==='leave'||s.signal_type==='remove') close();
  }
  async function setStatus(status){
    if(!request) return;
    await window.supabaseClient.from('bingo_live_guest_requests').update({status,updated_at:new Date().toISOString()}).eq('id',request.id);
    close();
  }
  function close(){
    if(pc){pc.close();pc=null;} if(localStream){localStream.getTracks().forEach(t=>t.stop());localStream=null;}
    if(channel&&window.supabaseClient){window.supabaseClient.removeChannel(channel);channel=null;}
    window.dispatchEvent(new Event('bingo-live-guest-ended'));
  }
  window.BingoLiveGuest={requestJoin,accept,decline:()=>setStatus('declined'),leave:()=>setStatus('left'),remove:()=>setStatus('removed'),subscribe,close};
})();