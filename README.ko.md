# Gotepad

[简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Gotepad는 바둑 기보 작성, 대국 검토 및 기보 정리를 위한 크로스 플랫폼 클라이언트입니다. 핵심 바둑판 및 기보 로직은 C++17로 구현되어 있으며, 클라이언트는 Godot 4.7.1(.NET 미사용)과 GDExtension으로 제작되었습니다. 현재 Windows x64와 Android 9 이상을 사용하는 arm64-v8a 가로 화면 기기에서 실행할 수 있습니다. Linux, macOS 및 iOS 지원은 추후 제공할 예정입니다.

이 프로젝트는 현재 개발 중입니다.

사용 방법은 [Gotepad 사용자 설명서](docs/user_manual.md)(현재 중국어)를 참조하세요.

## 릴리스 받기

미리 빌드된 버전은 이 저장소의 [GitHub Releases](../../releases) 페이지에 게시됩니다. 변경 사항은 [버전 기록](docs/version_log.md)을 참조하세요. 프로그램은 이 프로젝트의 릴리스 페이지 또는 신뢰할 수 있는 출처에서만 받으세요.

- Windows x64 버전은 설치가 필요 없는 단일 `Gotepad.exe` 파일로 제공됩니다. KataGo 분석 기능을 사용하려면 데스크톱용 KataGo 실행 파일, 모델 및 설정을 별도로 준비해야 합니다.
- Android 버전은 arm64-v8a APK로 제공되며 Android 9 이상을 지원합니다. 수동 설치 시 필요한 경우 시스템 안내에 따라 현재 출처의 앱 설치를 허용하세요.

## <u>이 프로젝트에 남겨진 몇 안 되는 사람의 말</u>

- 예전부터 만들고 싶었지만 만들지 못했던 것을 구현하도록 도와준 Codex에 감사드립니다.
- 이 프로그램은 바둑을 배우는 아이를 위해 부모가 만든 기보 노트 도구입니다. 정교한 공학이나 디자인보다는 개인 개발과 실제 사용의 편리함을 중심으로 만들었습니다.
- 앞으로의 모든 업데이트도 계속 오픈 소스와 무료로 제공됩니다. 필요에 맞는다면 안심하고 사용하세요.
- 프로젝트 빌드에 필요한 전용 파일은 모두 업로드되어 있습니다.
  - 각 서드 파티 라이브러리의 `third_party` 하위 디렉터리에는 버전과 배치 방법 등을 기록한 `gotepad_info.txt`가 있습니다.
  - AI를 이용한 자동 빌드를 권장합니다.
- **중요:** 기존 SGF 파일을 이 프로그램으로 편집할 때는 주의하고, 먼저 복사본을 만들어 두세요.
  - Gotepad는 SGF에 사용자 정의 속성을 기록하므로 다른 SGF 프로그램과의 호환성이 저하될 수 있습니다.
  - Gotepad는 SGF 규격의 일부만 지원하므로 지원하지 않는 속성이 사라질 수 있습니다.

## 주요 기능

- 완전한 바둑판 조작: 착수, 돌 따내기, 무르기, 배치 돌 설정 및 수정, 착수 색상 전환, 오조작 방지, 바둑판 조작 잠금을 지원합니다.
- 다중 분기 기보 관리: 기보 탐색, 선형 재생, 돌 찾기, 다음 수 분기의 순서 조정 및 삭제, 주 진행만 남기기, 축소 바둑판 트리로 전체 분기 탐색을 지원합니다.
- 변화도 검토: 임의의 국면에서 임시 변화도를 만들고 수순을 탐색하거나 되돌린 뒤, 검토 분기를 보존하거나 버릴 수 있습니다.
- SGF 읽기 및 쓰기: 로컬 파일, 시스템 클립보드 또는 운영 체제의 연결 프로그램 기능으로 기보를 불러올 수 있습니다. 대국 정보, 배치 노드, 분기, 국면 제목, 코멘트, 일반적인 바둑판 표식 및 Gotepad 사용자 정의 데이터를 지원하며, 비정상 SGF를 불러올 때 방어적 검사와 경고를 제공합니다.
- 기보 노트: 같은 국면에 여러 단계의 노트를 저장하고 순서 문자, 삼각형, 사각형, 원, X 표식을 추가할 수 있습니다. 읽기용과 출판용으로 서로 다른 수 번호 표시 방식을 설정할 수 있습니다. ‘집중’ 모드에서는 출판 내보내기 순서대로 모든 노트를 선형 탐색하며 바로 편집할 수 있습니다.
- 이미지에서 국면 만들기: Windows에서는 로컬 이미지를 선택하고 Android에서는 촬영하거나 앨범에서 이미지를 선택할 수 있습니다. OpenCV가 바둑판과 흑백 돌을 인식한 뒤 이미지 회전, 네 모서리 보정, 재인식 및 교차점별 수동 보정을 제공합니다.
- KataGo 분석: 단일 국면 및 연속 분석, 후보 수와 변화도, 추가 바둑판 후보 수, 승률 및 집 차이 곡선, 빠른 전체 기보 분석, 탐색량 증가, 실제 착수의 손실 경고를 지원합니다. Windows는 사용자가 배치한 외부 엔진을 사용하고, Android는 OpenCL/Eigen 백엔드와 모델을 내장하며 외부 모델도 불러올 수 있습니다.
- KataGo 인간 모방 대국: AI의 흑·백 선택, 현대 또는 AlphaGo 이전 기풍, 모방 기력, 수당 탐색량을 지정하고 현재 기보의 임의 국면에서 대국을 시작할 수 있습니다. 임시 대국은 무르기를 지원하며 원래 기보에 보존하거나 버릴 수 있습니다.
- 종국 계가: 중국식 규칙에서 KataGo로 각 교차점의 소유권을 판단하고 연결된 영역 단위로 결과를 직접 수정할 수 있습니다. 양쪽의 돌과 집, 덤, 최종 승패 차이를 보고합니다.
- PPTX 출판 내보내기: 선택한 바둑판, 수 번호, 표식, 노트를 편집 가능한 B5 가로형 교재로 배치합니다. 바둑판 이미지는 SVG 벡터 또는 호환성을 높인 PNG를 선택할 수 있으며 Android는 현재 SVG만 지원합니다.
- 다중 문서 및 사용자 지정 UI: 탭, 새로 만들기, 저장, 다른 이름으로 저장, 텍스처 전환, 수 번호 표시, 착수 음량, 바둑판 너비, UI 배율, 모바일 안전 여백 등의 설정을 제공합니다.
- 크로스 플랫폼 조작: Windows x64와 Android arm64-v8a를 지원합니다. Android에서는 터치 확대 및 이동, 큰 UI, 가로 화면 방향 전환, 시스템 파일 관리자에서 SGF 열기를 지원합니다.
- 중국어, 일본어, 한국어, 영어 UI를 제공합니다.
- SGF 저장 시 임시 백업을 사용하여 덮어쓰기 실패로 원본 파일이 손상될 위험을 줄입니다.

## 인터페이스 미리 보기

### 기보 노트와 바둑판 표식

같은 국면에 여러 단계의 노트를 기록하고 바둑판에 순서 문자, 삼각형, 사각형, 원, X 등의 표식을 추가할 수 있습니다.

![기보 노트와 바둑판 표식](examples/screenshots/notes.jpg)

### KataGo 국면 분석

분석 패널에는 후보 수, 승률, 집 차이, 후보 변화도를 표시하고 전체 기보 경로의 분석 곡선을 그릴 수 있습니다.

![KataGo 국면 분석](examples/screenshots/analysing.jpg)

### KataGo 인간 모방 대국

인간 모방 대국 전용 모델을 불러와 비슷한 수준의 AI와 대국할 수 있습니다.

![KataGo 인간 모방 대국](examples/screenshots/playwithai.jpg)

### 종국 계가

KataGo 소유권 분석과 중국식 규칙으로 종국 국면을 계가합니다.

![종국 계가](examples/screenshots/counting.jpg)

### 사진 및 이미지 인식

이미지 또는 사진에서 국면을 만듭니다.

![사진 및 이미지 인식](examples/screenshots/recognition.jpg)

### PPTX 교재 내보내기

바둑판, 수 번호, 표식, 노트를 배치하여 편집 가능한 PPTX 바둑 교재로 내보낼 수 있습니다.

![PPTX 바둑 교재 내보내기](examples/screenshots/courseware.png)

### 다국어 UI

![다국어 UI](examples/screenshots/multi-language.jpg)

## 프로젝트 구조

```text
src/          C++ 핵심 엔진, GoNotes 데이터 계층 및 Godot GDExtension
gotepad-gd/   Godot 클라이언트 프로젝트, 장면, 스크립트 및 그래픽 리소스
tests/        C++ 테스트 및 테스트 기보
third_party/  서드 파티 의존성 디렉터리 및 버전 안내
docs/         프로젝트 문서
```

나중에 다른 데스크톱 또는 모바일 인터페이스를 추가할 수 있도록 핵심 코드는 특정 GUI 기술과 최대한 분리되어 있습니다. 현재 Windows와 Android 클라이언트를 중점적으로 유지 관리하며 Linux, macOS 및 iOS는 향후 지원 대상입니다.

## 빌드 환경

- CMake 3.20 이상
- C++17 호환 컴파일러
- `godot-cpp` 바인딩 생성용 Python 3
- Godot 4.7.1 비 .NET 버전
- Godot 4.7 API와 일치하는 `godot-cpp`

프로젝트는 다음 서드 파티 라이브러리를 사용합니다.

- [godot-cpp](https://github.com/godotengine/godot-cpp): Godot GDExtension용 C++ 바인딩.
- [libsgfc++](https://github.com/herzbube/libsgfcplusplus): SGF 읽기, 검증 및 저장.
- [miniz](https://github.com/richgel999/miniz): PPTX 내보내기에 필요한 ZIP 압축 지원.
- [LunaSVG](https://github.com/sammycage/lunasvg): PPTX 안의 바둑판 SVG를 호환성이 높은 PNG로 변환합니다.
- [Noto CJK](https://github.com/notofonts/noto-cjk): PPTX 중국어 조판에 사용되는 고딕 및 명조 계열 글꼴. 글꼴 파일은 OFL-1.1에 따라 제공됩니다.
- [KataGo](https://github.com/lightvector/KataGo): 바둑 국면 분석 엔진. 데스크톱 버전은 외부 프로세스를 사용하며 Android 버전은 내장 분석 백엔드로 컴파일합니다.
- [Eigen](https://gitlab.com/libeigen/eigen): Android 내장 KataGo의 CPU 백엔드.
- [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers): Android 내장 KataGo OpenCL 백엔드의 컴파일 의존성.

서드 파티 소스 코드는 이 저장소에 포함되지 않습니다. 각 디렉터리의 `gotepad_info.txt`에 따라 지정 버전을 구한 뒤 해당 `third_party` 하위 디렉터리에 배치하세요. PPTX용 글꼴은 `third_party/fonts/noto-cjk`에 있습니다. 내보낸 파일에는 글꼴이 포함되지 않으므로 레이아웃을 유지해야 하는 사용자는 시스템에 해당 글꼴을 설치해야 합니다. 전체 글꼴 라이선스는 같은 디렉터리의 `OFL.txt`에서 확인할 수 있습니다.

의존성을 준비한 뒤 CMake로 Godot 확장을 빌드할 수 있습니다.

```sh
cmake -S . -B build -DGODOTCPP_TARGET=template_debug
cmake --build build --target go_gdext
```

확장은 `gotepad-gd/bin`에 출력됩니다. Godot 4.7.1로 `gotepad-gd/project.godot`을 열어 개발을 계속하거나 클라이언트를 실행할 수 있습니다.

### Android 빌드

Android 버전은 현재 `arm64-v8a`만 빌드하며 Android 9(API 28) 이상이 필요하고 가로 화면을 기준으로 설계되어 있습니다. 빌드 환경에는 다음 항목도 필요합니다.

- JDK 17
- Android SDK
- Android NDK r28
- 위 환경을 가리키는 `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_NDK_HOME` 환경 변수

`third_party/katago`의 안내에 따라 KataGo, Eigen 및 OpenCL Headers 소스를 준비하고 `gotepad-gd/assets/katago`에 Git LFS로 관리되는 모델을 준비한 뒤, Android NDK로 Android GDExtension, 내장 Eigen 백엔드 및 격리 실행되는 OpenCL 백엔드를 교차 컴파일하고 Godot의 Android 사용자 지정 빌드 템플릿으로 APK를 내보냅니다. 현재 내장 모델은 `g170e-b10c128-s1141046784-d204142634`이며 KataGo g170 확장 학습의 10 block / 128 channel 네트워크입니다. g170 학습에 연산 자원과 데이터를 기여하고 관련 모델 데이터를 CC0에 따라 퍼블릭 도메인으로 공개한 Jane Street와 KataGo 개발자 David J. Wu(lightvector), 그리고 다운로드 미러를 제공한 pachi 프로젝트에 감사드립니다. Android는 기기가 제공하는 OpenCL GPU 구현을 먼저 시도하고 OpenCL을 사용할 수 없거나 초기화에 실패하거나 분석 서비스가 비정상 종료되면 Eigen CPU 백엔드로 자동 전환합니다. APK에는 기기 제조사의 OpenCL 드라이버가 포함되지 않습니다.

정식 APK는 직접 만들고 장기간 안전하게 보관한 release keystore로 서명해야 합니다. 서명 키를 잃어버리면 같은 앱으로 사용자에게 덮어쓰기 업데이트를 제공할 수 없습니다. 키나 비밀번호를 저장소에 커밋하지 마세요. JDK 17의 `keytool`로 대화형 키를 만들 수 있습니다.

```powershell
keytool -genkeypair -v -keystore gotepad-release.jks -alias gotepad -keyalg RSA -keysize 4096 -validity 10000
```

생성한 키는 저장소 밖에 보관하고 안전한 백업을 만드세요. 로컬 Godot Android Release 내보내기 프리셋에 keystore 경로, alias 및 비밀번호를 설정하세요. 서명 경로나 인증 정보가 들어 있는 로컬 내보내기 설정을 공개하지 마세요.

### 플랫폼별 차이

- Windows 버전에서는 설정 패널에서 로컬 KataGo 실행 파일, 모델 및 설정을 선택합니다. Android 버전은 내장 백엔드와 내부 설정을 사용하므로 실행 파일 또는 설정 파일을 선택할 필요가 없습니다. 또한 시스템 파일 선택기에서 표준 `.bin.gz` 또는 `.txt.gz` 외부 분석 모델을 불러오고 언제든 내장 모델로 돌아갈 수 있습니다. 인간 모방 대국은 별도의 Human SL 모델과 독립적인 자동 성능 테스트 결과를 사용하므로 일반 분석 모델의 성능 설정을 그대로 재사용할 수 없습니다.
- Android 버전에서는 앱 안의 시스템 파일 선택기로 SGF를 불러오거나 시스템 클립보드의 완전한 SGF 텍스트를 붙여 넣을 수 있으며, 파일 관리자 또는 시스템 연결 프로그램을 지원하는 다른 앱에서 Gotepad로 SGF를 직접 열 수도 있습니다.
- Android 버전의 PPTX 내보내기는 SVG 바둑판 이미지만 지원하며 PNG 모드는 현재 사용할 수 없습니다. SVG 버전은 Microsoft 공식 PowerPoint 앱으로 열고 편집할 수 있습니다. WPS 등 일부 호환 프로그램에서는 포함된 SVG 이미지가 표시되지 않을 수 있습니다.
- OpenCL 백엔드는 처음 실행할 때 현재 GPU에 맞게 조정해야 하므로 이후 실행보다 시작 시간이 눈에 띄게 길 수 있습니다. 연속 분석은 전력 소비와 발열을 증가시킵니다.

## 라이선스

이 프로젝트는 [MIT License](LICENSE)에 따라 제공됩니다. 서드 파티 프로젝트에는 각각의 라이선스가 계속 적용됩니다.
