import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("ipa_validator",
    Path(__file__).resolve().parents[1] / "ios" / "scripts" / "validate_ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ValidatorTests(unittest.TestCase):
    def make_fixture(self, path, plist_platform="iPhoneOS", binary_platform=2):
        # Synthetic Mach-O header and a single LC_BUILD_VERSION; never an installable app.
        header = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
        command = struct.pack("<IIIIII", 0x32, 24, binary_platform, 0x110000, 0x110000, 0)
        info = {"CFBundleExecutable": "Test", "CFBundleIdentifier": "test.synthetic",
            "CFBundleSupportedPlatforms": [plist_platform], "DTPlatformName": plist_platform.lower(),
            "UIDeviceFamily": [1], "NSLocalNetworkUsageDescription": "synthetic fixture"}
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Test.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Test.app/Test", header + command)

    def test_device_format_validation_on_synthetic_fixture(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.ipa"
            self.make_fixture(path)
            self.assertEqual(module.validate(path)["platform"], "iPhoneOS")

    def test_simulator_plist_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.ipa"
            self.make_fixture(path, "iPhoneSimulator", 7)
            with self.assertRaises(ValueError):
                module.validate(path)

    def test_arm64_simulator_binary_with_device_plist_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.ipa"
            self.make_fixture(path, "iPhoneOS", 7)
            with self.assertRaises(ValueError):
                module.validate(path)


if __name__ == "__main__":
    unittest.main()
