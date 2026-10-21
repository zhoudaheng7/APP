"""Read-only, redacted consistency check for an enterprise-re-signed IPA.

Reads the actual Mach-O entitlement blob and embedded provisioning profiles.
This portable check does not authenticate signatures or grant entitlements.
Run Apple's codesign verification and an iPhone recording check separately.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import plistlib
import struct
import sys
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath


class CheckError(ValueError):
    """Messages contain field descriptions only, never source credential data."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def dictionary(data: bytes, message: str) -> dict:
    try:
        value = plistlib.loads(data)
    except Exception:
        raise CheckError(message) from None
    require(isinstance(value, dict), message)
    return value


def _tlv(data: bytes, offset: int = 0) -> tuple[int, bytes, int]:
    """Read bounded, definite-length DER; provisioning profiles are CMS DER."""
    require(offset + 2 <= len(data), "描述文件结构不完整")
    tag, first = data[offset], data[offset + 1]
    offset += 2
    if first & 0x80:
        count = first & 0x7F
        require(0 < count <= 4 and offset + count <= len(data), "描述文件长度无效")
        size = int.from_bytes(data[offset:offset + count], "big")
        offset += count
    else:
        size = first
    end = offset + size
    require(end <= len(data), "描述文件长度越界")
    return tag, data[offset:end], end


def _children(data: bytes) -> list[tuple[int, bytes]]:
    values, offset = [], 0
    while offset < len(data):
        tag, value, offset = _tlv(data, offset)
        values.append((tag, value))
        require(len(values) <= 128, "描述文件结构过大")
    return values


def read_profile(data: bytes) -> dict:
    tag, body, end = _tlv(data)
    require(tag == 0x30 and end == len(data), "描述文件不是有效CMS")
    content = _children(body)
    signed_data_oid = bytes.fromhex("2a864886f70d010702")
    data_oid = bytes.fromhex("2a864886f70d010701")
    require(len(content) == 2 and content[0] == (0x06, signed_data_oid)
            and content[1][0] == 0xA0, "描述文件缺少CMS签名容器")
    wrapped = _children(content[1][1])
    require(len(wrapped) == 1 and wrapped[0][0] == 0x30, "描述文件签名容器无效")
    signed = _children(wrapped[0][1])
    require(len(signed) >= 4 and signed[2][0] == 0x30, "描述文件内容缺失")
    encapsulated = _children(signed[2][1])
    require(len(encapsulated) == 2 and encapsulated[0] == (0x06, data_oid)
            and encapsulated[1][0] == 0xA0, "描述文件内容类型无效")
    payload = _children(encapsulated[1][1])
    require(len(payload) == 1 and payload[0][0] == 0x04, "描述文件内容编码无效")
    return dictionary(payload[0][1], "描述文件属性无效")


def read_entitlements(data: bytes) -> dict:
    require(len(data) >= 32 and struct.unpack_from("<I", data)[0] == 0xFEEDFACF,
            "需要arm64设备Mach-O可执行文件")
    _, cpu, _, kind, count, command_size, _, _ = struct.unpack_from("<8I", data)
    require(cpu == 0x0100000C and kind == 2 and count <= 4096 and 32 + command_size <= len(data),
            "设备可执行文件结构无效")
    offset, signatures, platforms = 32, [], []
    for _ in range(count):
        require(offset + 8 <= 32 + command_size, "Mach-O命令缺失")
        command, size = struct.unpack_from("<2I", data, offset)
        require(size >= 8 and offset + size <= 32 + command_size, "Mach-O命令越界")
        if command == 0x1D:
            require(size >= 16, "代码签名命令无效")
            signatures.append(struct.unpack_from("<2I", data, offset + 8))
        if command == 0x32:
            require(size >= 24, "设备平台命令无效")
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        offset += size
    require(offset == 32 + command_size and len(signatures) == 1, "可执行文件缺少唯一代码签名")
    require(platforms == [2], "需要iPhoneOS设备可执行文件")
    start, size = signatures[0]
    require(size >= 12 and start >= offset and start + size <= len(data), "代码签名越界")
    signature = data[start:start + size]
    magic, length, count = struct.unpack_from(">3I", signature)
    require(magic == 0xFADE0CC0 and 12 <= length <= len(signature)
            and count <= 128 and 12 + count * 8 <= length, "代码签名结构无效")
    values = []
    for index in range(count):
        kind, position = struct.unpack_from(">2I", signature, 12 + index * 8)
        require(position >= 12 + count * 8 and position + 8 <= length, "签名条目越界")
        blob_magic, blob_length = struct.unpack_from(">2I", signature, position)
        require(blob_length >= 8 and position + blob_length <= length, "签名条目长度无效")
        if kind == 5:
            require(blob_magic == 0xFADE7171, "签名权限编码不支持")
            values.append(dictionary(signature[position + 8:position + blob_length].rstrip(b"\0"),
                                     "签名权限属性无效"))
    require(len(values) == 1, "无法读取签名权限；请用macOS codesign检查DER权限")
    return values[0]


def _profile_allows_id(actual: str, allowed: object) -> bool:
    if not isinstance(allowed, str):
        return False
    if actual == allowed:
        return True
    return allowed.endswith(".*") and "*" not in allowed[:-1] and actual.startswith(allowed[:-1])


def verify_identity(info: dict, entitlements: dict, profile: dict, label: str,
                    now: dt.datetime) -> str:
    bundle = info.get("CFBundleIdentifier")
    team = entitlements.get("com.apple.developer.team-identifier")
    application = entitlements.get("application-identifier")
    require(isinstance(bundle, str) and bundle and isinstance(team, str) and team,
            f"{label}缺少应用或团队签名身份")
    require(isinstance(application, str) and application.endswith("." + bundle),
            f"{label}签名应用身份与Info不一致")
    prefix = application[:-(len(bundle) + 1)]
    teams, prefixes = profile.get("TeamIdentifier"), profile.get("ApplicationIdentifierPrefix")
    require(isinstance(teams, list) and isinstance(prefixes, list)
            and team in teams and prefix in prefixes,
            f"{label}描述文件与签名团队不一致")
    permissions = profile.get("Entitlements")
    require(isinstance(permissions, dict), f"{label}描述文件缺少授权")
    require(_profile_allows_id(application, permissions.get("application-identifier")),
            f"{label}描述文件未授权签名应用身份")
    require(permissions.get("com.apple.developer.team-identifier") == team,
            f"{label}描述文件团队授权不一致")
    expiration = profile.get("ExpirationDate")
    require(isinstance(expiration, dt.datetime), f"{label}描述文件缺少有效期")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=dt.timezone.utc)
    require(expiration > now, f"{label}描述文件已过期")
    return team


def verify_ipa(path: Path, now: dt.datetime | None = None) -> dict:
    now = now or dt.datetime.now(dt.timezone.utc)
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(len(entries) <= 20000, "IPA文件条目过多")
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), "IPA含重复文件路径")
        for name in names:
            part = PurePosixPath(name)
            require(not part.is_absolute() and ".." not in part.parts and "\\" not in name,
                    "IPA含无效文件路径")

        def read(name: str, maximum: int = 128 * 1024 * 1024) -> bytes:
            require(name in names, "IPA缺少所需文件或描述文件")
            require(archive.getinfo(name).file_size <= maximum, "IPA文件过大，拒绝解析")
            return archive.read(name)

        main_infos = [name for name in names if len(PurePosixPath(name).parts) == 3
                      and name.startswith("Payload/") and name.endswith(".app/Info.plist")]
        require(len(main_infos) == 1, "IPA必须包含一个主App")
        main_folder = main_infos[0].removesuffix("Info.plist")
        extension_infos = [name for name in names if name.startswith(main_folder + "PlugIns/")
                           and len(PurePosixPath(name).relative_to(PurePosixPath(main_folder)).parts) == 3
                           and name.endswith(".appex/Info.plist")]
        require(len(extension_infos) == 2, "IPA必须保留广播和实时活动两个扩展")

        def bundle(info_path: str, label: str) -> tuple[dict, dict, dict, str]:
            folder = info_path.removesuffix("Info.plist")
            info = dictionary(read(info_path, 1024 * 1024), f"{label}Info无效")
            executable = info.get("CFBundleExecutable")
            require(isinstance(executable, str) and executable and
                    PurePosixPath(executable).name == executable and "\\" not in executable,
                    f"{label}可执行文件名无效")
            entitlements = read_entitlements(read(folder + executable))
            profile = read_profile(read(folder + "embedded.mobileprovision", 4 * 1024 * 1024))
            team = verify_identity(info, entitlements, profile, label, now)
            return info, entitlements, profile, team

        main = bundle(main_infos[0], "主App")
        extensions = [bundle(name, "扩展") for name in extension_infos]
        broadcast = [value for value in extensions if value[0].get("NSExtension", {}).get(
            "NSExtensionPointIdentifier") == "com.apple.broadcast-services-upload"]
        activity = [value for value in extensions if value[0].get("NSExtension", {}).get(
            "NSExtensionPointIdentifier") == "com.apple.widgetkit-extension"]
        require(len(broadcast) == len(activity) == 1, "广播或实时活动扩展注册无效")
        broadcast = broadcast[0]
        require(broadcast[0]["NSExtension"].get("RPBroadcastProcessMode") ==
                "RPBroadcastProcessModeSampleBuffer", "广播采样模式无效")
        version = (main[0].get("CFBundleShortVersionString"), main[0].get("CFBundleVersion"))
        require(all(isinstance(value, str) and value for value in version), "主App版本无效")
        for extension in extensions:
            require(extension[3] == main[3], "主App与扩展必须由同一团队签名")
            require(extension[0]["CFBundleIdentifier"].startswith(main[0]["CFBundleIdentifier"] + "."),
                    "扩展Bundle ID不属于主App")
            require((extension[0].get("CFBundleShortVersionString"), extension[0].get("CFBundleVersion"))
                    == version, "主App与扩展版本不一致")
        modes = main[0].get("UIBackgroundModes", [])
        require(isinstance(modes, list) and {"audio", "screen-capture"}.issubset(modes),
                "主App缺少录制所需后台模式")
        require(main[0].get("NSSupportsLiveActivities") is True, "主App缺少实时活动声明")
        require(bool(main[0].get("NSMicrophoneUsageDescription")) and
                bool(main[0].get("NSScreenCaptureUsageDescription")), "主App缺少录制用途声明")
        group = main[0].get("AudioAppGroupIdentifier")
        require(isinstance(group, str) and group.startswith("group.") and len(group) > 6
                and "$(" not in group and "*" not in group and not any(c.isspace() for c in group),
                "主App共享组配置无效")
        require(broadcast[0].get("AudioAppGroupIdentifier") == group, "主App与广播Info共享组不一致")
        subdirectory = main[0].get("AudioAppGroupSubdirectory", "")
        require(isinstance(subdirectory, str) and subdirectory not in {".", ".."}
                and "/" not in subdirectory and "\\" not in subdirectory
                and not any(unicodedata.category(c) in {"Cc", "Cf", "Zl", "Zp"} for c in subdirectory),
                "共享存储子目录配置无效")
        require(broadcast[0].get("AudioAppGroupSubdirectory", "") == subdirectory,
                "主App与广播共享存储子目录不一致")
        for label, value in [("主App", main), ("广播", broadcast)]:
            signed_groups = value[1].get("com.apple.security.application-groups")
            profile_groups = value[2]["Entitlements"].get("com.apple.security.application-groups")
            require(isinstance(signed_groups, list) and group in signed_groups,
                    f"{label}实际签名未授权配置共享组")
            require(isinstance(profile_groups, list) and group in profile_groups,
                    f"{label}描述文件未授权配置共享组")
    return {
        "passed": True,
        "checks": ["实际签名权限与配置共享组一致", "描述文件授权与有效期一致",
                   "主App与两扩展身份及版本一致", "广播注册与后台模式保留", "共享子目录一致且安全"],
        "signatureAuthenticityVerified": False,
        "deviceSharedAccessVerified": False,
        "limitations": ["仅做签后包内容一致性检查；需另用Apple工具验证签名真实性",
                        "需在iPhone确认共享存储与实际长录"],
    }


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="只读检查企业重签IPA，不输出证书或设备信息")
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", type=Path, help="可选：保存脱敏JSON检查结果")
    args = parser.parse_args()
    try:
        result = verify_ipa(args.ipa)
    except CheckError as error:
        result = {"passed": False, "error": str(error)}
    except Exception:
        result = {"passed": False, "error": "IPA无法读取或包结构无效"}
    serialized = json.dumps(result, ensure_ascii=False, indent=2)
    print(serialized)
    if args.output:
        args.output.write_text(serialized + "\n", encoding="utf-8")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
