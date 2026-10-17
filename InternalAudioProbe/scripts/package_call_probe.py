"""Package the standalone, unprivileged SCK probe. Does not alter the stable app."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile
from package_ipa import verify_binary

app, destination = map(Path, sys.argv[1:3])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.lightsquare.callaudioprobe'
assert info['CFBundleShortVersionString'] == '0.1.0'
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
assert set(info['UIBackgroundModes']) == {'audio', 'screen-capture'}
assert info.get('NSMicrophoneUsageDescription') and info.get('NSScreenCaptureUsageDescription')
assert (app / 'Assets.car').is_file() and info.get('CFBundleIcons')
assert (app / 'HaishinKit-LICENSE.txt').is_file()
assert not (app / 'embedded.mobileprovision').exists()
assert not (app / 'PlugIns').exists(), 'Standalone probe has no extension or App Group dependency'
binary = verify_binary((app / info['CFBundleExecutable']).read_bytes())
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob('*')):
        if file.is_file():
            archive.write(file, (Path('Payload') / app.name / file.relative_to(app)).as_posix())
with zipfile.ZipFile(destination) as archive:
    assert archive.testzip() is None
    verify_binary(archive.read(f'Payload/{app.name}/{info["CFBundleExecutable"]}'))
receipt = dict(binary, bundleIdentifier=info['CFBundleIdentifier'], version=info['CFBundleShortVersionString'],
    build=info['CFBundleVersion'], signed=False, experimental=True, callCaptureVerified=False,
    size=destination.stat().st_size, sha256=hashlib.sha256(destination.read_bytes()).hexdigest())
destination.with_suffix('.verification.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
