# 樱读 · 社区反馈整理与处理说明

> 数据来源：B 站 / 小红书 上「樱读 v1.1.0」发布贴的评论区截图（共 12 张，2026-10）。
> 整理时间：2026-10-22
> 对应改动：本仓库未发布的本地改动（见文末「改动清单」）。

这份文档做两件事：**先把用户的反馈按主题归类并还原原意**，再逐条标注「已修复 / 已增强 / 暂不做」以及为什么。

## 一、反馈归类

| # | 反馈原文（摘要） | 归类 | 严重度 |
| --- | --- | --- | --- |
| 1 | 「滚动阅读什么时候能支持直接滑到下一章」 | 阅读器 · 滚动模式跨章 | 高（多人点赞 + 作者承诺） |
| 2 | 「目录识别过于松垮，`0` 都被识别成目录章节了」 | TXT 解析 · 章节识别 | 高 |
| 3 | 「不同章节之间不能无缝衔接（我用滚动阅读）」 | 同 #1 | 高 |
| 4 | 「行距、段距不能调到负的，间隔还是有点大」 | 排版设置 | 中 |
| 5 | 「如果阅读进度和时间有详细的曲线图」 | 阅读统计 | 中 |
| 6 | 「底栏什么玻璃没效果啊都是透明」 | 视觉 · 毛玻璃底栏 | 中 |
| 7 | 「能不能删除的时候直接删本地文件」 | 书架 · 删除文件 | 中 |
| 8 | 「朗读暂时不可用 · 系统未安装语音合成引擎」（截图 2 张） | TTS 可用性 | 中 |
| 9 | 「能不能适配一下平板啊，类似第二张图这种还有翻页效果」 | 宽屏适配 | 中 |
| 10 | 「可以做个这种书架吗，这个是 reeden 的书架」 | 书架样式 | 中 |
| 11 | 「希望能支持 js 格式的书源」 | 书源 · JS 规则引擎 | 高（工作量大） |
| 12 | 「音量键翻页，小樱非常奈斯」 | 音量键翻页 | 低（明确点名想要） |
| 13 | 「下不了小说了，源没问题」（附图） | 书源 · 网络健壮性 | 高 |
| 14 | 详情页报错「读取详情失败 / 请求失败：Connection closed before full header was received」（附图） | 同 #13 | 高 |
| 15 | 「兼容性有点炸裂，小米 17pm 一卡一卡的」 | 性能 | 中（难复现） |
| 16 | 「epub 排版比多看差一些」「希望支持 mobi 等格式」 | EPUB 排版 / 更多格式 | 中（大工程） |

## 二、逐条处理

### 1 + 3. 滚动阅读跨章无缝衔接 ✅ 已实现

**原问题**：滚动模式只在当前章内滚动，滑到底就停住，必须退出后手动「下一章」；翻页模式早就有「跨章连页」，滚动模式一直没有。

**做法**（`lib/src/ui/reader/reader_page.dart`）：

- `_ScrollReader` 的数据源从「单章文本」改成「章节列表」`List<_ScrollChapterText>`，内部为每个段落记住 `(所属章, 章内偏移)`，滚动时通过 `onPositionChanged(chapter, offset)` 回报真实阅读位置（进度、章节目录高亮因此都准确）。
- 监听滚动通知：接近底部（剩余 < 1.2 屏）时回调 `onNeedNext`，接近顶部（`extentBefore < 2`）时回调 `onNeedPrev`。
- 外层 `_extendScrollFlow()` / `_prependScrollFlow()` 负责把下一章 / 上一章读进同一个滚动视图；**向前补一章时用 TextPainter 量出插入内容的高度并补偿 `jumpTo`**，所以视觉上文字不会「跳一下」。
- 「下一章」按钮 / 音量键在滚动模式也直接续到下一章，不再是滚到底就不动。

**验证**：模拟器（MuMu，Android 15）滚动模式下从第 1 章连续滚到第 20 章，正文、页脚「第 N / 200 章」、进度同步推进，无跳字、无空白页。

### 2. 目录识别收紧 ✅ 已修复

**原因**：判断「这一行是不是章节标题」时先把行首空白 trim 掉了，再拿 `trim` 后的文本判断「是否带正文缩进」，结果是这个判断永远为假；同时以句号结尾的正文句子只要够短也会被当成标题，于是 `0`、`123`、`...` 这类残行都能混进目录。

**做法**（`lib/src/data/txt_parser.dart`）：

- 新增 `_hasBodyIndent(line)`：用**未 trim** 的原始行判断行首是否有 2 个全角空格 / 4 个半角空格——带正文缩进的行一律不算标题。
- 标题行长度上限从 50 收到 32（`_maxHeadingLineLength`）。
- 句读符号 > 2 个直接否掉；以 `。` / `.` 结尾一律不是标题；以 `！` / `？` 结尾只允许 ≤ 16 字。
- 保留 `第N章`、`序章/楔子/尾声/番外`、`Chapter N`、`【标题】` 四类模式。

**验证**：新增 `test/feedback_round2_test.dart` 覆盖「纯数字/纯符号不算章」「缩进正文不算章」「`【】` 仍支持」「200 章标准小说不多不少」。

### 4. 行距 / 段距 ✅ 已实现

- 行距下限从 1.2 放宽到 **1.0**（再小文字会重叠，不可读），设置项文案同步。
- 新增 **段间距** 独立滑杆（0 ~ 40，默认 12），滚动模式按 `EdgeInsets.only(bottom: paragraphGap)` 渲染；旧配置文件没有该键时回落默认值。
- 顺带把「距顶部 / 距底部」保留可调（原有），配合段间距可以把版面压得很紧。

### 5. 阅读时长曲线图 ✅ 已实现

`lib/src/ui/stats_page.dart` 新增「阅读时长」卡片：7 / 14 / 30 天三档切换，用 `CustomPainter` 画 **Catmull-Rom → 三次贝塞尔** 的平滑曲线，曲线下方铺渐变，标注日均时长，今天的数据点高亮。不引入任何第三方图表依赖。

### 6. 底栏「玻璃没效果」 ✅ 已修复

**原因**：`NavigationBar` 的背景色由主题写死成不透明色（`Colors.white` / `0xFF1D1626`），而底栏本身没有做模糊，所以既没有毛玻璃也谈不上透明效果，看上去就是一块纯色。

**做法**（`lib/src/ui/home_page.dart`）：`Scaffold.extendBody = true`；底栏外面套 `ClipRect → BackdropFilter(blur 18) → 半透明 tint`，并把 `NavigationBar` 的 `backgroundColor / surfaceTintColor / elevation` 全部置空，让模糊真正透出来。

### 7. 删除时删本地文件 ✅ 已实现

`BookStore.removeById(id, {deleteLocalFile})`：`true` 时同时删除源文件（在线书 / 文件已不存在时静默跳过）；书架「从书架移除」弹窗新增勾选项「同时删除本地文件」，并显示将被删除的路径，默认**不勾**（防止误删用户原书）。

### 8. TTS 不可用 → 内置离线语音 ✅ 已实现

**原问题**：很多机型（尤其国产 ROM、模拟器）压根没装系统 TTS 引擎，点朗读只会弹「系统未安装语音合成引擎」，功能等于不存在。作者在评论区也回了「跟手机品牌有关系，我后面换一个方案 / 考虑内置一个语音」。

**做法**（分两层）：

1. **引导层**：阅读器「朗读暂时不可用」弹窗新增 **去系统设置** 按钮，直接跳到系统「文字转语音输出」页（`MainActivity.openTtsSettings()`，依次尝试 `TTS_SETTINGS` → `TtsSettings` fragment → 应用详情兜底），失败时用 SnackBar 给出手动路径；设置页「未检测到语音引擎」一行同样可点。
2. **兜底层（内置离线语音）**：引入 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（Apache-2.0，纯 FFI、无 Java 依赖）+ VITS 中文模型「超文 (chaowen medium int8)」（CC0，22.05 kHz，18 MB），随包内置在 `assets/tts/chaowen/`。
   - `lib/src/platform/offline_tts.dart`：首次使用把模型从 assets 复制到应用私有目录（已存在则跳过），在**独立 isolate** 里加载 onnx 并合成 WAV，主线程不卡；isolate 崩溃/退出会回传错误，不会把 UI 卡到超时。
   - `lib/src/platform/tts_service.dart`：引擎解析顺序变为「用户指定 → 系统默认 → 逐个系统引擎 → 内置离线语音」，内置引擎在所有系统引擎都不可用时自动接管；合成结果交给原生 `ttsPlayFile`（`MainActivity` 里用 MediaPlayer 播放），播完仍走原来的 `ttsState done` 事件，所以**自动跟读、自动下一章、语速调整全都沿用原有逻辑**。
   - 设置页引擎下拉新增「内置离线语音（无需安装）」；「测试朗读」直接用内置语音播一句话。

**验证**（MuMu 模拟器 Android 15，该模拟器本身无系统 TTS 引擎）：选内置引擎 → 测试朗读 → logcat 出现 `MediaPlayer` + `AudioTrack` 播放记录（`stop(9): called with 93148 frames delivered`），`cache/tts_speech/p0.wav` 落地 178 KB / 22.05 kHz / 单声道 / 4.01 秒，证明「合成 → 播放」整条链路通。

**代价与体积控制**：sherpa-onnx 的原生库（onnxruntime 等，每个 ABI 20 MB 以上）+ 20 MB 语音模型，三条 ABI 全打进包里会让安装包涨到 170 MB 以上。本轮已做两级瘦身（`android/app/build.gradle.kts`）：

1. **单 ABI 打包**：release 只保留 arm64-v8a（`flutter build apk --release` → **43.4 MB**）；模拟器验证用 `--target-platform android-x64` 出 x86_64 包（44.7 MB）；debug 默认不限 ABI，免得换台设备就跑不起来。
2. **原生库压缩存储**：`packaging.jniLibs.useLegacyPackaging = true`，让 `.so` 以压缩方式进包（onnxruntime 25.6 MB → 8.9 MB），安装时由系统解压——磁盘占用不变，下载体积再省一大截。

后续若还想更小，可改为首次进入朗读时按需下载模型（约 20 MB），并用 App Bundle 交给商店按 ABI 分发。

### 9. 平板适配 ✅ 已实现（基础版）

- 阅读器：正文版心最大宽度 680 逻辑像素，超出部分均分为左右留白（`_maxColumnWidth` / `_effectiveMarginH`），宽屏不再一行排 40+ 字；手机竖屏不受影响。
- 书架：大封面样式的列数按屏宽自适应（3 / 4 / 5 / 6 列）。

### 10. 「大封面」书架 ✅ 已实现

`ShelfViewMode` 新增 `cover('大封面')`：封面做主视觉、书名作者压在下方，一屏 2~3 列（手机），排列方式面板里可直接切换并持久化。reenen 那种带书脊/多层木板的拟物书架没有做（属于纯视觉定制，收益低于其它项）。

### 11. JS 书源 ⏳ 部分支持（明确降级）

`exploreUrl` 的三种写法里，行格式 `标题::地址` 与 JSON 数组已支持（共约 634 个书源）；**`@js:` / `<js>` 脚本生成分类的源（约 168 个）无法执行**——项目里没有 JS 引擎，`webview_engine.dart` 的 WebView 也只能加载页面、不能安全求值阅读 3.0 的 JS 规则。

本轮做的事：发现页在书源统计里**显式区分**「可用 / 使用 JS 脚本（暂不支持）」，并给出提示文案，用户不会再对着一个「0 个可用」的书源反复点。真正的 JS 规则引擎（需要引入 quickjs / flutter_js 之类的原生依赖，并实现 Legado 的 `java.*` / `book.*` 接口）留作后续阶段。

### 12. 音量键翻页 ✅ 已实现

`MainActivity.onKeyDown` 拦截 `KEYCODE_VOLUME_UP / VOLUME_DOWN`（仅在开关打开且阅读页在前台时），通过 `MethodChannel` 回传 `prev` / `next`；Dart 侧 `NativeBridge.bindVolumeKeyHandler` 绑定到阅读器翻页，退出阅读页自动解绑，不会影响系统音量。开关在「阅读设置 → 更多」，**默认开启**（用户反馈里被明确点名想要，默认关等于没人发现它）。

### 13 + 14. 网络报错「Connection closed before full header was received」✅ 已修复

**原因**：`package:http` 默认复用 keep-alive 连接，对端提前关掉连接后，下一次请求会撞在一条死连接上直接抛 `ClientException`；原实现重试时仍用同一个 `http.Client`，于是每次重试都踩同一条死连接，最后把原始英文异常直接抛给用户。

**做法**（`lib/src/source/http_client.dart`）：重试次数 1 → 2；每次重试前 `_resetConnectionPool()` 关掉旧 client 并新建（仅当 client 由自己创建时才重建，避免动到外部注入的 mock client）；超时 / SocketException / ClientException 都走同一条恢复路径；错误信息保持中文可读。

### 15. 卡顿 / 16. EPUB 排版与 mobi ⏳ 暂不做

- 卡顿只在「小米 17pm」单个机型上被提到，没有可复现的操作路径与 profiler 数据，盲改容易引入回归；已记录待用户提供复现场景。
- mobi / azw3 需要引入 mobi 解析库并重建排版管线；EPUB 排版对齐多看是长期视觉工程。两者都超出本轮范围，写进 Roadmap。

## 三、改动清单

修改（27 个文件、+2226 / -339）：

```
android/app/build.gradle.kts                      单 ABI 打包 + 原生库压缩（瘦身）
android/app/src/main/kotlin/.../MainActivity.kt   音量键拦截 / 跳系统 TTS 设置 / 内置语音文件播放
lib/src/app.dart                                  AI 聊天时隐藏桌宠
lib/src/data/book_source.dart                     TXT 解码统一换行（跨章错位修复）
lib/src/data/book_store.dart                      removeById(deleteLocalFile) / 导出插图落盘
lib/src/data/epub_parser.dart                     插图抽取（章节回填时漏 images 的 bug）
lib/src/data/prefs.dart                           段间距 / 音量键 / AI 配置等字段
lib/src/data/shelf_sort.dart                      大封面样式
lib/src/data/txt_parser.dart                      目录识别收紧
lib/src/platform/native_bridge.dart               音量键通道 / 打开 TTS 设置
lib/src/platform/tts_service.dart                 内置离线语音接管朗读
lib/src/source/analyze_css.dart                   h3@text 这类裸标签选择器修复
lib/src/source/http_client.dart                   死连接重建 + 重试
lib/src/ui/home_page.dart                         毛玻璃底栏
lib/src/ui/reader/reader_page.dart                滚动跨章 / 版心收窄 / TTS 引导 / 插图渲染
lib/src/ui/reader/reader_settings_panel.dart      行距下限、段间距、音量键开关
lib/src/ui/settings_page.dart                     AI 卡片 / 语音引擎入口
lib/src/ui/shelf_page.dart                        大封面书架 / 删除文件勾选 / AI 入口
lib/src/ui/source/discover_page.dart              书源监听刷新 / JS 源提示
lib/src/ui/source/online_book_page.dart           详情失败的可读提示
lib/src/ui/stats_page.dart                        阅读时长曲线（7/14/30 天）
pubspec.yaml                                       sherpa_onnx 依赖 + 内置语音 asset
test/source_net_test.dart                          重试与错误信息
test/tts_service_test.dart                         朗读分段剔除插图标记 / ［插图］占位
```

新增：`lib/src/data/ai_service.dart`、`lib/src/platform/offline_tts.dart`、`lib/src/ui/ai_chat_page.dart`、`lib/src/ui/ai_settings_page.dart`、`assets/tts/chaowen/`（内置语音模型 20 MB），
测试 `test/ai_service_test.dart`、`test/explore_page_test.dart`、`test/txt_chapter_offsets_test.dart`、`test/feedback_round2_test.dart`、`test/epub_image_test.dart`、`test/offline_tts_assets_test.dart`。

## 四、验证

- `flutter analyze`：No issues found。
- `flutter test`：320 通过 / 2 失败（共 322 条），失败的 2 条在 `test/folder_picker_test.dart`（文件选择器的书源/小说过滤），**在改动前的干净分支上同样失败**，与本轮改动无关。
- `flutter build apk --release`：arm64 包 43.4 MB，x86_64 包 44.7 MB（单 ABI + 原生库压缩后，比三 ABI 全打包的 170 MB 小了一个数量级）。
- 模拟器（MuMu 12 / Android 15 / x86_64）逐项点测：滚动跨章 1→20 章、目录定位、大封面书架、删除勾选、时长曲线三档、TTS 引导跳转、内置离线语音合成+播放、音量键翻页、网络重试、EPUB 插图渲染；release 包同样跑通了内置离线语音（logcat `AudioTrack: stop(26): called with 807497 frames delivered`）。

## 五、补充：EPUB 插图（用户反馈 #16 的一部分）

**原问题**：「epub 排版比多看差一些」，且书里的插图看不到，只剩一个「［插图］」占位文字。

**根因**：`EpubParser` 其实早就把 `<img>` 抽出来并写进正文标记，但末尾「用 TOC 标题回填章节」的修补步骤重建 `EpubChapter` 时漏传了 `images:`，于是每章图片列表都被悄悄丢空——图片字节从未落盘，阅读器只能显示占位符。

**做法**：

- `lib/src/data/epub_parser.dart`：回填时保留 `images: ch.images`。
- `lib/src/data/book_store.dart`：导入 EPUB 时把每章插图写入 `<cache>/<bookId>/img/`。
- `lib/src/ui/reader/reader_page.dart`：滚动模式按 `\u0001IMG:name\u0001` 标记用 `BookImage` 渲染真图；分页模式因为按字符测量排版，仍显示「［插图］」文字占位（后续可改为按页占位高度）。

**验证**：`test/epub_image_test.dart` 在内存里现造一个带 PNG 插图的 EPUB，断言图片被抽出且标记正确；模拟器上用 VIEW intent 导入该 EPUB，正文里插图正常显示（截图像素采样到插图底色）。

## 六、补充：AI 助手可下载「本地小模型」（离线运行）

> 这条不是评论区反馈，是作者自己提的需求：给 AI 助手加一条「可选下载本地小模型」的接入，
> 走国内镜像下载，选型要「效果好而且轻量化」。

### 选型

| 方案 | 结论 |
| --- | --- |
| llama.cpp（flutter_llama 等第三方封装） | 需要自己交叉编译 JNI，且 x86_64 模拟器链路麻烦，弃 |
| ONNX Runtime GenAI | Android 官方包对 x86_64 覆盖不全，模拟器验证困难，弃 |
| **MediaPipe LLM Inference**（`com.google.mediapipe:tasks-genai:0.10.24`，Apache-2.0） | Google 官方 AAR，自带各 ABI 的 `libllm_inference_engine_jni.so`，Kotlin API 简单、流式回调原生支持。**采用** |

模型：**Qwen2.5-0.5B-Instruct** 的 MediaPipe `.task` 包（q8 量化，**521 MB**，Apache-2.0，原生支持中文）。
0.5B 是体积 / 可用性的平衡点：1.5B 要 1.1 GB 文件 + 2.5 GB 内存，给一个阅读 App 当赠品不合适；
换更大模型只需在 `localModelCatalog` 里加一条，引擎与模型解耦。
下载镜像按国内优先级排序：modelscope（实测 ~2 MB/s）→ hf-mirror.com → huggingface.co。

### 实现

- `lib/src/data/local_llm.dart`
  - `LocalModelSpec` / `localModelCatalog`：模型元数据（体积、许可证、镜像列表）都在这里。
  - `LocalModelManager`：下载（先写 `.part`，长度与 `bytes` 不符就换镜像重试）、进度通知、加载 / 卸载 / 删除、已下载状态探测（同时比对原生侧「已加载的路径」）。
  - `LocalLlmEngine`：`sakuramanga/llm` 通道的 Dart 封装（`info` / `load` / `generate` / `cancel` / `unload` / `tokenCount`）。
  - `LocalLlmChat`：把阅读快照 + 最近几轮对话压进 1280 token 的上下文（输入预算 800、回答 340）；超预算依次降级：丢历史 → 丢阅读数据 → 只留最后 300 字；输出清洗 `<|im_end|>` 等控制符。
- `android/app/src/main/kotlin/.../LocalLlmEngine.kt`：`LlmInference` 的持有者。`setMaxTokens(1280)`、`setMaxTopK(40)`，`generateResponseAsync` 逐段回传 `partial`，`done` / `error` 收尾；`cancel` 用标志位丢弃后续回调。
- `lib/src/ui/ai_settings_page.dart`：运行方式二选一（在线接口 / 内置本地模型）。**切换立即落盘**（这里踩过一个坑：早期只在「保存」按钮里写 prefs，而本地模式的卡片里根本没有保存按钮，于是切到本地后直接返回，对话页仍然走在线接口 —— 已改为点击即生效）；本地卡片显示模型名 / 参数量 / 许可证 / 体积 / 下载进度 / 已就绪状态，可删除模型文件。
- `lib/src/ui/ai_chat_page.dart`：本地模式下发送即「首次加载 → 逐字流式」，气泡实时增长，生成中发送键变「停止」；模型没下载时给引导页而不是报错。
- `android/app/build.gradle.kts`：`implementation("com.google.mediapipe:tasks-genai:0.10.24")`，沿用已有的单 ABI 打包规则，只打目标 ABI 的那份 `.so`。
- `android/app/proguard-rules.pro`（新增）：release 包开了 R8，`tasks-genai` 里有两类只在编译期 / 多模态分支存在的类（`com.google.auto.value.*`、`com.google.protobuf.*`、`com.google.mediapipe.framework.image.*`），不放过就会 `minifyReleaseWithR8` 直接失败；MediaPipe 的类还要整体 `-keep`（JNI 按类名反射查找，混淆后真机上会「模型加载失败」）。

### 验证（MuMu 模拟器 Android 15 / x86_64）

- 下载：设置 → AI 助手 → 运行方式「内置本地模型」→ 下载模型，进度条 0 → 100%，521 MB 约 5 分钟（~2 MB/s）；落地 `files/models/qwen2.5-0.5b-instruct-q8.task`，长度 546,660,344 字节与元数据完全一致。
- 首次对话：约 8 秒（TFLite 初始化 + XNNPACK delegate 缓存构建）后开始流式吐字；第二次 `load` 因 XNNPACK 权重缓存命中，加载 < 2 秒。
- 问答正确性：`我最近读到哪了？` → 「我最近阅读的书籍是《sakura_test_novel》和《插图测试书》。」（确实来自阅读快照）；`鼓励我坚持阅读` → 通顺的中文鼓励语。
- 重启 App 后模式仍是「本地模型」，对话页标题显示「AI 阅读助手 · 本地模型」。
- **release（R8 混淆 + 裁剪）包同样可用**：`flutter build apk --release --target-platform android-x64` 装上模拟器后，本地模型问答正常（「我最近读到哪了？」→ 同上）；arm64 分发包 **48.5 MB**（debug 包 131.7 MB），说明 proguard keep 规则确实保住了 JNI 侧要反射的类。

### 打包体积

| 产物 | 体积 |
| --- | --- |
| `flutter build apk --release`（默认 arm64-v8a） | 48.5 MB |
| `--target-platform android-x64`（模拟器验证包） | 50.2 MB |
| debug 包 | 131.7 MB |

模型不随包分发（按需下载 521 MB），所以装完不下载模型时只多了 MediaPipe AAR 的 ~5 MB。
注意 `--split-per-abi` 在本项目**不能直接用**：`androidComponents` 里的 ABI 收窄逻辑会与 AGP 的分包打架，把 x86_64 / v7a 分片剔成空壳（25 MB、无 `.so`）。已在 build.gradle.kts 里检测 `-Psplit-per-abi` 时跳过收窄。



## 八、酷安评论区第二轮（12 条）

来源：酷安 / 小红书「樱读」v1.2.4 帖评论区（43 条回复），按「能直接做的先做、做不了的说明原因」处理。

| # | 反馈原文（整理） | 处理 |
| --- | --- | --- |
| 1 | 「能不能把宠物设置可以关闭」 | **已做**：看板娘面板新增「在屏幕上显示桌宠」总开关，关掉后所有页面都不再出现，亲密度/点心照常累计 |
| 2 | 「书源搜索能不能设置线程，搜索太慢了」 | **已做**：设置 → 书源 → 「搜索并发数」1~16（默认 8），立即作用于全部在线搜索 |
| 3 | 书籍详情页排版太丑（附「阅读」详情页截图供借鉴） | **已做**：四宫格快捷入口（目录 / 换源 / 缓存 / 进度）+ 全宽「继续阅读」主按钮；「目录」格直接滚到章节区 |
| 4 | 「朗读能设置成文字自动跟随吗，现在虽然有这个设置选项但文字不能跟随」 | **已做**：分页模式下朗读推进时原本只改页码变量、不翻页；现在通过 `_PagedReaderState.jumpToIndex` 真正翻到朗读所在页（滚动模式本来就跟随） |
| 5 | 「不能自己选择男声和女声朗读」 | **部分做**：朗读设置新增「音色」预设（女声 1.15 / 原声 1.0 / 男声 0.85，走音调）。内置离线模型是单说话人，真正的男女声需要换多说话人模型或调用系统 TTS 的不同 voice |
| 6 | 「倍速能加到 3 倍吗」 | **已做**：语速上限 2.0 → 3.0（滑杆 25 档） |
| 7 | 「书架里的书籍可以批量删除吗？或者全选、部分选中部分删除」 | **已做**：排列面板 → 「批量管理 · 多选删除 / 分组」，支持全选 / 反选、批量删除（可选同时删本地文件） |
| 8 | 「书架里的书籍可以分组吗自定义分组」 | **已做**：书菜单 / 批量管理里设置分组，书架顶部出现「全部 / 未分组 / 各分组」筛选条 |
| 9 | 「目录向下翻没有侧边滑轨栏，几千章要滑好久」 | **已做**：目录面板右侧常驻滚动条（可拖动、超过 30 章才显示）+ 顶部「跳到第几章」输入框（60 章以上出现） |
| 10 | 「阅读时设置能自动隐藏或是不挡着字」 | **待澄清**：现有设置面板是底部半屏，正文在上半屏仍可见；如果想「点一下设置就自动隐藏、只留一条把手」可以再做 |
| 11 | 「能不能删除的时候直接删本地文件」 | **此前版本已做**：删除对话框里勾选「同时删除本地文件」 |
| 12 | 「添加键和设置重合，容易误触」 | **v1.2.3 已修**：FAB 抬到导航栏之上 |

### 说明：本轮没有做的

- **WebDAV / 其他备份**：技术上可行（`http` 已够用，打包 zip + PROPFIND/PUT），但要先定「备什么」（书架 + 进度 + 书源 + 设置）和「备到哪」（坚果云 / Nextcloud / WebDAV 自建），并且需要真实账号联调，工作量约 1~2 天。
- **导入「阅读」(legado) 的书架/进度**：这类备份 JSON 里只有 `bookSourceUrl` + 书名 + 进度，没有正文；只有在用户导入过同一份书源时才可能对上章节，属于「能对上就导入、对不上只能占位」。做过调研但没实装，因为对不上的比例会很高，容易变成「导进来一堆点开没内容的书」。
- **AI 分角色朗读（番茄式）**：可以做，但依赖两件事：一是把章节切出「旁白 / 台词」并标注说话人（X-Ray 已经能给出人名表，可以复用），二是多音色 TTS。建议先做「规则版」（引号内 = 台词，用不同音调），再考虑接 AI。
- **磨砂（frosted glass）观感**：`BackdropFilter` 在低端机上掉帧明显，和上一轮「卡顿」的投诉冲突。如果要做，建议做成「磨砂开关 + 默认关」，并在设置里提示性能代价。

## 九、第三轮：用户确认后新增的 7 项

上一轮结尾列了「本轮没做」的四项，作者确认全做（「WebDAV 备份方案你定，本地备份也一起做，导入「阅读」书架也要做，AI 分角色朗读可以做，磨砂观感可以做，男/女声做，可以给更多语言模型让用户自己可选择下载」），并追加了「搜索并发数改无上限」。

| # | 需求 | 处理 |
| --- | --- | --- |
| 1 | 搜索并发数不设上限，用户自己填 | **已做**：滑杆 1~32，另加「自定义（最多 999）」输入框；并发数越大越吃网络与内存，界面已提示「调大更快，弱网时容易失败」 |
| 2 | 本地备份 | **已做**：设置 → 数据 → 备份与恢复，一键打出 zip（书架 / 进度 / 书签 / 设置 / 书源 / 桌宠 / 阅读统计 / 统计曲线），存到 `Download/sakura-backup-<时间>.zip`，列表可直接恢复（恢复前自动把旧数据改名 `.bak`） |
| 3 | WebDAV 备份 | **已做**：备份页第二张卡片，填地址 / 账号 / 密码 / 目录后「测试连接」「上传备份」「从 WebDAV 恢复」；兼容坚果云、Nextcloud、群晖等标准 WebDAV |
| 4 | 导入「阅读」(legado) 书架 | **已做**：设置 → 数据 → 从「阅读」导入；支持 `.zip` / `.json` 备份，按「书名 + 作者」打分匹配本地与在线书源，匹配到的自动入架并带上书名作者，匹配不到的明确列出来（不再出现「导进来一堆点开没内容」） |
| 5 | AI 分角色朗读 | **已做**：完全本地的规则版——引号内算对白、「人名：」前缀认说话人、旁白与不同角色用不同音调，同一角色全书保持一致；不联网、不花 token。设置 → 朗读 → 「AI 分角色朗读」 |
| 6 | 磨砂观感 | **已做**：设置 → 外观 → 「磨砂玻璃」开关，打开后阅读页顶栏 / 底栏用 `BackdropFilter` 实时模糊透出正文；默认关闭，说明里标注「低端机上会略耗电」 |
| 7 | 男 / 女声 | **已做（已升级，见第十节）**：最初用「音调预设」模拟；现在改成真正换模型——设置 → 朗读 → 「语音包」可下载 174 人的「百变音色」或 14 MB 的「小雅」，音色是模型自带的，不再是变调 |
| 8 | 给更多本地模型让用户自己选下载 | **已做**：AI 设置里的本地模型从固定一个改成可选清单（Qwen2.5-0.5B / 1.5B / 3B、DeepSeek-R1-Distill-Qwen-1.5B），显示体积与「适合机型」，用哪个下哪个，可单独删除 |

### 验证

- `flutter analyze`：No issues found
- `flutter test`：398 项全过（新增 `tts_role_test`、`glass_bar_test`、`legado_import_test` 等）
- MuMu 模拟器（Android 15，900×1600）实测：本地备份生成 12 个文件的 zip、恢复后书架与进度一致；WebDAV 用本地 node 起的 WebDAV 服务器走通「测试连接 / 上传 / 从远端恢复」；legado 备份导入把 3 本书入架、2 本匹配不到单独列出；分角色朗读逐段音调不同；磨砂开关切换后顶栏底板半透明（`BackdropFilter`）；音色切「男声」后重进应用仍是男声（`ttsVoiceStyle` 已持久化）

## 十、第四轮：语音包可选下载 + 坚果云本地登录

作者指出两件事：①「提供更多本地模型让用户自己选下载」说的是**语音模型**，内置只有一个音色确实太单调，应该让用户自己下载；②坚果云那套「手填地址 + 应用密码」太绕，改成可以本地登录。

### 1. 语音包（音色）可选下载

| 语音包 | 体积 | 说明 |
| --- | --- | --- |
| 超文（内置） | 随 APK 约 20 MB | 单说话人女声，装好就能读，不下载任何东西 |
| 百变音色（174 人） | 32 MB（解压约 204 MB） | aishell3 174 个说话人，预设「男声·低沉 / 男声·清亮 / 女声·温和 / 女声·明亮」 |
| 小雅 | 14 MB | piper 小雅，年轻女声，体积最小 |

- 列表里显示体积、当前使用中（✓）与「删除」，下载有进度条 + 「下载完成，正在解压…」状态，出错给中文原因；
- 下载走 `gh-proxy.com` 优先、GitHub 直连兜底，先落 `<id>.download` 校验字节数再解压；
- 解压是流式（`BZip2Decoder().decodeLazy` + 手写 tar 头解析，64 KB 分块写盘）：aishell3 解压后 204 MB，一次性读进内存会 OOM；
- 换包时 `OfflineTts.configureVoice()` 重启推理 isolate 指向新模型；换说话人只传 `sid`，不用重启；
- 删除当前包会自动回到内置超文，不会变成「没有语音」。

### 2. 坚果云本地登录

- 备份页 WebDAV 卡片顶部新增「用坚果云账号直接登录」+「获取应用密码」两个按钮；
- 先拿账号密码试一次 WebDAV（部分账号/企业账号登录密码可直接用）；
- 不通过就打开浏览器登录坚果云「安全选项 → 添加应用」，回来后弹框粘贴应用密码，立刻再验；
- 密码只存这台手机（`webdavPass`），不上传任何地方；全程不做网页模拟登录（坚果云登录页有 CSRF + 验证码，硬抓接口既容易失效也容易让用户怀疑偷密码）。

### 验证

- `flutter analyze`：No issues found；`flutter test`：416 项全过（新增 `tts_voice_pack_test` 12 例、`jianguoyun_login_test` 9 例）
- 设备（MuMu Android 15，127.0.0.1:16384）实测：
  - 小雅 14 MB 下载 → 自动切换 → 「测试朗读」出声（logcat `AudioTrack: 87267 frames`）；
  - 百变音色 32 MB 下载 → 解压 204 MB 未 OOM → 切「男声·清亮」出声（30614 frames）；
  - 切包实证：`[offline-tts] loading model: /data/user/0/com.operit.sakuraread/files/tts/aishell3/model.onnx`，切回内置变成 `.../files/tts/chaowen/zh_CN-chaowen-medium.onnx`；
  - 坚果云登录输错密码 → 真实 401 → 自动跳浏览器打开安全选项页 → 回来弹「还需要应用密码」→ 取消后按钮恢复可点，并提示「坚果云 WebDAV 需要用「应用密码」，去安全选项生成一个吧」。
