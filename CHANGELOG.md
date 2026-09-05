# Changelog

## 0.5.0 — 2026-09-05

The "free the execution seat" release. Adds a local worker family (Ollama +
Aider) for $0-marginal-cost execution — the mechanical counterpart to the
existing Claude/Codex/Grok crew — with no consent gate (nothing is billed to
another account) but the same mandatory blind-verifier gate as every other
seat, since the local worker has no OS-enforced sandbox of its own.

### Added
- **`references/ollama-workers.md`** — probe, billing (none), model
  discovery, transport, and honest seat-evidence limits for the local seat.
- **Local worker support** — `scripts/ollama-dispatch.sh` (fixed-argv
  launcher pairing Ollama with Aider, since Ollama alone has no
  edit/tool-use loop) and `agents/foreman-ollama-wrapper.md` (transport
  wrapper).
- Ollama + Aider detection in `scripts/probe.sh` (CLI presence, server
  reachability, pulled models, Aider presence — no billable call).
- Ollama rows in `references/model-matrix.md` (Tables 5-6) and
  `references/routing.md`, and an Ollama column in SKILL.md's capability-
  class table — FAST/WORKHORSE only, never FRONTIER, never a reviewer.

### Why no consent gate, unlike Codex/Grok
Local execution bills no external account, so the per-dispatch ask that
exists for Codex/Grok doesn't apply. That specifically enables running
simple, tightly-scoped tickets without an ask — it trades away a money
question that doesn't exist on this seat, not the safety question. The
safety question (unsandboxed writes; git auto-commit is the only undo
mechanism) is handled by refusing any workspace-write dispatch against a
dirty tree, and by never waiving the blind-verifier requirement.

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
