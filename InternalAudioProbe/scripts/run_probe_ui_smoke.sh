#!/bin/bash
set -euo pipefail
export_probe_attachments() {
  if [ -d dist/ProbeInteraction.xcresult ]; then
    xcrun xcresulttool export attachments --path dist/ProbeInteraction.xcresult --output-path dist/ProbeUIAttachments || true
  fi
}
trap export_probe_attachments EXIT
DEVICE=$(python3 - <<'PY'
import json, subprocess
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=[d for runtime,items in inventory['devices'].items() if 'iOS-27' in runtime for d in items if 'iPhone' in d['name'] and d.get('isAvailable')]
assert devices, 'An iOS 27 iPhone Simulator is required'
print(devices[0]['udid'])
PY
)
if ! xcrun simctl list devices booted | grep -q "$DEVICE"; then xcrun simctl boot "$DEVICE"; fi
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild test -project InternalAudioProbe.xcodeproj -scheme CallAudioProbe \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/probe-simulator \
  -parallel-testing-enabled NO -resultBundlePath dist/ProbeInteraction.xcresult \
  -collect-test-diagnostics never -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee dist/probe-ui-tests.log
