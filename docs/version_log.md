# 0.1.21

- 工具菜单中增加一键为特定节点添加占位笔记的功能，特定节点包含有多分支的中间节点以及叶子节点。有占位笔记的节点会自动出现在“专注”模式中，方便用户直接编辑笔记内容。
- 落子防误触在二次点击模式下，点击棋盘外的空白区域可取消一次点击状态。
- 初步进行整体界面美化。
- 优化UI细节。

Translation：

- Added a one-click action in the Tools menu to create placeholder notes for intermediate nodes with multiple branches and leaf nodes. Nodes with placeholder notes automatically appear in Focus mode, making it easy to edit their notes directly.
- In "Click twice" move confirmation mode, clicking the empty area outside the board now cancels the pending move.
- Made initial improvements to the overall interface appearance.
- Improved UI details.

# 0.1.20

- 界面右侧增加用户手册按钮。
- 优化变化图模式的操作体验，取消二次确认，补齐键盘方向键功能。
- 优化UI细节。

Translation：

- Added a user manual button on the right side of the interface.
- Improved variation mode by removing confirmation dialogs for deleting or replacing nodes and adding left/right arrow key navigation.
- Improved UI details.

# 0.1.19

- 适配macOS和iOS平台。macOS版与Windows版类似，需要自行准备KataGo环境；iOS版内置KataGo的Metal后端，以及与安卓版相同的10b模型，并支持侧载其他官方模型，人类模仿棋模型依然需要自行下载。在发布文件中，macOS目前仅构建了arm版，今后根据需要补充universal版；iOS提供ipa和构建指南，但不提供商店下载。
- 安卓版的导出PPT功能，现已支持使用PNG格式的棋盘图片，可兼容WPS等Office软件。
- 设置中的“大尺寸界面（移动端用）”改为“界面UI缩放”，倍率下限调整到0.5x，精度支持到小数点后2位。
- 优化其他UI细节。

Translation：

- Added support for macOS and iOS. Like the Windows version, the macOS version requires users to set up KataGo themselves. The iOS version includes KataGo's Metal backend and the same 10b model as the Android version, and supports importing other official models; the Human SL model for human-like play must still be downloaded separately. The current macOS release is ARM-only, with a Universal version to be added as needed. For iOS, an IPA and build instructions are provided, but the app is not available through the App Store.
- PPT export on Android now supports PNG board images for compatibility with WPS and other office suites.
- Renamed the "Large UI (for mobile)" setting to "UI scaling", lowered the minimum scale to 0.5×, and added support for two decimal places.
- Improved other UI details.

# 0.1.18

- 安卓版增加特定模型加速选项，勾选后KataGo分析可能获得加速效果。首批优化的对象模型是b18c384nbt、tf2-b10c384，在玄戒O3上已通过加速效果和数值一致性的双重验证，其中tf2模型获得了40%以上的显著速度提升。在其他机型（如骁龙8E5）和其他版本的模型上也可能获得相近的加速效果，但这受到多重因素的影响：该机型是否能够正常运行对象模型；对象模型的热点算子是否被本优化涵盖；不同计算精度带来的数值差异是否在可接受范围；等等。建议用户采取关闭、开启加速开关，分别进行自动性能检测，对比性能测试结果，再结合数值验证结果，综合考虑是否开启加速。请注意，安卓内置的10b模型由于内部结构差异，暂不受加速开关的影响。
- 安卓版在进行人类模仿棋时，固定使用内置模型进行胜率、目差分析，以避免分析模式设置了较重模型导致AI行棋变慢。
- 优化自动性能检测、持续分析相关的操作细节。
- 优化影响触屏操作的UI细节。

Translation：

- Added a model-specific acceleration option on Android that may speed up KataGo analysis. The first optimized models are b18c384nbt and tf2-b10c384. On the XRING O3, both passed checks for speed gains and numerical consistency, with the tf2 model running more than 40% faster. Similar gains may be possible on other devices, such as Snapdragon 8E5, and with other versions of these models, depending on whether the device can run the model, whether the optimization covers its most demanding operations, and whether differences between numerical precisions are acceptable. To decide whether to enable the option, run the automatic performance test with acceleration off and on, compare the results, and consider the numerical validation results as well. The built-in Android 10b model has a different architecture and is currently unaffected by this option.
- Human-like play on Android now always uses the built-in model to evaluate win rate and score lead, so selecting a larger model for regular analysis does not slow down the AI's moves.
- Improved details of automatic performance testing and continuous analysis.
- Improved UI details affecting touch controls.

# 0.1.17

- 落子防误触支持两种模式：二次点击和图标确认。

Translation：

- Move confirmation now supports two modes: clicking the same position again and confirming with icons.

# 0.1.16 (android)

- 完善安卓端的自动性能检测和配置参数优化的逻辑，避免落入保守配置导致无法充分发挥移动端GPU的性能。特别指出，此修改使得KataGo分析模式在小米玄戒O3上取得了至少翻倍的性能提升。

Translation：

- Improved Android's automatic performance testing and configuration optimization logic, preventing overly conservative settings from underutilizing the mobile GPU. In particular, this change at least doubled KataGo analysis performance on the Xiaomi XRING O3.

# 0.1.15

- 棋谱信息页的规则和贴目增加快捷设置按钮，便于在加载缺少相关属性的SGF时做快速设置，该设置会影响KataGo分析。
- 设置和棋谱信息面板增加翻页按钮，优化移动端的翻页体验。
- 优化手机上打开大尺寸界面选项后，英文版的分析面板尺寸可能异常的问题。

Translation：

- Added quick-set buttons for rules and komi to the game information panel, making it easier to configure SGFs that omit these properties. These settings affect KataGo analysis.
- Added page navigation buttons to the settings and game information panels, improving the mobile scrolling experience.
- Fixed an issue where the English analysis panel could become abnormally wide on phones when the large UI option was enabled.

# 0.1.14

- 解决安卓版中如果KataGo后台被系统回收，只能重启软件才能恢复的问题。
- Windows端的分支预览视图支持鼠标左键移动视口，适应触控板不支持右键拖拽的情况。
- 数目功能改用独立计算量参数，默认500 visits。
- 变化图模式中，允许在中间节点直接另选位置落子，自动删除原有后续节点。
- Windows端双击打开SGF时，在当前已运行的Gotepad内新建标签页，而非新建Gotepad窗口。
- 修复安卓端从系统内打开SGF跳转Gotepad时，已有标签被新SGF覆盖的问题。

Translation：

- Fixed an issue on Android where KataGo could only be restored by restarting the application after its backend was reclaimed by the system.
- The branch preview on Windows can now be panned with the left mouse button, accommodating touchpads that do not support right-button dragging.
- Endgame scoring now uses a separate computation-effort setting, defaulting to 500 visits.
- In variation mode, you can play a different move from an intermediate node, replacing its existing continuation after confirmation.
- On Windows, double-clicking an SGF now opens it in a new tab in the running Gotepad instance instead of creating another Gotepad window.
- Fixed an issue on Android where opening an SGF from the system could overwrite an existing tab in Gotepad.

# 0.1.13

- 修复仿人棋退出后预置按钮消失的问题。
- 盘面候选标记支持显示目差。
- 人类模仿棋增加认输提示。
- 软件启动时自动检测更新。
- 优化UI细节。

Translation：

- Fixed an issue where preset-stone buttons disappeared after exiting human-like play.
- On-board candidate markers can now display score lead.
- Added resignation suggestions to human-like play.
- The application now checks for updates automatically at startup.
- Improved UI details.

# 0.1.12

- 增加盘面候选标记的胜率文字大小；前三候选和其他候选可以分别设置透明度。
- 修改分析模式相关设置时，尽量避免影响已有的分析数据和持续分析开关。
- 安卓版的数值和文本编辑控件启用长按后编辑，减少输入法的误弹出，并增加数值调整箭头的大小。
- 完善人类模仿棋在切换或新建其他棋谱时的退出机制。
- 优化首次使用软件时调整界面语言的指引。
- 优化数值设置选项的调整步进。

Translation：

- Increased the win-rate text size of on-board candidate markers; opacity can now be configured separately for the top three and additional candidates.
- Changes to analysis-mode settings now preserve existing analysis data and the continuous-analysis toggle whenever possible.
- On Android, numeric and text input controls now require a long press to edit, reducing accidental keyboard pop-ups, and the numeric adjustment arrows have been enlarged.
- Improved how human-like play exits when switching to or creating another game record.
- Improved the guidance for changing the interface language when using the application for the first time.
- Improved the adjustment step sizes of numeric settings.

# 0.1.11

- 增加检测软件更新的功能。
- 优化UI细节。

# 0.1.10

- 【紧急】修复倒扑棋型无法正常提子的严重Bug。
- 分析模式可以设置额外数目的盘上候选标记。
- 分析模式中，当棋盘上锁不允许落子时，可通过点击盘上的候选标记直接进入变化图。
- 笔记面板追加专注模式，可以浏览和编辑所有笔记，浏览顺序与导出的PPT一致。
- 安卓版调整性能配置参数，可能优化功耗发热。
- 修复UI Bugs，优化UI细节。

# 0.1.9

- 新建棋盘界面增加“粘贴”入口，可以从系统剪贴板读取完整的 SGF 文本并创建棋谱。

# 0.1.8

- 接入 Katago 的人类模仿棋功能，Windows、Android 都需要自行部署专用模型。
- 笔记输入框增加“全选/复制/剪切/粘贴”的实体按钮，用于移动端触屏操作。
- 优化UI细节。

## 0.1.8 b1

- 进入人类模仿棋时继承当前棋谱内的落子顺序，避免特殊局面影响 AI 判断。

## 0.1.8 b2

- 修正人类模仿棋的自动性能检测逻辑。

## 0.1.8 b3

- 修复分支预览界面缩放至同屏大量节点后，可能出现卡顿、卡死的问题。
- 分析模式中，当棋谱下一手命中前三选时，该位置的胜率标记追加黑色轮廓。

## 0.1.8 b4

- 人类模仿棋的 visits 参数与分析模式参数分离。
- 加强安卓平台上人类模仿棋自动性能检测的健壮性。

# 0.1.7

- 增加从图片或者拍照新建棋盘的功能，拍照仅支持安卓版。
- 增加终局数目功能，仅支持中国规则。
- 增加将本软件注册为 SGF 文件打开方式的功能。
- 在打开持续分析时，进入和退出变化图、分支预览模式，不会关闭持续分析。
- 增加限制棋盘横向屏幕占比功能，用于一些特殊屏幕比例的移动端设备。
- 盘面最后一手数字使用强调色。
- 优化UI细节。

# 0.1.6

- 安卓版增加大UI模式，优化手机使用体验。
- 安卓版更新内置的10b权重，并开放外置权重加载功能。
- 提升SGF读写的健壮性。
- 在分析模式下，对胜率掉10点以上的下一手标红提示。
- 优化UI细节。

## android 0.1.6 b1
- 解决横屏不能根据设备方向旋转的问题。
- 解决字体回退导致出现方块字符的问题。

# 0.1.5

- 在中文基础上，追加适配日本语、韩国语、英语。
- 适配安卓平台，推荐使用安卓平板。
- 安卓版应用内嵌 katago 引擎，自动选择OpenCL/Eigen 后端。目前处于试验阶段，权重仅支持b10c128。
- 优化UI细节。

# 0.1.4

- 合并分支剪切和顺序调整图标，并增加双击进入分支功能。
- 修改katago的自动性能测试功能，取消时间限制，显示测试过程。
- 局面分析增加加大计算量功能。
- 增加工具菜单，加入保留主干和清理笔记功能。
- 增加高分辨率界面缩放和桌面窗口大小记忆。
- 增加 PPTX 棋盘坐标导出选项。
- 增加落子音效及相关设置。
- 优化UI细节。

# 0.1.3

- 完善笔记编辑期间的未保存内容保护和棋子编号预览。
- 支持事务式修改已有预置棋子节点，并校验后续棋局分支。
- 文本框聚焦时，非冲突的全局快捷键仍可正常使用。

# 0.1.2

- 增加 PPTX 棋盘图片的 SVG/PNG 导出选项。
- 增加用户手册。

# 0.1.1

- 接入本地的katago分析引擎。
