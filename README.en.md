# Gotepad

[简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Gotepad is a cross-platform client for recording Go games, reviewing positions, and organizing game records. Its core board and game-record logic is implemented in C++17, while the client is built with Godot 4.7.1 (non-.NET) and GDExtension. It currently runs on Windows x64 and arm64-v8a Android devices running Android 9 or later in landscape orientation. Linux, macOS, and iOS support is planned.

The project is still under development.

For usage instructions, see the [Gotepad User Manual](docs/user_manual.md) (currently in Chinese).

## Getting a release

Prebuilt versions are published on the repository's [GitHub Releases](../../releases) page. See the [version history](docs/version_log.md) for changes. Download the application only from this project's release page or another trusted source.

- The Windows x64 edition is distributed as a single `Gotepad.exe` and requires no installation. KataGo analysis requires a separately deployed desktop KataGo executable, model, and configuration.
- The Android edition is distributed as an arm64-v8a APK and supports Android 9 or later. When installing it manually, follow the system prompt to allow installation from the current source if necessary.

## <u>A few words from the human behind this project</u>

- Thanks to Codex for helping me build something I had wanted to make but could not accomplish before.
- This is a note-taking tool made by the parent of a young Go player for their own child. Everything is centered on practical personal development and use rather than elaborate engineering or design.
- All future updates will remain open source and free. Please feel free to use the software if it meets your needs.
- All project-specific files required to build the project have been uploaded.
  - Each third-party library has a `gotepad_info.txt` file in its corresponding subdirectory under `third_party`, documenting its version and deployment procedure.
  - Using AI-assisted builds is recommended.
- **Important:** Use caution when editing existing SGF assets with this application, and create a backup copy first.
  - Gotepad writes custom properties to SGF files, which may reduce compatibility with other SGF applications.
  - Gotepad supports only a subset of the SGF specification, so unsupported properties may be discarded.

## Main features

- Full Go board interaction: play and capture stones, undo moves, place and edit setup stones, switch the move color, prevent accidental taps, and lock board operations.
- Multi-branch game-record management: navigate and play through a game, find stones, reorder or delete next-move branches, retain only the main line, and browse the complete variation tree as board thumbnails.
- Variation exploration: create a temporary variation from any position, browse or roll back its moves, and choose whether to keep or discard it.
- SGF reading and writing: load records from local files, the system clipboard, or the operating system's Open With action. Supports game metadata, setup nodes, branches, position titles, comments, common board marks, and Gotepad custom data, with defensive validation and warnings for malformed SGF files.
- Game notes: store multiple layers of notes for one position; add sequential letters, triangles, squares, circles, and crosses; and configure different move-numbering modes for reading and publication. Focus mode browses every note linearly in publication-export order and allows direct editing while browsing.
- Create positions from images: select a local image on Windows, or take a photo or choose one from the gallery on Android. OpenCV detects the board and black and white stones, after which users can rotate the image, correct its four corners, run recognition again, and manually correct individual intersections.
- KataGo analysis: single-position and continuous analysis, candidate moves and variations, additional board candidates, win-rate and score-lead curves, fast full-game analysis, increased search effort, and warnings for inferior played moves. Windows uses an externally deployed engine; Android includes OpenCL and Eigen backends and a built-in model, while also allowing an external model to be imported.
- KataGo human-like play: choose whether the AI plays Black or White, select a modern or pre-AlphaGo style, playing strength, and search effort per move, then start a game from any position in the current record. Temporary games support takeback and can either be retained in the original record or discarded.
- Final scoring: under Chinese rules, use KataGo to determine ownership at every intersection, manually correct connected ownership regions, and report stones plus territory, komi, and the final margin for both sides.
- PPTX publication export: lay out selected boards, move numbers, marks, and notes as an editable B5 landscape slide deck. Board images can be exported as SVG vectors or compatibility-oriented PNG files; Android currently supports SVG only.
- Multiple documents and a customizable interface: tabs, new, save, save as, texture selection, move-number display, stone-sound volume, board width, UI scaling, and mobile safe-margin settings.
- Cross-platform interaction: Windows x64 and Android arm64-v8a are supported. Android adds touch zoom and panning, a large-UI option, landscape-orientation following, and opening SGF files from the system file manager.
- Chinese, Japanese, Korean, and English interface languages.
- SGF saves use a temporary backup to reduce the risk of damaging the original file if an overwrite fails.

## Interface preview

### Game notes and board marks

Multiple layers of notes can be recorded for one position, with sequential letters, triangles, squares, circles, crosses, and other board marks.

![Game notes and board marks](examples/screenshots/notes.jpg)

### KataGo position analysis

The analysis panel displays candidate moves, win rate, score lead, candidate variations, and an analysis curve for the complete game path.

![KataGo position analysis](examples/screenshots/analysing.jpg)

### KataGo human-like play

Load a dedicated human-like-play model to play against an AI of a comparable level.

![KataGo human-like play](examples/screenshots/playwithai.jpg)

### Final scoring

Use KataGo ownership analysis and Chinese rules to score the final position.

![Final scoring](examples/screenshots/counting.jpg)

### Photo and image recognition

Create a position from an image or a photo.

![Photo and image recognition](examples/screenshots/recognition.jpg)

### PPTX courseware export

Boards, move numbers, marks, and notes can be laid out and exported as an editable PPTX Go lesson deck.

![PPTX Go courseware export](examples/screenshots/courseware.png)

### Multilingual UI

![Multilingual UI](examples/screenshots/multi-language.jpg)

## Project structure

```text
src/          C++ core engine, GoNotes data layer, and Godot GDExtension
gotepad-gd/   Godot client project, scenes, scripts, and art assets
tests/        C++ tests and test game records
third_party/  Third-party dependency directories and version notes
docs/         Project documentation
```

The core code is kept as independent as possible from a specific GUI technology so that other desktop and mobile front ends can be added later. Windows and Android are the currently maintained clients; Linux, macOS, and iOS are future targets.

## Build environment

- CMake 3.20 or later
- A C++17-compatible compiler
- Python 3, used to generate `godot-cpp` bindings
- Godot 4.7.1, non-.NET edition
- `godot-cpp` matching the Godot 4.7 API

The project depends on the following third-party libraries:

- [godot-cpp](https://github.com/godotengine/godot-cpp): C++ bindings for Godot GDExtension.
- [libsgfc++](https://github.com/herzbube/libsgfcplusplus): SGF reading, validation, and writing.
- [miniz](https://github.com/richgel999/miniz): ZIP archive support for PPTX export.
- [LunaSVG](https://github.com/sammycage/lunasvg): converts board SVGs in PPTX exports to compatibility-oriented PNG images.
- [Noto CJK](https://github.com/notofonts/noto-cjk): Gothic and serif CJK fonts used for Chinese PPTX layout. Font files are distributed under OFL-1.1.
- [KataGo](https://github.com/lightvector/KataGo): Go position analysis engine. The desktop edition runs an external process, while the Android edition compiles KataGo as built-in analysis backends.
- [Eigen](https://gitlab.com/libeigen/eigen): CPU backend for the embedded Android KataGo engine.
- [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers): compile-time dependency for the embedded Android KataGo OpenCL backend.

Third-party source code is not distributed in this repository. Follow the `gotepad_info.txt` file in each directory to obtain the specified version and place its source under the corresponding `third_party` subdirectory. PPTX fonts are located under `third_party/fonts/noto-cjk`. Exported files do not embed fonts, so users who need consistent layout should install these fonts on their systems. The complete font license is provided in `OFL.txt` in that directory.

After preparing the dependencies, build the Godot extension with CMake:

```sh
cmake -S . -B build -DGODOTCPP_TARGET=template_debug
cmake --build build --target go_gdext
```

The extension is written to `gotepad-gd/bin`. Open `gotepad-gd/project.godot` with Godot 4.7.1 to continue development or run the client.

### Android build

The Android edition currently targets only `arm64-v8a`, requires Android 9 (API 28) or later, and is designed for landscape orientation. The build environment also requires:

- JDK 17
- Android SDK
- Android NDK r28
- `JAVA_HOME`, `ANDROID_HOME`, and `ANDROID_NDK_HOME` environment variables pointing to those components

After preparing the KataGo, Eigen, and OpenCL Headers sources described under `third_party/katago`, and the Git LFS-managed model under `gotepad-gd/assets/katago`, use the Android NDK to cross-compile the Android GDExtension, embedded Eigen backend, and isolated OpenCL backend, then export the APK with Godot's custom Android build template. The current embedded model is `g170e-b10c128-s1141046784-d204142634`, a 10-block, 128-channel network from KataGo's extended g170 training run. We thank Jane Street and KataGo author David J. Wu (lightvector) for contributing compute and data to the g170 training run and releasing the resulting model data into the public domain under CC0, and the pachi project for providing a download mirror. Android first attempts to use an OpenCL GPU implementation exposed by the device and automatically falls back to the Eigen CPU backend if OpenCL is unavailable, initialization fails, or the analysis service terminates unexpectedly. The APK does not contain a device-vendor OpenCL driver.

A release APK must be signed with a release keystore that you create and retain securely. If the signing key is lost, future versions cannot be delivered to users as updates to the same application. Never commit the key or its password to the repository. A key can be created interactively with the JDK 17 `keytool`:

```powershell
keytool -genkeypair -v -keystore gotepad-release.jks -alias gotepad -keyalg RSA -keysize 4096 -validity 10000
```

Store the generated key outside the repository and keep a secure backup. Configure its keystore path, alias, and password in your local Godot Android Release export preset. Do not publish local export configuration containing signing paths or credentials.

### Platform differences

- On Windows, select a local KataGo executable, model, and configuration in Settings. Android uses built-in backends and an internal configuration, so no executable or configuration path is required. Android can also import a standard external `.bin.gz` or `.txt.gz` analysis model through the system file picker and switch back to the embedded model at any time. Human-like play uses a separate Human SL model and independent automatic performance-test results; it cannot directly reuse the performance configuration of the regular analysis model.
- On Android, SGF files can be loaded through the in-app system file picker, pasted as complete SGF text from the system clipboard, or opened directly from a file manager or another application that supports the system Open With action.
- Android PPTX export supports SVG board images only; PNG mode is currently unavailable. The SVG edition can be viewed and edited with the official Microsoft PowerPoint app. WPS and some other compatible applications may not display embedded SVG images.
- The first OpenCL backend run must tune itself for the current GPU and can take noticeably longer than subsequent runs. Continuous analysis increases power consumption and heat.

## License

This project is licensed under the [MIT License](LICENSE). Third-party projects remain subject to their respective licenses.
