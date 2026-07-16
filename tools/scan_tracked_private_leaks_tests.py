import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "scan-tracked-private-leaks.sh"


class ScanTrackedPrivateLeaksTests(unittest.TestCase):
    def test_allows_reviewed_public_tracker_fixtures(self):
        with self.make_repo() as repo:
            for path in [
                "tests/fixtures/minimal.xm",
                "tests/reference-xm/generated/basic-instrument-sample.xm",
                "tests/reference-xm/generated/multi-pattern-loop-boundary.xm",
                "tests/reference-xm/generated/instrument-sustained-defaults.xm",
                "tests/reference-xm/generated/instrument-metadata-matrix.xm",
                "tests/fixtures/minimal.mod",
            ]:
                self.write_file(repo, path, b"synthetic public fixture")
            self.git_add(repo)

            result = self.run_scan(repo)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("passed", result.stdout)

    def test_rejects_tracked_generated_artifact_paths(self):
        with self.make_repo() as repo:
            self.write_file(repo, "reports/candidate.wav", b"RIFF")
            self.git_add(repo)

            result = self.run_scan(repo)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("candidate.wav", result.stderr)
            self.assertIn("artifact", result.stderr)

    def test_rejects_unapproved_tracked_tracker_modules(self):
        with self.make_repo() as repo:
            self.write_file(repo, "tests/private-module.xm", b"synthetic")
            self.git_add(repo)

            result = self.run_scan(repo)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tests/private-module.xm", result.stderr)
            self.assertIn("allowlist", result.stderr)

    def test_rejects_tracked_private_marker_content(self):
        with self.make_repo() as repo:
            private_path = "/" + "Users" + "/maintainer/private-module.xm"
            self.write_file(repo, "notes.txt", f"input={private_path}\n".encode("utf-8"))
            self.git_add(repo)

            result = self.run_scan(repo)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("notes.txt:1", result.stderr)
            self.assertIn("blocked marker", result.stderr)

    def test_ignores_untracked_local_outputs(self):
        with self.make_repo() as repo:
            self.write_file(repo, ".gitignore", b".gstack/\n*.profraw\n")
            self.write_file(repo, "README.md", b"public")
            self.git_add(repo)
            self.write_file(repo, ".gstack/browse-audit.jsonl", b"local")
            self.write_file(repo, "default.profraw", b"local")

            result = self.run_scan(repo)

            self.assertEqual(result.returncode, 0, result.stderr)

    def make_repo(self):
        return TemporaryGitRepo()

    def run_scan(self, repo):
        return subprocess.run(
            ["bash", "scripts/scan-tracked-private-leaks.sh"],
            cwd=repo,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def git_add(self, repo):
        subprocess.run(["git", "add", "."], cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def write_file(self, repo, relative_path, data):
        path = Path(repo) / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


class TemporaryGitRepo:
    def __enter__(self):
        self._temp = tempfile.TemporaryDirectory()
        self.path = Path(self._temp.name)
        (self.path / "scripts").mkdir()
        shutil.copy2(SCRIPT_PATH, self.path / "scripts" / "scan-tracked-private-leaks.sh")
        subprocess.run(["git", "init", "-q"], cwd=self.path, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return self.path

    def __exit__(self, exc_type, exc, tb):
        self._temp.cleanup()


if __name__ == "__main__":
    unittest.main()
