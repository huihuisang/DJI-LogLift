#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
: "${TASK_ARTIFACT_DIR:?Run verification through task-artifacts}"
DERIVED_DATA="${LOGBATCH_DERIVED_DATA:-$HOME/Library/Caches/LogBatch/DerivedData}"
FIXTURE_DIR="$(mktemp -d "$TASK_ARTIFACT_DIR/verification-XXXXXX")"
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 script/sync_dji_luts.py
python3 script/sync_product_images.py
python3 script/prepare_fixtures.py "$FIXTURE_DIR"
./script/build_and_run.sh --build-only > "$FIXTURE_DIR/build.log" 2>&1
python3 script/source_digest.py > "$FIXTURE_DIR/tested-source.json"
if ! xcodebuild -project LogBatch.xcodeproj -scheme LogBatch -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$FIXTURE_DIR/TestResults.xcresult" \
    "LOGBATCH_FIXTURE_DIR=$FIXTURE_DIR" CODE_SIGNING_ALLOWED=NO test > "$FIXTURE_DIR/tests.log" 2>&1; then
    tail -n 100 "$FIXTURE_DIR/tests.log"
    exit 1
fi
python3 script/verify_media.py "$FIXTURE_DIR" | tee "$FIXTURE_DIR/media-report.json"
python3 script/verify_bundle.py "$DERIVED_DATA/Build/Products/Debug/LogLift for DJI.app" | tee "$FIXTURE_DIR/bundle-report.json"
python3 script/source_digest.py > "$FIXTURE_DIR/source-after-tests.json"
cmp "$FIXTURE_DIR/tested-source.json" "$FIXTURE_DIR/source-after-tests.json"
printf 'Verification evidence: %s\n' "$FIXTURE_DIR"
