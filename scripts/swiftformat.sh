#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.59.1"
expected_commit="22a472ced4c621a0e41b982a6f32dec868d09392"
tool_root="${LYGLYPHTEXT_BUILD_ROOT:-$project_root/.build}/tools/swiftformat/$version"
source_dir="$tool_root/source"
build_dir="$tool_root/build"
cached_binary="$build_dir/release/swiftformat"

if [[ "${1:-}" == --bootstrap ]]; then
    [[ $# == 1 ]] || { echo 'Usage: swiftformat.sh --bootstrap' >&2; exit 2; }
    mkdir -p "$tool_root"
    if [[ ! -d "$source_dir/.git" ]]; then
        [[ ! -e "$source_dir" ]] || { echo "Refusing to replace existing source directory: $source_dir" >&2; exit 2; }
        git clone --quiet --depth 1 --branch "$version" https://github.com/nicklockwood/SwiftFormat.git "$source_dir"
    fi
    actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
    [[ "$actual_commit" == "$expected_commit" ]] || { echo "SwiftFormat source commit mismatch: $actual_commit" >&2; exit 2; }
    [[ -z "$(git -C "$source_dir" status --porcelain)" ]] || { echo 'SwiftFormat source has local changes; refusing to build.' >&2; exit 2; }
    swift build --package-path "$source_dir" --scratch-path "$build_dir" -c release --product swiftformat
    binary="$cached_binary"
else
    [[ $# -gt 0 ]] || { echo 'Usage: swiftformat.sh --bootstrap | [--lint] <paths...>' >&2; exit 2; }
    binary="${LYGLYPHTEXT_SWIFTFORMAT:-$cached_binary}"
fi

[[ -x "$binary" ]] || { echo 'SwiftFormat 0.59.1 unavailable. Run scripts/swiftformat.sh --bootstrap or set LYGLYPHTEXT_SWIFTFORMAT.' >&2; exit 2; }
actual_version="$("$binary" --version)"
[[ "$actual_version" == "$version" ]] || { echo "SwiftFormat version mismatch: expected $version, got $actual_version" >&2; exit 2; }

if [[ "${1:-}" == --bootstrap ]]; then
    echo "SwiftFormat $actual_version ready: $binary"
    exit 0
fi

exec "$binary" --config "$project_root/.swiftformat" "$@"
