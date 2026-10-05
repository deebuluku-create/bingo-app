/* Bingo member social graph — isolated addon. No master HTML edits.
   Loaded independently only when explicitly included by deployment wiring.
   Frontend adapter expects existing window.supabase and existing profile router. */
(function(){
'use strict';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const compact=n=>{n=Number(n||0);return n>=1e6?(n/1e6).toFixed(1).replace('.0','')+'M':n>=1e3?(n/1e3).toFixed(1).replace('.0','')+'K':String(n)};
window.BingoSocialAddon={
 async counts(profileId){
   const {data,error}=await window.supabase.rpc('bingo_profile_social_counts',{p_profile_id:profileId});
   if(error) throw error; return Array.isArray(data)?data[0]:data;
 },
 async follow(viewerId,profileId,on){
   if(!viewerId||viewerId===profileId) return;
   if(on) return window.supabase.from('bingo_follows').insert({follower_id:viewerId,following_id:profileId});
   return window.supabase.from('bingo_follows').delete().eq('follower_id',viewerId).eq('following_id',profileId);
 },
 async requestFriend(viewerId,profileId){
   if(!viewerId||viewerId===profileId) return;
   return window.supabase.from('bingo_friendships').insert({requester_id:viewerId,addressee_id:profileId,status:'pending'});
 },
 async search(q){
   q=String(q||'').trim(); if(q.length<2) return [];
   const {data,error}=await window.supabase.rpc('bingo_search_members',{p_query:q,p_limit:20});
   if(error) throw error; return data||[];
 },
 async suggestions(){
   const {data,error}=await window.supabase.rpc('bingo_member_suggestions',{p_limit:20});
   if(error) throw error; return data||[];
 },
 compact,esc
};
})();