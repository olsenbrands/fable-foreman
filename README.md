# Fable Foreman: Turn Claude Fable into your agent orchestrator

Fable Foreman teaches Claude Fable or Opus, the lead, to plan coding work, assign it to capable agents, and personally verify the result. The lead stays responsible for the outcome while smaller, lower-cost workers handle suitable implementation, testing, and repairs.

This repository is free under the MIT license. Claude Code is required for full orchestration; Codex, Grok and TypeSafe Jev are optional.

## What's new in 0.6

- **Up to date with the September 2026 models.**
  - Claude: Opus 5.5 and Fable 5.1.
  - OpenAI: GPT-6 Astra, Sol and Luna. In GPT-6, Sol is the everyday workhorse, not the flagship.
  - xAI: Grok 4.7.
  - Prices and benchmark scores come from one dated evidence table.
- **A routing card per machine.** One command shows which model gets each kind of job, based on what is actually installed, signed in and approved on your computer.
  - Clear-cut jobs get a fixed default. Mechanical edits go to GPT-6 Luna, about a tenth of the cost of Claude Haiku.
  - Genuine judgment calls, such as which model writes everyday code, become one plain-language question per session. The lead remembers your answer for the rest of the session.
- **Access is proven, not assumed.** A tiny test call shows whether each provider can really do work, not just whether it is signed in.
- **The most expensive models need your double approval.** GPT-6 Astra and Claude Fable are only hired as helpers after you say yes twice in the same session.
- **An optional Jev decision layer** handles cheap, narrow triage.
- **Tested on real runs.**
  - A new behavioral suite runs real Claude Code leads through 15 scenarios, including farming out work, cross-family review, following your constraints, recovering from a dead provider, and asking before using premium models.
  - A deterministic grader scores each run from its actual tool calls, with hidden answer keys. Every scenario passed on its most recent run. These are single runs, not a statistical success rate; details are in [the results](skills/fable-foreman/tests/behavior/RESULTS-2026-09-23.md).
  - In a blind test, an AI model answered 12 routing questions using only the skill's instructions: with the 0.5 instructions it got 6 right, 2 partly right and 4 wrong; with the 0.6 instructions it got all 12 right.

## What it helps you do

### Choose the right agents for the work

The lead considers task complexity, available tools, cost, and prior results before assigning a worker. It can use Claude, Codex, or Grok agents, with lower-cost agents handling work they are suited to do. A routing card shows exactly which model gets each kind of job on your machine. When two good options are close, the lead asks you once, in plain language, and remembers your answer for the session.

### Keep track of the whole project

The lead creates a working record for assignments, decisions, completed work, and unresolved problems. It uses that record to make better-informed decisions and assignments as the work continues.

### Get repairs handled without managing every handoff

When review finds a problem, the lead sends the repair back to the original builder when possible. If an approach keeps failing, it changes the approach. Work that needs your input is recorded clearly while independent work continues.

### Verify what was actually delivered

Meaningful changes receive independent review. The Fable or Opus lead then checks the actual result against your request, personally verifies critical behavior, and tells you what is complete and what still needs attention.

## How it works

1. **Describe the result you want.** Ask for a feature, bug fix, refactor, or help planning a project. The lead identifies the work and how it will know the result is ready.
2. **Let the lead assign the work.** It gives suitable agents a clear task, ownership, and checks. Small tasks stay simple; independent work can run in parallel when useful.
3. **Review, repair, and verify.** Workers return their results and evidence. The lead arranges independent review, resolves confirmed problems, and personally checks the finished work before accepting it.
4. **Get a clear handoff.** See what changed, how it was checked, and anything still unresolved. You retain control over publishing, deployment, and other actions that need your approval.

Try this:

```text
Use /fable-foreman to build the feature described in PLAN.md. Choose suitable agents, keep track of the work, and personally verify the finished result. Ask me before deploying.
```

## Install

**Claude Code — recommended.** Paste this into a Claude Code session:

```text
Install Fable Foreman globally from https://github.com/olsenbrands/fable-foreman. Preserve my existing skills and agents, then verify that the skill folder and all five Fable Foreman agent definitions are installed.
```

Or install it manually after cloning the repository:

```bash
mkdir -p ~/.claude/skills ~/.claude/agents
cp -R skills/fable-foreman ~/.claude/skills/
cp agents/*.md ~/.claude/agents/
```

Both copies are required. The skill calls `foreman-scout`, `foreman-worker`, `foreman-verifier`, `foreman-codex-wrapper`, and `foreman-grok-wrapper` by name. Installing only the skill folder does not provide delegation or independent verification.

**Claude Desktop and claude.ai.** Package the skill folder as a ZIP and upload it through **Settings → Customize → Skills** with code execution enabled. Claude Desktop has a reduced workflow because it does not provide the Agent tool: the skill uses separate plan, execute, and self-review passes in one conversation, rather than full delegated orchestration. See Anthropic's [skills guide](https://support.claude.com/en/articles/12512180-use-skills-in-claude) for current availability and setup details.

## Before you start

**Does it work with Opus?** Yes. Fable or Opus can lead the workflow. The lead plans, assigns, supervises, and makes the final acceptance decision. As of September 2026, Opus 5.5 is the strongest-value lead: it scores above Fable 5.1 on independent benchmarks at 40% of the price. It's also the default when the lead needs a frontier-class Claude helper.

**Do I need Codex or Grok?** No. Claude agents can run the workflow on their own. Codex and Grok add options when they are installed and logged in.

**How does it know whether Codex or Grok will actually work?** It checks in two steps. A free probe confirms each tool is installed and signed in from the lead's own shell. Then one tiny test call per provider confirms it can really do work. Being signed in isn't enough on its own: an exhausted Grok balance or a used-up Codex window only shows up on a real call. Each provider gets one plain verdict, such as `LIVE`, `SIGNED_OUT`, or `BALANCE_EXHAUSTED`. If a restricted shell makes a signed-in tool look signed out, the verdict says exactly that instead of reporting the tool as missing.

**What is the optional Jev layer?** [TypeSafe Jev](https://docs.typesafe.ai) is a decision model, not a chatbot. It answers narrow yes/no, pick-one, and score questions for a tiny fraction of the cost of an AI model call. If you opt in with your own TypeSafe or OpenRouter key, the lead can use it for sorting jobs: spotting duplicate review findings, flagging findings whose quoted evidence doesn't back them up, and finding comparable past jobs. Jev only reorders what the lead reviews. It never accepts work and never makes security decisions. Without it, the skill works exactly the same.

**Will it use the most expensive models behind my back?** No. GPT-6 Astra and Claude Fable are "premium" models. Fable Foreman never hands work to either one unless you approve it twice in the same session: once when it asks, and again when it confirms the model and its cost. That approval ends with the session. If Fable itself is leading your session, that's fine; the rule is about the helpers it hires.

**Will it reduce my AI costs?** It is designed to spend effort where it helps: capable lower-cost workers for suitable tasks, focused review, and fewer repeated handoffs. Actual cost depends on the work, models, and repairs. Savings are not guaranteed.

**Does the skill include AI usage?** No. Your existing Claude, Codex, or Grok accounts provide the models and cover their usage. Before the first billable Codex or Grok dispatch, the skill asks for authorization unless you already authorized that provider in the session or configured your own optional standing pre-approval. Read the [provider setup and consent details](skills/fable-foreman/SKILL.md#step-0--know-the-job-site-once-per-session-re-run-on-model-change).

**Do I have to manage the workers myself?** No. The lead handles assignments, progress checks, review, and routine repairs within your instructions. It brings you decisions that need your input and keeps independent work moving.

## Learn more

- [Skill workflow](skills/fable-foreman/SKILL.md)
- [Routing guidance](skills/fable-foreman/references/routing.md) and [the model evidence table](skills/fable-foreman/references/model-matrix.md)
- [The optional Jev layer](skills/fable-foreman/references/jev.md)
- [Behavioral test suite and results](skills/fable-foreman/tests/behavior/)
- [Verification protocol](skills/fable-foreman/references/verification.md)
- [Release history and current limitations](CHANGELOG.md)

## License

MIT © Jordan Olsen
