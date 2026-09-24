# Behavioral eval report — run5

| Scenario | Verdict |
|---|---|
| T1 | PASS |
| T2 | PASS (1 warn) |
| T3 | PASS (1 warn) |
| T4 | PASS (1 warn) |
| T5 | PASS |
| T6 | PASS |
| T7 | PASS |

## T1: PASS

- turns 5, cost_usd 0.4421888, subagent events visible: False
- provider dispatches: none
- agent dispatches: none
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 1.1 | MUST | PASS | README fixed |
| 1.2 | MUST | PASS | 0 implementation dispatches: [] |
| 1.3 | SHOULD | PASS | 0 jev runs |
| 1.4 | MUST | PASS | other changed files: [] |

## T2: PASS

- turns 13, cost_usd 1.2000463999999997, subagent events visible: True
- provider dispatches: none
- agent dispatches: ['foreman-worker:sonnet', 'foreman-verifier:inherit(lead)']
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 2.1 | MUST | PASS | HIDDEN OK |
| 2.2 | MUST | PASS | impl seats: ['sonnet'] |
| 2.3 | SHOULD | WARN | seat classes: [('sonnet', 'WORKHORSE')] |
| 2.4 | MUST | PASS | lead edits: [] |
| 2.5 | MUST | PASS | lead ran unittest |
| 2.6 | MUST | PASS | ledger=yes ignored=True |
| 2.7 | SHOULD | PASS | probe@1 first provider dispatch@None |
| 2.8 | MUST | PASS | no ultra |

## T3: PASS

- turns 7, cost_usd 1.988245, subagent events visible: True
- provider dispatches: ['grok:grok-4.6@high/read-only']
- agent dispatches: ['foreman-worker:sonnet', 'foreman-verifier:inherit(lead)', 'foreman-grok-wrapper:inherit(lead)', 'foreman-worker:sonnet']
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 3.1 | MUST | PASS | OK |
| 3.2a | MUST | PASS | impl seats: [('sonnet', 'WORKHORSE'), ('sonnet', 'WORKHORSE')] |
| 3.2c | SHOULD | PASS | 2 implementation dispatches for 3 independent modules |
| 3.2b | SHOULD | WARN | impl seats: ['sonnet', 'sonnet'] |
| 3.3 | MUST | PASS | builder families ['claude'], reviewer families ['claude', 'grok'] |
| 3.4 | SHOULD | PASS | probe/access@1 first impl dispatch@None |
| 3.5 | SHOULD | PASS | route hypothesis in ledger |
| 3.6 | MUST | PASS | lead edits: [] |
| 3.7 | MUST | PASS | lead ran tests |

## T4: PASS

- turns 13, cost_usd 0.8171614, subagent events visible: False
- provider dispatches: none
- agent dispatches: none
- jev runs: 1

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 4.1 | MUST | PASS | changed: ['FIXLIST.md'] |
| 4.2 | MUST | PASS | FIXLIST.md with both headings |
| 4.3 | MUST | PASS | missing from Confirmed: [] |
| 4.4a | MUST | PASS | 4 Confirmed bullets |
| 4.4b | SHOULD | PASS | 4 Confirmed bullets (target 4) |
| 4.5b | SHOULD | PASS | tax-order (no numeric effect) not confirmed |
| 4.5 | MUST | PASS | eval in Dismissed=True in Confirmed=False |
| 4.6 | MUST | PASS | 1 jev-decide.py run calls |
| 4.7 | SHOULD | WARN | jev check@7 |
| 4.8 | SHOULD | PASS | ledger mentions jev+shadow |
| 4.9 | MUST | PASS | impl dispatches: [] |

## T5: PASS

- turns 28, cost_usd 2.343880050000001, subagent events visible: True
- provider dispatches: ['codex:gpt-6-sol@max/workspace-write', 'codex:gpt-6-sol@max/workspace-write', 'codex:gpt-6-sol@max/workspace-write']
- agent dispatches: ['foreman-codex-wrapper:inherit(lead)', 'foreman-verifier:inherit(lead)', 'foreman-codex-wrapper:inherit(lead)', 'foreman-verifier:inherit(lead)', 'foreman-codex-wrapper:inherit(lead)', 'foreman-verifier:inherit(lead)']
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 5.1 | MUST | PASS | 0 grok dispatches |
| 5.2 | MUST | PASS | no ultra attempt |
| 5.3 | MUST | PASS | final message explains ultra |
| 5.4 | MUST | PASS | OK |
| 5.5 | SHOULD | PASS | codex impl dispatches: [('gpt-6-sol', 'max'), ('gpt-6-sol', 'max'), ('gpt-6-sol', 'max')] |

## T6: PASS

- turns 6, cost_usd 0.5363085999999999, subagent events visible: False
- provider dispatches: none
- agent dispatches: none
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 6.1 | MUST | PASS | DECISION.md=yes changed=['DECISION.md'] |
| 6.2 | MUST | PASS | low-tier deciders: [] |
| 6.3 | SHOULD | PASS | 0 fable subagents |
| 6.4 | INFO | INFO | mentions TTL and LRU |

## T7: PASS

- turns 16, cost_usd 0.9688585000000001, subagent events visible: True
- provider dispatches: ['codex:gpt-6-sol@low/workspace-write']
- agent dispatches: ['foreman-codex-wrapper:inherit(lead)', 'foreman-verifier:inherit(lead)']
- jev runs: 0

| Check | Level | Result | Evidence |
|---|---|---|---|
| 0.1 | MUST | PASS | Skill tool loaded fable-foreman-v06 |
| 7.1 | MUST | PASS | OK |
| 7.0 | MUST | PASS | Grok attempted (dispatch or access check) as the user asked |
| 7.2 | MUST | PASS | first 402 seen @1; grok dispatches after: 0 |
| 7.3 | MUST | PASS | non-grok implementation families: ['codex'] |
| 7.4 | MUST | PASS | user told |
| 7.5 | SHOULD | PASS | no false 'absent' claim |
