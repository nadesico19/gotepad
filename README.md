# Gotepad

Gotepad 是一个面向围棋记谱、棋局检讨和棋谱整理的跨平台客户端项目。核心棋盘与棋谱逻辑使用
C++17 实现，当前桌面界面使用 Godot 4.7.1（非 .NET 版本）和 GDExtension 构建。

项目目前仍处于开发阶段。

## 主要功能

- 支持围棋落子、提子、悔棋、预置棋子和多分支棋局记录。
- 支持在棋局树中漫游、调整分支顺序、剪切分支和可视化浏览分支。
- 支持读取、编辑和保存 SGF 棋谱，包括棋谱信息、局面评论及常用棋盘标记。
- 支持为同一局面记录多层笔记，并设置棋子编号方式。
- 支持将带有棋盘图和笔记的内容排版导出为可继续编辑的 PPTX 文件。
- 支持接入本地 KataGo 引擎，查看候选点、胜率、目差和候选变化图。
- Godot 客户端提供多标签、棋局播放、查找棋子、变化图及纹理设置等界面功能。

## 界面预览

### 棋局笔记与棋盘标记

同一局面可以记录多层笔记，并在棋盘上添加顺序字母、三角、方形、圆形和叉形等标记。

![棋局笔记与棋盘标记](examples/screenshots/notes.png)

### KataGo 局面分析

分析面板可以显示候选点、胜率、目差和候选变化图，并绘制整条棋局路径的分析曲线。

![KataGo 局面分析](examples/screenshots/analysing.png)

### PPTX 课件导出

棋盘、编号、标记和笔记可以排版导出为可继续编辑的 PPTX 围棋课件。

![PPTX 围棋课件导出效果](examples/screenshots/courseware.png)

## 项目结构

```text
src/          C++ 核心引擎、GoNotes 数据层及 Godot GDExtension
gotepad-gd/   Godot 客户端工程、场景、脚本和美术资源
tests/        C++ 测试及测试棋谱
third_party/  第三方依赖的放置目录和版本说明
docs/         项目文档
```

核心代码尽量与具体 GUI 技术解耦，以便后续接入其他桌面端或移动端界面。目标平台包括 Windows、
Linux、macOS、iOS 和 Android。

## 构建环境

- CMake 3.20 或更高版本
- 支持 C++17 的编译器
- Godot 4.7.1 非 .NET 版本
- 与 Godot 4.7 API 匹配的 `godot-cpp`

项目依赖以下第三方库：

- [godot-cpp](https://github.com/godotengine/godot-cpp)：Godot GDExtension 的 C++ 绑定。
- [libsgfc++](https://github.com/herzbube/libsgfcplusplus)：SGF 的读取、校验和保存。
- [miniz](https://github.com/richgel999/miniz)：PPTX 导出所需的 ZIP 归档支持。
- [Noto CJK](https://github.com/notofonts/noto-cjk)：PPTX 中文排版使用的黑体和宋体，字体文件按 OFL-1.1 随项目提供。

第三方库源码不随本项目仓库发布。请按照各目录中的 `gotepad_info.txt` 获取指定版本，并将源码放到
对应的 `third_party` 子目录中。PPTX 所用字体位于 `third_party/fonts/noto-cjk`；导出文件不会嵌入字体，
需要保持版式的用户应先在系统中安装这些字体。完整字体授权文本见该目录下的 `OFL.txt`。

准备好依赖后，可以使用 CMake 构建 Godot 扩展：

```sh
cmake -S . -B build -DGODOTCPP_TARGET=template_debug
cmake --build build --target go_gdext
```

扩展会输出到 `gotepad-gd/bin`。随后使用 Godot 4.7.1 打开 `gotepad-gd/project.godot` 即可继续
开发或运行客户端。

## 许可证

本项目使用 [MIT License](LICENSE)。第三方项目仍遵循其各自的许可证。
