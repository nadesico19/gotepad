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
