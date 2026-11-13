#!/usr/bin/env sh
# Code generation (drift, freezed, riverpod, json_serializable).
#   tool/gen.sh          one-shot build
#   tool/gen.sh watch    rebuild on change
set -e
cd "$(dirname "$0")/.."
mode="${1:-build}"
dart run build_runner "$mode"
