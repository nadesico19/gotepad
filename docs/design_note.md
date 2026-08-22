# Gotepad 关键设计记录

本文档用于记录会影响多个模块或后续功能扩展的关键设计约定。当前仅记录人类指定的环节，其他设计在确认后再追加。

## 导出笔记时的节点挑选规则

### 术语

- **记录树节点**：`GoCore::record_tree()` 返回的树中的节点，包括 UID 为 0 的虚拟根节点。
- **排版对象节点**：从记录树中挑选出来、需要生成导出内容的局面节点。
- **叶节点**：没有子节点的记录树节点，即一条分支的最终局面。
- **上一对象节点**：当前分支上，距离当前对象节点最近的已选祖先对象节点；它不是导出顺序中的上一页。

### 挑选条件

从虚拟根节点开始，按照记录树中保存的子节点顺序进行深度优先、先序遍历。一个节点满足以下任意条件时，加入排版对象节点集合：

1. 该节点至少包含一层笔记；
2. 该节点是叶节点，无论是否包含笔记。

同时满足两个条件的节点只挑选一次。没有笔记且仍有子节点的中间节点不参与导出。

由于挑选过程只遍历当前 `GoCore` 记录树，已经不再挂接于记录树的悬空笔记不会被导出。

UID 为 0 的虚拟根节点遵循相同规则：根节点带有笔记时需要导出；一局完全没有后续节点的空棋局中，根节点本身也被视为叶节点。

### 对象节点展开为页面

- 对象节点没有笔记时，生成一页仅包含该局面、自动图题和空评论的页面。这用于保证每条分支的最终局面一定出现在导出结果中。
- 对象节点包含多层笔记时，按照笔记在该节点内的保存顺序逐层生成页面。
- 一层笔记的评论过长时可以拆成多个续页；续页仍属于同一层笔记和同一对象节点。
- 图号以对象节点为单位递增。同一节点的多层笔记及其续页共用同一个图号，不因实际页面数量增加图号。

### 遍历顺序与编号锚点

- 对象节点及图号的先后顺序由记录树的先序遍历结果决定，因此子分支顺序会影响导出顺序。
- 每进入一个对象节点，该节点会成为其所有后代分支的新“上一对象节点”。
- “分支相对编号”和“分支绝对编号”均以当前分支上的上一对象节点为锚点，而不是以导出文件中的上一页、同一局面的上一层笔记或其他分支的对象节点为锚点。

## 下一手分支标记形状

棋盘使用不同形状区分当前局面的下一手落子分支：

- 如果下一手节点是当前播放路径中紧接当前进度的节点，使用**方形**标记，表示播放条将沿此主分支继续前进；
- 其余下一手落子分支使用**圆形**标记，表示它们不在当前播放进度所采用的主分支上。

这里的“主分支”仅指当前 `playback_path` 在当前局面之后选择的下一节点，并不表示该分支在整棵棋谱树中具有永久的主分支身份。当前播放路径发生变化后，标记形状也应随之重新计算。

预置棋子分支继续使用其专用预览和选择方式，不套用上述落子点位的方形、圆形标记规则。标记形状只传达分支与当前播放路径的关系，不改变点击进入分支、上锁状态或棋局漫游的既有行为。

## 笔记面板打开时的棋子编号

笔记面板打开且当前局面存在已选中的笔记标签页时，棋盘必须使用该层笔记的 `numbering` 设置显示棋子编号。此规则的优先级高于程序设置面板中的常规“显示手数”和“绝对手数”选项，且不以标题或评论文本框是否处于编辑状态为条件。

- 打开笔记面板、切换笔记标签页或修改当前笔记的编号方式时，棋盘应立即按当前笔记重新生成编号快照。
- 使用播放条、鼠标滚轮、方向键或其他漫游方式切换局面后，笔记面板应同步到新局面；若新局面存在笔记，则按同步后选中的笔记标签页显示编号。
- 当前局面没有笔记、面板中只有用于新建笔记的 `+` 标签时，不存在笔记编号方式，此时棋盘退回程序设置中的常规编号规则。
- 关闭笔记面板或切换到其他互斥侧边面板后，笔记编号预览失效，棋盘恢复程序设置中的常规编号规则。
- “分支相对编号”“分支绝对编号”“全局绝对编号”和“无编号”的计算由 `GoNotes::note_position_snapshot_at()` 统一完成，Godot 界面只负责选择当前笔记并显示返回的快照，不自行重复实现编号算法。

## KataGo 分析引擎接入架构

### 总体边界

KataGo 分析功能采用“上层统一 JSONL 协议、下层按平台替换传输实现”的设计。Godot 界面和分析业务层不直接依赖操作系统进程、JNI、OpenCL 或 Eigen，只依赖 `KataGoTransport` 定义的行式传输接口。桌面端连接用户部署的外部 KataGo 进程；Android 端在 APK 内同时携带 OpenCL 和 Eigen 两套后端，优先使用 OpenCL，在其不可用或运行失败时自动切换到 Eigen。

桌面端和 Android 端均运行 KataGo 的 `analysis` 模式，通信内容遵循 KataGo Analysis Engine 的 JSON Lines 协议：每个请求是以换行结束的一行 JSON，每个中间结果、最终结果、警告或错误也是一行 JSON。请求使用唯一 `id` 关联结果；停止单个请求时发送带 `action: "terminate"` 和 `terminateId` 的控制消息。`KataGoQueryBuilder` 负责把 `GoNotes` 的局面、预置棋子、落子路径、轮到哪方、规则和贴目转换成 Analysis Engine 请求，并在落子颜色不连续时补入不进入 `GoCore` 节点的 pass，使 KataGo 得到正确的行棋历史。

### Godot 端的统一接口

`KataGoTransport` 对所有后端只暴露以下能力：启动、发送一行文本、停止、查询是否运行，以及接收结果行、日志、错误和停止事件。`KataGoAnalysisService` 在桌面平台创建 `KataGoLocalTransport`，在 Android 创建 `KataGoAndroidTransport`；它把请求字典序列化为单行 JSON，把传输层返回的文本解析成字典，再向分析面板发出结果、查询错误或服务错误信号。因此候选点、胜率曲线、持续分析、暂停显示、终止请求、全路径分析和变化图入口不需要了解当前后端。

日志与协议结果必须分流：标准输出对应的 JSONL 结果进入 `line_received`，初始化和运行日志进入 `log_received` 或控制台，不能把普通日志当成 JSON 结果，也不能把多行日志直接显示在会参与布局的单行状态标签中。

### 人类模仿棋的服务与模型边界

人类模仿棋继续使用 KataGo Analysis Engine 的 JSONL 协议和现有平台传输层，但在业务层使用独立的 `KataGoHumanAnalysisService` 与 `KataGoHumanTransport`。`KataGoHumanTransport` 在 Windows 下包装 `KataGoLocalTransport`，在 Android 下包装 `KataGoAndroidTransport`，所以它自动继承桌面标准管道通信以及 Android OpenCL→Eigen 回退机制，上层人类对局逻辑不需要区分平台。Android 的 OpenCL Java 桥和远端 Service 是进程级单例，Eigen 后端也不应与另一套 KataGo 原生状态并行使用，因此两项业务服务虽然对象独立，底层引擎所有权必须互斥：进入人类模仿棋前停止普通分析后端，整个模式内只允许 Human SL 服务持有引擎，退出时先停止 Human SL 服务，再按进入前的面板状态重新启动普通分析。模式内调用终局数目时也复用 Human SL 服务发送普通 ownership 查询，不能另行启动普通分析后端。

Human SL 不是普通策略网络的替代品，而是与主分析模型配套工作的附加模型。Windows 启动参数为 `analysis -model <主分析模型> -human-model <Human SL 模型> -config <Human SL 托管配置>`；Android 继续使用 APK 内置或用户选定的主分析模型，同时把用户通过系统文件选择器导入的 Human SL 模型作为 `human_model_path` 传入 OpenCL/Eigen 后端。Android 不把 Human SL 权重固化进 APK，导入后由应用数据目录管理真实文件路径，OpenCL 回退到 Eigen 时新后端继续使用同一主模型、Human SL 模型、配置和待处理 JSONL 请求。

普通分析与 Human SL 使用两份托管配置。`SettingsStore` 在 `user://katago/` 下生成 Human SL 专用配置，单独保存搜索线程数、批量大小、缓存规模等参数，并提供保守的跨平台默认值；人类模仿棋的自动性能检测针对“主模型 + Human SL 模型”的组合单独运行，不能复用普通分析模型的检测结果。检测前先比较设置面板路径与当前已生效路径：尚未保存或不一致时先征求保存确认，再校验文件存在、可读且扩展名受支持；检测结果只有在用户点击设置面板绿色确认按钮后才写入专用配置。

### Human SL 请求与选点

`KataGoQueryBuilder.build_human_query()` 复用普通查询格式，但其输入来自人类模仿棋的临时 `GoNotes`：进入模式时的当前盘面作为 `initialStones`，原棋谱此前的落子历史不复制，只有进入模式后的新落子进入 `moves`；棋盘路数、规则和有效贴目从原棋谱继承。查询删除 `analyzeTurns`，只分析临时棋谱的最终局面，同时启用 `includePolicy`，并通过 `overrideSettings` 传入本局选择的 `humanSLProfile`、`ignorePreRootHistory=false`、`humanSLRootExploreProbWeightless` 和 `humanSLCpuctPermanent`。棋风与棋力组合编码为 KataGo 原生档位，例如现代 1 段是 `rank_1d`，AlphaGo 前 1 段是 `preaz_1d`。`initialPlayer` 表示第 0 手行棋方而不是最终局面轮到哪方：临时棋谱还没有新落子时显式设为本次 AI 的颜色，产生新落子后则由临时线性历史的首手及补入的 pass 确定颜色序列。

最终结果优先从 `moveInfos` 中选择经过主模型搜索评价的 Human SL 候选。候选基础权重取 `humanPrior`，再按当前 AI 一方的 utility 使用 `humanPrior * exp(utility / 0.5)` 调整并进行加权随机抽样，使落子保留指定棋力的人类分布，同时降低明显亏损候选被选中的概率；白方使用反向 utility。候选还必须通过当前临时 `GoNotes` 的 `can_place_stone` 合法性检查。若搜索结果缺少可用候选，才回退到原始 `humanPolicy` 分布。Human SL 原始 pass 概率可能失真，所以只有主模型搜索也把 pass 判为第一选择时才接受 pass，随后由界面询问用户是否同意停一手。

### 人类对局的临时棋谱

人类模仿棋复用变化图的临时 `GoNotes` 机制：进入时新建空棋谱，把当前盘面固化为一个预置节点，并继承原棋谱的规则与有效贴目；此前的落子树和分支不复制。在这个基准节点之后由人类和 AI 线性追加落子，原棋谱在模式结束前不发生改变。模式内记录本次双方着手的 actor、UID 和颜色，使悔棋只能在人类回合一次删除“上一手人类落子及其后的 AI 应手”；接受时逐手把临时新增落子保留到主棋谱，放弃时直接销毁临时棋谱。AI 查询期间锁定棋盘交互并用查询 ID 丢弃过期结果，退出或取消时先终止活动请求，避免迟到的异步结果落到已经结束的模式中。

### Windows 桌面端

Windows 端由 `KataGoLocalTransport` 使用 `OS.execute_with_pipe()` 启动用户指定的 KataGo 可执行文件，参数形式为 `analysis -model <模型> -config <配置> -override-config reportAnalysisWinratesAs=BLACK`。Godot 通过子进程的标准输入写入 JSONL 请求，通过标准输出读取 JSONL 结果，通过标准错误读取日志和启动错误；停止服务时终止外部进程并关闭管道。

桌面端不编译、不注册也不发布嵌入式 KataGo 后端。这样可以让用户自行选择 OpenCL、CUDA、TensorRT、Eigen 等官方 KataGo 构建及模型，也避免 Android 专用代码和体积影响 Windows 发布版。桌面端与 Android 端的界面行为保持一致，是因为二者在 `KataGoTransport` 以上使用相同协议，而不是因为它们使用相同的进程管理方式。

### Android 端的嵌入式调用适配

Android 无法像桌面端一样依赖用户部署可执行文件和标准管道，因此对 KataGo v1.17.1 增加了 `analysisEmbedded()` 入口。该入口保留原 `analysis` 命令的参数和 JSONL 语义，但把 `std::getline(std::cin, ...)` 和向 `std::cout` 写结果替换为宿主传入的阻塞读行回调与写行回调。原命令行入口仍调用这一实现，所以补丁不改变 KataGo 自身作为外部程序运行时的行为。

嵌入式引擎使用后台 C++ 工作线程运行 `analysisEmbedded()`。输入行、输出行和日志分别通过受互斥锁保护的队列传递，Godot 主线程只负责发送和轮询，不执行模型加载或搜索。停止时向输入队列写入 `terminate_all`，关闭输入并等待工作线程退出。KataGo 原本适合“独立进程失败即退出”的若干路径也做了嵌入适配：嵌入构建中的 fatal error 改为抛出异常；神经网络服务线程初始化异常会汇报给创建线程、清理已创建线程并重新抛出，避免 `std::terminate` 直接杀死宿主且让上层能够执行后端回退。

内置模型以 Godot 资源随 APK 发布，首次使用时分块复制到 `user://katago/embedded/v1/`。这是因为 KataGo 的原生文件读取需要真实文件系统路径，不能直接读取打包资源路径。用户也可以通过 Android 系统文件选择器导入标准 `.bin.gz` 或 `.txt.gz` 主分析模型；导入任务在后台把内容复制到应用管理目录，设置确认后由普通分析和 Human SL 共同作为主模型使用，用户可以随时切回 APK 内置模型。Human SL 模型走独立的导入路径和设置字段，不能替代主分析模型。分析配置由程序写入 `user://katago/` 下的托管配置文件；默认采用较保守的线程数和批量大小，性能检测确认后再更新。OpenCL 调优数据另存到 `user://katago/opencl/`，供同一设备后续运行复用。

### Android 的 Eigen 后端

Eigen 后端使用 `USE_EIGEN_BACKEND` 编译，并与 Android 版 `go_gdext` 合并为同一个 GDExtension 动态库。`KataGoEmbeddedEngine` 作为仅在 Android 构建中注册的 Godot `RefCounted` 类型，向 GDScript 提供 `start_engine()`、`send_line()`、`poll_lines()`、`poll_logs()`、`stop_engine()`、`get_state()` 和 `get_error()`。`KataGoEmbeddedTransport` 将这些方法包装成标准的 `KataGoTransport` 接口。

Eigen 后端运行在 Gotepad 主进程内的后台线程中，不需要 Android IPC，也不依赖设备 GPU 驱动。它的性能较低，但兼容性最高，是 OpenCL 无法加载、初始化、编译内核或运行时失败后的保底后端。

### Android 的 OpenCL 后端与独立进程

OpenCL 后端使用 `USE_OPENCL_BACKEND` 单独编译为 `libkatago_opencl_android.so`，并由 `KataGoOpenCLService` 在 Android Manifest 指定的 `:katago_opencl` 私有进程中加载。它没有合并进主 GDExtension，原因是部分移动 GPU 驱动在加载、查询设备、编译内核或调优失败时可能直接终止进程；隔离后最多损失 OpenCL 服务进程，不会同时带走 Godot 主进程和用户当前棋谱。

Godot 主进程中的 `KataGoOpenCLTransport` 通过 `JavaClassWrapper` 调用 `GodotApp` 的静态桥接方法。`KataGoOpenCLBridge` 绑定远端 Service，并使用 Android `Messenger` 发送启动、输入行和停止消息；Service 通过另一个 `Messenger` 返回状态、JSONL 结果行、日志和错误。Service 内部再通过 JNI 调用 `libkatago_opencl_android.so`，JNI 层和 Eigen GDExtension 一样用线程安全队列连接 `analysisEmbedded()`。因此完整链路是“GDScript 行式接口 → Java 主进程桥 → Messenger IPC → 独立 Service → JNI → C++ 行式接口”，链路两端仍表现为与桌面标准输入输出相同的 JSONL 数据流。

OpenCL Service 初始化失败后会先把错误回传主进程，再结束自己的进程。KataGo 含有进程级原生全局状态，结束隔离进程可以保证用户稍后重试时从全新的原生状态开始，而不是复用初始化到一半的静态数据。

### OpenCL 到 Eigen 的自动回退

`KataGoAndroidTransport` 是 Android 两个后端之上的选择器。每次启动先创建 `KataGoOpenCLTransport`；以下情况会触发切换到 `KataGoEmbeddedTransport`：OpenCL 同步启动失败、异步报告错误，或者 OpenCL Service 意外停止且仍存在活动请求。已经主动选择 Eigen 后不会重复回退，若 Eigen 也无法启动则向界面报告两套后端均不可用。

为了让切换对业务层透明，选择器会保存所有尚未收到最终结果的请求原始 JSON 行。带 `id` 的普通分析请求加入活动表；收到相同 `id` 且 `isDuringSearch` 不为真的最终结果后移除；发送 terminate 时同步移除被终止的请求。切换成功后，尚在活动表中的请求会原样重发给 Eigen 后端，所以查询 ID、局面、计算量和中间结果设置保持不变。切换会重新开始这些请求的计算，上层应按查询 ID 更新或覆盖结果，不应假设 OpenCL 已完成的访问量能够迁移到 Eigen 搜索树中。

性能检测也使用 `KataGoAndroidTransport`，因此它测量的是当前设备实际可用的首选后端；OpenCL 失败时检测会沿用同一回退机制并测量 Eigen。界面日志应明确显示是否发生自动切换，避免把 Eigen 的低速度误认为 OpenCL 性能。

### Mali 与 Adreno 的 OpenCL 兼容处理

APK 不携带厂商 OpenCL 驱动，只声明可选的 `libOpenCL.so`。Android Manifest 使用 `<uses-native-library android:name="libOpenCL.so" android:required="false" />`，让支持 OpenCL 的系统向应用公开厂商库，同时不阻止没有 OpenCL 的设备安装。由于 NDK 不提供 OpenCL 导入库，构建时生成一个仅用于链接的临时 `libOpenCL.so` 桩库，使 `libkatago_opencl_android.so` 产生对 `libOpenCL.so` 的 `DT_NEEDED`；桩库本身绝不打进 APK，运行时由系统提供的 Mali 或 Adreno OpenCL 库满足依赖。Khronos OpenCL-Headers 只提供编译期声明，不提供运行时实现。

Adreno 驱动兼容点：Android 下枚举设备时只请求 `CL_DEVICE_TYPE_GPU`。部分 Qualcomm 驱动会对桌面端常用的 `CPU | GPU | ACCELERATOR` 组合返回 `CL_INVALID_DEVICE_TYPE`，即使显式请求 GPU 能正常工作。这个修改按 Android 平台生效，不硬编码具体 Adreno 型号，也不会影响桌面 KataGo 的设备枚举策略。

Mali 驱动兼容点：Android 下不探测 NVIDIA 风格的 WMMA FP16 tensor-core 内核。移动 GPU 并不提供这种执行路径，部分 Mali 驱动面对探测内核时不是返回编译错误，而是直接终止进程。普通 FP16 storage/compute 探测仍然保留；此外 Android 调优阶段不启动桌面版用于维持 GPU 高频状态的额外负载线程，以降低移动驱动并发调优的不稳定性和无谓功耗。

FP16 采用 `openclUseFP16=auto`。调优时始终以 Auto 探测 FP16 storage/compute 能力，调优文件记录“硬件能否使用”和“性能是否值得使用”；实际运行是否启用 FP16 再由当前配置决定。这样可避免第一次以 FP32 运行时把“未测试 FP16”错误缓存成“不支持 FP16”，导致后续在 Mali 或 Adreno 上无法启用本来可用的半精度路径。调优缓存位于应用私有可写目录，并由设备名、模型和棋盘尺寸等信息区分。

上述兼容策略不以 GPU 名称硬分支，而是组合使用 Android 平台约束、OpenCL 扩展能力检测、运行时调优、进程隔离和失败回退。这使同一 arm64-v8a APK 可以同时服务 Mali 与 Adreno 设备：能够稳定使用系统 OpenCL 的设备走 GPU 后端，缺少库、驱动拒绝调用、内核编译失败或运行异常的设备自动改走 Eigen。

### 构建与发布边界

Android 的“同时内置两套后端”是指两者进入同一个 APK，并不表示它们进入同一个 `.so`：`go_gdext` 包含 GoNotes 和 Eigen 后端，`libkatago_opencl_android.so` 包含 OpenCL 后端并只供隔离 Service 加载；二者共享相同的 KataGo 通用源文件和嵌入式分析适配。当前 Android 仅构建 `arm64-v8a`，并使用 16 KiB ELF 最大页大小链接选项以适配新一代 Android 设备。Windows 构建默认关闭 `BUILD_EMBEDDED_KATAGO` 和 `BUILD_ANDROID_KATAGO_OPENCL`，发布配置也排除 Android OpenCL 动态库。

第三方 KataGo 源码不会随 Gotepad 仓库发布，因此可复现构建必须以 `third_party/katago/embedded-analysis-api.patch` 保存所有对上游源码的必要修改。当前工作树中的 Android OpenCL 设备枚举、FP16 探测和调优稳定性修正也属于必须保留的适配内容；在清理或重新获取第三方源码前，应确认这些差异已经并入可发布补丁，否则仅重新应用现有嵌入接口补丁可能无法完整还原 Mali、Adreno 兼容行为。
