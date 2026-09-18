// Supabase Edge Function — opens Stripe's hosted Customer Portal for the
// currently logged-in MB Trade Lab user. The Portal itself (configured in
// Stripe Dashboard → Settings → Billing → Customer portal) is what actually
// gives you cancel, monthly/yearly switching, and card updates for free —
// this function's only job is to hand back a portal URL for THIS customer.
//
// Deploy with:
//   supabase functions deploy stripe-portal
// (no --no-verify-jwt here — same reasoning as stripe-checkout: this is
// called with the user's own login token, so Supabase's built-in JWT check
// is exactly what we want.)
//
// Secrets this function needs (set once with `supabase secrets set`):
//   STRIPE_SECRET_KEY   same one stripe-checkout uses
//   APP_URL             e.g. https://mbtradelab.com — where the Portal sends the user back to
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@17?target=denonext";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});

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

    const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not signed in." }, 401);
    const user = userData.user;

    const { data: sub } = await supabase
      .from("subscriptions")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .single();

    // No Stripe customer yet means they've never actually checked out —
    // nothing for the Portal to manage.
    if (!sub?.stripe_customer_id) {
      return json({ error: "No billing account yet — subscribe first, then billing can be managed here." }, 400);
    }

    // Same rule as stripe-checkout's success_url — send them back to the app
    // itself, not the marketing homepage.
    const appUrl = (Deno.env.get("APP_URL") ?? "https://example.com").replace(/\/+$/, "");
    const portalSession = await stripe.billingPortal.sessions.create({
      customer: sub.stripe_customer_id,
      return_url: `${appUrl}/mb-trade-lab.html`,
    });

    return json({ url: portalSession.url });
  } catch (e) {
    console.error("stripe-portal error:", e);
    return json({ error: "Could not open billing portal." }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
