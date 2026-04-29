#!/usr/bin/env bash
set -euo pipefail

ANDROID_WORKSPACE_ROOT="${ANDROID_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ANDROID_APP_DIR="${ANDROID_APP_DIR:-$ANDROID_WORKSPACE_ROOT/zodl-android}"
ANDROID_AVD_NAME="${ANDROID_AVD_NAME:-Pixel_6_API_33_zodl}"
ANDROID_APP_PACKAGE="${ANDROID_APP_PACKAGE:-co.electriccoin.zcash.foss.debug}"
ANDROID_GRADLE_TASK="${ANDROID_GRADLE_TASK:-:app:assembleZcashmainnetFossDebug}"
ANDROID_APK_NAME="${ANDROID_APK_NAME:-app-zcashmainnet-foss-debug.apk}"
ANDROID_BOOT_TIMEOUT_SECONDS="${ANDROID_BOOT_TIMEOUT_SECONDS:-180}"
ANDROID_EMULATOR_LOG="${ANDROID_EMULATOR_LOG:-$ANDROID_WORKSPACE_ROOT/android-emulator.log}"
ANDROID_EMULATOR_GPU_MODE="${ANDROID_EMULATOR_GPU_MODE:-}"
ANDROID_STATE_DIR="${ANDROID_STATE_DIR:-$ANDROID_WORKSPACE_ROOT/.pids}"
ANDROID_SERIAL_FILE="$ANDROID_STATE_DIR/android-emulator.serial"

mkdir -p "$ANDROID_STATE_DIR"

android_fail() {
    printf '\033[31mError: %s\033[0m\n' "$*" >&2
    exit 1
}

android_sdk_root() {
    if [ -n "${ANDROID_HOME:-}" ]; then
        printf '%s\n' "$ANDROID_HOME"
        return 0
    fi

    if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
        printf '%s\n' "$ANDROID_SDK_ROOT"
        return 0
    fi

    local default_sdk="$HOME/Library/Android/sdk"
    if [ -d "$default_sdk" ]; then
        printf '%s\n' "$default_sdk"
        return 0
    fi

    return 1
}

android_require_sdk() {
    local sdk_root
    sdk_root="$(android_sdk_root)" || android_fail "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT."
    [ -x "$sdk_root/emulator/emulator" ] || android_fail "Android emulator binary not found under $sdk_root/emulator/emulator"
    command -v adb >/dev/null 2>&1 || android_fail "adb is not on PATH"
}

android_host_is_macos_arm64() {
    [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]
}

android_resolve_emulator_gpu_mode() {
    if [ -n "$ANDROID_EMULATOR_GPU_MODE" ]; then
        printf '%s\n' "$ANDROID_EMULATOR_GPU_MODE"
        return 0
    fi

    if android_host_is_macos_arm64; then
        printf '%s\n' "swiftshader_indirect"
        return 0
    fi

    printf '%s\n' "auto"
}

android_emulator_serials() {
    adb devices | awk 'NR > 1 && $1 ~ /^emulator-[0-9]+$/ { print $1 }'
}

android_avd_name_for_serial() {
    local serial="$1"
    adb -s "$serial" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r'
}

android_running_serial_for_avd() {
    local serial
    while read -r serial; do
        [ -n "$serial" ] || continue
        if [ "$(android_avd_name_for_serial "$serial")" = "$ANDROID_AVD_NAME" ]; then
            printf '%s\n' "$serial"
            return 0
        fi
    done < <(android_emulator_serials)

    return 1
}

android_wait_for_boot() {
    local serial="$1"
    local timeout="${2:-$ANDROID_BOOT_TIMEOUT_SECONDS}"
    local i

    for i in $(seq 1 "$timeout"); do
        if [ "$(adb -s "$serial" get-state 2>/dev/null || true)" = "device" ] &&
            [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
            return 0
        fi
        sleep 1
    done

    return 1
}

android_start_emulator() {
    android_require_sdk

    local existing_serial=""
    if existing_serial="$(android_running_serial_for_avd)"; then
        android_wait_for_boot "$existing_serial"
        printf '%s\n' "$existing_serial" > "$ANDROID_SERIAL_FILE"
        printf '\033[36mAndroid emulator already running:\033[0m %s (%s)\n' "$ANDROID_AVD_NAME" "$existing_serial" >&2
        printf '%s\n' "$existing_serial"
        return 0
    fi

    local sdk_root
    sdk_root="$(android_sdk_root)"

    local before_serials
    before_serials="$(android_emulator_serials | tr '\n' ' ')"

    local gpu_mode
    gpu_mode="$(android_resolve_emulator_gpu_mode)"

    local emulator_args=(
        -avd "$ANDROID_AVD_NAME"
        -no-snapshot-save
    )
    if [ -n "$gpu_mode" ]; then
        emulator_args+=(-gpu "$gpu_mode")
    fi
    if [ "$gpu_mode" = "swiftshader_indirect" ] && android_host_is_macos_arm64; then
        # Keep Apple Silicon on the software-safe path to avoid host rendering flicker.
        emulator_args+=(-feature -Vulkan -feature -GLDirectMem)
    fi

    nohup "$sdk_root/emulator/emulator" \
        "${emulator_args[@]}" \
        > "$ANDROID_EMULATOR_LOG" 2>&1 &

    local serial=""
    local i
    for i in $(seq 1 "$ANDROID_BOOT_TIMEOUT_SECONDS"); do
        local candidate
        while read -r candidate; do
            [ -n "$candidate" ] || continue
            case " $before_serials " in
                *" $candidate "*) continue ;;
            esac
            serial="$candidate"
            break
        done < <(android_emulator_serials)

        if [ -n "$serial" ]; then
            break
        fi
        sleep 1
    done

    [ -n "$serial" ] || android_fail "Timed out waiting for $ANDROID_AVD_NAME to appear. See $ANDROID_EMULATOR_LOG"

    if ! android_wait_for_boot "$serial"; then
        android_fail "Timed out waiting for $ANDROID_AVD_NAME ($serial) to boot. See $ANDROID_EMULATOR_LOG"
    fi

    local actual_avd_name
    actual_avd_name="$(android_avd_name_for_serial "$serial")"
    [ "$actual_avd_name" = "$ANDROID_AVD_NAME" ] || android_fail "Expected $ANDROID_AVD_NAME but emulator booted as $actual_avd_name"

    printf '%s\n' "$serial" > "$ANDROID_SERIAL_FILE"
    printf '\033[32mAndroid emulator ready:\033[0m %s (%s)\n' "$ANDROID_AVD_NAME" "$serial" >&2
    printf '%s\n' "$serial"
}

android_find_built_apk() {
    find "$ANDROID_APP_DIR/app/build/outputs/apk" -name "$ANDROID_APK_NAME" -print | head -n 1
}
