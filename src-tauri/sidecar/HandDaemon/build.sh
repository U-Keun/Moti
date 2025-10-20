#!/usr/bin/env sh
set -eu

arch="$(uname -m)"
case "$arch" in
  arm64)  TRIPLE="aarch64-apple-darwin" ;;
  x86_64) TRIPLE="x86_64-apple-darwin" ;;
  *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_TAURI_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT="$SRC_TAURI_DIR/binaries/HandDaemon-${TRIPLE}"
mkdir -p "$SRC_TAURI_DIR/binaries"

PLIST="$SCRIPT_DIR/Info.plist"

SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"

if ! find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.swift' | grep -q . ; then
  echo "No Swift sources found in $SCRIPT_DIR" >&2
  exit 1
fi

find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.swift' -print0 \
| xargs -0 swiftc \
    -sdk "$SDK_PATH" \
    -O \
    -module-name HandDaemon \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" \
    -framework AVFoundation \
    -framework Vision \
    -framework CoreGraphics \
    -framework CoreMedia \
    -framework CoreVideo \
    -o "$OUT"

chmod +x "$OUT"
echo "Built sidecar: $OUT"
