#!/bin/sh
# SessionStart: tell the session where its own transcript lives, so it can
# point the `consultant` agent at it.
python3 -c '
import json, sys
path = json.load(sys.stdin).get("transcript_path")
if path:
    print(f"This session'"'"'s transcript: {path}  (pass it to the consultant agent)")
' 2>/dev/null || true
