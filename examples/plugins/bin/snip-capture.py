#!/usr/bin/env python3
"""Capture with Snip; only validated stdin arguments can request a crop."""

import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def find_snip():
    override = os.environ.get("SNIP_BIN")
    candidates = [Path(override).expanduser()] if override else [
        Path.home() / "bin/snip", Path("/opt/homebrew/bin/snip"), Path.home() / ".local/bin/snip",
    ]
    for path in candidates:
        if path.is_absolute() and path.is_file() and os.access(path, os.X_OK):
            return str(path)
    raise ValueError("snip not found")


def capture(subject):
    timeout = float(os.environ.get("SNIP_CAPTURE_TIMEOUT_S", "38"))
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("invalid SNIP_CAPTURE_TIMEOUT_S")
    # Keep time for cleanup before the manifest's 40-second crop timeout.
    timeout = min(timeout, 38)
    argv = [find_snip(), "capture", "--out", "clipboard", "--json"]
    env = dict(os.environ)
    env.pop("DICTATION_ARG_SUBJECT", None)
    if subject:
        argv += ["--describe", subject]

    cancelled = False

    def on_term(signum, frame):
        nonlocal cancelled
        cancelled = True

    previous_handler = signal.signal(signal.SIGTERM, on_term)
    child = None
    try:
        child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        deadline = time.monotonic() + timeout
        while True:
            if cancelled:
                raise ValueError("Snip capture cancelled")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Snip timed out")
            try:
                stdout, _ = child.communicate(timeout=min(remaining, 0.2))
                break
            except subprocess.TimeoutExpired:
                continue
        if cancelled:
            raise ValueError("Snip capture cancelled")
        if child.returncode != 0:
            message = {69: "Snip isn't running", 75: "Snip timed out"}.get(
                child.returncode, f"Snip capture failed ({child.returncode})")
            raise ValueError(message)
        result = json.loads(stdout)
        if not isinstance(result, dict) or result.get("ok") is not True:
            raise ValueError("Snip capture failed")
        return result
    finally:
        if child is not None:
            if child.poll() is None:
                child.terminate()
                try:
                    child.communicate(timeout=0.5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.communicate()
            else:
                child.wait()
        signal.signal(signal.SIGTERM, previous_handler)


def main():
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict) or not isinstance(payload.get("args", {}), dict):
            raise ValueError("invalid plugin payload")
        subject = payload.get("args", {}).get("subject", "")
        if not isinstance(subject, str):
            raise ValueError("invalid subject")
        subject = subject.strip()
        result = capture(subject)
        if not subject:
            notify = "Screenshot copied to clipboard"
        elif result.get("cropped"):
            notify = f"Screenshot of {subject} copied to clipboard"
        else:
            notify = f"Full screenshot copied: {result.get('reason') or 'No matching subject'}"
        print(json.dumps({"notify": notify}, ensure_ascii=False))
        return 0
    except Exception as error:
        # Never return 2: Dictation treats that code as a request to insert the transcript.
        message = " ".join(str(error).splitlines()) or "Snip capture failed"
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
