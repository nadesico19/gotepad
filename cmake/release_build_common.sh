#!/bin/bash
# Shared by the root release scripts. Requires macOS's Bash 3.2 or newer.

fail() { echo "$*" >&2; exit 1; }

project_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$project_root" "$1" ;;
    esac
}

release_helper() {
    "$python_path" "$project_root/cmake/release_build.py" "$project_root" "$@"
}

initialize_release() {
    [[ "$(uname -s)" == Darwin ]] || fail "This script requires macOS."
    godot_path="${GODOT_PATH:-$project_root/.tmp/tools/godot-4.7.1/Godot.app/Contents/MacOS/Godot}"
    cmake_path="${CMAKE_PATH:-cmake}"
    python_path="${PYTHON_PATH:-/usr/bin/python3}"
    build_jobs="${BUILD_JOBS:-8}"
    host_arch="$(uname -m)"
    [[ "$host_arch" == arm64 || "$host_arch" == x86_64 ]] || fail "Unsupported host: $host_arch"
    command -v "$godot_path" >/dev/null || fail "Set GODOT_PATH to the Godot executable."
    command -v "$cmake_path" >/dev/null || fail "Set CMAKE_PATH to CMake."
    command -v "$python_path" >/dev/null || fail "Set PYTHON_PATH to Python 3."
    command -v ninja >/dev/null || fail "Ninja is required on PATH."
    [[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_JOBS must be a positive integer."
    local godot_version
    godot_version="$("$godot_path" --version)"
    [[ "$godot_version" == 4.7.1.stable.* ]] || fail "Expected Godot 4.7.1 stable, found: $godot_version"
    mkdir -p "$project_root/.tmp/$platform"
    work_directory="$(mktemp -d "$project_root/.tmp/$platform-release.XXXXXX")"
    export_project="$work_directory/project"
    trap 'rm -rf -- "$work_directory"' EXIT
    log_directory="$project_root/.tmp/$platform"
    exec > >(tee "$log_directory/release-build.log") 2>&1
    release_helper validate "$platform"
}

build_host_extension() {
    local host_build_directory="$project_root/.tmp/build-macos-$host_arch-debug-for-editor"
    "$cmake_path" -S "$project_root" -B "$host_build_directory" -G Ninja \
        -DCMAKE_BUILD_TYPE=Debug "-DCMAKE_OSX_ARCHITECTURES=$host_arch" \
        -DGODOTCPP_TARGET=template_debug -DGODOTCPP_API_VERSION=4.7 \
        -DBUILD_EMBEDDED_KATAGO=OFF -DBUILD_ANDROID_KATAGO_OPENCL=OFF \
        "-DPython3_EXECUTABLE=$python_path"
    "$cmake_path" --build "$host_build_directory" --config Debug \
        --target go_gdext --parallel "$build_jobs"
}

godot_logged() {
    local log_path="$1"
    shift
    if [[ "${1:-}" == --import && ! -d "$export_project/.godot/imported" ]]; then
        # A fresh staging tree has no imported fonts/textures yet. Godot loads
        # the project theme before its initial resource scan, so bootstrap the
        # cache first, then require a clean full import in the checked pass.
        echo "Bootstrapping staged resource cache; log: $log_path.bootstrap"
        "$godot_path" --headless --path "$export_project" "$@" > "$log_path.bootstrap" 2>&1
    fi
    "$godot_path" --headless --path "$export_project" "$@" 2>&1 | tee "$log_path"
    # Preserve the known Godot 4.7.1 debugger teardown message in the log.
    if awk '/SCRIPT ERROR:|^ERROR:/ && $0 != "ERROR: Plugin is not attached to debugger." { found=1 } END { exit !found }' "$log_path"; then
        fail "Godot reported errors; see $log_path"
    fi
}

require_file() { [[ -f "$1" ]] || fail "Required file is missing: $1"; }

publish_file() {
    local source_path="$1" output_path="$2"
    require_file "$source_path"
    mkdir -p "$(dirname "$output_path")"
    # Preserve previous output, including user-specified output outside .tmp.
    if [[ -e "$output_path" ]]; then
        mv "$output_path" "$output_path.previous-$(basename "$work_directory")"
    fi
    cp -p "$source_path" "$output_path"
    echo "Created: $output_path"
    shasum -a 256 "$output_path"
}
