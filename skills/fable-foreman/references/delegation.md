# Delegation: tickets, statuses, escalation, ledger

## The ticket: 7 core sections + WRITE SET

Workers start with a fresh context. The ticket must carry everything; if the worker would need to ask a question, the ticket is incomplete.

```
TASK: <the task — for verifier tickets, the user's ORIGINAL words verbatim>
EXPECTED OUTCOME: <observable definition of done, gradeable before dispatch>
CONTEXT: <file PATHS to read; current state; background>
CONSTRAINTS: <stack, patterns, performance/compat requirements>
MUST DO: <non-negotiables, incl. the exact verify command to run>
MUST NOT: <the fence — files/scope off limits; no subagent spawning>
OUTPUT FORMAT: <the role's report contract: status-first for execution roles,
              verdict-first for verifier tickets — see the vocabularies below>
WRITE SET: <every file/glob this worker may create or modify — MANDATORY on
           every implementation ticket; omit only for read-only roles>
```

Inline-vs-path rule: short essentials go **inline verbatim** — the task text, acceptance criteria, a verifier's findings being handed to a fix worker. Bulk material — logs, diffs, generated docs, source files — travels as **paths** (workers read files themselves; artifacts go to `.foreman/scratch/`). A measured failure mode: a 42k-character dispatch prompt that was 99% pasted history.

One task per ticket. EXPECTED OUTCOME must be gradeable — if you can't write the acceptance check, you're not ready to delegate. Every ticket also carries its **owner, its checkpoints, and its authority**: what the worker may decide alone, and what it must bring back.

**Every implementation ticket's MUST DO ends with the same line:** *commit your work as WIP on the working branch and report the hash.* The builder owns that commit; the lead checks it (verification.md, "The mutation backstop").

## Parallel dispatch

Only for genuinely independent tickets, and only with **provably disjoint write sets**:

1. Compare WRITE SET declarations across the wave — any overlap, including shared manifests, lockfiles, and generated files → serialize those tickets or give each worker worktree isolation (`isolation: worktree` where supported).
2. Snapshot the baseline first: current commit hash + `git status --porcelain` output into the ledger. Every reconciliation afterward is a diff against this baseline.
3. Sequential remains the default — it can also ride shared prompt-cache warmth (not guaranteed; record the telemetry where exposed), which parallel dispatch forfeits.

### Freezing a candidate

Before a candidate goes to any reviewer, **prove every writer on its paths is
terminal** — collected with a terminal state, or stopped and confirmed dead (SKILL.md
hard rail 5). A possibly-live writer makes every downstream observation unreliable,
and reconciling against one is the concurrent-write race the WRITE SET rules exist to
prevent. Then record what the reviewer is judging:

- the **candidate hash** — the builder's WIP commit on the working branch;
- its **dependencies** — lockfile/manifest versions and the toolchain actually installed;
- the **relevant untracked or ignored inputs** the behavior depends on: `.env` files, fixtures, local config, generated assets — by path, with a fingerprint where that is cheap.

Those inputs sit outside the tracked-mutation backstop (verification.md), so if they
are not recorded at freeze time they cannot be reconciled afterward.

**Stateful rollouts do not freeze with the tree.** Where a change alters state living
outside it — a migration, a schema change, a feature flag, a deployed service, seeded
data — the candidate is the code **plus** the state transition. Record the pre-change
state, the transition applied, and how to observe and undo it; verify against the
state the change actually produced; and never treat a re-run over already-migrated
state as a reproduction of the first run.

## The three vocabularies (do not mix them)

**1. Worker status** — the first line of every **execution-role** report (worker, scout — Claude or Codex alike). Verifier reports use vocabulary 2, never this one:

| Status | Meaning | Foreman's move |
|---|---|---|
| `DONE` | Complete, with evidence (commands run + results, files touched) | Deterministic checks → verifier |
| `DONE_WITH_CONCERNS` | Complete, risks flagged | Resolve every concern before accepting; correctness concerns → fix now |
| `NEEDS_CONTEXT` | Missing information; no risky guesses made | Supply it; re-dispatch same worker, same seat |
| `BLOCKED` | Cannot proceed | Triage below |

**2. Verifier verdict** — `PASS` / `FAIL` / `PASS_WITH_NOTES` (verification.md), the **first line** of every verifier report regardless of which provider runs the verifier. A verdict is not a status; it grades a change, not a worker.

**3. Ledger lifecycle** — per task: `PENDING → DISPATCHED → REPORTED(status)`, branching on the status: `NEEDS_CONTEXT` → back to `PENDING` with a corrected ticket; `BLOCKED` → `PENDING` (re-route per the precedence table) or terminal `FAILED` if surfaced to the user. For `DONE`/`DONE_WITH_CONCERNS` (concerns resolved), the terminal path depends on the task type:

- **Implementation tasks** → `VERIFYING → VERIFIED | FAILED`. `VERIFIED` requires a `PASS` (or a `PASS_WITH_NOTES` whose notes you resolved); a `FAIL` verdict → `FAILED` + fix wave.
- **Read-only tasks** (scout, advisory) → terminal `ACCEPTED` once the foreman has consumed the report — there is no diff to verify.
- **Discipline modes** → terminal `SELF_REVIEWED` after the distinct self-review pass; never recorded as `VERIFIED`.

- **Parked** → `NEEDS USER`: terminal for *automatic* dispatch. Set by a failed recovery, or by any outcome the lead must hand back with a concrete question. Carries evidence, partial-artifact ownership, the missing criterion, the question, and the resume condition; only an explicit recorded resolution reopens it.

`LOST` = dispatched, never reported.

`BLOCKED` triage runs **after** the precedence guards (authority/ownership, then outcome state — see "Evaluation order"), then in order: **(1)** Bad ticket (ambiguous, missing constraint) → fix ticket, same seat — logged on Attempts, and bounded: a third correction on one outcome with no new observation is a real failure. **(2)** Capability gap → consult the precedence table. **(3)** External blocker (credentials, permissions, failing dependency) → surface to the user; do not work around it.

Reports are claims. Accept evidence — file:line references, command output, red-to-green transitions. Hedge language ("should work", "probably") is treated as a failure to verify.

## LOST workers and partial edits

A worker that hasn't reported within a reasonable bound for its task class, or whose process died:

1. **Prove it stopped first.** Check the recorded job's state; if it may still be running, terminate it and confirm a terminal state (exit code, dead process). Reconciling or retrying against a possibly-live worker creates exactly the concurrent-write race the WRITE SET rules exist to prevent.
2. Mark `LOST` in the ledger. Record what you know (job ID, artifact paths, exit code).
3. **Reconcile after the stop**: take a fresh diff against the ledger baseline. Partial edits are either completed by inspection (rare), reverted, or explicitly folded into the retry ticket. Never re-dispatch onto an unreconciled tree.
4. A LOST dispatch counts as a failure toward the precedence table.

Background jobs (including Codex workers): record the job identity and output path in the ledger **at dispatch time**, and capture exit codes on collection.

## The precedence table (single authority for retries and escalation)

Everything here is keyed on the **outcome id** — the unit of authorized work, not the
ticket, the seat, or the file. A rename, a split, a new findings list, a new seat, a
corrected ticket, or a restart **never resets any count**. Genuinely new authorized
scope is a **new outcome id**, recorded as one.

**Four separate counts** live on the Attempts table for each outcome id; none
substitutes for another:

| Count | Increments on | Bound |
|---|---|---|
| Delivery attempts | every dispatch that tries to produce this outcome | the rows below |
| Fix waves | every batched fix ticket against a findings list | two consecutive failures → recovery |
| Review rounds | every review or verification round on this outcome | disposition after two; no automatic fourth |
| Recovery | the one changed-approach attempt after two failed fix waves | **0 or 1, never 2** |

**Every actual dispatch attempt is logged**, including retries you classify as
ticket-caused. "Uncounted" means excluded from *attributable model-quality failures*
only — never erased from attempt history, elapsed time, cost, or the outcome's
recovery boundary.

### Evaluation order — guards first

For any failed, FAILED-verdict, or LOST task, evaluate in this sequence and stop at
the first guard that fires:

**(1) Authority and ownership.** A held write surface, a `LAUNCH UNKNOWN` reservation,
or a possibly-live writer on this outcome's paths **blocks any dispatch until
reconciled** — reconcile the reservation against live processes, prove the writer
terminal, then release or re-hold the surface. This guard runs before everything
else, including hard rail 5's re-dispatch of a LOST ticket.

**(2) Outcome state.** `NEEDS USER` (parked) or an active recovery reservation blocks
automatic dispatch **regardless of how the last failure is classified** — including a
failure classified as ticket-caused, and including the same outcome re-presented under
a corrected ticket. Only an explicit recorded resolution reopens it.

**(3) Original-outcome limits.** The fix-wave and review-round counts for this outcome
id. Exhausted limits are not reset by a new ticket revision.

**(4) Failure attribution and ordinary per-seat routing** — only now does the table
apply. Apply the first matching row:

| # | Condition | Action |
|---|---|---|
| 1 | Failure caused by the ticket (ambiguity, missing context) | Fix the ticket; retry **same seat**. Logged on Attempts; not counted as an attributable model-quality failure |
| 2 | First real failure at this seat | Retry same seat with something changed: corrected ticket, added context, or raised effort |
| 3 | Second real failure at this seat | Escalate one seat, **or** the foreman takes over — whichever the task's class warrants. A takeover records a **concrete cause** and a **bounded stopping point** (what the lead will do, and where ownership hands back), and the **former writer is proven terminal first** |
| 4 | Failure at the top seat (or foreman takeover failed) | **Park this outcome** as `NEEDS USER` with the evidence and a concrete question; continue every independent authorized outcome; the run halts only when none remain |
| 5 | Two consecutive failed **fix waves** against the same findings list | Recovery (below): exactly one changed-approach attempt, then park — regardless of seats remaining |

**Micro-fix (not a takeover).** After the builder reports and no worker is writing
that write set, the lead may correct **≤5 changed lines in tests, docstrings, comments
or docs** itself — never production logic, configuration or data. It is logged
`micro-fix: <files> — <cause>` with the diff hash, the real tests are re-run, and a
**fresh** verifier assesses the result (the lead never certifies its own edit). It does
not count as an attempt or a failure. Anything beyond that limit is an ordinary repair
back to the builder, or a row-3 takeover.

**Ticket corrections are bounded.** A third ticket correction on one outcome id with
**no new observation** is treated as a real failure toward that outcome's limits, not
a free retry: a repeated "bad ticket" classification is itself evidence that the seat,
the approach, or the lead's own understanding of the goal is wrong.

Never a third identical retry anywhere. Escalations are one-way per task: once a task
proves it needs a seat, don't re-try a cheaper one on it. Row 4, row 5, and the guards
exist so "keep trying" never silently becomes the plan.

### Recovery — exactly one, then park

Two failed fix waves on one outcome trigger **exactly one recovery reservation**,
**written before launch**, containing:

- the **diagnosed cause** of the two failures — not a restatement of the symptom;
- the **changed approach**: what is actually different this time;
- the **bounded deliverable** the recovery must produce;
- its **checks**, each naming the executor who will run it;
- its **stopping observation** — what will be true when the recovery is over, pass or fail.

The recovery's own repair and review substeps **cannot mint another recovery**. A
failed recovery moves the outcome to `NEEDS USER` carrying the evidence, ownership of
the partial artifact, the missing criterion, a concrete question for the user, and the
resume condition; it is ineligible for automatic dispatch until an explicit resolution
is recorded. **A failed recovery classified as ticket-caused is still a failed
recovery.**

### Park and continue — never halt a run that still has work

- **Dependents park with their links.** Any outcome depending on a parked one is parked and records the dependency.
- **Independent authorized outcomes continue.** The run halts only when no independent authorized work remains.
- **A surface whose process may still write stays held after the park**, and is reconciled before release.
- **Surface the question when it arises, and again first at closure.** Closure reports parked outcomes before anything else, and **the goal is never reported complete while an original outcome is parked**.

### Review rounds

After **two review rounds** on one outcome, the lead writes a **disposition for each
remaining finding**: confirmed failure, bounded hypothesis, optional improvement, or
unsupported claim. A third round is dispatched only for a **named unresolved
criterion** with a finite question and a stopping observation; there is no automatic
fourth. **Round exhaustion never creates acceptance** — an outcome whose required
observation still cannot be made is reported **incomplete** (verification.md).

## The degradation rule (budget pressure)

When usage limits bite, do **not** blanket-downshift. Re-run the routing decision for each remaining task:

- If a cheaper seat still clears that task's quality bar (tasks are often conservatively over-provisioned), step down **and journal it visibly**.
- If no affordable seat clears a task's bar, **park that task** as `NEEDS USER` — same shape as any park: evidence, partial-artifact ownership, the missing criterion, a concrete question (raise the cap, wait for quota, accept a documented reduction), and the resume condition. Continue every remaining task that a surviving seat clears **at its own bar**, and halt only when no independent authorized work remains. Parked-not-degraded beats degraded judgment — the First Law is not suspended by budget pressure, and neither is park-and-continue.

## The finding contract (every reviewer, every provider)

Any ticket asking a seat to produce findings — review, audit, adversarial
critique, verifier notes — MUST require this shape per finding, in its OUTPUT
FORMAT. Prose without it is a failed ticket, not a soft miss.

```
FINDING <n> | <BLOCKER|MAJOR|MINOR> | <QUOTED|OBSERVED|DERIVED|INFERRED>
CLAIM:   <one sentence — the defect, not the fix>
CITE:    <file>:<line-or-anchor> — "<exact text, verbatim>"   (QUOTED/DERIVED: required)
COMMAND: <exact command> -> <exit code / key output line>     (OBSERVED: required)
SO-WHAT: <the consequence if true>
```

The evidence class is an **objective property of the citation**, not the seat's
feeling about its own claim:

| Class | Means | Foreman check |
|---|---|---|
| `QUOTED` | exact text at a named location | grep the string |
| `OBSERVED` | output of a command the seat ran | re-run it |
| `DERIVED` | inference built on cited quotes | verify quotes, then judge the inference |
| `INFERRED` | reasoning only, no citation | a lead — never actionable alone |

Grading and dismissal rules live in verification.md ("Finding triage"). The payoff
is cost as much as accuracy: checking "SKILL.md line 27 says X" is a lookup;
checking "this contradicts the First Law" is a re-derivation.

**What the contract does NOT do — read this before trusting it.** A resolved
citation proves *the text exists*, never that it *supports the claim*. A seat can
quote a real line and draw a false conclusion from it, and that report passes a
naive grep check. So:

- **`QUOTED` earns a cheap existence check, not acceptance.** After the string
  resolves, judge whether it actually supports the claim. `DERIVED` always
  requires judging the inference on top of the quotes.
- **Severity is the foreman's call, not the seat's.** Confidence self-reports were
  banned for a reason; a self-assigned `BLOCKER` is the same species of claim.
  Re-rank every finding before it enters a fix wave.
- **`INFERRED` means not-yet-actionable, never discarded.** An `INFERRED` finding
  the foreman's **own re-rank** puts at **MAJOR or worse** gets one investigation
  *bounded by the consequence* — a named question, a stopping observation, a scope
  proportionate to what it would cost if true; the foreman establishes the evidence
  itself or re-tasks it narrowly, and only then dismisses or promotes it
  (verification.md, "Finding triage"). Dropping hard, poorly-cited findings while
  shipping well-cited trivia is the failure mode this contract would otherwise create.

## Self-correction — resolve it, don't escalate it

**The foreman resolves what the evidence already settles. It does not hand the
user a decision it can make itself.** On a `FAIL` verdict or a confirmed finding:

1. Triage findings (verification.md). Unsupported ones are dismissed and journaled — not raised with the user.
2. Batch every surviving finding into **one** fix ticket with the verifier's evidence verbatim.
3. Dispatch the fix to a **worker** — **the same builder first** (below).
4. Re-verify with a **fresh** verifier that never saw the first exchange.

**Ordinary repairs stay with the builder that produced the candidate.** Preserving
ownership is cheaper and more accurate than re-seating: the builder already holds its
own reasoning about the candidate, and that context is *normal* for repair work. Three
transport paths, by family:

- **Claude** — continue the same harness session/subagent thread where the harness supports continuation.
- **Grok** — resume the builder's session id through `scripts/grok-dispatch.sh` **on the same profile it was built under**: a `workspace`→`workspace` resume is evidenced to carry write tools (grok-workers.md, "Multi-turn continuation", 2026-08-17: a resumed worker recalled and re-ran its own code), and that is the path for builder repairs. **Cross-profile resume is refused** — a `read-only` reviewer that becomes a fixer always gets a **fresh `workspace` dispatch**, never a resume of its review session (observed refusal, 2026-09-07).
- **Codex** — **fresh dispatch, which is replacement, not retained context**: a new worker carrying the same contract, the findings, and the evidence. Say so plainly; do not describe the earlier context as tainted or contaminated.

Changing the owner is an escalation with a recorded cause (precedence row 3), not a
reflex. Builder context is never reused for that outcome's **independent verifier** —
that is where fresh context is load-bearing.

**The verifier's ban is revision-scoped.** A reviewer may be deliberately re-tasked as
a fixer, and it is not disqualified by family or by its earlier verdict — but:

- the fix is an **explicit, journaled, writable dispatch**, never an edit made under a read-only review ticket;
- the **earlier verdict does not cover the edits** — it graded the revision that existed before them;
- every **check affected by the edit is re-run**, by a named executor;
- **a different fresh context assesses the repaired revision**;
- **an agent that edits a candidate never independently certifies its own edits.** Judgment, repair, and re-verification remain three roles, whoever fills them — this is why `foreman-verifier` ships with no edit tools.

**Bounded by the precedence rules above**, so "keep trying" never becomes the plan:
two consecutive failed fix waves on the same findings list → one recovery, then park
(row 5). Never a third identical retry.

**Stopping is not escalating — and stopping an outcome is not halting the run.**
Every "stop" below means *park that outcome* as `NEEDS USER` with the evidence and a
concrete question, then continue every independent authorized outcome; the run halts
only when none remain ("Park and continue"). The foreman still stops — with evidence — for:

- **an ask that was advisory in the first place.** If the user requested a review,
  an audit, an opinion, or a plan, the deliverable is findings. Self-correction
  applies to work the foreman was told to *produce*, never as licence to start
  implementing off the back of a review the user asked for. Report and ask. If the
  user asked for both — 'build X, then review it' — the build is produce-work:
  confirmed findings against it enter self-correction, and the review's findings
  are still reported alongside.
- a **design, architecture, product, or security-posture choice** — a well-cited
  finding can still be a *judgment call the user owns*, not a settled defect.
- a **user-visible contract change** (API shape, output format, defaults, schema).
- an **external blocker** it must not work around (credentials, permissions).
- an **irreversible or destructive** action.
- a **policy refusal**, or **no available seat clearing the task's bar**. Those are reports the First Law requires, and they
are never satisfied by shipping degraded work instead. Everything else — a wrong
finding, a failed check, a bad ticket, a flaky seat — the foreman fixes and
journals.

## Fix waves

Findings from review/verification batch into **one** fix ticket carrying the complete findings list and the verifier's evidence verbatim — never one worker per finding (each rebuilds context and re-runs suites). Fix output re-enters verification. Two consecutive failed waves → precedence row 5: exactly one recovery, then park.

## Ledger schema

`.foreman/ledger.md`, written before the **first delegated dispatch of any run** — a single-worker run gets the minimal form (BASELINE + one task row + Attempts). Where a real shell exists, bootstrap it with `scripts/init-ledger.sh "<task title>"` (v0.3): it snapshots the baseline deterministically and refuses to clobber an existing ledger, forcing the resume-reconcile path below.

```
# Foreman Ledger — <task title>
BASELINE: <commit hash> | <git status --porcelain summary> | <date>
RUN: <run id> | host <hostname> | ledger schema <version>
## Current      <OVERWRITTEN each update — the live picture:
                in-flight dispatches | held write surfaces | parked questions
                (outcome id → question → resume condition) | LAUNCH UNKNOWN rows>
## Plan         <numbered outcomes, outcome id + class per outcome>
## Routing      <outcome → class → seat (+effort requested / applied) — why;
                route hypothesis + what would overturn it; one line each>
## Tasks        <outcome id | lifecycle state | owned paths | job id | depends-on>
## Reservations <one line WRITTEN BEFORE each dispatch: outcome id | seat |
                intended write surface | expected runtime | reservation id;
                the launched identity (pid / job id / session id) is APPENDED
                after launch; if the launch result is unknown the row reads
                LAUNCH UNKNOWN and the surface stays held>
## Recovery     <outcome id | diagnosed cause | changed approach | bounded
                deliverable | checks + executor | stopping observation>
## Attempts     <append-only, one line per attempt:
                outcome id | attempt # | delivery/fix-wave/review-round/recovery
                counts | seat + effort | seat-evidence tier | ticket rev |
                outcome (status/verdict/LOST + failure class) |
                checks run + executor + results | evidence/artifact paths |
                timestamp>
## Crew record  <one row per dispatch: outcome id | role | task shape | risk |
                requested model + requested effort | effort applied |
                seat-evidence tier | cost estimate | evidenced charge | quota |
                elapsed (execution and waiting separately) | disposition;
                any field the surface does not expose is `unavailable`>
## Decisions    <choices + why; seat changes; degradations; consent grants;
                dispositions after two review rounds>
## Scratch      <artifact paths>
```

`## Current` is the only overwritten section; everything else appends. A dispatch
with **no reservation line written before it** is a contract violation, and a
`LAUNCH UNKNOWN` row is reconciled against live processes — and released or
re-held — before any re-dispatch touching that surface (precedence guard 1).

The Attempts table is what makes the precedence rules provable after compaction:
"second real failure at this seat", "unchanged input", "two consecutive failed fix
waves", and "this outcome already used its one recovery" are all read directly off it
— never reconstructed from memory.

### Closure append to the global performance record

At closure, each outcome's crew-record summary is appended to the user-authorized
global record at `~/.foreman/crew-performance.md` (default path; injectable for
tests) using `scripts/crew-append.sh` — one call per record:

- **Idempotent, keyed** on host + run id + outcome id + closure revision, with a content fingerprint. An identical key with an identical fingerprint is a **no-op success**; an identical key with **different** content is a **conflict** — nothing is written and the receipt names both fingerprints.
- **Corrections are new rows** with a new closure revision referencing the corrected key. Prior rows are never rewritten, and no cross-machine synchronization is assumed.
- **Appends are serialized** under a lock and **bounded**: if the helper cannot acquire it within its bound it exits non-zero and writes a **retryable local receipt** into the run's `.foreman/`. **Closure never blocks on the global record** — report the receipt and finish.
- Records are self-delimited (header + end-marker carrying the fingerprint); an incomplete trailing fragment from an interrupted writer is quarantined, prior complete records are preserved byte-for-byte, and a re-run commits exactly one record.

Exact framing, locking, stale-owner, and recovery behavior live in the script's own
header — read it there rather than restating it here. What the record holds and what
it refuses to conclude is summarized in routing.md ("Route hypothesis and the
performance record"); read its relevant slice before a comparable dispatch.

Update on every state change. **Resuming after compaction or restart:** read the ledger, then reconcile — `git status`/diff against BASELINE, check for still-running jobs, confirm REPORTED/VERIFIED states against actual artifacts — before dispatching anything. A stale `DONE` causes accepted-but-missing work; a stale `DISPATCHED` causes duplicate work. Trust the tree over the ledger.
