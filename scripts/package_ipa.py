"""Package a real Xcode device build. Never pretend source code is an IPA."""
import plistlib
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

app, destination = map(Path, sys.argv[1:])
if not app.is_dir():
    raise SystemExit('Xcode app bundle missing; compile first.')
info = plistlib.loads((app / 'Info.plist').read_bytes())
executable = app / info['CFBundleExecutable']
if executable.read_bytes()[:4] != b'\xcf\xfa\xed\xfe':
    raise SystemExit('App executable is not a 64-bit Mach-O device binary.')
extension = app / 'PlugIns' / 'Broadcast.appex'
ext_info = plistlib.loads((extension / 'Info.plist').read_bytes())
if ext_info['NSExtension']['NSExtensionPointIdentifier'] != 'com.apple.broadcast-services-upload':
    raise SystemExit('Broadcast extension missing or incorrect.')
if ext_info['CFBundleIdentifier'] != info['CFBundleIdentifier'] + '.Broadcast':
    raise SystemExit('App and extension identifiers do not match.')
destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    payload = Path(tmp) / 'Payload'
    payload.mkdir()
    shutil.copytree(app, payload / app.name, symlinks=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(Path(tmp).rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(tmp))
print('Packaged unsigned device IPA:', destination)
