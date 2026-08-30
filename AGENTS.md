## 编译构建

- 项目类型：围棋棋盘的客户端。
- 语言和标准：C++ 17。
- 构建系统：CMake。
  - Windows 11 开发机没有安装 WindowsApp 版 Python，需要使用  `py` 命令而非 `python` 启动解释器。
- 第三方库统一放在 third_party 文件夹下。在库专属的子目录内，使用 gotepad_info.txt 记录了库的用途、构建、部署等信息。
- godot 环境在 D:\godot 中。本项目不需要使用 C# ，优先用 Godot_v4.7.1-stable_win64 中的环境。
- 项目中涉及godot扩展的部分，如果修改了代码导致需要重新编译godot扩展时，仅限当前开发机可运行的版本，可不需要经我指示自行编译并处理编译错误。
- 构建过程的中间文件可能会放在 .tmp 目录下，如果我要求清理 .tmp 下的临时文件，应避开会影响构建速度的缓存文件。
- Android 发布版必须使用项目根目录下的固定签名密钥库 `gotepad-model-test.keystore`，别名为 `gotepad-model-test`，证书 SHA-256 指纹为 `128F7F8D6CAE7B5EDBF05EBD6A9E7AD50914001BC2B04ED75A0121A81A007F31`。不得改用 Godot 默认 `debug.keystore`，否则无法覆盖安装既有版本。密钥库已由根目录 `.gitignore` 排除；密钥文件和口令均不得提交到版本库。
- Android 固定签名的本机私密构建信息记录在 `docs/local_build_secrets.md`。该文件已由 `.gitignore` 排除；构建前应读取并使用其中的现有配置，不得新建临时密钥，也不得将该文件内容复制到受版本管理的文件中。

## 项目构成

- 核心引擎使用 C++ 在 src 目录中实现。核心引擎需要跨 Windows、Linux、MacOSX、iOS、Android 平台编译运行。
- 界面部分采用多种 GUI 技术接入核心引擎。目前先使用 Godot 引擎开发桌面端，在 gotepad-gd 目录内实现。
- 在 tests 目录中编写各种测试。

## 编码规范

- C++ 头文件名使用 .hpp 后缀。
- 在 .hpp 中完成类的定义，除非有必须增设 .cpp 的情况。
- 类名使用 PascalCase，例如：`class UserManager`。
- 函数名使用 snake_case，例如：`get_user_info()`，注意private成员函数在后面加 “_” 以示区分。
- 成员变量名使用 snake_case，例如：`member_1`，注意private成员在后面加 “_” 以示区分。
- 常量使用 k 前缀 + PascalCase，例如：`const int kMaxRetries = 3;`。
- 成员函数体超过5行时抽出到类外的 inline 函数，保持类主体精简。

## 文档规范

- 编写 markdown 时，文字段落内不要自行计算行字符数并加入换行符，这种换行符会影响排版，应保持一个段落在同一行。
- user_manual.md 文档需要随着项目的开发进展，自动增加、调整内容；其余 markdown 文件除非我有明确指示，否则不要修改；user_manual.md 文档不要写入开发人员关心的话题，比如安卓版的构建细节等，只记录用户在使用软件上的指南和注意事项。

## 支持更新的版本号和 tag 设计

- 所有发行版都具有一个基础版本号 `i.j.k`，其中 `i`、`j`、`k` 均为大于等于 0 的整数。正式版在软件设置界面和用户手册中显示为 `i.j.k`，测试版显示为 `test/i.j.k`。
- 除了将同一个测试版本正式转正为相同基础版本号的情况外，每次新发布的版本都必须使用高于此前所有已发布版本的基础版本号。某个平台单独更新也必须递增全局基础版本号，不能在之后的其他平台版本或多端版本中重复使用。示例：`0.1.10` 多端发布、`android/0.1.11` 仅 Android 发布、`windows/0.1.12` 仅 Windows 发布、`0.1.13` 再次多端发布。
- GitHub Tag 只允许使用以下四种格式：
  - 正式多端版本：`i.j.k`，例如 `0.1.13`。
  - 正式单平台版本：`platform/i.j.k`，例如 `android/0.1.11`。
  - 测试多端版本：`test/i.j.k`，例如 `test/0.1.14`。
  - 测试单平台版本：`test/platform/i.j.k`，例如 `test/android/0.1.14`。
- `platform` 当前允许使用 `windows`、`android`、`linux`、`macos`、`ios`。不得使用 `android/test/i.j.k` 等其他前缀顺序。
- 无平台前缀的 Tag 对所有平台有效；有平台前缀的 Tag 仅对对应平台有效。通用 Tag 和当前平台 Tag 同时存在时，将两者都作为候选，并选择基础版本号最高者。
- 更新检测不得依赖 GitHub API 返回的 Tag 或 Release 顺序，必须遍历所有有效候选，再依次比较 `i`、`j`、`k`。
- 正式版客户端只接受不带 `test/` 前缀的正式版候选。测试版客户端同时接受测试版和正式版候选：优先选择基础版本号更高者；基础版本号相同时正式版优先，以便 `test/0.1.14` 可以正常转入正式版 `0.1.14`。
- 创建测试版 GitHub Release 时，除使用 `test/` Tag 外，还必须将该 Release 标记为 GitHub Prerelease；正式版不得标记为 Prerelease。Draft Release 不参与更新检测。
- 以上严格格式从 `0.1.11` 开始实施。基础版本号低于 `0.1.11` 的历史 Tag 允许存在 `-b1`、`-b2` 等遗留后缀，解析时仅吸收其 `i.j.k` 基础版本号；基础版本号大于等于 `0.1.11` 的 Tag 必须完全符合上述四种格式，任何多余前后缀、未知平台或格式错误都必须忽略并记录日志。
