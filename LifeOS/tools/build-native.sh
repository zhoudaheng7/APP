#!/bin/bash
set -euo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1
if [ -d /Applications/Xcode_26.6.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
fi
mkdir -p dist
TEST_MODE="${DAYISLE_TEST_MODE:-full}"
PHASE="${1:-all}"
case "$TEST_MODE" in full|unit) ;; *) echo 'Unknown test mode' >&2; exit 2 ;; esac
case "$PHASE" in all|prepare|verify) ;; *) echo 'Unknown phase' >&2; exit 2 ;; esac
export TEST_MODE
python3 - <<'PY'
import json,os
from pathlib import Path
Path('dist/test-mode.json').write_text(json.dumps({'mode':os.environ['TEST_MODE'],'release_gate_requested':os.environ['TEST_MODE']=='full'},indent=2))
PY
collect_evidence() {
  git rev-parse HEAD > dist/source-commit.txt
  if [ -d dist/Native.xcresult ]; then
    xcrun xcresulttool export attachments --path dist/Native.xcresult --output-path dist/Screenshots || true
  fi
}
trap collect_evidence EXIT
if [ "$PHASE" != verify ]; then
xcodebuild -version | tee dist/toolchain.txt
python3 tools/make_native_icon.py
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec native-project.yml
swift test --package-path . 2>&1 | tee dist/domain-tests.log
if [ "$TEST_MODE" = full ]; then
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
fi
xcrun simctl list devices available --json > dist/simulators.json
SIMULATOR_ID=$(python3 - <<'PY'
import json
devices=[dict(d,runtime=runtime) for runtime,group in json.load(open('dist/simulators.json'))['devices'].items() if '.iOS-' in runtime for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
def runtime_version(d): return tuple(-int(x) for x in d['runtime'].split('.iOS-')[-1].split('-'))
devices.sort(key=lambda d:(d['state']!='Booted',runtime_version(d),d['name']!='iPhone 17 Pro',d['name']))
assert devices,'No available iPhone Simulator'
print(devices[0]['udid'])
PY
)
printf '%s\n' "$SIMULATOR_ID" > dist/simulator-id.txt
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
build_simulator() {
  xcodebuild build-for-testing -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/simulator \
    "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee dist/simulator-build.log
}
if [ "$TEST_MODE" = unit ]; then build_simulator -only-testing:LifeOSNativeTests; else build_simulator; fi
fi
if [ "$PHASE" = prepare ]; then exit 0; fi
SIMULATOR_ID=$(cat dist/simulator-id.txt)
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --batteryState charged --batteryLevel 100 || true
xcrun simctl ui "$SIMULATOR_ID" appearance light
if [ "$TEST_MODE" = unit ]; then
  xcodebuild test-without-building -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/simulator \
    -only-testing:LifeOSNativeTests -resultBundlePath dist/Native.xcresult -parallel-testing-enabled NO \
    -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    2>&1 | tee dist/native-tests.log
  exit 0
fi
BASELINE=5800cd924066c81d4096efbb50f5b0fd7141fdc9
mkdir -p build/baseline
git -C .. archive "$BASELINE" LifeOS | tar -x -C build/baseline
(
  cd build/baseline/LifeOS
  python3 tools/make_native_icon.py
  xcodegen generate --spec native-project.yml
  xcodebuild test -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath ../derived \
    -only-testing:LifeOSUITests/LifeOSUITests/testCreateTaskSurvivesRelaunch \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
) 2>&1 | tee dist/baseline-install.log
xcrun simctl get_app_container "$SIMULATOR_ID" app.lifeos.personal data > dist/baseline-container.txt
python3 tools/verify-native-upgrade.py capture --container-file dist/baseline-container.txt --output dist/baseline-data-proof.json
xcodebuild test-without-building -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/simulator \
  -resultBundlePath dist/Native.xcresult -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee dist/native-tests.log
xcrun simctl get_app_container "$SIMULATOR_ID" app.lifeos.personal data > dist/upgraded-container.txt
python3 tools/verify-native-upgrade.py verify --before dist/baseline-data-proof.json --container-file dist/upgraded-container.txt --baseline-container-file dist/baseline-container.txt --output dist/upgrade-check.json
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" app.lifeos.personal -ui-testing
sleep 2
xcrun simctl io "$SIMULATOR_ID" screenshot dist/LifeOS-light.png
xcrun simctl ui "$SIMULATOR_ID" appearance dark
sleep 1
xcrun simctl io "$SIMULATOR_ID" screenshot dist/LifeOS-dark.png
python3 - <<'PY'
from pathlib import Path
import json,subprocess,re,hashlib
package=json.loads(Path('dist/unsigned-check.json').read_text())
log=Path('dist/native-tests.log').read_text()
required=['testActualLegacySQLitePayloadMigratesAndReopensWithoutChangingIDs','testCompetingStoreNeverOverwritesAConcurrentCommit','testPhotoProcessingRemovesPrivateMetadataAndBackupRejectsItsReintroduction','testNativeJavaScriptCoreRunsFrozenMachineAndProjectionCorpus','testWithdrawCheckpointsAndRetiresOldPayloadsThenUpdatesRegisteredNote','testWithdrawLeavesHandEditedManagedBlockAsVisibleConflict','testStoryPDFPaginatesChineseAndReopensSavedSnapshotAfterSourceDeletion','testClosingComposerKeepsDraftUntilExplicitSave','testStoryConfirmationPersistsAndOpensActualPDF','testBaselineUpgradePreservesV1Task']
required.append('testShareFileStaysUntilSystemCompletionAndChangedExportIsNeverDeleted')
required.append('testTypedReviewShortcutAppendSurvivesPendingDebounceAndPreservesAllEdits')
required.append('testNewReviewShortcutAppendCarriesLegacyDraftWithoutSavingFact')
assert all(re.search(r"Test Case .* "+re.escape(name)+r"\]' passed",log) for name in required), 'A required release test did not actually pass'
passed_cases = set(re.findall(r"Test Case '-\[(LifeOSNativeTests|LifeOSUITests)\.([A-Za-z_][A-Za-z0-9_]*) ([A-Za-z_][A-Za-z0-9_]*)\]' passed",log))
native_count = sum(module == 'LifeOSNativeTests' for module,_,_ in passed_cases)
ui_count = sum(module == 'LifeOSUITests' for module,_,_ in passed_cases)
assert native_count >= 48 and ui_count >= 5, 'Native/UI passed-case counts are unexpectedly small'
assert not re.search(r"Test Case .*' failed",log), 'A failed native/UI case remains'
assert 'testCreateTaskSurvivesRelaunch' in Path('dist/baseline-install.log').read_text(), 'Old app installation gate missing'
Path('dist/required-tests.json').write_text(json.dumps({'passed':required,'native_test_count':native_count,'ui_test_count':ui_count,'minimum_native_test_count':48,'minimum_ui_test_count':5},indent=2))
Path('dist/release-gate.json').write_text(json.dumps({'mode':'full','software_checks':'passed','source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'baseline_to_new_data_preserved':True,'upgrade_identity_method':'CoreData-storeUUID-and-baseline-records-v1','upgrade_check_sha256':hashlib.sha256(Path('dist/upgrade-check.json').read_bytes()).hexdigest(),'domain_native_ui_tests_passed':True,'unsigned_sha256':package['sha256'],'version':package['version'],'build':package['build'],'physical_iphone_verified':False,'real_vault_provider_verified':False},indent=2))
PY
