# The model matrix — who gets the work, at what effort, at what cost

Companion to [routing.md](routing.md). routing.md is the *procedure* for resolving
classes to seats; this file is the *evidence table* that procedure consults.

**Read this first — what the dollars mean.** On a subscription-authenticated
account (ChatGPT login for Codex, grok.com login for Grok, a Claude plan for the
LEAD seat) these prices are **not** card charges. They are the best available
**proxy for how fast a dispatch depletes that provider's allowance**. They become
literal only on API-key auth. Never quote them to the user as money spent without
first establishing the auth mode (codex-workers.md, grok-workers.md).

**On this subscription the envelope reports a flat pool rate, not the API list.**
Measured 2026-08-17/18: eleven Grok dispatches (1–14 turns) all fit *exactly*
$0.34 input / $0.085 cache-read / $1.02 output per M — 0.17x the public list on
every bucket (5.9x below list-with-cache; an earlier draft said 3.5x, which
priced only cache-read+output and dropped the uncached tokens). Grok's docs say
`total_cost_usd` appears only when the server reports a complete cost, so this is
xAI's own accounting for OAuth/pool traffic (14-headless-mode.md:184). Read it as
a fixed internal rate — not as evidence about what the subscription *allowance*
costs, and there is no comparable measurement for Claude or Codex subscriptions.
Where an envelope reports a cost, record that number; use Table 1 only to compare
seats. The largest of them — the 6-turn plan review — moved 84.5K uncached +
285.6K cache-read input tokens and 18K output for $0.0714.

**Currency rule applies to this whole file.** Every number below is dated. Model
lineups move faster than skill files. If anything here disagrees with the live
provider docs or the account itself, the live source wins and this table is
stale — re-derive it, don't route off it.

## Table 1 — Seats, price, capability (verified 2026-08-17)

Capability = Artificial Analysis Intelligence Index v4.1.1, one consistent source
so the column is comparable. It is a **composite**, not a coding benchmark — see
the health warning under Table 4 before treating small gaps as real.

| Seat | In $/M | Out $/M | Cache read | Context | Index | Notes |
|---|---|---|---|---|---|---|
| Claude Opus 5 | 5 | 25 | 90% off | 1M | **63** | highest measured; no surcharge at any length |
| Claude Fable 5 | 10 | 50 | 90% off | 1M | 62* | *score unstable across index revisions (64.9 → 60 → 62) |
| Grok 4.6 | 2 | 6 | 75% off | 500K | **61** | **2x on the WHOLE request above 200K** |
| gpt-5.6-sol | 5 | 30 | 90% off | 1.05M | 61 | >272K: 2x in / 1.5x out |
| gpt-5.6-terra | 2 | 12 | 90% off | 1.05M | 57 | >272K surcharge as above |
| Grok 4.5 | 2 | 6 | 85% off | 500K | 56 | no `xhigh` — sending it is a hard error |
| Claude Sonnet 5 | 2 | 10 | 90% off | 1M | 55 | no surcharge ever |
| gpt-5.6-luna | 0.20 | 1.20 | 90% off | 1.05M | **52** | best value on the board by a wide margin |
| Claude Haiku 4.5 | 1 | 5 | 90% off | **200K** | 30 | 4096-token cache floor — short turns cache poorly |

**Local (Ollama + Aider) seats are deliberately absent from Table 1.** They
are $0 marginal cost (excluding electricity/hardware already owned), but have
no measured entry on the Artificial Analysis Intelligence Index or any other
cross-vendor benchmark used here — quantization, model choice, and served
context window all vary per machine. Do not invent a number for the Index
column to make them sortable against the rest of this table; route them by
class (ollama-workers.md, routing.md) instead of by a fabricated score.

## Table 2 — What one real dispatch costs

A 4-turn agentic dispatch: ~100K working context sent fresh once, ~300K re-sent
from cache across later turns, 12K output. This shape matters more than list
price, because caching dominates multi-turn work.

| Seat | Cost (no cache-write premium) | Index | Capability per dollar |
|---|---|---|---|
| gpt-5.6-luna | **$0.040** | 52 | **1287** |
| Claude Haiku 4.5 | $0.190 | 30 | 158 |
| Grok 4.5 | $0.362 | 56 | 155 |
| Claude Sonnet 5 | $0.380 | 55 | 145 |
| gpt-5.6-terra | $0.404 | 57 | 141 |
| **Grok 4.6** | **$0.422** | **61** | 145 |
| Claude Opus 5 | $0.950 | 63 | 66 |
| gpt-5.6-sol | $1.010 | 61 | 60 |
| Claude Fable 5 | $1.900 | 62 | 33 |

Anthropic charges 1.25x base input on the first (cache-write) pass — verified on
the pricing page 2026-08-18 (2x for 1-hour TTL); Grok's envelopes report zero
cache-creation tokens (no write charge observed); OpenAI's write policy was
recorded by research as 1.25x but not primary-verified. With the Anthropic
premium applied to the 100K fresh pass: Haiku $0.215, Sonnet $0.430, Opus
$1.075, Fable $2.150 — Grok 4.6 ($0.422) then edges Sonnet rather than "landing
level"; no other conclusion changes. Cross-vendor per-token comparisons also
ignore tokenizer differences (Anthropic's 4.7+ tokenizer yields ~30% more tokens
than its 4.6-era one; vendor-to-vendor counts are not comparable) — treat Table 2
as ±20%.

Three conclusions that should drive routing:

1. **Grok 4.6 is the near-frontier value seat.** It sits in the same index band as
   Opus 5 and sol (61 vs 63 vs 61) at roughly **44% of Opus 5's depletion** and
   **42% of sol's**. State it as a band, not a ratio: per the health warning
   below, a 2-point composite gap is inside the noise, so "61 vs 63" licenses
   "same tier, far cheaper" and nothing more precise. That, not "Grok is cheap",
   is the reason to field it.
2. **gpt-5.6-luna dominates Haiku 4.5 outright** — cheaper *and* far more capable
   (52 vs 30), and Haiku's 4096-token cache floor means short agent turns often
   get no caching discount at all. Where Codex is available, luna is the FAST
   seat; Haiku is the fallback when it isn't.
3. **Sol and Fable are priced above their measured capability.** Sol costs 2.4x
   Grok 4.6 for the same index; Fable costs 2x Opus 5 while scoring at or below
   it. Field them for reasons other than capability-per-dollar — a specific
   strength, cross-family independence, or an unloaded pool — never by default.

## Table 3 — The Grok cliff is a routing boundary, not a price bump

Grok reprices the **entire request** at 2x once it crosses 200K, so cost jumps
discontinuously. Same job, 17% more input:

| Job | Grok 4.6 | Sonnet 5 | Verdict |
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

| Task shape | Accuracy-vs-effort curve | What to do |
|---|---|---|
| Analysis / knowledge work / review (WideSearch, GDPval, BrowseComp) | **nearly flat** — `low` gives up only 1-3 points for 33-50% less cost; `medium` matches `high` at 70-85% of cost | **default `medium`**; top effort is usually wasted money |
| Long-horizon coding (SWE-bench Pro) | **steep** — `low` gives up ~8 points | **default `high`**; do not economize here |

Anthropic's own framing: "Long-horizon coding is the other shape." Treat this as
measured on Anthropic models; the shape is a strong prior for other families, not
a proven transfer.

xAI's own published level guidance (PRIMARY, docs.x.ai) points the same way —
note that `medium`, not `high`, is the level it names for analysis:

| Grok level | xAI says it is for |
|---|---|
| `low` | latency-sensitive work, simple tool calls |
| `medium` | **complex data analysis and long-context reasoning** |
| `high` (default) | hard math, multi-step logic |
| `xhigh` | the hardest problems only |

OpenAI grades `none`→`max` by latency tolerance and difficulty, not by task
category. No vendor draws an explicit review-vs-build line.

| Surface | Levels | Default to | Escalate when |
|---|---|---|---|
| Grok 4.6 | low, medium, high, xhigh | **medium** for review/analysis, **high** for implementation | `xhigh` only for the hardest verification/design |
| Grok 4.5 | low, medium, high (**no xhigh**) | same, capped at high | — sending `xhigh` exits 1 |
| Codex | per codex-workers.md | provider default | hard debugging, final review |
| Claude subagents | scout low / worker high / verifier high | role default | per delegation.md |

The one hard tradeoff number anyone publishes: Grok `xhigh` vs `high` on
CursorBench buys **+0.9pp accuracy for +20% cost** (69.9% → 70.8%; SECONDARY,
cross-corroborated, absent from primary xAI pages). Combined with the flat
analysis curve above, `xhigh` on a review is close to pure waste.

Per routing.md: **raising effort on a cheap seat is often better economics than
raising the tier** — a tier step costs 2-5x (Table 2), an effort step ~20%. That
holds best on coding-shaped work, where the effort curve is steep.

## Table 4b — Grok as reviewer: supported, with a hard operating rule

Review work is reasoning-heavy and output-light. Measured on this account: an
adversarial plan review by Grok 4.6 billed **18,044 output tokens of which 14,579
(81%) were reasoning**. So the seat choice for deep review is dominated by output
price — which is where Grok is cheapest relative to capability: the same review
priced **2.4x on Opus 5, 2.7x on sol, 4.7x on Fable 5**, at index 61 vs 63/61/62.

Benchmark support is real but indirect (SECONDARY): Grok 4.6 **wins** knowledge-
work evaluations (GDPVal-AA, Harvey legal) and **loses** software-engineering
execution ones (DeepSWE -7.1pts, Terminal-Bench -8.6pts vs sol). That is
consistent with "relatively stronger at analysis than at execution" — it is not
proof, no code-review benchmark exists for any model, and some practitioner
reports argue the opposite. Do not overstate it.

> **Hard operating rule — verify a Grok reviewer's citations before acting.**
> Grok 4.6's measured non-hallucination rate is **65.7%** (SECONDARY): when
> uncertain it invents an answer roughly one time in three. That is a genuine
> hazard in a critic. Live evidence from this account cuts both ways — in a real
> plan review its quotations of this skill's own rules checked out verbatim
> against the files, and it caught a true self-contradiction; it also asserted an
> event "does not exist" when the event was simply outside its sandbox. So:
> **treat Grok findings as leads with citations attached, and confirm each
> against the named file or line before you act on it.** This is exactly why
> Grok is an advisory reviewer and never the accepting verdict (Table 5).

## Table 5 — Task type to seat

Judgment content decides the class (routing.md); this maps class to a first-choice
seat once economics is allowed to choose among seats that already clear the bar.
**The First Law is not suspended here:** if no listed seat clears the bar for a
task, go up a tier or stop — never take the cheap row because it is cheap.

| Task | Class | First choice | Then | Never |
|---|---|---|---|---|
| Architecture, ambiguous debugging, final judgment | FRONTIER | LEAD (whichever frontier-class model holds the session) | frontier subagent | Grok, luna, Haiku |
| Accepting verdict on a change (blind verifier) | FRONTIER | **Claude verifier** — always the acceptor. A **Codex read-only reviewer** is the strongest available cross-family *second opinion* (verification.md), never the acceptor | — | **Grok**, and any off-family seat *as acceptor* — Grok's seat evidence is billed-tier and a Grok reviewer never leads with a verdict (grok-workers.md) |
| Adversarial review / second opinion | FRONTIER-advisory | **Grok 4.6 @ medium** (Table 4: review curves are flat; escalate to `high` only when the review is itself long-horizon) | Codex sol | — |
| Well-specified implementation, tests, refactors | WORKHORSE | **Grok 4.6 @ high** (<200K) when cost dominates; **terra** (Codex mid tier — the class table's Codex WORKHORSE seat) otherwise; step up to **sol** only when agentic-execution reliability dominates (First Law: unsure → one tier up) — the only measured head-to-head shows Grok trailing *sol* on DeepSWE and Terminal-Bench (Table 4b). No comparable execution measurement exists for Sonnet 5, whose only cross-model number here is the composite index (where Grok leads 61 to 55) — so do not pick Sonnet over Grok on reliability grounds this table cannot support. | Sonnet 5 / terra on pool grounds | — |
| Large-context implementation (>200K) | WORKHORSE | **Sonnet 5** | terra | **Grok (cliff)**, Haiku (200K cap) |
| Mechanical edits, extraction, scanning | FAST | **gpt-5.6-luna @ low** | Haiku 4.5, then a local Ollama seat if neither is present | frontier seats |
| Well-specified, tightly-scoped, low-context implementation, free of judgment | WORKHORSE-lite, local | **Ollama + Aider** (ollama-workers.md) when the user has opted into local execution and no hosted seat is preferred | any hosted WORKHORSE seat | judgment work, large-context tickets, anything the blind verifier can't cheaply re-check |
| Repo-wide sweep (>500K) | any | Claude or Codex (1M ctx) | — | **Grok (500K ceiling)**, local (context ceiling varies and is commonly small) |

> **On "FRONTIER-advisory" — what that row does and does not grant.** A billed-tier
> seat never carries class-sensitive *authority* (verification.md): it cannot make
> a seat `verified`, cannot supply an accepting verdict, and cannot be the
> FRONTIER judgment a decision rests on. What it can do is *produce findings* that
> a frontier seat then adjudicates. "Advisory" names that asymmetry — the seat
> argues, the foreman decides, and nothing is accepted on the strength of the
> advisory seat alone. If you catch yourself accepting a change *because* the
> advisory reviewer approved it, that is the smuggle this note exists to stop.

## Table 6 — Which pool a seat drains

Claude workers draw on **the same allowance the foreman itself runs on**; Codex
and Grok workers do not. That is the one genuine endurance asymmetry, and it is
the only "pool" consideration this skill makes — remaining allowance is **not
observable** on any provider, so nothing here allocates quota.

| Seat | Pool | Consequence |
|---|---|---|
| Claude (LEAD + subagents) | the foreman's own | heavy Claude fan-out shortens the run itself |
| Codex | ChatGPT subscription, weekly rolling window | independent; exhaustion is abrupt and has happened |
| Grok | grok.com account | independent third pool |
| Ollama (local) | local hardware, not an account pool | no external exhaustion; contends with whatever else on the machine is already using the GPU/CPU (ollama-workers.md) |

**Use:** prefer an off-family seat for bulk implementation so the LEAD pool lasts.
When a pool is *known* down, re-route the remainder and journal it. This never
licenses a seat that does not clear the task's bar — a dead pool is a reason to
stop and tell the user, not to accept weaker work (delegation.md, First Law).

## Provenance of this table
- Prices, context windows, cache discounts, effort mechanics: primary vendor docs, 2026-08-17.
- Capability index: Artificial Analysis Intelligence Index v4.1.1, 2026-08-17.
- Grok CLI behaviours (cliff handling, effort validation, envelope usage fields): established by direct execution on this machine, 2026-08-17.
- Cost tables: computed from the above; recompute rather than trusting if any input changes.
