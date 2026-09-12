"""Run with python3 -m unittest discover -s tests -v; no network or credentials needed."""

import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class HookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.workspace = self.root / "workspace & <test>"
        self.workspace.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Keep PATH controlled so each hash utility is tested independently.
        for name in ("bash", "basename", "awk", "git", "dirname", "find",
                     "sort", "mkdir", "mktemp", "mv", "xargs", "cat"):
            source = "/bin/bash" if name == "bash" else shutil.which(name)
            (self.bin / name).symlink_to(source)
        curl = self.bin / "curl"
        curl.write_text(
            '#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE"\n'
            'printf \'{"ok":true,"result":{"message_id":123}}\\n\'\n'
        )
        curl.chmod(0o755)
        credentials = self.root / "telegram.env"
        credentials.write_text(
            'CYBERVISOR_TELEGRAM_BOT_TOKEN="test-token"\n'
            'CYBERVISOR_TELEGRAM_CHAT_ID="test-chat"\n'
        )
        self.capture = self.root / "request.txt"
        self.env = {
            "PATH": str(self.bin), "HOME": str(self.root),
            "CYBERVISOR_TELEGRAM_ENV_FILE": str(credentials),
            "CAPTURE": str(self.capture), "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
        }

    def run_hook(self, **variables):
        result = subprocess.run(
            ["/bin/bash", str(ROOT / "send-stage-notification.sh")],
            cwd=self.workspace, env={**self.env, **variables},
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.capture.read_text()

    def git(self, repo, *args):
        return subprocess.check_output(
            [str(self.bin / "git"), "-C", str(repo), *args],
            env=self.env, text=True, stderr=subprocess.PIPE,
        ).strip()

    def baseline(self):
        key = hashlib.md5(str(self.workspace).encode()).hexdigest()
        return self.root / ".cybervisor/hooks/state" / f"baseline_{key}.txt"

    def exercise_hash(self, utility):
        source = shutil.which(utility)
        if not source:
            self.skipTest(f"{utility} is not installed")
        (self.bin / utility).symlink_to(source)

        # A workspace with no repositories must produce an empty baseline.
        message = self.run_hook(CYBERVISOR_HOOK_PHASE="before_stage")
        self.assertIn("Starting", message)
        self.assertIn("workspace &amp; &lt;test&gt;", message)
        self.assertEqual(self.baseline().read_text(), "")

        nested = self.workspace / "nested repo"
        nested.mkdir()
        for repo in (self.workspace, nested):
            self.git(repo, "init")
            (repo / "file.txt").write_text("initial\n")
            self.git(repo, "add", "file.txt")
            self.git(repo, "commit", "-m", "chore: init")

        self.run_hook(CYBERVISOR_HOOK_PHASE="before_stage",
                      CYBERVISOR_STAGE_NAME="Commit")
        self.assertEqual(self.baseline().read_text().splitlines(), [
            f".\t{self.git(self.workspace, 'rev-parse', 'HEAD')}",
            f"nested repo\t{self.git(nested, 'rev-parse', 'HEAD')}",
        ])
        variables = {"CYBERVISOR_STAGE_NAME": "Commit",
                     "CYBERVISOR_STAGE_SUCCESS": "true"}
        self.assertNotIn("Commit Report", self.run_hook(**variables))

        for repo in (self.workspace, nested):
            (repo / "file.txt").write_text("initial\nadded\n")
            self.git(repo, "commit", "-am", "fix: handle <macOS> & Linux")
        message = self.run_hook(**variables)
        self.assertIn("Completed", message)
        self.assertIn("Commit Report", message)
        self.assertIn("<b>workspace</b>", message)
        self.assertIn("<b>nested repo</b>", message)
        self.assertEqual(message.count("fix: handle &lt;macOS&gt; &amp; Linux"), 2)
        self.assertIn("1 file changed, 1 insertion(+)", message)
        self.assertIn("chat_id=test-chat", message)
        self.assertIn("parse_mode=HTML", message)
        self.assertIn("Failed", self.run_hook(CYBERVISOR_STAGE_SUCCESS="false"))

    def test_macos_md5(self):
        self.exercise_hash("md5")

    def test_linux_md5sum(self):
        self.exercise_hash("md5sum")


if __name__ == "__main__":
    unittest.main()
