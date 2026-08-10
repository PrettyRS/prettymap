#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
for test_file in \
    tests/test_world_map.lua \
    tests/test_resources.lua \
    tests/test_region_picker.lua \
    tests/test_map.lua \
    tests/test_performance.lua \
    tests/test_asset_manifest.lua
do
    lua "$test_file"
done
