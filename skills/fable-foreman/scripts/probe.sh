#!/bin/sh
# fable-foreman — Step 0 deterministic probe.
# Emits the job-site capability table as plain text for the ledger.
# Read-only: makes no billable calls, changes no state, prints no secrets.
# Network: one free `grok models` call (bounded) to read the real sign-in state.
set -u

# run_bounded <seconds> <outfile> <cmd...> — POSIX stand-in for GNU timeout
# (absent on stock macOS). Returns the command's exit code, or 124 on timeout.
run_bounded() {
  _secs=$1; _out=$2; shift 2
  "$@" > "$_out" 2>&1 &
  _pid=$!
  _i=0
  while kill -0 "$_pid" 2>/dev/null; do
    if [ "$_i" -ge "$_secs" ]; then
      kill "$_pid" 2>/dev/null
      # A child that ignores SIGTERM must not hang the probe: 2s grace, then KILL.
      sleep 2; kill -9 "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null
      return 124
    fi
    sleep 1; _i=$((_i + 1))
  done
  wait "$_pid"
}
PROBE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/foreman-probe.XXXXXX") || PROBE_TMP=""
[ -n "$PROBE_TMP" ] && trap 'rm -rf "$PROBE_TMP"' EXIT INT TERM

echo "== foreman probe $(date -u +%Y-%m-%dT%H:%M:%SZ) =="

# Codex CLI
if command -v codex >/dev/null 2>&1; then
  echo "codex: installed ($(command -v codex))"
  if LOGIN_STATUS=$(codex login status 2>&1); then
    echo "codex auth: $LOGIN_STATUS"
  else
    if [ -s "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then
      echo "codex auth: credentials file present; billing mode UNKNOWN (status command failed)"
    else
      echo "codex auth: NOT authenticated"
    fi
  fi
  CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  if [ -f "$CFG" ]; then
    # First matching assignment only — profiles/overrides may change the
    # effective value; treat as a hint, not the resolved configuration.
    echo "codex config model (first assignment, unresolved): $(grep -E '^\s*model\s*=' "$CFG" | head -1 | sed 's/^[[:space:]]*//')"
    echo "codex config effort (first assignment, unresolved): $(grep -E '^\s*model_reasoning_effort\s*=' "$CFG" | head -1 | sed 's/^[[:space:]]*//')"
  fi
  # The account's model catalog, from the CLI's own cache (free, local).
  # Descriptions carry the provider's positioning ("Frontier…", "Workhorse…",
  # "Fast and affordable…") — map classes from THOSE, never from a name:
  # names are reused across generations with different positioning.
  MC="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  if [ -s "$MC" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$MC" <<'PYEOF' || echo "codex models (cached): cache present but unparsable"
import json, sys
d = json.load(open(sys.argv[1]))
print(f"codex models (cached {d.get('fetched_at','?')}, client {d.get('client_version','?')}) — positioning from the provider's own descriptions:")
for m in d.get("models", []):
    if m.get("visibility") not in (None, "list"):
        continue
    effs = "/".join(e.get("effort", "?") for e in m.get("supported_reasoning_levels", []))
    print(f"  {m.get('slug')}: \"{m.get('description','')}\" | efforts {effs} | ctx {m.get('context_window')}")
print("codex effort note: 'ultra' = automatic task delegation (a worker spawning workers) — the launcher refuses it (hard rail 1)")
PYEOF
  else
    echo "codex models (cached): no readable cache at $MC — discover tiers per codex-workers.md"
  fi
else
  echo "codex: NOT installed"
fi

# Codex consent posture. The default is the consent rule; a user may opt out of
# the per-session ask on THIS machine only, by creating ~/.foreman/codex-preapproved
# or exporting FOREMAN_CODEX_PREAPPROVED=1. No credential values are read or printed.
if [ "${FOREMAN_CODEX_PREAPPROVED:-}" = "1" ] || [ -f "${FOREMAN_HOME:-$HOME/.foreman}/codex-preapproved" ]; then
  echo "codex billing: PRE-APPROVED (user config) — consent ask skipped, budget step-down does not apply to Codex"
else
  echo "codex billing: consent rule applies — confirm with the user before the first billable Codex call (unless they asked for Codex this session)"
fi
# Grok standing pre-approval — same shape as Codex's, user-set only (2026-09-04).
# The flag file may hold a line "parallel: N" naming the fan-out ceiling (default 15).
if [ "${FOREMAN_GROK_PREAPPROVED:-}" = "1" ] || [ -f "${FOREMAN_HOME:-$HOME/.foreman}/grok-preapproved" ]; then
  GROK_PAR=$(grep -E '^parallel: *[0-9]+' "${FOREMAN_HOME:-$HOME/.foreman}/grok-preapproved" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)
  echo "grok billing: PRE-APPROVED (user config) — consent ask skipped, budget step-down does not apply to Grok; grok effort: lead judgment per dispatch (no-evidence prior: highest supported); parallel ceiling ${GROK_PAR:-15} (reported default, not a measured maximum)"
fi

# Grok CLI (xAI). Binary is normally at $HOME/.grok/bin/grok and may or may
# not also be on PATH; $GROK_HOME (default ~/.grok) governs where its config
# lives, so honor it for the binary fallback too.
GROK_HOME_DIR="${GROK_HOME:-$HOME/.grok}"
GROK_BIN_BAD=""
if [ -n "${GROK_BIN:-}" ]; then
  # Explicit override — grok-dispatch.sh honors the same variable first and, like
  # this probe, refuses rather than falling through to PATH when it is unusable.
  if [ ! -x "$GROK_BIN" ]; then
    GROK_BIN_BAD="$GROK_BIN"
    GROK_BIN=""
  fi
elif command -v grok >/dev/null 2>&1; then
  GROK_BIN=$(command -v grok)
elif [ -x "$GROK_HOME_DIR/bin/grok" ]; then
  GROK_BIN="$GROK_HOME_DIR/bin/grok"
else
  GROK_BIN=""
fi

if [ -n "$GROK_BIN_BAD" ]; then
  echo "grok: GROK_BIN is set but not executable ($GROK_BIN_BAD) — the launcher will refuse (exit 69); unset it or fix it"
elif [ -n "$GROK_BIN" ]; then
  echo "grok: installed ($GROK_BIN)"
  GROK_VERSION=$("$GROK_BIN" --version 2>&1) || GROK_VERSION="UNKNOWN (version command failed)"
  echo "grok version: $GROK_VERSION"

  AUTH_FILE="$GROK_HOME_DIR/auth.json"
  if [ -s "$AUTH_FILE" ]; then
    # Presence only — never print token/key values. auth_mode is non-secret
    # metadata (e.g. "oidc"); the pattern is anchored to that literal key
    # name so it can never match the adjacent "key"/"refresh_token" lines
    # that hold real credentials. jq is used when available for accuracy and
    # falls back to the same anchored grep otherwise.
    if command -v jq >/dev/null 2>&1; then
      AUTH_MODE=$(jq -r '[.[].auth_mode][0] // empty' "$AUTH_FILE" 2>/dev/null) || AUTH_MODE=""
    else
      AUTH_MODE=$(grep -o '"auth_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$AUTH_FILE" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/') || AUTH_MODE=""
    fi
    if [ -n "$AUTH_MODE" ]; then
      echo "grok auth: credentials file present (mode: $AUTH_MODE)"
    else
      echo "grok auth: credentials file present (mode unknown)"
    fi
  else
    echo "grok auth: no credentials file at $AUTH_FILE"
  fi

  # Live sign-in check — free (lists models; spends nothing). Two traps this
  # closes (2026-09-23): `grok models` exits 0 EVEN WHEN SIGNED OUT, printing a
  # built-in fallback list, so exit status proves nothing; and a sandboxed or
  # HOME-redirected shell can make a signed-in user look signed out. Being
  # signed in also does NOT prove capacity: an exhausted Grok Build balance
  # (HTTP 402) only shows on a billable call — see scripts/access-check.sh.
  GROK_ACCESS="UNDETERMINED"
  GROK_NEXT=""
  if [ -n "$PROBE_TMP" ]; then
    run_bounded "${FOREMAN_PROBE_TIMEOUT:-45}" "$PROBE_TMP/grok-models" "$GROK_BIN" models
    GM_RC=$?
    if grep -q "You are logged in" "$PROBE_TMP/grok-models" 2>/dev/null; then
      GROK_ACCESS="SIGNED-IN"
      GROK_NEXT="capacity unproven until one billable ping: scripts/access-check.sh grok (~\$0.01)"
      GLIVE=$(sed -n 's/^[[:space:]]*[*-][[:space:]]*\([A-Za-z0-9._-]*\).*/\1/p' "$PROBE_TMP/grok-models" | tr '\n' ' ')
      GDEF=$(sed -n 's/^Default model:[[:space:]]*//p' "$PROBE_TMP/grok-models" | head -1)
      echo "grok models (live, this account): ${GLIVE% } (CLI default: ${GDEF:-unknown})"
      # Newest base model = highest grok-X.Y with no suffix; suffixed ids are variants.
      GNEW=$(printf '%s\n' $GLIVE | grep -E '^grok-[0-9]+(\.[0-9]+)*$' | sort -t- -k2 -V 2>/dev/null | tail -1)
      [ -n "$GNEW" ] && echo "grok newest base model: $GNEW (variants such as *-build-fast are priced separately — model-matrix.md)"
    elif grep -q "not authenticated" "$PROBE_TMP/grok-models" 2>/dev/null; then
      if [ -s "$AUTH_FILE" ]; then
        GROK_ACCESS="ENV-MISMATCH"
        GROK_NEXT="credentials exist at $AUTH_FILE but the CLI reports signed-out FROM THIS SHELL — usually a sandboxed shell (no network / no ~/.grok access) or a different HOME/GROK_HOME. Re-run this probe unsandboxed before concluding Grok is absent; if it persists, the user runs 'grok login'"
      else
        GROK_ACCESS="SIGNED-OUT"
        GROK_NEXT="Grok seats unavailable this session; the user may run 'grok login' (never start it yourself). The model list the CLI prints when signed out is a built-in fallback, not the account's"
      fi
    elif [ "$GM_RC" = 124 ]; then
      GROK_NEXT="'grok models' timed out after ${FOREMAN_PROBE_TIMEOUT:-45}s — likely network or sandbox; not evidence of absence"
    else
      GROK_NEXT="'grok models' gave no sign-in line (exit $GM_RC): $(head -1 "$PROBE_TMP/grok-models" 2>/dev/null | cut -c1-160)"
    fi
  fi
  echo "grok access: $GROK_ACCESS${GROK_NEXT:+ — $GROK_NEXT}"

  # Model ids from the local cache only — never calls the API. Structural
  # extraction (which JSON key is a model id vs. a nested field like
  # "info"/"laziness_detector") needs a real parser to stay correct, so this
  # only reports ids when jq is available and admits it otherwise rather
  # than risk emitting wrong ids from a regex guess.
  MODELS_CACHE="$GROK_HOME_DIR/models_cache.json"
  if [ -s "$MODELS_CACHE" ]; then
    if command -v jq >/dev/null 2>&1; then
      MODEL_IDS=$(jq -r '(.models | keys) // [] | join(", ")' "$MODELS_CACHE" 2>/dev/null) || MODEL_IDS=""
    else
      MODEL_IDS=""
    fi
    if [ -n "$MODEL_IDS" ]; then
      echo "grok models (cached): $MODEL_IDS"
    else
      echo "grok models (cached): cache file present but ids not parsed (jq unavailable or unexpected format)"
    fi
  else
    echo "grok models (cached): no local cache at $MODELS_CACHE"
  fi
else
  echo "grok: NOT installed"
fi
echo "grok sandbox: default is OFF — dispatches must always pass an explicit sandbox profile"

# TypeSafe Jev (optional structured-decision layer — references/jev.md).
# Metadata only: opt-in flag and key PRESENCE; validity needs access-check.sh.
JEV_FLAG="${FOREMAN_HOME:-$HOME/.foreman}/jev-enabled"
if [ "${FOREMAN_JEV:-}" = "1" ] || [ -f "$JEV_FLAG" ]; then
  JEV_SRC="none found"
  if [ -n "${TYPESAFE_API_KEY:-}" ]; then JEV_SRC="env TYPESAFE_API_KEY"
  elif [ -n "${OPENROUTER_API_KEY:-}" ]; then JEV_SRC="env OPENROUTER_API_KEY"
  else
    JEV_SVC=$(sed -n 's/^keychain-service:[[:space:]]*//p' "$JEV_FLAG" 2>/dev/null | head -1)
    if [ -n "$JEV_SVC" ] && command -v security >/dev/null 2>&1; then
      if security find-generic-password -s "$JEV_SVC" >/dev/null 2>&1; then
        JEV_SRC="keychain service '$JEV_SVC' (presence only)"
      else
        JEV_SRC="keychain service '$JEV_SVC' named but not found"
      fi
    fi
  fi
  echo "jev: opted in (user config) — key: $JEV_SRC; validity unproven until scripts/access-check.sh jev (free key check + ~\$0.000001 decision)"
else
  echo "jev: not opted in — optional; the skill runs identically without it (references/jev.md)"
fi

# Native-transport (claudemix-style splitter) facts — reported separately;
# presence of parts does not mean the transport is routable (setup-runbook.md).
if command -v cliproxyapi >/dev/null 2>&1; then
  echo "cliproxyapi binary: present ($(command -v cliproxyapi))"
else
  echo "cliproxyapi binary: absent"
fi
FOUND_CONF="absent"
for P in /opt/homebrew/etc/cliproxyapi.conf /usr/local/etc/cliproxyapi.conf; do
  [ -f "$P" ] && FOUND_CONF="present ($P)"
done
echo "cliproxyapi config: $FOUND_CONF"
echo "native transport: routable only if binary+config+auth+splitter all verified live (setup-runbook.md Part B); this probe checks presence only"

# Gateway detection — redacted to scheme://host:port; URLs can carry tokens
# and this output is pasted into durable ledgers.
if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
  # scheme = letter followed by letters/digits/+/-/. per RFC 3986; authority
  # ends at /, ?, or #; userinfo (anything@) stripped. Anything that doesn't
  # parse as scheme://... is withheld entirely rather than echoed raw.
  # Regex guard (not a glob — globs let 'h$://' through): only values whose
  # scheme strictly matches RFC 3986 are redacted-and-shown; everything else
  # is withheld entirely. The grep and sed use the same charset, so any value
  # grep admits, sed will rewrite — no fall-through printing the raw value.
  if printf '%s' "$ANTHROPIC_BASE_URL" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then
    REDACTED=$(printf '%s' "$ANTHROPIC_BASE_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#@]*@)?([^/?#]*).*#\1\3#')
    case "$REDACTED" in
      https://api.anthropic.com|https://api.anthropic.com:443)
        echo "ANTHROPIC_BASE_URL: set to the default Anthropic endpoint ($REDACTED) — direct connection" ;;
      *)
        echo "ANTHROPIC_BASE_URL: set — $REDACTED (session is behind a gateway/splitter; full value withheld)" ;;
    esac
  else
    echo "ANTHROPIC_BASE_URL: set — unparseable form, value withheld (session may be behind a gateway/splitter)"
  fi
else
  echo "ANTHROPIC_BASE_URL: unset (direct Anthropic connection)"
fi

# Git baseline for the ledger — a failed status is reported as FAILED, never
# rendered as a clean tree.
if git rev-parse --git-dir >/dev/null 2>&1; then
  HASH=$(git rev-parse -q --verify --short HEAD 2>/dev/null) || HASH=""
  [ -n "$HASH" ] || HASH="unborn (no commits yet)"
  if STATUS=$(git status --porcelain 2>/dev/null); then
    DIRTY=$(printf '%s' "$STATUS" | grep -c . || true)
    echo "git: repo — HEAD $HASH, dirty files: $DIRTY"
  else
    echo "git: repo — HEAD $HASH, dirty files: STATUS FAILED (do not treat as clean)"
  fi
else
  echo "git: not a repository (ledger baseline will note this)"
fi

echo "== probe complete. Agent-tool and shell-mode facts come from the harness, not this script =="
