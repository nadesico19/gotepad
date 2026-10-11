# Gotepad：从 Git 仓库建立 iOS 真机构建与安装环境

本文供新 Mac 上的 GPT/开发者执行，目标是在只有本仓库 Git 跟踪文件的条件下，准备依赖、编译 Godot GDExtension、导出 Xcode 项目、开发签名，并安装到 iPhone 或 iPad。本文记录日期为 2026-10-11。命令默认从项目根目录执行，适用于真机 arm64 开发包；不是模拟器、App Store 或 TestFlight 发布流程。

## 1. 执行约定与仓库完整性

先阅读项目根目录的 `AGENTS.md`。依赖下载、生成脚本、日志和构建目录放在项目 `.tmp/` 内；第三方源码最终放到 CMake 指定的 `third_party/` 路径。保留已有修改和依赖缓存，不删除用户文件，不批量还原仓库，不把账号口令、签名私钥、描述文件或本地构建产物提交到 Git。

用户授权“搭建、构建并安装”后可以连续完成这些步骤；Apple 账号登录、验证码、协议接受、开发者模式确认、钥匙串授权等需要本人操作的步骤，应给出具体操作位置并等待完成，不猜测密码或代替用户作出法律协议决定。

只信任当前检出的源码、`CMakeLists.txt`、`cmake/katago_ios_metal.cmake` 和第三方目录内的 `gotepad_info.txt`。不要假定原开发机的 `.tmp`、`build_ios_debug.sh`、证书、工具或第三方源码会出现在新机器上。

```bash
git status --short
git rev-parse HEAD
git ls-files CMakeLists.txt cmake gotepad-gd/export_presets.cfg gotepad-gd/go_gdext.gdextension
git ls-files build_ios_debug.sh gotepad-gd/ios src/ios_model_file_picker.mm src/ios_sgf_file_bridge.mm src/ios_sgf_open_receiver.mm
mkdir -p .tmp/ios-bootstrap .tmp/ios
```

截至本文编写时，`build_ios_debug.sh` 是未跟踪的本地便捷脚本，不能作为新机器必需的输入。本文后面提供独立构建命令。第三方库的源码也不随 Git 发布，Git 中只有获取说明和 KataGo 补丁。

还有一个需要区分的状态：本机工作目录已经包含 SGF 打开接收、图片识别等后续开发修改，其中 `src/ios_sgf_file_bridge.hpp/.mm`、`src/ios_sgf_import.hpp`、`src/ios_sgf_open_receiver.mm`、`gotepad-gd/script/ios_sgf_picker.gd/.uid`、`gotepad-gd/ios/plugins/sgf_receiver/sgf_receiver.gdip` 在本次检查时尚未被跟踪。本机修改后的 CMake/导出配置可能引用这些文件，但此前已提交的版本没有这些引用。新机器必须以实际提交版本为准：若 CMake 或脚本引用的项目源码缺失，这属于提交不完整，不能靠安装 SDK 解决。应报告具体缺失文件，请维护者补齐项目源码；不能编造实现、静默删除功能或称“已还原本机最新版本”。编译已完整提交的较早版本则不要求这些尚未发布的功能文件。

可用以下命令辅助定位，注意 `git ls-files` 只表示文件被跟踪，不表示本机未提交修改已经上传：

```bash
rg -n 'src/ios_|ios/plugins|plugins/' CMakeLists.txt gotepad-gd/export_presets.cfg
rg -n 'ios_sgf|IOSSGF' gotepad-gd/script src/go_gdext.cpp
```

## 2. 已验证的技术组合

| 项目 | 当前参考值 |
|---|---|
| 开发机 | Apple Silicon Mac；Intel Mac 需要分别生成 x86_64 的宿主扩展和 arm64 的 iOS 扩展 |
| Godot | 4.7.1 stable，标准版，非 .NET |
| godot-cpp | `ba0edfed90512ec64aba51d4295a3e7e30112f86`，Godot API 4.7 |
| Xcode | 本机已成功使用 Xcode 27.0、iOS 27.0 SDK |
| iOS 最低版本 | 16.0，与导出预设和 Swift target 保持一致 |
| 真机架构 | arm64 |
| 原生构建 | CMake + Ninja，C++17、Objective-C++、Swift C++ interoperability |
| KataGo | v1.17.1 源码 + 仓库嵌入式补丁 |
| 推理后端 | Metal GPU / MPSGraph；此构建不提供 ANE 转换或 iOS Eigen 自动回退 |
| 签名 | Apple Development + Automatic Signing |

这是一组已使用的版本，不意味着任意旧 Xcode 都兼容。新设备系统必须受到所用 Xcode 支持，Godot 程序、导出模板与 C++ API 必须匹配。不要不经检查替换为 Godot 或依赖的最新版本。

## 3. 安装完整 Xcode 与命令行工具

从 Mac App Store 或 [Apple 官方下载](https://developer.apple.com/download/all/)安装适合当前 macOS 和设备系统的完整 Xcode。只有 Command Line Tools 不够；它缺少完整 iOS SDK、平台组件与设备部署能力。首次打开 Xcode，由用户阅读并接受协议，完成必要组件安装，并在 Xcode Settings 的 Components/Platforms 中确认 iOS 平台支持已安装。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-path
xcrun --find swiftc
xcrun --find devicectl
/usr/bin/python3 --version
```

如果 Xcode 装在其他位置，把 `DEVELOPER_DIR` 改为实际路径。后续所有 shell 都要设置它，避免 `xcode-select` 仍指向 `/Library/Developer/CommandLineTools`。如果首次组件设置尚未完成，让用户完成 Xcode 首次启动；不要把“许可未接受”当作编译错误。

安装 [Homebrew](https://brew.sh/) 后准备工具：

```bash
brew install cmake ninja git git-lfs
cmake --version
ninja --version
git lfs version
```

Apple Silicon 的 Homebrew 通常在 `/opt/homebrew/bin`，Intel 通常在 `/usr/local/bin`；确保当前 shell 的 PATH 含实际路径。签名所需的系统密码由用户在系统提示中输入。

## 4. 获取 Git LFS 实际资源

`.gitattributes` 将图片、SVG、音频、字体、模型等交由 Git LFS。Git 中保存指针是正常的，但工作目录必须有实际资源，不能把图片、模型统一替换成指针来获得“干净”状态。

```bash
git lfs install
git lfs pull
git lfs status
```

先确认 `git status` 中是否有用户对资源的真实修改，再执行下载；不要强行覆盖这些修改。下载失败时修复网络或 Git LFS 访问，而不是继续用指针文件导入 Godot。检查关键模型和字体：

```bash
shasum -a 256 gotepad-gd/assets/katago/g170e-b10c128-s1141046784-d204142634.kgmodel
wc -c gotepad-gd/assets/katago/g170e-b10c128-s1141046784-d204142634.kgmodel gotepad-gd/assets/fonts/NotoSansCJKsc-Regular.otf
```

内置 10b 模型应为 11,138,361 字节，SHA-256 为 `1a8e05a4ea3fca20dab79410cbb566c760767fcdd2fa0b701cfe259a84cc8b04`。若内容以 `version https://git-lfs.github.com/spec/v1` 开头、长度只有约百余字节，说明尚未展开。

## 5. 下载第三方源码

先读取各目录内 Git 跟踪的 `gotepad_info.txt`，如其中版本已更新，以当前仓库要求为准。参考版本如下：

| 依赖 | 获取源与固定版本 | 最终目录 |
|---|---|---|
| godot-cpp | `https://github.com/godotengine/godot-cpp.git`，提交 `ba0edfed90512ec64aba51d4295a3e7e30112f86` | `third_party/godot-cpp` |
| libsgfcplusplus | `https://github.com/herzbube/libsgfcplusplus.git`，提交 `e10f3f23db5b7a286146c2eeff348da249114ccd`，递归子模块 | `third_party/libsgfcplusplus` |
| miniz | `https://github.com/richgel999/miniz.git`，标签 `3.1.2` | `third_party/miniz` |
| LunaSVG | `https://github.com/sammycage/lunasvg.git`，提交 `83c58df8103dc7dca423dfd824992af94d49bed6`，递归子模块 | `third_party/lunasvg` |
| KataGo | 官方 v1.17.1 ZIP，按下一节校验和打补丁 | `third_party/katago/source/KataGo-1.17.1` |
| Eigen | 官方 3.4.0 ZIP | `third_party/katago/source/eigen-3.4.0` |
| OpenCV（条件依赖） | `https://github.com/opencv/opencv.git`，参考标签 `4.13.0` | `third_party/opencv` |

第三方目标目录初始就有 `gotepad_info.txt`，不能直接 `git clone ... third_party/godot-cpp`，否则会因非空目录失败。先下载到 `.tmp`，再复制源码，并保留仓库的元信息：

```bash
# 保存为 .tmp/ios-bootstrap/fetch-dependencies.sh 后，在项目根目录运行。
set -euo pipefail
fetch_dependency() {
    local dependency_name="$1"
    local repository_url="$2"
    local dependency_ref="$3"
    local destination_path="$4"
    local staging_path=".tmp/ios-bootstrap/$dependency_name"
    if [[ -e "$staging_path" ]]; then
        echo "已有缓存 $staging_path；核对其版本后复用，勿盲目重复执行。" >&2
        return 1
    fi
    git clone --no-checkout "$repository_url" "$staging_path"
    git -C "$staging_path" checkout --detach "$dependency_ref"
    git -C "$staging_path" submodule update --init --recursive
    mkdir -p "$destination_path"
    rsync -a --exclude='.git' --exclude='gotepad_info.txt' "$staging_path/" "$destination_path/"
}
fetch_dependency godot-cpp https://github.com/godotengine/godot-cpp.git ba0edfed90512ec64aba51d4295a3e7e30112f86 third_party/godot-cpp
fetch_dependency libsgfcplusplus https://github.com/herzbube/libsgfcplusplus.git e10f3f23db5b7a286146c2eeff348da249114ccd third_party/libsgfcplusplus
fetch_dependency miniz https://github.com/richgel999/miniz.git 3.1.2 third_party/miniz
fetch_dependency lunasvg https://github.com/sammycage/lunasvg.git 83c58df8103dc7dca423dfd824992af94d49bed6 third_party/lunasvg
```

本项目直接编译 miniz 源文件，不执行其上游 CMake，因此新机器还需生成静态构建用的 `miniz_export.h`。已有文件先检查，不覆盖不同实现：

```bash
if [[ ! -f third_party/miniz/miniz_export.h ]]; then
    cat > third_party/miniz/miniz_export.h <<'MINIZ_HEADER'
#pragma once
#ifndef MINIZ_EXPORT
#define MINIZ_EXPORT
#endif
MINIZ_HEADER
fi
```

确认 `third_party/libsgfcplusplus/sgfc` 和 `third_party/lunasvg/plutovg` 含源码。新机器无需 Android SDK、NDK、OpenCL Headers、QNN SDK、macOS KataGo 可执行程序或用户外部模型来构建 iOS Metal 版本。

如果当前 CMake 的 iOS 分支启用 OpenCV，使用同一 helper 获取 `opencv`，ref 为 `4.13.0`、目标为 `third_party/opencv`。此前已提交的 iOS CMake 未启用 OpenCV，不能仅因本机安装了它就把它当成所有版本的必要依赖。iOS 启用时 CMake 仅构建静态 `core,imgproc`，不要链接 Homebrew 的 macOS OpenCV 动态库。其他版本应先核对项目需求再替换。

## 6. KataGo 与 Eigen：校验、解压和补丁

以下参考 ZIP 与哈希已经核对；本次重新下载的 KataGo ZIP 与 `gotepad_info.txt` 一致，Metal C++/Swift 源码与本机版本一致。

```bash
set -euo pipefail
mkdir -p .tmp/ios-bootstrap/archives third_party/katago/source
curl -fL --retry 3 https://github.com/lightvector/KataGo/archive/refs/tags/v1.17.1.zip -o .tmp/ios-bootstrap/archives/KataGo-v1.17.1.zip
curl -fL --retry 3 https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.zip -o .tmp/ios-bootstrap/archives/eigen-3.4.0.zip
printf '%s\n' '5d2fe983a81b10d0cc577666bb484b51a7cbb2fc436d45bb42fffb418cd6f531  .tmp/ios-bootstrap/archives/KataGo-v1.17.1.zip' 'eba3f3d414d2f8cba2919c78ec6daab08fc71ba2ba4ae502b7e5d4d99fc02cda  .tmp/ios-bootstrap/archives/eigen-3.4.0.zip' | shasum -a 256 -c -
# 仅在目标源码目录不存在时解压；已有源码先核对补丁状态，不覆盖。
unzip -q .tmp/ios-bootstrap/archives/KataGo-v1.17.1.zip -d third_party/katago/source
unzip -q .tmp/ios-bootstrap/archives/eigen-3.4.0.zip -d third_party/katago/source
```

必须应用 Git 跟踪的嵌入式补丁，从项目根目录运行：

```bash
project_root="$PWD"
(
    cd third_party/katago/source/KataGo-1.17.1
    git apply --check "$project_root/third_party/katago/embedded-analysis-api.patch"
    git apply "$project_root/third_party/katago/embedded-analysis-api.patch"
)
rg -n 'analysisEmbedded' third_party/katago/source/KataGo-1.17.1/cpp/main.h
```

本次已确认该补丁能应用到指定的全新官方归档。重复执行前先用 `git apply --reverse --check` 判断补丁是否已经存在，不要反复打补丁。iOS 设置 `BUILD_ANDROID_KATAGO_OPENCL=OFF`，不要求 `o3-profile.patch`，也不需要恢复本机忽略目录内的 ONNX/QNN 或 Android O3 修改；这些修改不是官方依赖的下载步骤。不要把旧开发机未跟踪的 KataGo 源码作为唯一依据。

`cmake/katago_ios_metal.cmake` 会在构建目录生成 iOS Metal 适配文件，移除 macOS Core ML 模型转换器依赖，明确禁用 ANE 转换，并生成 Swift C++ 头文件。保留这套适配，不要额外引入 katagocoreml、protobuf、abseil 或手动复制旧的 `KataGoSwift-swift.h`。

## 7. Godot 程序和导出模板

从 [Godot 4.7.1 官方发布页](https://github.com/godotengine/godot-builds/releases/tag/4.7.1-stable) 下载标准 macOS universal 程序与同版本导出模板；确认实际发布资产名称后下载。参考命令如下，遇到 404 应检查发布页，不要替换为随机镜像或其他版本：

```bash
mkdir -p .tmp/tools/godot-4.7.1 .tmp/ios-bootstrap/godot
curl -fL --retry 3 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip -o .tmp/ios-bootstrap/godot/Godot.zip
curl -fL --retry 3 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz -o .tmp/ios-bootstrap/godot/templates.tpz
unzip -q .tmp/ios-bootstrap/godot/Godot.zip -d .tmp/tools/godot-4.7.1
unzip -q .tmp/ios-bootstrap/godot/templates.tpz -d .tmp/ios-bootstrap/godot/export
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
rsync -a .tmp/ios-bootstrap/godot/export/templates/ "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/"
export GODOT_PATH="$PWD/.tmp/tools/godot-4.7.1/Godot.app/Contents/MacOS/Godot"
"$GODOT_PATH" --version
ls "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/ios.zip"
```

也可使用 Godot 编辑器的 Export Template Manager 安装同版模板。Godot 的 [iOS 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)说明 iOS 导出需要 macOS、Xcode 和 iOS 模板。不要要求 C#/.NET 环境。

## 8. Apple 账号、开发签名与设备准备

用户在 Xcode → Settings → Accounts 登录自己的 Apple Account，选择自己的 Team。在 Manage Certificates 中确认存在带私钥的 Apple Development 证书；缺失时由用户创建。不要使用本文原开发机的 Team ID、证书指纹、设备 UDID 或从其他电脑复制私钥。

免费账号的 Personal Team 可以安装到自己的设备；按 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)，开发描述文件有效期为 7 天，到期需重新构建安装，且有 App ID、设备和应用数量限制。App Store/TestFlight 分发另需付费开发者计划，本文无需购买。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
security find-identity -v -p codesigning
xcrun devicectl list devices
xcrun xctrace list devices
```

连接 iPhone/iPad、解锁，在设备上确认信任这台 Mac；打开 Xcode → Window → Devices and Simulators，等待配对及设备支持准备完成。随后在设备“设置 → 隐私与安全性 → 开发者模式”开启，按提示重启，并在重启后确认启用。参考 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。账号登录、电脑配对与设备开发者模式是不同的准备步骤，不能互相代替。

将本机 Team ID 和目标真机标识放在当前 shell 环境，不写死在通用脚本中：

```bash
export TEAM_ID='替换为当前账号的Team ID'
export DEVICE_ID='替换为目标iPhone或iPad的设备标识'
```

同时连接多台设备时，必须确认目标型号/名称。不要沿用上次的设备 ID。`xcodebuild -showdestinations` 与 `devicectl list devices` 可辅助核对。

## 9. 调整导出预设的本机签名信息

检查 `gotepad-gd/export_presets.cfg` 中 `name="iOS Debug"` 对应的 options，而不是假定预设序号永远为 3：

- `application/app_store_team_id` 改为当前 Team ID；这是公开标识，不是密码，但不能使用原作者的 Team。
- 保持 `application/export_project_only=true`，后续由 Xcode 编译和签名。
- `application/min_ios_version="16.0"` 与 CMake 和 Swift deployment target 一致。
- 当前 `application/targeted_device_family=2` 在本机生成的 Xcode 项目中对应 `TARGETED_DEVICE_FAMILY="1,2"`，支持 iPhone 和 iPad，不要误读成只能用于 iPad。导出后仍需核对实际生成值。
- 默认 Bundle ID 为 `io.github.nadesico19.gotepad`；如果当前账号无法注册它，为本地测试选择自己可用的唯一 ID，并同步给导出、签名、安装核查与诊断命令。改变 ID 会安装成另一个应用，不能继续覆盖原应用及其数据。
- 版本号读取当前仓库预设。单纯本地调试不自动创建发行 Tag 或提高全局版本号；正式发布须遵守 `AGENTS.md` 的版本规则。

检查 `project.godot` 保留 `rendering_device/driver.ios="metal"`。这控制 Godot 渲染；KataGo 使用 Metal 则由 CMake 和运行时 `metalDeviceToUse=0` 控制，两者不是同一开关。

若当前提交启用了 `plugins/GotepadSGFReceiver=true`，必须同时有 Git 跟踪的接收器源码及 `.gdip` 描述文件。该插件静态 `.a` 由 CMake 生成到 `gotepad-gd/ios/plugins/sgf_receiver/`，不从原开发机复制。描述文件是项目配置，应由版本库提供；缺少时按第 1 节报告，不静默关闭插件。

## 10. 先构建 macOS 宿主扩展，再构建 iOS 扩展

新的 Git checkout 没有 `gotepad-gd/bin/`。Godot 在 Mac 上导入资源和解析脚本时需要 macOS 版 GDExtension；仅编译 iOS dylib 不够。先生成与本机 Godot 架构匹配的宿主库：

```bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
host_arch="$(uname -m)"
cmake -S . -B ".tmp/build-macos-$host_arch-debug" -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug -DCMAKE_OSX_ARCHITECTURES="$host_arch" \
    -DGODOTCPP_TARGET=template_debug -DGODOTCPP_API_VERSION=4.7 \
    -DBUILD_EMBEDDED_KATAGO=OFF -DBUILD_ANDROID_KATAGO_OPENCL=OFF \
    -DPython3_EXECUTABLE=/usr/bin/python3
cmake --build ".tmp/build-macos-$host_arch-debug" --target go_gdext --parallel 8
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
cmake -S . -B .tmp/build-ios-arm64-metal -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS "-DCMAKE_OSX_SYSROOT=$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo -DGODOTCPP_TARGET=template_debug \
    -DGODOTCPP_API_VERSION=4.7 -DBUILD_EMBEDDED_KATAGO=ON \
    -DBUILD_ANDROID_KATAGO_OPENCL=OFF -DPython3_EXECUTABLE=/usr/bin/python3
cmake --build .tmp/build-ios-arm64-metal --target go_gdext --parallel 8
ls gotepad-gd/bin/libgo_gdext.ios.template_debug.arm64.dylib
```

内存较小的 Mac 将并行数降到 2～4。只构建 `go_gdext`，无需构建或运行项目测试目标。宿主和 iOS 使用不同构建目录，不能混用旧平台的 CMakeCache。`go_gdext.gdextension` 必须与输出文件名一致；iOS 编译不是 macOS dylib 改名。

## 11. Godot 导入与导出 Xcode 项目

```bash
set -euo pipefail
mkdir -p .tmp/ios
"$GODOT_PATH" --headless --path gotepad-gd --import 2>&1 | tee .tmp/ios/import.log
"$GODOT_PATH" --headless --path gotepad-gd --export-debug 'iOS Debug' "$PWD/.tmp/ios/Gotepad.ipa" 2>&1 | tee .tmp/ios/export.log
```

Godot 导出使用绝对输出路径，避免路径相对于 `--path` 解析带来的歧义。预设开启 `export_project_only` 后，主要结果是 `.tmp/ios/Gotepad.xcodeproj` 和配套目录，不表示已经生成可安装的 IPA。

必须检查日志里的 `SCRIPT ERROR:` 和 `ERROR:`，不能只看退出码。原开发机遇到过退出阶段的单行 `ERROR: Plugin is not attached to debugger.`，该信息本身不能证明构建失败；只有核对没有其他脚本/资源/扩展错误，且后续 Xcode 构建成功，才能按这一已知信息处理。禁止忽略所有 ERROR。

```bash
ls .tmp/ios/Gotepad.xcodeproj/project.pbxproj
rg -n 'TARGETED_DEVICE_FAMILY|IPHONEOS_DEPLOYMENT_TARGET' .tmp/ios/Gotepad.xcodeproj/project.pbxproj
```

## 12. Xcode 构建、签名并安装

```bash
set -euo pipefail
: "${TEAM_ID:?请先设置本机Team ID}"
: "${DEVICE_ID:?请先设置目标设备标识}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project .tmp/ios/Gotepad.xcodeproj -scheme Gotepad \
    -configuration Debug -sdk iphoneos -destination "id=$DEVICE_ID" \
    -derivedDataPath "$PWD/.tmp/ios/DerivedData" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "DEVELOPMENT_TEAM=$TEAM_ID" CODE_SIGN_STYLE=Automatic build \
    2>&1 | tee .tmp/ios/xcodebuild.log
app_path="$PWD/.tmp/ios/DerivedData/Build/Products/Debug-iphoneos/Gotepad.app"
codesign --verify --deep --strict "$app_path"
xcrun devicectl device install app --device "$DEVICE_ID" "$app_path" \
    2>&1 | tee .tmp/ios/install.log
```

没有连接目标设备时可先用 `-destination 'generic/platform=iOS'` 编译，但安装必须指定实际设备，且开发描述文件须包含它。需要再次安装到另一台设备时，先为新设备构建以完成注册/签名，再安装；不能保证原描述文件涵盖新设备。

签名等待钥匙串提示时，请用户在系统弹窗中输入 Mac 登录密码并允许访问对应 Apple Development 私钥。证书存在但不带私钥不构成有效签名身份。不要删除、吊销原证书来试错，也不要导出私钥到项目。

设备首次打开若提示“不受信任的开发者”，到“设置 → 通用 → VPN 与设备管理”找到对应开发者并信任；界面措辞可能随系统版本变化。保持联网以完成验证。不要重装应用来解决单纯的信任问题，更不要先卸载应用导致棋谱和设置丢失。

## 13. 结果验收与日志

完成时确认：原生扩展构建成功；Godot 导入和导出无实质错误；Xcode 输出 `BUILD SUCCEEDED`；`codesign --verify` 通过；`devicectl` 返回 `App installed` 与正确 Bundle ID。报告实际设备、Bundle ID、构建产物位置和未完成的真机测试，不能把“已安装”说成“所有功能已测试通过”。

由用户或明确授权的测试过程检查：应用启动、横屏布局、内置 10b 普通分析、终局数目、正确类型的外部模型导入、普通/Human SL 性能检测，以及进入后台后的停止行为。如果当前提交包含 SGF 文档接收或图片识别，再检查对应功能。Human SL 与普通分析模型不可混用，文件名不决定模型类型。

本机成功运行过 iPad mini 6 与 iPad Pro 11 英寸 M5；导出目标覆盖 iPhone，但本文不宣称已在所有 iPhone 上完成实机验证。

需要启动日志时，先查看当前 Xcode 的命令帮助，再选择其支持的选项：

```bash
xcrun devicectl device process launch --help
xcrun devicectl device info files --help
xcrun devicectl device copy from --help
```

应用数据可通过 `appDataContainer` 与当前 Bundle ID 读取；崩溃日志使用 `systemCrashLogs`。复制到项目 `.tmp/` 保存分析。分析崩溃时用此次构建的 dylib/dSYM UUID 对应符号化，不能使用另一轮构建的符号。`EXC_CRASH/SIGABRT`、`std::terminate` 和 Jetsam 内存终止需分别分析，不要见到闪退就认定内存不足。

## 14. 常见故障与处理顺序

| 现象 | 检查与处理 |
|---|---|
| `xcodebuild` 要求完整 Xcode、找不到 iphoneos SDK | 核对完整安装、iOS 组件和 `DEVELOPER_DIR` |
| `add_subdirectory` 找不到第三方 CMakeLists | 补齐指定版本源码和子模块；目标路径不能多嵌套一层 |
| 缺失 `src/ios_*.mm`、`.gdip` 或项目脚本 | 核对 Git 提交完整性；这些不是可从第三方库下载的文件 |
| Godot 无法解码 PNG/字体/模型 | 检查 LFS 是否仍为指针；下载真实资源 |
| Godot Mac 导入找不到扩展 | 先构建与宿主架构一致的 macOS debug 扩展，核对 `.gdextension` 路径 |
| 找不到 iOS export template | 同版模板目录应含 `ios.zip`；不要只安装 macOS 模板 |
| Swift 头文件缺失、错误 target、符号链接失败 | 使用完整 Xcode 的 Swift，Ninja，iphoneos SDK；保留 iOS target triple 和 Swift interoperability 配置 |
| Core ML converter/katagocoreml 缺失 | 检查是否使用仓库的 iOS Metal 适配；不要按 macOS 上游方案安装一套转换器 |
| iOS 适配提示 converter markers changed | 检查 KataGo 源码是否为指定版本；升级须审核适配逻辑 |
| 签名显示 0 valid identities | Xcode 登录账号，确认 Apple Development 证书和私钥、钥匙串及中间证书链 |
| `unable to build chain to self-signed root` | 从 [Apple PKI](https://www.apple.com/certificateauthority/)核对匹配的 WWDR 中间证书；本机曾需 WWDR G3，不应对所有机器盲装或把证书设为 Always Trust |
| `No profiles` / Bundle ID 不可注册 | 当前 Team、网络、设备注册、自动签名、账号额度和唯一 Bundle ID |
| 设备不可用/开发者模式关闭 | 解锁、信任、完成配对，开启模式并重启确认，检查 Xcode 支持设备系统 |
| 包装好但不能安装/覆盖 | 设备是否在描述文件中、签名 Team 和 Bundle ID 是否一致；不要先卸载 |
| 免费签名过期 | 使用同一 Team 和 Bundle ID 重新构建安装 |

## 15. 后续维护

可将第 10～12 节封装为 `.tmp/ios-bootstrap/build-and-install.sh`，输入通过 `DEVELOPER_DIR`、`GODOT_PATH`、`TEAM_ID`、`DEVICE_ID` 和并行数传递。除非用户要求提交该脚本，否则它仍只是本机生成文件。即使以后版本库加入正式构建脚本，也应保留版本匹配、LFS、依赖获取、宿主扩展、证书和设备检查。

这份文档提供从已提交完整版本重建环境的方法，不会自动使未跟踪的功能源码出现在 GitHub。维护者发布新的 iOS 功能时，应一并提交所需项目源码、插件描述、CMake 和导出配置；二进制、依赖源码、缓存和签名凭据继续由新机器自行下载或生成。
