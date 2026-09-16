// Supabase Edge Function — receives events from Stripe and keeps
// public.subscriptions in sync. This is the ONLY thing allowed to change a
// user's subscription status (see supabase/sql/001_subscriptions.sql).
//
// Deploy with:
//   supabase functions deploy stripe-webhook --no-verify-jwt
// --no-verify-jwt is required: Stripe has no Supabase login token to send,
// only its own signature (checked below via STRIPE_WEBHOOK_SECRET). Without
// that flag Supabase rejects every call with 401 before your code runs —
// same reason mt-webhook needs it for the MT4/5 EA.
//
// After deploying, go to Stripe Dashboard → Developers → Webhooks → Add
// endpoint, point it at:
//   https://<project-ref>.supabase.co/functions/v1/stripe-webhook
// and select these events: checkout.session.completed, invoice.paid,
// invoice.payment_failed, customer.subscription.deleted.
// Stripe will show you the signing secret for that endpoint — that's
// STRIPE_WEBHOOK_SECRET below.
//
// Secrets this function needs (set once with `supabase secrets set`):
//   STRIPE_SECRET_KEY          same one stripe-checkout uses
//   STRIPE_WEBHOOK_SECRET      whsec_... from the Stripe webhook endpoint page
//   STRIPE_PRICE_ID_MONTHLY    same two price ids stripe-checkout uses — lets
//   STRIPE_PRICE_ID_YEARLY     this figure out "plan" from the price on an invoice
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@17?target=denonext";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    // This is what stops anyone but Stripe from ever POSTing a fake
    // "subscription active" event at this endpoint.
    event = await stripe.webhooks.constructEventAsync(body, signature!, webhookSecret);
  } catch (err) {
    console.error("stripe-webhook signature check failed:", err);
    return new Response("Invalid signature", { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = session.metadata?.supabase_user_id ?? session.client_reference_id;
        if (!userId) break;
        // Set at checkout time (see stripe-checkout) — cheaper than re-deriving
        // it from a price id lookup here.
        const plan = session.metadata?.plan === "yearly" ? "yearly" : "monthly";
        await supabase.from("subscriptions").update({
          status: "active",
          plan,
          stripe_customer_id: session.customer as string,
          stripe_subscription_id: session.subscription as string,
          updated_at: new Date().toISOString(),
        }).eq("user_id", userId);
        break;
      }

      case "invoice.paid": {
        const invoice = event.data.object as Stripe.Invoice;
        const sub = await findByCustomer(invoice.customer as string);
        if (!sub) break;
        const periodEnd = invoice.lines.data[0]?.period?.end;
        // A plan switch made through the Customer Portal doesn't go through
        // checkout.session.completed — it lands here instead, so re-derive
        // plan from whichever price the invoice actually billed.
        const priceId = invoice.lines.data[0]?.price?.id;
        const update: Record<string, unknown> = {
          status: "active",
          current_period_end: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
          updated_at: new Date().toISOString(),
        };
        if (priceId === Deno.env.get("STRIPE_PRICE_ID_YEARLY")) update.plan = "yearly";
        else if (priceId === Deno.env.get("STRIPE_PRICE_ID_MONTHLY")) update.plan = "monthly";
        await supabase.from("subscriptions").update(update).eq("user_id", sub.user_id);
        break;
      }

      case "invoice.payment_failed": {
        const invoice = event.data.object as Stripe.Invoice;
        const sub = await findByCustomer(invoice.customer as string);
        if (!sub) break;
        await supabase.from("subscriptions").update({
          status: "past_due",
          updated_at: new Date().toISOString(),
        }).eq("user_id", sub.user_id);
        break;
      }

      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;
        const sub = await findByCustomer(subscription.customer as string);
        if (!sub) break;
        await supabase.from("subscriptions").update({
          status: "canceled",
          updated_at: new Date().toISOString(),
        }).eq("user_id", sub.user_id);
        break;
      }
    }
  } catch (e) {
    // Log but still 200 back — Stripe retries aggressively on non-2xx,
    // and a bug on our side shouldn't cause a retry storm. Check the
    // function logs (`supabase functions logs stripe-webhook`) if this fires.
    console.error(`stripe-webhook handler error for ${event.type}:`, e);
  }

  return new Response("ok", { status: 200 });
});

async function findByCustomer(customerId: string) {
  const { data } = await supabase
    .from("subscriptions")
    .select("user_id")
    .eq("stripe_customer_id", customerId)
    .single();
  return data;
}
