# Local (Ollama + Aider) workers: probe, invoke, read back

An optional fourth worker family, alongside Claude/Codex/Grok — never a
requirement. Where Codex and Grok are full coding agents (their own
read/edit/run loop, their own `--sandbox` flag), **Ollama by itself is not**:
it is a bare completion server with no file-editing/tool-use loop and no
sandbox. To get a comparable local worker that actually executes, this skill
pairs Ollama with **Aider** (MIT-licensed, first-class Ollama support), which
supplies the agentic loop and uses **git auto-commit as its only undo
mechanism**. That single fact — no OS-enforced boundary, git is the safety
net — governs every rule below.

**Install with `pipx install aider-chat`, not a bare `pip install`.** A plain
`pip`/`python` on PATH may resolve to some *other* tool's virtualenv (this
happened on the author's own machine — the first `pip` found on PATH
belonged to an unrelated agent's venv) and installing Aider there pollutes
it. `pipx` gives Aider its own isolated environment regardless of what else
is on PATH. If neither `pipx` nor a working `python`/`pip` is on PATH, install
one Python (e.g. via `py -3 -m pip install --user pipx` on Windows, then
`py -3 -m pipx ensurepath`) before installing Aider. **The PATH update from
`pipx ensurepath` does not reach an already-running shell/session** — an
already-open Claude Code session needs a restart before `aider` resolves on
PATH; the probe reporting `aider: NOT installed` right after a fresh install
is this, not a failed install.

## The probe (once per session, cache the result)

```bash
command -v ollama                                # 1. CLI installed?
ollama --version                                 # 2. binary alive — which build?
curl -fsS http://127.0.0.1:11434/api/tags         # 3. server actually running and reachable?
ollama list                                       # 4. which models are pulled?
command -v aider && aider --version               # 5. is the agentic loop present?
```

Honor `OLLAMA_API_BASE` if the environment sets it — the launcher checks the
same variable, defaulting to `http://127.0.0.1:11434`. Step 3 matters on its
own: a stopped server is the most common local-seat failure, and it produces
a confusing Aider connection error rather than a clean refusal, which is why
`scripts/ollama-dispatch.sh` checks reachability itself before spending
anything.

**Verified on this machine (2026-09-05):** `ollama.exe` 0.32.4, listening on
`0.0.0.0:11434`; `ollama list` reports ten pulled models including
`qwen2.5-coder:14b`, `qwen2.5:32b`, `mistral:latest`, `qwen3.5:latest`, and
six identically-sized (4.4 GB) custom-tagged models (`neo-v1`, `argus-v1`,
`zeus-v1`, `artemis-v1`, `blacksun-v1`, `logos-v1`) whose tuning is unverified
— **don't default to those** for foreman work; use a known base model. Aider
0.86.2 was installed via `pipx` (see above) and confirmed working end-to-end
against `qwen2.5-coder:14b` through `scripts/ollama-dispatch.sh` — a real
docstring-addition ticket was dispatched, applied, and auto-committed cleanly
in a scratch repo, 2026-09-05.

## Billing: none — but that is not the same as "no cost to weigh"

There is no consent gate here the way there is for Codex/Grok (Step 0 items
4-5): nothing is billed to another account, so the per-dispatch ask that
exists for those providers does not apply to local dispatches. That is also
why the user's hybrid-trust instruction (simple/mechanical tasks may run
without a per-dispatch ask) is safe to apply *here* specifically — it trades
away a money question that doesn't exist on this seat, not a safety question.

**The safety question is unsandboxed filesystem writes, and it is never
waived.** Aider edits files directly with no OS-level boundary; the git
auto-commit it makes is the entire undo mechanism. That is why:
- `scripts/ollama-dispatch.sh` refuses a `workspace-write` dispatch against a
  dirty tree (the commit would otherwise mix pre-existing changes into "the
  model's" diff, and there would be nothing clean to verify or revert).
- Ticket WRITE SETs must stay tight — same rule as every other worker, but
  with no sandbox to catch a WRITE SET violation, the ticket text is the only
  boundary.
- The blind-verifier requirement (SKILL.md, "Verify like you trust no one")
  is never skipped for local-worker output — if anything it matters *more*
  here, since seat evidence is weaker than Codex's or Grok's (see below).

One more real, observed cost: this machine had a `python` process already
holding an established connection to the Ollama server when it was probed —
something else on this machine uses it. A local dispatch can contend for the
same GPU/CPU with whatever else is running; a slow or stalled response may be
resource contention, not absence, before you conclude the launcher hung.

## Discovering the account's models

`ollama list` is authoritative and local — no account/auth split exists the
way it does for Codex (ChatGPT-login vs. API-key IDs). There is no equivalent
of Codex's or Grok's effort dial: Ollama serves whatever the model was built
with, and Aider has no `--reasoning-effort` flag for it. Convey desired depth
in the ticket text instead ("mechanical batch edit; do not deliberate" /
"reason carefully"), same fallback routing.md already prescribes when no
effort control exists.

**Context window is a real trap, not a formality.** Unlike Codex/Grok, whose
context ceilings are fixed platform facts, an Ollama model's *served* context
window depends on how it's invoked — Ollama's own default is small (commonly
2048 tokens) unless the caller requests more. Aider negotiates this with
Ollama itself and will warn if a chat history risks exceeding it, but a
ticket carrying a large WRITE SET or a lot of pasted context can silently
truncate on this seat in a way it would not on Codex/Grok. Keep local tickets
small and self-contained; when a task needs a lot of context, route it to a
Claude/Codex/Grok seat instead.

Map to routing classes conservatively, since none of this is externally
benchmarked the way model-matrix.md's Table 1 is: `qwen2.5-coder:14b` (or
whichever coding-tuned model is present) as **FAST** for mechanical,
tightly-scoped edits, and **WORKHORSE** only for well-specified
implementation you would be comfortable re-verifying closely. **Never
FRONTIER** — there is no capability evidence to support judgment-class work
on this seat, and the First Law (SKILL.md) means the absence of evidence is
itself a reason not to route judgment work here.

## Transport: wrapper first, direct launcher call as fallback

Same wrapper-first pattern as Codex and Grok: the bundled `scripts/ollama-
dispatch.sh` launcher and the `foreman-ollama-wrapper` agent.

**The launcher's real argument list** (read from `scripts/ollama-
dispatch.sh` — never hand-compose an `aider` or `ollama` call):

```
ollama-dispatch.sh <ticket-file> <model> <read-only|workspace-write> <artifact-log> [workdir]
```

Four required slots, one optional (`workdir`, defaulting to `.`). Note the
artifact extension is `.log`, not `.jsonl`/`.json` — Aider's output is plain
text, so there is no event stream to parse, only a transcript to tail.

Before spending anything, the launcher validates and refuses (`BLOCKED` on
stderr, nonzero exit) on: an invalid sandbox value; a model id outside
`[A-Za-z0-9._:-]` (Ollama tags use a colon, e.g. `qwen2.5-coder:14b` — wider
than Codex's charset); a missing ticket or workdir; an artifact path that
doesn't end in `.log`, is a symlink, or aliases the ticket; a
`workspace-write` dispatch against a **dirty git tree** or a non-git workdir;
and an unreachable Ollama server or missing `aider` binary.

What it pins into the actual `aider` invocation once validation passes:
`--yes-always --no-analytics --no-check-update --model
ollama_chat/$MODEL --message-file $TICKET`, plus `--chat-mode ask
--no-auto-commits` for `read-only` (drafts changes, applies none) or
`--auto-commits` for `workspace-write`. The child's PID is written to
`<artifact>.pid` before the launcher waits on it — the "prove it stopped"
handle (delegation.md) — and an INT/TERM to the launcher forwards to the
child and reaps it, identical discipline to `codex-dispatch.sh`.

**The wrapper contract** (also lives in `agents/foreman-ollama-wrapper.md`):

1. Run `scripts/ollama-dispatch.sh` exactly once, with exactly the ticket's
   arguments. Never compose a raw `aider`/`ollama` command, never wrap the
   launcher in shell operators, never run it twice.
2. Report: Line 1 `DONE`/`BLOCKED`, then the envelope verbatim, then the last
   60 lines of the artifact log verbatim (`tail -n 60 <artifact-log>`) — no
   JSON to parse here, unlike Codex/Grok.
3. Spawn nothing; write nothing except what the launcher itself writes.
4. The relay is transport metadata — the foreman reads the artifact **and
   the git log/diff** directly for anything it will act on. The transcript
   never substitutes for looking at the actual commit.

**Failure mapping:**

| Observation | Treatment |
|---|---|
| Launcher exit nonzero (`BLOCKED:` refusal, or Aider itself failing) | Worker `BLOCKED`; envelope + `<artifact>.stderr` are the evidence |
| Exit 0, no `Model:`/`Main model:` banner found | `seat: unverified` — proceed, but never upgrade this to `verified` on any later claim |
| Exit 0, workdir still dirty after a `workspace-write` dispatch beyond the expected auto-commit | Treat as a contract breach — Aider is supposed to leave a clean tree with its own commit on top; investigate before accepting |
| Wrapper itself silent past its deadline | Wrapper task is `LOST` (delegation.md) — check `<artifact>.pid`, kill the child if still live, reconcile against `git status` before doing anything else |

## Reading back

**Seat evidence here is the weakest of the four families, and must be
labeled that way.** Codex's evidence comes from a parsed lifecycle event in
its own JSON stream; Grok's comes from a billing-layer `modelUsage` key that
tracks the real request. The local seat has neither — the only signal is a
plain-text banner line the same process prints about itself, which is
self-report, not independent evidence. Log it exactly as the launcher does:
`seat evidence: banner-consistent (unverified) — Model: ollama_chat/... with
... edit format` (verified banner text on aider 0.86.2, 2026-09-05; older or
newer builds may say `Main model:` instead — the launcher matches both).
Never write `seat: verified` for a local dispatch.

**What actually proves what changed is the git commit, not the transcript.**
Read the diff (`git show`/`git diff` against the baseline the ledger
recorded) before accepting anything — the transcript is for understanding
*why*, the commit is the record of *what*. This is not a hypothetical: a
verified dispatch (2026-09-05, `qwen2.5-coder:14b`) proposed a plausible-
looking whole-file edit in its transcript, exchanged further tokens, and
then applied **nothing** — no new commit, file unchanged on disk. The
launcher and wrapper reported `exit code: 0` throughout; only `git log`/`git
diff` revealed that the ticket produced no actual change. A clean exit and a
sensible-looking transcript are not evidence that anything was written.

Otherwise the local worker follows the same status contract as every other
worker: `DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED` as the
first line of its report (put this in the ticket's OUTPUT FORMAT — Aider
will not emit it natively, so the ticket must ask for it explicitly as the
last line of its response), evidence over narrative, artifacts under
`.foreman/scratch/` with paths.

## Quota notes

No external rate limit and no separate account pool to exhaust — the
constraint is local hardware (GPU/CPU/RAM) and whatever else on the machine
is already using it (see Billing above). Concurrent foreman work and other
local model workloads on the same machine will compete for the same
resource; that shows up as slowness, not as a quota error, so don't assume a
slow dispatch means the launcher hung.
