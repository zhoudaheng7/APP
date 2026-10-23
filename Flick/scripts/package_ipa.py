"""Package only a successful iPhoneOS arm64 build, preserving executable modes."""
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

app, destination = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Info.plist').read_bytes())
executable = app / info['CFBundleExecutable']
binary = executable.read_bytes()
magic, cpu, _, kind, commands = struct.unpack_from('<IIIII', binary)
assert magic == 0xFEEDFACF and cpu == 0x0100000C and kind == 2, 'Expected a real arm64 Mach-O executable'
offset = 32
platform = None
for _ in range(commands):
    command, size = struct.unpack_from('<II', binary, offset)
    if command == 0x32:
        platform, minimum, sdk = struct.unpack_from('<III', binary, offset + 8)
    offset += size
assert platform == 2, 'A simulator app cannot be packaged as a phone IPA'
assert info.get('DTPlatformName') == 'iphoneos'
assert info.get('UIDeviceFamily') == [1]
assert float(info['MinimumOSVersion']) >= 26
assert not info.get('UIDesignRequiresCompatibility', False)
assert 'NSLocalNetworkUsageDescription' in info and '_flick-photo._tcp' in info['NSBonjourServices']
assert info['NSNearbyInteractionUsageDescription']
assert info['CFBundleDisplayName'] == '\u4e00\u7529'
assert info['CFBundleShortVersionString'] == '0.3.0'
assert set(info['CFBundleIcons']['CFBundleAlternateIcons']) == {'FlickPhoto','FlickRipple','FlickOrange','FlickDuet','FlickHappy'}
assert len(list(app.glob('*.wav'))) == 12
extensions = list((app / 'PlugIns').glob('*.appex'))
assert len(extensions) == 1, 'Expected embedded native share extension'
extension_info = plistlib.loads((extensions[0] / 'Info.plist').read_bytes())
extension_executable = extensions[0] / extension_info['CFBundleExecutable']
extension_binary = extension_executable.read_bytes()
ext_magic, ext_cpu = struct.unpack_from('<II', extension_binary)
assert ext_magic == 0xFEEDFACF and ext_cpu == 0x0100000C
assert extension_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services'
assert extension_info['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
assert extension_info['UIDeviceFamily'] == [1]
assert len(list(extensions[0].glob('*.wav'))) == 12
executables = {executable, extension_executable}
assert not list(app.rglob('*.p12')) and not list(app.rglob('*.mobileprovision'))
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            entry = zipfile.ZipInfo('Payload/' + app.name + '/' + path.relative_to(app).as_posix())
            entry.create_system = 3
            entry.external_attr = (0o100755 if path in executables else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
report = {'file': destination.name, 'bundle_id': info['CFBundleIdentifier'], 'minimum_iOS': info['MinimumOSVersion'], 'sdk': info.get('DTSDKName'), 'arm64': True, 'platform': 'iPhoneOS', 'share_extension': extension_info['CFBundleIdentifier'], 'signed': False}
(destination.parent / 'build-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
