# Changelog

## 0.6.4 — 2026-09-24

### Added
- README: a "Now with Jev" section near the top, with the Jev logo (`assets/jev-logo.png`),
  what Jev does for the lead, and a four-step checklist to make sure it works: a key
  from OpenRouter or TypeSafe, where to store it, the `~/.foreman/jev-enabled` opt-in,
  and `scripts/access-check.sh jev`.
- setup-runbook.md: a Jev section so the agent can walk the user through the same steps.
  Docs only; no behavior change.

## 0.6.3 — 2026-09-24

### Fixed
- Finished removing maintainer-specific details that line-by-line searches missed
  because they wrapped across lines: Grok session ids and "run on this machine" in the
  fixture-4 evidence, a local report path in the behavioral results, the test machine's
  global-rule side effects and skill count in grok-workers.md, a note about the
  maintainer's own Codex default, and the test harness's reference to a specific notes
  app. The README's blind-test sentence is also reworded in plain language. Docs and
  comments only.

## 0.6.2 — 2026-09-24

### Fixed
- Removed maintainer-specific details from the docs and test evidence: an absolute home
  path in the fixture-4 evidence file, plus "this Mac", "the user's stated preference" and
  "the user's flags" wording. Docs only, no behavior change. Test fixture 6 now starts its
  local stub without a reverse-DNS lookup, which had timed it out on one machine.

## 0.6.1 — 2026-09-24

### Fixed
- SKILL.md no longer contains `$` followed by a digit. The skill loader treats `$0`, `$1`
  and so on as placeholders for invocation arguments, so the Jev cost "~$0.0002" showed
  up as garbled text whenever the skill was invoked with arguments. Fixture 7 now guards
  against it (7.10).

## 0.6.0 — 2026-09-23

The "know what you can actually use" release. The model lineup changed under the
skill in one month: Claude Opus 5.5, GPT-6 Astra/Sol/Luna, and Grok 4.7. Leads
also kept failing to tell whether Grok was usable. This release rebuilds the
evidence table on a single benchmark version, turns provider access into
deterministic verdicts, and adds an optional Jev decision layer.

### Added
- **Live access verdicts** (`scripts/access-check.sh`) — one minimal call per
  provider through the skill's own launchers, printing a fixed vocabulary
  (`LIVE`, `SIGNED_IN`, `SIGNED_OUT`, `ENV_MISMATCH`, `BALANCE_EXHAUSTED`,
  `AUTH_FAILED`, `RATE_LIMITED`, `KEY_REJECTED`, `NO_KEY`, `DISABLED`, …).
  Billable pings run only under pre-approval or `--consented`.
- **Probe: real Grok sign-in state** — `scripts/probe.sh` now runs `grok models`
  under a bounded wait and parses the sign-in line. It closes three traps
  observed on the author's machine: the command exits 0 when signed out and
  prints a built-in fallback model list; a sandboxed or HOME-redirected shell
  looks signed out (now `ENV-MISMATCH`, not "absent"); and signed in does not
  prove capacity (an HTTP 402 balance exhaustion only shows on a real call).
  It also prints the account's live Grok list and newest base model.
- **Probe: Codex catalog** — the Codex CLI's own model cache is printed with
  each model's positioning text and supported efforts, so classes are mapped
  from the provider's words rather than remembered names.
- **Launchers name access failures** — `grok-dispatch.sh` prints
  `GROK ACCESS: BALANCE_EXHAUSTED | AUTH_FAILED | RATE_LIMITED | NETWORK`, and
  `codex-dispatch.sh` prints `CODEX ACCESS: RATE_LIMITED/QUOTA | AUTH_FAILED |
  MODEL_NOT_ENTITLED`, with matching failure-mapping rows.
- **Jev decision layer (optional)** — `scripts/jev-decide.py` (stdlib Python:
  opt-in gate, key resolution without printing, pre-spend validation of question
  types and the 32K/64K limits, timeout, envelope) and `references/jev.md`
  (eight recipes ranked by value, hard rules, and a shadow-mode graduation test).
  Advisory only: it never accepts, never gates security, and never handles
  dates or arithmetic.
- **Fixture 6** (`tests/fixture-6-access.sh`, 35 cases) — stubbed Grok states
  (signed in, signed out, credentials-but-signed-out, hang, HTTP 402),
  per-model effort refusals, `ultra` refusal, and the Jev launcher against a
  local stub endpoint, including a no-key-leak check.

- **Behavioral suite** (`tests/behavior/`). SPEC.md was written before any run. Seven
  scenarios: trivial inline, farm-out, cross-family build and verify, Jev triage, user
  constraints and `ultra`, frontier judgment, and dead-pool recovery. Each is a real
  headless Claude Code lead run against a scratch repo with hidden answer keys, graded
  deterministically from the transcript. Final run: 7/7 scenarios pass every MUST
  (`tests/behavior/RESULTS-2026-09-23.md`).

- **Routing card** (`scripts/routing-card.py`, `references/routing-defaults.json`) — the
  single answer to "which seat for this job" on this machine. It joins live access,
  consent flags, dated suggestions, saved recon verdicts, and the user's earlier answers.
  - **Settled rows** are defaults that need an allowed, logged reason to deviate.
    "Transport overhead" is explicitly not one.
  - **Close calls** (everyday coding: Grok 4.7 / GPT-6 Sol / Sonnet 5; hard coding:
    Astra / Opus / Grok) produce one grouped, plain-language question with a
    recommendation. The answer is remembered for the session with `remember
    --session`, offered back in later sessions within 30 days in the same project,
    and never applied silently. Unattended runs start from a printed judgment prior.
  - **`NEW MODELS` / `STALE`** trigger one bounded recon pass. Its verdicts are saved
    with an expiry (`recon-record`), so the same model is not researched every session.
  - The card **fails closed** when a model list can't be parsed, and shows
    "needs consent" for providers the user has not pre-approved.
  - Fixture 7 covers all of this (30 cases).
- **Premium seats need double approval** (user direction, 2026-09-24). GPT-6 Astra and
  Claude Fable are never dispatched as a subagent, worker, reviewer, verifier or fallback
  unless the user said yes twice in the current session: once to the ask, and once to a
  confirmation naming the model and its cost.
  - Record the approval with `routing-card.py approve-premium <model> --session <id>
    --confirmed`. It never carries into another session.
  - The Codex launcher refuses `gpt-6-astra` without `FOREMAN_PREMIUM_APPROVED`.
  - The card's defaults and fallbacks were rewritten to avoid premium seats: hard coding
    starts from Opus; verifier and review fallbacks use GPT-6 Sol and Grok 4.6;
    high-risk review uses Grok 4.6 at high plus Sol.
  - A premium LEAD is unaffected.
  - Fixtures 6–7 cover the gate. Behavioral check 0.5 and scenarios T14–T15 test it.
- **Micro-fix allowance** (user decision, 2026-09-24). After the builder reports, the lead
  may correct ≤5 lines in tests, docstrings, comments or docs itself instead of a repair
  round-trip. It is logged as `micro-fix`, followed by the real tests and a **fresh**
  verifier, and is never allowed for production logic. The micro-fix and the three
  existing lead-edit cases (trivial inline, one-command change, recorded takeover) are
  now listed together in hard rail 4. Run 10 observed both sides: a 1-line fix done by
  the lead, and a larger fix sent back to the builder.
- **Three-model skill review** (GPT-6 Sol, Grok 4.7, Opus 5.5, all at medium). The
  adopted suggestions:
  - SKILL.md restructured around a 9-step run order (about 5,300 → 2,900 words); mode
    and provider tables moved to routing.md; every other seat menu defers to the card
  - foreman-verifier dispatched with `model: "opus"` (it previously inherited a Fable
    lead's price)
  - Grok 4.6 as the default off-family reviewer, with Astra for high-risk changes
  - a light lane for one-ticket jobs
  - mandatory Jev shadow calls reduced to recipes 1–2
  - the Haiku-scout "wrapper overhead" exception removed
  - a `bar` deviation reason, so the First Law can still overrule a settled default
    when the lead names the risk

  Deferred: performance-record summaries on the card, and behavioral scenarios for
  fan-out LOST handling, compaction recovery, and a Fable lead.
- **Behavioral runs 6–8** on the restructured skill: 13 scenarios, all passing every MUST
  on their latest run.
  - Leads routed mechanical work to GPT-6 Luna, everyday coding to Grok 4.7 (the
    judgment prior), off-family review to Grok 4.6, and verification to Opus.
  - They asked the single plain-language question when a human was present, respected
    the missing Codex consent, and never used an unevaluated model.
  - One real rule break remains on record: a lead patched two of Luna's docstrings
    itself.
  - New rule from the runs: never end a turn with a worker in flight in headless runs.

### Changed
- **Dispatch gate:** a change one deterministic command completes (a codemod or
  `perl -pi` rename) is run inline. The gate is about model-written work.
- **Jev trigger:** eligible recipes run in shadow mode even when the lead triages inline.
- **Off-family review when Claude builds:** add a read-only Codex or Grok review, or log
  the reason for skipping it. In testing it caught two gaps the Claude verifier missed.
- **Model matrix rebuilt** (`references/model-matrix.md`) on Artificial
  Analysis v4.3 only, with output tokens per task alongside list price. Opus 5.5
  (58, $4/$20) becomes the default frontier Claude subagent, ahead of Fable 5.1
  (53, $10/$50). GPT-6 Luna ($0.10/$0.50) becomes the FAST seat. GPT-6 Sol is the
  Codex *workhorse*: the name moved class from GPT-5.6, where Sol was the
  flagship. GPT-6 Astra is the Codex frontier tier. Grok 4.7 becomes the
  implementation default (Coding Agent Index 56 vs 47) and Grok 4.6 the
  output-light reviewer, because 4.7 emits ~2x the output tokens. The measured
  Grok pool rate is now ~0.34x list (it was 0.17x in August).
- **Effort validation is per model** — both launchers read the CLI's own model
  cache and refuse an effort level the model does not list, before spending.
  Codex `max` is now allowed. Codex `ultra` is refused outright because it
  auto-delegates to sub-agents (hard rail 1).
- **Newest-model rule for Grok** — the newest base model is the implementation
  default. A new release is proven on a representative ticket against the
  previous one before a fan-out leans on it, and any regression fallback is
  scoped to that task shape.
- **LEAD advice** — a one-time, informational Step 0 note is allowed when another
  frontier seat is both higher-scoring and cheaper than the LEAD. The mid-run
  "never switch frontier models" rule is unchanged.
- `probe.sh` no longer reports the default `https://api.anthropic.com` base URL
  as a gateway.

### Evidence
- Live on the author's machine, 2026-09-23: `access-check.sh all` returned
  Grok LIVE (grok-4.7), Codex LIVE (gpt-6-luna), and Jev DISABLED. With a
  scratch opt-in, the Jev check caught a rejected key through the free
  key endpoint, spending nothing. With a valid key, the live check
  showed that OpenRouter rejects the `typesafe/jev-latest` alias. The default is
  now the exact id `typesafe/jev-1.13`, which returned REACHABLE (0.24 s,
  ~$0.00001). A `model:` override and a `MODEL_NOT_FOUND` verdict were added. Fixtures 1–6 pass, including fixture 4 live.
- Blind A/B routing test: two Sonnet readers answered 12 scenarios from the v0.5
  and v0.6 skill files: v0.5 scored 6 correct, 2 partial, 4 wrong, and it
  reproduced the "Grok looks unavailable" bug; v0.6 scored 12/12
  (`tests/evidence/ab-routing-2026-09-23.md`).
- Cross-family review: GPT-6 Astra (read-only, through the updated Codex
  launcher) returned FAIL with six findings. Five were confirmed and fixed with
  regression cases: the Jev check accepted an empty 200, provider error bodies
  could echo a key, the probe timeout could hang on a SIGTERM-ignoring child, a
  failed `codex login status` read as signed out, and a nonexistent `--live`
  flag was advertised. The sixth (effort validation fails open without a model
  cache) is kept by design and now documented.

## 0.5.0 — 2026-09-07

The "policy reconciliation" release. Every rule that let a provider family, a
billing tier, or a fixed effort level stand in for a judgment is replaced by the
judgment itself: the lead accepts, reviewers supply evidence, and seats are
qualified by what they can actually do. Recovery becomes outcome-bound and parks
instead of halting, and the crew starts keeping a performance record. Written
against an adjudicated implementation contract that resolved nine findings from
an independent review, three of them as amendments.

### Changed
- **Acceptance and reviewer qualification** (SKILL.md, `references/verification.md`,
  `references/model-matrix.md`, `agents/foreman-verifier.md`, README) — the lead
  accepts; a reviewer verdict supplies evidence, never acceptance; a reviewer
  verdict alone is never acceptance proof. Reviewer qualification is model +
  transport + allowed tools + assigned checks. Every required deterministic
  observation names its executor: a no-shell reviewer reasons over the candidate
  and the check artifacts while the lead or a designated capable executor runs
  the candidate-bound checks, and an unrun check stays UNVERIFIED. The Claude
  reviewer stays the *default* evidence seat, described honestly as
  contract-plus-detection (a no-edit tool contract plus a mutation backstop),
  not a sandbox.
- **Family bars removed** — all three families are eligible for any role when
  qualified. The "never the accepting verdict" and "advisory only" clauses that
  barred Grok, and the billed-tier authority bar, are replaced by *disclosure*:
  seat-evidence tier is recorded and weighed, never used to disqualify. Grok's
  sandbox protections and the citation-verification rule are unchanged.
- **Effort by lead judgment** (`references/routing.md`, `references/model-matrix.md`,
  `references/grok-workers.md`, `references/codex-workers.md`, SKILL.md) — fixed
  `xhigh`/`medium`/`high` prescriptions are gone from the role table, Table 5, and
  the worker references. Effort is chosen per dispatch by the lead, with the
  highest supported level as the no-evidence prior for Grok and the performance
  record as the evidence that revises it; discretion applies only where model and
  transport support it. The CursorBench effort tradeoff stays as a dated,
  SECONDARY prior with unproved cross-family transfer.
- **Personal final verification** (SKILL.md, `references/verification.md`) —
  independent reviewers supply evidence and challenge; their PASS does not
  transfer acceptance responsibility from the lead, who inspects the actual
  candidate, reconciles original requirements to evidence, adjudicates
  consequential findings, and personally checks critical behavior, material gaps,
  and disputed claims. A required observation that cannot be made is reported
  incomplete.
- **Behavior-test review trigger** — the "single-file, no logic content" review
  exemption is replaced by a behavior test: a change that cannot alter behavior
  may skip independent review; anything that can may not.
- **Outcome-bound recovery with park-and-continue** (`references/delegation.md`) —
  four separate counts keyed on outcome id (delivery attempts, fix waves, review
  rounds, recovery 0 or 1), evaluated guards-first: authority and ownership,
  then outcome state, then original-outcome limits, then failure attribution.
  Two failed fix waves buy exactly one reserved, diagnosed, changed recovery; a
  failed recovery parks the outcome as `NEEDS USER` with evidence, missing
  criterion, concrete question, and resume condition. Dependents are parked with
  their links, independent authorized work continues, and the run halts only when
  none remains. Renames, splits, re-seats, corrected tickets, and restarts never
  reset a count; a third ticket correction without a new observation counts as a
  real failure. Hard rail 5's re-dispatch now defers to the recovery/park state.
- **Hard rails renumbered 1-6 in list order** — collect-or-LOST is now rail 5 and
  seat provenance rail 6. Older entries below cite the pre-0.5 numbering and are
  left as written.
- **Review rounds** — after two rounds the lead writes a per-finding disposition;
  a third round needs a named unresolved criterion, a finite question, and a
  stopping observation; there is no automatic fourth, and round exhaustion never
  creates acceptance.
- **Builder ownership and role transitions** (`references/delegation.md`,
  `references/verification.md`) — the builder makes the WIP commit on the working
  branch and reports the hash; the lead checks clean tree and HEAD. Same builder
  first when resumable (Claude via harness continuation, Grok via launcher
  resume); Codex fresh dispatch is replacement with preserved contract, findings,
  and evidence. A reviewer never changes the candidate it is judging within the
  same assignment; a role change is an explicit journaled writable dispatch, the
  earlier verdict does not cover the new edits, affected checks are re-run, and a
  different fresh context assesses the repaired revision.
- **Plan-stage different-family challenge** — a substantial plan gets an
  off-family challenge that replaces the planned *architecture* review only.
  Candidate-specific post-build assurance is still required; a duplicate
  off-family post-build read may be omitted only with a written risk rationale.
- **Mid-tier lead** (`references/routing.md`) — when the lead is mid-tier the
  acceptance judgment must be frontier-qualified: pin a frontier seat for it or
  stop. Routine reviewers are not all promoted to frontier.
- **Factual claims corrected** — cache reuse is not guaranteed (record telemetry
  when exposed); fifteen concurrent workers is a *reported* default ceiling, not
  a measured maximum; provider telemetry with missing raw values is recorded as
  `unavailable`; a launcher `CONTEXT ALERT` is an average-based routing warning,
  never per-call billing proof; the rail-6 seat-provenance claim is narrowed to
  the common unverified path.
- **README** now gives a concise product overview and links to the skill,
  verification guidance, routing guidance, and this release history for the
  implementation details.

### Added
- **A user-authorized global performance record** at `~/.foreman/crew-performance.md`
  with `scripts/crew-append.sh` — one self-delimited record per closed outcome
  (record key of host, run id, outcome id, closure revision, plus a content
  fingerprint and matching end-marker), bounded lock acquisition with a local
  receipt instead of an indefinite block, stale-lock reclaim only for a provably
  dead same-host owner, staged and fsynced appends with trailing-fragment
  quarantine, no-op on identical duplicates and a conflict exit on a same-key
  different-content record, and corrections appended as new rows. The lead reads
  the relevant slice before a comparable dispatch; no cross-machine sync is
  assumed. The record refuses to conclude universal provider rankings, accuracy
  without a denominator, served identity from self-report, or savings from one
  uncontrolled campaign. Fragment recovery replaces the target by atomic rename
  and keeps the intact copy on failure; lock reclaim uses process-table liveness,
  not `kill -0` alone.
- **Ledger sections** — `scripts/init-ledger.sh` now emits `## Current`
  (overwritten; parked questions and held write surfaces), a reservation section
  (a line before every dispatch, seat identity appended after, `LAUNCH UNKNOWN`
  reconciled before release), and a per-run crew record with run id, host, and
  schema version, and it emits the `RUN:` line and the `## Recovery` section of
  the ledger schema. The atomic exclusive create and the exit-0 `EXISTS` behavior
  on an existing ledger are preserved.
- **Probe output** — `scripts/probe.sh` reports Grok effort as "lead judgment per
  dispatch (no-evidence prior: highest supported)" instead of a fixed level.

### Deliberately NOT changed
- **The launchers.** `scripts/grok-dispatch.sh` and `scripts/codex-dispatch.sh`
  are untouched in this release, sandbox profiles and all.
- **Grok's sandbox and the citation contract.** Removing the family bar does not
  relax either.
- **The First Law**, the 3x expected-runtime worker timeout, and the ledger's
  append-only discipline.

### Known follow-up (not in this release)
- `scripts/grok-dispatch.sh:236` still prints "every call was repriced" where it
  means "the average exceeded 200K; individual calls may or may not have been
  repriced." Corrected in a separate ticket so the launchers stay untouched here.

## 0.4.0 — 2026-08-18

The "know what a seat costs" release. Adds xAI Grok as a third worker provider,
gives routing a dated cost/capability evidence table, and makes review findings
citable and self-correcting. Hardened by an adversarial review from Grok itself,
which returned VERDICT:REVISE with four blockers — three were conceded and the
plan was cut back accordingly.

### Added
- **`references/model-matrix.md`** — the evidence table behind seat selection:
  price, capability index, context ceilings, cache discounts, effort payoff, and
  task-type placement, each dated and sourced. Includes real per-dispatch cost
  comparisons and the finding that list prices are an *upper bound* on
  subscription-metered accounts.
- **Grok worker support** — `references/grok-workers.md`,
  `scripts/grok-dispatch.sh` (fixed-argv launcher), and
  `agents/foreman-grok-wrapper.md` (transport wrapper).
- **The finding contract** (delegation.md) — every reviewer, any provider, tags
  each finding `QUOTED` / `OBSERVED` / `DERIVED` / `INFERRED` and shows its
  citation. Seats are never asked to self-rate confidence.
- **Finding triage** (verification.md) — the foreman resolves citations before
  grading code; unsupported findings are dismissed and journaled, and one
  fabricated citation taints its whole report.
- **Self-correction** (delegation.md) — confirmed findings go to a fix worker and
  then a *fresh* verifier, automatically. The verifier never edits. Bounded by the
  existing precedence table. Stopping remains reserved for: an ask that was
  advisory in the first place (a review is not a licence to implement), a design /
  architecture / security-posture choice or user-visible contract change the user
  owns, external blockers, destructive actions, policy refusals, or a bar no seat
  clears.
- **`BILLED` evidence tier** (verification.md) — ranked below `SERVED`, for
  provider accounting like Grok's `modelUsage`. It never makes a seat `verified`.
- Grok detection in `scripts/probe.sh` (presence, version, auth mode, cached
  model ids — no billable call, no credential values printed).
- **Opt-in Codex standing pre-approval** — a machine-local flag
  (`~/.foreman/codex-preapproved` or `FOREMAN_CODEX_PREAPPROVED=1`), reported by
  `scripts/probe.sh`, lets a user skip the per-session Codex consent ask and
  exempt Codex from budget step-down. The published default is unchanged: the
  consent rule applies.

- **Route to what is actually there** (SKILL.md) — mode (harness capabilities) and
  provider pool are now two independent axes instead of an enumerated combination
  table. Any subset works: Claude-only, Claude+Codex, Claude+Grok, or all three.
  Absence is a routing input, never a blocker, and the foreman never asks the user
  to install a provider mid-run. Includes the case where mode and pool intersect to
  leave no legal acceptor — handled by a disclosed reduced-assurance rule, not a stall.

### Changed
- Seat routing now consults the matrix for the seat *within* a class, and prefers
  off-family workers for bulk implementation because Claude workers drain the same
  allowance the foreman itself runs on.
- Effort guidance is now task-shape aware: analysis/review curves are nearly flat
  (prefer `medium`), long-horizon coding is steep (prefer `high`).
- Grok launcher switches Claude-config discovery off at the source
  (`GROK_CLAUDE_*_ENABLED=false`) and passes `--no-subagents`.
- Launcher measures average prompt size per model call (the json envelope sums
  uncached input across turns); the reactive 200K rule is reworded to a decidable
  context-set rule.
- Wrapper relay is treated as a claim — pinned read-only extraction commands in
  both wrapper contracts; the foreman reads artifacts directly.
- Isolation documented honestly for macOS: no child-network block, whole-disk
  reads, writes-only confinement; Grok `workspace` is weaker than Codex
  `workspace-write`.
- Table 3 percentages corrected (Sonnet 44/45/46% cheaper, not 79/82/84%); the
  cost note corrected to the observed flat 0.17x-of-list pool rate; Table 2 notes
  the Anthropic cache-write premium.
- Launcher absolutizes paths and guards arity; `codex-dispatch.sh`'s evidence
  scanner initializes `candidate` (it raised NameError on every real stream).
- One acceptor stated consistently everywhere: the accepting verdict is always
  the Claude verifier; a Codex read-only reviewer is a second opinion.

### Deliberately NOT changed
- **The First Law is untouched.** An earlier draft would have made it
  "pool-aware" so quota pressure could move the quality bar. The adversarial
  review called that institutionalizing a past failure, and it was dropped.
- **Grok cannot hold a verifier verdict.** Its seat evidence is billed-tier, not
  served-tier, so it is an advisory reviewer and second opinion only.

## 0.3.0 — 2026-08-07

The "trust the log, see the crew" release. Derived from a comparative study of
[claudemix](https://github.com/hughminhphan/claudemix), hardened through three
rounds of adversarial review by OpenAI's frontier Codex model (16 findings →
fixed or explicitly disclosed), and live-tested head-to-head against v0.2.0.

### Added
- **Layer 0 seat provenance** (`references/verification.md`): which model
  actually served a dispatch is graded by deterministic evidence in three
  tiers — SERVED > ROUTED > REQUESTED — never by a worker's self-report.
  Dispatches without real evidence are honestly ledgered `seat: unverified`.
- **Visible-subagent Codex transport** (`references/codex-workers.md`): Codex
  jobs run inside harness-visible wrapper subagents by default — live presence
  in the UI, completion notifications instead of polling, foreman stays free
  during long builds. Direct exec remains the documented fallback for
  sub-minute calls and Codex-only mode.
- **`scripts/codex-dispatch.sh`** — fixed-argv Codex launcher: validates every
  argument, constrains artifact paths (no symlinks, no ticket aliasing),
  records the child PID for orphan control, forwards termination signals, and
  reports seat evidence honestly (current Codex CLI emits no served-model
  field; the launcher says so instead of inventing one).
- **`scripts/probe.sh`** — deterministic Step 0 probe (Codex presence/auth/
  billing mode, native-transport facts, git baseline) with secrets redacted
  from output.
- **`scripts/init-ledger.sh`** — atomic, injection-hardened ledger bootstrap
  that refuses to clobber an existing ledger.
- **`agents/foreman-codex-wrapper.md`** — bundled transport-wrapper role with
  a machine-narrowed tool list (no edit tools, no agent spawning).
- **`references/setup-runbook.md`** — agent-executable, evidence-verified
  environment setup; optional consent-gated native-GPT-subagent transport
  (claudemix-style splitter) with supply-chain pinning rules and honest
  security/ToS statements.
- **Silent-fallback hazard** documentation (`references/routing.md`) with
  current-build empirical results: what silently substitutes, what fails
  loudly, and the countermeasures.

### Changed
- Hard rails: added rail 5 (seat provenance) and a tightly-scoped transport
  carve-out to rail 1 (the wrapper may invoke the launcher exactly once).
- Behavioral anomaly is now a *trigger* for a provenance check, never itself
  evidence of which model served.
- Detected seat substitution is classified as a transport/routing failure with
  its own escalation path (never free same-seat retries).

### Known limitations (disclosed, not hidden)
- Current Codex CLI provides no served-model metadata, so Codex seats remain
  `unverified` at the SERVED tier until the CLI emits it — the launcher already
  scans version-tolerantly for the day it does.
- The wrapper-must-use-the-launcher rule is contractual and transcript-
  auditable; machine prevention requires harness-level tool policy.

## 0.2.0 — 2026-07-19

- Frontier-class LEAD seat parity: any frontier Claude (Fable, Opus) runs the
  foreman identically; Step 0 probe cache expires on mid-run model change.

## 0.1.0 — 2026-07-14

- Initial release: capability-class routing (FRONTIER/WORKHORSE/FAST),
  ticket/status delegation contract, blind fresh-context verification,
  append-only ledger, Codex CLI worker integration.
