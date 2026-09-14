// ============================================================================
// BINGO CHANGE 09 — boost-quote Edge Function
//
// Computes the exact placement-based boost amount, start and expiry
// server-side and records it as a pending quote. The browser never
// supplies a price or a date for a boost — it only ever echoes back the
// quote_id this function returns, and the existing mpesa-boost function
// must (see the note at the bottom of this file) look the amount and
// expiry up from bingo_boost_quotes by that id rather than trusting
// anything the client sends.
//
// Deploy with the Supabase CLI from the repo root:
//   supabase functions deploy boost-quote
//
// Required environment variables (already used by mpesa-boost, per the
// same project): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. The service-role
// key lives only in this server-side Edge Function's own environment —
// never in Mother HTML, never in the browser.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Mirrors the client-side AA_BOOST_BUDGETS / AA_CORPORATE_BUDGETS /
// AA_AGENT_INTRO_PLAN amounts in Mother HTML. Duplicated deliberately —
// this function cannot import from the browser bundle, and the backend
// value is the one actually charged, so it is intentionally the
// authoritative copy, not the browser's.
const BUDGET_AMOUNTS = new Set([100, 250, 500, 1000, 2500, 5000, 10000, 15000, 25000, 200]);

const PLACEMENTS: Record<string, { label: string; surchargeKes: number }> = {
  "feed-priority": { label: "Priority in Home Feed", surchargeKes: 0 },
  "home-banner": { label: "Home Sponsored Banner", surchargeKes: 300 },
};

const DURATIONS: Record<number, string> = {
  1: "24 Hours",
  7: "1 Week",
  30: "1 Month",
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders() });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return jsonResponse({ error: "Sign in required." }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Verify the caller's identity from their own JWT — never trust a
  // user_id supplied in the request body.
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user?.id) {
    return jsonResponse({ error: "Could not verify your session. Please log in again." }, 401);
  }
  const userId = userData.user.id;

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }

  const postId = String(input.post_id || "");
  const postType = String(input.post_type || "vehicle");
  const placementId = String(input.placement_id || "");
  const budgetAmount = Number(input.budget_amount || 0);
  const durationDays = Number(input.duration_id || input.duration_days || 0);
  const geo = String(input.geo || "all");

  if (!postId) return jsonResponse({ error: "A post is required." }, 400);
  const placement = PLACEMENTS[placementId];
  if (!placement) return jsonResponse({ error: "Invalid placement selected." }, 400);
  if (!DURATIONS[durationDays]) return jsonResponse({ error: "Invalid duration selected." }, 400);
  if (!BUDGET_AMOUNTS.has(budgetAmount)) return jsonResponse({ error: "Invalid budget amount selected." }, 400);

  // Ownership: property and food business posts have a real backend row
  // this function can check directly. Vehicle listings currently have no
  // backend table at all in Bingo (they live only in each browser's own
  // state.listings) — server-side ownership verification for them is not
  // possible with today's architecture, so it stays enforced client-side
  // by aaBoostOwnedByMe, same as every other vehicle action in Mother
  // HTML. A forged vehicle post_id here cannot expose or modify anyone
  // else's data — it can only ever produce a quote for a post the payer
  // cannot actually activate.
  if (postType === "property" || postType === "stay") {
    const { data: row, error } = await admin
      .from("property_listings")
      .select("id,user_id")
      .eq("id", postId)
      .maybeSingle();
    if (error || !row) return jsonResponse({ error: "Post not found." }, 404);
    if (String(row.user_id) !== userId) return jsonResponse({ error: "Only the owner can boost this post." }, 403);
  } else if (postType === "food_business") {
    const { data: row, error } = await admin
      .from("food_businesses")
      .select("id,user_id")
      .eq("id", postId)
      .maybeSingle();
    if (error || !row) return jsonResponse({ error: "Post not found." }, 404);
    if (String(row.user_id) !== userId) return jsonResponse({ error: "Only the owner can boost this post." }, 403);
  }

  const amountKes = budgetAmount + placement.surchargeKes;
  const startsAt = new Date();
  const expiresAt = new Date(startsAt.getTime() + durationDays * 86400000);

  const { data: quote, error: insertError } = await admin
    .from("bingo_boost_quotes")
    .insert({
      user_id: userId,
      post_id: postId,
      post_type: postType,
      placement_id: placementId,
      duration_days: durationDays,
      geo,
      amount_kes: amountKes,
      starts_at: startsAt.toISOString(),
      expires_at: expiresAt.toISOString(),
      status: "quoted",
    })
    .select()
    .single();

  if (insertError || !quote) {
    console.error("boost-quote insert failed", insertError);
    return jsonResponse({ error: "Could not prepare a quote. Please try again." }, 500);
  }

  return jsonResponse({
    quote_id: quote.id,
    amount_kes: amountKes,
    starts_at: quote.starts_at,
    expires_at: quote.expires_at,
    placement_label: placement.label,
    geo_label: geo,
  });
});

// ----------------------------------------------------------------------------
// UPDATE (Packet 09 server closure): the companion change this note used to
// describe as required manual work on the existing mpesa-boost function is
// now implemented as a full replacement — see
// supabase/functions/mpesa-boost/index.ts and
// supabase/bingo_change_boost_payment_server_closure.sql. That function
// reads amount/placement/dates only from the stored bingo_boost_quotes row
// when quote_id is present, activates the boost and credits Agent
// commission exactly once inside one atomic transaction
// (bingo_activate_boost_from_quote), and keeps the legacy no-quote_id path
// (spare/CV/job/profile boosts) working exactly as before. It was written
// fresh rather than edited in place because the previously-deployed
// mpesa-boost source is not part of this repository — read its own header
// comment before deploying it over whatever is live today.
// ----------------------------------------------------------------------------
