"""R283–R305: isolated wrapper/manifest contract; no installed Snip required."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "examples/plugins/bin/snip-capture.py"
IGNORE_WORDS = [
    "um", "uh", "er", "like", "so", "just", "please", "this", "that", "it", "here", "there",
    "the", "a", "an", "my", "whole", "entire", "full", "screen", "everything", "now",
]
TRIGGERS = [
    "take a screenshot", "take a screenshot of {subject}", "grab a screenshot",
    "grab a screenshot of {subject}", "screenshot", "screenshot this", "screenshot that",
    "screenshot the {subject}", "screenshot that {subject}",
]


class SnipCaptureTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(WRAPPER.is_file(), "R297 wrapper is missing: examples/plugins/bin/snip-capture.py")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.record = self.directory / "record.json"
        self.snip = self.directory / "fake snip"
        self.snip.write_text(f"#!{sys.executable}\n" + '''
import json
import os
import sys
import time
from pathlib import Path
record = {"argv": sys.argv[1:], "env": dict(os.environ), "pid": os.getpid()}
with open(os.environ["FAKE_RECORD"] + ".jsonl", "a") as history:
    history.write(json.dumps(record) + "\\n")
Path(os.environ["FAKE_RECORD"]).write_text(json.dumps(record))
prefix = "FAKE_DESCRIBE_" if "--describe" in sys.argv else "FAKE_"
def setting(name, default):
    return os.environ.get(prefix + name, os.environ.get("FAKE_" + name, default))
time.sleep(float(setting("SLEEP", "0")))
print(setting("OUTPUT", '{"ok": true, "cropped": false}'))
sys.exit(int(setting("EXIT", "0")))
''')
        self.snip.chmod(0o700)
        self.env = dict(os.environ, SNIP_BIN=str(self.snip), FAKE_RECORD=str(self.record),
                        DICTATION_ARG_SUBJECT="stale poisoned subject", HOME=str(self.directory))
        # Keep the fixture independent of inherited settings.
        for key in ["SNIP_CAPTURE_TIMEOUT_S", "SNIP_FALLBACK_TIMEOUT_S", "FAKE_SLEEP",
                    "FAKE_OUTPUT", "FAKE_EXIT", "FAKE_DESCRIBE_SLEEP", "FAKE_DESCRIBE_OUTPUT",
                    "FAKE_DESCRIBE_EXIT"]:
            self.env.pop(key, None)

    def run_wrapper(self, args=None, raw=None, **env):
        payload = raw if raw is not None else json.dumps({"plugin": "screenshot", "args": args or {},
                                                         "context": {}, "version": 1})
        return subprocess.run([sys.executable, str(WRAPPER)], input=payload, text=True,
                              capture_output=True, env=dict(self.env, **env), timeout=12)

    def invocations(self):
        return [json.loads(line) for line in
                Path(str(self.record) + ".jsonl").read_text().splitlines()]

    def assert_failure(self, result, message=None):
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)
        if message is not None:
            self.assertEqual(result.stderr.strip(), message)

    def test_R285_R297_no_subject_omits_describe_and_removes_poisoned_env(self):
        for args in [{}, {"subject": ""}, {"subject": "   "}]:
            with self.subTest(args=args):
                result = self.run_wrapper(args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"notify": "Screenshot copied to clipboard"})
                record = json.loads(self.record.read_text())
                self.assertEqual(record["argv"], ["capture", "--out", "clipboard", "--json"])
                self.assertNotIn("DICTATION_ARG_SUBJECT", record["env"])

    def test_R285_subject_comes_from_stdin_and_is_one_literal_argument(self):
        subject = 'the Slack window; $(touch nope) "chart"'
        result = self.run_wrapper({"subject": subject}, FAKE_OUTPUT='{"ok":true,"cropped":true}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.record.read_text())["argv"],
                         ["capture", "--out", "clipboard", "--json", "--describe", subject])
        self.assertEqual(json.loads(result.stdout), {"notify": f"Screenshot of {subject} copied to clipboard"})

    def test_R285_R286_uncropped_reason_is_plain_text(self):
        reason = '<b>No matching chart</b> & *try again*\nsecond line'
        result = self.run_wrapper({"subject": "chart"},
                                  FAKE_OUTPUT=json.dumps({"ok": True, "cropped": False, "reason": reason}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"notify": f"Full screenshot copied: {reason}"})

    def test_R285_R305_nonretryable_exit_messages_never_fall_back_or_exit_two(self):
        for index, (code, message) in enumerate([(69, "Snip isn't running"), (64, "Snip capture failed (64)"),
                              (2, "Snip capture failed (2)")], 1):
            with self.subTest(code=code):
                self.assert_failure(self.run_wrapper({"subject": "chart"}, FAKE_EXIT=str(code)), message)
                self.assertEqual(len(self.invocations()), index)

    def test_R297_malformed_stdin_is_one_error_line_and_never_exit_two(self):
        for raw in ["", "not json\nmore text", "[]", "null", '{"args": []}',
                    '{"args":{"subject":42}}']:
            with self.subTest(raw=raw):
                self.assert_failure(self.run_wrapper(raw=raw))
                self.assertFalse(self.record.exists(), "Bad input must not start snip")

    def test_R297_bad_snip_output_is_a_failure(self):
        for index, output in enumerate(["invalid json", "null", "[]", '{"ok": false}'], 1):
            with self.subTest(output=output):
                self.assert_failure(self.run_wrapper({"subject": "chart"}, FAKE_OUTPUT=output))
                self.assertEqual(len(self.invocations()), index)

    def start_sleeping_wrapper(self, subject="chart", **env):
        process = subprocess.Popen([sys.executable, str(WRAPPER)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=dict(self.env, FAKE_SLEEP="10", **env))
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.communicate()
            if self.record.exists():
                pid = json.loads(self.record.read_text())["pid"]
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        self.addCleanup(cleanup)
        process.stdin.write(json.dumps({"args": {"subject": subject}}))
        process.stdin.close()
        process.stdin = None
        deadline = time.monotonic() + 6
        while not self.record.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(self.record.exists(), "fake snip did not start")
        return process, json.loads(self.record.read_text())["pid"]

    def assert_child_gone(self, pid):
        with self.assertRaises(ProcessLookupError, msg="snip child must be reaped"):
            os.kill(pid, 0)

    def test_R297_sigterm_forwards_to_child_and_waits(self):
        process, pid = self.start_sleeping_wrapper()
        process.terminate()
        stdout, stderr = process.communicate(timeout=6)
        self.assertEqual(process.returncode, 1, stderr)
        self.assertEqual(stdout, "")
        self.assertEqual(len(stderr.splitlines()), 1, stderr)
        self.assert_child_gone(pid)
        self.assertEqual(len(self.invocations()), 1, "Cancellation must not start fallback")

    def test_R297_own_timeout_kills_and_reaps_child(self):
        process, pid = self.start_sleeping_wrapper(subject="", SNIP_CAPTURE_TIMEOUT_S="4")
        stdout, stderr = process.communicate(timeout=6)
        self.assertEqual(process.returncode, 1, stderr)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr.strip(), "Snip timed out")
        self.assert_child_gone(pid)

    def assert_fallback_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(json.loads(result.stdout), {
            "notify": "Full screenshot copied to clipboard. Couldn't crop to chart."})
        calls = self.invocations()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]["argv"],
                         ["capture", "--out", "clipboard", "--json", "--describe", "chart"])
        self.assertEqual(calls[1]["argv"], ["capture", "--out", "clipboard", "--json"])
        for call in calls:
            self.assertNotIn("DICTATION_ARG_SUBJECT", call["env"])

    def test_R305_describe_exit_75_falls_back(self):
        self.assert_fallback_success(self.run_wrapper({"subject": "chart"}, FAKE_DESCRIBE_EXIT="75"))

    def test_R305_describe_exit_70_falls_back(self):
        self.assert_fallback_success(self.run_wrapper({"subject": "chart"}, FAKE_DESCRIBE_EXIT="70"))

    def test_R305_describe_deadline_falls_back_and_reaps_child(self):
        result = self.run_wrapper({"subject": "chart"}, FAKE_DESCRIBE_SLEEP="10",
                                  SNIP_CAPTURE_TIMEOUT_S="4", SNIP_FALLBACK_TIMEOUT_S="4")
        self.assert_fallback_success(result)
        self.assert_child_gone(self.invocations()[0]["pid"])

    def test_R305_exit_69_has_no_fallback(self):
        self.assert_failure(self.run_wrapper({"subject": "chart"}, FAKE_EXIT="69"),
                            "Snip isn't running")
        self.assertEqual(len(self.invocations()), 1)

    def test_R305_bare_exit_75_has_no_fallback(self):
        self.assert_failure(self.run_wrapper(FAKE_EXIT="75"), "Snip timed out")
        self.assertEqual(len(self.invocations()), 1)

    def test_R305_fallback_failure_has_one_error_line(self):
        result = self.run_wrapper({"subject": "chart"}, FAKE_EXIT="70")
        self.assert_failure(result, "Screenshot failed. Nothing was copied.")
        self.assertEqual(len(self.invocations()), 2)

    def test_R305_fallback_deadline_has_one_error_line_and_reaps_child(self):
        result = self.run_wrapper({"subject": "chart"}, FAKE_DESCRIBE_EXIT="75",
                                  FAKE_SLEEP="10", FAKE_DESCRIBE_SLEEP="0",
                                  SNIP_FALLBACK_TIMEOUT_S="4")
        self.assert_failure(result, "Screenshot failed. Nothing was copied.")
        self.assertEqual(len(self.invocations()), 2)
        self.assert_child_gone(self.invocations()[1]["pid"])

    def test_R297_missing_snip_is_one_error_line(self):
        self.assert_failure(self.run_wrapper(SNIP_BIN=str(self.directory / "missing")), "snip not found")

    def test_R297_finds_snip_in_home_bin_without_path_lookup(self):
        target = self.directory / "bin/snip"
        target.parent.mkdir()
        self.snip.rename(target)
        self.env.pop("SNIP_BIN")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.record.exists())

    def test_R298_wrapper_is_executable(self):
        self.assertTrue(os.access(WRAPPER, os.X_OK))


class ScreenshotManifestTests(unittest.TestCase):
    def test_R287_R298_full_replacement_manifest(self):
        path = ROOT / "examples/plugins/screenshot.json"
        self.assertTrue(path.is_file(), "R287 screenshot manifest is missing")
        manifest = json.loads(path.read_text())
        self.assertEqual(manifest["name"], "screenshot")
        self.assertEqual(manifest["action"]["type"], "exec")
        self.assertEqual(manifest["action"]["path"], "bin/snip-capture.py")
        self.assertEqual(manifest["action"].get("argv", []), [])
        self.assertEqual(manifest["timeout_s"], 15)
        self.assertEqual(manifest["timeout_with_args_s"], 40)
        self.assertEqual(manifest["confirm_delay_s"], 0)
        self.assertEqual(manifest["args"]["subject"]["ignore_words"], IGNORE_WORDS)
        self.assertFalse(manifest["args"]["subject"].get("required", False))
        self.assertEqual(manifest["triggers"], TRIGGERS)


if __name__ == "__main__":
    unittest.main()
