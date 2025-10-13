set -euo pipefail
mkdir -p HandDaemon.app/Contents/MacOS
cat > HandDaemon.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>HandDaemon</string>
    <key>CFBundleDisplayName</key><string>HandDaemon</string>
    <key>CFBundleIdentifier</key><string>dev.u-keun.HandDaemon</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>HandDaemon</key>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key>
    <string>HandDaemon needs the camera to enable gesture detection.</string>
</dict></plist>
PLIST
cat > main.swift <<'SWIFT'
import Foundation
import AVFoundation
func printHelloJSON() {
    let s = "{\"type\":\"hello\"}\n"
    FileHandle.standardOutput.write(Data(s.utf8))
    fflush(stdout)
}
func requestCameraAndWait() {
    AVCaptureDevice.requestAccess(for: .video) { _ in
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
printHelloJSON()
requestCameraAndWait()
CFRunLoopRun()
SWIFT
swiftc main.swift -framework AVFoundation -o HandDaemon.app/Contents/MacOS/HandDaemon
echo "Built: HandDaemon.app"
