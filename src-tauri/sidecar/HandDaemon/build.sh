set -euo pipefail

arch="$(uname -m)"
arch="$(uname -m)"
if [ "$arch" = "arm64" ]; then
  TRIPLE="aarch64-apple-darwin"
elif [ "$arch" = "x86_64" ]; then
  TRIPLE="x86_64-apple-darwin"
else
  echo "unsupported arch: $arch" >&2; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_TAURI_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT="$SRC_TAURI_DIR/binaries/HandDaemon-${TRIPLE}"
mkdir -p "$SRC_TAURI_DIR/binaries"

PLIST="$(mktemp)"
cat > "$PLIST" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>HandDaemon</string>
    <key>CFBundleIdentifier</key><string>dev.u-keun.HandDaemon</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSCameraUsageDescription</key>
    <string>제스처 인식을 위해 카메라 접근이 필요합니다.</string>
    <key>NSCameraUseContinuityCameraDeviceType</key>
    <true/>
</dict></plist>
PLIST

SRC="$SCRIPT_DIR/main.swift"
swiftc "$SRC" -O \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" \
    -framework AVFoundation \
    -o "$OUT"

chmod +x "$OUT"
echo "Built sidecar: $OUT"
