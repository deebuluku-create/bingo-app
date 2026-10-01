import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// Separate Food payment flow. Never redeploy or change mpesa-boost here.
const CORS = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"GET, POST, OPTIONS","Content-Type":"application/json"};
const TABLE = "food_subscription_payments";
const PRICE = 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function json(body: unknown, status=200) { return new Response(JSON.stringify(body),{status,headers:CORS}); }
function secret(name: string) {
  const value=(Deno.env.get("MPESA_FOOD_"+name.replace(/^MPESA_/,""))||Deno.env.get(name)||"").trim();
  if(!value || /^value\s*:/i.test(value)) throw new Error("M-Pesa configuration is incomplete: "+name+" must contain the actual credential, without a 'value:' label.");
  return value;
}
function environment() {
  const value=(Deno.env.get("MPESA_FOOD_ENVIRONMENT")||Deno.env.get("MPESA_ENVIRONMENT")||"sandbox").trim().replace(/^value\s*:\s*/i,"").toLowerCase();
  if(value!=="sandbox"&&value!=="production")throw new Error("M-Pesa environment must be sandbox or production.");
  return value;
}
function admin() {
  let key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!key){try{key=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}").default}catch{/* handled below */}}
  if(!key)throw new Error("Payment database service is not configured.");
  return createClient(Deno.env.get("SUPABASE_URL")!,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export function normalizePhone(input: unknown) {
  let phone=String(input||"").trim().replace(/[\s()+-]/g,"");
  if(phone.startsWith("0"))phone="254"+phone.slice(1);else if(/^[17]\d{8}$/.test(phone))phone="254"+phone;
  return /^254[17]\d{8}$/.test(phone)?phone:null;
}
function timestamp() {return new Date(Date.now()+3*3600000).toISOString().replace(/\D/g,"").slice(0,14)}
function credentials() {
  const shortcode=secret("MPESA_SHORTCODE");if(!/^\d{5,8}$/.test(shortcode))throw new Error("M-Pesa shortcode is not configured correctly.");
  return {shortcode,passkey:secret("MPESA_PASSKEY"),key:secret("MPESA_CONSUMER_KEY"),consumerSecret:secret("MPESA_CONSUMER_SECRET"),mode:environment()};
}
async function hash(token: string) {return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(token)))).map(x=>x.toString(16).padStart(2,"0")).join("")}
function nonce(){return Array.from(crypto.getRandomValues(new Uint8Array(32))).map(x=>x.toString(16).padStart(2,"0")).join("")}
async function providerFetch(url: string,init: RequestInit) {
  const response=await fetch(url,{...init,signal:AbortSignal.timeout(20000)});
  let body:any;try{body=await response.json()}catch{throw new Error("Safaricom returned an invalid response.")}
  return {response,body};
}
async function oauth(c: ReturnType<typeof credentials>) {
  const base=c.mode==="production"?"https://api.safaricom.co.ke":"https://sandbox.safaricom.co.ke";
  const {response,body}=await providerFetch(base+"/oauth/v1/generate?grant_type=client_credentials",{headers:{Authorization:"Basic "+btoa(c.key+":"+c.consumerSecret)}});
  if(!response.ok||!body.access_token)throw new Error("Safaricom did not accept the configured M-Pesa credentials. Check the Food payment environment and credentials.");
  return {base,token:String(body.access_token)};
}
async function stkQuery(checkout: string) {
  const c=credentials(),{base,token}=await oauth(c),ts=timestamp();
  const {response,body}=await providerFetch(base+"/mpesa/stkpushquery/v1/query",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({BusinessShortCode:c.shortcode,Password:btoa(c.shortcode+c.passkey+ts),Timestamp:ts,CheckoutRequestID:checkout})});
  if(!response.ok||body.ResultCode===undefined||!/^\d+$/.test(String(body.ResultCode)))return null;
  return {code:Number(body.ResultCode),description:String(body.ResultDesc||"")};
}
function summary(row:any){return {ok:true,payment_id:row.id,food_business_id:row.business_id,status:row.status,amount:PRICE,days:30,payment_mode:row.environment,activated:!!row.activated_at,subscription_expires_at:row.subscription_expires_at||null,message:row.status==="paid"?(row.activated_at?"Payment confirmed. Your restaurant subscription is active.":row.environment==="sandbox"?"Sandbox payment test completed. No live restaurant subscription was activated.":"Payment confirmed, but restaurant activation needs support review."):row.status==="failed"?(row.result_description||"Payment was not completed."):row.environment==="sandbox"?"Sandbox test request pending. It cannot activate a live restaurant.":"M-Pesa request pending. Confirm on your phone; do not send another request."};}
async function findPayment(db:any,id:string){const {data,error}=await db.from(TABLE).select("*").eq("id",id).maybeSingle();if(error)throw new Error("Payment status could not be loaded.");return data}
async function finishPayment(db:any,row:any,code:number,description:string,receipt:string|null=null) {
  const {error}=await db.rpc("bingo_finish_food_subscription_payment",{p_payment_id:row.id,p_checkout:row.checkout_request_id,p_code:code,p_description:description,p_receipt:receipt});
  if(error)throw new Error("Payment confirmation could not be recorded. Do not pay again; retry checking payment status.");
  return await findPayment(db,row.id);
}
export function callbackDetails(callback:any,row:any) {
  if(!callback?.CheckoutRequestID||callback.CheckoutRequestID!==row.checkout_request_id||callback.MerchantRequestID!==row.merchant_request_id)throw new Error("Payment callback identifiers did not match.");
  if(callback.ResultCode===undefined||!/^\d+$/.test(String(callback.ResultCode)))throw new Error("Invalid callback result.");
  const code=Number(callback.ResultCode),items=callback.CallbackMetadata?.Item||[];
  const value=(name:string)=>items.find((x:any)=>x.Name===name)?.Value;
  let receipt:string|null=null;
  if(code===0){
    if(Number(value("Amount"))!==PRICE||normalizePhone(value("PhoneNumber"))!==row.phone)throw new Error("Payment callback amount or phone did not match.");
    receipt=String(value("MpesaReceiptNumber")||"");if(!/^[A-Z0-9]{8,20}$/.test(receipt))throw new Error("Payment receipt was missing or invalid.");
  }
  return {code,description:String(callback.ResultDesc||""),receipt};
}
async function reconcile(db:any,row:any) {
  if(row.status==="failed"||row.status==="paid"||row.environment!==environment())return row;
  if(!row.checkout_request_id&&row.status==="unknown"&&row.callback_payload){
    const candidate={...row,checkout_request_id:String(row.callback_payload.CheckoutRequestID),merchant_request_id:String(row.callback_payload.MerchantRequestID)};
    callbackDetails(row.callback_payload,candidate);
    const verification=await stkQuery(candidate.checkout_request_id);
    if(!verification)return row;
    const {error}=await db.from(TABLE).update({checkout_request_id:candidate.checkout_request_id,merchant_request_id:candidate.merchant_request_id,status:"pending"}).eq("id",row.id).is("checkout_request_id",null);
    if(error)throw new Error("Payment tracking could not be recovered.");
    row=await findPayment(db,row.id);
  }
  if(!row.checkout_request_id)return row;
  // Provider query is read-only. A callback alone cannot activate a listing.
  const verification=await stkQuery(row.checkout_request_id);if(!verification)return row;
  let receipt:string|null=null;
  if(row.callback_payload){const callback=callbackDetails(row.callback_payload,row);if(callback.code!==verification.code)throw new Error("Payment verification is inconsistent; support review is required.");receipt=callback.receipt}
  return await finishPayment(db,row,verification.code,verification.description,receipt);
}
async function handleCallback(req:Request,url:URL,db:any) {
  const id=url.searchParams.get("payment")||"",token=url.searchParams.get("token")||"";
  if(!UUID.test(id)||!/^[a-f0-9]{64}$/.test(token))return json({ok:false,error:"Invalid callback authentication."},403);
  const row=await findPayment(db,id);
  if(!row||await hash(token)!==row.callback_token_hash)return json({ok:false,error:"Invalid callback authentication."},403);
  const body=await req.json(),callback=body?.Body?.stkCallback;
  if(!callback?.CheckoutRequestID||!callback.MerchantRequestID)return json({ok:false,error:"Invalid callback payload."},400);
  // An unusually early callback is retained before the STK response is bound.
  if(!row.checkout_request_id){
    const {error}=await db.from(TABLE).update({callback_payload:callback}).eq("id",id).is("checkout_request_id",null);
    if(error)throw new Error("Callback could not be retained.");
    let latest=await findPayment(db,id);
    if(!latest.checkout_request_id&&latest.status==="unknown"&&latest.environment===environment()){
      const candidate={...latest,checkout_request_id:String(callback.CheckoutRequestID),merchant_request_id:String(callback.MerchantRequestID)};
      callbackDetails(callback,candidate);
      const verified=await stkQuery(candidate.checkout_request_id);
      if(verified){
        const {error:bindError}=await db.from(TABLE).update({checkout_request_id:candidate.checkout_request_id,merchant_request_id:candidate.merchant_request_id,status:"pending"}).eq("id",id).is("checkout_request_id",null);
        if(bindError)throw new Error("Payment tracking could not be recovered.");
        latest=await findPayment(db,id);
      }
    }
    if(!latest.checkout_request_id)return json({ResultCode:0,ResultDesc:"Callback retained for verification."});
    callbackDetails(callback,latest);await reconcile(db,latest);
  }else{
    callbackDetails(callback,row);
    const {error}=await db.from(TABLE).update({callback_payload:callback}).eq("id",id);if(error)throw new Error("Callback could not be retained.");
    // A late receipt can be attached without extending a paid subscription twice.
    if(row.status==="paid"){const details=callbackDetails(callback,row);if(details.code===0)await finishPayment(db,row,0,details.description,details.receipt)}
    else await reconcile(db,{...row,callback_payload:callback});
  }
  return json({ResultCode:0,ResultDesc:"Callback received and checked."});
}
async function startPayment(db:any,user:any,body:any) {
  const id=String(body.food_business_id||""),phone=normalizePhone(body.phone);
  if(!UUID.test(id)||!phone)return json({ok:false,error:"A valid restaurant and Kenyan M-Pesa phone number are required."},400);
  const {data:business,error}=await db.from("food_businesses").select("id,owner_id,status").eq("id",id).maybeSingle();
  if(error)throw new Error("Restaurant ownership could not be verified.");
  if(!business||business.owner_id!==user.id)return json({ok:false,error:"You can only renew your own restaurant."},403);
  if(["hidden","deleted"].includes(business.status))return json({ok:false,error:"This restaurant cannot be renewed while hidden or deleted."},409);
  const c=credentials();
  const {data:pending,error:pendingError}=await db.from(TABLE).select("*").eq("business_id",id).eq("environment",c.mode).in("status",["requesting","pending","unknown"]).maybeSingle();
  if(pendingError)throw new Error("Existing payment requests could not be checked.");
  if(pending){if(pending.owner_id!==user.id)return json({ok:false,error:"An earlier owner payment needs support review."},409);return json(summary(pending),202);}
  // Token acquisition is not a payment. Check credentials before inserting a request.
  const {base,token:access}=await oauth(c),paymentId=crypto.randomUUID(),callbackToken=nonce();
  const {data:row,error:insertError}=await db.from(TABLE).insert({id:paymentId,business_id:id,owner_id:user.id,phone,amount:PRICE,days:30,environment:c.mode,status:"requesting",callback_token_hash:await hash(callbackToken)}).select().single();
  if(insertError?.code==="23505"){
    const {data:other}=await db.from(TABLE).select("*").eq("business_id",id).eq("environment",c.mode).in("status",["requesting","pending","unknown"]).maybeSingle();
    if(other&&other.owner_id===user.id)return json(summary(other),202);
  }
  if(insertError||!row)throw new Error("Payment request could not be recorded. No STK request was sent.");
  const ts=timestamp(),callbackUrl=new URL(Deno.env.get("SUPABASE_URL")+"/functions/v1/mpesa-food-subscription");callbackUrl.searchParams.set("callback","1");callbackUrl.searchParams.set("payment",paymentId);callbackUrl.searchParams.set("token",callbackToken);
  let upstream:any;
  try{
    upstream=await providerFetch(base+"/mpesa/stkpush/v1/processrequest",{method:"POST",headers:{Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({BusinessShortCode:Number(c.shortcode),Password:btoa(c.shortcode+c.passkey+ts),Timestamp:ts,TransactionType:"CustomerPayBillOnline",Amount:PRICE,PartyA:Number(phone),PartyB:Number(c.shortcode),PhoneNumber:Number(phone),CallBackURL:callbackUrl.toString(),AccountReference:"BINGOFOOD",TransactionDesc:"Bingo Food 30 days"})});
  }catch{
    await db.from(TABLE).update({status:"unknown",result_description:"Safaricom response was not confirmed. Do not send a second payment request."}).eq("id",paymentId);
    return json(summary({...row,status:"unknown"}),202);
  }
  const result=upstream.body;
  if(!upstream.response.ok||String(result.ResponseCode)!=="0"||!result.CheckoutRequestID||!result.MerchantRequestID){
    const message=String(result.errorMessage||result.ResponseDescription||"Safaricom rejected the payment request.");
    await db.from(TABLE).update({status:"failed",result_description:message,completed_at:new Date().toISOString()}).eq("id",paymentId);
    return json({ok:false,payment_id:paymentId,error:message},502);
  }
  const {error:bindError}=await db.from(TABLE).update({status:"pending",checkout_request_id:String(result.CheckoutRequestID),merchant_request_id:String(result.MerchantRequestID)}).eq("id",paymentId);
  if(bindError)return json({ok:true,payment_id:paymentId,status:"unknown",payment_mode:c.mode,message:"M-Pesa request sent, but tracking needs support review. Do not pay again."},202);
  let latest=await findPayment(db,paymentId);
  if(latest.callback_payload){try{latest=await reconcile(db,latest)}catch{/* status checks can retry verification */}}
  return json({...summary(latest),message:c.mode==="sandbox"?"Sandbox STK test sent. It will not activate a live restaurant subscription.":"M-Pesa request sent for KES 1,000. Confirm on your phone; activation follows verified payment."});
}
export async function handler(req:Request) {
  if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
  if(req.method==="GET"){
    let mode:string="invalid",configured=false;try{mode=environment();credentials();configured=true}catch{/* no values exposed */}
    return json({ok:true,function:"mpesa-food-subscription",payment_mode:mode,credentials_configured:configured,live_payments_ready:configured&&mode==="production",amount:PRICE,days:30});
  }
  if(req.method!=="POST")return json({ok:false,error:"Method not allowed."},405);
  try{
    const db=admin(),url=new URL(req.url);
    if(url.searchParams.get("callback")==="1")return await handleCallback(req,url,db);
    const authorization=req.headers.get("Authorization")||"";
    if(!authorization.startsWith("Bearer "))return json({ok:false,error:"Sign in before making or checking a payment."},401);
    const {data,error}=await db.auth.getUser(authorization.slice(7));
    if(error||!data.user)return json({ok:false,error:"Your session is invalid or expired. Please sign in again."},401);
    const body=await req.json();
    if(body.action==="stk")return await startPayment(db,data.user,body);
    if(body.action==="status"){
      if(!UUID.test(String(body.payment_id||"")))return json({ok:false,error:"A valid payment ID is required."},400);
      let row=await findPayment(db,body.payment_id);if(!row||row.owner_id!==data.user.id)return json({ok:false,error:"Payment was not found."},404);
      try{row=await reconcile(db,row)}catch{/* remain pending; never infer success from a failed provider query */}
      return json(summary(row));
    }
    return json({ok:false,error:"Unknown payment action."},400);
  }catch(error){
    const message=error instanceof Error?error.message:"Payment service could not complete this request.";
    console.error("Food payment request failed:",message);
    return json({ok:false,error:message},503);
  }
}
Deno.serve(handler);
