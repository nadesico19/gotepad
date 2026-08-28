# Gotepad

Gotepad 是一个面向围棋记谱、棋局检讨和棋谱整理的跨平台客户端项目。核心棋盘与棋谱逻辑使用 C++17 实现，客户端使用 Godot 4.7.1（非 .NET 版本）和 GDExtension 构建。目前可运行于 Windows x64，以及 Android 9 或更高版本的 arm64-v8a 横屏设备；Linux、macOS 和 iOS 尚处于计划适配阶段。

项目目前仍处于开发阶段。

使用方法请参阅 [Gotepad 用户手册](docs/user_manual.md)。

## 获取发行版

预编译版本将发布在本仓库的 [GitHub Releases](../../releases) 页面，版本变化参见 [更新记录](docs/version_log.md)。请只从本项目发布页或可信来源获取程序。

- Windows x64 版以单文件 `Gotepad.exe` 提供，无需安装；KataGo 分析功能需要用户另外部署桌面版 KataGo、模型和配置。
- Android 版以 arm64-v8a APK 提供，支持 Android 9 及更高版本；手动安装时可能需要按系统提示允许从当前来源安装应用。

## <u>本项目中为数不多来自人类的话语</u>

- 感谢 codex ，帮我实现了过去想做而没能做的事。
- 这是一个棋童家长为自家小孩学棋做的笔记工具，一切都围绕个人开发和使用上的便利性，没有太考究的工程和设计要素。
- 软件未来所有更新内容都会永久开源和免费，如有需要请放心使用。
- 项目编译所必要的本项目专属文件均已上传。
  - 第三方库均在 third_party 中对应的子目录下放置了 gotepad_info.txt ，记录了版本和部署方法等信息。
  - 推荐使用 AI 自动进行构建。
- 【重要提醒】请谨慎使用本软件编辑您既有的SGF文件资产，如需编辑请先创建副本。
  - 软件会在 SGF 中创建自定义属性，可能会破坏文件与其他 SGF 软件的兼容性；
  - 软件仅支持 SGF 规范的子集，可能会丢弃文件中不支持的属性。

## 主要功能

- 完整的围棋棋盘操作：支持落子、提子、悔棋、预置及修改预置棋子、落子颜色切换、落子防误触和棋盘操作锁定。
- 多分支棋谱管理：支持棋局漫游、线性播放、查找棋子、调整或删除下一手分支、保留主干，以及以缩略图树可视化浏览整局分支。
- 变化图推演：可从任意局面建立临时变化图，浏览、回退并选择保留或放弃推演分支。
- SGF 棋谱读写：可以从本地文件、系统剪贴板或系统“打开方式”载入棋谱，支持棋谱信息、预置节点、分支、局面标题、评论、常用棋盘标记和 Gotepad 自定义数据，并在加载异常棋谱时提供防御性校验与提示。
- 棋局笔记：同一局面可保存多层笔记，支持顺序字母、三角、方形、圆形和叉形标记，并可为阅读及出版设置不同的棋子编号方式；“专注”模式可以按照出版导出的顺序线性浏览整份棋谱的全部笔记，并在浏览过程中直接编辑。
- 从图片创建棋局：Windows 可选择本地图片，Android 可拍照或从相册选图；程序通过 OpenCV 识别棋盘和黑白棋子，并提供旋转、四角校正、重新识别和逐点人工修正。
- KataGo 分析：支持单局面及持续分析、候选点与变化图、胜率和目差曲线、快速整局分析、增加计算量和候选劣化提示。Windows 调用用户部署的外部引擎，Android 内置 OpenCL/Eigen 后端和模型，并允许导入外置权重。
- KataGo 人类模仿棋：可以选择 AI 执黑或执白、现代或 AlphaGo 前棋风、模仿棋力及每手计算量，并从当前棋谱的任意局面开始对局；临时对局可以悔棋，并可选择保留到原棋谱或放弃。
- 终局数目：在中国规则下调用 KataGo 判断交叉点归属，允许用户按连通区域修正结果，并汇报双方子空、贴目和胜负目数。
- PPTX 出版导出：将筛选出的棋盘、编号、标记和笔记排版为可继续编辑的 B5 横版课件，并可选择 SVG 矢量棋盘或兼容性更好的 PNG 棋盘（Android 目前仅支持 SVG）。
- 多文档与个性化界面：提供多标签、新建、保存、另存、纹理切换、手数显示、落子音量、棋盘宽度、界面缩放及移动端安全边距等设置。
- 跨平台交互：支持 Windows x64 和 Android arm64-v8a；Android 提供触控缩放与拖动、大尺寸界面、横屏方向跟随，以及从系统文件管理器打开 SGF。
- 提供中文、日本語、한국어和 English 四种界面语言。
- 保存 SGF 时采用临时副本保护，降低覆盖写入过程中原文件损坏的风险。

## 界面预览

### 棋局笔记与棋盘标记

同一局面可以记录多层笔记，并在棋盘上添加顺序字母、三角、方形、圆形和叉形等标记。

![棋局笔记与棋盘标记](examples/screenshots/notes.jpg)

### KataGo 局面分析

分析面板可以显示候选点、胜率、目差和候选变化图，并绘制整条棋局路径的分析曲线。

![KataGo 局面分析](examples/screenshots/analysing.jpg)

### KataGo 人类模仿棋

加载人类模仿棋专用模型，可以和水平相当的 AI 进行对局。

![KataGo 人类模仿棋](examples/screenshots/playwithai.jpg)

### 终局数目

利用 Katago 进行归属判定，使用中国规则进行数目。

![终局数目](examples/screenshots/counting.jpg)

### 拍照识图

从图片或拍照创建棋局。

![拍照识图](examples/screenshots/recognition.jpg)

### PPTX 课件导出

棋盘、编号、标记和笔记可以排版导出为可继续编辑的 PPTX 围棋课件。

![PPTX 围棋课件导出效果](examples/screenshots/courseware.png)

### UI 多语言

![UI 多语言](examples/screenshots/multi-language.jpg)

## 项目结构

```text
src/          C++ 核心引擎、GoNotes 数据层及 Godot GDExtension
gotepad-gd/   Godot 客户端工程、场景、脚本和美术资源
tests/        C++ 测试及测试棋谱
third_party/  第三方依赖的放置目录和版本说明
docs/         项目文档
```

核心代码尽量与具体 GUI 技术解耦，以便后续接入其他桌面端或移动端界面。当前重点维护 Windows 和 Android 客户端，Linux、macOS 和 iOS 为后续目标平台。

## 构建环境

- CMake 3.20 或更高版本
- 支持 C++17 的编译器
- Python 3（用于生成 `godot-cpp` 绑定代码）
- Godot 4.7.1 非 .NET 版本
- 与 Godot 4.7 API 匹配的 `godot-cpp`

项目依赖以下第三方库：

- [godot-cpp](https://github.com/godotengine/godot-cpp)：Godot GDExtension 的 C++ 绑定。
- [libsgfc++](https://github.com/herzbube/libsgfcplusplus)：SGF 的读取、校验和保存。
- [miniz](https://github.com/richgel999/miniz)：PPTX 导出所需的 ZIP 归档支持。
- [LunaSVG](https://github.com/sammycage/lunasvg)：将 PPTX 中的棋盘图转换为兼容性更好的 PNG。
- [Noto CJK](https://github.com/notofonts/noto-cjk)：PPTX 中文排版使用的黑体和宋体，字体文件按 OFL-1.1 随项目提供。
- [KataGo](https://github.com/lightvector/KataGo)：围棋局面分析引擎；桌面端使用外部程序，Android 端编译为内置分析后端。
- [Eigen](https://gitlab.com/libeigen/eigen)：Android 内置 KataGo 的 CPU 后端。
- [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers)：Android 内置 KataGo 的 OpenCL 后端编译依赖。

第三方库源码不随本项目仓库发布。请按照各目录中的 `gotepad_info.txt` 获取指定版本，并将源码放到对应的 `third_party` 子目录中。PPTX 所用字体位于 `third_party/fonts/noto-cjk`；导出文件不会嵌入字体，需要保持版式的用户应先在系统中安装这些字体。完整字体授权文本见该目录下的 `OFL.txt`。

准备好依赖后，可以使用 CMake 构建 Godot 扩展：

```sh
cmake -S . -B build -DGODOTCPP_TARGET=template_debug
cmake --build build --target go_gdext
```

扩展会输出到 `gotepad-gd/bin`。随后使用 Godot 4.7.1 打开 `gotepad-gd/project.godot` 即可继续开发或运行客户端。

### Android 构建

Android 版本目前只构建 `arm64-v8a`，最低支持 Android 9（API 28），并按横屏界面设计。构建环境还需要：

- JDK 17；
- Android SDK；
- Android NDK r28；
- 分别指向上述环境的 `JAVA_HOME`、`ANDROID_HOME` 和 `ANDROID_NDK_HOME` 环境变量。

准备好 `third_party/katago` 中说明的 KataGo、Eigen 和 OpenCL Headers 源码，以及 `gotepad-gd/assets/katago` 中由 Git LFS 管理的模型后，需要使用 Android NDK 交叉编译 Android GDExtension、内置 Eigen 后端和隔离运行的 OpenCL 后端，再通过 Godot 的 Android 自定义构建模板导出 APK。当前内置模型为 `g170e-b10c128-s1141046784-d204142634`，即 KataGo g170 扩展训练的 10 block / 128 channel 网络。感谢 Jane Street 与 KataGo 作者 David J. Wu（lightvector）为 g170 训练批次贡献算力和数据，并将相关模型数据按 CC0 贡献至公有领域；也感谢 pachi 项目提供该模型的下载镜像。Android 会优先尝试设备公开的 OpenCL GPU 实现，OpenCL 不可用、初始化失败或分析服务异常退出时自动回退到 Eigen CPU 后端；APK 本身不包含设备厂商的 OpenCL 驱动。

正式发布 APK 必须使用自行创建并长期妥善保存的 release keystore。签名密钥一旦遗失，就无法再以相同应用身份为用户提供覆盖升级；不要将密钥或密码提交到仓库。可使用 JDK 17 的 `keytool` 创建密钥，命令会交互询问密码和证书信息：

```powershell
keytool -genkeypair -v -keystore gotepad-release.jks -alias gotepad -keyalg RSA -keysize 4096 -validity 10000
```

请把生成的密钥保存在仓库以外并做好备份，在本地 Godot Android Release 导出预设中配置 keystore、alias 和密码。不要把包含签名路径或凭据的本地导出配置发布到仓库。

### 平台使用差异

- Windows 版的 KataGo 通过设置面板选择本地可执行文件、模型和配置；Android 版使用内置后端和内部配置，不需要选择可执行文件或配置，也可以通过系统文件选择器导入标准 `.bin.gz` 或 `.txt.gz` 外置分析模型，并随时切回内置模型。人类模仿棋另行使用 Human SL 模型，并使用独立的自动性能检测结果，不能直接复用普通分析模型的性能配置。
- Android 版既可以在程序内通过系统文件选择器加载 SGF，也可以粘贴系统剪贴板中的完整 SGF 文本，还可以从文件管理器或其他支持系统“打开方式”的应用直接使用 Gotepad 打开 SGF。
- Android 版导出 PPTX 时仅支持 SVG 棋盘图片；PNG 模式目前不可用。SVG 版可使用 Microsoft PowerPoint App 浏览和编辑，WPS 等兼容软件可能无法显示其中的 SVG 图片。
- OpenCL 后端首次运行需要针对当前 GPU 调优，启动时间可能明显长于后续运行；持续分析会增加耗电和发热。

## 许可证

本项目使用 [MIT License](LICENSE)。第三方项目仍遵循其各自的许可证。
