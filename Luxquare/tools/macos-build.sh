#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
mkdir -p dist
xcodebuild -version | tee dist/toolchain.txt
xcrun --sdk iphoneos --show-sdk-version | tee -a dist/toolchain.txt
xcrun --sdk iphoneos --show-sdk-version | grep -E '^27\.'
python3 tools/verify_public_source.py . --report dist/source-check.json
python3 tools/verify_parser_fixture.py | tee dist/protocol-fixture-check.log
swift Tests/DialogueSSEParserChecks.swift 2>&1 | tee dist/protocol-tests.log
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen --version | tee -a dist/toolchain.txt
sw_vers | tee -a dist/toolchain.txt
uname -m | tee -a dist/toolchain.txt
xcodegen generate
xcodebuild build -project Luxquare.xcodeproj -scheme Luxquare \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee dist/iphone-build.log
python3 tools/package_unsigned_ipa.py build/device/Build/Products/Release-iphoneos/Luxquare.app \
  dist/Luxquare-unsigned.ipa --bundle-id org.luxquare.app
git rev-parse HEAD > dist/source-commit.txt
xcrun simctl list devices available --json > dist/simulator-inventory.json
SIMULATOR_ID=$(python3 - <<'PY'
import json
devices = [d for group in json.load(open('dist/simulator-inventory.json'))['devices'].values()
           for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not devices:
    raise SystemExit('No available iPhone simulator')
devices.sort(key=lambda d: (d['name'] != 'iPhone 18 Pro', d['state'] != 'Booted', d['name']))
print(devices[0]['udid'])
PY
)
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --batteryState charged --batteryLevel 100 || true
if [ -d UITests ] && find UITests -name '*.swift' -print -quit | grep -q .; then
  xcodebuild test -project Luxquare.xcodeproj -scheme Luxquare \
    -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath build/simulator -resultBundlePath dist/Smoke.xcresult \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -collect-test-diagnostics never 2>&1 | tee dist/simulator-tests.log
  xcrun xcresulttool export attachments --path dist/Smoke.xcresult --output-path dist/UIAttachments || true
else
  xcodebuild build -project Luxquare.xcodeproj -scheme Luxquare \
    -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    2>&1 | tee dist/simulator-build.log
fi
SIM_APP=build/simulator/Build/Products/Debug-iphonesimulator/Luxquare.app
xcrun simctl install "$SIMULATOR_ID" "$SIM_APP"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" org.luxquare.app | tee dist/simulator-launch.txt
sleep 2
xcrun simctl io "$SIMULATOR_ID" screenshot dist/Luxquare-first-launch.png
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path('.')
files = [p for p in root.rglob('*') if p.is_file() and not set(p.parts) & {'build','dist','.git','Luxquare.xcodeproj'}]
manifest = [{'path':p.as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(files)]
Path('dist/source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'device_package':True,'simulator_installed':True,'simulator_launched':True,'physical_iphone_verified':False}))
PY
