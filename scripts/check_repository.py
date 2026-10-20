#!/usr/bin/env python3
"""只读检查当前仓库；不访问远端，也不自动安装工具。"""

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


class CheckFailure(Exception):
    """可向调用方报告的检查失败。"""


GENERATED = {".git", ".build", ".swiftpm", "DerivedData", "build", "Generated", "__pycache__"}
TEXT_SUFFIXES = {".md", ".sh", ".py", ".swift", ".json", ".yml", ".yaml"}
TEXT_NAMES = {".editorconfig", ".swiftformat", ".gitignore", "LICENSE"}


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if result.returncode:
        raise CheckFailure(result.stderr.decode("utf-8", errors="replace").strip() or "Git check failed")
    return result.stdout


def repository_files(root):
    if Path(git(root, "rev-parse", "--show-toplevel").decode().strip()).resolve() != root.resolve():
        raise CheckFailure("Check root must be the repository root")
    names = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    files = []
    for name in sorted(set(names.decode("utf-8").split("\0")) - {""}):
        path = root / name
        if any(part in GENERATED for part in Path(name).parts):
            continue
        if not path.exists() and not path.is_symlink():
            continue
        if not path.resolve().is_relative_to(root.resolve()):
            raise CheckFailure(f"Repository file resolves outside root: {name}")
        if path.is_file():
            files.append(path)
    return files


def markdown_prose(text, label):
    """屏蔽代码围栏和行内代码；围栏内示例不当作链接。"""
    lines = []
    fence = None
    for line in text.splitlines():
        match = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if match and match[1][0] == fence[0] and len(match[1]) >= len(fence) and not match[2].strip():
                fence = None
            continue
        if match:
            fence = match[1]
            continue
        lines.append(line)
    if fence:
        raise CheckFailure(f"Unclosed Markdown fence: {label}")
    return re.sub(r"(`+).*?\1", "", "\n".join(lines))


def markdown_targets(prose):
    """识别行内链接／图片及引用定义；括号 URL 和尖括号路径均可。"""
    targets = []
    for match in re.finditer(r"!?\[[^\]\n]*\]\(", prose):
        start = match.end()
        if prose[start:start + 1] == "<":
            end = prose.find(">", start + 1)
            if end >= 0:
                targets.append(prose[start + 1:end])
            continue
        depth = 0
        escaped = False
        end = start
        while end < len(prose):
            char = prose[end]
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "(":
                depth += 1
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            end += 1
        targets.append(prose[start:end])
    for match in re.finditer(r"^\s{0,3}\[[^\]\n]+\]:\s*(?:<([^>]+)>|(\S+))", prose, re.MULTILINE):
        targets.append(match[1] if match[1] is not None else match[2])
    return targets


def check_link(root, source, target):
    target = re.sub(r"\\([\\() ])", r"\1", target)
    parsed = urlsplit(target)
    if parsed.scheme and parsed.scheme != "file":
        return
    if parsed.scheme == "file" or parsed.path.startswith("/"):
        raise CheckFailure(f"Absolute local link in {source.relative_to(root)}: {target}")
    if parsed.netloc or not parsed.path:
        return
    destination = (source.parent / unquote(parsed.path)).resolve()
    if not destination.is_relative_to(root.resolve()):
        raise CheckFailure(f"Link escapes repository in {source.relative_to(root)}: {target}")
    if not destination.exists():
        raise CheckFailure(f"Missing local link in {source.relative_to(root)}: {target}")


def verify_docs(root):
    files = repository_files(root)
    markdown_count = 0
    shell_count = 0
    for path in files:
        if path.suffix not in TEXT_SUFFIXES and path.name not in TEXT_NAMES:
            continue
        label = path.relative_to(root)
        data = path.read_bytes()
        text = data.decode("utf-8")
        if b"\r" in data or (data and not data.endswith(b"\n")):
            raise CheckFailure(f"Expected LF and final newline: {label}")
        for line in text.splitlines():
            trailing = line[len(line.rstrip(" \t")):]
            if trailing and not (path.suffix == ".md" and trailing == "  "):
                raise CheckFailure(f"Trailing whitespace: {label}")
        if path.suffix == ".md":
            prose = markdown_prose(text, label)
            for target in markdown_targets(prose):
                check_link(root, path, target)
            markdown_count += 1
        if path.suffix == ".sh":
            result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
            if result.returncode:
                raise CheckFailure(result.stderr.strip())
            shell_count += 1
    for args in [("diff", "--check"), ("diff", "--cached", "--check")]:
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
        if result.returncode:
            raise CheckFailure(result.stdout.strip() or result.stderr.strip())
    print(f"PASS: docs — {markdown_count} Markdown files, {shell_count} Shell syntax checks, text conventions and both diffs")


def verify_format(root):
    files = [str(path) for path in repository_files(root) if path.suffix == ".swift"]
    if not files:
        print("SKIP: format 不适用 — 当前没有 Swift 源文件；未执行 Swift 格式检查。")
        return
    result = subprocess.run([str(root / "scripts/swiftformat.sh"), "--lint", *files], cwd=root)
    if result.returncode:
        raise CheckFailure(f"SwiftFormat check failed (exit {result.returncode})")
    print(f"PASS: format — {len(files)} Swift files")


def main():
    root = Path(__file__).resolve().parent.parent
    if len(sys.argv) != 2 or sys.argv[1] not in {"docs", "format"}:
        print("Usage: scripts/verify.sh docs|format", file=sys.stderr)
        return 2
    try:
        {"docs": verify_docs, "format": verify_format}[sys.argv[1]](root)
    except (CheckFailure, OSError, UnicodeError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
