# Grok workers: probe, invoke, read back

xAI's Grok CLI is an optional accelerator, alongside Codex — never a requirement. When present, it adds a third family of worker seats. Everything below is sourced from direct execution on the author's machine (2026-08-17/18; the raw run artifacts are machine-local and not shipped), the launcher script (`scripts/grok-dispatch.sh`), and the cost/capability tables in [model-matrix.md](model-matrix.md) — nothing here is asserted from general knowledge of Grok.

## The probe (once per session, cache the result) — and why access used to be ambiguous

**Access is a ladder, and each rung needs its own evidence.** Earlier versions of
this skill conflated the rungs, and leads repeatedly could not tell whether Grok was
usable: one session concluded "CLI unauthenticated" from a sandboxed shell while the
user was signed in; another saw "logged in" while every dispatch was failing with an
exhausted balance. The rungs, and what proves each:

| Rung | Question | Evidence (cost) | Who checks it |
|---|---|---|---|
| 1. Installed | Does the binary run? | `grok --version` (free) | `scripts/probe.sh` |
| 2. Signed in | Does the CLI see a grok.com session **from this shell**? | `grok models` prints `You are logged in with …` (free) | `scripts/probe.sh` → `grok access: SIGNED-IN` |
| 3. Usable | Will a dispatch actually run (balance, entitlement, network)? | one billable ping through the launcher (~$0.007) | `scripts/access-check.sh grok` → `ACCESS grok: LIVE` |

Three traps, each observed on the author's machine and each now handled by the scripts:

- **`grok models` exits 0 even when signed out** and then prints a *built-in fallback*
  model list (`grok-4.6`, `grok-4.5` on 1.0.41), not the account's. Exit status proves
  nothing; only the `You are logged in` / `You are not authenticated` line does, and a
  model list is the account's only when the first line says logged in. (OBSERVED
  2026-09-23 with an empty `GROK_HOME`.)
- **A sandboxed or HOME-redirected shell looks signed out.** If `~/.grok/auth.json`
  exists but the CLI says `not authenticated`, the probe reports **`ENV-MISMATCH`**,
  not absence: re-run the probe outside the sandbox (or with the real `HOME` /
  `GROK_HOME`) before concluding anything. Never report "Grok unavailable" from this
  state alone.
- **Signed in is not usable.** An exhausted Grok Build balance arrives only on a
  billable call, as `API error (status 402 Payment Required): Grok Build usage balance
  exhausted` (OBSERVED 2026-09-21), while `grok models` still says logged in. The
  launcher now prints `GROK ACCESS: BALANCE_EXHAUSTED` for it.

So the rule is: **run `scripts/probe.sh` (rungs 1–2, free), then `scripts/access-check.sh
grok` (rung 3) before the first real dispatch of a session**, and ledger the verdict
line verbatim. `access-check.sh` refuses the billable ping unless Grok is pre-approved
or you pass `--consented` after the user agreed. One verdict per session is enough —
until a dispatch reports otherwise (failure mapping below).

- Honor `GROK_BIN` if the environment sets it — the launcher, probe, and access check
  resolve the binary the same way: `$GROK_BIN` if set, then `grok` on PATH, then
  `$GROK_HOME/bin/grok` (default `~/.grok/bin/grok`).
- Verified build: Grok CLI 1.0.41 (2026-09-22), macOS arm64, OAuth/OIDC session auth
  against grok.com — a subscription, not an API key (see Billing). The CLI updates
  itself often; re-read `grok --version` and the model list rather than trusting this line.
- No GNU `timeout` on stock macOS or Windows: the scripts use their own bounded wait
  (45 s for `grok models`, override with `FOREMAN_PROBE_TIMEOUT`). A slow response is
  latency, not absence.

## Billing (subscription session — ordinary budget discipline applies)

The account used to verify this reference authenticates via an OAuth/OIDC session against grok.com, not an API key — a subscription, the same shape as a ChatGPT-subscription Codex login, not metered per call against a card. **Opt-in pre-approval (user-set, per machine, added 2026-09-04):** if `scripts/probe.sh` reports `grok billing: PRE-APPROVED (user config)` (`~/.foreman/grok-preapproved` exists, or `FOREMAN_GROK_PREAPPROVED=1`), skip the consent ask, journal `Grok: pre-approved by user config`, dispatch Grok (the newest base model for implementation, `grok-4.6` for output-light review — see tiers below) with **effort chosen per dispatch by the lead** (with no performance evidence yet, the prior is the highest level the model supports — pre-approval removes the consent ask, it does not fix a level), and fan out up to the parallel ceiling the flag file names (default 15 — the user ran 15 concurrent Grok 4.6 workers comfortably on one test Mac; a reported successful default, not a measured maximum — see Quota notes). Without the flag, treat Grok spend under the ordinary rule: journal it, and step a Grok dispatch down or stop under budget pressure exactly as for any other seat.

What "spend" means concretely: every `--output-format json` call returns a `total_cost_usd` field in the envelope, which the launcher parses and prints. Real dispatches observed this session: a trivial echo ~$0.010; a one-file schema review ~$0.015; writing a module plus tests and running them ~$0.021 (20s, 4 turns); resuming a session to add validation and re-run tests ~$0.014 (26s, 4 turns). Treat published list prices (model-matrix.md Table 1) as an **upper bound**, not the bill — this account's envelopes have reported pool rates of 0.17x list (2026-08) and ~0.34x list (2026-09-23) — the rate moves, so never hardcode it (model-matrix.md). Where the envelope reports a real cost, that number wins over any table.

Functional check before the first real dispatch of a session: `scripts/access-check.sh grok` — it runs the free sign-in check, then one `Reply with exactly: ok` ticket through the launcher on the newest base model, and prints `ACCESS grok: LIVE — …` (or the exact failure state). Never a raw `grok` call.

## Discovering the account's tiers — and picking the newest one wisely

`grok models` (when it says logged in) is authoritative for *which* models this
account sees; the CLI's `~/.grok/models_cache.json` is authoritative for *which
effort levels each model accepts*, and both launchers read it. `scripts/probe.sh`
prints the live list and the **newest base model** (the highest `grok-X.Y` with no
suffix). As of 2026-09-23 this account sees:

| Model | Efforts | Context | Price (list) | Role |
|---|---|---|---|---|
| `grok-4.7` (CLI default) | low, medium, high (vendor default, "Recommended"), xhigh | 500K | $2 / $6 | **default implementation seat** |
| `grok-4.7-build-fast` | same | 500K | **2x** ($4 / $12) | wall-clock emergencies only |
| `grok-4.6` | low, medium, high, xhigh | 500K | $2 / $6 | output-light reviewer; fallback where 4.7 regresses |
| `grok-4.5` | low, medium, high (**no xhigh**) | 500K | $2 / $6 | last-resort fallback |

**4.7 vs 4.6 — the evidence, not the hype.** Artificial Analysis (PRIMARY,
2026-09-21): Coding Agent Index 56 vs 47, Terminal-Bench 4.0 33% vs 18%, DeepSWE 73%
vs 65%, hallucination 29% vs 34% — but Intelligence Index only 46 vs 44, and 4.7 at
`xhigh` emits **~81K output tokens per task vs ~38K** for 4.6. The "mixed reviews" are
mostly about that token burn (and tighter guardrails in chat use), not a measured
coding regression; none was found. On this account a one-word ping cost 222 output
tokens on 4.7 vs 12 on 4.6 at `low` (one sample — a hint, not a measurement). So:

The routing card decides which of these a job gets (everyday coding is a close call between Grok 4.7, GPT-6 Sol and Sonnet 5; review rows default to Grok 4.6). The evidence behind those rows:

- **Implementation (agentic coding, anything that runs tools or tests): `grok-4.7`.**
- **Adversarial review / analysis (output-light, reasoning over text): `grok-4.6`** is
  the value default; 4.7 when the review must execute code.
- **When a newer Grok appears** (probe prints a new newest-base-model), do not assume
  it is better for every task shape: take the first ticket of the next fan-out through
  both the new and the previous model (the "prove an unproven repeated pattern on a
  representative early artifact" rule, SKILL.md) and let the performance record decide.
  Until then the newest model is the implementation default and the previous one the
  review default.
- **Regression fallback is per task shape, not global.** If the record shows 4.7
  failing where 4.6 succeeded on a shape, route that shape to 4.6 and journal why.

Effort is **per model** and read from the cache — the launcher refuses a level the
model does not list, before spending. `grok-4.5` has no `xhigh` (a hard error, exit 1,
not a silent downgrade — verified 2026-08-17).

## Transport: visible subagent wrapper first, direct launcher call as fallback

Grok gets the same wrapper-first transport pattern v0.3 gave Codex, via the bundled `scripts/grok-dispatch.sh` launcher and the `foreman-grok-wrapper` agent.

**When the Agent tool is available, dispatch Grok through the wrapper subagent** — the bundled `foreman-grok-wrapper` agent where the harness registers plugin agents, otherwise a generic FAST subagent carrying the wrapper contract below verbatim — a FAST-seat Claude subagent whose entire job is to run the fixed-argv launcher once and relay the result. Stated honestly, this buys the same three things the Codex wrapper buys: user visibility (a named crew member in the harness UI, not an invisible shell-out), notification-driven collection instead of hand-rolled polling, and a foreman that stays free while the worker runs. Direct launcher invocation from the foreman's own Bash remains correct in Agent-tool-less modes and for sub-minute advisory calls where wrapper overhead exceeds the benefit.

**The launcher's real argument list** (read from `scripts/grok-dispatch.sh` — never hand-compose a `grok` call):

```
grok-dispatch.sh <ticket-file> <model> <effort> <read-only|workspace> <artifact-json> [workdir] [resume-session-id] [schema-file]
```

**Eight positional slots: five required** (ticket, model, effort, sandbox, artifact path) **and three optional** (`workdir`, defaulting to `.`; a resume session id, defaulting to none — a fresh session; a schema file, defaulting to none). Optional slots are positional — to pass a schema without resuming, pass an empty string for the resume slot. `FOREMAN_SKILL_DIR` is the directory containing the SKILL.md you are reading — `~/.claude/skills/fable-foreman` on a standard install, `<checkout>/skills/fable-foreman` in the marketplace repo; resolve it once, and pass every argument as an absolute path. Note the sandbox spelling: **`workspace`, not Codex's `workspace-write`** — don't cross-copy the two launchers' argv.

Before spending anything, the launcher validates and refuses (`BLOCKED` on stderr, nonzero exit) on:

- `sandbox` not exactly `read-only` or `workspace` — **`off` (Grok's own CLI default) and `strict` are both refused.** Grok ships five built-in profiles (`off`, `workspace`, `read-only`, `strict`, `devbox` — 18-sandbox.md), but this launcher wires through only two of them and never dispatches a worker with no OS-enforced boundary at all.
- `effort` not one of `low|medium|high|xhigh`.
- `xhigh` requested against a model id containing `4.5` — caught here, before the call, because it's a known hard error on this build.
- a malformed model id, or a resume id containing anything outside `[A-Za-z0-9-]`.
- a missing ticket file or workdir.
- **`read-only` sandbox sited under `/tmp`, `/private/tmp`, or `/var/tmp`** — documented behaviour (18-sandbox.md:44): `read-only` permits writes to temp dirs and `~/.grok`, and it was reproduced here (a file was created in a `/private/tmp` workdir). The launcher refuses this combination outright rather than let a reviewer believe it's isolated when it isn't.
- an artifact path that doesn't end in `.json`, is a symlink, aliases the ticket file, or otherwise isn't a plain regular file.

What the launcher pins into the actual `grok` invocation once validation passes:

- `GROK_CLAUDE_SKILLS_ENABLED=false`, `GROK_CLAUDE_RULES_ENABLED=false`, `GROK_CLAUDE_AGENTS_ENABLED=false`, `GROK_CLAUDE_MCPS_ENABLED=false`, `GROK_CLAUDE_HOOKS_ENABLED=false` in the child's environment — **Claude-config discovery is switched off at the source** (05-configuration.md, "Harness compatibility"; verified 2026-08-18: MCP servers no longer load, slash commands 209→103, ~9K fewer input tokens per call). A generic top-level `CLAUDE.md` in the *working directory* stays recognized — that is project context and acceptable.
- `--disallowed-tools "Agent"` and `--no-subagents` (both pinned; both verified) and `--deny "MCPTool"` — **this machine-enforces "workers never spawn workers" at the tool layer, inside the dispatched Grok process itself.** This is strictly stronger than the Codex path: Codex's launcher has no equivalent tool-denial flag, so "workers never spawn workers" there is contractual only (codex-workers.md). For Grok, even a badly-prompted worker cannot invoke a subagent-spawning tool or reach an MCP server — the CLI itself refuses.
- `--deny "Write($VAULT_GLOB)"` and `--deny "Edit($VAULT_GLOB)"` (glob overridable via `FOREMAN_VAULT_GLOB`), plus a `--rules` string forbidding session logs, notes-vault writes, and archiving/topic-linking, and confining edits to the ticket's working directory. This exists because Grok auto-discovers and loads the user's whole Claude Code world by default — `~/.claude/CLAUDE.md`, `~/.claude/skills/` (204 skills loaded in testing), `.claude/agents/`, installed plugins, and MCP server config from `~/.claude.json`/`.mcp.json` — and an unconstrained dispatch was **observed** obeying the user's global auto-archive rule and writing session logs into their notes vault, with vault hooks firing. The env cells above remove that at the source; `--rules` and the deny globs remain as defense in depth (`--rules` was verified to suppress it on its own).
- `--permission-mode bypassPermissions --output-format json --sandbox "$SANDBOX" -m "$MODEL" --reasoning-effort "$EFFORT" --cwd "$WORKDIR"`, plus `--resume "$RESUME"` when a resume id was given.
- For `read-only` dispatches specifically, an additional inner allowlist — `--tools read_file,grep,list_dir` — so an advisory reviewer gets no shell and no edit tools at all: the sandbox is the outer boundary, this is the inner one.
- The child's PID is written to `<artifact>.pid` **before** the launcher waits on it — the "prove it stopped" handle for the LOST protocol (delegation.md). If the PID file can't be written, the launcher kills the just-spawned child and refuses rather than let paid work run untracked. An INT/TERM to the launcher forwards to the child and reaps it — no orphaned Grok process left editing after the wrapper dies.

**The wrapper contract** (put it in the wrapper's prompt verbatim — it also lives in `agents/foreman-grok-wrapper.md`):

1. Run `scripts/grok-dispatch.sh` exactly once, with exactly the arguments your ticket gives you, and the shell timeout your ticket names. Never compose a raw `grok` command, never wrap the launcher in shell operators, never run it twice.
2. Report in exactly this shape: Line 1 `DONE` if the launcher exited zero, else `BLOCKED` followed by the tail of `<artifact>.stderr`. Then the launcher's stdout (the transport envelope) verbatim. Then Grok's final message, produced by running exactly this read-only command and relaying its stdout verbatim: `python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));so=d.get("structuredOutput");print(json.dumps(so,indent=1) if so is not None else d.get("text",""))' <artifact-json>` — never retype, summarize, or reconstruct it; if the command fails, relay its error and say `RELAY FAILED`.
3. Spawn nothing; write nothing except what the launcher itself writes.
4. Your relay is transport metadata. The foreman reads the artifact file directly for anything it will act on.

**Vocabulary discipline:** identical to Codex's rule — the envelope is transport metadata, not a report vocabulary. The worker status or reviewer finding is read from the first line of the *relayed* Grok message, exactly as if Grok had reported directly.

**Failure mapping (deterministic — no judgment calls at the transport layer):**

| Observation | Treatment |
|---|---|
| Launcher exit nonzero (any pre-flight `BLOCKED:` refusal above, or the child itself exiting nonzero) | Worker `BLOCKED`; envelope + `<artifact>.stderr` are the evidence |
| Exit 0, artifact JSON top-level `{"type":"error", ...}` (e.g. an unknown model id Grok itself refused) | `BLOCKED`; the envelope prints `GROK ERROR: <message>` verbatim — a genuine provider-side refusal, not a transport glitch |
| Exit 0, no parseable status line in the relayed final message — on a *reviewer* ticket a verdict first line (`PASS` / `FAIL` / `PASS_WITH_NOTES`) parses as well as a worker status | `BLOCKED` (malformed report); artifact path in ledger |
| Exit 0, empty final message or unparsable JSON artifact | `BLOCKED`; artifact retained for diagnosis |
| Wrapper itself silent past its deadline | Wrapper task is `LOST` — apply the LOST protocol to the *wrapper* (delegation.md); check `<artifact>.pid`, kill the child if still live, and only then reconcile the workspace |
| Envelope prints `GROK ACCESS: BALANCE_EXHAUSTED` (HTTP 402) | The Grok pool is down for this run: stop dispatching Grok, collect every live Grok worker (hard rail 5), re-route the remainder per the degradation rule, journal it, and tell the user once — never retry into a 402 |
| Envelope prints `GROK ACCESS: AUTH_FAILED` / `RATE_LIMITED` / `NETWORK` | `BLOCKED` with that cause; AUTH → the user runs `grok login`; RATE_LIMITED → counts toward the precedence table, back off; NETWORK → check whether this shell is sandboxed/offline before concluding Grok is down |
| Envelope reports `seat: billed-tier evidence …` | Normal and expected — record it; it is **not** `seat: verified` (see Reading back) |
| Envelope reports `CONTEXT ALERT` (average prompt per model call above 200000) | Do not send Grok another ticket carrying the *same context set or a superset* (same working files/paths plus the same or a longer resumed session) for the rest of this run — a fresh, smaller ticket may still use Grok; when unsure, don't. Re-route and journal it (model-matrix.md Table 3) |
| Relayed message does not match the artifact | Wrapper contract breach; use the artifact, ledger `wrapper relay: unreliable`, and do not reuse that wrapper seat this run |

**Enforcement scope, stated honestly:** the launcher makes compliance auditable — the transcript shows either one launcher call or a contract breach — and pins the argv so a wrapper has no legitimate reason to touch `grok` directly. It does **not** machine-prevent the wrapper's own general shell from calling `grok` raw; that remains a harness-layer concern (tool-policy hooks), exactly as with Codex. Where Grok genuinely goes further than Codex is *inside* the dispatched process: `--disallowed-tools Agent` / `--deny MCPTool` stop the worker itself from spawning subagents or reaching MCP, machine-enforced rather than merely written into its rules.

## Invocation pattern

Non-interactive, one ticket per invocation, via the wrapper (above) or directly:

`FOREMAN_SKILL_DIR` is the directory containing the SKILL.md you are reading —
`~/.claude/skills/fable-foreman` on a standard install, `<checkout>/skills/fable-foreman`
in the marketplace repo; resolve it once, and pass every argument as an absolute path.

```bash
# Advisory / review work — read-only sandbox, sited outside /tmp:
"$FOREMAN_SKILL_DIR"/scripts/grok-dispatch.sh \
  <abs-repo>/.foreman/scratch/ticket-N.md grok-4.6 medium read-only \
  <abs-repo>/.foreman/scratch/artifact-N.json <abs-repo>

# Implementation work — writable workspace:
"$FOREMAN_SKILL_DIR"/scripts/grok-dispatch.sh \
  <abs-repo>/.foreman/scratch/ticket-N.md grok-4.7 high workspace \
  <abs-repo>/.foreman/scratch/artifact-N.json <abs-repo>

# Continuing a prior dispatch's session (verified: the worker recalled code
# from the earlier turn without it being re-sent):
"$FOREMAN_SKILL_DIR"/scripts/grok-dispatch.sh \
  <abs-repo>/.foreman/scratch/ticket-N-followup.md grok-4.7 high workspace \
  <abs-repo>/.foreman/scratch/artifact-N2.json <abs-repo> <sessionId-from-artifact-N>

# Schema-locked review — note the EMPTY 7th (resume) slot before the schema:
"$FOREMAN_SKILL_DIR"/scripts/grok-dispatch.sh \
  <abs-repo>/ticket.md grok-4.6 medium read-only \
  <abs-repo>/out.json <abs-repo> "" <abs-repo>/schema.json
```

- The ticket goes in via `--prompt-file` (a real file path, baked in by the launcher) — unlike Codex's stdin pipe (`- <`), don't try to pipe a ticket to Grok directly.
- **Effort is chosen per dispatch by the lead**, at or below what the model supports (the launcher validates the value and refuses anything else). With no performance evidence for the task shape yet, the no-evidence prior is the highest level the model supports; model-matrix.md Table 4 is the *cost* prior, and the performance record overrides it. The examples below show a level because the launcher's argv requires one, not because that level is prescribed.
- Sandbox follows the *task*, as for Codex (with the macOS caveat below): `read-only` for advisory, `workspace` for anything that edits files — and never a read-only reviewer sited under `/tmp` (the launcher refuses it anyway).
- **Isolation, honestly:** on macOS neither profile blocks child-process network (documented no-op — 18-sandbox.md:34) and both read the whole filesystem (:40, :44); only writes are confined. Grok's `workspace` is therefore *weaker* than Codex's `workspace-write` (which blocks network on macOS). Reserve `workspace` for repos you would let an autonomous agent read your home directory from; review work stays `read-only` with the launcher's no-shell tool allowlist.
- `--json-schema` yields a validated `structuredOutput` object in place of parsed prose — verified working. **Pass it through the launcher's 8th slot (`schema-file`), never by hand-composing a `grok` command**: the launcher reads the schema from a file, validates it is real JSON, and keeps the dispatch inside the pinned argv with its `Agent`/`MCPTool` denials intact. A schema-locked verdict is the recommended shape for review tickets, so it must not cost you the machine-enforced rails.

## Reading back

**Seat provenance first — this is the one nuance that must never get flattened.** The JSON envelope's `modelUsage` key (e.g. `grok-4.6-build`) names what was *billed* for the turn, and it tracks the actual request rather than echoing a constant — verified by requesting each model in turn and observing the key change. That is real evidence, stronger than a self-report. But it comes from the usage/billing layer, not from post-resolution model-identity metadata the way verification.md's Layer 0 defines `SERVED` evidence. **Log it exactly as the launcher itself does:** `seat: billed-tier evidence — modelUsage <key> (NOT served-tier; not 'verified')`. Never write `seat: verified` for a Grok dispatch on this evidence. Seat tier is *disclosed with the finding*, not a bar on the seat: a Grok reviewer's verdict supplies evidence, never acceptance — **the lead accepts**, and a reviewer verdict alone is never acceptance proof (model-matrix.md Table 5; verification.md). Rank it closer to verification.md's `REQUESTED` tier than to `SERVED`, even though it is materially better than a bare `-m` flag with no accounting behind it.

Otherwise, Grok workers follow the same contract as Claude and Codex workers: status as the first line of the final message (`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED` — put this in every execution ticket's OUTPUT FORMAT), evidence not narrative, artifacts to `.foreman/scratch/` with paths. A Grok read-only reviewer asked for a review verdict may lead with the verdict vocabulary (`PASS` / `FAIL` / `PASS_WITH_NOTES`) as a **reporting convention**, exactly as a Codex read-only reviewer may (verification.md) — the verdict is scoped evidence, and acceptance stays with the lead. Its citations are still confirmed against the named file or line before anyone acts on them (model-matrix.md Table 4b).

**The relay is a claim.** A haiku transport wrapper was observed (2026-08-18) relaying an invented report while the on-disk artifact held the real, schema-valid one. For any class-sensitive read — verdicts, findings entering a fix wave, statuses that decide routing — the foreman reads the artifact file directly; the relay serves notification and status only.

**Telemetry limits — what the envelope's numbers do and do not evidence.** Record what the envelope reports, and record a raw value that is missing as `unavailable` — never inferred from a table, never back-filled from list price, and never carried forward from another dispatch. `total_cost_usd` is the provider's own accounting for this call, not a bill you have seen; label it by what it evidences (model-matrix.md, "what the dollars mean"). And the launcher's `CONTEXT WARN` / `CONTEXT ALERT` is derived from the **average** prompt size per model call (uncached + cache-read + cache-creation, divided by `num_turns`): it is a **routing warning about that average**, not proof that any individual call crossed the cliff or was repriced. Treat it as the reactive routing rule it is (Table 3), and do not report it to the user as per-call billing evidence. The launcher itself is unchanged; this is how to read what it already prints.

Multi-turn continuation is real **within one sandbox profile**: `--resume <sessionId>` continues a prior session across a **separate process invocation**, verified — a worker recalled code it had written in an earlier dispatch without being re-sent it. What it does not do is change the session's sandbox: a `workspace` session resumes on `workspace` (the examples above), a `read-only` session resumes on `read-only`, and asking for the other profile is refused before any spend (Role transition, below). Useful for iterative fix tickets against the same Grok session; each invocation is still one ticket under delegation.md's ticket contract.

**Role transition — reviewer to fixer.** A reviewer never edits the candidate it is judging within the same assignment. Changing its role is an **explicit journaled writable dispatch**: the earlier verdict does not cover the edits it then makes, affected checks are re-run, and a **different fresh context** assesses the repaired revision (delegation.md, verification.md). Mechanically on Grok this is settled by observation, not by policy preference. **OBSERVED 2026-09-07** on grok CLI 1.0.13 through the unchanged launcher: resuming a session that was created under `read-only` with sandbox `workspace` is **refused before any spend** — `error: cannot resume this session under sandbox profile 'workspace' — it was created with 'read-only'. Omit --sandbox to resume with 'read-only', or start a new session to use 'workspace'.` (step 1 artifact `a1.json`: the `read-only` reviewer read the file, reported it had no write tool, and created nothing; step 2 stderr `a2.json.stderr`, both under the fixture's `.foreman/scratch/`). So a Grok reviewer-to-fixer transition is a **fresh `workspace` dispatch** carrying the finding, the candidate hash, and the criteria verbatim — the resume slot cannot cross sandbox profiles, and there is nothing conditional left to wait on. And because the launcher gives a `read-only` reviewer no shell at all (`--tools read_file,grep,list_dir`), every deterministic check assigned to such a reviewer needs a **named executor** — the lead or a designated capable seat runs it and records the result; a check nobody ran stays UNVERIFIED, and the reviewer's independent reasoning over the candidate and the check artifacts is what it actually contributes.

**Work-quality spot-check (one data point, not a pattern):** on this account, a Grok worker's self-reported test-pass claim (4/4, then 5/5 after a follow-up ticket) was independently re-run by the foreman and genuinely matched, across two dispatches. Treat this the same as any worker self-report per verification.md — re-run it yourself; one clean spot-check is not a standing exemption.

## Quota notes

- Grok draws on its own account pool (the grok.com subscription), independent of both the Claude pool the foreman itself runs on and Codex's ChatGPT pool (model-matrix.md Table 6) — a genuine endurance asymmetry worth using for bulk work when the Claude pool is under pressure.
- The concrete, verified boundary to route around is the **200K-token repricing cliff**: above 200K input, the *entire* request reprices at 2x, so route away from the surcharge. Which seat is then cheapest is not established — Table 3's cross-provider comparison is list-price math and this account's measured Grok billing ran well under list. Grok's 500K ceiling, by contrast, is a hard limit. The launcher measures this reactively — deriving the **average prompt size per model call** from the envelope (uncached input + cache reads + cache creation, divided by `num_turns`) and printing `CONTEXT WARN` / `CONTEXT ALERT` off that — because a foreman cannot reliably estimate request size ahead of a dispatch (Grok prepends its own system prompt and toolset: ~19K tokens on this build with discovery off, ~28K with the user's Claude config discovered). **Reactive rule:** after a `CONTEXT ALERT`, do not send Grok another ticket that carries the *same context set or a superset* (same working files/paths plus the same or a longer resumed session) — that is a fact the foreman knows from what it put in the ticket. A fresh ticket with a smaller context set may still use Grok; when unsure, don't. A `CONTEXT WARN` means shrink the next ticket's context or split it.
- Rate limits are per-account. 15 concurrent Grok 4.6 workers ran comfortably on one test Mac (2026-09-04). That is a **reported successful concurrency default, not a measured maximum** — nothing established where the real ceiling sits, in either direction, and a successful run at 15 did not test the next step up. Treat 15 as the default fan-out under pre-approval, and raise or lower it on observation. Beyond that, no verified data exists for rate-limit windows or message-allowance mechanics — don't promise numbers that weren't measured. A rate-limit error mid-run is a real failure toward the precedence table (delegation.md) — don't burn retries in place; fall back to the Claude seat of the same class for the remainder and journal it.
