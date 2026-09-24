# Blind A/B routing test — v0.5.0 vs v0.6.0 (2026-09-23)

**Method.** Two fresh Sonnet 5 subagents received the same 12 scenarios. Each was
pointed at an unlabeled copy of one skill version (A = v0.5.0 from `origin/main`,
B = the v0.6.0 working tree; `tests/` removed from both), told to answer only from
the skill's files, and told to write "SKILL SILENT" where the files did not cover a
case. Neither knew which version it had or that a comparison was running. The lead
graded both against the key below. One run per arm: this is evidence of coverage
and clarity, not a statistical accuracy estimate.

| # | Scenario (short) | Key | A (v0.5) | B (v0.6) |
|---|---|---|---|---|
| 1 | auth.json exists, `grok models` says not authenticated | ENV-MISMATCH: re-run unsandboxed before concluding absent | ✗ "treat Grok as absent" — **the reported bug, reproduced** | ✓ |
| 2 | first dispatch returns HTTP 402 balance exhausted | pool down: stop, collect workers, re-route, tell user once, no retry | ◐ stop + re-route; no collection/user notice | ✓ |
| 3 | GPT-6 catalog: refactor / cross-family frontier review | Sol / Astra | ✓ (from positioning text) | ✓ |
| 4 | mechanical 60-file rename, Claude + Codex | GPT-6 Luna | ✓ | ✓ |
| 5 | deepest Codex effort, `ultra` available | `max`; `ultra` breaks hard rail 1 | ✓ (reasoned from the rail) | ✓ (launcher refuses it) |
| 6 | Grok models 4.7 / 4.7-fast / 4.6 / 4.5: implementation / review / fast | 4.7 / 4.6 / fast only for wall-clock | ◐ 4.7 for both; unsure about fast | ✓ |
| 7 | frontier Claude verifier: `opus` or `fable` | `opus` (Opus 5.5) | ✗ "either works" | ✓ |
| 8 | 27 overlapping findings, Jev REACHABLE | dedupe + citation pre-check; advisory; never drop MAJOR+ | ✗ SKILL SILENT on Jev | ✓ |
| 9 | Grok ticket at ~230K | route away (Claude) | ✓ | ✓ |
| 10 | Fable 5.1 LEAD, long run | may note Opus 5.5 once, informational | ✗ (old policy: say nothing) | ✓ |
| 11 | Grok reviewer PASS | not acceptance; lead accepts | ✓ | ✓ |
| 12 | two parallel tickets both edit package.json | serialize or worktrees | ✓ | ✓ |

**Score:** A = 6 correct, 2 partial, 4 wrong. B = 12 correct.

**Regression check.** The controls (#9, #11, #12) passed on both versions, so v0.6
did not disturb the verification and write-set rules. Scenario #3 passing on v0.5
shows the class-by-positioning procedure was already sound; v0.6 makes it explicit
and prints the catalog, which removes the naming trap rather than relying on the
reader to avoid it.

**Honest limits.** Several v0.6 wins (#7, #8, #10) are new policy that v0.5 could not
have known, so they measure coverage, not reasoning quality. #1 is the one that
measures the reported defect directly, and v0.5 failed it exactly as described.
