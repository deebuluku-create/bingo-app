/* Bingo OAuth fast-start — 2026-10-05. Surgical Google/Facebook redirect optimization. */
(function(){'use strict';if(window.__bingoOauthFastStart)return;window.__bingoOauthFastStart=1;
function install(){
 if(typeof window.aaGoogleLogin!=='function'||window.aaGoogleLogin.__bingoFast)return false;
 function fast(provider){
  return async function(){
   if(!window.sb){if(typeof toast==='function')toast(provider+' sign-in is not ready yet.');return}
   try{
    if(window.state){state.authBusy=true;state.authError=''}
    if(typeof aaSaveCurrentRoute==='function')aaSaveCurrentRoute();
    if(typeof aaSaveOAuthAuthIntent==='function')aaSaveOAuthAuthIntent();
    const redirectTo=typeof aaOAuthRedirectTo==='function'?aaOAuthRedirectTo():location.origin+'/';
    const r=await sb.auth.signInWithOAuth({provider:provider.toLowerCase(),options:{redirectTo}});
    if(r.error)throw r.error;
   }catch(e){if(window.state){state.authBusy=false;state.authError=String(e&&e.message||provider+' sign-in could not start.')}if(typeof render==='function')render()}
  }
 }
 const g=fast('Google');g.__bingoFast=true;window.aaGoogleLogin=g;
 if(typeof window.aaFacebookLogin==='function'){const f=fast('Facebook');f.__bingoFast=true;window.aaFacebookLogin=f}
 return true;
}
if(!install()){let n=0,t=setInterval(function(){if(install()||++n>80)clearInterval(t)},50)}
})();