"""Validate iPhoneOS archive structure; this does not validate a signing identity."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import struct
import zipfile


def validate(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError("IPA has a corrupt ZIP entry")
        names = archive.namelist()
        info_paths = [name for name in names if name.startswith("Payload/")
                      and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(info_paths) != 1:
            raise ValueError("Expected exactly one app at Payload/*.app")
        info = plistlib.loads(archive.read(info_paths[0]))
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Not an iPhoneOS device build")
        if info.get("DTPlatformName") != "iphoneos":
            raise ValueError("Simulator builds cannot be installed on iPhone")
        if 1 not in info.get("UIDeviceFamily", []):
            raise ValueError("App does not support iPhone")
        executable = info_paths[0].removesuffix("Info.plist") + info["CFBundleExecutable"]
        binary = archive.read(executable)
        if len(binary) < 32 or binary[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected a 64-bit little-endian Mach-O executable")
        cpu = struct.unpack_from("<I", binary, 4)[0]
        if cpu != 0x0100000C:
            raise ValueError("Expected arm64 architecture")
        ncmds = struct.unpack_from("<I", binary, 16)[0]
        offset, platform = 32, None
        for _ in range(ncmds):
            command, size = struct.unpack_from("<II", binary, offset)
            if size < 8 or offset + size > len(binary):
                raise ValueError("Invalid Mach-O load command")
            if command == 0x32:
                platform = struct.unpack_from("<I", binary, offset + 8)[0]
            offset += size
        if platform != 2:
            raise ValueError("Mach-O platform is not iOS device (arm64 simulator is rejected)")
        if not info.get("NSLocalNetworkUsageDescription"):
            raise ValueError("Missing local network usage description")
        return {
            "file": path.name, "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bundle_id": info["CFBundleIdentifier"], "platform": "iPhoneOS",
            "architecture": "arm64", "minimum_ios": info.get("MinimumOSVersion"),
            "signature": "unsigned - must be re-signed before installation",
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    parser.add_argument("--report")
    args = parser.parse_args()
    report = validate(args.ipa)
    output = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        Path(args.report).write_text(output, encoding="utf-8")
    print(output)
