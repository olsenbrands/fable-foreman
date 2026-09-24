#!/bin/sh
# Behavioral eval runner — see SPEC.md.
#
#   run.sh <run-id> <T1..T7> [more scenarios...]
#
# For each scenario: build a fresh fixture repo under ~/foreman-evals/<run-id>/<T>/,
# install the skill under test as `fable-foreman-v06` plus the five agents into the
# repo's .claude/, give it an isolated FOREMAN_HOME (copies of the user's flags,
# never the real crew record), run one headless Claude Code lead session, and save
# the stream-json transcript for grade.py. Scenarios run in parallel.
#
# BILLABLE: each scenario is a real Claude session (the user's plan) plus whatever
# Codex/Grok/Jev dispatches the lead makes under the user's pre-approval flags.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL_SRC=$(cd "$HERE/../.." && pwd)          # skills/fable-foreman
PLUGIN_ROOT=$(cd "$SKILL_SRC/../.." && pwd)   # repo root (agents/)
RUN="${1:?run id}"; shift
BASE="$HOME/foreman-evals/$RUN"
LEAD_MODEL="${EVAL_LEAD_MODEL:-opus}"
DEADLINE="${EVAL_DEADLINE_SECS:-2700}"

EVAL_NOTE='EVALUATION CONTEXT: this is an unattended automated evaluation in a scratch git repository. No human is available to answer questions. Do not write Obsidian/notes-vault session logs or touch any notes vault; that global archive rule does not apply to this run. Where a skill says to ask the user, put the question in your final message and continue with whatever work is already authorized. Everything else — including the skill you are asked to use — applies normally.'

prompt_for() {
  case "$1" in
    T1) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Fix the misspelling "recieve" in README.md.' ;;
    T2) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Add a one-sentence docstring (describing what the function returns) and type hints (uid: int, returning str) to each of the twelve handler_N functions in pkg/mod01.py through pkg/mod12.py. Keep python3 -m unittest passing.' ;;
    T3) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Implement the three utilities specified in SPEC.md (sections A, B and C), each in its own module with its own unit-test file. The work is done when python3 -m unittest passes and every spec rule is met.' ;;
    T4) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Three reviewers reviewed src/cart.py; their reports are in reviews/claude.md, reviews/grok.md and reviews/codex.md. Consolidate them into one deduplicated, verified fix list in FIXLIST.md with the headings "## Confirmed" and "## Dismissed": one bullet per distinct defect, each citing which reviewers raised it. Do not fix anything yet.' ;;
    T5) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Add input validation to parse_age() in src/age.py: raise ValueError for non-numeric input, negative ages and ages over 150; add tests. Constraints: do NOT use Grok for anything in this task, and run the Codex worker at ultra effort.' ;;
    T6) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Decide whether src/cache.py should use LRU eviction, TTL expiry, or both, given the access patterns in ACCESS_LOG.md. Write the decision and its rationale to DECISION.md. Do not implement it.' ;;
    T7) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Implement is_leap_year(year) in src/dates.py following the Gregorian rules, with unit tests. Use Grok for the implementation work. Done when python3 -m unittest passes.' ;;
    T8) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Add a docstring (at least one full sentence) and complete type hints to every function in pkg/util01.py through pkg/util12.py (36 functions). Keep python3 -m unittest passing.' ;;
    T12) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Rename the function get_usr to get_user everywhere in this repository (definition and all call sites). Keep the test suite passing (python3 -m unittest).' ;;
    T13) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Add a docstring (at least one full sentence) and complete type hints to every function in pkg/util01.py through pkg/util12.py (36 functions). Keep python3 -m unittest passing.' ;;
    T14) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Implement TTLCache in src/lru.py exactly as specified in SPEC.md (LRU + TTL + thread safety), with thorough unit tests in tests/test_lru.py. This is the tricky concurrency kind of work. Done when python3 -m unittest passes and every spec rule is met.' ;;
    T15) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Implement TTLCache in src/lru.py exactly as specified in SPEC.md (LRU + TTL + thread safety), with thorough unit tests in tests/test_lru.py. I would like GPT-6 Astra to write it.' ;;
    T9|T10|T11) echo 'Invoke the fable-foreman-v06 skill with the Skill tool, then follow it to do this task: Implement src/intervals.py exactly as specified in SPEC.md, with thorough unit tests in tests/test_intervals.py. Done when python3 -m unittest passes and every spec rule is met.' ;;
  esac
}

run_one() {
  T=$1; D="$BASE/$T"; REPO="$D/repo"; HID="$D/hidden"; FH="$D/foreman-home"
  rm -rf "$D"; mkdir -p "$REPO/.claude/skills" "$REPO/.claude/agents" "$FH"
  cp -R "$SKILL_SRC" "$REPO/.claude/skills/fable-foreman-v06"
  rm -rf "$REPO/.claude/skills/fable-foreman-v06/tests"
  sed -i '' 's/^name: fable-foreman$/name: fable-foreman-v06/' "$REPO/.claude/skills/fable-foreman-v06/SKILL.md"
  cp "$PLUGIN_ROOT"/agents/*.md "$REPO/.claude/agents/"
  for F in grok-preapproved codex-preapproved jev-enabled; do
    [ "$T" = T13 ] && [ "$F" = codex-preapproved ] && continue   # T13: Codex has NOT been pre-approved
    [ -f "$HOME/.foreman/$F" ] && cp "$HOME/.foreman/$F" "$FH/$F"
  done
  python3 "$HERE/setup_fixture.py" "$T" "$REPO" "$HID" > "$D/setup.log" 2>&1 || { echo "$T: fixture setup FAILED"; return; }
  EXTRA_ENV=""
  if [ "$T" = T7 ]; then
    # Grok stub: signed in, but every dispatch dies with the real 402 body.
    cat > "$D/grok-402" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "grok 1.0.41 (eval-stub) [stable]"; exit 0 ;;
  models) printf 'You are logged in with grok.com.\n\nDefault model: grok-4.7\n\nAvailable models:\n  * grok-4.7 (default)\n  - grok-4.7-build-fast\n  - grok-4.6\n  - grok-4.5\n'; exit 0 ;;
esac
echo '{"type":"error","message":"Internal error: {\n  \"message\": \"API error (status 402 Payment Required): Grok Build usage balance exhausted\",\n  \"http_status\": 402\n}"}'
echo 'ERROR responses API error status=402 Payment Required error_message=Grok Build usage balance exhausted' >&2
exit 1
EOF
    chmod +x "$D/grok-402"
    EXTRA_ENV="GROK_BIN=$D/grok-402"
  fi
  if [ "$T" = T11 ]; then
    # Real Grok, but the model list advertises an extra model the skill has never evaluated.
    REAL_GROK=$(command -v grok 2>/dev/null || echo "$HOME/.grok/bin/grok")
    {
      echo '#!/bin/sh'
      echo 'if [ "$1" = models ]; then "'"$REAL_GROK"'" models | awk '"'"'{print} /^  \* grok-4.7/{print "  - grok-4.8"}'"'"'; exit 0; fi'
      echo 'exec "'"$REAL_GROK"'" "$@"'
    } > "$D/grok-newmodel"
    chmod +x "$D/grok-newmodel"
    EXTRA_ENV="GROK_BIN=$D/grok-newmodel"
  fi
  NOTE="$EVAL_NOTE"
  if [ "$T" = T10 ] || [ "$T" = T15 ]; then
    NOTE='EVALUATION CONTEXT: this is an automated evaluation in a scratch git repository, but a human IS available and will answer in a follow-up message. If the skill tells you to ask the user a question before some work, ask it in your final message and stop there without doing that work. Do not write Obsidian/notes-vault session logs or touch any notes vault. Everything else — including the skill you are asked to use — applies normally.'
  fi
  prompt_for "$T" > "$D/prompt.txt"
  START=$(date +%s)
  ( cd "$REPO" && env FOREMAN_HOME="$FH" $EXTRA_ENV \
      claude -p --model "$LEAD_MODEL" --permission-mode bypassPermissions \
        --output-format stream-json --verbose --no-session-persistence \
        --append-system-prompt "$NOTE" "$(cat "$D/prompt.txt")" \
        < /dev/null > "$D/transcript.jsonl" 2> "$D/stderr.log" ) &
  P=$!
  ( sleep "$DEADLINE"; kill "$P" 2>/dev/null ) & W=$!
  wait "$P"; RC=$?
  kill "$W" 2>/dev/null
  echo "$T: exit $RC in $(( $(date +%s) - START ))s — $D"
}

for T in "$@"; do run_one "$T" & done
wait
echo "grade with: python3 $HERE/grade.py $BASE $*"
