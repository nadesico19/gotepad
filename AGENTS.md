## 编译环境

- 项目类型：围棋棋盘的客户端。
- 语言和标准：C++ 17。
- 构建系统：CMake。
- 第三方库统一放在 third_party 文件夹下，目前有：
  - libsgfcplusplus：解析/导出SGF围棋谱需要。
- godot 环境在 D:\godot 中。
  - 本项目不需要使用 C# ，优先用 Godot_v4.7.1-stable_win64 中的环境。

## 项目构成

- 核心引擎使用 C++ 在 src 目录中实现。
  - 核心引擎需要跨 Windows、Linux、MacOSX、iOS、Android 平台编译运行。
- 界面部分采用多种 GUI 技术接入核心引擎。
  - 目前先使用 Godot 引擎开发桌面端，在 gotepad-gd 目录内实现。
- 在 tests 目录中编写各种测试。

## 编码规范

- C++ 头文件名使用 .hpp 后缀。
- 在 .hpp 中完成类的定义，除非有必须增设 .cpp 的情况。
- 类名使用 PascalCase，例如：`class UserManager`。
- 函数名使用 snake_case，例如：`get_user_info()`，注意private成员函数在后面加“_”以示区分。
- 成员变量名使用 snake_case，例如：`member_1`，注意private成员在后面加“_”以示区分。
- 常量使用 k 前缀 + PascalCase，例如：`const int kMaxRetries = 3;`。
- 成员函数体超过5行时抽出到类外的inline函数，保持类主体精简。

## 特殊要求

- 项目中涉及godot扩展的部分，如果修改了代码导致需要重新编译godot扩展时，可不需要经我指示自行编译并处理编译错误。