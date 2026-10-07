#!/usr/bin/env python3
"""Exit 0 below Codex's weekly 95% backstop, 2 at it, 3 if unavailable."""
import datetime as dt, json, math, os, select, subprocess, sys, time
def weekly_bucket(result):
    if not isinstance(result, dict):
        return None
    by_id = result.get("rateLimitsByLimitId")
    codex = by_id.get("codex") if isinstance(by_id, dict) else None
    sources = [source for source in (codex, result.get("rateLimits")) if isinstance(source, dict)]
    choices = [source.get(key) for source in sources for key in ("primary", "secondary")]
    valid = [b for b in choices if isinstance(b, dict) and b.get("windowDurationMins") == 10080
             and isinstance(b.get("usedPercent"), (int, float))
             and math.isfinite(b["usedPercent"]) and 0 <= b["usedPercent"] <= 100]
    return max(valid, key=lambda b: b["usedPercent"]) if valid else None
def read_limits():
    messages = [
        {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "prism-budget-check", "version": "1.0"}}},
        {"method": "initialized", "params": {}},
        {"id": 2, "method": "account/rateLimits/read", "params": {}},
    ]
    process = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        process.stdin.write(json.dumps(messages[0]).encode() + b"\n")
        process.stdin.flush()
        pending, deadline, initialized = b"", time.monotonic() + 20, False
        while time.monotonic() < deadline:
            ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            pending += chunk
            if len(pending) > 1000000:
                break
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                try:
                    message = json.loads(line)
                except (ValueError, UnicodeError):
                    continue
                if not isinstance(message, dict):
                    continue
                if message.get("id") == 1:
                    if message.get("error") or not isinstance(message.get("result"), dict):
                        return None
                    process.stdin.write(b"".join(json.dumps(m).encode() + b"\n" for m in messages[1:]))
                    process.stdin.flush()
                    initialized = True
                if message.get("id") == 2:
                    return message.get("result") if initialized and not message.get("error") else None
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
def main():
    try:
        bucket = weekly_bucket(read_limits() or {})
    except Exception:
        bucket = None
    if bucket is None:
        print("Codex weekly budget unavailable; stop and save a checkpoint.")
        return 3
    used, reset = bucket["usedPercent"], bucket.get("resetsAt")
    when = dt.datetime.fromtimestamp(reset, dt.timezone.utc).isoformat() if isinstance(reset, (int, float)) else "unknown"
    print(f"Codex weekly: {used:g}% used, {100-used:g}% remaining; reset {when}.")
    return 2 if used >= 95 else 0
if __name__ == "__main__":
    sys.exit(main())
