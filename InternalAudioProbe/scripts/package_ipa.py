"""Package an actual unsigned iPhoneOS device build; reject simulator or source-only output."""
from __future__ import annotations
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def verify_binary(data: bytes) -> dict:
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xFEEDFACF:
        raise ValueError('Expected a real thin 64-bit Mach-O executable')
    _, cpu, _, kind, commands, command_bytes, _, _ = struct.unpack_from('<8I', data)
    if cpu != 0x0100000C or kind != 2:
        raise ValueError('Expected an arm64 executable (MH_EXECUTE)')
    offset, platforms = 32, []
    for _ in range(commands):
        command, size = struct.unpack_from('<2I', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError('Truncated Mach-O load command')
        if command == 0x32:
            platforms.append(struct.unpack_from('<I', data, offset + 8)[0])
        offset += size
    if offset > 32 + command_bytes or 2 not in platforms:
        raise ValueError(f'Expected LC_BUILD_VERSION iPhoneOS platform=2, got {platforms}')
    return {'architecture': 'arm64', 'platform': 'iPhoneOS', 'macho': True}


def package(app: Path, destination: Path) -> dict:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    binary = app / info['CFBundleExecutable']
    evidence = verify_binary(binary.read_bytes())
    extension = app / 'PlugIns/InternalAudioBroadcast.appex'
    ext_info = plistlib.loads((extension / 'Info.plist').read_bytes())
    ext_binary = verify_binary((extension / ext_info['CFBundleExecutable']).read_bytes())
    assert ext_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.broadcast-services-upload'
    assert ext_info['NSExtension']['RPBroadcastProcessMode'] == 'RPBroadcastProcessModeSampleBuffer'
    assert ext_info['CFBundleIdentifier'].startswith(info['CFBundleIdentifier'] + '.')
    assert ext_info['AudioAppGroupIdentifier'] == info['AudioAppGroupIdentifier']
    assert 'NSMicrophoneUsageDescription' not in ext_info
    assert (app / 'Assets.car').is_file(), 'Compiled app icon assets missing'
    assert info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon'), 'Primary icon declaration missing'
    assert info.get('CADisableMinimumFrameDurationOnPhone') is True, 'High refresh-rate opt-in missing'
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Info.plist is not a device build')
    assert info.get('NSMicrophoneUsageDescription'), 'Mixed-mode microphone purpose missing'
    assert info.get('NSSupportsLiveActivities') is True
    activity = app / 'PlugIns/RecordingActivity.appex'
    activity_info = plistlib.loads((activity / 'Info.plist').read_bytes())
    activity_binary = verify_binary((activity / activity_info['CFBundleExecutable']).read_bytes())
    assert activity_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    assert activity_info['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.activity'
    assert activity_info['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
    assert 'audio' in info['UIBackgroundModes']
    if 'screen-capture' not in info.get('UIBackgroundModes', []):
        raise ValueError('Missing background screen-capture mode')
    if (app / 'embedded.mobileprovision').exists():
        raise ValueError('Unexpected provisioning profile: this package is explicitly unsigned')
    destination.parent.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in app.rglob('*') if p.is_file())
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, (Path('Payload') / app.name / path.relative_to(app)).as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA ZIP integrity check failed')
        required = f'Payload/{app.name}/{info["CFBundleExecutable"]}'
        verify_binary(archive.read(required))
    evidence.update(bundleIdentifier=info['CFBundleIdentifier'], version=info['CFBundleShortVersionString'],
                    fileCount=len(files), size=destination.stat().st_size,
                    sha256=hashlib.sha256(destination.read_bytes()).hexdigest(), signed=False,
                    microphonePermission=True, microphoneDefault=False, backgroundModes=info['UIBackgroundModes'],
                    liveActivity={'bundleIdentifier': activity_info['CFBundleIdentifier'], **activity_binary},
                    extension={'bundleIdentifier': ext_info['CFBundleIdentifier'], **ext_binary},
                    appGroup=info['AudioAppGroupIdentifier'], iconAssets=True, highRefreshEnabled=True)
    destination.with_suffix('.verification.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    return evidence


if __name__ == '__main__':
    print(json.dumps(package(Path(sys.argv[1]), Path(sys.argv[2])), indent=2))
