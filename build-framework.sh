#!/usr/bin/env bash
# Rebuilds the one Go framework the app links.
#
# gomobile puts the whole Go runtime in each framework it makes, so an app
# may link only one: every package the app needs is bound through ./all.
# Two frameworks in one app crash on each other's symbols, which reads as a
# segfault at launch with nothing pointing at the cause.
set -euo pipefail

cd "$(dirname "$0")"

# gomobile looks for gobind on PATH, and go install puts it in GOPATH/bin.
export PATH="$(go env GOPATH)/bin:$PATH"

if ! command -v gomobile >/dev/null; then
  echo "installing gomobile…"
  go install golang.org/x/mobile/cmd/gomobile@latest
  gomobile init
fi

# CGO is what lets mygo's purego calls build for iOS; without it the build
# stops on _PUREGO_REQUIRES_CGO_ON_IOS.
CGO_ENABLED=1 gomobile bind -target ios -o All.xcframework ./all

echo
echo "exported:"
grep -oE 'All[A-Za-z]+' All.xcframework/ios-arm64/All.framework/Headers/All.objc.h \
  | sort -u | tr '\n' ' '
echo
