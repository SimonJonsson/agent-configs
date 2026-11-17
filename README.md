# agent-configs

Skills and configuration for the coding-agent CLIs (Claude Code, Codex,
OpenCode, pi, Gemini, Copilot, ...), kept in one place and linked into each
provider so a skill is written once and available everywhere.

Machine and desktop config lives in [dot-configs](https://github.com/SimonJonsson/dot-configs).
This repo only holds what the agents read.

## Setup

```sh
git clone git@github.com:SimonJonsson/agent-configs.git ~/Repos/agent-configs
~/Repos/agent-configs/install.sh
```

Re-run `install.sh` after adding a skill or a provider file. It only touches
providers whose config root already exists on the machine, so it is safe on a
box that has, say, Claude and Codex but not Gemini. `--all` links into every
known provider regardless, `--dry-run` prints what would happen.

Anything real sitting where a link needs to go is moved to
`~/.agent-configs-backup/<timestamp>/`.

## Layout

```
skills/<name>/SKILL.md      one skill, shared by every provider
providers/<provider>/...    mirrored into that provider's config root
install.sh                  links both of the above
```

### Skills

Skills follow the [Agent Skills](https://agentskills.io) format: a directory
with a `SKILL.md` whose frontmatter has `name` and `description`, plus any
scripts or reference files next to it. Every provider below reads that format.

Each skill directory is symlinked, not copied, into:

| Provider   | Skills directory             | Config root         |
| ---------- | ---------------------------- | ------------------- |
| any        | `~/.agents/skills`           | always linked       |
| Claude     | `~/.claude/skills`           | `~/.claude`         |
| Codex      | `~/.codex/skills`            | `~/.codex`          |
| OpenCode   | `~/.config/opencode/skill`   | `~/.config/opencode`|
| pi         | `~/.pi/agent/skills`         | `~/.pi/agent`       |
| Gemini     | `~/.gemini/skills`           | `~/.gemini`         |
| Copilot    | `~/.copilot/skills`          | `~/.copilot`        |
| Cursor     | `~/.cursor/skills`           | `~/.cursor`         |
| Amp        | `~/.config/amp/skills`       | `~/.config/amp`     |

Skills that Omarchy ships (`omarchy`, `diagnose-crash`) are already linked into
the same directories by Omarchy itself and are not tracked here.

Current skills:

- `evaluate-agents`: audit live herdr agents and move each to the cheapest
  model that fits the remaining work. Claude-specific (uses `/model`).
- `grill-me`: relentless one-question-at-a-time interview of a plan.
- `orchestrate`: `/orchestrate` plans work into waves and dispatches each item
  to a Claude worker in its own worktree and herdr workspace; workers report
  state changes back and the orchestrator reviews their PRs. Needs herdr.
- `herdr`: control the herdr multiplexer from inside an agent pane. Copied from
  [herdrdev/herdr](https://github.com/herdrdev/herdr/tree/master/skills/herdr);
  re-copy after a herdr upgrade if the CLI changes.

### Provider configs

Files under `providers/<name>/` are linked file by file into that provider's
config root, so `providers/claude/settings.json` becomes `~/.claude/settings.json`.

Tracked today:

- `claude/settings.json`: default model, effort levels, TUI, and the herdr
  session hook. The hook path uses `$HOME` so the same file works on macOS.
- `codex/config.toml`: feature flags.
- `opencode/agent/explore-glm.md`: a read-only exploration subagent.

Not tracked, on purpose:

- Hook scripts and plugins that herdr installs (`herdr-agent-state.*`,
  `~/.codex/hooks.json`). `herdr integration install <provider>` regenerates
  them and would fight a symlink.
- `~/.config/opencode/opencode.json` and `plugin/`: owned by the
  `ninfer-omarchy-setup` repo, which manages the local inference server.
- Credentials, session logs, caches.

## Adding things

- New skill: `mkdir skills/<name>`, write `SKILL.md`, run `./install.sh`.
- New provider file: put it at `providers/<provider>/<path as under the config
  root>`, run `./install.sh`.
- New provider: add a row to `PROVIDERS` in `install.sh` and to the table above.
