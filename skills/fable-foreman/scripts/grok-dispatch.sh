#!/bin/sh
# fable-foreman — fixed-argv Grok launcher.
# Transport wrappers run ONLY this script, never a hand-composed grok command:
# argv is pinned here, so pipelines, substitutions, and nested grok invocations
# cannot ride in through the wrapper's shell (SKILL.md hard rail 1 carve-out).
#
# Usage: grok-dispatch.sh <ticket-file> <model> <effort> <read-only|workspace> <artifact-json> [workdir] [resume-session-id] [schema-file]
#
# schema-file: optional path to a JSON Schema. When given, Grok is constrained to
# emit a matching object under `structuredOutput` — a verdict contract that
# cannot hedge in prose. Kept INSIDE the pinned argv on purpose: schema-locked
# review is the recommended pattern, so it must not require a hand-composed
# grok command that bypasses these guards.
#
# Emits a transport envelope (exit code / duration / pid file / seat evidence /
# usage) on stdout; the Grok JSON result goes to <artifact-json>, stderr to
# <artifact-json>.stderr, the child PID to <artifact-json>.pid.
set -eu

[ $# -ge 5 ] || { echo "BLOCKED: usage: grok-dispatch.sh <ticket-file> <model> <effort> <read-only|workspace> <artifact-json> [workdir] [resume-session-id] [schema-file]" >&2; exit 64; }

# Resolution order matches scripts/probe.sh — $GROK_BIN, then PATH, then
# $GROK_HOME/bin — so Step 0 certifies the same binary that later gets paid.
# probe.sh applies the same order and, like this script, refuses rather than
# falling through when $GROK_BIN is set but not executable. If you set it here,
# set it in the environment the probe ran in too. The resolved path is echoed in
# the envelope so the ledger records which binary actually ran.
if [ -n "${GROK_BIN:-}" ]; then
  :
elif command -v grok >/dev/null 2>&1; then
  GROK_BIN=$(command -v grok)
else
  GROK_BIN="${GROK_HOME:-$HOME/.grok}/bin/grok"
fi
# Optional extra deny glob for a path that must never be written even by a
# tool call (e.g. a notes vault). Unset by default: this ships to other
# machines, so no personal path is hardcoded here. The OS sandbox — not this
# glob — is the real boundary (see the note where the denials are assembled).
VAULT_GLOB="${FOREMAN_VAULT_GLOB:-}"

TICKET="$1"; MODEL="$2"; EFFORT="$3"; SANDBOX="$4"; OUT="$5"; WORKDIR="${6:-.}"; RESUME="${7:-}"; SCHEMA="${8:-}"

# `off` is never accepted: a dispatched worker always gets an OS-enforced boundary.
case "$SANDBOX" in read-only|workspace) ;; *) echo "BLOCKED: invalid sandbox '$SANDBOX' (use read-only|workspace)" >&2; exit 64 ;; esac
case "$EFFORT" in low|medium|high|xhigh) ;; *) echo "BLOCKED: invalid effort '$EFFORT'" >&2; exit 64 ;; esac
case "$MODEL" in *[!A-Za-z0-9._-]*|"") echo "BLOCKED: invalid model id" >&2; exit 64 ;; esac
case "$RESUME" in
  -*) echo "BLOCKED: resume session id must not begin with '-' (got '$RESUME') — pass a bare session id, not a flag" >&2; exit 64 ;;
  *[!A-Za-z0-9-]*) echo "BLOCKED: invalid resume session id" >&2; exit 64 ;;
esac

# grok-4.5 has no xhigh: sending it is a hard error (exit 1), not a graceful
# degrade — verified 2026-08-17. Catch it here rather than paying a failed turn.
if [ "$EFFORT" = "xhigh" ]; then
  case "$MODEL" in *4.5*) echo "BLOCKED: model '$MODEL' does not support xhigh (use high|medium|low)" >&2; exit 64 ;; esac
fi

[ -x "$GROK_BIN" ] || { echo "BLOCKED: grok binary not executable: $GROK_BIN" >&2; exit 69; }

# Model-aware effort check from the CLI's own model cache (free, local). The
# static 4.5 rule above stays as the fallback when no cache is readable. A
# model absent from the cache is allowed through — the cache can lag a new
# release, and Grok itself refuses an unknown id cheaply (failure mapping).
GROK_MC="${GROK_HOME:-$HOME/.grok}/models_cache.json"
if [ -s "$GROK_MC" ] && command -v python3 >/dev/null 2>&1; then
  EFF_OK=$(python3 - "$GROK_MC" "$MODEL" "$EFFORT" <<'PYEOF' 2>/dev/null
import json, sys
mc, model, eff = sys.argv[1:4]
m = (json.load(open(mc)).get("models") or {}).get(model)
if not isinstance(m, dict):
    print("unknown-model"); sys.exit(0)
levels = [e.get("id") for e in (m.get("info") or {}).get("reasoning_efforts") or []]
print("ok" if not levels or eff in levels else "no:" + "|".join(levels))
PYEOF
) || EFF_OK=""
  case "$EFF_OK" in
    no:*) echo "BLOCKED: model '$MODEL' does not support effort '$EFFORT' (supported: ${EFF_OK#no:})" >&2; exit 64 ;;
  esac
fi
[ -f "$TICKET" ] || { echo "BLOCKED: ticket not found: $TICKET" >&2; exit 66; }
[ -d "$WORKDIR" ] || { echo "BLOCKED: workdir not found: $WORKDIR" >&2; exit 66; }

# Schema is taken as a FILE PATH rather than an inline argv blob from the caller,
# and validated as real JSON here before use. Be precise about what that buys:
# the contents are still expanded onto grok's argv below (`--json-schema "$(cat
# ...)"`), because that is the only interface the binary offers. What the file
# indirection removes is caller-side quoting hazard and unvalidated text; it does
# not keep the schema off the command line.
if [ -n "$SCHEMA" ]; then
  [ -f "$SCHEMA" ] || { echo "BLOCKED: schema file not found: $SCHEMA" >&2; exit 66; }
  [ -L "$SCHEMA" ] && { echo "BLOCKED: schema path is a symlink: $SCHEMA" >&2; exit 64; }
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SCHEMA" 2>/dev/null \
      || { echo "BLOCKED: schema file is not valid JSON: $SCHEMA" >&2; exit 64; }
  fi
fi

# --prompt-file and --json-schema paths are resolved by grok relative to --cwd,
# so everything is absolutized here (verified 2026-08-18: a relative ticket with
# a different workdir failed with 'No such file'). OUT is absolutized too so the
# artifact checks below and the envelope name the same file the caller meant.
case "$TICKET" in /*) ;; *) TICKET="$PWD/$TICKET" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
if [ -n "$SCHEMA" ]; then
  case "$SCHEMA" in /*) ;; *) SCHEMA="$PWD/$SCHEMA" ;; esac
fi
WORKDIR=$(cd "$WORKDIR" && pwd -P)
[ -d "$(dirname "$OUT")" ] || { echo "BLOCKED: artifact directory does not exist: $(dirname "$OUT")" >&2; exit 66; }

# The read-only profile does NOT contain writes under /tmp (verified 2026-08-17:
# a file was created in a /private/tmp workdir under --sandbox read-only). A
# read-only reviewer sited there is not isolated, so refuse it outright.
if [ "$SANDBOX" = "read-only" ]; then
  ABS_WD=$(cd "$WORKDIR" 2>/dev/null && pwd -P) || { echo "BLOCKED: cannot resolve workdir" >&2; exit 66; }
  case "$ABS_WD" in
    /tmp|/tmp/*|/private/tmp|/private/tmp/*|/var/tmp|/var/tmp/*|/private/var/tmp|/private/var/tmp/*)
      echo "BLOCKED: read-only sandbox does not contain writes under /tmp ($ABS_WD) — site the reviewer elsewhere" >&2; exit 64 ;;
  esac
fi

# Artifact-path constraints: never a symlink, never the ticket itself.
case "$OUT" in *.json) ;; *) echo "BLOCKED: artifact path must end in .json: $OUT" >&2; exit 64 ;; esac
for P in "$OUT" "$OUT.stderr" "$OUT.pid"; do
  [ -L "$P" ] && { echo "BLOCKED: artifact path is a symlink: $P" >&2; exit 64; }
  [ -e "$P" ] && [ ! -f "$P" ] && { echo "BLOCKED: artifact path exists and is not a regular file: $P" >&2; exit 64; }
  [ -e "$P" ] && [ "$P" -ef "$TICKET" ] && { echo "BLOCKED: artifact path aliases the ticket: $P" >&2; exit 64; }
done
[ "$OUT" = "$TICKET" ] && { echo "BLOCKED: artifact path equals ticket path" >&2; exit 64; }
# A mistyped artifact path (say, a repo's package.json) would be truncated at
# spawn. Refuse any pre-existing NON-EMPTY file: fresh artifacts and empty
# placeholders are fine, real files are not ours to destroy.
[ -s "$OUT" ] && { echo "BLOCKED: artifact path already exists and is non-empty: $OUT (refusing to truncate)" >&2; exit 64; }

# Grok auto-discovers the user's Claude world (CLAUDE.md, skills, agents, MCP
# servers, hooks) by default. The GROK_CLAUDE_*_ENABLED=false cells the
# launcher puts in the child's environment (see the spawn line below) switch
# that discovery OFF at the source (05-configuration.md 'Harness compatibility'; verified 2026-08-18:
# MCP servers no longer load, 209->103 commands, ~9K fewer input tokens per
# call). --rules and the deny rules below remain as defense in depth. Note: a
# generic top-level CLAUDE.md in the *working directory* stays recognized
# (documented) — that is project context and acceptable.
WORKER_RULES='You are a dispatched worker in a headless, non-interactive run. Do NOT write any session log. Do NOT write to the user'"'"'s notes vault or to any path outside the working directory named in your ticket. Do NOT run vault archiving or topic-linking steps. Confine all file changes to the working directory named in your ticket. Your final message IS your report to the dispatcher.'

# Hard rail 1 machine-enforced: workers never spawn workers.
#
# Boundary honesty: the OS sandbox is a WRITE boundary only. `workspace`
# confines writes to CWD + temp dirs + ~/.grok at the kernel level
# (18-sandbox.md). It is NOT a read boundary — both profiles read the whole
# filesystem — and on macOS it is NOT a network boundary: child-process network
# blocking is Linux-only, a documented no-op on macOS (18-sandbox.md:34). So a
# `workspace` worker holds a shell, web_fetch/web_search, and global read: it
# can read and transmit anything the user can. Codex's `workspace-write` blocks
# network on macOS by default; do not treat the two as equivalent. Site
# workspace workers only on repos you would let an autonomous agent read your
# home directory from; prefer read-only + no shell for review. The Write/Edit
# deny globs below are tool-layer defense-in-depth, never the boundary.
set -- --disallowed-tools "Agent" \
       --no-subagents \
       --deny "MCPTool" \
       --rules "$WORKER_RULES" \
       --permission-mode bypassPermissions \
       --output-format json \
       --sandbox "$SANDBOX" \
       -m "$MODEL" --reasoning-effort "$EFFORT" --cwd "$WORKDIR"

# An advisory reviewer gets no shell and no edit tools at all — the sandbox is
# the outer boundary, the allowlist is the inner one.
if [ "$SANDBOX" = "read-only" ]; then
  set -- "$@" --tools "read_file,grep,list_dir"
fi

if [ -n "$VAULT_GLOB" ]; then
  set -- "$@" --deny "Write($VAULT_GLOB)" --deny "Edit($VAULT_GLOB)"
fi

if [ -n "$RESUME" ]; then
  set -- "$@" --resume "$RESUME"
fi

if [ -n "$SCHEMA" ]; then
  set -- "$@" --json-schema "$(cat "$SCHEMA")"
fi

START=$(date +%s)
set +e
env GROK_CLAUDE_SKILLS_ENABLED=false GROK_CLAUDE_RULES_ENABLED=false GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false "$GROK_BIN" --prompt-file "$TICKET" "$@" > "$OUT" 2> "$OUT.stderr" &
CPID=$!
# PID file is the LOST-protocol handle — if it cannot be written, paid work must
# not continue untracked: kill the child and fail loudly.
if ! printf '%s\n' "$CPID" > "$OUT.pid"; then
  kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null
  echo "BLOCKED: could not write pid file $OUT.pid; grok child killed — no untracked spend" >&2
  exit 74
fi
trap 'kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null; echo "BLOCKED: launcher terminated; grok child $CPID killed and reaped" >&2; exit 143' INT TERM
wait "$CPID"
CODE=$?
trap - INT TERM
set -e
END=$(date +%s)

echo "exit code: $CODE"
echo "duration: $((END - START))s"
echo "pid file: $OUT.pid (child $CPID, reaped)"
echo "binary: $GROK_BIN"
echo "discovery: claude-compat OFF (GROK_CLAUDE_*_ENABLED=false) | subagents: --no-subagents + Agent tool removed"
echo "sandbox: $SANDBOX | tools: $([ "$SANDBOX" = read-only ] && echo 'read_file,grep,list_dir' || echo default) | Agent: blocked | MCP: denied | schema: ${SCHEMA:-none}"

# Seat provenance + reactive context measurement. modelUsage is BILLED-tier
# evidence (verification.md): it names what was charged, not the weights that
# answered. Never print it as `seat: verified`.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$OUT" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8", errors="replace"))
except Exception as e:
    print(f"seat evidence: NONE (unparsable artifact: {e})")
    try:
        tail = open(sys.argv[1] + ".stderr", encoding="utf-8", errors="replace").read()[-4000:]
    except OSError:
        tail = ""
    for kw, v in (("402", "BALANCE_EXHAUSTED"), ("usage balance", "BALANCE_EXHAUSTED"),
                  ("not authenticated", "AUTH_FAILED"), ("401", "AUTH_FAILED"), ("429", "RATE_LIMITED")):
        if kw in tail.lower():
            print(f"GROK ACCESS: {v} (from stderr) — see the failure mapping in grok-workers.md"); break
    sys.exit(0)
if not isinstance(d, dict):
    print("seat evidence: NONE (artifact is not a JSON object)"); sys.exit(0)
def access_verdict(text):
    # Deterministic access classification (2026-09-23). Signed-in is not the
    # same as usable: an exhausted Grok Build balance arrives as HTTP 402 on a
    # billable call while `grok models` still reports "logged in".
    t = text.lower()
    if "402" in t or "usage balance" in t or "payment required" in t:
        return "BALANCE_EXHAUSTED — Grok pool is down; stop Grok dispatches, re-route per the degradation rule, do not retry until the user restores capacity"
    if "401" in t or "403" in t or "not authenticated" in t or "unauthorized" in t or "login" in t:
        return "AUTH_FAILED — session expired or signed out; the user runs 'grok login' (never start it yourself)"
    if "429" in t or "rate limit" in t or "too many requests" in t:
        return "RATE_LIMITED — back off; count toward the precedence table, do not burn retries in place"
    if "dns" in t or "connect" in t or "network" in t or "timed out" in t:
        return "NETWORK — check whether this shell is sandboxed/offline before concluding Grok is down"
    return None
if d.get("type") == "error":
    msg = d.get("message", "(no message)")
    print(f'GROK ERROR: {msg}')
    v = access_verdict(msg)
    if v:
        print(f'GROK ACCESS: {v}')
    sys.exit(0)
mu = d.get("modelUsage")
if isinstance(mu, dict) and mu:
    print(f'seat: billed-tier evidence — modelUsage {", ".join(sorted(mu))} (NOT served-tier; not `verified`)')
else:
    print("seat evidence: NONE (no modelUsage in envelope)")
print(f'session id: {d.get("sessionId","(none)")}')
print(f'stop reason: {d.get("stopReason","(none)")}  turns: {d.get("num_turns","(none)")}')
u = d.get("usage") or {}
def _n(key):
    try:
        return int(u.get(key) or 0)
    except (TypeError, ValueError):
        return 0
inp = _n("input_tokens")                    # UNCACHED only, SUMMED across model calls
cr = _n("cache_read_input_tokens")
cc = _n("cache_creation_input_tokens")
out = u.get("output_tokens")
tot = u.get("total_tokens")
try:
    turns = int(d.get("num_turns") or 0) or 1
except (TypeError, ValueError):
    turns = 1
prompt_total = inp + cr + cc
prompt_avg = prompt_total // turns
print(f'usage: uncached_input={inp} cache_read={cr} output={out} total={tot} cost_usd={d.get("total_cost_usd")}')
print(f'prompt: total={prompt_total} over {turns} model call(s), avg/call={prompt_avg} '
      '(exact for 1 call; a floor for multi-turn — late calls of a growing session are larger)')
# Reactive context rule (routing.md, model-matrix.md Table 3): the 200K
# repricing cliff applies to the WHOLE prompt of EACH model call, so the figure
# that matters is prompt size per call — not `usage.input_tokens`, which is
# uncached-only and summed across calls (14-headless-mode.md:168-175).
# Per-call exactness needs the streaming-json `usage` events (14-headless-mode.md,
# one per model response); the json envelope only carries sums.
if prompt_avg > 200000:
    print("CONTEXT ALERT: average prompt exceeded 200000 per call — every call was repriced at the 2x tier")
elif prompt_avg > 120000 or (turns == 1 and prompt_total > 150000):
    print("CONTEXT WARN: prompt size approaching/likely past the 200000 repricing cliff on late calls — "
          "treat this workstream as at the cliff")
PYEOF
fi

exit "$CODE"
