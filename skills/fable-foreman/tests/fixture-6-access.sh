#!/bin/sh
# Fixture 6 (v0.6) — provider access detection, effort validation, Jev launcher.
#
# Everything runs against STUBS inside a mktemp dir: fake `grok` binaries that
# print what the real CLI prints in each state (captured 2026-09-23 from grok
# 1.0.41, and the real HTTP 402 body from a 2026-09-21 run), fake Codex/Grok
# model caches, and a local HTTP stub standing in for the Jev endpoint. No
# network, no billable call, no real credential is read.
#
#   6.1  probe: signed in           -> "grok access: SIGNED-IN", live list, newest base model
#   6.2  probe: signed out, no creds -> SIGNED-OUT, fallback-list warning
#   6.3  probe: signed out WITH creds -> ENV-MISMATCH (the "can't tell if I have access" bug)
#   6.4  probe: models hangs          -> UNDETERMINED + timed out, bounded
#   6.5  grok-dispatch: HTTP 402      -> "GROK ACCESS: BALANCE_EXHAUSTED"
#   6.6  grok-dispatch: effort not in the model's cached list -> BLOCKED before spend
#   6.7  codex-dispatch: ultra refused; per-model effort refused; max allowed past validation
#   6.8  jev-decide: DISABLED / NO_KEY / invalid request / oversized state
#   6.9  jev-decide: stub 200 -> answers printed; stub 401 -> KEY_REJECTED
#   6.10 no key material in any output
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
SK="$HERE/.."

TMP=$(mktemp -d "${TMPDIR:-/tmp}/foreman-fx6.XXXXXX") || exit 1
STUB_PID=""
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM

FH="$TMP/home"; mkdir -p "$FH/.foreman" "$FH/.grok/bin" "$FH/.codex" "$TMP/bin"
case "$FH" in "$HOME"/*) fail "6.0 temp HOME escaped into the real HOME"; finish "fixture 6";; esac

# ---- fake grok (behaviour chosen by $GROK_STUB_MODE) -------------------------
cat > "$FH/.grok/bin/grok" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "grok 9.9.9 (stub) [stable]"; exit 0 ;;
  models)
    case "${GROK_STUB_MODE:-in}" in
      in)  printf 'You are logged in with grok.com.\n\nDefault model: grok-4.7\n\nAvailable models:\n  * grok-4.7 (default)\n  - grok-4.7-build-fast\n  - grok-4.6\n  - grok-4.5\n' ;;
      out) printf 'You are not authenticated.\n\nDefault model: grok-4.6\n\nAvailable models:\n  * grok-4.6 (default)\n  - grok-4.5\n' ;;
      hang) trap '' TERM; sleep 30 ;;
    esac
    exit 0 ;;
esac
# dispatch path: emulate the real 402 failure (stdout JSON error, exit 1)
if [ "${GROK_STUB_MODE:-in}" = "402" ]; then
  echo '{"type":"error","message":"Internal error: {\n  \"message\": \"API error (status 402 Payment Required): Grok Build usage balance exhausted\",\n  \"http_status\": 402\n}"}'
  echo 'ERROR responses API error status=402 Payment Required' >&2
  exit 1
fi
echo '{"type":"result","text":"ok","modelUsage":{"grok-4.7-build":{}},"sessionId":"s1","num_turns":1,"usage":{"input_tokens":10,"output_tokens":1}}'
EOF
chmod +x "$FH/.grok/bin/grok"
cat > "$FH/.grok/models_cache.json" <<'EOF'
{"models":{"grok-4.7":{"info":{"reasoning_efforts":[{"id":"xhigh"},{"id":"high"},{"id":"medium"},{"id":"low"}]}},
           "grok-4.5":{"info":{"reasoning_efforts":[{"id":"high"},{"id":"medium"},{"id":"low"}]}},
           "grok-9.0":{"info":{"reasoning_efforts":[{"id":"high"},{"id":"low"}]}}}}
EOF
cat > "$FH/.codex/models_cache.json" <<'EOF'
{"fetched_at":"stub","client_version":"stub","models":[
 {"slug":"gpt-6-astra","description":"Frontier intelligence for the most demanding work.","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"xhigh"},{"effort":"max"},{"effort":"ultra"}]},
 {"slug":"gpt-6-luna","description":"Fast and affordable model for easier tasks.","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"xhigh"},{"effort":"max"}]}]}
EOF
# a codex stub that records its argv and succeeds — proves validation let it through
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
[ "$1" = "login" ] && { echo "Logged in using ChatGPT"; exit 0; }
echo "$@" > "${CODEX_STUB_ARGV:-/dev/null}"; echo '{"type":"thread.started"}'; exit 0
EOF
chmod +x "$TMP/bin/codex"

PATHX="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ -x /opt/homebrew/bin/python3 ] && PATHX="$PATHX:/opt/homebrew/bin"
[ -x /usr/local/bin/python3 ] && PATHX="$PATHX:/usr/local/bin"
run_env() { env -i HOME="$FH" FOREMAN_HOME="$FH/.foreman" GROK_HOME="$FH/.grok" CODEX_HOME="$FH/.codex" \
            PATH="$PATHX" TMPDIR="$TMP" "$@"; }

# ---- 6.1 – 6.4 probe ----------------------------------------------------------
printf '{"x":{"auth_mode":"oidc"}}' > "$FH/.grok/auth.json"
( cd "$TMP" && run_env GROK_STUB_MODE=in sh "$SK/scripts/probe.sh" > "$TMP/p1" 2>&1 )
assert_contains "6.1 signed in: access verdict"        "$TMP/p1" "grok access: SIGNED-IN"
assert_contains "6.1 signed in: live model list"       "$TMP/p1" "grok models (live, this account): grok-4.7 grok-4.7-build-fast grok-4.6 grok-4.5"
assert_contains "6.1 signed in: newest base model"     "$TMP/p1" "grok newest base model: grok-4.7"
assert_contains "6.1 signed in: capacity still unproven" "$TMP/p1" "capacity unproven"
assert_contains "6.1 codex catalog positioning shown"  "$TMP/p1" 'gpt-6-luna: "Fast and affordable model for easier tasks."'

rm -f "$FH/.grok/auth.json"
( cd "$TMP" && run_env GROK_STUB_MODE=out sh "$SK/scripts/probe.sh" > "$TMP/p2" 2>&1 )
assert_contains "6.2 signed out: SIGNED-OUT"           "$TMP/p2" "grok access: SIGNED-OUT"
assert_contains "6.2 signed out: fallback list flagged" "$TMP/p2" "built-in fallback"
assert_absent   "6.2 signed out: no live list claimed"  "$TMP/p2" "grok models (live"

printf '{"x":{"auth_mode":"oidc"}}' > "$FH/.grok/auth.json"
( cd "$TMP" && run_env GROK_STUB_MODE=out sh "$SK/scripts/probe.sh" > "$TMP/p3" 2>&1 )
assert_contains "6.3 creds present but CLI signed out: ENV-MISMATCH" "$TMP/p3" "grok access: ENV-MISMATCH"
assert_contains "6.3 tells the lead to re-run unsandboxed"          "$TMP/p3" "Re-run this probe unsandboxed"

S=$(date +%s)
( cd "$TMP" && run_env GROK_STUB_MODE=hang FOREMAN_PROBE_TIMEOUT=2 sh "$SK/scripts/probe.sh" > "$TMP/p4" 2>&1 )
E=$(date +%s)
assert_contains "6.4 hang: UNDETERMINED"  "$TMP/p4" "grok access: UNDETERMINED"
assert_contains "6.4 hang (child ignores SIGTERM): says timed out" "$TMP/p4" "timed out"
[ $((E - S)) -lt 20 ] && pass "6.4 hang: probe stayed bounded ($((E - S))s)" || fail "6.4 hang: probe took $((E - S))s"

# ---- 6.5 – 6.6 grok-dispatch ---------------------------------------------------
WD="$FH/work"; mkdir -p "$WD"; printf 'Reply with exactly: ok\n' > "$WD/t.md"
run_env GROK_STUB_MODE=402 sh "$SK/scripts/grok-dispatch.sh" "$WD/t.md" grok-4.7 low read-only "$WD/a1.json" "$WD" > "$TMP/d5" 2>&1
assert_contains "6.5 402: balance exhaustion named"   "$TMP/d5" "GROK ACCESS: BALANCE_EXHAUSTED"
assert_contains "6.5 402: exit code surfaced"         "$TMP/d5" "exit code: 1"

run_env sh "$SK/scripts/grok-dispatch.sh" "$WD/t.md" grok-9.0 xhigh read-only "$WD/a2.json" "$WD" > "$TMP/d6" 2>&1
RC=$?
assert_eq      "6.6 effort outside the cached list: exit 64" "64" "$RC"
assert_contains "6.6 effort outside the cached list: named"   "$TMP/d6" "does not support effort 'xhigh' (supported: high|low)"
[ -f "$WD/a2.json.pid" ] && fail "6.6 no process spawned" || pass "6.6 no process spawned"

# ---- 6.7 codex-dispatch ----------------------------------------------------------
run_env sh "$SK/scripts/codex-dispatch.sh" "$WD/t.md" gpt-6-astra ultra read-only "$WD/c1.jsonl" "$WD" > "$TMP/c1" 2>&1
assert_eq      "6.7 ultra refused: exit 64" "64" "$?"
assert_contains "6.7 ultra refused: rail named" "$TMP/c1" "hard rail 1"
run_env sh "$SK/scripts/codex-dispatch.sh" "$WD/t.md" gpt-6-luna minimal read-only "$WD/c2.jsonl" "$WD" > "$TMP/c2" 2>&1
assert_eq      "6.7 minimal on gpt-6-luna refused: exit 64" "64" "$?"
run_env sh "$SK/scripts/codex-dispatch.sh" "$WD/t.md" gpt-6-astra max read-only "$WD/c4.jsonl" "$WD" > "$TMP/c4" 2>&1
assert_eq      "6.7 premium Astra refused without double approval: exit 64" "64" "$?"
assert_contains "6.7 premium refusal names the approval step" "$TMP/c4" "needs the user's double approval"
run_env CODEX_STUB_ARGV="$TMP/argv" FOREMAN_PREMIUM_APPROVED=gpt-6-astra sh "$SK/scripts/codex-dispatch.sh" "$WD/t.md" gpt-6-astra max read-only "$WD/c3.jsonl" "$WD" > "$TMP/c3" 2>&1
assert_contains "6.7 approved Astra + max passes validation to codex" "$TMP/argv" "model_reasoning_effort=max"

# ---- 6.8 – 6.9 jev-decide ---------------------------------------------------------
JEV="$SK/scripts/jev-decide.py"
printf '{"state":{"a":"b"},"questions":{"q":{"type":"noul","instructions":"Is a b?"}}}' > "$TMP/req.json"
run_env python3 "$JEV" check > "$TMP/j1" 2>&1; assert_eq "6.8 no opt-in: exit 3 (DISABLED)" "3" "$?"
assert_contains "6.8 no opt-in: says DISABLED" "$TMP/j1" "jev access: DISABLED"
: > "$FH/.foreman/jev-enabled"
run_env python3 "$JEV" check > "$TMP/j2" 2>&1; assert_eq "6.8 opted in, no key: exit 4 (NO_KEY)" "4" "$?"
printf '{"state":{"a":"b"},"questions":{"q":{"type":"choice","instructions":"x","criteria":{"only":"one"}}}}' > "$TMP/bad.json"
run_env OPENROUTER_API_KEY=stubkey-XYZ python3 "$JEV" run "$TMP/bad.json" "$TMP/o0.json" > "$TMP/j3" 2>&1
assert_eq "6.8 one-option choice refused before spend: exit 64" "64" "$?"
python3 -c 'import json;json.dump({"state":{"blob":"x"*200000},"questions":{"q":{"type":"noul","instructions":"?"}}},open("'"$TMP"'/big.json","w"))'
run_env OPENROUTER_API_KEY=stubkey-XYZ python3 "$JEV" run "$TMP/big.json" "$TMP/o1.json" > "$TMP/j4" 2>&1
assert_eq "6.8 oversized state refused before spend: exit 64" "64" "$?"

# local stub endpoint: /ok answers, /deny returns 401
cat > "$TMP/stub.py" <<'EOF'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/deny":
            self.send_response(401); self.end_headers()
            self.wfile.write(json.dumps({"error": {"code": 401, "echo": self.headers.get("Authorization", "")}}).encode()); return
        if self.path == "/empty":
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}'); return
        assert body["model"] and body["questions"]["q"]["type"] == "noul"
        out = {"model": "jev-1.13.0", "answers": {"q": {"noul": 0.93}}, "usage": {"input_tokens": 42}}
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(out).encode())
import socketserver
# TCPServer, not HTTPServer: HTTPServer.server_bind does a reverse-DNS getfqdn() that
# took 35 s on one test machine (2026-09-24) and timed this fixture out.
s = socketserver.TCPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1])); s.serve_forever()
EOF
python3 "$TMP/stub.py" "$TMP/port" & STUB_PID=$!
wait_until 20 '[ -s "$TMP/port" ]'
PORT=$(cat "$TMP/port")
run_env OPENROUTER_API_KEY=stubkey-XYZ FOREMAN_JEV_ENDPOINT="http://127.0.0.1:$PORT/ok" python3 "$JEV" run "$TMP/req.json" "$TMP/o2.json" > "$TMP/j5" 2>&1
assert_eq       "6.9 stub 200: exit 0"            "0" "$?"
assert_contains "6.9 stub 200: REACHABLE"         "$TMP/j5" "jev access: REACHABLE"
assert_contains "6.9 stub 200: answer surfaced"   "$TMP/j5" "answer q: noul=0.93"
assert_contains "6.9 stub 200: advisory reminder" "$TMP/j5" "never acceptance"
assert_file     "6.9 stub 200: artifact written"  "$TMP/o2.json"
run_env OPENROUTER_API_KEY=stubkey-XYZ FOREMAN_JEV_ENDPOINT="http://127.0.0.1:$PORT/deny" python3 "$JEV" run "$TMP/req.json" "$TMP/o3.json" > "$TMP/j6" 2>&1
assert_eq       "6.9 stub 401: exit 5"            "5" "$?"
assert_contains "6.9 stub 401: KEY_REJECTED"      "$TMP/j6" "jev access: KEY_REJECTED"

run_env OPENROUTER_API_KEY=stubkey-XYZ FOREMAN_JEV_ENDPOINT="http://127.0.0.1:$PORT/empty" python3 "$JEV" run "$TMP/req.json" "$TMP/o4.json" > "$TMP/j7" 2>&1
assert_eq       "6.11 stub 200 with no answers: not REACHABLE-ok (exit 6)" "6" "$?"
assert_contains "6.11 stub 200 with no answers: MALFORMED" "$TMP/j7" "MALFORMED_RESPONSE"
: > "$FH/.foreman/jev-enabled"
run_env OPENROUTER_API_KEY=stubkey-XYZ FOREMAN_JEV_ENDPOINT="http://127.0.0.1:$PORT/empty" python3 "$JEV" check > "$TMP/j8" 2>&1
assert_eq       "6.11 check on empty 200: exit 6" "6" "$?"
LEAKF=0; grep -q "stubkey-XYZ" "$TMP/o3.json" && LEAKF=1
assert_eq "6.12 key echoed by the provider is redacted in the artifact" "0" "$LEAKF"

# ---- 6.10 secrets never echoed ------------------------------------------------------
LEAK=0
for F in "$TMP"/j*; do grep -q "stubkey-XYZ" "$F" && LEAK=1; done
assert_eq "6.10 key value never printed" "0" "$LEAK"

finish "fixture 6 (access + effort + jev)"
