"""R283–R298: isolated wrapper/manifest contract; no installed Snip required."""
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
    "grab a screenshot of {subject}", "screenshot", "screenshot this",
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
Path(os.environ["FAKE_RECORD"]).write_text(json.dumps({
    "argv": sys.argv[1:], "env": dict(os.environ), "pid": os.getpid(),
}))
time.sleep(float(os.environ.get("FAKE_SLEEP", "0")))
print(os.environ.get("FAKE_OUTPUT", '{"ok": true, "cropped": false}'))
sys.exit(int(os.environ.get("FAKE_EXIT", "0")))
''')
        self.snip.chmod(0o700)
        self.env = dict(os.environ, SNIP_BIN=str(self.snip), FAKE_RECORD=str(self.record),
                        DICTATION_ARG_SUBJECT="stale poisoned subject", HOME=str(self.directory))
        # Keep the fixture independent of inherited settings.
        for key in ["SNIP_CAPTURE_TIMEOUT_S", "FAKE_SLEEP", "FAKE_OUTPUT", "FAKE_EXIT"]:
            self.env.pop(key, None)

    def run_wrapper(self, args=None, raw=None, **env):
        payload = raw if raw is not None else json.dumps({"plugin": "screenshot", "args": args or {},
                                                         "context": {}, "version": 1})
        return subprocess.run([sys.executable, str(WRAPPER)], input=payload, text=True,
                              capture_output=True, env=dict(self.env, **env), timeout=8)

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

    def test_R285_exit_messages_never_fall_back_or_exit_two(self):
        for code, message in [(69, "Snip isn't running"), (75, "Snip timed out"),
                              (70, "Snip capture failed (70)"), (64, "Snip capture failed (64)"),
                              (2, "Snip capture failed (2)")]:
            with self.subTest(code=code):
                self.assert_failure(self.run_wrapper({"subject": "chart"}, FAKE_EXIT=str(code)), message)

    def test_R297_malformed_stdin_is_one_error_line_and_never_exit_two(self):
        for raw in ["", "not json\nmore text", "[]", "null", '{"args": []}',
                    '{"args":{"subject":42}}']:
            with self.subTest(raw=raw):
                self.assert_failure(self.run_wrapper(raw=raw))
                self.assertFalse(self.record.exists(), "Bad input must not start snip")

    def test_R297_bad_snip_output_is_a_failure(self):
        for output in ["invalid json", "null", "[]", '{"ok": false}']:
            with self.subTest(output=output):
                self.assert_failure(self.run_wrapper(FAKE_OUTPUT=output))

    def start_sleeping_wrapper(self, **env):
        process = subprocess.Popen([sys.executable, str(WRAPPER)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=dict(self.env, FAKE_SLEEP="5", **env))
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
        process.stdin.write(json.dumps({"args": {"subject": "chart"}}))
        process.stdin.close()
        process.stdin = None
        deadline = time.monotonic() + 3
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
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 1, stderr)
        self.assertEqual(stdout, "")
        self.assertEqual(len(stderr.splitlines()), 1, stderr)
        self.assert_child_gone(pid)

    def test_R297_own_timeout_kills_and_reaps_child(self):
        process, pid = self.start_sleeping_wrapper(SNIP_CAPTURE_TIMEOUT_S="1")
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 1, stderr)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr.strip(), "Snip timed out")
        self.assert_child_gone(pid)

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
