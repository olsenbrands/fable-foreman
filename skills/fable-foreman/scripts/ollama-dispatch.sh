#!/bin/sh
# fable-foreman — fixed-argv local (Ollama + Aider) launcher.
# Transport wrappers run ONLY this script, never a hand-composed aider/ollama
# command: argv is pinned here, so pipelines, substitutions, and nested
# invocations cannot ride in through the wrapper's shell (SKILL.md hard rail 1
# carve-out).
#
# Why Aider, not a raw `ollama run`: Ollama is a bare completion server with no
# file-editing/tool-use loop and no sandbox of its own. Aider supplies the
# read-repo/edit-file/run-tests loop and uses git auto-commit as its undo
# mechanism — that commit is this launcher's ONLY safety net, which is why the
# clean-tree precondition below is not optional.
#
# Usage: ollama-dispatch.sh <ticket-file> <model> <read-only|workspace-write> <artifact-log> [workdir]
# Emits a transport envelope (exit code / duration / pid file / seat evidence) on
# stdout; Aider's own transcript goes to <artifact-log>, stderr to
# <artifact-log>.stderr, the child PID to <artifact-log>.pid (the "prove it
# stopped" handle — same discipline as codex-dispatch.sh / grok-dispatch.sh).
set -eu

TICKET="$1"; MODEL="$2"; SANDBOX="$3"; OUT="$4"; WORKDIR="${5:-.}"

case "$SANDBOX" in read-only|workspace-write) ;; *) echo "BLOCKED: invalid sandbox '$SANDBOX'" >&2; exit 64 ;; esac
# Ollama model ids use a colon for the tag (qwen2.5-coder:14b) — wider charset
# than Codex's launcher, which never sees tags.
case "$MODEL" in *[!A-Za-z0-9._:-]*|"") echo "BLOCKED: invalid model id" >&2; exit 64 ;; esac
[ -f "$TICKET" ] || { echo "BLOCKED: ticket not found: $TICKET" >&2; exit 66; }
[ -d "$WORKDIR" ] || { echo "BLOCKED: workdir not found: $WORKDIR" >&2; exit 66; }

# Artifact-path constraints, mirrored from codex-dispatch.sh: plain-text log,
# never a symlink, never the ticket itself.
case "$OUT" in *.log) ;; *) echo "BLOCKED: artifact path must end in .log: $OUT" >&2; exit 64 ;; esac
for P in "$OUT" "$OUT.stderr" "$OUT.pid"; do
  [ -L "$P" ] && { echo "BLOCKED: artifact path is a symlink: $P" >&2; exit 64; }
  [ -e "$P" ] && [ ! -f "$P" ] && { echo "BLOCKED: artifact path exists and is not a regular file: $P" >&2; exit 64; }
  [ -e "$P" ] && [ "$P" -ef "$TICKET" ] && { echo "BLOCKED: artifact path aliases the ticket: $P" >&2; exit 64; }
done
[ "$OUT" = "$TICKET" ] && { echo "BLOCKED: artifact path equals ticket path" >&2; exit 64; }

# Preflight: the local seat has no OS-enforced sandbox — the git working tree
# is the only undo mechanism, so a workspace-write dispatch refuses to run
# against a dirty tree (Aider's auto-commit would otherwise sweep pre-existing
# changes into "the model's" commit, and there would be no clean diff to
# verify). read-only dispatches (ask-mode, no edits applied) are exempt.
if [ "$SANDBOX" = workspace-write ]; then
  git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "BLOCKED: workdir is not a git repository — no undo mechanism for an unsandboxed local worker" >&2
    exit 65
  }
  # Aider unconditionally appends ".aider*" to .gitignore the first time it
  # runs in a repo, and does not reliably fold that edit into its own commit
  # (observed 2026-09-05: left uncommitted after an otherwise-clean dispatch).
  # Normalize it ourselves, as a separate, clearly-attributed commit, before
  # judging tree cleanliness — this is one-time launcher bookkeeping, never
  # the model's work, so it must never be mistaken for either.
  GI="$WORKDIR/.gitignore"
  if ! grep -qx '\.aider\*' "$GI" 2>/dev/null; then
    printf '%s\n' '.aider*' >> "$GI"
    git -C "$WORKDIR" add -- .gitignore
    git -C "$WORKDIR" -c user.email="foreman-launcher@localhost" -c user.name="fable-foreman ollama-dispatch.sh" \
      commit -q -m "chore(foreman): ignore aider metadata" -- .gitignore
  fi
  DIRTY=$(git -C "$WORKDIR" status --porcelain 2>/dev/null) || {
    echo "BLOCKED: git status failed in workdir — refusing to dispatch against an unverifiable tree" >&2
    exit 65
  }
  [ -z "$DIRTY" ] || {
    echo "BLOCKED: workdir has uncommitted changes — commit or stash before a workspace-write local dispatch" >&2
    exit 65
  }
fi

# Server reachability — the most common local-seat failure mode is "Ollama
# isn't running," which is worth a clear refusal rather than a confusing Aider
# connection-error transcript.
OLLAMA_URL="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 5 "$OLLAMA_URL/api/tags" >/dev/null 2>&1 || {
    echo "BLOCKED: Ollama not reachable at $OLLAMA_URL/api/tags — is the server running?" >&2
    exit 69
  }
fi
command -v aider >/dev/null 2>&1 || { echo "BLOCKED: aider not found on PATH (pip install aider-chat)" >&2; exit 69; }

START=$(date +%s)

# Aider warns and may misbehave if this isn't set explicitly, even though it
# happens to default correctly for a local server (verified 2026-09-05).
export OLLAMA_API_BASE="$OLLAMA_URL"

ARGS="--yes-always --no-analytics --no-check-update --no-pretty --model ollama_chat/$MODEL --message-file $TICKET"
case "$SANDBOX" in
  read-only) ARGS="$ARGS --chat-mode ask --no-auto-commits" ;;
  workspace-write) ARGS="$ARGS --auto-commits" ;;
esac

# Run Aider as a tracked child: PID recorded before any output is awaited, and
# a termination trap forwards INT/TERM and waits — no orphaned Aider editing
# the workspace after the wrapper dies (delegation.md "prove it stopped").
set +e
# shellcheck disable=SC2086
( cd "$WORKDIR" && aider $ARGS ) > "$OUT" 2> "$OUT.stderr" &
CPID=$!
if ! printf '%s\n' "$CPID" > "$OUT.pid"; then
  kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null
  echo "BLOCKED: could not write pid file $OUT.pid; aider child killed — no untracked work" >&2
  exit 74
fi
trap 'kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null; echo "BLOCKED: launcher terminated; aider child $CPID killed and reaped" >&2; exit 143' INT TERM
wait "$CPID"
CODE=$?
trap - INT TERM
set -e
END=$(date +%s)

echo "exit code: $CODE"
echo "duration: $((END - START))s"
echo "pid file: $OUT.pid (child $CPID, reaped)"

# Seat evidence — plain-text scrape, not an event stream. Aider prints a
# "Model: <id> ..." banner line naming what it actually loaded (verified
# 2026-09-05 on aider 0.86.2; some builds/configs say "Main model:" instead,
# so both are matched); grep it rather than trust the requested id. This is
# weaker than Codex's JSONL scan and weaker than Grok's billed modelUsage
# field — it is a self-reported banner from the same process being asked to
# prove its own identity, so it never certifies more than "unverified,
# banner-consistent."
BANNER=$(grep -iE '^(Main model|Model):' "$OUT" 2>/dev/null | head -1 || true)
if [ -n "$BANNER" ]; then
  echo "seat evidence: banner-consistent (unverified) — $BANNER"
else
  echo "seat evidence: NONE — no 'Main model:' banner found in aider output; requested 'ollama_chat/$MODEL'. Seat: unverified (Layer 0)."
fi

exit "$CODE"
