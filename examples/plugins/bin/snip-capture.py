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


class RetryableCaptureError(ValueError):
    """Only Snip 75/70 and the wrapper deadline permit a plain retry."""


def capture_timeout(name, maximum):
    timeout = float(os.environ.get(name, str(maximum)))
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError(f"invalid {name}")
    return min(timeout, maximum)


def capture(subject):
    # Named captures reserve six seconds for fallback and time for child cleanup.
    timeout = capture_timeout("SNIP_CAPTURE_TIMEOUT_S", 31 if subject else 38)
    argv = [find_snip(), "capture", "--out", "clipboard", "--json"]
    env = dict(os.environ)
    env.pop("DICTATION_ARG_SUBJECT", None)
    cancelled = False

    def on_term(signum, frame):
        nonlocal cancelled
        cancelled = True

    def run_capture(call_argv, call_timeout):
        child = None
        try:
            if cancelled:
                raise ValueError("Snip capture cancelled")
            child = subprocess.Popen(call_argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, env=env)
            deadline = time.monotonic() + call_timeout
            while True:
                if cancelled:
                    raise ValueError("Snip capture cancelled")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    child.kill()
                    raise RetryableCaptureError("Snip timed out")
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
                error = RetryableCaptureError if child.returncode in (75, 70) else ValueError
                raise error(message)
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

    previous_handler = signal.signal(signal.SIGTERM, on_term)
    try:
        try:
            result = run_capture(argv + ["--describe", subject] if subject else argv, timeout)
            if cancelled:
                raise ValueError("Snip capture cancelled")
            return result, False
        except RetryableCaptureError:
            if cancelled:
                raise ValueError("Snip capture cancelled")
            if not subject:
                raise
        # run_capture has reaped the describe child before starting this single fallback.
        try:
            result = run_capture(argv, capture_timeout("SNIP_FALLBACK_TIMEOUT_S", 6))
            if cancelled:
                raise ValueError("Snip capture cancelled")
            return result, True
        except Exception:
            raise ValueError("Screenshot failed. Nothing was copied.") from None
    finally:
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
        result, used_fallback = capture(subject)
        if used_fallback:
            notify = f"Full screenshot copied to clipboard. Couldn't crop to {subject}."
        elif not subject:
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
