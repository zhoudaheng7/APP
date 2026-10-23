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
assert not list(app.rglob('*.p12')) and not list(app.rglob('*.mobileprovision'))
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            entry = zipfile.ZipInfo('Payload/' + app.name + '/' + path.relative_to(app).as_posix())
            entry.create_system = 3
            entry.external_attr = (0o100755 if path == executable else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
report = {'file': destination.name, 'bundle_id': info['CFBundleIdentifier'], 'minimum_iOS': info['MinimumOSVersion'], 'sdk': info.get('DTSDKName'), 'arm64': True, 'platform': 'iPhoneOS', 'signed': False}
(destination.parent / 'build-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
