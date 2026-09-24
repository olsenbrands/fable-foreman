#!/bin/sh
# fable-foreman — fixed-argv Codex launcher.
# Transport wrappers run ONLY this script, never a hand-composed codex command:
# argv is pinned here, so pipelines, substitutions, and nested codex invocations
# cannot ride in through the wrapper's shell (SKILL.md hard rail 1 carve-out).
# The wrapper-must-not-touch-codex rule itself is contractual and transcript-
# auditable, not machine-enforced — see codex-workers.md for the honest scope.
#
# Usage: codex-dispatch.sh <ticket-file> <model> <effort> <read-only|workspace-write> <artifact-jsonl> [workdir]
# Emits a transport envelope (exit code / duration / pid file / seat evidence) on
# stdout; the Codex event stream goes to <artifact-jsonl>, stderr to <artifact-jsonl>.stderr,
# the child PID to <artifact-jsonl>.pid (the "prove it stopped" handle).
set -eu

TICKET="$1"; MODEL="$2"; EFFORT="$3"; SANDBOX="$4"; OUT="$5"; WORKDIR="${6:-.}"

case "$SANDBOX" in read-only|workspace-write) ;; *) echo "BLOCKED: invalid sandbox '$SANDBOX'" >&2; exit 64 ;; esac
# `ultra` (GPT-6 Astra/Sol) is "maximum reasoning with automatic task
# delegation": the worker spawns its own sub-agents. That is a worker spawning
# workers — hard rail 1 — so it is refused here, whatever the model supports.
case "$EFFORT" in
  ultra) echo "BLOCKED: effort 'ultra' auto-delegates to sub-agents (a worker spawning workers — SKILL.md hard rail 1); use max or lower" >&2; exit 64 ;;
  minimal|low|medium|high|xhigh|max) ;;
  *) echo "BLOCKED: invalid effort '$EFFORT'" >&2; exit 64 ;;
esac
case "$MODEL" in *[!A-Za-z0-9._-]*|"") echo "BLOCKED: invalid model id" >&2; exit 64 ;; esac
# Premium seats (gpt-6-astra) need the user's double approval for THIS session
# (routing-card.py approve-premium). The lead exports FOREMAN_PREMIUM_APPROVED=<model>
# only after recording that approval; anything else is refused before any spend.
case "$MODEL" in
  gpt-6-astra*)
    case ",${FOREMAN_PREMIUM_APPROVED:-}," in
      *",$MODEL,"*) ;;
      *) echo "BLOCKED: '$MODEL' is a premium seat — it needs the user's double approval this session (routing-card.py approve-premium $MODEL --session <run-id> --confirmed, then FOREMAN_PREMIUM_APPROVED=$MODEL)" >&2; exit 64 ;;
    esac ;;
esac
# Model-aware check against the CLI's own catalog (free, local): GPT-6 models
# have no `minimal`, gpt-6-luna has no `ultra`, gpt-5.5 has no `max`. A model
# missing from the cache passes through — the cache can lag a release — and so
# does every model when no cache is readable (fail-open by design: the provider
# then refuses an unsupported level itself, costing one failed turn, not a
# silent downgrade). The static `ultra` refusal above never fails open.
MC="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
if [ -s "$MC" ] && command -v python3 >/dev/null 2>&1; then
  EFF_OK=$(python3 - "$MC" "$MODEL" "$EFFORT" <<'PYEOF' 2>/dev/null
import json, sys
mc, model, eff = sys.argv[1:4]
for m in json.load(open(mc)).get("models", []):
    if m.get("slug") == model:
        lv = [e.get("effort") for e in m.get("supported_reasoning_levels", [])]
        print("ok" if not lv or eff in lv else "no:" + "|".join(lv)); break
else:
    print("unknown-model")
PYEOF
) || EFF_OK=""
  case "$EFF_OK" in
    no:*) echo "BLOCKED: model '$MODEL' does not support effort '$EFFORT' (supported: ${EFF_OK#no:})" >&2; exit 64 ;;
  esac
fi
[ -f "$TICKET" ] || { echo "BLOCKED: ticket not found: $TICKET" >&2; exit 66; }
[ -d "$WORKDIR" ] || { echo "BLOCKED: workdir not found: $WORKDIR" >&2; exit 66; }

# Artifact-path constraints: the artifact must be a fresh .jsonl (or an existing
# regular file), never a symlink, never the ticket itself — a dispatch must not
# be able to truncate arbitrary wrapper-writable files through OUT.
case "$OUT" in *.jsonl) ;; *) echo "BLOCKED: artifact path must end in .jsonl: $OUT" >&2; exit 64 ;; esac
for P in "$OUT" "$OUT.stderr" "$OUT.pid"; do
  [ -L "$P" ] && { echo "BLOCKED: artifact path is a symlink: $P" >&2; exit 64; }
  [ -e "$P" ] && [ ! -f "$P" ] && { echo "BLOCKED: artifact path exists and is not a regular file: $P" >&2; exit 64; }
  # -ef catches aliases of the same file (hard links, differing path spellings)
  [ -e "$P" ] && [ "$P" -ef "$TICKET" ] && { echo "BLOCKED: artifact path aliases the ticket: $P" >&2; exit 64; }
done
[ "$OUT" = "$TICKET" ] && { echo "BLOCKED: artifact path equals ticket path" >&2; exit 64; }

START=$(date +%s)

# Run Codex as a tracked child: PID recorded before any output is awaited, and
# a termination trap forwards INT/TERM and waits — no orphaned Codex editing
# the workspace after the wrapper dies (delegation.md "prove it stopped").
set +e
codex exec -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --sandbox "$SANDBOX" \
  --skip-git-repo-check -C "$WORKDIR" --json - < "$TICKET" > "$OUT" 2> "$OUT.stderr" &
CPID=$!
# The PID file is the LOST-protocol handle — if it cannot be written, paid work
# must not continue untracked: kill the child and fail loudly (round-3 finding 4).
if ! printf '%s\n' "$CPID" > "$OUT.pid"; then
  kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null
  echo "BLOCKED: could not write pid file $OUT.pid; codex child killed — no untracked spend" >&2
  exit 74
fi
trap 'kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null; echo "BLOCKED: launcher terminated; codex child $CPID killed and reaped" >&2; exit 143' INT TERM
wait "$CPID"
CODE=$?
trap - INT TERM
set -e
END=$(date +%s)

echo "exit code: $CODE"
echo "duration: $((END - START))s"
echo "pid file: $OUT.pid (child $CPID, reaped)"

# Served-model evidence — schema-aware, not a bare grep: only a top-level
# "model" key in a parsed JSONL event counts, and the event type is recorded.
# Current Codex builds emit none (verified 2026-08-07); a nested tool-argument
# or prompt-body "model" string must NOT falsely certify a seat.
EVIDENCE=""
if command -v python3 >/dev/null 2>&1; then
  EVIDENCE=$(python3 - "$OUT" <<'PYEOF'
import json, sys
# `candidate` must exist before the loop: it is only assigned inside the
# model-field branch, so a stream with no model field (or a request-side one)
# raised NameError on the `if candidate is not None` check below.
candidate = None
try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if isinstance(ev, dict) and isinstance(ev.get("model"), str):
                # Only session/thread/turn lifecycle events can certify the
                # SERVING model; request-side events echo the REQUESTED model
                # ({"type":"request.sent","model":...} must not certify a
                # seat). Keep scanning past non-lifecycle candidates — an
                # early request event must not mask lifecycle evidence later
                # in the stream. Unknown event types are surfaced as
                # candidates, never as evidence.
                etype = ev.get("type", "unknown")
                if isinstance(etype, str) and (
                    etype in ("thread.started", "turn.started", "turn.completed", "session.created")
                    or etype.startswith("session_")
                ):
                    print(f'served model "{ev["model"]}" in lifecycle event "{etype}"')
                    candidate = None
                    break
                if candidate is None:
                    candidate = f'CANDIDATE-ONLY: model "{ev["model"]}" in unrecognized event "{etype}" — not certifying; seat stays unverified'
        if candidate is not None:
            print(candidate)
except OSError:
    pass
PYEOF
) || EVIDENCE=""
fi
# Access classification from stderr — the same deterministic vocabulary the
# Grok launcher prints, so the foreman reads one set of states across providers.
if [ "$CODE" != 0 ] && [ -s "$OUT.stderr" ]; then
  if grep -qiE "usage limit|rate.?limit|429|quota" "$OUT.stderr"; then
    echo "CODEX ACCESS: RATE_LIMITED/QUOTA — pool exhausted or throttled; re-route per the degradation rule, do not retry in place"
  elif grep -qiE "401|403|unauthori|not logged in|login" "$OUT.stderr"; then
    echo "CODEX ACCESS: AUTH_FAILED — the user runs 'codex login' (never start it yourself)"
  elif grep -qiE "model.*(not found|not supported|does not exist)|unsupported model" "$OUT.stderr"; then
    echo "CODEX ACCESS: MODEL_NOT_ENTITLED — this account cannot use '$MODEL'; re-discover tiers (codex-workers.md)"
  fi
fi
if [ -n "$EVIDENCE" ]; then
  echo "seat evidence: $EVIDENCE via codex --json event stream"
else
  echo "seat evidence: NONE — no top-level served-model field in event stream; requested '$MODEL' via -m. Seat: unverified (Layer 0)."
fi

exit "$CODE"
