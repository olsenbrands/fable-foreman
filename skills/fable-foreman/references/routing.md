# Routing: resolving capability classes to live models

The skill's policy never names dated model IDs. This file is the procedure for resolving FRONTIER / WORKHORSE / FAST to what exists on the user's account **today**.

## The LEAD seat

The session model is the **LEAD seat** — it runs you, the foreman. Do not assume it is frontier-class: sessions start on mid-tier models, org fallbacks, and cost-capped configs. If FRONTIER-class judgment work is on the plan and you cannot establish that the LEAD seat is frontier-class (from the session's own model identity), say so and suggest the user switch models — routing architecture decisions to a mid-tier seat while calling it FRONTIER violates the First Law with extra steps.

**Frontier is a class, not a single model.** The test is whether the LEAD seat clears the frontier bar, never whether it is the *most* capable model in the lineup. Every current top-tier Claude family qualifies, and the foreman behaves identically in each: same classes, same gates, same tickets, same verification. A frontier LEAD must never recommend switching to a *different* frontier model — that is churn dressed up as rigor. Reserve the switch recommendation for a LEAD seat that is actually mid-tier or below.

**The seat can change under you.** Claude Code may move a session to a different model mid-run — safety-classifier fallback (which can also pin the session to the new model for its remainder), quota exhaustion, org policy, or the user typing `/model`. Treat the Step 0 probe as cache with an invalidation rule, not a one-time fact. On any signal the identity moved, re-probe and write one ledger line: `LEAD seat changed: <old class> → <new class> — <trigger>`. Then:

- **Frontier → frontier** (e.g. a fallback between top-tier families): nothing to re-plan. Finish the run; in-flight tickets stay valid, because tickets are written against classes.
- **Frontier → mid-tier** (a real downgrade): stop before the next FRONTIER-class dispatch, tell the user the seat dropped, and let them choose — restore the seat, re-route that work to a frontier subagent, or accept a documented reduction. Never quietly keep making frontier-class calls from a mid-tier seat.

## Claude seats

- **WORKHORSE** = the `sonnet` alias; **FAST** = the `haiku` alias. **FRONTIER** is normally the LEAD seat itself, but frontier-class *workers* are dispatchable too — the Agent tool's `model` parameter accepts frontier aliases (`opus`, `fable`) alongside `sonnet` and `haiku`. Aliases track the latest release in each family automatically — new releases require zero skill edits.
- **When to spend a frontier worker** (the First Law still applies — this is the expensive seat): genuinely independent frontier-judgment workstreams that must run in parallel; a blind verifier for a frontier-class change when no Codex counterpart exists; or a second opinion on a decision the run hinges on. Not for implementation a WORKHORSE clears. An Opus lead dispatching Opus workers is ordinary routing, not an escalation — but it is the priciest crew you can field, so announce it like any other fan-out.
- Pass the model per dispatch via the Agent tool's `model` parameter (overrides agent-file frontmatter). Treat it as a *request*: runtimes may substitute if the org disallows a tier. A dispatch behaving far above or below its class is a *trigger to check provenance* (verification.md Layer 0) — behavior is never itself the provenance mechanism, in either direction: anomalous output doesn't prove substitution, and normal-looking output doesn't prove the requested seat served.

- The built-in `Explore` agent inherits the session model — from any frontier LEAD that is an expensive default for background scanning, and when LEAD and `Explore` resolve to the same model you are paying frontier rates to grep. Dispatch `foreman-scout` (FAST) instead. (With Codex present, model-matrix.md prefers `gpt-5.6-luna` for FAST work; the bundled scout is haiku-pinned — use it for sub-minute recon where wrapper overhead would exceed the saving, and a luna Codex dispatch for large mechanical sweeps.)

### The silent-fallback hazard

A routing request the runtime can't honor may be **silently replaced, not rejected** — the dispatch proceeds on a different model with no error surfaced. Documented field case (claudemix, 2026-08): a non-Claude model string passed *inline* in an Agent tool call was silently dropped and the subagent ran on a Claude model, while the same string in the agent file's `model:` frontmatter routed correctly (through their proxy). The hazard generalizes: org policy denials, decommissioned aliases, and unsupported tiers can all land as silent substitutions.

Empirical status in Claude Code (tested 2026-08-07, current build): an agent file pinned to a foreign model **with no proxy present** fails *loudly* ("Agent terminated early due to an API error"), and inline `model` values outside the supported enum are rejected at schema validation — neither path silently substituted in our tests. Treat that as the harness's current behavior, not a guarantee: the substitution class remains real across runtimes, builds, and org policies.

Countermeasures, in order: **(1)** route non-standard models via agent-file frontmatter, never inline strings; **(2)** treat every `model` parameter as a request; **(3)** close the loop with Layer 0 seat provenance (verification.md) — deterministic evidence of the served model, which converts a silent substitution from an invisible routing error into a logged, handleable event.

## Effort — use the controls that actually exist

Effort is a real dial, but only where a mechanism exists to set it. Per surface:

- **Codex workers**: set it explicitly per invocation — `-c model_reasoning_effort=<level>` (see codex-workers.md).
- **Claude subagents**: the bundled role files carry static defaults — scout `low`, worker `high`, verifier `high` — so a FAST scout never silently inherits an expensive session effort. If your harness offers a per-invocation effort control, it overrides these; if a model/effort combination isn't supported, the runtime falls back to the model's default — log what actually applied. Where no control exists, don't pretend: convey expected depth in the ticket ("mechanical batch edit; do not deliberate" / "reason carefully about the concurrency implications").
- Heuristics: low/minimal for mechanical work; provider default for normal work; deep effort only for hard verification and design. Raising effort on a cheap seat is often better economics than raising the tier — try it first for borderline tasks (precedence table row 2).

## Codex seats

Follow codex-workers.md: probe → consent → **discover the account's actual tiers** (config.toml preference, `/model`, or asking the user; documentation ≠ entitlement; IDs differ by auth mode) → verify each tier you intend to use with one tiny call → map verified tiers to classes by the provider's published positioning → record the mapping in the ledger (consent is skipped only when the probe reports the user's opt-in pre-approval — codex-workers.md).

Providers commonly ship flagship / workhorse / economy tiers, but treat that as a pattern to check, not an invariant. The user's configured default model is their *preference* — identify what it is before classifying it; a user who pinned the flagship as default did not thereby make the flagship your WORKHORSE.

> **Dated example — not policy.** As of 2026-07 the Codex flagship family was GPT-5.6: Sol (flagship), Terra (positioned "everyday workhorse"), Luna ("clear repeatable tasks"), with ChatGPT-account logins using suffixed IDs (`gpt-5.6-sol`) where API-key auth used bare ones (`gpt-5.6`). By the time you read this, assume the lineup has changed — run the discovery procedure.

## Grok seats

Follow [grok-workers.md](grok-workers.md): probe → note billing mode → tiers are
fixed and small (`grok-4.6` default, `grok-4.5`) → dispatch only through
`scripts/grok-dispatch.sh`.

- **Grok 4.6** — first-choice **FRONTIER-advisory** seat (adversarial review,
  second opinion) and a first-choice **WORKHORSE** seat for well-specified
  implementation. Never the accepting verifier verdict: its seat evidence is
  billed-tier, not served-tier (verification.md).
- **Grok 4.5** — lower-capability fallback. **No `xhigh`** — sending it exits 1.
- **The 200K cliff is a routing boundary, not a surcharge to absorb.** Grok
  reprices the *whole* request 2x above 200K — a jump that is certain from xAI's
  published policy. Which alternative then wins on cost is **not** established
  (Table 3): the comparison is list-price math, and measured Grok billing on a
  subscription ran far under list. Route away from the surcharge; do not assert a
  specific cheaper seat as fact. Above 500K Grok is ineligible outright. Apply it
  reactively, not by pre-counting tokens: the launcher reports the dispatch's
  average prompt size per model call and emits `CONTEXT WARN`/`CONTEXT ALERT`.
  **Reactive rule:** after a `CONTEXT ALERT`, do not send Grok another ticket
  that carries the *same context set or a superset* (same working files/paths
  plus the same or a longer resumed session) — that is a fact the foreman knows
  from what it put in the ticket. A fresh ticket with a smaller context set may
  still use Grok; when unsure, don't. A `CONTEXT WARN` means shrink the next
  ticket's context or split it. See model-matrix.md Table 3.
- Grok auto-discovers the user's Claude Code config (CLAUDE.md, skills, agents,
  MCP servers, hooks) by default. The launcher switches that discovery off at
  the source (`GROK_CLAUDE_*_ENABLED=false`) and pins the remaining
  countermeasures; never hand-compose a `grok` command that skips them. Grok
  still prepends its own system prompt and toolset (~19K tokens on this build
  with discovery off; ~28K with the user's Claude config discovered).

Ordinary budget discipline **does** apply to Grok; the user's opt-in Codex
pre-approval (SKILL.md Step 0 item 4) does not extend here.

## Ollama seats (local)

Follow [ollama-workers.md](ollama-workers.md): probe → confirm the server is
reachable and Aider is installed (Ollama alone has no edit/tool-use loop) →
dispatch only through `scripts/ollama-dispatch.sh`.

- No consent gate — nothing is billed to another account, so the per-dispatch
  ask that applies to Codex/Grok does not apply here. This is what makes it
  safe to honor the user's hybrid-trust instruction (simple/mechanical tasks
  may dispatch without an ask) *specifically on this seat*: it trades away a
  money question that doesn't exist locally, not the safety question, which
  is unsandboxed writes — that gate (the blind verifier) is never waived.
- **FAST or WORKHORSE only, never FRONTIER.** No benchmark evidence exists
  for these models the way model-matrix.md's Table 1 sources one for the
  hosted seats — the absence of evidence is itself a reason not to route
  judgment work here (First Law).
- **Context window is a live trap, not a platform constant.** Unlike Codex's
  or Grok's fixed ceilings, what an Ollama model actually serves depends on
  how it's invoked and commonly defaults small. Keep local tickets short and
  self-contained; route large-context work to a hosted seat instead.
- **Seat evidence is the weakest of the four families** — a plain-text banner
  line the same process prints about itself, not an independent event stream
  or billing record. Never write `seat: verified` for a local dispatch.
- No external rate limit or account pool — the constraint is local hardware,
  shared with whatever else on the machine is already using it.

## Choosing the seat for a task

0. **Consult [model-matrix.md](model-matrix.md)** — the evidence table for price, capability, context limits, effort payoff, and task-type placement. This procedure decides *which class*; that table decides *which seat within it*, and records what each choice actually costs.
1. Classify the task's *judgment content*, not its size. A 500-line mechanical rename is FAST; a 10-line concurrency fix is FRONTIER.
2. Apply the First Law: cheapest seat that clearly clears the bar; unsure → one seat up.
2b. **Effort before tier.** The payoff curve depends on task shape, not difficulty: analysis/review is nearly flat (medium ≈ high at 70-85% of cost), long-horizon coding is steep. Raising effort costs ~20%; raising a tier costs 2-5x. See model-matrix.md Table 4.
2c. **Claude workers drain the same allowance the foreman runs on**; Codex and Grok workers do not. For bulk implementation, prefer an off-family seat so the run itself lasts longer. This never licenses a seat that fails the task's bar — remaining allowance is not observable on any provider, so nothing here allocates quota.
3. Claude vs Codex vs Grok within a class: prefer the provider under less quota pressure; prefer cross-family pairing for build/verify; respect explicit user preference.
4. Log every routing decision in one ledger line: `task → class → seat (+effort if applied) — why`.

## Currency rule

If anything suggests your model knowledge is stale — an unfamiliar name from the user, an alias resolving oddly, an entitlement error on dispatch — verify against live provider docs or the account itself before routing. This repo's own first Codex dispatch failed on exactly this: a day-old model family, a CLI predating it, and an auth-mode ID split no static document had caught yet.
