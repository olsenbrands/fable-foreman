#!/bin/sh
# Fixture 7 (v0.7) — routing-card.py: defaults, consent, fail-closed parsing, recon memory,
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
      echo '  gpt-6.1-sol: "Latest workhorse" | efforts low/max | ctx 500000'
      echo '  gpt-6-astra: "Frontier" | efforts low/max | ctx 272000'
      echo '  gpt-6-sol: "Previous generation workhorse" | efforts low/max | ctx 272000'
      echo '  gpt-6-luna: "Fast and affordable" | efforts low/max | ctx 272000'
      echo '  gpt-5.6-sol: "Older generation workhorse" | efforts low/max | ctx 272000'
      for X in ${CODEX_EXTRA:-}; do echo "  $X: \"stub\" | efforts low/max | ctx 272000"; done
    fi
    echo "grok models (live, this account): grok-4.7 grok-4.6 $4 (CLI default: grok-4.7)"
    echo "grok access: $3 — stub"
    echo "jev: opted in (user config) — key: stub"
  } > "$1"
}
run() { env FOREMAN_HOME="$FH" FOREMAN_TODAY="${DAY:-2026-10-22}" python3 "$RC" "$@"; }

probe "$TMP/p1" up SIGNED-IN ""
run --probe-output "$TMP/p1" --project /proj > "$TMP/c1"
assert_contains "7.1 Luna is the mechanical default" "$TMP/c1" "**codex:gpt-6-luna (newest luna) @ low or medium** | claude:haiku"
assert_contains "7.1 precedence rule printed" "$TMP/c1" "**Precedence:** user constraints"
assert_contains "7.1 judgment prior for everyday coding" "$TMP/c1" 'start from **grok-4.7**'
assert_contains "7.1 one grouped plain-language question with a recommendation" "$TMP/c1" "For everyday coding tickets: grok-4.7 — cheapest per ticket"
assert_contains "7.1 recommendation stated" "$TMP/c1" "I'd suggest grok-4.7."
assert_contains "7.1 overhead is not a reason" "$TMP/c1" '"transport overhead"'
assert_contains "7.1 verifier pinned to opus" "$TMP/c1" '**claude:opus @ high** — Agent tool: subagent_type foreman-verifier, model "opus"'
assert_contains "7.1 off-family review defaults to the newest Grok; escalation stays non-premium" "$TMP/c1" "**grok:grok-4.7 (newest base) @ medium, read-only**"
assert_contains "7.1 escalation never premium" "$TMP/c1" "Never escalate to a premium model on your own."
assert_contains "7.1 hard coding judgment prior is Opus, not Astra" "$TMP/c1" 'start from **opus**'
assert_contains "7.1 Astra shown as premium, not approved" "$TMP/c1" "(here: gpt-6-astra)"
assert_contains "7.1 premium never an option" "$TMP/c1" "never dispatch, never a fallback, never an option"
assert_contains "7.1 question mentions premium only as opt-in" "$TMP/c1" "are never picked automatically"
assert_absent  "7.1 Astra not listed in any close call" "$TMP/c1" "- codex:gpt-6-astra"
assert_contains "7.1 newest Sol used, not the previous generation" "$TMP/c1" "codex:gpt-6.1-sol (newest sol)"
assert_absent  "7.1 previous-generation Sol never a seat" "$TMP/c1" "codex:gpt-6-sol ("
assert_contains "7.1 previous generation listed as superseded" "$TMP/c1" "never route to them: codex:gpt-5.6-sol, codex:gpt-6-sol"
assert_absent  "7.1 Astra never offered as a normal option in the question" "$TMP/c1" "I'd suggest GPT-6 Astra"
assert_file "7.1 card cached" "$FH/routing-card.md"

probe "$TMP/p2" down SIGNED-IN ""
run --probe-output "$TMP/p2" > "$TMP/c2"
assert_contains "7.2 codex down: Haiku, default named" "$TMP/c2" "**claude:haiku** *(default codex:gpt-6-luna (newest luna) @ low or medium: not signed in)*"

probe "$TMP/p2b" noconsent SIGNED-IN ""
run --probe-output "$TMP/p2b" > "$TMP/c2b"
assert_contains "7.2b no Codex consent: Luna needs consent, Haiku meanwhile" "$TMP/c2b" "needs the user's consent"
assert_contains "7.2b consent folded into the one question" "$TMP/c2b" "May I use Codex (it spends your Codex plan)"
run --probe-output "$TMP/p2b" --consented codex > "$TMP/c2c"
assert_contains "7.2c in-session consent restores Luna" "$TMP/c2c" "**codex:gpt-6-luna (newest luna) @ low or medium** | claude:haiku"

probe "$TMP/p3" nomodels SIGNED-IN ""
run --probe-output "$TMP/p3" > "$TMP/c3"
assert_contains "7.3 unparsed Codex model list fails closed" "$TMP/c3" "model list unparsed"

probe "$TMP/p4" up SIGNED-IN "grok-4.8"
run --probe-output "$TMP/p4" > "$TMP/c4"
assert_contains "7.4 newer release in a known line is used automatically" "$TMP/c4" "used automatically:** grok:grok-4.8 (newest base)"
assert_contains "7.4 the successor becomes the seat" "$TMP/c4" 'start from **grok-4.8**'
assert_contains "7.4 ping before first dispatch" "$TMP/c4" "ping it once"
assert_contains "7.4 the old release is superseded" "$TMP/c4" "grok:grok-4.7"
probe "$TMP/p4n" up SIGNED-IN ""
CODEX_EXTRA="gpt-7-nova" run --probe-output "$TMP/p4n" > /dev/null
CODEX_EXTRA="gpt-7-nova" probe "$TMP/p4n" up SIGNED-IN ""
run --probe-output "$TMP/p4n" > "$TMP/c4n"
assert_contains "7.4 an unknown model LINE needs recon" "$TMP/c4n" "NEW MODEL LINES — recon required before routing to them:** codex:gpt-7-nova"
run recon-record codex gpt-7-nova ignore - 7 no public evidence found > /dev/null
run --probe-output "$TMP/p4n" > "$TMP/c4b"
assert_contains "7.4 an 'ignore' verdict clears the flag (no re-research)" "$TMP/c4b" "No unevaluated model lines on this machine."
run recon-record codex gpt-7-nova use standard-coding 14 cheaper at equal CA > /dev/null
run --probe-output "$TMP/p4n" > "$TMP/c4c"
assert_contains "7.4 a 'use' verdict becomes the session suggestion" "$TMP/c4c" 'start from **gpt-7-nova**'
DAY=2026-11-20 run --probe-output "$TMP/p4n" > "$TMP/c4d"
assert_contains "7.4 expired verdict flags the line again" "$TMP/c4d" "recon required before routing to them:** codex:gpt-7-nova"
rm -f "$FH/recon/models.json"
CODEX_EXTRA="gpt-6.2-luna gpt-6.1-astra" probe "$TMP/p4l" up SIGNED-IN ""
run --probe-output "$TMP/p4l" > "$TMP/c4l"
assert_contains "7.4 a newer Luna becomes the mechanical default" "$TMP/c4l" "**codex:gpt-6.2-luna (newest luna) @ low or medium**"
assert_contains "7.4 a newer Astra is still premium" "$TMP/c4l" "(here: gpt-6.1-astra, gpt-6-astra)"
assert_absent  "7.4 newer Astra never offered as a successor seat" "$TMP/c4l" "codex:gpt-6.1-astra (newest astra)"

DAY=2026-11-10 run --probe-output "$TMP/p1" > "$TMP/c5"
assert_contains "7.5 old suggestions flagged STALE" "$TMP/c5" "**STALE**"
DAY=2026-11-10 run recon-record codex gpt-6.1-sol use - 14 rechecked > /dev/null
DAY=2026-11-10 run --probe-output "$TMP/p1" > "$TMP/c5b"
assert_contains "7.5 recon done today stops a repeat" "$TMP/c5b" "recon already done today — do not repeat it"
rm -f "$FH/recon/models.json"

probe "$TMP/p6" up ENV-MISMATCH ""
run --probe-output "$TMP/p6" > "$TMP/c6"
assert_contains "7.6 env-mismatch Grok is unknown, not absent" "$TMP/c6" "UNKNOWN from this shell"

run remember standard-coding gpt-6.1-sol --session S1 --project /proj > /dev/null
run --probe-output "$TMP/p1" --session S1 --project /proj > "$TMP/c7"
assert_contains "7.7 same session: apply the answer, do not re-ask" "$TMP/c7" "Chosen this session: gpt-6.1-sol — apply it; do not ask again."
run --probe-output "$TMP/p1" --session S2 --project /proj > "$TMP/c7b"
assert_contains "7.7 next session: offered back" "$TMP/c7b" "you chose gpt-6.1-sol for everyday coding tickets; keep that?"
run --probe-output "$TMP/p1" --session S3 --project /other > "$TMP/c7c"
assert_absent "7.7 other project: not offered" "$TMP/c7c" "you chose gpt-6.1-sol"
DAY=2026-12-30 run --probe-output "$TMP/p1" --session S4 --project /proj > "$TMP/c7d"
assert_absent "7.7 expired answer: not offered" "$TMP/c7d" "you chose gpt-6.1-sol"
run remember standard-coding gpt-6-sol --session S5 --project /proj > /dev/null
run --probe-output "$TMP/p1" --session S5 --project /proj > "$TMP/c7e"
assert_contains "7.7 an answer naming an older Sol maps to the newest Sol" "$TMP/c7e" "Chosen this session: gpt-6.1-sol (newest sol; answer named gpt-6-sol)"
run remember standard-coding gpt-9 --session S1 > /dev/null 2>&1; assert_eq "7.7 invalid choice refused" "64" "$?"
run remember mechanical haiku --session S1 > /dev/null 2>&1; assert_eq "7.7 settled job cannot be 'remembered'" "64" "$?"

printf 'ACCESS grok: BALANCE_EXHAUSTED — stub\nACCESS codex: LIVE — stub\n' > "$TMP/a1"
run --probe-output "$TMP/p1" --access "$TMP/a1" > "$TMP/c8"
assert_contains "7.8 dead Grok leaves the pool" "$TMP/c8" "| grok | UNAVAILABLE — access-check: BALANCE_EXHAUSTED |"
assert_contains "7.8 proven Codex shown as proven" "$TMP/c8" "| codex | proven live"
assert_contains "7.8 off-family review falls back to Sol, never Astra" "$TMP/c8" "**codex:gpt-6.1-sol (newest sol) @ medium, read-only** *(default grok:grok-4.7 (newest base)"

run approve-premium gpt-6-astra --session P1 > /dev/null 2>&1; assert_eq "7.9 premium approval without the confirming yes refused" "64" "$?"
run remember hard-coding gpt-6-astra --session P1 > /dev/null 2>&1; assert_eq "7.9 cannot pick Astra before double approval" "64" "$?"
run approve-premium gpt-6-astra --session P1 --confirmed > /dev/null
run --probe-output "$TMP/p1" --session P1 > "$TMP/c9"
assert_contains "7.9 double-approved Astra available this session" "$TMP/c9" "**approved this session: gpt-6-astra**"
run remember hard-coding gpt-6-astra --session P1 > /dev/null; assert_eq "7.9 approved Astra can be chosen" "0" "$?"
run --probe-output "$TMP/p1" --session P2 > "$TMP/c9b"
assert_contains "7.9 approval does not carry into another session" "$TMP/c9b" "not approved — never dispatch, never a fallback"
assert_absent "7.9 premium choice never offered back next session" "$TMP/c9b" "you chose gpt-6-astra"
run approve-premium sonnet --session P1 --confirmed > /dev/null 2>&1; assert_eq "7.9 non-premium model refused by approve-premium" "64" "$?"
run approve-premium gpt-6.1-sol --session P1 --confirmed > /dev/null 2>&1; assert_eq "7.9 Sol is not premium" "64" "$?"
run remember hard-coding gpt-6.1-astra --session P3 > /dev/null 2>&1; assert_eq "7.9 a newer Astra is premium too" "64" "$?"

# 7.11 the Codex launcher refuses any Astra-line id without the session approval, before any spend
LCH="$HERE/../scripts/codex-dispatch.sh"; echo t > "$TMP/t.md"
for M in gpt-6-astra gpt-6.1-astra gpt-7-astra; do
  env -u FOREMAN_PREMIUM_APPROVED sh "$LCH" "$TMP/t.md" "$M" low read-only "$TMP/o.jsonl" "$TMP" > "$TMP/l.out" 2>&1
  assert_eq "7.11 launcher refuses $M without approval" "64" "$?"
done
assert_contains "7.11 refusal names the premium rule" "$TMP/l.out" "premium seat"

# 7.12 model_lines.py: numeric version order, variants, hidden entries, broken catalogs
MLP="$HERE/../scripts/model_lines.py"
assert_eq "7.12 6.10 beats 6.9" "gpt-6.10-sol" "$(python3 "$MLP" resolve codex sol --models gpt-6.9-sol,gpt-6.10-sol,gpt-6-sol)"
assert_eq "7.12 grok 4.10 beats 4.9; variants never chosen" "grok-4.10" "$(python3 "$MLP" resolve grok base --models grok-4.9,grok-4.10,grok-4.11-build-fast)"
python3 "$MLP" resolve codex nova --models gpt-6.1-sol > /dev/null 2>&1; assert_eq "7.12 absent line exits 3" "3" "$?"
mkdir -p "$TMP/cx"; printf '{"models":[{"slug":"gpt-6.1-sol","visibility":"list"},{"slug":"gpt-6.2-sol","visibility":"hide"},{"slug":"gpt-6-sol"}]}' > "$TMP/cx/models_cache.json"
assert_eq "7.12 hidden newer entry ignored" "gpt-6.1-sol" "$(CODEX_HOME="$TMP/cx" python3 "$MLP" resolve codex sol)"
printf 'not json' > "$TMP/cx/models_cache.json"
CODEX_HOME="$TMP/cx" python3 "$MLP" resolve codex sol > /dev/null 2>&1; assert_eq "7.12 broken catalog: clean miss, no crash" "3" "$?"
assert_contains_str() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (got [$3])" ;; esac; }
assert_contains_str "7.12 Astra resolves but is marked premium" "PREMIUM" "$(python3 "$MLP" resolve codex astra --models gpt-6-astra,gpt-6.1-sol)"

# 7.13 review findings (2026-10-22): remembered/recon choices can never bring back a superseded or unavailable model
run remember standard-coding gpt-6.1-sol --session R1 > /dev/null
sed '/gpt-.*-sol:/d' "$TMP/p1" > "$TMP/p-nosol"
run --probe-output "$TMP/p-nosol" --session R1 > "$TMP/c13a"
assert_contains "7.13 a remembered seat that is gone is not applied" "$TMP/c13a" "not usable right now"
assert_absent  "7.13 ...and never 'apply it'" "$TMP/c13a" "Chosen this session: gpt-6.1-sol — apply it"
run recon-record grok grok-4.6 use off-family-review,standard-coding 7 synthetic > /dev/null
run --probe-output "$TMP/p1" > "$TMP/c13b"
assert_contains "7.13 a recon verdict naming an old release in a known line is ignored" "$TMP/c13b" "Recon verdicts ignored: grok-4.6"
assert_contains "7.13 ...the newest Grok stays the reviewer" "$TMP/c13b" "**grok:grok-4.7 (newest base) @ medium, read-only**"
rm -f "$FH/recon/models.json"
run recon-record codex gpt-7-nova use standard-coding 14 evaluated > /dev/null
CODEX_EXTRA="gpt-7-nova gpt-8-nova" probe "$TMP/p13c" up SIGNED-IN ""
run --probe-output "$TMP/p13c" > "$TMP/c13c"
assert_contains "7.13 a recon-approved line resolves to its newest release" "$TMP/c13c" 'start from **gpt-8-nova**'
assert_absent  "7.13 ...and its successor is not a 'new line'" "$TMP/c13c" "recon required before routing to them:** codex:gpt-8-nova"
rm -f "$FH/recon/models.json"
assert_absent "7.13 an older id than the evaluated one is not called 'newer'" \
  "$(printf '%s' "$(python3 "$HERE/../scripts/model_lines.py" classify codex --models gpt-6-sol --evaluated gpt-6.1-sol)" > "$TMP/cl"; echo "$TMP/cl")" "newer than the evaluated"
for M in gpt-6-ASTRA GPT-6.1-Astra; do
  env -u FOREMAN_PREMIUM_APPROVED sh "$LCH" "$TMP/t.md" "$M" low read-only "$TMP/o.jsonl" "$TMP" > /dev/null 2>&1
  assert_eq "7.13 launcher refuses mixed-case $M" "64" "$?"
done
env -u FOREMAN_PREMIUM_APPROVED CODEX_HOME=/nonexistent sh "$LCH" /nonexistent/ticket gpt-7-astral low read-only "$TMP/o.jsonl" "$TMP" > /dev/null 2>&1
assert_eq "7.13 a non-Astra line containing 'astra' is not refused as premium" "66" "$?"

# 7.14 second review (2026-10-22): recon successors can be remembered; double-approved premium choices are usable
run recon-record codex gpt-7-nova use standard-coding 14 evaluated > /dev/null
run remember standard-coding gpt-8-nova --session N1 > /dev/null 2>&1; assert_eq "7.14 the newest release of a recon-approved line can be remembered" "0" "$?"
CODEX_EXTRA="gpt-7-nova" probe "$TMP/p14" up SIGNED-IN ""
run --probe-output "$TMP/p14" > "$TMP/c14"
assert_absent "7.14 the recon-evaluated release itself is not called a successor" "$TMP/c14" "used automatically:** codex:gpt-7-nova"
rm -f "$FH/recon/models.json"
run approve-premium gpt-6-astra --session A1 --confirmed > /dev/null
run remember hard-coding gpt-6-astra --session A1 > /dev/null
run --probe-output "$TMP/p1" --session A1 > "$TMP/c14b"
assert_contains "7.14 a double-approved premium choice is applied this session" "$TMP/c14b" "Chosen this session: gpt-6-astra — apply it"

# The skill loader substitutes $0, $1, ... in SKILL.md with invocation arguments
# (observed 2026-09-24: "~$0.0002" rendered as "~<args>.0002"). Keep SKILL.md free of them.
if grep -nE '\$[0-9]' "$HERE/../SKILL.md" > "$TMP/dollars"; then fail "7.10 SKILL.md has \$N argument placeholders: $(head -1 "$TMP/dollars")"; else pass "7.10 SKILL.md has no \$N argument placeholders"; fi

finish "fixture 7 (routing card)"
