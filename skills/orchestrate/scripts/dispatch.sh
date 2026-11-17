#!/usr/bin/env bash
#
# Start one worker: a git worktree with its own herdr workspace, running a
# Claude session named RUN/ITEM that reads its brief and reports back to the
# orchestrator with SendMessage.
#
#   dispatch.sh RUN_DIR ITEM [--model MODEL] [--base REF] [--branch NAME]
#
# RUN_DIR   the run directory holding plan.md and briefs/ITEM.md
# ITEM      short slug, [a-z0-9-], at most 24 chars
# --model   worker model (default: opus)
# --base    ref to branch from (default: origin's default branch)
# --branch  branch name (default: work/ITEM)
#
# Run from the orchestrator's pane, inside the repository, after writing the
# orchestrator's session name to RUN_DIR/orchestrator. Prints the worker
# record (also saved as RUN_DIR/workers/ITEM.json).

set -euo pipefail

die() { printf 'dispatch: %s\n' "$*" >&2; exit 1; }

[[ ${HERDR_ENV:-} == 1 ]] || die "not inside a herdr pane"
(($# >= 2)) || die "usage: dispatch.sh RUN_DIR ITEM [--model M] [--base REF] [--branch NAME]"

run_dir=$(realpath "$1"); item=$2; shift 2
model=opus base='' branch="work/$item"
while (($#)); do
    case $1 in
        --model)  model=$2; shift 2 ;;
        --base)   base=$2; shift 2 ;;
        --branch) branch=$2; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ $item =~ ^[a-z0-9][a-z0-9-]{0,23}$ ]] || die "item must match [a-z0-9-], max 24 chars: $item"
brief="$run_dir/briefs/$item.md"
[[ -f $brief ]] || die "missing brief: $brief"
[[ -e $run_dir/workers/$item.json ]] && die "worker $item already dispatched (see $run_dir/workers/$item.json)"

root=$(git rev-parse --show-toplevel) || die "not in a git repository"
git -C "$root" fetch --quiet origin || die "git fetch failed"
if [[ -z $base ]]; then
    base=$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || base=origin/main
fi
wt_path="$root-wt/$item"

# The orchestrator records its own session name (as `ListAgents` shows it)
# before the first dispatch; workers message it there.
orch=$(cat "$run_dir/orchestrator" 2>/dev/null) \
    || die "write this session's name (from ListAgents) to $run_dir/orchestrator first"
worker="w-$item"
run=$(basename "$run_dir")
session="$run/$item"   # unique Claude session name, as ListAgents shows it

# Standing instructions for the worker, kept out of the conversation so they
# survive compaction.
mkdir -p "$run_dir/workers"
protocol="$run_dir/workers/$item.protocol.md"
cat >"$protocol" <<PROTO
# You are a worker in an orchestrated run

- Run: \`$run_dir\` (the plan is \`plan.md\` there). Your item: **$item**.
- Your brief: \`$brief\`. It defines the goal, scope and what "done" means.
- You work only in this worktree (\`$wt_path\`, branch \`$branch\`, based on \`$base\`). Do not touch other worktrees or the main checkout.
- The orchestrator is the Claude session \`$orch\` (name and [ref], exactly as ListAgents shows it).
- Your session is named \`$session\`. It holds the full context of the run, answers your questions or takes them to the user, and reviews your PR.

## Reporting state changes

Report every state change, and nothing else, with the \`SendMessage\` tool, to exactly \`$orch\` (copy it, ref included; never retype it from memory). Start every message with \`[$run/$item] <state>:\`.

Your first report (\`started\`) must also say who you are: run \`ListAgents\` and include the \`This session is <name> [<ref>]\` value, so the orchestrator replies to the right session.

| state | when |
|---|---|
| \`started\` | you have read the brief and the code and have a plan; include the plan in one line |
| \`needs-input\` | you need a decision; ask one precise question with the options you see, then stop and wait for the answer |
| \`pr-up\` | checks pass and the PR is open; include the PR URL |
| \`done\` | review feedback is addressed and there is nothing left for you to do |
| \`failed\` | you cannot finish; say why and what you tried |

Answers and review feedback come back as messages from \`$orch\`, tagged \`[$run/$item]\`. If a message is not tagged for your item, do not act on it; reply to its sender that it was misrouted. Do not report progress chatter.

## Finishing

1. Run the checks the brief names (have the \`checker\` agent try to break the change), and fix what they find.
2. Commit with clear messages, push the branch, and open a PR into \`${base#origin/}\` with \`gh pr create\`. Do not merge.
3. Report \`pr-up\`, then wait: the orchestrator may send review feedback into this session. Address it, push, and report \`pr-up\` again.

Never deploy, apply infrastructure, or change shared external state unless the brief explicitly says so. If the brief is ambiguous on something that matters, report \`needs-input\` rather than guess.
PROTO

created=$(herdr worktree create --cwd "$root" --branch "$branch" --base "$base" \
    --path "$wt_path" --label "$item" --no-focus) || die "herdr worktree create failed"
workspace=$(jq -r '.result.workspace.workspace_id' <<<"$created")
pane=$(jq -r '.result.root_pane.pane_id' <<<"$created")

herdr agent start "$worker" --kind claude --pane "$pane" --timeout 90000 -- \
    --model "$model" --permission-mode auto -n "$session" \
    --append-system-prompt-file "$protocol" >/dev/null \
    || die "worker agent did not start in $pane (workspace $workspace was created; inspect it)"

herdr agent prompt "$worker" "Read your brief at $brief and carry it out. Report state changes to $orch as your system prompt describes." >/dev/null \
    || die "could not send the first prompt to $worker"

jq -n --arg item "$item" --arg worker "$worker" --arg workspace "$workspace" --arg pane "$pane" \
    --arg branch "$branch" --arg base "$base" --arg path "$wt_path" --arg model "$model" \
    --arg session "$session" --arg brief "$brief" --arg at "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    '{item:$item, worker:$worker, workspace:$workspace, pane:$pane, branch:$branch, base:$base, path:$path, model:$model, session:$session, brief:$brief, dispatched_at:$at}' \
    | tee "$run_dir/workers/$item.json"
