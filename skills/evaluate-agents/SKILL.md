---
name: evaluate-agents
description: Audit every live Claude Code agent (herdr panes) and the standing agent config, decide whether each task is over- or under-scaled for the model running it, and move agents to the cheapest model that can still do the job. Use when the user asks to evaluate, right-size, or rebalance agents or model usage.
disable-model-invocation: true
---

# Evaluate agents

Goal: spend Fable tokens only on work that needs Fable. Everything else runs on
Opus, Sonnet, or Haiku. This skill inspects what is running right now, grades
each task against the model doing it, and applies the change.

## 1. Gather

Run the scanner. It asks herdr for live agents and reads each agent's transcript
from `~/.claude/projects/*/<session>.jsonl`:

```bash
python3 ~/.claude/skills/evaluate-agents/scripts/scan_agents.py --prompts 5
```

Add `--json` for machine output. Outside herdr (`HERDR_ENV` unset) pass
`--session <id> ...` to inspect specific transcripts instead.

For every agent the scan prints: pane id, status (`idle`, `working`, `blocked`),
cwd, title, model per turn, output and thinking tokens, cache reads, tool-call
mix, prompt count, correction count, and the last few user prompts.

Then look at what is still in flight, not only what was done. For each agent
that is not the current pane:

```bash
herdr agent read <pane_id> --lines 60
```

For the current pane use the conversation you are already in. Load the `herdr`
skill if you need CLI details.

Also read the standing configuration:

- `~/.claude/settings.json`: `model`, `modelSettings.*.effortLevel`
- `.claude/agents/*.md` and `~/.claude/agents/*.md`: `model:` frontmatter
- `CLAUDE.md` files that tell the Agent tool which `model` override to use

## 2. Grade each task

Model ids, cheapest first:

| Tier | Id | Fits |
| --- | --- | --- |
| Haiku | `claude-haiku-4-5-20251001` | Mechanical, fully specified work: renames, formatting, single-file edits with a known diff, log or config lookups, boilerplate, shell one-liners, summarising output, small scripted checks. |
| Sonnet | `claude-sonnet-5` | Ordinary engineering: features and bug fixes with a clear repro, tests, refactors inside one module, docs, config across a few files, CV or prose edits, dotfile and desktop tweaks. |
| Opus | `claude-opus-5` | Ambiguous debugging, multi-module design, performance work, security-sensitive code, reviewing large diffs, plans that need judgement, tasks where Sonnet has already needed a correction. |
| Fable | `claude-fable-5-1` | Novel research or algorithm design, ML and RL modelling decisions, long autonomous runs with many judgement calls, anything Opus already failed at. The `[1m]` suffix in settings selects the 1M-context variant; keep it if the session needs it. |

Signals from the scan:

- **Over-scaled**: high tier with a tool mix that is mostly `Bash`, `Read`, `Edit`, short prompts about config or wording, no corrections, low thinking-token share. Typical: dotfiles, shell, CV text, questions with a lookup answer.
- **Under-scaled**: corrections at 2 or more, the same tool call repeated with small variations, tests failing across several turns, prompts like "still broken", user re-explaining the task.
- **Right-sized**: model tier matches the remaining work and there is no correction pattern. Leave it alone.

Grade the remaining work, not the history. A Fable session that finished an RL
design and is now touching up docstrings is over-scaled from here on. A Sonnet
session that just hit an unexplained race condition is under-scaled from here on.

Do not downgrade when:

- the user chose the model explicitly in this session;
- the agent is mid-task and `working`; wait for `idle`;
- the remaining work is a continuation that needs the same context depth (a
  cheaper model gets the same transcript but reasons over it less well).

## 3. Apply

For each agent that is `idle` and not the current pane, switch the model in
place. `/model` takes effect on the next turn and keeps the transcript:

```bash
herdr agent prompt <pane_id> "/model claude-sonnet-5"
herdr agent read <pane_id> --lines 8      # confirm the switch was accepted
```

For agents that are `working`, record the recommendation as pending. If the
user wants it applied automatically:

```bash
herdr agent wait <pane_id> --until idle --timeout 600000 && herdr agent prompt <pane_id> "/model <id>"
```

For the current pane you cannot type into yourself. Tell the user the exact
`/model <id>` to run.

For standing config:

- Edit `model:` in `.claude/agents/*.md` directly; this is reversible and
  scoped to those subagents.
- Add or fix Agent-tool guidance in the project `CLAUDE.md` when a repeated
  pattern shows up (for example "searches and log reading go to `haiku`,
  ordinary edits to `sonnet`").
- The global default in `~/.claude/settings.json` is a user preference. Propose
  the new value with the reasoning and change it only when the user confirms.

## 4. Report

One table, one row per agent:

`pane | task (title) | current model | tokens out/think | verdict (over / under / ok) | new model | applied? | why`

Then two short lists: changes applied, and changes pending on the user
(working agents, the current pane, settings.json). Keep the why to one sentence
each. Do not restate the rubric.
