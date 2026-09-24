# Setup runbook (agent-executable, idempotent)

This runbook is written to be executed by a coding agent with a real shell. Every step verifies itself with evidence — command output, not assumptions. Re-running any step is safe. Report what you did and what each check showed; never report a step done without its evidence.

## Part A — Verify the foreman environment (A1 and A5 are free; A2–A4 involve billable Codex calls, gated by the consent rule)

**A1. Probe.** Run `scripts/probe.sh` from this skill's directory. Paste its output into the run ledger (or your report if no ledger exists yet). This is metadata-only and needs no approval.

**A2. Codex functional check** (skip if A1 showed Codex absent or unauthenticated). This is a billable call — the consent rule applies (codex-workers.md): confirm Codex is wanted this session before running it. One tiny call on the account default model:

```bash
codex exec "Reply with exactly: ok"
```

- `ok` back → Codex seats are live. Record billing mode from A1 in the ledger.
- Failure with credentials present → likely expired login: tell the user to run `codex login`. **Never initiate an interactive auth flow yourself.**

**A3. Tier verification** (only when a run will actually route to Codex). For each tier you intend to use, one echo call with the explicit model ID (IDs differ by auth mode — codex-workers.md):

```bash
codex exec -m <candidate-model> "Reply with exactly: ok"
```

Record each result as `tier <model>: verified | unavailable` in the ledger. A tier that fails entitlement is unavailable — no retries, no substitution guessing.

**A4. Transport check.** If the Agent tool is available, the visible-subagent wrapper transport (codex-workers.md) is the Codex default — nothing to install. Optionally validate it end-to-end: write a one-line ticket ("Reply with exactly: ok. First line of your reply: DONE"), dispatch one wrapper subagent whose ticket names the launcher arguments, and confirm the report carries the transport envelope (exit code, duration, seat-evidence line — under current Codex builds, expect `seat: unverified — requested <model>`) followed by the relayed message. That single test exercises the launcher, relay fidelity, and Layer 0 honesty at once.

**A5. Ledger bootstrap.** `scripts/init-ledger.sh "<task title>"` — idempotent; on an existing ledger it stops and tells you to reconcile instead.

## Part B — Native GPT-subagent transport (OPTIONAL — user approval required, never install unprompted)

A claudemix-style loopback splitter (`hughminhphan/claudemix`, MIT) can make GPT models *native* Claude Code subagents: the model is pinned in an agent file's frontmatter, a local proxy routes `gpt-*` requests to a CLIProxyAPI instance holding the user's OpenAI/Codex login, and Anthropic-bound traffic is proxied **body-preserving, not byte-for-byte**: the splitter buffers and parses every request body, normalizes framing headers (strips `transfer-encoding`, sets `content-length`, rewrites `Host`), and forwards auth headers unmodified — meaning request bodies and live authorization headers transit the splitter's process memory. That is the honest trust statement to consent to.

**Before anything is installed, the user must explicitly confirm all three:**

1. **Terms of service.** Routing subscription logins through local proxies is a gray area on both providers' terms. The claudemix author's own position is "read both providers' terms and make your own call." That call belongs to the user, not the agent.
2. **Security posture.** The splitter is an unauthenticated localhost listener; anything local that can reach its port rides through as an authenticated client while it runs. CLIProxyAPI's key is read from its config file. The user should understand both facts.
3. **Interactive steps.** CLIProxyAPI needs its own OAuth login (browser flow). The agent must not drive OAuth; the user completes it.

**Install sketch (agent runs the non-interactive parts, user does the OAuth). Supply-chain rules are not optional:**

```bash
brew install cliproxyapi          # then: USER completes its Codex OAuth login
# fetch splitter from github.com/hughminhphan/claudemix — PINNED to a commit hash
#   the user has seen, never a moving branch; record the pin and the file's
#   sha256 in the ledger; READ the fetched script before first run (it will sit
#   in the path of live authorization headers)
# create ~/.claude/agents/<name>.md with frontmatter model: <gpt-model-id>
#   — refuse to overwrite an existing file; back up and diff instead
# chmod 600 the splitter script and any file that names ports/keys
# launch sessions via a shell function that sets ANTHROPIC_BASE_URL=http://127.0.0.1:8318
#   and ENABLE_TOOL_SEARCH=true   # gateway disables tool-schema deferral; this restores it
# verify each mutation after making it (file exists, hash matches, perms right)
#   and record the evidence; a failed step stops the install, not "continues with notes"
```

Re-running Part B is safe only because every write above is guarded (pin verified, existing files refused, evidence recorded) — idempotency here means "refuses to change what exists," not "overwrites to a known state."

**Verification (claudemix's own discipline, with this skill's evidence tiers applied honestly):** confirm routing by grepping the splitter's append-only log (`~/.local/state/claudemix/splitter.log`) for a `cliproxy`-routed request with `status=200` — never by asking the subagent what model it is. If the log shows the request went to Anthropic, the frontmatter pin silently fell back (routing.md, silent-fallback hazard) — fix the routing; do not proceed on vibes. And classify the log correctly: it is **ROUTED-tier evidence** (verification.md Layer 0) — it proves which upstream took the request and that it returned 200, not which model CLIProxyAPI actually served behind that hop. Seat `verified` still requires served-model metadata from the upstream itself; absent that, record `routed to cliproxy, served-model unconfirmed`.

**Known gateway side effect:** any `ANTHROPIC_BASE_URL` gateway disables Claude Code's tool-schema deferral, inflating boot context (claudemix author measured 164k → 41k tokens after setting `ENABLE_TOOL_SEARCH=true`). Do not "fix" this with `CLAUDE_CODE_AUTO_COMPACT_WINDOW` — it clamps the effective limit downward.

When Part B is active, Codex seats may be dispatched as native subagents instead of wrapper subagents; everything else in the skill (tickets, statuses, Layer 0 provenance, verification) applies unchanged — provenance evidence just comes from the splitter log instead of `codex --json`.

## Jev (optional decision layer)

Jev needs the user's own key and the user's own opt-in. Never create the flag file or store a key yourself; walk the user through it.

1. **Key:** an OpenRouter account with credit (model `typesafe/jev-1.13`) or a TypeSafe account (typesafe.ai). Either key works.
2. **Where the key lives:** `OPENROUTER_API_KEY` / `TYPESAFE_API_KEY` in the environment, or a macOS keychain item the user creates (`security add-generic-password -s <service> -a "$USER" -w`) named on the flag file's `keychain-service:` line.
3. **Opt-in:** the user creates `~/.foreman/jev-enabled` with `provider:`, optional `keychain-service:`, `privacy:` and `model:` lines (format in jev.md).
4. **Proof:** `scripts/access-check.sh jev` must print `REACHABLE`. `NO_KEY`, `KEY_REJECTED`, `NO_CREDIT`, `MODEL_NOT_FOUND`, `RATE_LIMITED`, `TRANSPORT_FAILED` or `DISABLED` each name the fix. The skill works identically without Jev.
