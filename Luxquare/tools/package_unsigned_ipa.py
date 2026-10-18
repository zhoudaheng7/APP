"""Package a compiled iPhoneOS application, with independent binary evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path


def inspect_macho(data: bytes) -> dict:
    if len(data) < 32:
        raise ValueError("Truncated Mach-O header")
    magic, cpu, _, kind, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data)
    if (magic, cpu, kind) != (0xFEEDFACF, 0x0100000C, 2):
        raise ValueError("Expected thin arm64 Mach-O executable")
    if sizeofcmds > len(data) - 32 or ncmds > sizeofcmds // 8:
        raise ValueError("Invalid Mach-O command table")
    offset = 32
    platforms = []
    signed = False
    for _ in range(ncmds):
        if offset + 8 > 32 + sizeofcmds:
            raise ValueError("Truncated load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > 32 + sizeofcmds:
            raise ValueError("Invalid load command size")
        if command == 0x32:
            if size < 24:
                raise ValueError("Truncated LC_BUILD_VERSION")
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        if command == 0x1D:
            if size < 16:
                raise ValueError("Truncated LC_CODE_SIGNATURE")
            signed |= struct.unpack_from("<I", data, offset + 12)[0] > 0
        offset += size
    if offset != 32 + sizeofcmds or platforms != [2]:
        raise ValueError(f"Expected exactly one iPhoneOS platform=2, got {platforms}")
    return {"architecture": "arm64", "platform": "iPhoneOS", "code_signature_present": signed}


def package(app: Path, destination: Path, bundle_id: str | None = None) -> dict:
    if app.suffix != ".app" or not app.is_dir() or app.is_symlink():
        raise ValueError("Expected compiled .app directory")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info["CFBundleExecutable"]
    if Path(executable).name != executable:
        raise ValueError("Unsafe executable name")
    binary = inspect_macho((app / executable).read_bytes())
    if binary["code_signature_present"]:
        raise ValueError("This packager only accepts explicitly unsigned output")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Info.plist is not an iPhoneOS device build")
    if bundle_id is not None and info["CFBundleIdentifier"] != bundle_id:
        raise ValueError("Unexpected application identifier")
    if not (app / "Assets.car").is_file() or not info.get("CFBundleIcons"):
        raise ValueError("Compiled primary icon assets are missing")
    paths = sorted(p for p in app.rglob("*") if p.is_file())
    if any(p.is_symlink() for p in paths):
        raise ValueError("Application contains a symbolic link")
    if any(p.name in {"embedded.mobileprovision", ".env"} or p.suffix in {".p12", ".pem", ".key"} for p in paths):
        raise ValueError("Unexpected signing or environment material")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in paths:
            archive.write(path, (Path("Payload") / app.name / path.relative_to(app)).as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA ZIP integrity failed")
        inspect_macho(archive.read(f"Payload/{app.name}/{executable}"))
    evidence = {
        "schema": "lux-unsigned-ipa/v1",
        "bundle_identifier": info["CFBundleIdentifier"],
        "display_name": info.get("CFBundleDisplayName", info.get("CFBundleName")),
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "minimum_os": info["MinimumOSVersion"],
        "sdk": info.get("DTSDKName"),
        "file_count": len(paths),
        "bytes": destination.stat().st_size,
        "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        "provisioning_profile_present": False,
        "signed": False,
        "installed_on_device": False,
        **binary,
    }
    destination.with_suffix(".verification.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--bundle-id")
    args = parser.parse_args()
    print(json.dumps(package(args.app, args.destination, args.bundle_id), indent=2))
