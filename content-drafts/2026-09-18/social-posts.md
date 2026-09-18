# Social Posts — 2026-09-18

## Post 1 — X/Twitter (Feature: automatic MT4/MT5 trade sync)

Your journal is only as good as the data in it.

Most traders skip logging half their trades because typing them in by hand is tedious — so the sample you're judging your edge on is biased before you even open your stats.

MB Trade Lab's EA closes that gap: it pushes every closed MT4/MT5 trade into your journal automatically and derives your *real* risk % from the actual stop-loss distance, not what you meant to risk. Terminal was closed for a day? It catches up the moment it reconnects.

No manual entry. No missing trades. No guessed risk %.

**Hashtags:** #ForexTrading #TradingJournal #MT4 #MT5 #RiskManagement #PriceAction

**Visual:** `graphics/post1.webp` (copy of `shot-accounts.webp` — Accounts page showing live-synced MT4/MT5 balances)

---

## Post 2 — LinkedIn (Feature: multi-strategy isolation)

A mistake I see constantly in trading journals: one big pool of trades covering three different strategies.

Blend a scalping strategy with a swing strategy in the same stats and the averages lie to you — your scalping win rate drags down what might be a genuinely strong swing edge, and vice versa. Traders abandon strategies that were actually working, because the strategy was never measured on its own.

MB Trade Lab keeps every strategy in its own isolated dashboard: separate win rate, net R:R, drawdown, and monthly heatmap per strategy — so you can see which one actually has an edge instead of judging all of them by a blended average that describes none of them.

**Hashtags:** #TradingStrategy #TradingPsychology #ForexTrading #RiskManagement #DayTrading

**Visual:** `graphics/post2.png` (copy of `shot-strategies.png` — strategy management view with isolated per-strategy data)

---

## Post 3 — X/Twitter (General trading education: expectancy, no specific app feature)

Win rate is the most overrated number in trading.

A strategy that wins 30% of the time can be far more profitable than one that wins 70%, once you factor in the size of wins vs. losses. The number that actually tells you whether a strategy is worth trading is **expectancy**:

`Expectancy = (Win% × Avg Win in R) − (Loss% × Avg Loss in R)`

Example A — 30% win rate, 4R average win, 1R average loss:
(0.3 × 4) − (0.7 × 1) = **+0.5R per trade** → profitable.

Example B — 70% win rate, 0.5R average win, 2R average loss:
(0.7 × 0.5) − (0.3 × 2) = **−0.25R per trade** → a loser, despite winning most of the time.

Stop asking "how often do I win?" Start asking "what's my expectancy?"

**Hashtags:** #TradingEducation #ForexTrading #Expectancy #RiskManagement #TradingPsychology

**Visual:** `graphics/post3.png` (AI-generated — see `image-prompts.json`, entry id `post3-expectancy`)
