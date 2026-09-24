# The model matrix — who gets the work, at what effort, at what cost

Companion to [routing.md](routing.md). routing.md is the *procedure* for resolving
classes to seats; this file is the *evidence table* that procedure consults.

**Read this first — what the dollars mean.** On a subscription-authenticated
account (ChatGPT login for Codex, grok.com login for Grok, a Claude plan for the
LEAD seat) these prices are **not** card charges. They are the best available
**proxy for how fast a dispatch depletes that provider's allowance**. They become
literal only on API-key auth. Never quote them to the user as money spent without
first establishing the auth mode (codex-workers.md, grok-workers.md).

**On this subscription the envelope reports a flat pool rate, not the API list —
and the rate moves.** Measured 2026-08-17/18: eleven Grok dispatches all fit
exactly 0.17x the public list on every bucket. Re-measured 2026-09-23 (two
one-turn pings, grok-4.7 and grok-4.6, identical rate): **~0.34x list** ($0.68/M
uncached input). Two samples prove the rate changed, not what it is now in
general. Grok's docs say `total_cost_usd` appears only when the server reports a
complete cost, so this is xAI's own accounting for OAuth/pool traffic. Read it as
an internal rate — not as evidence about what the subscription *allowance* costs,
and there is no comparable measurement for Claude or Codex subscriptions. Where
an envelope reports a cost, record that number; use Table 1 only to compare
seats, and never hardcode a pool multiplier.

**Currency rule applies to this whole file.** Every number below is dated. Model
lineups move faster than skill files. If anything here disagrees with the live
provider docs or the account itself, the live source wins and this table is
stale — re-derive it, don't route off it. `scripts/probe.sh` prints the live
Codex catalog and Grok model list for exactly this reason.

## Table 1 — Seats, price, capability (verified 2026-09-23)

Capability = Artificial Analysis, **one index version (v4.3.x)** so the columns
compare. **II** = Intelligence Index (a composite, not a coding benchmark). **CA**
= Coding Agent Index (the model driven through its own agent harness — the
closest public proxy for "can it carry a delegated ticket"). `n/m` = not measured
on v4.3 in any source found; do not back-fill it from the old v4.1 scale (Opus 5
was 63 there — the scales are not comparable). **Out tok/task** = output tokens
AA measured per II task at the effort shown: the *volume* half of the bill, which
list price hides.

| Seat | In $/M | Out $/M | Cache read $/M | Context | II v4.3 | CA | Out tok/task | Notes |
|---|---|---|---|---|---|---|---|---|
| Claude Opus 5.5 | 4 | 20 | 0.20 | 1M | **58** (max) | n/m | 119K (max) | highest II measured; default effort `medium`; released 2026-09-22 |
| Claude Fable 5.1 | 10 | 50 | 0.25 | 1M | 53 (max) | **62** | 78K (max) | Anthropic: "start with Opus 5.5"; Fable 5.1 when Opus falls short at high effort |
| GPT-6 Astra | 10 | 50 | 1.00 | 272K (872K max) | 53 (max) | **62** | **27K** (max) | Terminal-Bench 4.0 59%; >272K: $20/$75 |
| Claude Opus 5 | 5 | 25 | 0.50 | 1M | n/m | 60 | 73K (max) | superseded by Opus 5.5 (cheaper and higher) |
| GPT-6 Sol | 2 | 10 | 0.20 | 272K (872K max) | 48† | 57 | n/m | Codex **workhorse** tier — the name moved class (see note); >272K: $4/$15 |
| Grok 4.7 | 2 | 6 | 0.50 | 500K | 46 (xhigh) | 56 | **81K** (xhigh) | DeepSWE 73%, Terminal-Bench 4.0 33%; **2x whole request ≥200K** |
| Grok 4.6 | 2 | 6 | 0.50 | 500K | 44 (high) | 47 | 38K (xhigh) | same price as 4.7, half the output volume; same 200K cliff |
| Claude Sonnet 5 | 2 | 10 | 0.20 | 1M | n/m | n/m | n/m | $2/$10 now permanent; no length surcharge |
| GPT-6 Luna | **0.10** | **0.50** | 0.01 | 272K (872K max) | 37† | 41 | n/m | Codex FAST tier; >272K: $0.20/$0.75 |
| Claude Haiku 4.5 | 1 | 5 | 0.10 | **200K** | n/m | n/m | n/m | 4096-token cache floor |
| Grok 4.7 Fast (`grok-4.7-build-fast`) | 4 | 12 | 1.00 | 500K | — | — | — | same weights class as 4.7, **2x price** for speed; Grok Build/Cursor only |

† SECONDARY (press reporting AA numbers; not on an AA page we could fetch). Treat as ±2.

**The GPT-6 naming trap.** In GPT-5.6, *Sol* was the flagship. In GPT-6, *Astra* is
the flagship and **Sol is the workhorse** ("Workhorse model for coding and everyday
work" — the Codex CLI's own catalog). A foreman carrying "Sol = frontier" forward
would under-seat frontier work. Map Codex classes from the provider's own
positioning text, which `scripts/probe.sh` prints from the CLI's model cache —
never from a remembered name.

**`gpt-reserve`** appears in the Codex catalog as "Fast and affordable agentic coding
model". Third-party trackers (SECONDARY, not confirmed by OpenAI) describe it as a
Luna-class fallback pool served when a plan's normal Codex allowance is exhausted.
Never request it as a seat; if a Codex dispatch behaves like a FAST seat after a
quota warning, treat it as a possible substitution (routing.md, silent-fallback
hazard) — Codex seat evidence is `unverified` either way.

## Table 2 — What one real dispatch costs

A 4-turn agentic dispatch: ~100K working context sent fresh once, ~300K re-sent
from cache across later turns, 12K output. List prices, no cache-write premium.
This shape matters more than list price, because caching dominates multi-turn
work — but **output volume differs by model** (Table 1, "Out tok/task"), so the
12K output here is a fixed yardstick, not a prediction.

| Seat | Cost | II v4.3 | CA | Read it as |
|---|---|---|---|---|
| GPT-6 Luna | **$0.019** | 37† | 41 | ~10x cheaper than Haiku, far more capable |
| Claude Haiku 4.5 | $0.190 | n/m | n/m | FAST fallback when Codex is absent |
| GPT-6 Sol | $0.380 | 48† | 57 | workhorse value on the Codex side |
| Claude Sonnet 5 | $0.380 | n/m | n/m | workhorse on the lead's own pool |
| Grok 4.7 / 4.6 | $0.422 | 46 / 44 | 56 / 47 | same list price; 4.7 emits ~2x the output on hard tasks |
| Claude Opus 5.5 | $0.700 | **58** | n/m | frontier at a workhorse-adjacent price |
| Grok 4.7 Fast | $0.844 | — | — | pay 2x only for wall-clock |
| Claude Fable 5.1 | $1.675 | 53 | 62 | premium frontier |
| GPT-6 Astra | $1.900 | 53 | 62 | premium frontier; token-frugal (27K/task) |

Anthropic charges a cache-write premium on the fresh pass (Opus 5.5 $5/M, Fable 5.1
$12.50/M for 5-minute TTL; verified 2026-09-23): Opus 5.5 $0.80, Fable 5.1 $1.93,
Sonnet 5 $0.43, Haiku $0.215. Treat the table as ±20% (tokenizers differ across
vendors).

**Per-task reality check — output volume × output price** at the measured effort
(AA II tasks): Astra 27K × $50 = **$1.35**; Grok 4.6 38K × $6 = **$0.23**; Grok 4.7
81K × $6 = **$0.49**; Fable 5.1 78K × $50 = **$3.90**; Opus 5.5 119K × $20 = **$2.38**.
AA's own cost-per-task: Astra $3.26 vs Fable 5.1 $7.63 for the same II score.

Five conclusions that should drive routing:

1. **Opus 5.5 is the Claude frontier value seat.** Highest II on the board at 40% of
   Fable 5.1's list price; Anthropic's own guidance is to start there. The `opus`
   alias is the default frontier *subagent*; reach for `fable` only on evidence that
   Opus fell short on this kind of work (performance record) — never by default.
2. **GPT-6 Luna redefines FAST.** At $0.019 a dispatch it is an order of magnitude
   under Haiku. Where Codex is present, Luna is the FAST seat; Haiku is the fallback.
   CA 41 is a real ceiling — keep Luna on mechanical, well-bounded tickets.
3. **Grok 4.7 and GPT-6 Sol are the workhorse pair** (CA 56 vs 57, same input price).
   Grok's output is cheaper per token but 4.7 emits roughly twice as much of it — that
   token burn, not a measured coding regression, is the substance behind 4.7's mixed
   reviews (VentureBeat, 2026-09). Choose between them on user preference, pool
   pressure, and cross-family pairing, then let the performance record settle it.
4. **Grok 4.7 beats 4.6 on execution, not on the composite.** CA +9, Terminal-Bench
   18→33%, DeepSWE 65→73%, hallucination 34→29% — but II only +2 at a higher effort.
   So: 4.7 for implementation; 4.6 stays a sound output-light *reviewer* at half the
   volume. When the record shows 4.7 regressing on a task shape, fall back to 4.6
   for that shape and journal it.
5. **Astra and Fable 5.1 tie on both indexes; Astra costs ~40% as much per task.** Both are **premium seats** by the user's rule (2026-09-24): never dispatched without double approval in the session.
   Where Codex is present, Astra is the strongest cross-family frontier reviewer or
   hard-ticket implementer. Fable 5.1 is priced above its measured capability
   relative to Opus 5.5 — field it for a specific strength, never by default.

## Table 3 — The Grok cliff is a routing boundary, not a price bump

Grok reprices the **entire request** at 2x once it crosses 200K, so cost jumps
discontinuously. Same job, 17% more input:

| Job | Grok 4.7 / 4.6 | Sonnet 5 | Verdict |
|---|---|---|---|
| 180K in / 15K out | **$0.450** | $0.510 | Grok wins |
| 210K in / 15K out | $1.020 | **$0.570** | Sonnet 44% cheaper (Grok costs 1.79x) |
| 250K in / 15K out | $1.180 | **$0.650** | Sonnet 45% cheaper (1.82x) |
| 400K in / 20K out | $1.840 | **$1.000** | Sonnet 46% cheaper (1.84x) |

**Rule: above ~200K, Grok loses its own cost advantage — change seats.** What is
certain is the *within-Grok* jump: xAI's published policy reprices the whole
request 2x, so the same job costs twice what it would have. What is **not**
established is the cross-provider winner: the table above is list-price math, and
this account's envelopes report a flat 0.17x-of-list pool rate (see the note
above) with no matching subscription measurement for Claude. So treat "Sonnet is
cheaper above the cliff" as a **list-price-relative** claim to confirm against
measured envelope costs, and treat "don't pay Grok's surcharge" as the rule.
Above 500K Grok is ineligible outright — that is a hard context ceiling, not a
price argument.

**How to apply this without counting tokens.** Estimating request size ahead of a
dispatch is unreliable (Grok prepends its own system prompt and toolset — ~19K
tokens on this build with Claude-config discovery off, ~28K with it on), so
measure after the fact instead. The json envelope reports summed *uncached* input
separately from cache reads, so `grok-dispatch.sh` derives the **average prompt
size per model call** (uncached + cache-read + cache-creation, divided by
`num_turns`) rather than reading `input_tokens` raw, and emits `CONTEXT WARN` /
`CONTEXT ALERT` off that. Ledger the number. **Reactive rule:** the launcher
reports the dispatch's average prompt size per model call. After a
`CONTEXT ALERT`, do not send Grok another ticket that carries the *same context
set or a superset* (same working files/paths plus the same or a longer resumed
session) — that is a fact the foreman knows from what it put in the ticket. A
fresh ticket with a smaller context set may still use Grok; when unsure, don't. A
`CONTEXT WARN` means shrink the next ticket's context or split it.

## Table 4 — Effort: a volume dial, and it pays off unevenly

Verified for all three providers: **raising reasoning effort never changes the
per-token price.** It changes how many reasoning/output tokens get generated,
billed at the ordinary output rate. Effort therefore multiplies the *output* half
of the bill — the expensive half on every seat in Table 1.

**The finding that should drive effort choice — the payoff depends on task shape,
not on difficulty alone.** Anthropic publishes the only quantified curve (PRIMARY,
2026-08-17), and the two shapes diverge sharply:

| Task shape | Accuracy-vs-effort curve | Cost prior (the lead's judgment and the performance record override this) |
|---|---|---|
| Analysis / knowledge work / review (WideSearch, GDPval, BrowseComp) | **nearly flat** — `low` gives up only 1-3 points for 33-50% less cost; `medium` matches `high` at 70-85% of cost | `medium` has matched `high` at 70-85% of cost on these benchmarks; a prior for review-shaped work, not a default |
| Long-horizon coding (SWE-bench Pro) | **steep** — `low` gives up ~8 points | `low` gave up ~8 points here; the prior favors higher effort for long-horizon coding |

Anthropic's own framing: "Long-horizon coding is the other shape." Treat this as
measured on Anthropic models; the shape is a strong prior for other families, not
a proven transfer. Everything in Table 4 is *cost evidence and priors for the
lead's judgment*, never a dispatch rule: effort is chosen per dispatch by the
lead, and the performance record overrides these priors as it accumulates.

xAI's own published level guidance (PRIMARY, docs.x.ai) points the same way —
note that `medium`, not `high`, is the level it names for analysis. These are
xAI's descriptions of its own levels, evidence the lead weighs, not levels this
file assigns:

| Grok level | xAI says it is for |
|---|---|
| `low` | latency-sensitive work, simple tool calls |
| `medium` | **complex data analysis and long-context reasoning** |
| `high` (default) | hard math, multi-step logic |
| `xhigh` | the hardest problems only |

OpenAI grades `none`→`max` by latency tolerance and difficulty, not by task
category. No vendor draws an explicit review-vs-build line.

| Surface | Levels | How effort is chosen | Cost evidence to weigh |
|---|---|---|---|
| Grok 4.7 / 4.6 | low, medium, high, xhigh (read per model from the CLI cache; the launcher validates) | per dispatch by the lead; with no performance evidence yet, the prior is the highest level the model supports | 4.7 at `xhigh` emits ~2x 4.6's output (81K vs 38K per AA task) — flat per-token price, so this is volume, not rate |
| Grok 4.5 | low, medium, high (**no xhigh**) | same, capped at high because the level does not exist | — the launcher validates effort values and `xhigh` exits 1 |
| Codex (GPT-6) | low, medium, high, xhigh, max (+ `ultra` on Astra/Sol — **refused by the launcher**: it auto-delegates to sub-agents, hard rail 1); no `minimal` | per dispatch by the lead, among the levels the verified model supports (the launcher checks the CLI's catalog) | provider default (`medium`) is the fallback when nothing is known |
| Claude subagents | low, medium, high, xhigh, max (Opus 5.5 default: `medium`) | role default (scout low / worker high / verifier high) unless the lead chooses otherwise | Opus 5.5 at `max` emits ~119K output per AA task vs ~73K for Opus 5 — `max` is a volume multiplier |

The one hard tradeoff number anyone publishes: Grok's top effort level vs `high`
on CursorBench — **a coding benchmark** — buys **+0.9pp accuracy for +20% cost**
(69.9% → 70.8%; SECONDARY, cross-corroborated, absent from primary xAI pages).
Read it as a *cost prior*, not a rule: it says what a step up the dial costs on
one coding benchmark, on one family. Transfer to other task shapes and to other
model families is unproved (same caveat as the Anthropic curve above — measured
on one vendor's models, a prior for others). The lead chooses effort per
dispatch, and the performance record overrides this prior as soon as it has
comparable outcomes to compare.

Per routing.md: **raising effort on a cheap seat is often better economics than
raising the tier** — a tier step costs 2-5x (Table 2), an effort step ~20%. That
holds best on coding-shaped work, where the effort curve is steep.

## Table 4b — Grok as reviewer: supported, with a hard operating rule

Review work is reasoning-heavy and output-light. Measured on this account: an
adversarial plan review by Grok 4.6 billed **18,044 output tokens of which 14,579
(81%) were reasoning**. So the seat choice for deep review is dominated by output
price and output *volume* — which is where **Grok 4.6** is cheapest: $6/M output at
about half the volume of 4.7, versus $20 (Opus 5.5) and $50 (Astra, Fable 5.1).

> **Hard operating rule — verify a Grok reviewer's citations before acting.**
> AA measures Grok hallucination at **34% (4.6, high)** and **29% (4.7, xhigh)**
> (PRIMARY, 2026-09-21): when uncertain it invents an answer roughly one time in
> three or four. That is a genuine hazard in a critic. Live evidence from this
> account cuts both ways — in a real plan review its quotations of this skill's own
> rules checked out verbatim, and it caught a true self-contradiction; it also
> asserted an event "does not exist" when the event was simply outside its sandbox.
> So: **treat Grok findings as leads with citations attached, and confirm each
> against the named file or line before you act on it.** Where Jev is enabled, a
> citation-support pre-check can order that confirmation work (jev.md) — it never
> replaces it.

## Table 5 — Task type to seat

> **The routing card is the authority on which seat a job gets** (`scripts/routing-card.py`,
> built from `routing-defaults.json`). This table is the evidence behind those rows —
> read it for a deviation, a recon pass, or a model the card does not cover, not as a
> second menu.

Judgment content decides the class (routing.md); this maps class to the evidence-favored
seat once economics is allowed to choose among seats that already clear the bar.
**The First Law is not suspended here:** if no listed seat clears the bar for a
task, go up a tier — or park that outcome as `NEEDS USER` and continue the ones
that still have a qualified seat; never take the cheap row because it is cheap.
**Effort in this table is never prescriptive** — effort is chosen per dispatch by
the lead (Table 4 is the cost prior); this table places seats, nothing more.

| Task | Class | First choice | Then | Never |
|---|---|---|---|---|
| Architecture, ambiguous debugging, final judgment | FRONTIER | LEAD (whichever frontier-class model holds the session) | frontier subagent — `opus` (Opus 5.5); GPT-6 Astra or Fable only with the user's double approval (premium seats) | Luna, Haiku |
| Accepting verdict on a change (blind verifier) | FRONTIER | **Claude verifier** — the default evidence seat; **the lead accepts**. A **Grok 4.6 or GPT-6 Sol read-only reviewer** is the cross-family *second opinion*; GPT-6 Astra is stronger but premium (double approval) | any qualified reviewer (model + transport + allowed tools + assigned checks, with a named executor for every required deterministic check) may give a scoped verdict, its evidence tier disclosed | **a reviewer verdict alone as acceptance proof** |
| Adversarial review / second opinion | FRONTIER-advisory | **Grok 4.6** (output-light, lowest volume), effort by lead judgment | GPT-6 Sol; Grok 4.7 when the review needs to run code; Astra only with double approval | — |
| Hard, well-specified implementation | FRONTIER | **Opus** subagent or **Grok 4.7 at xhigh** (CA 56) | GPT-6 Astra (CA 62) only with the user's double approval | Luna |
| Well-specified implementation, tests, refactors | WORKHORSE | **Grok 4.7** below the 200K cliff under pre-approval (when the user has pre-approved Grok); **GPT-6 Sol** otherwise (CA 57, Codex's workhorse tier) | Sonnet 5 on pool grounds; Grok 4.6 where the record shows 4.7 regressing on this task shape | — |
| Large-context implementation (>200K) | WORKHORSE | **Sonnet 5** (no surcharge) | GPT-6 Sol (long-context tier above 272K) | **Grok (cliff)**, Haiku (200K cap) |
| Mechanical edits, extraction, scanning | FAST | **GPT-6 Luna** | Haiku 4.5 | frontier seats |
| Narrow typed triage (dedupe, support-check, rank, classify) — see jev.md | DECISION | **Jev** when opted in (advisory signal, ~$0.0002) | Luna / Haiku | Jev as acceptance, as a sole security gate, or on dates/arithmetic |
| Repo-wide sweep (>500K) | any | Claude (1M ctx) | Codex up to its 872K max | **Grok (500K ceiling)** |

> **On "FRONTIER-advisory" — what that row does and does not grant.** The row
> places a seat where its *findings* are wanted; it does not move the acceptance
> decision, because acceptance is the lead's and no reviewer verdict alone is
> acceptance proof. What an advisory reviewer does is *produce findings, with
> citations*, that the lead then adjudicates. "Advisory" names that asymmetry —
> **the seat argues, the foreman decides** — and a seat's evidence tier
> (verification.md Layer 0) travels with its findings as *disclosure*, never as a
> reason to discount the seat or to skip confirming its citations. If you catch
> yourself accepting a change *because* the advisory reviewer approved it, that is
> the smuggle this note exists to stop: **never accept because the advisory
> reviewer approved**. The same holds, more strongly, for a Jev probability.

## Table 6 — Which pool a seat drains

Claude workers draw on **the same allowance the foreman itself runs on**; Codex,
Grok, and Jev do not. That is the one genuine endurance asymmetry, and it is the
only "pool" consideration this skill makes — remaining allowance is **not
observable** on any provider, so nothing here allocates quota.

| Seat | Pool | Consequence |
|---|---|---|
| Claude (LEAD + subagents) | the foreman's own | heavy Claude fan-out shortens the run itself |
| Codex | ChatGPT plan, 5-hour and 7-day windows, metered per model (Astra drains fastest) | independent; exhaustion is abrupt and has happened — `CODEX ACCESS: RATE_LIMITED/QUOTA` |
| Grok | Grok Build usage balance (grok.com account) | independent third pool; exhaustion is an HTTP 402 that `grok models` does **not** reveal (2026-09-21) — `GROK ACCESS: BALANCE_EXHAUSTED` |
| Jev | OpenRouter credits or a TypeSafe key | independent, pennies; a revoked key is caught free by `access-check.sh jev` |

**Use:** prefer an off-family seat for bulk implementation so the LEAD pool lasts.
When a pool is *known* down, re-route the remainder and journal it. This never
licenses a seat that does not clear the task's bar — a dead pool is a reason to
**park** the outcomes no remaining seat clears as `NEEDS USER`, with the evidence
and a concrete question for the user, and to carry on with the outcomes that
remaining seats do clear at the bar; never a reason to accept weaker work. The
run halts only when nothing independent is left to do (delegation.md, First Law).

## Provenance of this table
- Claude prices, cache pricing, effort levels, release dates: platform.claude.com model and pricing pages, 2026-09-23 (PRIMARY).
- GPT-6 prices incl. long-context tier: developers.openai.com/api/docs/pricing, 2026-09-23 (PRIMARY). Codex tier positioning and effort levels: the Codex CLI's own model cache on the author's test machine, 2026-09-24 (OBSERVED).
- Grok prices, 200K rule, 4.7 Fast pricing: docs.x.ai pricing, 2026-09-23 (PRIMARY). Grok model list and efforts: `grok models` + the CLI model cache, grok 1.0.41 (OBSERVED).
- II v4.3, CA, output tokens per task, hallucination: artificialanalysis.ai articles on Opus 5.5, GPT-6 Astra, GPT-6 Sol/Luna, Grok 4.7 (2026-09-03 to 09-22). GPT-6 Sol/Luna II values are SECONDARY.
- Grok pool rate: two live pings on this account, 2026-09-23 (OBSERVED).
- Superseded: the 2026-08-17 table (AA v4.1.1, Opus 5 / Fable 5 / GPT-5.6 / Grok 4.5-4.6) — its scores are on a different scale and must not be mixed with these.
- Cost tables: computed from the above; recompute rather than trusting if any input changes.
