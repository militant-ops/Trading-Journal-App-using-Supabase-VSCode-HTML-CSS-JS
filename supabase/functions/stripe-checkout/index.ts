// Supabase Edge Function — starts a Stripe Checkout session for the
// currently logged-in MB Trade Lab user (14-day free trial, then the
// standard subscription price).
//
// Deploy with:
//   supabase functions deploy stripe-checkout
// (no --no-verify-jwt here — this one IS called with the user's own login
// token, from the app's "Upgrade" button, so Supabase's built-in JWT check
// is exactly what we want.)
//
// Request body: { "plan": "monthly" | "yearly" } — defaults to "monthly" if
// omitted. Picks between the two Price secrets below accordingly.
//
// Secrets this function needs (set once with `supabase secrets set`):
//   STRIPE_SECRET_KEY          sk_test_... while testing, sk_live_... when you go live
//   STRIPE_PRICE_ID_MONTHLY    the monthly recurring Price id (price_...)
//   STRIPE_PRICE_ID_YEARLY     the yearly recurring Price id (price_...)
//   APP_URL                    e.g. https://mbtradelab.com — where Checkout sends the user back to
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@17?target=denonext";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});

// Service-role client: we only use it to look up/update the caller's own
// subscriptions row after verifying who they are via their JWT below.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return json({ error: "Not signed in." }, 401);

    // Supabase's gateway already verified this JWT is genuine before our
    // code ran; this call just reads who it belongs to.
    const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not signed in." }, 401);
    const user = userData.user;

    let body: { plan?: string } = {};
    try { body = await req.json(); } catch { /* no body sent — default to monthly */ }
    const plan = body.plan === "yearly" ? "yearly" : "monthly";
    const priceId = plan === "yearly"
      ? Deno.env.get("STRIPE_PRICE_ID_YEARLY")!
      : Deno.env.get("STRIPE_PRICE_ID_MONTHLY")!;

    // Reuse an existing Stripe customer for this user if we've made one
    // before, instead of creating a new one on every "Upgrade" click.
    const { data: sub } = await supabase
      .from("subscriptions")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .single();

    let customerId = sub?.stripe_customer_id as string | undefined;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await supabase
        .from("subscriptions")
        .update({ stripe_customer_id: customerId, updated_at: new Date().toISOString() })
        .eq("user_id", user.id);
    }

    const appUrl = Deno.env.get("APP_URL") ?? "https://example.com";
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      client_reference_id: user.id, // belt-and-braces: lets the webhook find the user even if the customer lookup below ever misses
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${appUrl}?checkout=success`,
      cancel_url: `${appUrl}?checkout=cancelled`,
      // stripe-webhook reads metadata.plan straight off checkout.session.completed
      // rather than having to re-derive it from the price id.
      metadata: { supabase_user_id: user.id, plan },
    });

    return json({ url: session.url });
  } catch (e) {
    console.error("stripe-checkout error:", e);
    return json({ error: "Could not start checkout." }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
