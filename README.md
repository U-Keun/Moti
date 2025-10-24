
## 개요
맥북 모션 제어 시스템: 카메라 기반 손 제스처로 화면 잠금 및 영역 캡처를 수행하는 메뉴바 앱. Tauri(Rust/Svelte) + Swift(Vision) 사이드카 아키텍처.

## 주요 기능
- 잠금(Bye) : 손바닥을 보이며 좌/우 흔들기 파형 검출 → 화면 잠금(⌃⌘Q)

https://github.com/user-attachments/assets/6e093e84-7196-4a66-ba05-a54dfa9a30a5

- 영역 캡처 (Frame) : 양손으로 만든 프레임을 감지 → 관심 영역 확정 → 해당 영역 캡처
개발 중
