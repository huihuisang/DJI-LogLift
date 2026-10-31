#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${LOGBATCH_DERIVED_DATA:-$HOME/Library/Caches/LogBatch/DerivedData}"
MODE="${1:---build-only}"
FOREGROUND=false
for argument in "$@"; do
    if [[ "$argument" == "--foreground" ]]; then FOREGROUND=true; fi
done
case "$MODE" in
    --build-only) ;;
    --verify|--debug|--logs|--telemetry)
        if [[ "$FOREGROUND" != true ]]; then
            echo 'Launching requires --foreground.' >&2
            exit 2
        fi
        ;;
    *) echo 'usage: build_and_run.sh [--build-only|--verify|--debug|--logs|--telemetry] [--foreground]' >&2; exit 2 ;;
esac
cd "$ROOT_DIR"
xcodegen generate --quiet
xcodebuild -project LogBatch.xcodeproj -scheme LogBatch -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO build
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/LogLift for DJI.app"
if [[ "$MODE" == "--build-only" ]]; then
    printf 'Built app: %s\n' "$APP_BUNDLE"
    exit 0
fi
APP_ARGUMENTS=()
case "${LOGBATCH_PREVIEW_LANGUAGE:-}" in
    en|zh-Hans|ja|ko) APP_ARGUMENTS+=("-AppleLanguages" "(${LOGBATCH_PREVIEW_LANGUAGE})") ;;
    '') ;;
    *) echo 'Unsupported preview language.' >&2; exit 2 ;;
esac
case "${LOGBATCH_PREVIEW_APPEARANCE:-}" in
    light|dark) APP_ARGUMENTS+=("--studio-appearance" "$LOGBATCH_PREVIEW_APPEARANCE") ;;
    '') ;;
    *) echo 'Unsupported preview appearance.' >&2; exit 2 ;;
esac
if [[ "${LOGBATCH_REDUCE_MOTION_PREVIEW:-0}" == 1 ]]; then APP_ARGUMENTS+=("--reduce-motion-preview"); fi
open_app() {
    if [[ "${#APP_ARGUMENTS[@]}" -gt 0 ]]; then
        /usr/bin/open -n "$APP_BUNDLE" --args "${APP_ARGUMENTS[@]}"
    else
        /usr/bin/open -n "$APP_BUNDLE"
    fi
}
pkill -x LogLift >/dev/null 2>&1 || true
case "$MODE" in
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/LogLift" ;;
    --logs|--telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate 'process == "LogLift"'
        ;;
    --verify)
        open_app
        sleep 1
        pgrep -x LogLift >/dev/null
        ;;
esac

