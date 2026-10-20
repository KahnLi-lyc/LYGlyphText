#!/usr/bin/env python3
"""生成演示工程并验证 iOS 构建／测试；不下载工具，不接管其他模拟器。"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


XCODEGEN_VERSION = "2.46.0"


class VerificationFailure(Exception):
    """可读的工具或验证失败。"""


def parse_arguments(arguments):
    if arguments == ["build"]:
        return "build", None
    if len(arguments) == 2 and arguments[0] == "test":
        if re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", arguments[1]):
            return "test", arguments[1]
        raise VerificationFailure("test requires an explicit Simulator UDID, not a device name")
    raise VerificationFailure("Usage: scripts/verify.sh docs|format|build|test <UDID>")


def validate_test_summary(summary):
    count = summary.get("totalTestCount")
    passed = summary.get("passedTests")
    failed = summary.get("failedTests")
    if type(count) is not int or count <= 0:
        raise VerificationFailure("Zero tests or missing test count: no successful verification")
    if type(passed) is not int or passed <= 0:
        raise VerificationFailure("No tests passed: skipped tests do not establish success")
    if failed != 0 or summary.get("result") != "Passed":
        raise VerificationFailure(f"Test result is not Passed: {summary.get('result')}, failed={failed}")
    return count, passed


def output(command, root):
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    if result.returncode:
        raise VerificationFailure(result.stderr.strip() or result.stdout.strip() or f"Command failed: {command[0]}")
    return result.stdout


def run_logged(command, root, log):
    print(f"Running {log.stem}; log: {log}", flush=True)
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        tail = "\n".join(log.read_text(encoding="utf-8", errors="replace").splitlines()[-60:])
        raise VerificationFailure(f"{log.stem} failed (exit {result.returncode}).\n{tail}\nFull log: {log}")


def validate_simulator(root, udid):
    devices = json.loads(output(["xcrun", "simctl", "list", "devices", "available", "--json"], root))
    for runtime, entries in devices.get("devices", {}).items():
        for device in entries:
            if device.get("udid", "").lower() == udid.lower() and device.get("isAvailable"):
                if ".iOS-" not in runtime:
                    raise VerificationFailure("The selected destination must be an iOS Simulator")
                return {"runtime": runtime, "name": device["name"], "udid": device["udid"]}
    raise VerificationFailure(f"Unavailable Simulator UDID: {udid}")


def verify(root, mode, udid):
    for tool in ["xcodegen", "xcodebuild", "xcrun", "swift"]:
        if shutil.which(tool) is None:
            raise VerificationFailure(f"Required tool unavailable: {tool}; install explicitly before retrying")
    version = output(["xcodegen", "--version"], root).strip()
    if not re.fullmatch(rf"(?:Version:\s*)?{re.escape(XCODEGEN_VERSION)}", version):
        raise VerificationFailure(f"XcodeGen version mismatch: expected {XCODEGEN_VERSION}, got {version}")
    simulator = validate_simulator(root, udid) if mode == "test" else None
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = root / ".build" / "verification" / f"{stamp}-{os.getpid()}-{mode}"
    evidence.mkdir(parents=True)
    metadata = {
        "mode": mode,
        "xcodegen": version,
        "xcode": output(["xcodebuild", "-version"], root).strip(),
        "swift": output(["swift", "--version"], root).strip(),
        "simulator": simulator,
    }
    (evidence / "environment.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    demo = root / "Examples" / "LYGlyphTextDemo"
    run_logged(["xcodegen", "generate", "--spec", str(demo / "project.yml")], root, evidence / "generate.log")
    common = ["SWIFT_VERSION=6", "CODE_SIGNING_ALLOWED=NO"]
    derived = root / ".build" / "DemoDerivedData"
    if mode == "build":
        run_logged([
            "xcodebuild", "-scheme", "LYGlyphText", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(root / ".build" / "PackageDerivedData"), "build", *common,
        ], root, evidence / "package-build.log")
        run_logged([
            "xcodebuild", "-project", str(demo / "LYGlyphTextDemo.xcodeproj"), "-scheme", "LYGlyphTextDemo",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(derived), "build", *common,
        ], root, evidence / "demo-build.log")
        print(f"PASS: Swift 6 mode Package and Demo Simulator builds. Evidence: {evidence}")
        return
    bundle = evidence / "Tests.xcresult"
    run_logged([
        "xcodebuild", "-project", str(demo / "LYGlyphTextDemo.xcodeproj"), "-scheme", "LYGlyphTextDemo",
        "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", str(derived),
        "-resultBundlePath", str(bundle), "-parallel-testing-enabled", "NO", "test", *common,
    ], root, evidence / "tests.log")
    summary_text = output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)], root)
    (evidence / "test-summary.json").write_text(summary_text, encoding="utf-8")
    count, passed = validate_test_summary(json.loads(summary_text))
    print(f"PASS: {passed}/{count} tests passed; hosted Package/unit and UI targets share one scheme. Evidence: {evidence}")


def main():
    try:
        mode, udid = parse_arguments(sys.argv[1:])
        verify(Path(__file__).resolve().parent.parent, mode, udid)
    except (VerificationFailure, OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
