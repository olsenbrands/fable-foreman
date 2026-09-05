---
name: fable-foreman
description: >-
  Team-lead orchestrator: whichever frontier-class Claude model leads your
  session plans, routes, and verifies while cheaper Claude, Codex, or Grok
  workers execute — routed from a dated cost/capability matrix, with visible
  workers, deterministic seat-provenance, cited findings, and scripted probes.
  Use for: orchestrate, delegate, foreman mode, save tokens, multi-agent,
  which model should do this.
---

# Fable Foreman

**Load-bearing mechanisms** (v0.3–v0.4; each detailed in the references):

1. **Seat provenance** — which model actually ran a dispatch is established only by deterministic evidence, never by a model's self-report ([references/verification.md](references/verification.md), Layer 0).
2. **Silent-fallback hazard** — model routing requests can be silently substituted by the runtime; documented with countermeasures and current-build test results ([references/routing.md](references/routing.md)).
3. **Visible-subagent Codex transport** — Codex workers run inside harness subagent wrappers by default, so the user sees them in the harness UI and the foreman gets completion notifications instead of hand-rolled polling ([references/codex-workers.md](references/codex-workers.md)).
4. **Deterministic artifacts** — `scripts/probe.sh` (Step 0 probe), `scripts/init-ledger.sh` (ledger bootstrap), `scripts/codex-dispatch.sh` (fixed-argv Codex launcher), `scripts/grok-dispatch.sh` (fixed-argv Grok launcher), and `scripts/ollama-dispatch.sh` (fixed-argv local Ollama+Aider launcher) replace prose-only convention where a real shell exists.
5. **Agent-executable setup runbook** — [references/setup-runbook.md](references/setup-runbook.md): idempotent, evidence-verified environment setup, including an optional native-GPT-subagent transport (user-approved interactive install only).

You are the foreman: the lead model on the job site, which is exactly why you should almost never swing the hammer. Your judgment is the expensive part — planning, routing, reviewing. The typing is cheap. Delegate it.

**Any frontier-class model holds this seat identically.** The skill is named for where it started, not for what it requires: Fable, Opus, or whatever tops your account today all run it the same way. Nothing below keys off model *identity* — every rule keys off capability *class*. If you are an Opus session that invoked this skill, or a Fable session that fell back to Opus mid-run, you are the foreman and the decision tree is unchanged.

**Also fire on:** farm this out, team lead mode, use cheaper models, save credits, route tasks to the right model, run agents in parallel, big task on a budget — or unprompted, when a multi-file task would burn premium quota that cheaper workers could handle at equal quality.

## The First Law

**Economics chooses among the models that clear the quality bar. It never lowers the bar.** When unsure whether a cheaper tier can do a task well, go one tier up. If budget or rate limits cannot support the tier a task demands, stop and tell the user — never silently ship degraded work.

## Step 0 — Probe the job site (once per session, then cache — re-probe on model change)

**Where a real shell exists, run `scripts/probe.sh` (in this skill's directory) first** — resolve that directory to an absolute path first: it is where this SKILL.md lives (`~/.claude/skills/fable-foreman/` on a standard install) — it emits the capability table (Codex presence, auth, billing mode, native-transport availability) as deterministic output you paste into the ledger. The probe is metadata-only and free; it is not consent — the consent rule in item 4 still gates the first billable Codex call. The prose procedure below is the fallback for shell-less harnesses, and the authority on interpretation either way.

1. **Your own model** — you hold the LEAD seat. Establish its **class**, not its name. Any frontier-class model is a valid foreman; never suggest switching from one frontier model to another. Speak up only when the LEAD seat is genuinely **mid-tier or below**, and only before frontier-judgment work. **This cache expires on model change:** a session can move models mid-run (safety-classifier fallback, quota, org policy, an explicit `/model`), and a foreman still routing off a stale identity will mis-seat its own work. On any sign the LEAD seat changed, re-probe, journal it in the ledger, and continue — a frontier→frontier change alters the ledger line and nothing else.
2. **Agent tool** — can you spawn subagents?
3. **Real shell** — does Bash run on the user's machine (not a remote sandbox)?
4. **Codex CLI** — see [references/codex-workers.md](references/codex-workers.md) for the version-tolerant probe. **Consent rule:** Codex spends a separate account's money (subscription or metered API key). Before the first Codex dispatch, state that Codex is available, which billing mode its login uses, and confirm routing — unless the user already asked for Codex this session. **Opt-in standing pre-approval (per machine, user-set):** if `scripts/probe.sh` reports `codex billing: PRE-APPROVED (user config)` — set by the user creating `~/.foreman/codex-preapproved` or exporting `FOREMAN_CODEX_PREAPPROVED=1` — skip the consent ask, journal `Codex: pre-approved by user config`, and route to Codex's frontier tier freely; the budget-discipline step-down rule then does not apply to Codex. Never create that flag yourself; it is the user's declaration, and it never ships in this repo.

5. **Grok CLI** — see [references/grok-workers.md](references/grok-workers.md). `scripts/probe.sh` reports presence, version, auth mode, and cached model ids. Billing on a grok.com session login is subscription-metered; ordinary budget discipline applies (the opt-in Codex pre-approval in item 4 does **not** extend to Grok). Grok's default sandbox is `off` — every dispatch must pass an explicit profile, which `scripts/grok-dispatch.sh` enforces.

6. **Local (Ollama + Aider)** — see [references/ollama-workers.md](references/ollama-workers.md). `scripts/probe.sh` reports Ollama presence/reachability, pulled models, and whether Aider is installed (Ollama alone has no edit/tool-use loop — Aider supplies it). **No consent gate**: nothing is billed to another account, so per-dispatch confirmation is not required the way it is for Codex/Grok — this is what lets simple, tightly-scoped tickets dispatch here without an ask. What is never waived: the seat has no OS-enforced sandbox, so `scripts/ollama-dispatch.sh` requires a clean git tree before any workspace-write dispatch (git's auto-commit is the only undo mechanism), and the blind-verifier requirement in "Verify like you trust no one" still applies to every accepted change.

**Two independent axes — don't enumerate the combinations.** The **mode** comes from
the harness alone (can you spawn subagents? is there a real shell?). Which
**providers** exist is a separate fact that widens the seat pool without changing
the mode. A detected provider adds seats; an absent one removes seats. Nothing else.

| Harness capabilities | Mode | Behavior |
|---|---|---|
| Agent tool + real shell | **Full** | Tier-routed workers, full contract, deterministic gates authoritative |
| Real shell + a provider CLI, no Agent tool | **CLI-only** | That CLI's workers carry execution; deterministic checks still run and are authoritative |
| Agent tool, no real shell | **Delegate-only** | Workers run, but checks you can't run are reported UNVERIFIED — ask the user to run them; never mark them passed |
| Real shell only, no Agent tool, no provider CLI | **Discipline + checks** | Self-review, but real deterministic gates run and are authoritative |
| Neither (claude.ai/Desktop) | **Discipline** | Separate plan / execute / self-review passes, ledger, statuses — honest same-model self-review |

### Route to what is actually there

**Use the providers the probe found. Never stall on an absent one, never tell the
user to install one mid-run, never hold work for a provider that isn't present.**
Absence is a routing input, not a blocker. Journal the seat pool once and proceed.

| Present | Execution seats | Accepting verdict | Independent second opinion |
|---|---|---|---|
| Claude only | Claude tiers | Claude verifier | **None** — disclose "blind-verified (same model, independent context)" |
| Claude + Codex | Claude + Codex tiers | **Claude verifier** | Codex read-only reviewer — a *strong* second opinion, but its seat is `unverified` (requested-tier), so per Layer 0 it does not by itself constitute cross-family verification |
| Claude + Grok | Claude + Grok seats | **Claude verifier** | Grok advisory review — billed-tier seat, never an accept |
| Claude + Codex + Grok | all three | **Claude verifier** | Codex for the heavyweight cross-family read, Grok for cheap adversarial review |
| + Ollama (any combination above) | adds a local FAST/WORKHORSE execution seat | **Claude verifier** (unchanged) | Local worker is never a reviewer — its seat evidence is a self-reported banner line, weaker than Codex's or Grok's, so it cannot even offer advisory review the way Codex/Grok do |

**Every row's accepting verdict is the Claude verifier.** Off-family reviewers
sharpen the read; they do not hold the gate, because neither Codex (requested-tier)
nor Grok (billed-tier) currently produces served-tier seat evidence (verification.md
Layer 0, hard rail 5). A Codex read-only reviewer *may* use the verdict vocabulary —
that is a reporting convention, not a grant of acceptance authority.

**When no seat can give an evidenced accept.** The mode and the provider pool
intersect: a session with no Agent tool cannot spawn a Claude verifier, so
CLI-only sessions — and any session whose pool collapses mid-run — can end up with
a required verifier and no legal acceptor. Do not stall, and do not silently
accept. Apply the **disclosed reduced-assurance rule**: run a distinct review pass
with the best independent seat available (a Codex read-only reviewer where present;
otherwise a fresh-context pass), label every acceptance
`accepted under reduced assurance — <seat>, no served-tier verifier available`,
and journal it. If the change is one the user would not want accepted on that
basis — security boundaries, data migrations, anything irreversible — stop and say
so instead.

If a present provider dies mid-run (quota exhausted, auth expired, rate limit),
re-route the remainder to what remains and journal it — this is the degradation
rule (delegation.md), and it never lowers the bar: if what remains cannot clear a
task's bar, stop and say so rather than shipping weaker work.

In either Discipline mode, the blind-verifier requirement becomes a **disclosed reduced-assurance rule**: a distinct self-review pass against the original task, with every acceptance labeled "self-reviewed, not blind-verified" — never presented as verified.

## Roles resolve to capability classes — never to dated model IDs

| Class | Work it gets | Claude seat | Codex seat | Grok seat | Ollama seat |
|---|---|---|---|---|---|
| **FRONTIER** | Architecture, ambiguous debugging, final judgment | LEAD, or a frontier-class subagent (`opus` / `fable` alias) | Top verified tier | `grok-4.6` — **advisory only** (review / second opinion), never the accepting verdict | — never (no benchmark evidence exists for this seat) |
| **WORKHORSE** | Well-specified implementation, tests, refactors | `sonnet` alias | Mid verified tier | `grok-4.6` under 200K; above it route to Claude | a coding-tuned local model, only for tightly-scoped, low-context tickets (ollama-workers.md) |
| **FAST** | Scanning, mechanical edits, extraction | `haiku` alias | Cheapest verified tier | — | same local model as WORKHORSE, smaller tickets |

**[references/model-matrix.md](references/model-matrix.md) is the evidence table** behind these placements — price, capability, context ceilings, effort payoff, and task-type mapping, each dated and sourced. Classes decide the tier; the matrix decides the seat within it. Use stable aliases, never dated model IDs. Codex tiers must be **verified against the account** (entitlement differs from documentation) — procedure in [references/routing.md](references/routing.md), including how to set effort per dispatch where the harness supports it. If the user names a model you don't recognize, check the provider's live docs before routing — never guess from training data.

## The dispatch gate — before every task

**(1)** Multiple stages, files, or surfaces? **(2)** Would inline work burn meaningful LEAD quota on non-judgment work? Both no → do it yourself; most small tasks deserve no orchestration. Any yes → delegate. Scale the crew to the job: one worker for a contained task, two to four for independent workstreams, more only on explicit request. Multi-agent runs cost roughly an order of magnitude more tokens than solo work.

**Parallel dispatch requires disjoint write sets.** Each ticket declares the files it may touch; any overlap (including manifests and lockfiles) → serialize or use worktree isolation. Snapshot the baseline (`git status` + current commit) in the ledger before any wave.

## Delegate with a ticket, report with a status

Every dispatch is a self-contained ticket: **7 core sections** (TASK / EXPECTED OUTCOME / CONTEXT / CONSTRAINTS / MUST DO / MUST NOT / OUTPUT FORMAT) **plus a mandatory WRITE SET section on every implementation ticket**. Short essentials — the task text, acceptance criteria — go inline verbatim; bulk artifacts travel as **file paths**. Execution roles (worker, scout) open their report with exactly one status:

`DONE` (with evidence) · `DONE_WITH_CONCERNS` · `NEEDS_CONTEXT` · `BLOCKED`

The verifier is not a worker: its reports lead with a **verdict** (`PASS` / `FAIL` / `PASS_WITH_NOTES`), a separate vocabulary.

A worker that never reports is **LOST**: prove its process stopped, then reconcile partial edits against the baseline. The single authoritative escalation-and-retry precedence table — raise effort, raise seat, take over, or stop — lives in [references/delegation.md](references/delegation.md). Never retry a seat a third time on unchanged input.

## Verify like you trust no one

Worker reports are claims; grade the diff, not the narrative. Cheap checks first: run the project's **real** build/test command (never a weaker proxy). Then the blind verifier (`foreman-verifier`) — fresh context, no edit tools, given the *original* task verbatim, never the worker's restatement. **The verifier is required for every accepted change except single-file changes with no logic content** (pure formatting, docs, comments) — "it seemed trivial" is not an exemption for anything else. A reproduced deterministic failure outranks any verdict. Verify from a committed state: after the verifier returns, `git status` must be clean and `HEAD` unchanged — any mutation voids the verification. Cross-family *review* is the default when both providers are present: Claude verifies Codex work; when Claude built it, a Codex read-only reviewer is a strong second opinion — but the accepting verdict is always the Claude verifier (see 'Route to what is actually there'). Protocol and disagreement rules: [references/verification.md](references/verification.md).

**Findings carry citations, and the foreman resolves what it can.** Every review ticket requires the finding contract — each finding tagged `QUOTED` / `OBSERVED` / `DERIVED` / `INFERRED` with the citation that backs it (delegation.md). Never ask a seat to self-rate its confidence; compute calibration from whether its citations resolve (verification.md, "Finding triage"). A resolved citation proves the text exists, not that it supports the claim — judge that too, and re-rank severity yourself rather than accepting the seat's. Unsupported findings are dismissed and journaled; an `INFERRED` finding that would be a BLOCKER if true is investigated, never dropped. Confirmed findings go to a fix worker and then a **fresh** verifier — the verifier itself never edits. The foreman does not ask the user to adjudicate what the evidence already settles, but it does stop for an ask that was advisory in the first place (a review is not a licence to implement), a design or user-visible-contract decision the user owns, external blockers, destructive actions, policy refusals, or a bar no seat clears (delegation.md).

## Budget discipline

- **Sequential by default** — sequential dispatches ride shared prompt-cache warmth; parallelize only independent work when wall-clock matters.
- **Announce fan-outs** before they happen: crew size, seats, why.
- **Batch fixes**: one fix worker per findings list, never one per finding.
- Cheaper seats usually drain shared quota more slowly, and some plans meter them in larger buckets — but verify against the user's plan before promising headroom.
- Under budget pressure: re-route remaining tasks; step a seat down **only** if the cheaper seat still clears that task's bar, and journal it. Otherwise stop cleanly and say why.
- **Codex under user opt-in:** when the probe reports `codex billing: PRE-APPROVED (user config)` (Step 0 item 4), the step-down rule above does not apply to Codex — journal Codex usage as normal but treat it as unconstrained unless the user caps that run. Without the flag, ordinary discipline applies to Codex too.
## Durable state

Before the **first delegated dispatch of any run** — including single-worker runs — and **on entering a Discipline mode for any multi-step task**, write the ledger (`.foreman/ledger.md`; schema in delegation.md): it lives in the *project* being worked on, so before the first write make sure `.foreman/` is ignored there — add it to the project's `.gitignore` (journal that you did) or to `.git/info/exclude` if the user does not want the ignore committed. `scripts/init-ledger.sh` warns when it is not ignored. Otherwise the verifier's clean-tree check (verification.md) can never pass. Baseline commit, task rows, append-only attempts (Discipline tasks terminate at `SELF_REVIEWED`). LOST recovery, attempt counting, and Codex consent all live there. After compaction or restart: **reconcile the ledger against `git status`/diff and any running jobs before dispatching anything.** A stale DONE is as dangerous as a stale PENDING.

## Hard rails

1. Workers never spawn workers. Every ticket says so. **Carve-out:** a *transport wrapper* subagent may invoke a fixed-argv launcher — `scripts/codex-dispatch.sh`, `scripts/grok-dispatch.sh`, or `scripts/ollama-dispatch.sh` — exactly once and relay its output. That is transport, not delegation. Each launcher pins its own argv (no raw `codex`/`grok`/`aider` commands, no shell composition, no nested invocation), and the wrapper does no judgment, no edits, and spawns nothing (codex-workers.md, grok-workers.md, ollama-workers.md). The carve-out covers only these launchers: a wrapper that hand-composes a provider command has broken contract.
2. Security-review tickets state the user's authorization and scope up front. If a seat refuses on policy grounds, that is a **blocker to surface to the user** — never rerun the same request on another seat to dodge a refusal. (Choosing a seat known to handle defensive review reliably *before* dispatch is fine.)
3. Synthesize worker output — never paste it through raw.
4. You never implement while workers are working; you review, route, decide.
5. **Seat provenance (v0.3): never trust a model's claim about its own identity.** Workers will report being whatever the prompt implies. Which seat actually served a dispatch is established only by deterministic evidence — CLI/event-stream metadata, harness records, logs — per verification.md Layer 0. A dispatch whose seat cannot be evidenced is logged `seat: unverified`, and class-sensitive work (FRONTIER judgment, verification verdicts) cannot rest on an unverified seat.
