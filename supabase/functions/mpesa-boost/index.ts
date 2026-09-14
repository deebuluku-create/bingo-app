// ============================================================================
// BINGO — mpesa-boost Edge Function (Packet 09 server closure)
//
// This is a fresh, complete implementation, NOT an edit of whatever is
// currently deployed as mpesa-boost — that function's source is not part
// of this repository, so it could not be opened or diffed. Deploy this in
// its place only after reading it end to end and confirming it covers
// everything the live function currently does (in particular: if you use
// a different Daraja shortcode type, a different M-Pesa provider, or
// already persist transactions in a table this file doesn't know about,
// adapt the marked sections below before deploying).
//
// Contract preserved exactly for Mother HTML (no client change needed):
//   POST { action:"create_boost", listing_id, target_id, target_type,
//          quote_id?, budget_amount, exact_amount, days, click_price,
//          targeting, phone } -> { amount, budget_amount, boost_id }
//   POST { action:"boost_status", boost_id } -> { status, payment_status,
//          remaining_amount, result_code, message }
//   Safaricom's own POST (Body.stkCallback, no action/apikey) is handled
//   as the payment callback on this same endpoint.
//
// Required environment variables (Supabase project secrets — never in
// Mother HTML): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
// MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET, MPESA_SHORTCODE,
// MPESA_PASSKEY, MPESA_CALLBACK_URL, MPESA_ENV ("sandbox" or "production").
//
// Deploy: supabase functions deploy mpesa-boost
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Supabase provides this to every Edge Function automatically — it is the
// same browser-safe publishable/anon key Mother HTML already uses, not a
// secret. Used only to open a client scoped to the caller's own JWT so
// RLS-aware, auth.uid()-based RPCs (bingo_boost_activation_status) see the
// real caller instead of no one, which the service-role client would.
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const MPESA_ENV = (Deno.env.get("MPESA_ENV") || "sandbox").toLowerCase();
const MPESA_BASE = MPESA_ENV === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
const MPESA_CONSUMER_KEY = Deno.env.get("MPESA_CONSUMER_KEY")!;
const MPESA_CONSUMER_SECRET = Deno.env.get("MPESA_CONSUMER_SECRET")!;
const MPESA_SHORTCODE = Deno.env.get("MPESA_SHORTCODE")!;
const MPESA_PASSKEY = Deno.env.get("MPESA_PASSKEY")!;
const MPESA_CALLBACK_URL = Deno.env.get("MPESA_CALLBACK_URL")!;

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

function mpesaTimestamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

async function getMpesaToken(): Promise<string> {
  const auth = btoa(`${MPESA_CONSUMER_KEY}:${MPESA_CONSUMER_SECRET}`);
  const res = await fetch(`${MPESA_BASE}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${auth}` },
  });
  if (!res.ok) throw new Error("Could not authenticate with M-Pesa.");
  const data = await res.json();
  return data.access_token;
}

async function stkPush(opts: { phone: string; amount: number; accountRef: string; desc: string }) {
  const token = await getMpesaToken();
  const timestamp = mpesaTimestamp();
  const password = btoa(`${MPESA_SHORTCODE}${MPESA_PASSKEY}${timestamp}`);
  const res = await fetch(`${MPESA_BASE}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: MPESA_SHORTCODE,
      Password: password,
      Timestamp: timestamp,
      TransactionType: "CustomerPayBillOnline",
      Amount: Math.round(opts.amount),
      PartyA: opts.phone,
      PartyB: MPESA_SHORTCODE,
      PhoneNumber: opts.phone,
      CallBackURL: MPESA_CALLBACK_URL,
      AccountReference: opts.accountRef,
      TransactionDesc: opts.desc,
    }),
  });
  const data = await res.json();
  if (!res.ok || data.ResponseCode !== "0") {
    throw new Error(data?.errorMessage || data?.ResponseDescription || "M-Pesa could not start the payment request.");
  }
  return data as { CheckoutRequestID: string; MerchantRequestID: string };
}

function normalizePhone(raw: string): string {
  const digits = String(raw || "").replace(/\D/g, "");
  if (digits.startsWith("254")) return digits;
  if (digits.startsWith("0")) return "254" + digits.slice(1);
  if (digits.startsWith("7") || digits.startsWith("1")) return "254" + digits;
  return digits;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders() });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // -------------------------------------------------------------------
  // Safaricom's own callback: no `action`, no Authorization Bearer from
  // our app — its shape is Body.stkCallback. Handle it before anything
  // that requires a Bingo user JWT.
  // -------------------------------------------------------------------
  const stkCallback = (body as any)?.Body?.stkCallback;
  if (stkCallback) {
    const checkoutRequestId = String(stkCallback.CheckoutRequestID || "");
    const resultCode = Number(stkCallback.ResultCode);
    const resultDesc = String(stkCallback.ResultDesc || "");
    const items: any[] = stkCallback.CallbackMetadata?.Item || [];
    const pick = (name: string) => items.find((i) => i.Name === name)?.Value;
    const amount = Number(pick("Amount") ?? 0);
    const receipt = pick("MpesaReceiptNumber") ? String(pick("MpesaReceiptNumber")) : null;

    const { data: quote } = await admin
      .from("bingo_boost_quotes")
      .select("*")
      .eq("checkout_request_id", checkoutRequestId)
      .maybeSingle();

    // Log every callback we receive, success or not, for audit/replay
    // detection. A duplicate receipt hitting the unique index is expected
    // on a Safaricom retry and is treated as already handled, not an error.
    try {
      await admin.from("bingo_boost_mpesa_log").insert({
        quote_id: quote?.id ?? null,
        checkout_request_id: checkoutRequestId,
        mpesa_receipt_number: receipt,
        result_code: Number.isFinite(resultCode) ? resultCode : null,
        result_desc: resultDesc,
        amount: Number.isFinite(amount) ? amount : null,
        raw_payload: body,
      });
    } catch (e) {
      // unique_violation on mpesa_receipt_number = replayed callback we
      // already processed; acknowledge to Safaricom and stop here.
      return json({ ResultCode: 0, ResultDesc: "Already processed" });
    }

    if (resultCode === 0 && quote && receipt) {
      try {
        await admin.rpc("bingo_activate_boost_from_quote", {
          p_quote_id: quote.id,
          p_mpesa_receipt: receipt,
          p_confirmed_amount: amount,
          p_checkout_request_id: checkoutRequestId,
        });
      } catch (e) {
        console.error("Boost activation failed", e);
        // Do not throw back to Safaricom — the payment succeeded on their
        // side regardless; this is logged for manual reconciliation.
      }
    }

    // Safaricom only needs a 200 with this shape; it is not shown to the user.
    return json({ ResultCode: 0, ResultDesc: "Accepted" });
  }

  // -------------------------------------------------------------------
  // Everything else requires a verified Bingo user session.
  // -------------------------------------------------------------------
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Sign in required." }, 401);
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user?.id) return json({ error: "Could not verify your session. Please log in again." }, 401);
  const userId = userData.user.id;

  const action = String(body.action || "");

  if (action === "create_boost") {
    let quoteId = body.quote_id ? String(body.quote_id) : null;
    let amount: number;
    let postType = String(body.target_type || "vehicle");

    if (quoteId) {
      // Quote-authoritative path (Change 09 + this closure): the server
      // reads amount/placement/dates ONLY from the stored quote — any
      // budget_amount/exact_amount/days sent alongside quote_id is
      // ignored, per this packet's own requirement.
      const { data: quote, error } = await admin.from("bingo_boost_quotes").select("*").eq("id", quoteId).eq("user_id", userId).maybeSingle();
      if (error || !quote) return json({ error: "Quote not found." }, 404);
      if (quote.status !== "quoted" || new Date(quote.expires_at) <= new Date()) {
        return json({ error: "This quote is no longer valid. Please request a new one." }, 409);
      }
      amount = Number(quote.amount_kes);
      postType = quote.post_type;
    } else {
      // Legacy/compatibility path (spare parts, CVs, jobs, profile boosts
      // — none of Change 09's placement flow): still trusts the client's
      // amount, exactly as the pre-existing behavior did. Synthesizes a
      // quote row so the callback/activation code path stays single and
      // consistent instead of maintaining two parallel mechanisms.
      amount = Number(body.exact_amount ?? body.budget_amount ?? 0);
      if (!amount || amount <= 0) return json({ error: "Invalid boost amount." }, 400);
      const days = Number(body.days || 30);
      const startsAt = new Date();
      const expiresAt = new Date(startsAt.getTime() + days * 86400000);
      const { data: synthQuote, error: synthError } = await admin
        .from("bingo_boost_quotes")
        .insert({
          user_id: userId,
          post_id: String(body.target_id || body.listing_id || ""),
          post_type: postType,
          placement_id: "legacy",
          duration_days: days,
          geo: String((body.targeting as any)?.location || "all"),
          amount_kes: amount,
          starts_at: startsAt.toISOString(),
          expires_at: expiresAt.toISOString(),
          status: "quoted",
        })
        .select()
        .single();
      if (synthError || !synthQuote) return json({ error: "Could not prepare this boost for payment." }, 500);
      quoteId = synthQuote.id;
    }

    const phone = normalizePhone(String(body.phone || ""));
    if (!phone || phone.length < 12) return json({ error: "Enter a valid Safaricom M-Pesa number." }, 400);

    let stk;
    try {
      stk = await stkPush({ phone, amount, accountRef: `BINGO-${quoteId}`, desc: `Bingo ${postType} boost` });
    } catch (e) {
      return json({ error: String((e as Error)?.message || e) }, 502);
    }

    await admin.from("bingo_boost_quotes").update({ checkout_request_id: stk.CheckoutRequestID }).eq("id", quoteId);

    return json({ amount, budget_amount: amount, boost_id: quoteId });
  }

  if (action === "boost_status") {
    const quoteId = String(body.boost_id || "");
    if (!quoteId) return json({ error: "Missing boost reference." }, 400);
    // bingo_boost_activation_status checks auth.uid() against the quote's
    // owner, so it must be called with the caller's own JWT, not the
    // service-role admin client (which has no authenticated user context).
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
    const { data, error } = await userClient.rpc("bingo_boost_activation_status", { p_quote_id: quoteId });
    if (error) return json({ status: "failed", message: String(error.message || error) });
    const status = (data as any)?.status;
    return json({
      status: status === "paid" ? "active" : status,
      payment_status: status === "paid" ? "paid" : status,
      remaining_amount: undefined,
      message: status === "paid" ? "Payment confirmed." : status === "expired" ? "This boost request has expired." : undefined,
    });
  }

  return json({ error: "Unknown action." }, 400);
});
