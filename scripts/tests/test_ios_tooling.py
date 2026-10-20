"""iOS 检查入口的参数与结果边界，不调用真实 Xcode 或 Simulator。"""

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("verify_ios", PROJECT / "scripts/verify_ios.py")
IOS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IOS)
UDID = "01234567-89AB-CDEF-0123-456789ABCDEF"


class IOSToolingTests(unittest.TestCase):
    def test_build_and_explicit_test_destination(self):
        self.assertEqual(IOS.parse_arguments(["build"]), ("build", None))
        self.assertEqual(IOS.parse_arguments(["test", UDID]), ("test", UDID))
        for arguments in [[], ["test"], ["test", "iPhone"], ["build", UDID], ["docs"]]:
            with self.subTest(arguments=arguments), self.assertRaises(IOS.VerificationFailure):
                IOS.parse_arguments(arguments)

    def test_zero_missing_skipped_or_failed_tests_fail(self):
        for summary in [
            {},
            {"totalTestCount": 0, "passedTests": 0, "failedTests": 0, "result": "Passed"},
            {"totalTestCount": 4, "passedTests": 0, "failedTests": 0, "result": "Skipped"},
            {"totalTestCount": 4, "passedTests": 3, "failedTests": 1, "result": "Failed"},
            {"totalTestCount": 4, "passedTests": 4, "result": "Passed"},
        ]:
            with self.subTest(summary=summary), self.assertRaises(IOS.VerificationFailure):
                IOS.validate_test_summary(summary)
        self.assertEqual(IOS.validate_test_summary({
            "totalTestCount": 4, "passedTests": 4, "failedTests": 0, "result": "Passed",
        }), (4, 4))

    def test_missing_or_wrong_tool_does_not_start_generation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(IOS.shutil, "which", return_value=None), patch.object(IOS, "run_logged") as run:
                with self.assertRaisesRegex(IOS.VerificationFailure, "unavailable"):
                    IOS.verify(root, "build", None)
                run.assert_not_called()
            for version in ["Version: 2.47.0", "Version: 2.46.0-dev"]:
                with patch.object(IOS.shutil, "which", return_value="/tool"), patch.object(IOS, "output", return_value=version), patch.object(IOS, "run_logged") as run:
                    with self.assertRaisesRegex(IOS.VerificationFailure, "version mismatch"):
                        IOS.verify(root, "build", None)
                    run.assert_not_called()
            self.assertFalse((root / ".build").exists())

    def test_simulator_destination_must_exist_and_be_ios(self):
        for devices in [{}, {"runtime.tvOS-27-0": [{"udid": UDID, "isAvailable": True, "name": "TV"}]}]:
            with patch.object(IOS, "output", return_value=json.dumps({"devices": devices})):
                with self.assertRaises(IOS.VerificationFailure):
                    IOS.validate_simulator(PROJECT, UDID)
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"udid": UDID, "isAvailable": True, "name": "Test"}]}
        with patch.object(IOS, "output", return_value=json.dumps({"devices": devices})):
            self.assertEqual(IOS.validate_simulator(PROJECT, UDID)["name"], "Test")

    def test_failed_process_preserves_log_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log = root / "build.log"
            def fail(command, **kwargs):
                kwargs["stdout"].write("specific build diagnostic\n")
                return subprocess.CompletedProcess(command, 65)
            with patch.object(IOS.subprocess, "run", side_effect=fail):
                with self.assertRaisesRegex(IOS.VerificationFailure, "specific build diagnostic"):
                    IOS.run_logged(["xcodebuild"], root, log)
            self.assertIn("specific build diagnostic", log.read_text())

    def test_shell_rejects_missing_extra_and_named_test_destinations(self):
        for arguments in [[], ["build", "extra"], ["test"], ["test", "iPhone"]]:
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(PROJECT / "scripts/verify.sh"), *arguments], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
