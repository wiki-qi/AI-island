#!/usr/bin/env python3
import socket, json, time

SOCK = "/Users/wiki/Library/Application Support/NotchAgent/notch.sock"

def send(msg):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(SOCK)
    s.send((json.dumps(msg) + "\n").encode())
    s.close()

# 1. Claude Code — running, then permission request
send({"type":"sessionStart","sessionId":"demo-claude","payload":{"source":"claude","session_name":"fix auth bug"}})
time.sleep(0.3)
send({"type":"toolUse","sessionId":"demo-claude","payload":{"source":"claude","tool_name":"Read","description":"src/auth/middleware.ts"}})
time.sleep(0.3)
send({"type":"approvalRequest","sessionId":"demo-claude","payload":{"source":"claude","tool_name":"Bash","description":"$ npm test --coverage","file_path":"src/auth/middleware.ts"}})
time.sleep(0.3)

# 2. Codex — running
send({"type":"sessionStart","sessionId":"demo-codex","payload":{"source":"codex","session_name":"build REST API"}})
time.sleep(0.3)
send({"type":"toolUse","sessionId":"demo-codex","payload":{"source":"codex","tool_name":"Write","description":"src/routes/users.ts — New file (47 lines)"}})
time.sleep(0.3)

# 3. Gemini — completed
send({"type":"sessionStart","sessionId":"demo-gemini","payload":{"source":"gemini","session_name":"optimize queries"}})
time.sleep(0.3)
send({"type":"sessionCompleted","sessionId":"demo-gemini","payload":{"source":"gemini","summary":"Optimized 3 slow queries, reduced avg response time by 40%."}})

print("Done: 3 sessions (approval + running + completed)")
