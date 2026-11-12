"""Release-history synchronization checks; no engine, network or build output."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("changelog", Path(__file__).resolve().parents[1] / "tools/changelog.py")
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)

TEXT = C.SEPARATOR + """
Version: 0.2.7
Date: 2026-11-12
  Bugfixes:
    - Keep labels aligned. Reported by HorizonBeta.
      (https://github.com/TTLouis/factorio-production-flow/issues/2)
  Features:
    - Add Chinese support.
""" + C.SEPARATOR + """
Version: 0.2.6
  Changes:
    - Earlier change.
"""


class ChangelogTests(unittest.TestCase):
    def fixture(self):
        scratch = Path(__file__).resolve().parent / "out/changelog-fixtures"
        scratch.mkdir(parents=True, exist_ok=True)
        temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        (root / C.SOURCE).parent.mkdir(parents=True)
        (root / C.SOURCE).write_text(TEXT, encoding="utf-8")
        (root / "mod/production-flow/info.json").write_text(json.dumps({"version": "0.2.7"}))
        return root

    def test_categories_continuations_and_reporter_are_preserved(self):
        releases = C.parse(TEXT)
        self.assertEqual([r["version"] for r in releases], ["0.2.7", "0.2.6"])
        self.assertEqual(releases[0]["date"], "2026-11-12")
        self.assertIsNone(releases[1]["date"])
        notes = C.render_release(releases[0])
        self.assertIn("### Bugfixes\n", notes)
        self.assertIn("Reported by HorizonBeta. (https://github.com/", notes)
        self.assertIn("### Features\n\n- Add Chinese support.", notes)
        self.assertNotIn("0.2.6", notes)

    def test_crlf_input_renders_identically(self):
        self.assertEqual(C.render(C.parse(TEXT)), C.render(C.parse(TEXT.replace("\n", "\r\n"))))

    def test_root_check_rejects_missing_or_stale_copy(self):
        root = self.fixture()
        with self.assertRaisesRegex(ValueError, "Root CHANGELOG.md is stale"):
            C.check(root)
        target = root / "CHANGELOG.md"
        target.write_text(C.render(C.load(root)), encoding="utf-8")
        C.check(root)
        target.write_text(target.read_text(encoding="utf-8").replace("Add Chinese support.", "Different notes."), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "stale"):
            C.check(root)

    def test_manifest_version_must_match_latest_history(self):
        root = self.fixture()
        (root / "mod/production-flow/info.json").write_text('{"version":"0.2.8"}')
        with self.assertRaisesRegex(ValueError, "differs from info.json"):
            C.load(root)

    def test_invalid_history_is_rejected(self):
        examples = ["", TEXT + TEXT, TEXT.replace("Date: 2026-11-12", "Date: 2026-02-30"),
                    TEXT.replace("Date: 2026-11-12", "Date: 2026-1-2"),
                    TEXT.replace("    - Add Chinese support.", "    Add Chinese support."),
                    TEXT.replace("Version: 0.2.6", "Version: 0.2.8"),
                    TEXT.replace("    - Add Chinese support.", "    - ")]
        for text in examples:
            with self.subTest(text=text[-80:]), self.assertRaises(ValueError):
                C.parse(text)

    def test_current_repository_is_synchronized(self):
        C.check()

    def test_release_command_uses_only_requested_source_entry(self):
        result = subprocess.run([sys.executable, str(C.ROOT / "tools/changelog.py"), "--release", "0.2.6"],
                                capture_output=True, encoding="utf-8", check=True)
        self.assertIn("## 0.2.6", result.stdout)
        self.assertNotIn("## 0.2.7", result.stdout)
        self.assertIn("Jump to the selected space platform", result.stdout)
        missing = subprocess.run([sys.executable, str(C.ROOT / "tools/changelog.py"), "--release", "9.9.9"], capture_output=True)
        self.assertNotEqual(missing.returncode, 0)


if __name__ == "__main__":
    unittest.main()
