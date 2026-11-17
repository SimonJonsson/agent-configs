#!/usr/bin/env python3
"""Render a Claude Code session transcript (.jsonl) as compact, readable text.

Used by the `consultant` agent to catch up on a live session it cannot see.

    session-digest.py TRANSCRIPT [--max-chars N] [--result-chars N]
    session-digest.py TRANSCRIPT --grep PATTERN [--max-chars N]

Default: the recent tail of the session. User messages and assistant replies
in full, tool calls as one line each, tool results truncated; the opening user
request is always kept, older parts are dropped beyond --max-chars.

--grep: only the entries matching PATTERN (case-insensitive regex), each with
its neighbours, for digging into a specific earlier point.
"""
import argparse
import json
import re

REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)


def clean(text):
    return REMINDER.sub("", text).strip()


def tool_line(block):
    name = block.get("name", "?")
    inp = block.get("input") or {}
    for key in ("description", "command", "file_path", "pattern", "prompt", "url", "query"):
        if inp.get(key):
            val = str(inp[key]).replace("\n", " ")
            return f"-> {name}: {val[:200]}"
    return f"-> {name}"


def result_text(block):
    content = block.get("content")
    if isinstance(content, list):
        content = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
    return clean(str(content or ""))


def render(path, result_chars):
    out = []
    with open(path, errors="replace") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("isSidechain") or entry.get("type") not in ("user", "assistant"):
                continue
            msg = entry.get("message") or {}
            content = msg.get("content")
            role = entry["type"]
            if entry.get("isCompactSummary"):
                out.append(f"## Earlier context (compacted summary)\n{clean(str(content))}")
                continue
            if isinstance(content, str):
                text = clean(content)
                if text:
                    out.append(f"## {role.capitalize()}\n{text}")
                continue
            for block in content or []:
                kind = block.get("type")
                if kind == "text" and clean(block.get("text", "")):
                    out.append(f"## {role.capitalize()}\n{clean(block['text'])}")
                elif kind == "tool_use":
                    out.append(tool_line(block))
                elif kind == "tool_result":
                    text = result_text(block)
                    flag = "ERROR " if block.get("is_error") else ""
                    if len(text) > result_chars:
                        text = text[:result_chars] + f" ...[{len(text) - result_chars} chars cut]"
                    out.append(f"   <- {flag}{text}")
                elif kind == "image":
                    out.append(f"## {role.capitalize()}\n[image]")
    return out


def grep(parts, pattern, max_chars):
    rx = re.compile(pattern, re.I)
    keep = set()
    for i, p in enumerate(parts):
        if rx.search(p):
            keep.update(range(max(i - 1, 0), min(i + 2, len(parts))))
    out, prev, size = [], None, 0
    for i in sorted(keep):
        if prev is not None and i != prev + 1:
            out.append("[...]")
        size += len(parts[i]) + 1
        if size > max_chars:
            out.append("[... more matches omitted; narrow the pattern ...]")
            break
        out.append(parts[i])
        prev = i
    return "\n".join(out) if out else f"no matches for {pattern!r}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("--max-chars", type=int, default=24_000)
    ap.add_argument("--grep", metavar="PATTERN")
    ap.add_argument("--result-chars", type=int, default=400)
    args = ap.parse_args()

    parts = render(args.transcript, args.result_chars)
    if not parts:
        return
    if args.grep:
        print(grep(parts, args.grep, args.max_chars))
        return
    first = next((i for i, p in enumerate(parts) if p.startswith("## User")), 0)
    head, rest = parts[: first + 1], parts[first + 1 :]
    budget = args.max_chars - sum(len(p) for p in head)
    kept = []
    for p in reversed(rest):
        budget -= len(p) + 1
        if budget < 0:
            kept.append("[... earlier part of the session omitted ...]")
            break
        kept.append(p)
    print("\n".join(head + list(reversed(kept))))


if __name__ == "__main__":
    main()
