"""Synthetic format/authorization checks; no real certificates, profiles, or audio."""
from __future__ import annotations

import datetime as dt
import json
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_signed_ipa import CheckError, read_entitlements, read_profile, verify_ipa


NOW = dt.datetime(2026, 10, 20, tzinfo=dt.timezone.utc)
GROUP = "group.example.resigned.audio"
TEAM = "SYNTHETIC1"
MAIN = "Payload/Recorder.app/"
BROADCAST = MAIN + "PlugIns/Audio.appex/"
ACTIVITY = MAIN + "PlugIns/Activity.appex/"


def der(tag: int, value: bytes) -> bytes:
    if len(value) < 128:
        length = bytes([len(value)])
    else:
        size = len(value).to_bytes((len(value).bit_length() + 7) // 8, "big")
        length = bytes([0x80 | len(size)]) + size
    return bytes([tag]) + length + value


def cms(profile: dict) -> bytes:
    payload = der(0x30, der(0x06, bytes.fromhex("2a864886f70d010701")) +
                  der(0xA0, der(0x04, plistlib.dumps(profile))))
    signed = der(0x30, der(0x02, b"\1") + der(0x31, b"") + payload + der(0x31, b""))
    return der(0x30, der(0x06, bytes.fromhex("2a864886f70d010702")) + der(0xA0, signed))


def macho(entitlements: dict, platform: int = 2) -> bytes:
    xml = plistlib.dumps(entitlements)
    blob = struct.pack(">2I", 0xFADE7171, len(xml) + 8) + xml
    signature = struct.pack(">5I", 0xFADE0CC0, 20 + len(blob), 1, 5, 20) + blob
    commands = struct.pack("<6I", 0x32, 24, platform, 0x1B0000, 0x1B0000, 0)
    commands += struct.pack("<4I", 0x1D, 16, 72, len(signature))
    return struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 2, len(commands), 0, 0) + commands + signature


def fixture() -> dict[str, bytes]:
    entries = {}
    for folder, bundle, extension in [
        (MAIN, "example.resigned.audio", None),
        (BROADCAST, "example.resigned.audio.broadcast", "com.apple.broadcast-services-upload"),
        (ACTIVITY, "example.resigned.audio.activity", "com.apple.widgetkit-extension"),
    ]:
        info = {"CFBundleExecutable": "Recorder", "CFBundleIdentifier": bundle,
                "CFBundleShortVersionString": "0.4.2", "CFBundleVersion": "7"}
        if extension:
            info["NSExtension"] = {"NSExtensionPointIdentifier": extension}
            if folder == BROADCAST:
                info["NSExtension"]["RPBroadcastProcessMode"] = "RPBroadcastProcessModeSampleBuffer"
        else:
            info.update(UIBackgroundModes=["screen-capture", "audio"], NSSupportsLiveActivities=True,
                        NSScreenCaptureUsageDescription="Synthetic", NSMicrophoneUsageDescription="Synthetic")
        entitlements = {"application-identifier": TEAM + "." + bundle,
                        "com.apple.developer.team-identifier": TEAM}
        if folder != ACTIVITY:
            info["AudioAppGroupIdentifier"] = GROUP
            entitlements["com.apple.security.application-groups"] = [GROUP]
        profile = {"TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM],
                   "ExpirationDate": dt.datetime(2027, 10, 20), "Entitlements": dict(entitlements),
                   "DeveloperCertificates": [b"SYNTHETIC-PRIVATE-CERTIFICATE-NOT-REAL"],
                   "ProvisionedDevices": ["SYNTHETIC-PRIVATE-DEVICE-NOT-REAL"]}
        entries[folder + "Info.plist"] = plistlib.dumps(info)
        entries[folder + "Recorder"] = macho(entitlements)
        entries[folder + "embedded.mobileprovision"] = cms(profile)
    return entries


def change_plist(entries: dict, name: str, change) -> None:
    value = plistlib.loads(entries[name])
    change(value)
    entries[name] = plistlib.dumps(value, fmt=plistlib.FMT_BINARY)


class SignedIPACheckTests(unittest.TestCase):
    def verify(self, entries: dict[str, bytes]) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                for name, value in entries.items():
                    archive.writestr(name, value)
            return verify_ipa(path, NOW)

    def test_reconfigured_explicit_group_and_redacted_receipt(self):
        result = self.verify(fixture())
        self.assertTrue(result["passed"])
        self.assertFalse(result["signatureAuthenticityVerified"])
        self.assertFalse(result["deviceSharedAccessVerified"])
        serialized = json.dumps(result)
        for sensitive in [TEAM, GROUP, "SYNTHETIC-PRIVATE", "DeveloperCertificates", "ProvisionedDevices"]:
            self.assertNotIn(sensitive, serialized)

    def test_missing_actual_broadcast_group_is_rejected(self):
        entries = fixture()
        entitlements = read_entitlements(entries[BROADCAST + "Recorder"])
        entitlements.pop("com.apple.security.application-groups")
        entries[BROADCAST + "Recorder"] = macho(entitlements)
        with self.assertRaisesRegex(CheckError, "实际签名未授权"):
            self.verify(entries)

    def test_explicit_product_namespace_is_accepted(self):
        entries = fixture()
        for folder in [MAIN, BROADCAST]:
            change_plist(entries, folder + "Info.plist",
                         lambda value: value.update(AudioAppGroupSubdirectory="Shengyu"))
        self.assertTrue(self.verify(entries)["passed"])

    def test_absent_and_empty_namespace_preserve_legacy_root(self):
        entries = fixture()
        change_plist(entries, BROADCAST + "Info.plist",
                     lambda value: value.update(AudioAppGroupSubdirectory=""))
        self.assertTrue(self.verify(entries)["passed"])

    def test_namespace_mismatch_is_rejected(self):
        entries = fixture()
        change_plist(entries, MAIN + "Info.plist",
                     lambda value: value.update(AudioAppGroupSubdirectory="Shengyu"))
        with self.assertRaisesRegex(CheckError, "子目录不一致"):
            self.verify(entries)

    def test_unsafe_or_nonstring_namespace_is_rejected(self):
        for invalid in [".", "..", "../Shengyu", "Shengyu/Other", "Shengyu\\Other",
                        "Shengyu\nOther", "Shengyu\0Other", "Shengyu\x7fOther",
                        "Shengyu\u202eOther", "Shengyu\u2028Other", 7, ["Shengyu"]]:
            with self.subTest(invalid=repr(invalid)):
                entries = fixture()
                for folder in [MAIN, BROADCAST]:
                    change_plist(entries, folder + "Info.plist",
                                 lambda value: value.update(AudioAppGroupSubdirectory=invalid))
                with self.assertRaisesRegex(CheckError, "子目录配置无效"):
                    self.verify(entries)

    def test_other_profile_group_does_not_replace_configured_group(self):
        entries = fixture()
        profile = read_profile(entries[BROADCAST + "embedded.mobileprovision"])
        profile["Entitlements"]["com.apple.security.application-groups"] = ["group.example.other"]
        entries[BROADCAST + "embedded.mobileprovision"] = cms(profile)
        with self.assertRaisesRegex(CheckError, "描述文件未授权配置共享组"):
            self.verify(entries)

    def test_group_string_is_not_accepted_as_array(self):
        entries = fixture()
        entitlements = read_entitlements(entries[MAIN + "Recorder"])
        entitlements["com.apple.security.application-groups"] = GROUP
        entries[MAIN + "Recorder"] = macho(entitlements)
        with self.assertRaisesRegex(CheckError, "实际签名未授权"):
            self.verify(entries)

    def test_mismatched_info_group_is_rejected(self):
        entries = fixture()
        change_plist(entries, BROADCAST + "Info.plist", lambda value: value.update(AudioAppGroupIdentifier="group.other"))
        with self.assertRaisesRegex(CheckError, "Info共享组不一致"):
            self.verify(entries)

    def test_expired_profile_is_rejected(self):
        entries = fixture()
        profile = read_profile(entries[MAIN + "embedded.mobileprovision"])
        profile["ExpirationDate"] = dt.datetime(2026, 10, 19)
        entries[MAIN + "embedded.mobileprovision"] = cms(profile)
        with self.assertRaisesRegex(CheckError, "已过期"):
            self.verify(entries)

    def test_wrong_profile_application_is_rejected(self):
        entries = fixture()
        profile = read_profile(entries[MAIN + "embedded.mobileprovision"])
        profile["Entitlements"]["application-identifier"] = TEAM + ".other.application"
        entries[MAIN + "embedded.mobileprovision"] = cms(profile)
        with self.assertRaisesRegex(CheckError, "未授权签名应用身份"):
            self.verify(entries)

    def test_changed_extension_version_is_rejected(self):
        entries = fixture()
        change_plist(entries, ACTIVITY + "Info.plist", lambda value: value.update(CFBundleVersion="8"))
        with self.assertRaisesRegex(CheckError, "版本不一致"):
            self.verify(entries)

    def test_missing_background_capture_mode_is_rejected(self):
        entries = fixture()
        change_plist(entries, MAIN + "Info.plist", lambda value: value.update(UIBackgroundModes=["audio"]))
        with self.assertRaisesRegex(CheckError, "后台模式"):
            self.verify(entries)

    def test_missing_activity_extension_is_rejected(self):
        entries = {name: data for name, data in fixture().items() if not name.startswith(ACTIVITY)}
        with self.assertRaisesRegex(CheckError, "两个扩展"):
            self.verify(entries)

    def test_simulator_binary_is_rejected(self):
        entries = fixture()
        entitlements = read_entitlements(entries[MAIN + "Recorder"])
        entries[MAIN + "Recorder"] = macho(entitlements, platform=7)
        with self.assertRaisesRegex(CheckError, "iPhoneOS"):
            self.verify(entries)

    def test_unsigned_binary_is_rejected(self):
        entries = fixture()
        entries[MAIN + "Recorder"] = b"not a signed Mach-O"
        with self.assertRaises(CheckError):
            self.verify(entries)

    def test_unsafe_path_is_rejected_without_extraction(self):
        entries = fixture()
        entries["Payload/../outside.txt"] = b"not written"
        with self.assertRaisesRegex(CheckError, "无效文件路径"):
            self.verify(entries)

    def test_truncated_code_signature_and_profile_are_rejected(self):
        entries = fixture()
        with self.assertRaises(CheckError):
            read_entitlements(entries[MAIN + "Recorder"][:-10])
        with self.assertRaises(CheckError):
            read_profile(entries[MAIN + "embedded.mobileprovision"][:-10])


if __name__ == "__main__":
    unittest.main()
