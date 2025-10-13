# HandDaemon (sidecar)

- macOS 카메라 권한 요청 + stdout에 JSON 1줄(`{"type":"hello"}`) 출력
- Swift 1파일 빌드

## Build
```bash
cd src-tauri/sidecar/HandDaemon
chmod +x build.sh
./build.sh
# 생성물: HandDaemon.app/Contents/MacOS/HandDaemon
