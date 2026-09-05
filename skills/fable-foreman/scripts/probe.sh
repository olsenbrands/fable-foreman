#!/bin/sh
# fable-foreman — Step 0 deterministic probe.
# Emits the job-site capability table as plain text for the ledger.
# Read-only: makes no billable calls, changes no state, prints no secrets.
set -u

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
    echo "grok auth: NOT authenticated (no credentials file at $AUTH_FILE)"
  fi

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

# Local seat (Ollama + Aider). No consent gate — nothing is billed to another
# account — but the server must actually be reachable, and Aider is a
# separate required dependency (Ollama alone has no edit/tool-use loop).
OLLAMA_URL="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
if command -v ollama >/dev/null 2>&1; then
  echo "ollama: installed ($(command -v ollama))"
  OLLAMA_VERSION=$(ollama --version 2>&1) || OLLAMA_VERSION="UNKNOWN (version command failed)"
  echo "ollama version: $OLLAMA_VERSION"
  if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 3 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    echo "ollama server: reachable at $OLLAMA_URL"
    MODELS=$(ollama list 2>/dev/null | awk 'NR>1{print $1}' | tr '\n' ' ')
    if [ -n "$MODELS" ]; then
      echo "ollama models (pulled): $MODELS"
    else
      echo "ollama models (pulled): none found (or 'ollama list' failed)"
    fi
  else
    echo "ollama server: NOT reachable at $OLLAMA_URL — local dispatch will refuse"
  fi
else
  echo "ollama: NOT installed"
fi
if command -v aider >/dev/null 2>&1; then
  AIDER_VERSION=$(aider --version 2>&1) || AIDER_VERSION="UNKNOWN (version command failed)"
  echo "aider: installed ($(command -v aider)), version: $AIDER_VERSION"
else
  echo "aider: NOT installed — required for local dispatch (Ollama has no edit/tool-use loop on its own); pip install aider-chat"
fi
echo "local seat sandbox: none (OS-enforced) — git auto-commit is the only undo mechanism; scripts/ollama-dispatch.sh refuses workspace-write dispatch against a dirty tree"

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
    echo "ANTHROPIC_BASE_URL: set — $REDACTED (session is behind a gateway/splitter; full value withheld)"
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
