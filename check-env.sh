#!/usr/bin/env bash
# Prints what the probe needs before it can run on a phone: the tools, and
# whether a signing identity is there. Run it from this directory.
set -uo pipefail

say() { printf '%-22s %s\n' "$1" "$2"; }
ok() { say "$1" "✓ $2"; }
no() { say "$1" "✗ $2"; }

echo "iOS 探针环境检查"
echo "────────────────"
echo

if xcodebuild -version >/dev/null 2>&1; then
  ok Xcode "$(xcodebuild -version | head -1 | sed 's/Xcode //')"
else
  no Xcode "未安装"
fi

if xcrun simctl list devices available 2>/dev/null | grep -q iPhone; then
  ok 模拟器 "$(xcrun simctl list devices available | grep -c iPhone) 台 iPhone 可用"
else
  no 模拟器 "没有可用的 iPhone 模拟器"
fi

# A physical device shows up here only when connected and trusted.
devices=$(xcrun xctrace list devices 2>/dev/null | grep -c "iPhone (" || true)
if [ "${devices:-0}" -gt 0 ]; then
  ok 真机 "$devices 台已连接"
else
  say 真机 "未连接（插上数据线并点信任）"
fi

ids=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Development\|iPhone Developer" || true)
if [ "${ids:-0}" -gt 0 ]; then
  ok 签名证书 "$ids 个可用"
else
  no 签名证书 "没有：Xcode → Settings → Accounts 添加 Apple ID"
fi

echo
if [ -d All.xcframework ]; then
  ok 框架 "All.xcframework 已构建"
else
  no 框架 "先运行 ./build-framework.sh"
fi
