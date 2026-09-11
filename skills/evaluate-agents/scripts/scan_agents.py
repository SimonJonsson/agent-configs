#!/usr/bin/env python3
"""Report what every live Claude Code agent is doing and which model it burns.

Sources:
  - `herdr agent list`   (requires HERDR_ENV=1)   -> live agents, pane ids, session ids
  - ~/.claude/projects/*/<session>.jsonl          -> model per turn, token usage, prompts

Usage: scan_agents.py [--json] [--prompts N] [--session ID ...]
  --session ID   inspect these transcript ids instead of asking herdr
"""
import glob, json, os, re, subprocess, sys
from collections import Counter, defaultdict

PROJECTS = os.path.expanduser("~/.claude/projects")
CORRECTION = re.compile(
    r"^\s*(no\b|nope|wrong|not (that|what)|that'?s not|still (not|doesn'?t|broken)|"
    r"doesn'?t work|didn'?t work|again\b|revert|undo|why did you)", re.I)


def live_agents():
    if os.environ.get("HERDR_ENV") != "1":
        return []
    out = subprocess.run(["herdr", "agent", "list"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        return []
    return json.loads(out.stdout)["result"]["agents"]


def find_transcript(session_id):
    hits = glob.glob(os.path.join(PROJECTS, "*", f"{session_id}.jsonl"))
    return hits[0] if hits else None


def user_text(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = [b.get("text", "") for b in c if b.get("type") == "text"]
        return "\n".join(p for p in parts if p)
    return ""


def analyse(path, n_prompts):
    models, out_tok, think_tok, cache_read = Counter(), Counter(), Counter(), Counter()
    tools = Counter()
    prompts, corrections = [], 0
    title, effort, last_ts, first_ts = None, None, None, None
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = d.get("type")
            ts = d.get("timestamp")
            if ts:
                first_ts = first_ts or ts
                last_ts = ts
            if t == "ai-title":
                title = d.get("title") or d.get("value") or title
            if d.get("effort"):
                effort = d["effort"]
            if t == "assistant":
                m = d.get("message", {})
                model = m.get("model", "?")
                models[model] += 1
                u = m.get("usage", {}) or {}
                out_tok[model] += u.get("output_tokens", 0) or 0
                think_tok[model] += (u.get("output_tokens_details") or {}).get("thinking_tokens", 0) or 0
                cache_read[model] += u.get("cache_read_input_tokens", 0) or 0
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tools[b.get("name", "?")] += 1
            elif t == "user" and not d.get("isMeta") and not d.get("isSidechain"):
                txt = user_text(d.get("message", {})).strip()
                if not txt or txt.startswith("<"):
                    continue
                prompts.append(txt)
                if CORRECTION.search(txt):
                    corrections += 1
    return {
        "transcript": path,
        "title": title,
        "effort": effort,
        "started": first_ts,
        "last_activity": last_ts,
        "turns_by_model": dict(models),
        "output_tokens_by_model": dict(out_tok),
        "thinking_tokens_by_model": dict(think_tok),
        "cache_read_tokens_by_model": dict(cache_read),
        "tool_calls": dict(tools.most_common()),
        "user_prompts": len(prompts),
        "corrections": corrections,
        "recent_prompts": [p[:300].replace("\n", " ") for p in prompts[-n_prompts:]],
    }


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    n_prompts = 5
    if "--prompts" in args:
        n_prompts = int(args[args.index("--prompts") + 1])
    sessions = []
    if "--session" in args:
        i = args.index("--session") + 1
        while i < len(args) and not args[i].startswith("--"):
            sessions.append({"session": args[i]})
            i += 1
    else:
        for a in live_agents():
            sid = (a.get("agent_session") or {}).get("value")
            sessions.append({
                "pane_id": a.get("pane_id"), "agent": a.get("agent"),
                "status": a.get("agent_status"), "cwd": a.get("cwd"),
                "focused": a.get("focused"), "terminal_title": a.get("terminal_title_stripped"),
                "session": sid,
            })
    report = []
    for s in sessions:
        entry = dict(s)
        path = find_transcript(s["session"]) if s.get("session") else None
        entry.update(analyse(path, n_prompts) if path else {"transcript": None})
        report.append(entry)
    if as_json:
        print(json.dumps(report, indent=2))
        return
    if not report:
        print("no agents found (HERDR_ENV != 1 or nothing running); pass --session ID to inspect a transcript")
        return
    for e in report:
        print(f"== {e.get('pane_id', '-')}  {e.get('agent', '')}  status={e.get('status', '-')}"
              f"{'  [this pane]' if e.get('focused') else ''}")
        print(f"   cwd: {e.get('cwd')}   title: {e.get('terminal_title') or e.get('title')}")
        if not e.get("transcript"):
            print("   (no transcript found)")
            continue
        print(f"   session: {e['session']}   effort: {e.get('effort')}   last: {e.get('last_activity')}")
        for m, n in e["turns_by_model"].items():
            print(f"   model {m}: {n} turns, out={e['output_tokens_by_model'][m]} "
                  f"think={e['thinking_tokens_by_model'][m]} cache_read={e['cache_read_tokens_by_model'][m]}")
        top = ", ".join(f"{k}x{v}" for k, v in list(e["tool_calls"].items())[:6])
        print(f"   prompts: {e['user_prompts']}  corrections: {e['corrections']}  tools: {top}")
        for p in e["recent_prompts"]:
            print(f"   > {p[:160]}")
        print()


if __name__ == "__main__":
    main()
