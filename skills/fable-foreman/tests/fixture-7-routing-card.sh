#!/bin/sh
# Fixture 7 (v0.6) — routing-card.py: defaults, consent, fail-closed parsing, recon memory,
# session memory, grouped plain-language question. Synthetic probe output in a mktemp
# FOREMAN_HOME; no provider CLI is called.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
RC="$HERE/../scripts/routing-card.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/foreman-fx7.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
FH="$TMP/fh"; mkdir -p "$FH"

probe() { # probe <file> <codex: up|down|noconsent|nomodels> <grok-state> <extra grok models>
  {
    case "$2" in down) echo "codex auth: NOT authenticated" ;; *) echo "codex auth: Logged in using ChatGPT" ;; esac
    [ "$2" = noconsent ] || echo "codex billing: PRE-APPROVED (user config)"
    echo "grok billing: PRE-APPROVED (user config)"
    if [ "$2" != nomodels ]; then
      echo '  gpt-6-astra: "Frontier" | efforts low/max | ctx 272000'
      echo '  gpt-6-sol: "Workhorse" | efforts low/max | ctx 272000'
      echo '  gpt-6-luna: "Fast and affordable" | efforts low/max | ctx 272000'
    fi
    echo "grok models (live, this account): grok-4.7 grok-4.6 $4 (CLI default: grok-4.7)"
    echo "grok access: $3 — stub"
    echo "jev: opted in (user config) — key: stub"
  } > "$1"
}
run() { env FOREMAN_HOME="$FH" FOREMAN_TODAY="${DAY:-2026-09-24}" python3 "$RC" "$@"; }

probe "$TMP/p1" up SIGNED-IN ""
run --probe-output "$TMP/p1" --project /proj > "$TMP/c1"
assert_contains "7.1 Luna is the mechanical default" "$TMP/c1" "**codex:gpt-6-luna @ low or medium** | claude:haiku"
assert_contains "7.1 precedence rule printed" "$TMP/c1" "**Precedence:** user constraints"
assert_contains "7.1 judgment prior for everyday coding" "$TMP/c1" 'start from **grok-4.7**'
assert_contains "7.1 one grouped plain-language question with a recommendation" "$TMP/c1" "For everyday coding tickets: Grok 4.7 — cheapest per ticket"
assert_contains "7.1 recommendation stated" "$TMP/c1" "I'd suggest Grok 4.7."
assert_contains "7.1 overhead is not a reason" "$TMP/c1" '"transport overhead"'
assert_contains "7.1 verifier pinned to opus" "$TMP/c1" '**claude:opus @ high** — Agent tool: subagent_type foreman-verifier, model "opus"'
assert_contains "7.1 off-family review defaults to Grok 4.6; high-risk escalation stays non-premium" "$TMP/c1" "run Grok 4.6 at high AND a GPT-6 Sol read-only review"
assert_contains "7.1 hard coding judgment prior is Opus, not Astra" "$TMP/c1" 'start from **opus**'
assert_contains "7.1 Astra shown as premium, unavailable" "$TMP/c1" "premium — needs the user's double approval this session"
assert_contains "7.1 question mentions premium only as opt-in" "$TMP/c1" "are used only if you ask for them"
assert_absent  "7.1 Astra never offered as a normal option in the question" "$TMP/c1" "I'd suggest GPT-6 Astra"
assert_file "7.1 card cached" "$FH/routing-card.md"

probe "$TMP/p2" down SIGNED-IN ""
run --probe-output "$TMP/p2" > "$TMP/c2"
assert_contains "7.2 codex down: Haiku, default named" "$TMP/c2" "**claude:haiku** *(default codex:gpt-6-luna @ low or medium: not signed in)*"

probe "$TMP/p2b" noconsent SIGNED-IN ""
run --probe-output "$TMP/p2b" > "$TMP/c2b"
assert_contains "7.2b no Codex consent: Luna needs consent, Haiku meanwhile" "$TMP/c2b" "needs the user's consent"
assert_contains "7.2b consent folded into the one question" "$TMP/c2b" "May I use Codex (it spends your Codex plan)"
run --probe-output "$TMP/p2b" --consented codex > "$TMP/c2c"
assert_contains "7.2c in-session consent restores Luna" "$TMP/c2c" "**codex:gpt-6-luna @ low or medium** | claude:haiku"

probe "$TMP/p3" nomodels SIGNED-IN ""
run --probe-output "$TMP/p3" > "$TMP/c3"
assert_contains "7.3 unparsed Codex model list fails closed" "$TMP/c3" "model list unparsed"

probe "$TMP/p4" up SIGNED-IN "grok-4.8"
run --probe-output "$TMP/p4" > "$TMP/c4"
assert_contains "7.4 unknown model flagged" "$TMP/c4" "NEW MODELS — recon required before routing to them:** grok:grok-4.8"
run recon-record grok grok-4.8 ignore - 7 no public evidence found > /dev/null
run --probe-output "$TMP/p4" > "$TMP/c4b"
assert_contains "7.4 an 'ignore' verdict clears the flag (no re-research)" "$TMP/c4b" "No unevaluated models on this machine."
run recon-record grok grok-4.8 use standard-coding 14 cheaper at equal CA > /dev/null
run --probe-output "$TMP/p4" > "$TMP/c4c"
assert_contains "7.4 a 'use' verdict becomes the session suggestion" "$TMP/c4c" 'start from **grok-4.8**'
DAY=2026-10-20 run --probe-output "$TMP/p4" > "$TMP/c4d"
assert_contains "7.4 expired verdict flags the model again" "$TMP/c4d" "grok:grok-4.8"
rm -f "$FH/recon/models.json"

DAY=2026-10-30 run --probe-output "$TMP/p1" > "$TMP/c5"
assert_contains "7.5 old suggestions flagged STALE" "$TMP/c5" "**STALE**"
DAY=2026-10-30 run recon-record codex gpt-6-sol use - 14 rechecked > /dev/null
DAY=2026-10-30 run --probe-output "$TMP/p1" > "$TMP/c5b"
assert_contains "7.5 recon done today stops a repeat" "$TMP/c5b" "recon already done today — do not repeat it"
rm -f "$FH/recon/models.json"

probe "$TMP/p6" up ENV-MISMATCH ""
run --probe-output "$TMP/p6" > "$TMP/c6"
assert_contains "7.6 env-mismatch Grok is unknown, not absent" "$TMP/c6" "UNKNOWN from this shell"

run remember standard-coding gpt-6-sol --session S1 --project /proj > /dev/null
run --probe-output "$TMP/p1" --session S1 --project /proj > "$TMP/c7"
assert_contains "7.7 same session: apply the answer, do not re-ask" "$TMP/c7" "Chosen this session: gpt-6-sol — apply it; do not ask again."
run --probe-output "$TMP/p1" --session S2 --project /proj > "$TMP/c7b"
assert_contains "7.7 next session: offered back" "$TMP/c7b" "you chose gpt-6-sol for everyday coding tickets; keep that?"
run --probe-output "$TMP/p1" --session S3 --project /other > "$TMP/c7c"
assert_absent "7.7 other project: not offered" "$TMP/c7c" "you chose gpt-6-sol"
DAY=2026-11-30 run --probe-output "$TMP/p1" --session S4 --project /proj > "$TMP/c7d"
assert_absent "7.7 expired answer: not offered" "$TMP/c7d" "you chose gpt-6-sol"
run remember standard-coding gpt-9 --session S1 > /dev/null 2>&1; assert_eq "7.7 invalid choice refused" "64" "$?"
run remember mechanical haiku --session S1 > /dev/null 2>&1; assert_eq "7.7 settled job cannot be 'remembered'" "64" "$?"

printf 'ACCESS grok: BALANCE_EXHAUSTED — stub\nACCESS codex: LIVE — stub\n' > "$TMP/a1"
run --probe-output "$TMP/p1" --access "$TMP/a1" > "$TMP/c8"
assert_contains "7.8 dead Grok leaves the pool" "$TMP/c8" "| grok | UNAVAILABLE — access-check: BALANCE_EXHAUSTED |"
assert_contains "7.8 proven Codex shown as proven" "$TMP/c8" "| codex | proven live"
assert_contains "7.8 off-family review falls back to Sol, never Astra" "$TMP/c8" "**codex:gpt-6-sol @ medium, read-only** *(default grok:grok-4.6"

run approve-premium gpt-6-astra --session P1 > /dev/null 2>&1; assert_eq "7.9 premium approval without the confirming yes refused" "64" "$?"
run remember hard-coding gpt-6-astra --session P1 > /dev/null 2>&1; assert_eq "7.9 cannot pick Astra before double approval" "64" "$?"
run approve-premium gpt-6-astra --session P1 --confirmed > /dev/null
run --probe-output "$TMP/p1" --session P1 > "$TMP/c9"
assert_contains "7.9 double-approved Astra available this session" "$TMP/c9" "\`gpt-6-astra\` — Codex frontier tier, ~5x GPT-6 Sol's price per token: **approved this session**"
run remember hard-coding gpt-6-astra --session P1 > /dev/null; assert_eq "7.9 approved Astra can be chosen" "0" "$?"
run --probe-output "$TMP/p1" --session P2 > "$TMP/c9b"
assert_contains "7.9 approval does not carry into another session" "$TMP/c9b" "not approved — never dispatch, never a fallback"
assert_absent "7.9 premium choice never offered back next session" "$TMP/c9b" "you chose gpt-6-astra"
run approve-premium sonnet --session P1 --confirmed > /dev/null 2>&1; assert_eq "7.9 non-premium model refused by approve-premium" "64" "$?"

# The skill loader substitutes $0, $1, ... in SKILL.md with invocation arguments
# (observed 2026-09-24: "~$0.0002" rendered as "~<args>.0002"). Keep SKILL.md free of them.
if grep -nE '\$[0-9]' "$HERE/../SKILL.md" > "$TMP/dollars"; then fail "7.10 SKILL.md has \$N argument placeholders: $(head -1 "$TMP/dollars")"; else pass "7.10 SKILL.md has no \$N argument placeholders"; fi

finish "fixture 7 (routing card)"
