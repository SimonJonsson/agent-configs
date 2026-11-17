---
name: orchestrate
description: Run a piece of work as orchestrator + workers. This session keeps the full context, plans the work into waves, and dispatches each item to a Claude worker in its own git worktree and herdr workspace; workers report state changes (started, needs-input, pr-up, done, failed) back here with SendMessage, and this session reviews their PRs. Use when the user runs /orchestrate or asks to orchestrate work across herdr workers.
disable-model-invocation: true
---

# Orchestrate

You are the **orchestrator**. You hold the full context of the work and the
user's intent; workers hold one item each. You plan, brief, dispatch, review
and integrate. You do not write the item code yourself; your context is for
judgment, so delegate reads to `scout` and verification to `checker`.

Workers are full Claude sessions (Opus unless the plan says otherwise), each in
its own worktree and herdr workspace, with the same `scout`, `checker` and
`consultant` agents available. Each costs about as much as a normal session,
so parallelism should earn its keep.

Herdr provides the worktrees, workspaces and agent lifecycle;
`scripts/dispatch.sh` next to this file wraps it to start one worker. Messages
between this session and workers go through `SendMessage`, both ways.

## 0. Preconditions

- `test "${HERDR_ENV:-}" = 1`, otherwise say you are not inside herdr and stop.
- In a git repository with an `origin` remote; `gh auth status` succeeds.
- Note uncommitted changes in the main checkout. Workers branch from `origin`,
  so local-only work is invisible to them; ask whether to push it first.

## 1. Understand the work

Work from the conversation and the user's arguments. Use `scout` agents (in
parallel) to map the code the work touches. Ask the user only what would change
the plan, all in one message. A vague goal is better settled now than by five
workers each guessing.

## 2. Plan in waves

Split the work into **items**. Each item is one PR a reviewer can read in one
sitting, with:

- a slug (`[a-z0-9-]`, ≤ 24 chars), a goal, and what **done** means (behavior plus the checks that prove it);
- its **scope**: the files and modules it may change;
- dependencies on other items;
- a model: `opus` by default, `sonnet` for mechanical work (renames, boilerplate, docs);
- risks or open questions.

Group items into **waves**. Items in one wave run in parallel, so they must be
independent *and* touch disjoint files; anything else goes in a later wave,
which branches from `main` after the earlier wave merges. Default to at most 3
workers at once. One item is a valid plan: the gain is then a clean worktree and
a reviewed PR, not parallelism.

If the plan involves design choices with lasting consequences, money, data
integrity, security or concurrency, have the `consultant` review it (in the
background) before you present it.

## 3. Write the run directory

`RUN=<repo-root>-wt/_orchestrate/<yyyy-mm-dd>-<run-slug>`, outside the
repository so it never lands in a commit. Worktrees go beside it in
`<repo-root>-wt/<item>`.

- `$RUN/plan.md`: goal, waves, items (with scope, dependencies, model), merge policy, decisions made along the way, and a status table you update on every worker message. You are its only writer; it is how you recover after a restart or compaction.
- `$RUN/orchestrator`: this session's identity exactly as `ListAgents` reports it, name and ref (`This session is dot-configs-6e [c25ceb]` → `dot-configs-6e [c25ceb]`). Workers message it there. If this session restarts, its ref may change: run `ListAgents` again, rewrite the file, and send each live worker the new identity.
- `$RUN/briefs/<item>.md`: one brief per item. The brief is all the worker knows about the run, so make it self-contained:

```markdown
# Brief: <item>: <one-line goal>

- **Branch:** work/<item>, from <base>.
- **Why:** the larger goal and how this item serves it.
- **Context:** the files, functions and contracts that matter, as `path:line`;
  decisions already made and by whom; constraints (ports, services, data).
- **Do:** the change, specific enough that two workers would build the same thing.
- **Not in scope:** what belongs to other items or later waves.
- **Done means:** observable behavior, plus the tests to add.
- **Checks:** the exact commands to run.
```

## 4. Get the go

Show the user the plan: waves, items, models, and the **merge policy** (default:
the user merges; alternatively "orchestrator merges once checks pass and review
is clean"). Dispatch only after an explicit go. This is the one approval for
the run; afterwards, act within it and ask only when something changes it.

## 5. Dispatch a wave

For each item in the wave, from this pane and inside the repository:

```bash
<skill-dir>/scripts/dispatch.sh "$RUN" <item> --model <model>
```

It creates the worktree and its herdr workspace (without stealing focus),
starts a Claude session named `<run>/<item>` (herdr agent `w-<item>`) with the reporting protocol as an
appended system prompt, sends it the brief, and records it in
`$RUN/workers/<item>.json`. If it fails part-way, read the
error, inspect what was created, and fix the cause; do not blindly re-run.

Then tell the user what is running and end your turn. Do not poll.

## 6. React to reports

Workers message this session with `[<run>/<item>] <state>: …`. Update the status
table in `plan.md` on each one. A worker's `started` message gives its identity
(`name [ref]`); record it in the status table and address that worker only by
it, copied exactly, never retyped. Tag every message to a worker
`[<run>/<item>]`. On resume or after compaction, re-read
`plan.md` first, and `ListAgents` / `herdr agent list` to see who is live.
Reply with `SendMessage` to the recorded identity. If a message arrives that
is not tagged for this run, do not act on it; tell the sender it was
misrouted. For each report:

- **started**: compare the worker's plan with the brief; correct it now if it
  drifted. Otherwise no reply.
- **needs-input**: answer it yourself if the plan, the brief or the context
  settles it, and record the decision in `plan.md`. Otherwise ask the user and
  get their attention with
  `herdr notification show "<item> needs input" --body "<question>" --sound request`,
  then relay the answer to the worker.
- **pr-up**: review. Run `checker` against the worktree path and the PR
  (`gh pr diff <n>`), read the diff against the brief, and consult the
  `consultant` for high-stakes items. Send concrete feedback to the worker, or
  approve. With approval: merge if the merge policy allows, otherwise tell the
  user the PR is ready.
- **done**: mark the item done in `plan.md`.
- **failed**: notify the user the same way if it needs them; read the worker (`herdr agent read w-<item> --source recent-unwrapped --lines 150`),
  decide whether to re-brief it, split the item, or take it to the user.

If the user asks for status, or nothing has arrived for a long while, check
`herdr agent list` for workers in `blocked` state (usually a permission prompt)
and tell the user which pane needs them. Never answer a worker's permission
prompt yourself.

When every item in a wave has merged, update the remaining briefs for what
changed and dispatch the next wave (its base is the new `main`).

## 7. Finish

- Summarize for the user: each item, its PR, what merged, what is left.
- For each merged item, remove its worktree and workspace:
  `herdr worktree remove --workspace <workspace from workers/<item>.json>`.
  Only remove workspaces this run created, and only after their PR merged or
  the user said to drop them. Unmerged worktrees stay.
- Keep `$RUN` as the record of the run.
