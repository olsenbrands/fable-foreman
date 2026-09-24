#!/bin/sh
# fable-foreman — definitive provider access check (the live half of Step 0).
#
#   access-check.sh <grok|codex|jev|all> [--consented] [--model <id>]
#
# probe.sh answers "installed? signed in?" for free. It cannot answer "will a
# dispatch actually run?", because the failures that matter — an exhausted
# Grok Build balance (HTTP 402), an expired session, a Codex quota window, a
# revoked OpenRouter key — only show on a real call. This script makes ONE
# minimal call per provider through the skill's own launchers and prints one
# verdict line per provider from a fixed vocabulary:
#
#   ACCESS <provider>: LIVE | SIGNED_OUT | ENV_MISMATCH | BALANCE_EXHAUSTED |
#                      AUTH_FAILED | RATE_LIMITED | KEY_REJECTED | NO_KEY |
#                      DISABLED | NOT_INSTALLED | FAILED(<reason>)
#
# Cost: Grok ~$0.007, Codex one tiny turn on the cheapest listed tier, Jev
# ~$0.000001. Grok and Codex pings are billable, so they run only when the
# probe-visible pre-approval flag exists or the caller passes --consented after
# the user agreed (SKILL.md Step 0 consent rule). Never prints credentials.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
WHAT="${1:-}"; shift 2>/dev/null || true
CONSENTED=0; PIN_MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --consented) CONSENTED=1 ;;
    --model) shift; PIN_MODEL="${1:-}" ;;
    *) echo "BLOCKED: unknown argument '$1'" >&2; exit 64 ;;
  esac
  shift
done
case "$WHAT" in grok|codex|jev|all) ;; *) echo "usage: access-check.sh <grok|codex|jev|all> [--consented] [--model <id>]" >&2; exit 64 ;; esac

FH="${FOREMAN_HOME:-$HOME/.foreman}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
# Read-only Grok reviewers refuse workdirs under /tmp (grok-dispatch.sh), so
# the ping lives under the foreman home, not the system temp dir.
WD="$FH/scratch/access-check/$STAMP-$$"
mkdir -p "$WD" || { echo "BLOCKED: cannot create $WD" >&2; exit 73; }
printf 'Reply with exactly: ok\n' > "$WD/ping.md"

approved() { # approved <provider>
  [ "$CONSENTED" = 1 ] && return 0
  case "$1" in
    grok) [ "${FOREMAN_GROK_PREAPPROVED:-}" = 1 ] || [ -f "$FH/grok-preapproved" ] ;;
    codex) [ "${FOREMAN_CODEX_PREAPPROVED:-}" = 1 ] || [ -f "$FH/codex-preapproved" ] ;;
  esac
}

check_grok() {
  if [ -n "${GROK_BIN:-}" ]; then GB="$GROK_BIN"
  elif command -v grok >/dev/null 2>&1; then GB=$(command -v grok)
  else GB="${GROK_HOME:-$HOME/.grok}/bin/grok"; fi
  [ -x "$GB" ] || { echo "ACCESS grok: NOT_INSTALLED"; return; }
  # Free sign-in check first: never pay to learn the user is signed out.
  "$GB" models > "$WD/grok-models.txt" 2>&1 &
  P=$!; I=0
  while kill -0 "$P" 2>/dev/null; do
    [ "$I" -ge 45 ] && { kill "$P" 2>/dev/null; sleep 2; kill -9 "$P" 2>/dev/null; echo "ACCESS grok: FAILED(models command timed out — network or sandbox; not evidence of absence)"; return; }
    sleep 1; I=$((I + 1))
  done
  if grep -q "not authenticated" "$WD/grok-models.txt"; then
    if [ -s "${GROK_HOME:-$HOME/.grok}/auth.json" ]; then
      echo "ACCESS grok: ENV_MISMATCH — credentials exist but this shell sees a signed-out CLI (sandboxed shell or different HOME/GROK_HOME). Re-run unsandboxed before concluding Grok is absent."
    else
      echo "ACCESS grok: SIGNED_OUT — the user runs 'grok login'"
    fi
    return
  fi
  grep -q "You are logged in" "$WD/grok-models.txt" || { echo "ACCESS grok: FAILED(no sign-in line from 'grok models': $(head -1 "$WD/grok-models.txt" | cut -c1-120))"; return; }
  M="$PIN_MODEL"
  if [ -z "$M" ]; then
    M=$(sed -n 's/^[[:space:]]*[*-][[:space:]]*\([A-Za-z0-9._-]*\).*/\1/p' "$WD/grok-models.txt" \
        | grep -E '^grok-[0-9]+(\.[0-9]+)*$' | sort -t- -k2 -V 2>/dev/null | tail -1)
  fi
  [ -n "$M" ] || M=$(sed -n 's/^Default model:[[:space:]]*//p' "$WD/grok-models.txt" | head -1)
  if ! approved grok; then
    echo "ACCESS grok: SIGNED_IN (capacity unproven) — live ping needs consent: re-run with --consented after the user agrees (~\$0.01)"
    return
  fi
  ENV_OUT=$(sh "$HERE/grok-dispatch.sh" "$WD/ping.md" "$M" low read-only "$WD/grok-ping.json" "$WD" 2>&1)
  RC=$?
  printf '%s\n' "$ENV_OUT" > "$WD/grok-envelope.txt"
  ACC=$(printf '%s\n' "$ENV_OUT" | sed -n 's/^GROK ACCESS: //p' | head -1)
  SEAT=$(printf '%s\n' "$ENV_OUT" | sed -n 's/^seat: //p' | head -1)
  COST=$(printf '%s\n' "$ENV_OUT" | sed -n 's/.*cost_usd=\([0-9.eE-]*\).*/\1/p' | head -1)
  if [ "$RC" = 0 ] && [ -z "$ACC" ] && [ -n "$SEAT" ]; then
    echo "ACCESS grok: LIVE — $M answered ($SEAT; cost_usd=${COST:-unavailable})"
  elif [ -n "$ACC" ]; then
    echo "ACCESS grok: $ACC"
  else
    echo "ACCESS grok: FAILED(exit $RC; envelope $WD/grok-envelope.txt)"
  fi
}

check_codex() {
  command -v codex >/dev/null 2>&1 || { echo "ACCESS codex: NOT_INSTALLED"; return; }
  if ! codex login status > "$WD/codex-login.txt" 2>&1; then
    # Only a clear "not logged in" is SIGNED_OUT; any other failure (sandbox,
    # renamed subcommand) is an environment problem, not absence.
    if grep -qiE "not logged in|logged out|no credentials|please log in" "$WD/codex-login.txt"; then
      echo "ACCESS codex: SIGNED_OUT — the user runs 'codex login'"
    else
      echo "ACCESS codex: FAILED(status command failed: $(head -1 "$WD/codex-login.txt" | cut -c1-120) — check for a sandboxed shell before concluding Codex is absent)"
    fi
    return
  fi
  M="$PIN_MODEL"
  MC="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  if [ -z "$M" ] && [ -s "$MC" ] && command -v python3 >/dev/null 2>&1; then
    # Cheapest tier by the provider's own positioning text, newest first.
    M=$(python3 - "$MC" <<'PYEOF' 2>/dev/null
import json, sys
ms = [m for m in json.load(open(sys.argv[1])).get("models", []) if m.get("visibility") in (None, "list")]
cheap = [m for m in ms if "affordable" in (m.get("description") or "").lower() and "older" not in (m.get("description") or "").lower()]
print((cheap or ms or [{}])[0].get("slug", ""))
PYEOF
)
  fi
  [ -n "$M" ] || { echo "ACCESS codex: FAILED(no model to ping — pass --model)"; return; }
  if ! approved codex; then
    echo "ACCESS codex: SIGNED_IN ($(head -1 "$WD/codex-login.txt")) — live ping needs consent: re-run with --consented"
    return
  fi
  ENV_OUT=$(sh "$HERE/codex-dispatch.sh" "$WD/ping.md" "$M" low read-only "$WD/codex-ping.jsonl" "$WD" 2>&1)
  RC=$?
  printf '%s\n' "$ENV_OUT" > "$WD/codex-envelope.txt"
  ACC=$(printf '%s\n' "$ENV_OUT" | sed -n 's/^CODEX ACCESS: //p' | head -1)
  if [ "$RC" = 0 ]; then
    echo "ACCESS codex: LIVE — $M answered (seat evidence per envelope: $(printf '%s\n' "$ENV_OUT" | sed -n 's/^seat evidence: //p' | cut -c1-80))"
  elif [ -n "$ACC" ]; then
    echo "ACCESS codex: $ACC"
  else
    echo "ACCESS codex: FAILED(exit $RC; stderr $WD/codex-ping.jsonl.stderr)"
  fi
}

check_jev() {
  command -v python3 >/dev/null 2>&1 || { echo "ACCESS jev: FAILED(python3 missing)"; return; }
  OUT=$(python3 "$HERE/jev-decide.py" check 2>&1)
  V=$(printf '%s\n' "$OUT" | sed -n 's/^jev access: //p' | tail -1)
  echo "ACCESS jev: ${V:-FAILED(no verdict)}"
}

echo "== foreman access check $STAMP (evidence: $WD) =="
case "$WHAT" in
  grok) check_grok ;;
  codex) check_codex ;;
  jev) check_jev ;;
  all) check_grok; check_codex; check_jev ;;
esac
echo "== ledger these lines verbatim; an access verdict is valid for this session until a dispatch reports otherwise =="
