#!/usr/bin/env bash
set -euo pipefail

vendor="$(cd "$(dirname "$0")/../Vendor/Mars" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/logkit-mars.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
output="${1:-$vendor/mars.xcframework.zip}"
[[ "$output" = /* ]] || output="$PWD/$output"
base=6aa5b567afada93936252bac2f271c4b43eccd1f

git -C "$work" init -q
git -C "$work" fetch -q --depth=1 https://github.com/Tencent/mars.git "$base"
git -C "$work" checkout -q --detach FETCH_HEAD
git -C "$work" -c user.name=LogKit -c user.email=build@localhost am \
    --committer-date-is-author-date "$vendor"/Patches/*.patch

cd "$work/mars"
TZ=Asia/Shanghai xlog/tests/run_formatter_tests.sh
python3 xlog/tests/verify_ios_xcframework_unittest.py
python3 build_ios.py --xlog-xcframework
framework=cmake_build/iOS-xlog-xcframework/mars.xcframework
python3 xlog/tests/verify_ios_xcframework.py "$framework"
(cd "$(dirname "$framework")" && zip -q -X -r "$work/mars.xcframework.zip" mars.xcframework)
mkdir -p "$(dirname "$output")"
cp "$work/mars.xcframework.zip" "$output"
