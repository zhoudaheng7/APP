#!/bin/bash
set -euo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1
if [ -d /Applications/Xcode_27.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
fi
mkdir -p dist
xcodebuild -version | tee dist/toolchain.txt
python3 tools/make_native_icon.py
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec native-project.yml
swift test --package-path . 2>&1 | tee dist/domain-tests.log
xcodebuild build -project LifeOS.xcodeproj -scheme LifeOS -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee dist/device-build.log
python3 - <<'PY'
from pathlib import Path
import zipfile,plistlib,json,hashlib
app=Path('build/device/Build/Products/Release-iphoneos/LifeOS.app')
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='app.lifeos.personal'
assert info.get('LifeOSUpdateManifestURL','')==''
with zipfile.ZipFile('dist/LifeOS-unsigned.ipa','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(app.rglob('*')):
        if p.is_file(): z.write(p,'Payload/LifeOS.app/'+p.relative_to(app).as_posix())
Path('dist/unsigned-check.json').write_text(json.dumps({'device_package':True,'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'physical_iphone_verified':False,'sha256':hashlib.sha256(Path('dist/LifeOS-unsigned.ipa').read_bytes()).hexdigest()},indent=2))
PY
xcrun simctl list devices available --json > dist/simulators.json
SIMULATOR_ID=$(python3 - <<'PY'
import json
devices=[d for group in json.load(open('dist/simulators.json'))['devices'].values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
devices.sort(key=lambda d:(d['name']!='iPhone 18 Pro',d['state']!='Booted',d['name']))
assert devices,'No available iPhone Simulator'
print(devices[0]['udid'])
PY
)
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --batteryState charged --batteryLevel 100 || true
xcrun simctl ui "$SIMULATOR_ID" appearance light
xcodebuild test -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/simulator \
  -resultBundlePath dist/Native.xcresult -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee dist/native-tests.log
xcrun xcresulttool export attachments --path dist/Native.xcresult --output-path dist/Screenshots || true
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" app.lifeos.personal -ui-testing
sleep 2
xcrun simctl io "$SIMULATOR_ID" screenshot dist/LifeOS-light.png
xcrun simctl ui "$SIMULATOR_ID" appearance dark
sleep 1
xcrun simctl io "$SIMULATOR_ID" screenshot dist/LifeOS-dark.png
git rev-parse HEAD > dist/source-commit.txt
