# MB Trade Lab

**A live, subscription-based trading journal for forex, metals and indices traders — built solo, end to end: landing page, full web app, database, automated MT4/MT5 integration, and billing.**

🔗 **Live app:** [mbtradelab.com](https://mbtradelab.com)

MB Trade Lab replaces the generic spreadsheet journal with something built for how a discretionary trader actually reviews performance: strategy-isolated data, session/pair breakdowns, a monthly edge heatmap, and — the part most journals skip — trades that log themselves straight from MetaTrader instead of being typed in by hand.

## What it does

- **Dashboard** — equity curve, win rate, net R:R and account growth at a glance, with Live vs. Backtest views kept separate
- **Logbook** — every trade fully searchable, with screenshots and notes attached
- **Monthly heatmap** — spot exactly which days/sessions your edge actually shows up
- **Session & pair breakdowns** — performance sliced by trading session and instrument
- **Multi-strategy support** — each strategy's data stays isolated so results never blend and skew analysis
- **R:R or real currency** — log and view performance either way
- **Missed-trade tracking** — log the setups you didn't take, not just the ones you did
- **Import/export** — your data is never locked in
- **Automatic MT4/MT5 sync** — an Expert Advisor pushes every closed trade and live balance straight into the journal, with no manual entry
- **Multi-account support** with real-time balance sync

## Architecture

```
Browser (mb-trade-lab.html)
   │  fetch() → Supabase REST API (PostgREST)
   ▼
Supabase (Postgres + Auth + Storage)
   │
   ├── Row-level security: the client can read/write its own trade data,
   │   but NEVER its own subscription status
   │
   └── Edge Functions (Deno, TypeScript)
         ├── mt-webhook        ← MetaTrader EAs push closed trades + balance here
         ├── stripe-checkout   ← starts a subscription (14-day trial)
         ├── stripe-portal     ← hands the user Stripe's hosted billing portal
         └── stripe-webhook    ← the ONLY thing allowed to change subscription
                                 status, verified via Stripe's signature
```

The front end is deliberately dependency-free — vanilla HTML/CSS/JS, no framework or build step — so the entire client is one auditable file. All state-changing logic that matters for billing or trust (who's actually subscribed, what a trade is worth) lives server-side in Supabase, never in client-trusted code.

**Stack:** HTML/CSS/JavaScript (vanilla) · Supabase (Postgres, Auth, Edge Functions) · Stripe (Checkout, Billing Portal, Webhooks) · MQL5 (MetaTrader 4/5 Expert Advisors)

## MetaTrader integration (MQL5)

Three custom Expert Advisors, written from scratch, handle everything on the trading-platform side:

| EA | What it does |
|---|---|
| `MB_TradeLab_EA.mq5` | Sends every closed trade to the journal automatically, keeps live account balance in sync (deposits/withdrawals included), and derives each trade's real risk % from its stop-loss distance — no manual entry, and it catches up on anything missed while the terminal was closed. |
| `MB_TradeCopier_EA.mq5` | Copies trades from one MT5 "Master" account to any number of "Slave" accounts on the same machine, with each slave sizing its own lots independently (risk %, multiplier, or fixed). |
| `MB_RiskClickTrader_EA.mq5` | One-click, risk-based execution: drag a stop-loss line, set a risk %, and the EA computes the correct lot size live from the current price and fires the order. |

## Billing & security model

- Every signup gets a 14-day trial automatically via a Postgres trigger
- Subscription status (`trialing` / `active` / `past_due` / `canceled`) can **only** be written by the `stripe-webhook` Edge Function, authenticated via Stripe's signing secret — the client has no path to fake or extend its own access
- The MetaTrader webhook authenticates each EA independently via a per-account token embedded in its own webhook URL, not a user login session
- Public anon keys embedded in the client are scoped and safe by design (Supabase's row-level security is the actual access boundary); all service-role keys and Stripe secret keys live only in server-side Edge Function environment variables, never in client code or this repo

## Project structure

```
├── index.html              # Marketing / landing page
├── mb-trade-lab.html        # The application itself
├── privacy.html / terms.html / support.html
├── mb-logo.png / shot-*.png  # Brand + product screenshots
├── MB_TradeLab_EA.mq5        # Auto trade-sync + balance EA
├── MB_TradeCopier_EA.mq5     # Cross-account trade copier EA
├── MB_RiskClickTrader_EA.mq5 # Risk-based one-click execution EA
└── supabase/
    ├── sql/                 # Schema migrations (subscriptions, support messages, plan)
    └── functions/           # Edge Functions: mt-webhook, stripe-checkout, stripe-portal, stripe-webhook
```

## Background

Originally built as a personal trading journal to replace a spreadsheet, then rebuilt into a subscription product other traders can use — including the billing, security model, and MetaTrader automation needed to make that viable, not just the front-end UI.

## Skills demonstrated

Full-stack product design and delivery from scratch: front-end UI/UX with no framework, relational schema design, server-side business logic (Supabase Edge Functions in TypeScript/Deno), third-party payment integration (Stripe), a security model that separates client-trusted from server-trusted data, and native MetaTrader platform development in MQL5.

## Roadmap

- Deeper statistical breakdowns (performance by day of week, etc.)
- Automated reporting/export
- Head-to-head strategy comparison over time
