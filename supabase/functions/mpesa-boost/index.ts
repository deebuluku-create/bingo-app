// ============================================================================
// BINGO — mpesa-boost Edge Function
//
// This is the EXACT source of the function as deployed to the live
// Supabase project (Bingo App Kenya, ref ktwkfavryihrfwghsbuo),
// downloaded directly from the Supabase dashboard and committed here
// verbatim (only this header comment was added) so this repository is
// an accurate backup of production rather than a guess at it. The
// previous version of this file in this repository was a fresh
// implementation written without access to the real deployed source —
// it has been fully superseded and replaced by this file.
//
// Confirmed facts about this function (from reading this source):
//   - Reads MPESA_ENVIRONMENT (not MPESA_ENV) for sandbox/production.
//   - Prices every boost at a fixed MPESA_PRICE_PER_DAY = 500 (KES),
//     server-side only — the client cannot influence the amount charged.
//   - Only two actions exist: POST {action:"create_boost", listing_id,
//     days, phone} (requires a Bearer JWT), and Safaricom's own callback
//     at ?callback=1 (Body.stkCallback shape). There is NO boost_status
//     action — any other action value returns a 400 "Unknown action"
//     error.
//   - Ownership is checked against vehicle_listings(id, user_id) — this
//     function only ever supports vehicle listings; any other post type
//     will always fail with "Listing was not found."
//   - Writes to auto_arcade_boosts (the pending/active boost record) and
//     mpesa_transactions (the raw M-Pesa transaction log), keyed to each
//     other by auto_arcade_boosts.id = mpesa_transactions.boost_id.
//
// Do not deploy over the live function without first diffing this file
// against a freshly re-downloaded copy — someone may have changed the
// deployed version since this copy was taken.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const MPESA_PRICE_PER_DAY = 500;

const MPESA_ENVIRONMENT =
  (Deno.env.get("MPESA_ENVIRONMENT") || "sandbox").toLowerCase();

const MPESA_BASE_URL =
  MPESA_ENVIRONMENT === "production"
    ? "https://api.safaricom.co.ke"
    : "https://sandbox.safaricom.co.ke";

/* ---------------------------------------------------------
   BASIC RESPONSE HELPER
--------------------------------------------------------- */

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

/* ---------------------------------------------------------
   PHONE NUMBER NORMALIZATION
--------------------------------------------------------- */

function normalizeKenyanPhone(value: string): string | null {
  let phone = String(value || "").trim();

  phone = phone.replace(/[^\d+]/g, "");

  if (phone.startsWith("+")) {
    phone = phone.substring(1);
  }

  if (phone.startsWith("0")) {
    phone = "254" + phone.substring(1);
  }

  if (phone.startsWith("7")) {
    phone = "254" + phone;
  }

  if (!/^254[17]\d{8}$/.test(phone)) {
    return null;
  }

  return phone;
}

/* ---------------------------------------------------------
   REQUIRED SECRET HELPER
--------------------------------------------------------- */

function getRequiredSecret(name: string): string {
  const value = Deno.env.get(name);

  if (!value || !value.trim()) {
    throw new Error(`Missing Supabase secret: ${name}`);
  }

  return value.trim();
}

/* ---------------------------------------------------------
   SUPABASE ADMIN CLIENT
--------------------------------------------------------- */

function getSupabaseAdmin() {
  const supabaseUrl = getRequiredSecret("SUPABASE_URL");

  let secretKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  /*
   * Current Supabase projects expose secret keys through
   * SUPABASE_SECRET_KEYS.
   *
   * We also support the older service-role variable.
   */
  if (!secretKey) {
    const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");

    if (secretKeysRaw) {
      try {
        const secretKeys = JSON.parse(secretKeysRaw);
        secretKey =
          secretKeys.default ||
          secretKeys["default"];
      } catch {
        // Continue to the missing-key error.
      }
    }
  }

  if (!secretKey) {
    throw new Error(
      "Supabase server secret key is unavailable. Check SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY.",
    );
  }

  return createClient(supabaseUrl, secretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/* ---------------------------------------------------------
   AUTHENTICATED USER
--------------------------------------------------------- */

async function getAuthenticatedUser(req: Request) {
  const authorization = req.headers.get("Authorization");

  if (!authorization?.startsWith("Bearer ")) {
    return null;
  }

  const accessToken = authorization
    .substring("Bearer ".length)
    .trim();

  if (!accessToken) {
    return null;
  }

  const supabaseUrl = getRequiredSecret("SUPABASE_URL");

  let publishableKey = Deno.env.get("SUPABASE_ANON_KEY");

  /*
   * Current Supabase projects expose publishable keys
   * through SUPABASE_PUBLISHABLE_KEYS.
   */
  if (!publishableKey) {
    const publishableKeysRaw =
      Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");

    if (publishableKeysRaw) {
      try {
        const publishableKeys =
          JSON.parse(publishableKeysRaw);

        publishableKey =
          publishableKeys.default ||
          publishableKeys["default"];
      } catch {
        // Continue to the missing-key error.
      }
    }
  }

  if (!publishableKey) {
    throw new Error(
      "Supabase publishable/anon key is unavailable.",
    );
  }

  const supabase = createClient(
    supabaseUrl,
    publishableKey,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  const { data, error } =
    await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return null;
  }

  return data.user;
}

/* ---------------------------------------------------------
   M-PESA OAUTH ACCESS TOKEN
--------------------------------------------------------- */

async function getMpesaAccessToken(): Promise<string> {
  const consumerKey =
    getRequiredSecret("MPESA_CONSUMER_KEY");

  const consumerSecret =
    getRequiredSecret("MPESA_CONSUMER_SECRET");

  const credentials = btoa(
    `${consumerKey}:${consumerSecret}`,
  );

  const response = await fetch(
    `${MPESA_BASE_URL}/oauth/v1/generate?grant_type=client_credentials`,
    {
      method: "GET",
      headers: {
        Authorization: `Basic ${credentials}`,
        Accept: "application/json",
      },
    },
  );

  const text = await response.text();

  if (!response.ok) {
    throw new Error(
      `M-Pesa OAuth failed (${response.status}): ${text}`,
    );
  }

  let data: any;

  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(
      "M-Pesa OAuth returned invalid JSON.",
    );
  }

  if (!data.access_token) {
    throw new Error(
      "M-Pesa OAuth response did not contain access_token.",
    );
  }

  return data.access_token;
}

/* ---------------------------------------------------------
   KENYAN TIMESTAMP
--------------------------------------------------------- */

function makeTimestamp(): string {
  /*
   * Daraja expects Kenyan local time:
   *
   * YYYYMMDDHHmmss
   *
   * Kenya uses UTC+3.
   *
   * Adding the offset before extracting UTC components
   * correctly handles midnight/day/month/year rollover.
   */
  const kenyaTime = new Date(
    Date.now() + 3 * 60 * 60 * 1000,
  );

  const yyyy = kenyaTime.getUTCFullYear();
  const mm = String(
    kenyaTime.getUTCMonth() + 1,
  ).padStart(2, "0");

  const dd = String(
    kenyaTime.getUTCDate(),
  ).padStart(2, "0");

  const hh = String(
    kenyaTime.getUTCHours(),
  ).padStart(2, "0");

  const mi = String(
    kenyaTime.getUTCMinutes(),
  ).padStart(2, "0");

  const ss = String(
    kenyaTime.getUTCSeconds(),
  ).padStart(2, "0");

  return `${yyyy}${mm}${dd}${hh}${mi}${ss}`;
}

/* ---------------------------------------------------------
   BASE64
--------------------------------------------------------- */

function base64Encode(value: string): string {
  return btoa(
    unescape(
      encodeURIComponent(value),
    ),
  );
}

/* ---------------------------------------------------------
   CALLBACK URL
--------------------------------------------------------- */

function getCallbackUrl(): string {
  const configured =
    Deno.env.get("MPESA_CALLBACK_URL");

  if (!configured || !configured.trim()) {
    throw new Error(
      "MPESA_CALLBACK_URL has not been configured yet.",
    );
  }

  return configured.trim();
}

/* ---------------------------------------------------------
   M-PESA STK PUSH
--------------------------------------------------------- */

async function initiateStkPush(params: {
  phone: string;
  amount: number;
  accountReference: string;
  transactionDescription: string;
}) {
  const shortcode =
    getRequiredSecret("MPESA_SHORTCODE");

  const passkey =
    getRequiredSecret("MPESA_PASSKEY");

  const callbackUrl =
    getCallbackUrl();

  const timestamp =
    makeTimestamp();

  const password =
    base64Encode(
      `${shortcode}${passkey}${timestamp}`,
    );

  const accessToken =
    await getMpesaAccessToken();

  const payload = {
    BusinessShortCode:
      Number(shortcode),

    Password:
      password,

    Timestamp:
      timestamp,

    TransactionType:
      "CustomerPayBillOnline",

    Amount:
      Math.round(params.amount),

    PartyA:
      Number(params.phone),

    PartyB:
      Number(shortcode),

    PhoneNumber:
      Number(params.phone),

    CallBackURL:
      callbackUrl,

    AccountReference:
      params.accountReference,

    TransactionDesc:
      params.transactionDescription,
  };

  console.log(
    "Sending M-Pesa STK Push:",
    JSON.stringify({
      amount: payload.Amount,
      phone: params.phone,
      accountReference:
        params.accountReference,
      environment:
        MPESA_ENVIRONMENT,
    }),
  );

  const response = await fetch(
    `${MPESA_BASE_URL}/mpesa/stkpush/v1/processrequest`,
    {
      method: "POST",

      headers: {
        Authorization:
          `Bearer ${accessToken}`,

        "Content-Type":
          "application/json",

        Accept:
          "application/json",
      },

      body:
        JSON.stringify(payload),
    },
  );

  const text =
    await response.text();

  let data: any;

  try {
    data =
      JSON.parse(text);
  } catch {
    throw new Error(
      `M-Pesa STK Push returned invalid JSON: ${text}`,
    );
  }

  if (!response.ok) {
    throw new Error(
      `M-Pesa STK Push failed (${response.status}): ${
        data?.errorMessage || text
      }`,
    );
  }

  if (
    data?.ResponseCode &&
    String(data.ResponseCode) !== "0"
  ) {
    throw new Error(
      data?.ResponseDescription ||
        data?.CustomerMessage ||
        "M-Pesa rejected the STK Push.",
    );
  }

  return data;
}

/* ---------------------------------------------------------
   CREATE BOOST + START PAYMENT
--------------------------------------------------------- */

async function createBoostPayment(
  req: Request,
) {
  const user =
    await getAuthenticatedUser(req);

  if (!user) {
    return json(
      {
        ok: false,
        error:
          "You must be signed in to boost a listing.",
      },
      401,
    );
  }

  const body =
    await req.json();

  const listingId =
    String(
      body?.listing_id || "",
    ).trim();

  const phoneInput =
    String(
      body?.phone || "",
    ).trim();

  const requestedDays =
    Number(body?.days);

  if (!listingId) {
    return json(
      {
        ok: false,
        error:
          "listing_id is required.",
      },
      400,
    );
  }

  if (
    !Number.isInteger(requestedDays) ||
    requestedDays < 1 ||
    requestedDays > 365
  ) {
    return json(
      {
        ok: false,
        error:
          "Boost days must be a whole number between 1 and 365.",
      },
      400,
    );
  }

  const phone =
    normalizeKenyanPhone(
      phoneInput,
    );

  if (!phone) {
    return json(
      {
        ok: false,
        error:
          "Enter a valid Kenyan M-Pesa number, for example 0712345678.",
      },
      400,
    );
  }

  const totalAmount =
    requestedDays *
    MPESA_PRICE_PER_DAY;

  const supabaseAdmin =
    getSupabaseAdmin();

  /* -------------------------------------------------------
     VERIFY LISTING OWNERSHIP
  ------------------------------------------------------- */

  const {
    data: listing,
    error: listingError,
  } = await supabaseAdmin
    .from("vehicle_listings")
    .select("id,user_id")
    .eq("id", listingId)
    .maybeSingle();

  if (listingError) {
    console.error(
      "Listing lookup error:",
      listingError,
    );

    return json(
      {
        ok: false,
        error:
          "Unable to verify the listing. Check that vehicle_listings is the correct listing table.",
      },
      500,
    );
  }

  if (!listing) {
    return json(
      {
        ok: false,
        error:
          "Listing was not found.",
      },
      404,
    );
  }

  if (
    String(listing.user_id) !==
    String(user.id)
  ) {
    return json(
      {
        ok: false,
        error:
          "You can only boost your own listing.",
      },
      403,
    );
  }

  /* -------------------------------------------------------
     CREATE PENDING BOOST
  ------------------------------------------------------- */

  const {
    data: boost,
    error: boostError,
  } =
    await supabaseAdmin
      .from("auto_arcade_boosts")
      .insert({
        listing_id:
          listingId,

        user_id:
          user.id,

        days:
          requestedDays,

        price_per_day:
          MPESA_PRICE_PER_DAY,

        total_amount:
          totalAmount,

        seller_id:
          user.id,

        duration_days:
          requestedDays,

        amount:
          totalAmount,

        phone,

        payment_status:
          "pending",

        boost_status:
          "pending",

        status:
          "pending",
      })
      .select()
      .single();

  if (boostError) {
    console.error(
      "Boost creation error:",
      boostError,
    );

    return json(
      {
        ok: false,
        error:
          "The boost could not be created. Check the auto_arcade_boosts table columns.",
      },
      500,
    );
  }

  const accountReference =
    `BOOST-${String(
      boost.id,
    ).substring(0, 12)}`;

  /* -------------------------------------------------------
     START M-PESA PAYMENT
  ------------------------------------------------------- */

  let stkResponse: any;

  try {
    stkResponse =
      await initiateStkPush({
        phone,

        amount:
          totalAmount,

        accountReference,

        transactionDescription:
          `Auto Arcade listing boost - ${requestedDays} day(s)`,
      });
  } catch (error) {
    console.error(
      "STK Push error:",
      error,
    );

    await supabaseAdmin
      .from("auto_arcade_boosts")
      .update({
        status:
          "payment_failed",
      })
      .eq(
        "id",
        boost.id,
      );

    return json(
      {
        ok: false,

        boost_id:
          boost.id,

        error:
          error instanceof Error
            ? error.message
            : "Unable to send M-Pesa STK Push.",
      },
      502,
    );
  }

  /* -------------------------------------------------------
     SAVE M-PESA TRANSACTION
  ------------------------------------------------------- */

  const {
    error: transactionError,
  } =
    await supabaseAdmin
      .from("mpesa_transactions")
      .insert({
        boost_id:
          boost.id,

        user_id:
          user.id,

        listing_id:
          listingId,

        phone_number:
          phone,

        amount:
          totalAmount,

        merchant_request_id:
          stkResponse?.MerchantRequestID ||
          null,

        checkout_request_id:
          stkResponse?.CheckoutRequestID ||
          null,

        result_code:
          null,

        result_description:
          null,

        mpesa_receipt_number:
          null,

        status:
          "pending",
      });

  if (transactionError) {
    console.error(
      "Transaction record error:",
      transactionError,
    );

    /*
     * The STK Push has already been sent.
     * Do not mark the payment as failed simply because
     * our local transaction record failed.
     */
    return json(
      {
        ok: true,

        boost_id:
          boost.id,

        payment_pending:
          true,

        warning:
          "STK Push was sent, but the local transaction record could not be saved. Check Supabase logs before retrying.",
      },
      202,
    );
  }

  return json({
    ok: true,

    boost_id:
      boost.id,

    payment_pending:
      true,

    amount:
      totalAmount,

    days:
      requestedDays,

    phone,

    merchant_request_id:
      stkResponse?.MerchantRequestID ||
      null,

    checkout_request_id:
      stkResponse?.CheckoutRequestID ||
      null,

    customer_message:
      stkResponse?.CustomerMessage ||
      "Enter your M-Pesa PIN on your phone.",
  });
}

/* ---------------------------------------------------------
   M-PESA CALLBACK
--------------------------------------------------------- */

async function handleMpesaCallback(
  req: Request,
) {
  const body =
    await req.json();

  console.log(
    "Received M-Pesa callback:",
    JSON.stringify(body),
  );

  const stkCallback =
    body?.Body?.stkCallback;

  /*
   * Safaricom expects a successful HTTP response even when
   * there is nothing useful to process.
   */
  if (!stkCallback) {
    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback received.",
    });
  }

  const checkoutRequestId =
    stkCallback.CheckoutRequestID;

  const resultCode =
    Number(
      stkCallback.ResultCode,
    );

  const resultDescription =
    stkCallback.ResultDesc ||
    "";

  if (!checkoutRequestId) {
    console.error(
      "M-Pesa callback missing CheckoutRequestID.",
    );

    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback received.",
    });
  }

  const supabaseAdmin =
    getSupabaseAdmin();

  /* -------------------------------------------------------
     FIND TRANSACTION
  ------------------------------------------------------- */

  const {
    data: transaction,
    error,
  } =
    await supabaseAdmin
      .from("mpesa_transactions")
      .select("*")
      .eq(
        "checkout_request_id",
        checkoutRequestId,
      )
      .maybeSingle();

  if (error) {
    console.error(
      "Transaction lookup error:",
      error,
    );

    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback received.",
    });
  }

  if (!transaction) {
    console.error(
      "No transaction found for CheckoutRequestID:",
      checkoutRequestId,
    );

    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback received.",
    });
  }

  /* -------------------------------------------------------
     IDEMPOTENCY PROTECTION
  ------------------------------------------------------- */

  /*
   * Safaricom/webhook infrastructure can retry callbacks.
   *
   * If this transaction has already been completed,
   * do not activate the boost again.
   */
  if (
    transaction.status === "paid" ||
    transaction.status === "failed"
  ) {
    console.log(
      "Ignoring duplicate callback for completed transaction:",
      transaction.id,
    );

    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback already processed.",
    });
  }

  /* -------------------------------------------------------
     CALLBACK METADATA
  ------------------------------------------------------- */

  const callbackItems =
    stkCallback?.CallbackMetadata?.Item ||
    [];

  function metadataValue(
    name: string,
  ) {
    const item =
      callbackItems.find(
        (entry: any) =>
          entry?.Name === name,
      );

    return item?.Value ?? null;
  }

  const receiptNumber =
    metadataValue(
      "MpesaReceiptNumber",
    );

  const transactionDate =
    metadataValue(
      "TransactionDate",
    );

  const phoneNumber =
    metadataValue(
      "PhoneNumber",
    );

  const callbackAmount =
    metadataValue(
      "Amount",
    );

  /* -------------------------------------------------------
     SUCCESSFUL PAYMENT
  ------------------------------------------------------- */

  if (resultCode === 0) {
    /*
     * Verify the amount when Safaricom supplies it.
     */
    if (
      callbackAmount !== null &&
      Number(callbackAmount) !==
        Number(transaction.amount)
    ) {
      console.error(
        "M-Pesa callback amount mismatch:",
        {
          expected:
            transaction.amount,

          received:
            callbackAmount,

          checkoutRequestId,
        },
      );

      await supabaseAdmin
        .from(
          "mpesa_transactions",
        )
        .update({
          status:
            "failed",

          result_code:
            resultCode,

          result_description:
            "Payment amount mismatch.",

          completed_at:
            new Date().toISOString(),
        })
        .eq(
          "id",
          transaction.id,
        );

      await supabaseAdmin
        .from(
          "auto_arcade_boosts",
        )
        .update({
          status:
            "payment_failed",
        })
        .eq(
          "id",
          transaction.boost_id,
        );

      return json({
        ResultCode: 0,
        ResultDesc:
          "Callback processed.",
      });
    }

    /* -----------------------------------------------------
       MARK TRANSACTION PAID
    ----------------------------------------------------- */

    const {
      error:
        updateTransactionError,
    } =
      await supabaseAdmin
        .from(
          "mpesa_transactions",
        )
        .update({
          status:
            "paid",

          result_code:
            resultCode,

          result_description:
            resultDescription,

          mpesa_receipt_number:
            receiptNumber
              ? String(
                  receiptNumber,
                )
              : null,

          transaction_date:
            transactionDate
              ? String(
                  transactionDate,
                )
              : null,

          callback_phone:
            phoneNumber
              ? String(
                  phoneNumber,
                )
              : null,

          completed_at:
            new Date().toISOString(),
        })
        .eq(
          "id",
          transaction.id,
        );

    if (updateTransactionError) {
      console.error(
        "Transaction payment update failed:",
        updateTransactionError,
      );

      return json({
        ResultCode: 0,
        ResultDesc:
          "Callback received.",
      });
    }

    /* -----------------------------------------------------
       GET BOOST
    ----------------------------------------------------- */

    const {
      data: boost,
      error:
        boostLookupError,
    } =
      await supabaseAdmin
        .from(
          "auto_arcade_boosts",
        )
        .select("*")
        .eq(
          "id",
          transaction.boost_id,
        )
        .maybeSingle();

    if (
      boostLookupError ||
      !boost
    ) {
      console.error(
        "Boost lookup failed after payment:",
        boostLookupError,
      );

      return json({
        ResultCode: 0,
        ResultDesc:
          "Callback received.",
      });
    }

    /*
     * Extra protection against a race/duplicate callback.
     */
    if (
      boost.status === "active"
    ) {
      console.log(
        "Boost is already active:",
        boost.id,
      );

      return json({
        ResultCode: 0,
        ResultDesc:
          "Boost already activated.",
      });
    }

    /* -----------------------------------------------------
       DETERMINE BOOST START TIME
    ----------------------------------------------------- */

    const now =
      new Date();

    let startDate =
      now;

    /*
     * If another active boost exists for this listing,
     * queue the new boost after it.
     */
    const {
      data: existingBoost,
    } =
      await supabaseAdmin
        .from(
          "auto_arcade_boosts",
        )
        .select(
          "id,ends_at",
        )
        .eq(
          "listing_id",
          transaction.listing_id,
        )
        .eq(
          "status",
          "active",
        )
        .gt(
          "ends_at",
          now.toISOString(),
        )
        .order(
          "ends_at",
          {
            ascending: false,
          },
        )
        .limit(1)
        .maybeSingle();

    if (
      existingBoost?.ends_at
    ) {
      const existingEnd =
        new Date(
          existingBoost.ends_at,
        );

      if (
        existingEnd >
        startDate
      ) {
        startDate =
          existingEnd;
      }
    }

    /* -----------------------------------------------------
       CALCULATE END DATE
    ----------------------------------------------------- */

    const days =
      Number(
        boost.days || 1,
      );

    const endDate =
      new Date(
        startDate,
      );

    endDate.setDate(
      endDate.getDate() +
        days,
    );

    /* -----------------------------------------------------
       ACTIVATE BOOST
    ----------------------------------------------------- */

    const {
      error:
        activateError,
    } =
      await supabaseAdmin
        .from(
          "auto_arcade_boosts",
        )
        .update({
          status:
            "active",

          starts_at:
            startDate.toISOString(),

          ends_at:
            endDate.toISOString(),
        })
        .eq(
          "id",
          boost.id,
        );

    if (activateError) {
      console.error(
        "Boost activation failed:",
        activateError,
      );

      /*
       * Payment remains recorded as paid.
       *
       * We intentionally do not mark the payment failed,
       * because the customer actually paid.
       */
    }

    return json({
      ResultCode: 0,
      ResultDesc:
        "Callback processed successfully.",
    });
  }

  /* -------------------------------------------------------
     FAILED / CANCELLED PAYMENT
  ------------------------------------------------------- */

  await supabaseAdmin
    .from(
      "mpesa_transactions",
    )
    .update({
      status:
        "failed",

      result_code:
        resultCode,

      result_description:
        resultDescription,

      completed_at:
        new Date().toISOString(),
    })
    .eq(
      "id",
      transaction.id,
    );

  await supabaseAdmin
    .from(
      "auto_arcade_boosts",
    )
    .update({
      status:
        "payment_failed",
    })
    .eq(
      "id",
      transaction.boost_id,
    );

  return json({
    ResultCode: 0,
    ResultDesc:
      "Callback processed successfully.",
  });
}

/* ---------------------------------------------------------
   HEALTH CHECK
--------------------------------------------------------- */

async function healthCheck() {
  const required = [
    "MPESA_CONSUMER_KEY",
    "MPESA_CONSUMER_SECRET",
    "MPESA_PASSKEY",
    "MPESA_SHORTCODE",
    "MPESA_CALLBACK_URL",
  ];

  const configured =
    Object.fromEntries(
      required.map(
        (key) => [
          key,
          Boolean(
            Deno.env.get(key),
          ),
        ],
      ),
    );

  return json({
    ok: true,

    function:
      "mpesa-boost",

    environment:
      MPESA_ENVIRONMENT,

    configured,

    message:
      "M-Pesa boost function is running.",
  });
}

/* ---------------------------------------------------------
   MAIN SERVER
--------------------------------------------------------- */

Deno.serve(
  async (req: Request) => {
    /* -----------------------------------------------------
       CORS PREFLIGHT
    ----------------------------------------------------- */

    if (
      req.method ===
      "OPTIONS"
    ) {
      return new Response(
        "ok",
        {
          headers:
            corsHeaders,
        },
      );
    }

    try {
      const url =
        new URL(
          req.url,
        );

      /* ---------------------------------------------------
         HEALTH CHECK
      --------------------------------------------------- */

      if (
        req.method ===
        "GET"
      ) {
        return await healthCheck();
      }

      /* ---------------------------------------------------
         ONLY POST AFTER THIS POINT
      --------------------------------------------------- */

      if (
        req.method !==
        "POST"
      ) {
        return json(
          {
            ok: false,
            error:
              "Method not allowed.",
          },
          405,
        );
      }

      /* ---------------------------------------------------
         M-PESA CALLBACK
      --------------------------------------------------- */

      /*
       * Safaricom calls:
       *
       * /mpesa-boost?callback=1
       */
      if (
        url.searchParams.get(
          "callback",
        ) === "1"
      ) {
        return await handleMpesaCallback(
          req,
        );
      }

      /* ---------------------------------------------------
         FRONTEND REQUEST
      --------------------------------------------------- */

      /*
       * Expected body:
       *
       * {
       *   "action": "create_boost",
       *   "listing_id": "...",
       *   "days": 3,
       *   "phone": "0712345678"
       * }
       */

      const body =
        await req
          .clone()
          .json();

      if (
        body?.action ===
        "create_boost"
      ) {
        return await createBoostPayment(
          req,
        );
      }

      return json(
        {
          ok: false,

          error:
            "Unknown action. Use action=create_boost.",
        },
        400,
      );
    } catch (error) {
      console.error(
        "mpesa-boost error:",
        error,
      );

      return json(
        {
          ok: false,

          error:
            error instanceof Error
              ? error.message
              : "Unexpected server error.",
        },
        500,
      );
    }
  },
);