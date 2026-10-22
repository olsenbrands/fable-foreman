# Verification: cheap checks first, then a blind reviewer

Orchestration's bottleneck isn't coordination — it's validation. This is where the skill spends its rigor.

## Layer 0 — Seat provenance (verify with the log, never the model's self-report)

Routing decisions are only as real as the seat that actually served the request, and runtimes can substitute seats (routing.md). So before a report's *content* is graded, its *provenance* is established — from deterministic evidence only. Evidence comes in tiers, and the tiers are not equal:

- **SERVED evidence** (the real thing): an artifact produced *after* model resolution that names the model that answered — a served-model field in an event stream, a provider-side log correlating the request to the serving model. Only served-tier evidence makes a seat `verified`.
- **BILLED evidence** (new, below served): provider-side *accounting* that names the model charged for the turn — e.g. Grok's envelope `modelUsage` key, which tracks the request rather than echoing a constant. Materially stronger than a self-report, because it originates outside the model's prose. It is still **not** served evidence: a billing SKU names what was charged, not the weights that answered, and nothing establishes that it would reveal a substitution. **Billed evidence never makes a seat `verified`** — it is recorded and disclosed at its own tier, which is the whole consequence; it does not disqualify the seat from a role it is otherwise qualified for (SKILL.md hard rail 6).
- **ROUTED evidence** (weaker): an artifact proving which *route* a request took without naming the served model — a proxy log line, an HTTP status from a known upstream. Records that routing behaved; does not verify the seat.
- **REQUESTED evidence** (weakest): what you asked for — a `-m` flag, an agent-file `model:` line, the harness UI echoing the dispatch parameters. Necessary for the ledger, worthless as proof of what served.

Per surface, honestly stated:

- **Codex dispatches:** current Codex builds do **not** emit a served-model field in `codex exec --json` (verified 2026-08-07 against the CLI's JSONL processor source — the stream's `thread.started` carries only a thread id). The launcher (`scripts/codex-dispatch.sh`) scans for one anyway, version-tolerantly: if a future build emits it, that is served evidence; until then every Codex dispatch is `seat: unverified — requested <model> via -m`, written exactly so in the ledger attempt line. Do not dress requested evidence as served.
- **Grok dispatches:** the JSON envelope carries `modelUsage` keyed by the billed model (verified 2026-08-17: requesting 4.5 vs 4.6 changes the key). That is **billed-tier** evidence — `scripts/grok-dispatch.sh` prints it as `seat: billed-tier evidence — modelUsage <key> (NOT served-tier; not 'verified')` and the ledger records that string verbatim. The consequence is **disclosure**: a Grok seat is qualified for the roles its capability, transport, tools, and assigned checks support — including review, where its verdict is scoped evidence for the lead — and every acceptance resting on it names the tier. What billed evidence cannot do is prove which weights answered, or turn any reviewer's verdict into acceptance; the lead accepts (grok-workers.md, model-matrix.md Table 5, "Personal final verification" below).
- **Claude subagent dispatches:** harness dispatch metadata generally records the *request* (requested tier). Where the harness surfaces a post-resolution model identity, that is served evidence; where it doesn't, the seat is `unverified` — say so rather than inferring the seat from output quality or the worker's claims.
- **Never** establish provenance by asking the worker what model it is. A model's self-identification tracks its prompt and system context, not its weights. (Measured nuance, 2026-08-07: Claude Code injects identity into Claude subagents' system prompts, and haiku subagents resisted three priming attempts including a fake proxy-routing notice — self-reports *here* are usually right. The rule stands anyway: "usually right" is not evidence, and the risk concentrates exactly where it matters — foreign models behind proxies, which have no identity anchor at all.)

Consequences of an unverified seat: **disclosure, not disqualification.** The work is not discarded and the seat is not barred from its role; what changes is what you may *claim*. Record the tier on the attempt line and repeat it in any acceptance resting on that seat: (a) it does not by itself prove that cross-family verification happened (below) — the *independence of the read* still ranks as it does, but the served identity is unproved; and (b) FRONTIER-class judgment recorded from it is labelled disclosed-uncertain, so the lead weighs it knowing the seat is unproved rather than treating it as established. Acceptance was never the seat's to give in the first place. A **detected substitution** (evidence shows a different seat than routed) is a *transport/routing failure*, not a ticket failure: invalidate the seat mapping, repair the route (or change transport) before re-dispatching, and count a repeated substitution on the same route as a real failure toward the precedence table — never loop free retries into a route that is known to lie.

## Finding triage — grade the citation before you grade the code

Findings are claims, and a seat that fabricates when uncertain fabricates
confidently. **Never ask a seat to self-report a confidence score.** Require the
finding contract instead (delegation.md): every finding carries an evidence class
— `QUOTED`, `OBSERVED`, `DERIVED`, or `INFERRED` — and calibration is computed by
the foreman from whether the citations resolve.

1. **Resolve every citation first.** `QUOTED` → the exact string must exist at the
   named location (grep it). `OBSERVED` → the named command must reproduce. This
   is cheap: a lookup, not a re-derivation. Where a finding arrived through a
   transport wrapper, resolve it against the *artifact file*, not the relayed text.
2. **Re-rank severity yourself — before any dismissal.** The seat's severity is a
   claim like any other (delegation.md), and the whole triage branches on
   severity, so re-ranking comes *first*: judge the consequence if the finding
   were true, against this candidate and this user's system. Only the lead's rank
   decides what happens next. Never let a seat's self-assigned `MINOR` route a
   consequential defect into the dismissal path.
3. **Unsupported findings do not enter a fix wave — but the re-ranked severity
   decides what happens instead.** A finding whose citation fails to resolve, or
   an `INFERRED` finding the lead ranks below MAJOR, is recorded
   `DISMISSED (unsupported)` in the ledger with the reason. An **`INFERRED`
   finding the lead ranks MAJOR or worse gets exactly one bounded investigation,
   sized to the consequence**: a named question, a stopping observation, and a
   scope proportionate to what it would cost if true — the foreman establishes
   the evidence itself or re-tasks it narrowly, and only then dismisses or
   promotes it (delegation.md). Resolving a bad finding is the foreman's job, not
   the user's — but silently discarding a hard one is not resolving it.
4. **Taint rule.** One fabricated citation means re-verify *every* finding in that
   report and write `seat reliability: fabricated citation` on the attempt line.
   That seat carries no advisory weight for the rest of the run.
5. **Absence is not evidence.** "X does not exist" is `OBSERVED` only when the
   failed search is shown *and* its scope covers where X would be. A seat
   reporting absence from a sandbox that could not reach the location is
   `INFERRED`. Before dismissing a **sub-BLOCKER absence claim, the lead runs the
   reachability check itself**: could the seat's scope have seen the location at
   all, and does the claim hold when *you* look there? It is a lookup, not an
   investigation. If the absence would be **immaterial even if true**, do not
   investigate it — record it dismissed with that reason and move on. (Live case,
   2026-08-17: a read-only reviewer correctly quoted four rules from files it
   could see, then declared an event nonexistent because it lay outside its
   sandbox. Four findings stood; that one did not.)

## When the verifier is required

In Full and Delegate-only modes: **every accepted change that could alter behavior.**
The exemption is a **behavior test, not a size test** — a change is exempt only when
the lead can state why it cannot alter executed code, configuration, data, or
user-visible output (a comment, a doc paragraph, whitespace). File count is not the
test: a one-line, one-file change to a condition is not exempt, and a large
docs-only diff is. If you cannot state the reason, the change is not exempt. In
Delegate-only mode the verifier still runs, but deterministic checks nobody could
execute remain **UNVERIFIED** until the user supplies their results — a verifier
verdict cannot substitute for an unrun check, so acceptance waits on both. In
CLI-only mode (real shell + provider CLI, no Agent tool) there may be no Claude
verifier to spawn; the trigger for SKILL.md's disclosed reduced-assurance rule is
**no qualified independent reviewer available** (model + transport + tools + assigned
checks) — not "no served-tier verifier". When another family's reviewer *is* present
and qualified, use it and accept normally, with the seat's evidence tier disclosed.
When none is, run a distinct review pass with the best independent seat available,
label every acceptance `accepted under reduced assurance — <seat>, no qualified
independent reviewer available`. For security boundaries, data migrations, or
anything irreversible, do not accept under that label — **park that outcome** as
`NEEDS USER` with the evidence and the question, while independent work continues
(delegation.md, "Park and continue"). In the Discipline modes there is no blind verifier — the disclosed reduced-assurance rule in SKILL.md replaces this section, and acceptances are labeled "self-reviewed, not blind-verified." That's the whole rule. "It seemed straightforward" is not an exemption — straightforward-looking changes are where unreviewed regressions live. If you are tempted to skip the verifier, that impulse is itself a signal the change deserves one.

## Layer 1 — Deterministic checks (free, always first)

Run the project's **real** gate yourself via Bash before paying for model judgment:

- The actual build/test command the project ships (`npm run build`, `make test`, CI's exact command). **Never a weaker proxy** — a bare `tsc --noEmit` can pass while the real `tsc -b` build fails. Unsure what the real gate is? Read `package.json` scripts / CI config; don't invent one.
- In delegate-only mode (no real shell): you cannot run these — mark them **UNVERIFIED**, ask the user to run them, and never count an unrun check as passed.

A failing deterministic check needs no verifier — it goes straight into a fix ticket.

## Layer 2 — The blind verifier (`foreman-verifier`)

Dispatch with:

1. **The original task, verbatim** — the user's words, never the worker's restatement. Workers narrow problems in self-serving ways ("customer #4012" becomes "some customers").
2. The diff or changed-file paths.
3. The acceptance criteria from the ticket, inline.
4. **Nothing else.** No worker reasoning, no summaries. Anchoring the verifier on the builder's narrative defeats the point.

The verifier assumes the work is broken until evidence says otherwise: it walks the diff and checks the *goal*, not just the checklist — "checks pass but the goal is broken" is a FAIL.

**Every required deterministic observation names its executor.** The check is run by
the seat that actually can run it: a `foreman-verifier` whose allowlist is
read-and-run only (`Read, Glob, Grep, Bash` — no edit tools, no delegation, no
skills; Bash is check-only by contract) runs its own assigned checks; a reviewer with
no shell (a Grok `read-only` reviewer, a Codex sandboxed read) **does the independent
reasoning over the candidate and the check artifacts**, while the lead or a
designated capable executor runs the candidate-bound checks and records the output.
Write the executor beside each check in the ticket and on the attempt line. **A check
nobody ran is UNVERIFIED** — never marked passed because a reviewer read a log
someone else produced, and never inferred from a verdict. No route is declared
equivalent to another, and no sandbox is relaxed to make a reviewer's life easier.

**The mutation backstop** (be honest about what it is): the candidate change must be
**committed** so it is in the tree and the tree is clean *before* any reviewer is
dispatched. **The builder makes that commit** — every implementation ticket's contract
says: *commit your work as WIP on the working branch and report the hash*. The lead
then **checks it**: the reported hash is HEAD, `git status --porcelain` is empty, and
`.foreman/` is ignored (SKILL.md, Durable state) or the check is meaningless. Never
stash the change — that removes the very thing under verification and leaves the
reviewer validating the baseline.

**Preconditions and record before dispatch:** every writer on the candidate's paths is
**proven terminal** (delegation.md, "Freezing a candidate"), and the inputs the
behavior depends on are recorded — candidate hash, dependency state, and the relevant
untracked or ignored files (`.env`, fixtures, local config, generated assets).

When the reviewer returns, `git status --porcelain` must be empty and
`git rev-parse HEAD` unchanged. That detects mutations to tracked content and refs —
it does not catch ignored files or external state, so this is **contract-plus-detection,
not a sandbox**. Any detected mutation voids the verification and is itself a finding.

**A source change after the review reopens the criteria it touches.** Evidence
gathered against the earlier revision is reused only with a **written rationale**
saying why the change cannot affect it; otherwise those checks re-run. Re-verification
after a targeted repair is **labelled as targeted** — which criteria were re-observed,
which are carried forward and on what rationale — so a partial re-check is never read
as a full one. Do not re-run every passing check merely to look thorough; re-run what
the change could have moved.

For hard isolation, run the Claude verifier in a worktree once the change is
committed; a Codex read-only reviewer (`--sandbox read-only`) or a Grok `read-only`
reviewer adds an isolated cross-family second read. Any of them may return a scoped
verdict; none of them is acceptance.

Verdicts: `PASS` / `FAIL` / `PASS_WITH_NOTES` — the first line of the reviewer's report, whichever provider runs it (any reviewer asked for a verdict may use this vocabulary; it is a reporting convention over the checks that reviewer was assigned, never acceptance authority — see "Personal final verification"). Per-criterion evidence table; everything unexamined goes under **Not checked** and counts as NOT verified. `PASS_WITH_NOTES` is legal only when every *required* criterion passed and the notes concern non-required observations — a required criterion under a note is a `FAIL`.

## Disagreement and flakiness rules

- **A reproduced deterministic failure is authoritative.** If the foreman's check fails and the verifier says PASS (or vice versa), the failing run wins until explained.
- Suspected flaky test: at most **3 reruns** to characterize it. Inconsistent results = treat as failing; report the flake itself as a finding. Never rerun-until-green.
- Verifier verdict vs deterministic evidence still unresolved after that → the change is **blocked**, not accepted. Report both artifacts to the user.

## Cross-family pairing

When both providers are available, verify across families: Codex built it → Claude verifies; Claude built it → an off-family read-only reviewer is a strong second opinion. Same-family reviewers share the builder's blind spots. This matters most at the frontier — independent pre-deployment evaluation in 2026 measured record rates of frontier models gaming checks (exploiting eval-environment bugs, extracting hidden test code). Worker self-reports from any provider's top tier are precisely what you don't trust. Off-family reads sharpen the evidence; **no reviewer verdict, from any family, is acceptance** — that is the lead's, personally (below).

**The plan challenge is the architecture review.** For a substantial plan, a
qualified reviewer from a different family attacks it before the build (SKILL.md, the
dispatch gate) — that discharges the *planned architecture review*, and nothing else.
**Candidate-specific post-build assurance is still required**, because an accepted
plan says nothing about what the diff actually did; a plan review never covers an
implementation that diverged from it. A duplicate off-family post-build read may be
omitted only with a **written risk rationale** naming what that read would have
covered and why the risk is acceptable here.

**Independence has two axes — context and model — and they are not equal.** `foreman-verifier`'s agent file says `model: inherit`, so **always dispatch it with `model: "opus"`** — inheriting would put a Fable lead's verifier on Fable, a premium seat the user never approved. Opus is frontier-class, which is the right default for catching real defects. What it does not get is model diversity. Rank the *independence of the read* honestly (this ranks review independence, not acceptance authority): cross-family (Codex reviews Claude) > same-family, different tier > **same model, fresh context** > same context. The last is worthless; the third is genuinely useful — blind context still strips the builder's reasoning, its restatement of the task, and its motivated conclusion, which is where most bad accepts come from. So keep verifying, and keep the disclosure accurate: when verifier and foreman resolve to the same model, say "blind-verified (same model, independent context)" rather than implying an independent second opinion you did not obtain. If a shared blind spot would be expensive — subtle concurrency, security boundaries, anything the whole run hinges on — that is when to reach for a Codex reviewer or ask the user for one.

## Acceptance rules for the foreman

- Trust flows from artifacts: diffs, command output, file:line citations. Narrative counts for nothing.
- A worker claiming a test passed is a claim; you or the named executor re-running it is a fact.
- Findings batch into **one** fix ticket (delegation.md), and the fix re-enters this same path. Two consecutive failed fix waves on the same findings → precedence row 5: exactly one recovery, then park to `NEEDS USER` with the evidence, while independent work continues.

### Personal final verification

**The lead verifies and accepts the assembled outcome personally.** Independent
reviewers exist to supply evidence and to challenge the work; a reviewer's `PASS`
**transfers none of the acceptance responsibility** to that reviewer, whatever its
family, tier, or seat-evidence. "The verifier passed it" is not an acceptance
rationale — no reviewer verdict alone is acceptance.

Before accepting, the lead:

1. **Inspects the actual candidate** — the diff, the files, the artifact the user will receive. Not the worker's summary, not the reviewer's summary of the worker's summary.
2. **Reconciles the original requirements to the evidence**, one at a time: the user's own words on one side, the observation that satisfies them on the other. A requirement with no observation behind it is not met.
3. **Adjudicates every consequential finding** — confirmed, dismissed with a reason, or parked as a question for the user. Disagreements between seats are settled by the lead against the artifacts, not by seat seniority.
4. **Personally checks** the critical user-facing behavior, the integration points where the pieces meet, any material gap the evidence leaves, and every disputed claim. These are the observations most likely to be wrong in a way the user would feel.
5. **Reports incomplete** — never accepted — when a required observation **cannot be made** (no executor, no environment, a check nobody could run). Say which observation, why it could not be made, and what would make it possible.

Two boundaries on this pass. **Do not re-run every passing check** to look thorough:
the personal pass targets the critical, the gapped, and the disputed — the rest stands
on the recorded evidence with its executor named. And **an agent that edited the
candidate never independently certifies its own edits**, including the lead: if you
made repairs yourself, an independent seat reviews them and you still hold acceptance
on the assembled whole (delegation.md, the revision-scoped rule).
