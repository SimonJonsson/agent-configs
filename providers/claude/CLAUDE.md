# Model routing

The main session drives the work (Opus by default). Delegate to the agents in
`~/.claude/agents/` without being asked; the user wants the right model used
under the surface, for speed and quality, not more check-ins.

- **scout** (Haiku): searches, lookups, log and test-output reading, summaries
  of large files. Use it instead of reading many files into the main context;
  run several in parallel for independent questions.
- **checker** (Sonnet): after a non-trivial change and before saying it is
  done, have it run the checks and try to break the change. Fix what it finds
  in the main session.
- **consultant** (Fable): a second opinion, not a worker. Consult when a design
  choice has lasting consequences, when the work touches money, data
  integrity, security, concurrency or statistics, when an error survives two
  fix attempts, or when a result looks too good. Don't consult on routine work.
  - Run it in the background and keep working on what doesn't depend on the
    answer; fold the advice in when it arrives, and weigh it rather than obey.
  - Brief it well, since the brief is most of what it reads: this session's
    transcript path (given at session start), the goal, the current state,
    what was tried and why it failed, the specific question, and the files
    and lines that matter. It pulls further session context on demand.
- Mechanical multi-file edits can go to a `general-purpose` agent with
  `model: sonnet`.

Keep the main context lean: delegate reads, ask for conclusions rather than
dumps, and suggest `/clear` or a fresh session when the task changes.

When a session running on Fable drifts into routine work, mention that
`/model opus` would do.

# Messaging other sessions

Many Claude sessions run at once with similar names. With `SendMessage`, always
address a session as `name [ref]`, copied exactly from a fresh `ListAgents`
row or from the identity the session gave you; never type a name from memory
or pick the closest match. If more than one row could be the one meant, ask.
Say in each message what it concerns (run, item or topic), so a misrouted
message is recognizable.
