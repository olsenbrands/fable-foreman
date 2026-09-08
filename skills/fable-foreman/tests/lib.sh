# fable-foreman tests — shared assertions. Sourced, never executed.
# POSIX sh. Fixtures do NOT use `set -e`: a failed assertion is recorded and the
# fixture keeps going, so one run reports every broken case rather than the first.

# Scratch repos must not inherit the runner's git configuration. A global
# core.excludesFile that already ignores .foreman/ makes init-ledger.sh suppress
# its "is not gitignored" note — correct behaviour, but it fails case 1.3 on that
# machine and nowhere else. Neutralise global and system config so every git call
# a fixture makes sees the same empty configuration (git >= 2.32).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS  %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL  %s\n' "$*"; }

# ok <name> <status>   — status 0 means the case passed.
ok() {
  if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi
}

assert_eq() { # assert_eq <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected [$2], got [$3])"
  fi
}

assert_contains() { # assert_contains <name> <file> <fixed-string>
  if [ -f "$2" ] && grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1 (file $2 does not contain [$3])"
  fi
}

assert_absent() { # assert_absent <name> <file> <fixed-string>
  if [ -f "$2" ] && grep -qF -- "$3" "$2"; then
    fail "$1 (file $2 unexpectedly contains [$3])"
  else
    pass "$1"
  fi
}

assert_file() { # assert_file <name> <path>
  if [ -f "$2" ]; then pass "$1"; else fail "$1 (no such file: $2)"; fi
}

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

count_matches() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# wait_until <seconds> <shell-condition...> — bounded poll, 0 if it became true.
wait_until() {
  _limit=$1; shift
  _n=0
  while [ "$_n" -lt "$((_limit * 20))" ]; do
    if eval "$@"; then return 0; fi
    sleep 0.05
    _n=$((_n + 1))
  done
  return 1
}

finish() { # finish <fixture name>
  printf -- '---- %s: %s passed, %s failed\n' "$1" "$PASS_COUNT" "$FAIL_COUNT"
  [ "$FAIL_COUNT" = "0" ] || exit 1
  exit 0
}
