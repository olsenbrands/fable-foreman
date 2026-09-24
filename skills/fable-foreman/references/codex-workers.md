# Codex workers: probe, invoke, read back

OpenAI's Codex CLI is an optional accelerator — never a requirement. When present, it adds a second family of worker seats.

## The probe (once per session, cache the result)

```bash
command -v codex                                   # 1. installed?
codex login status                                 # 2. authenticated? which billing mode?
test -s "${CODEX_HOME:-$HOME/.codex}/auth.json"    # 2b. fallback if the subcommand errors
```

- Step 2 is the documented status command; its output also tells you **how the account is billed** (ChatGPT subscription vs API key). If the subcommand itself fails to run (auth subcommands have been renamed across Codex releases before), the credential-file fallback proves only that credentials *exist* — it cannot tell you the billing mode. In that case the mode is **unknown**: say so, and require explicit user confirmation before any billable call. (Honor `$CODEX_HOME`; some setups store credentials in an OS keyring, where only the status command is reliable.)
- **Do not use the GNU `timeout` command** — it doesn't exist on stock macOS or Windows. Use your shell tool's own timeout parameter, set generously (60s+): a slow response is latency, not absence.

## Consent and billing (before any model call)

The probe above is metadata-only and free. An actual Codex invocation **spends the user's OpenAI account** — subscription quota, or real metered dollars on an API key. Before the first dispatch:

1. Tell the user Codex is available and which billing mode `login status` reported.
2. Confirm they want Codex in the rotation — unless they already asked for Codex this session, which is consent.
3. Record the consent (and mode) in the ledger.

Only after consent, run the functional check — one tiny call, cheapest tier you can name confidently or the account default: `codex exec "Reply with exactly: ok"`. If it fails while credentials exist, they're likely expired: tell the user to run `codex login`; never initiate an interactive auth flow yourself.

**Opt-in pre-approval.** If `scripts/probe.sh` printed `codex billing: PRE-APPROVED (user config)` (the user created `~/.foreman/codex-preapproved` or exported `FOREMAN_CODEX_PREAPPROVED=1`), steps 1–2 are skipped: note the billing mode and `pre-approved by user config` in the ledger and dispatch — the user has asked for Codex to be used ambitiously on this machine. The flag is machine-local and never part of this repository.

## Discovering the account's tiers

Documentation is not entitlement, and **model IDs differ by auth mode** — this repo's own first review dispatch bounced because an API-doc model ID (`gpt-5.6`) wasn't valid for a ChatGPT-account login (which wanted `gpt-5.6-sol`). Procedure:

1. Read the catalog `scripts/probe.sh` prints from `${CODEX_HOME:-$HOME/.codex}/models_cache.json` — the Codex CLI's own list of the models this login sees, each with the provider's positioning text and its supported effort levels. It is free, local, and it is what the launcher validates effort against. (Check its `fetched_at`; the CLI refreshes it, and a stale cache can lag a release.)
2. Read `${CODEX_HOME:-$HOME/.codex}/config.toml` — the user's configured `model` and `model_reasoning_effort` are their expressed preference; identify what that model *is* before classifying it. (On the author's machine the preference is the frontier tier, `gpt-6-astra` at `medium` — a user who pinned the flagship did not thereby make it your WORKHORSE, and a config default is **not** the double approval a premium seat needs; the launcher always passes `-m`, so the config default never silently runs.)
3. If no catalog is readable, ask the user or check `codex` interactive `/model` output.
4. Before relying on any tier in a long run, verify it with one tiny call — `scripts/access-check.sh codex` does this on the cheapest listed tier (`--model <id>` for another). A tier that fails entitlement goes in the ledger as unavailable (`CODEX ACCESS: MODEL_NOT_ENTITLED`).

Map verified tiers to FRONTIER / WORKHORSE / FAST by the provider's published positioning for them (routing.md), and record the mapping in the ledger so it's auditable.

**Two effort facts for GPT-6 (2026-09-23):** there is no `minimal` level, and `ultra` (Astra, Sol) means "maximum reasoning with automatic task delegation" — the worker splits its task across sub-agents it spawns itself. That is a worker spawning workers, so `scripts/codex-dispatch.sh` refuses `ultra` outright (hard rail 1); `max` is the deepest non-delegating level and is allowed. The Codex "Fast" service tier (priority processing) doubles usage and is never set by the launcher.

**Effort is chosen per dispatch by the lead**, from the levels the verified model actually supports — the user's configured `model_reasoning_effort` is their expressed preference and the fallback when nothing else is known, not a ceiling on the lead's judgment. Never send a level the account's model does not support; verify it the same way you verify a tier, with one tiny call. model-matrix.md Table 4 is the *cost* prior, and the performance record overrides it.

## Transport (v0.3): visible subagents first, direct exec as fallback

Before v0.3 the skill shelled out to `codex exec` directly from the foreman's own Bash. That works, but the Codex worker is invisible to the user (no presence in the harness UI), the foreman must hand-roll background polling and LOST detection, and long builds tie ledger hygiene to manual job bookkeeping. v0.3 changes the default:

**When the Agent tool is available, dispatch Codex through a transport wrapper subagent** — a FAST-seat Claude subagent whose entire job is to run the fixed-argv launcher once and relay the result. Use the bundled `foreman-codex-wrapper` agent where the harness registers plugin agents (its tool list machine-excludes edit tools and agent spawning); otherwise a generic FAST subagent carrying the contract below. What this buys, stated honestly:

- **User visibility:** the *wrapper* appears in the harness UI as a live subagent — the user sees a named crew member carrying the Codex job instead of an invisible shell-out. The Codex process itself sits behind it; the wrapper's report must therefore expose the handles (artifact paths, exit code) that make the inner process inspectable after the fact.
- **Notifications over polling:** the harness notifies the foreman on wrapper completion; no polling loops, no foreground blocking, and LOST detection rides the harness's own task tracking.
- **Foreman stays free:** long Codex builds no longer occupy the foreman's attention between dispatch and collection.

Cost: one FAST wrapper's tokens per dispatch (small; the wrapper does no thinking). Direct launcher invocation from the foreman's own Bash remains correct in CLI-only mode (no Agent tool), for sub-minute advisory calls, and **for small FAST tickets** (a Luna job expected to finish in a few minutes): run the launcher from the lead's own shell (in the background only if the harness will notify you when it exits; otherwise in the foreground with a generous timeout), record its pid file in the dispatch register, and collect it like any worker — never end your turn while it is still running. That removes the wrapper step entirely, so "wrapper overhead" is never a reason to skip the card's Luna default.

**The wrapper contract (put it in the wrapper's prompt verbatim):**

1. Run `scripts/codex-dispatch.sh` (in this skill's directory) exactly once, with exactly the six arguments given in your ticket — ticket file, model, effort, sandbox, artifact path, workdir. There is no session-resume slot in this launcher (unlike Grok's), so every dispatch is a fresh one; the effort argument is whatever the lead chose for this dispatch, at a level the model supports. Never compose a raw `codex` command, never add shell operators around the launcher, never run it twice, never edit any file yourself. Set your shell tool's timeout to the deadline named in the ticket.
2. Relay two things, clearly separated: first the launcher's **transport envelope** (its stdout: exit code, duration, seat evidence — verbatim), then the Codex worker's final message, produced by running **exactly** this read-only command against the JSONL artifact and relaying its stdout verbatim — it prints the `text` of the last agent-message `item.completed` event in the stream:

   ```bash
   python3 -c 'import json,sys;E=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8",errors="replace") if l.strip().startswith("{")];M=[e["item"].get("text") for e in E if isinstance(e,dict) and e.get("type")=="item.completed" and isinstance(e.get("item"),dict) and "agent" in str(e["item"].get("item_type") or e["item"].get("type") or "") and e["item"].get("text")];print(M[-1] if M else "RELAY FAILED: no agent-message item.completed event in artifact")' <artifact-jsonl>
   ```

   Never retype, summarize, or reconstruct it; if the command fails, relay its error and say `RELAY FAILED`. You are transport, not a reviewer.
3. Spawn nothing; write nothing except the artifact files the launcher itself names.
4. Your relay is transport metadata. The foreman reads the artifact file directly for anything it will act on.

**Vocabulary discipline:** the transport envelope is *transport metadata*, not a report vocabulary. The worker status (`DONE`/`BLOCKED`/…) or verifier verdict (`PASS`/`FAIL`/…) is read from the first line of the **relayed Codex message**, exactly as if Codex had reported directly; the foreman enters `REPORTED(status)` from that line alone. An envelope without a parseable status line in the relayed message maps to `BLOCKED` (see failure mapping). Three vocabularies remain three (delegation.md).

**Failure mapping (deterministic — no judgment calls at the transport layer):**

| Observation | Treatment |
|---|---|
| Launcher exit nonzero | Worker `BLOCKED`; envelope + stderr artifact are the evidence |
| Envelope prints `CODEX ACCESS: RATE_LIMITED/QUOTA` | The Codex pool is exhausted or throttled for this window: stop dispatching Codex, re-route the remainder per the degradation rule, journal it — never retry in place |
| Envelope prints `CODEX ACCESS: AUTH_FAILED` / `MODEL_NOT_ENTITLED` | `BLOCKED` with that cause; AUTH → the user runs `codex login`; NOT_ENTITLED → mark the tier unavailable and re-map classes from the catalog |
| Exit 0, no parseable status line in relayed message | `BLOCKED` (malformed report); artifact path in ledger |
| Exit 0, empty final message / malformed JSONL | `BLOCKED`; artifact retained for diagnosis |
| Wrapper itself silent past its deadline | Wrapper task is `LOST` — apply the LOST protocol (delegation.md) to the *wrapper*; then reconcile the workspace before any retry, because the inner Codex process may have kept editing after the wrapper died |
| Envelope reports `seat: unverified` | Normal under current Codex builds — record it; Layer 0 consequences apply (verification.md) |
| Relayed message does not match the artifact | Wrapper contract breach; use the artifact, ledger `wrapper relay: unreliable`, and do not reuse that wrapper seat this run |

The wrapper is transport, not delegation — this is the sanctioned carve-out to "workers never spawn workers" (SKILL.md hard rail 1), and it is tight *because the launcher pins the argv*: the wrapper has no legitimate reason to touch `codex` directly, and a wrapper that does has broken contract.

**Enforcement scope, stated honestly:** the launcher makes compliance *deterministically auditable* (the transcript shows either one launcher call or a contract breach — there is no ambiguous middle), and the launcher itself validates everything it is given. What it does not do is machine-prevent a wrapper from invoking `codex` raw — the wrapper holds a general shell, and prompt text cannot revoke it. Machine enforcement belongs to the harness layer (tool-policy hooks or permission rules restricting `codex` outside the launcher path) and is a recommended hardening for standing setups, not something this skill can impose from inside a prompt. Treat a transcript showing a raw `codex` call from a wrapper exactly like a worker editing outside its WRITE SET: a contract breach that voids the dispatch.

**Orphan control:** the launcher records the Codex child PID to `<artifact>.pid` before waiting, and forwards INT/TERM to the child. On a wrapper-LOST event, that PID file is the "prove it stopped" handle (delegation.md): check it, kill if live, and only then reconcile the workspace.

**Native-transport option (documented, not default):** a claudemix-style loopback splitter can make GPT models *literally* native subagents (model pinned in agent frontmatter, no CLI at all). That requires third-party infrastructure (CLIProxyAPI), an interactive OAuth install, and a terms-of-service judgment that belongs to the user. Procedure and caveats: [setup-runbook.md](setup-runbook.md), Part B. Never install it unprompted.

## Invocation pattern

Non-interactive, one task per invocation, seat and effort pinned into the call exactly as the lead chose them for this dispatch (a supported level only):

```bash
# Advisory / review work — read-only sandbox:
codex exec -m <verified-model> -c model_reasoning_effort=<level> \
  --sandbox read-only -C <repo-path> - < .foreman/scratch/ticket-N.md

# Implementation work — writable workspace:
codex exec -m <verified-model> -c model_reasoning_effort=<level> \
  --sandbox workspace-write -C <repo-path> - < .foreman/scratch/ticket-N.md
```

- Write the ticket to a file and pipe via stdin (`- <`) — avoids shell-quoting bugs.
- Sandbox follows the *task* (advisory vs implementation), not the seat.
- `--json` emits a JSONL event stream if you need structured events; otherwise the final message arrives on stdout.
- Long tasks: under the default wrapper transport, the wrapper subagent carries the job and the harness handles completion notification — record the wrapper's task identity in the ledger instead of a raw job ID. Under direct exec (fallback), the baseline rule stands: **record the job ID and output file path in the ledger at dispatch time**, capture the exit code on collection, and apply the LOST-worker protocol (delegation.md) if it goes silent. Never foreground-block the session on a long build.

## Reading back

Codex workers follow the same contract as Claude workers: **status as the first line of the final message** (`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED` — put this in every execution ticket's OUTPUT FORMAT), evidence not narrative, artifacts to `.foreman/scratch/` with paths. A Codex read-only reviewer asked for a review verdict may lead with the verdict vocabulary (`PASS` / `FAIL` / `PASS_WITH_NOTES`) as a reporting convention (verification.md) — and that verdict is scoped **evidence**: **the lead accepts**, a reviewer verdict supplies evidence rather than acceptance, and a reviewer verdict alone is never acceptance proof. Reviewer qualification is model + transport + allowed tools + assigned checks, with a **named executor** for every required deterministic check; a check nobody ran stays UNVERIFIED. Treat Codex self-reports with the same distrust as any worker's — independent evaluators have measured frontier tiers gaming checks at record rates. Cross-family review is the default: Claude verifies Codex work.

**The relay is a claim.** A haiku transport wrapper was observed (2026-08-18) relaying an invented report while the on-disk artifact held the real, schema-valid one. For any class-sensitive read — verdicts, findings entering a fix wave, statuses that decide routing — the foreman reads the artifact file directly; the relay serves notification and status only.

**Repairs and role transition — Codex has no resume.** `codex-dispatch.sh` exposes no session-resume argument, so a repair ticket to Codex is a **fresh dispatch**, and a fresh dispatch is a *replacement*: the new worker carries the preserved contract, the findings list, and the evidence from the earlier attempt, written into its ticket. It does not carry the earlier worker's reasoning, and nothing about the earlier session should be described as retained. A reviewer never edits the candidate it is judging within the same assignment; changing a Codex reviewer into a fixer is an **explicit journaled writable dispatch** (`workspace-write`), its earlier verdict does not cover the edits it then makes, affected checks are re-run, and a **different fresh context** assesses the repaired revision (delegation.md, verification.md).

## Quota notes

- Codex plans meter usage in rolling windows, with cheaper tiers typically draining the shared pool more slowly and often enjoying higher message allowances — but verify against the user's plan rather than promising numbers.
- Rate limits are per-account: more parallel workers ≠ more throughput. Sequential-by-default applies here too.
- Rate-limit errors mid-run: don't burn retries — fall back to the Claude seat of the same class for the remainder and note it in the ledger.
