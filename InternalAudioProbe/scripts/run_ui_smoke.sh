#!/bin/bash
set -euo pipefail
export_ui_attachments() {
  if [ -d dist/Interaction.xcresult ]; then
    xcrun xcresulttool export attachments --path dist/Interaction.xcresult --output-path dist/UIAttachments || true
  fi
}
trap export_ui_attachments EXIT
DEVICE=$(python3 - <<'PY'
import json, subprocess
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=[d for runtime,items in inventory['devices'].items() if 'iOS-27' in runtime for d in items if 'iPhone' in d['name'] and d.get('isAvailable')]
assert devices, 'An installed iOS 27 iPhone Simulator is required'
print(devices[0]['udid'])
PY
)
if ! xcrun simctl list devices booted | grep -q "$DEVICE"; then xcrun simctl boot "$DEVICE"; fi
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild build-for-testing -project InternalAudioProbe.xcodeproj -scheme InternalAudioProbe \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/simulator \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee dist/simulator-build.log
xcrun simctl install "$DEVICE" build/simulator/Build/Products/Debug-iphonesimulator/InternalAudioProbe.app
APP_DATA=$(xcrun simctl get_app_container "$DEVICE" com.lightsquare.internalaudioprobe data)
python3 scripts/install_ui_fixture.py "$APP_DATA/Documents"
xcodebuild test-without-building -project InternalAudioProbe.xcodeproj -scheme InternalAudioProbe \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/simulator \
  -parallel-testing-enabled NO -resultBundlePath dist/Interaction.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee dist/ui-tests.log
