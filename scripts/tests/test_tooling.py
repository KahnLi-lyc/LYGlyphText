"""工程检查的边界回归；全部使用临时仓库，不依赖 Simulator 或网络。"""

import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("check_repository", PROJECT / "scripts/check_repository.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class ToolingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_valid_local_links_parentheses_spaces_and_external_urls(self):
        self.write("docs/note (one).md", "# Note\n")
        self.write("README.md", '[note](<docs/note (one).md>)\n[encoded](docs/note%20%28one%29.md#section)\n[Apple](https://example.com/api(_:))\n[ref]: <docs/note (one).md>\n')
        CHECKER.verify_docs(self.root)

    def test_broken_new_untracked_link_fails(self):
        self.write("README.md", "[broken](missing.md)\n")
        with self.assertRaisesRegex(CHECKER.CheckFailure, "Missing local link"):
            CHECKER.verify_docs(self.root)

    def test_code_examples_are_not_local_links(self):
        self.write("README.md", "```md\n[example](missing.md)\n```\n`[example](also-missing.md)`\n")
        CHECKER.verify_docs(self.root)

    def test_unclosed_fence_fails(self):
        self.write("README.md", "```swift\nlet number = 1\n")
        with self.assertRaisesRegex(CHECKER.CheckFailure, "Unclosed Markdown fence"):
            CHECKER.verify_docs(self.root)

    def test_links_cannot_escape_or_publish_local_paths(self):
        outside = self.base / "outside.md"
        outside.write_text("# Private\n", encoding="utf-8")
        for target in ["../outside.md", str(outside), outside.as_uri()]:
            with self.subTest(target=target):
                self.write("README.md", f"[outside]({target})\n")
                with self.assertRaises(CHECKER.CheckFailure):
                    CHECKER.verify_docs(self.root)

    def test_symlink_cannot_expand_check_scope(self):
        outside = self.base / "outside.md"
        outside.write_text("# Private\n", encoding="utf-8")
        (self.root / "linked.md").symlink_to(outside)
        with self.assertRaisesRegex(CHECKER.CheckFailure, "outside root"):
            CHECKER.repository_files(self.root)

    def test_ignored_and_generated_files_do_not_enter_scope(self):
        self.write(".gitignore", "References/\n.build/\n")
        self.write("References/ThirdParty/README.md", "[broken](missing.md)\n")
        self.write(".build/Cached.swift", "let malformed=1\n")
        self.write("Sources/Generated/Code.swift", "let generated=1\n")
        self.write("README.md", "# Project\n")
        CHECKER.verify_docs(self.root)
        names = [str(path.relative_to(self.root)) for path in CHECKER.repository_files(self.root)]
        self.assertEqual(names, [".gitignore", "README.md"])

    def test_invalid_shell_and_text_conventions_fail(self):
        path = self.write("scripts/bad.sh", "#!/bin/bash\nif then\n")
        with self.assertRaises(CHECKER.CheckFailure):
            CHECKER.verify_docs(self.root)
        path.unlink()
        for data in [b"# No newline", b"# CRLF\r\n", b"# trailing \n"]:
            with self.subTest(data=data):
                (self.root / "README.md").write_bytes(data)
                with self.assertRaises(CHECKER.CheckFailure):
                    CHECKER.verify_docs(self.root)

    def test_zero_swift_files_is_explicit_skip_without_tool(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            CHECKER.verify_format(self.root)
        self.assertIn("SKIP", output.getvalue())
        self.assertIn("不适用", output.getvalue())
        self.assertNotIn("PASS", output.getvalue())

    def prepare_wrapper(self):
        self.write(".swiftformat", "--swiftversion 6.0\n--header ignore\n")
        destination = self.root / "scripts/swiftformat.sh"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PROJECT / "scripts/swiftformat.sh", destination)
        self.write("Package.swift", "let value = 1\n")
        environment = {key: value for key, value in os.environ.items() if not key.startswith("LYGLYPHTEXT_")}
        return environment

    def test_missing_tool_fails_without_installing(self):
        environment = self.prepare_wrapper()
        result = subprocess.run([str(self.root / "scripts/swiftformat.sh"), "--lint", "Package.swift"], cwd=self.root, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unavailable", result.stderr)
        self.assertFalse((self.root / ".build").exists())

    def test_wrong_tool_version_fails_before_lint(self):
        environment = self.prepare_wrapper()
        tool = self.write("wrong-tool", '#!/bin/bash\nif [[ "$1" == --version ]]; then echo 0.61.1; else exit 99; fi\n')
        tool.chmod(0o755)
        environment["LYGLYPHTEXT_SWIFTFORMAT"] = str(tool)
        result = subprocess.run([str(self.root / "scripts/swiftformat.sh"), "--lint", "Package.swift"], cwd=self.root, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("version mismatch", result.stderr)

    def test_bootstrap_refuses_existing_unknown_source_without_overwriting(self):
        environment = self.prepare_wrapper()
        cache = self.root / ".build"
        marker = self.write(".build/tools/swiftformat/0.59.1/source/keep.txt", "preserve\n")
        environment["LYGLYPHTEXT_BUILD_ROOT"] = str(cache)
        result = subprocess.run([str(self.root / "scripts/swiftformat.sh"), "--bootstrap"], cwd=self.root, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Refusing to replace", result.stderr)
        self.assertEqual(marker.read_text(), "preserve\n")

    def test_format_gate_propagates_formatter_failure(self):
        self.prepare_wrapper()
        original = subprocess.run

        def fail_format(command, **kwargs):
            if command[0] == str(self.root / "scripts/swiftformat.sh"):
                return subprocess.CompletedProcess(command, 2)
            return original(command, **kwargs)

        with patch.object(CHECKER.subprocess, "run", side_effect=fail_format):
            with self.assertRaisesRegex(CHECKER.CheckFailure, "exit 2"):
                CHECKER.verify_format(self.root)

    def test_format_gate_only_passes_own_swift_files(self):
        self.prepare_wrapper()
        self.write(".gitignore", ".build/\n")
        self.write(".build/Dependency.swift", "let ignored=1\n")
        self.write("Sources/Generated/Code.swift", "let generated=1\n")
        self.write("Sources/Own.swift", "let value = 2\n")
        commands = []
        original = subprocess.run

        def capture(command, **kwargs):
            if command[0] == str(self.root / "scripts/swiftformat.sh"):
                commands.append(command)
                return subprocess.CompletedProcess(command, 0)
            return original(command, **kwargs)

        with patch.object(CHECKER.subprocess, "run", side_effect=capture):
            CHECKER.verify_format(self.root)
        self.assertEqual(commands, [[str(self.root / "scripts/swiftformat.sh"), "--lint", str(self.root / "Package.swift"), str(self.root / "Sources/Own.swift")]])

    def test_unknown_verification_mode_fails(self):
        result = subprocess.run([str(PROJECT / "scripts/verify.sh"), "build"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs|format", result.stderr)


if __name__ == "__main__":
    unittest.main()
