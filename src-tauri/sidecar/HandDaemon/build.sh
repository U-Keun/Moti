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

SRC="/tmp/handdaemon_main.swift"
cat > "$SRC" << 'SWIFT'
import Foundation
import AVFoundation

@inline(__always) func emit(_ s: String) {
    FileHandle.standardOutput.write(Data((s + "\n").utf8))
    fflush(stdout)
}

emit(#"{"type":"hello"}"#)

var granted: Bool? = nil
AVCaptureDevice.requestAccess(for: .video) { ok in
    granted = ok
    emit(#"{"type":"camera_access","granted":\#(ok)}"#)
}
while granted == nil { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }

guard granted == true else { exit(2) }

let session = AVCaptureSession()
session.beginConfiguration()
if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

let types: [AVCaptureDevice.DeviceType]
if #available(macOS 14.0, *) {
    types = [.builtInWideAngleCamera, .continuityCamera]
} else {
    types = [.builtInWideAngleCamera]
}
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: types,
    mediaType: .video,
    position: .unspecified
)
guard let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video) else {
    FileHandle.standardError.write(Data("[HandDaemon] no camera device\n".utf8))
    exit(3)
}
guard let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input) else {
  FileHandle.standardError.write(Data("[HandDaemon] cannot add input\n".utf8))
  exit(4)
}
session.addInput(input)
session.commitConfiguration()
session.startRunning()

emit(#"{"type":"camera_ready"}"#)

RunLoop.current.run()
SWIFT

swiftc "$SRC" -O \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" \
    -framework AVFoundation \
    -o "$OUT"

chmod +x "$OUT"
echo "Built sidecar: $OUT"
