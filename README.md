# 樱读（Sakura Read）

二次元风格的 Android 小说阅读器：支持 TXT / EPUB 本地阅读；兼容「阅读 3.0」书源，搜书 → 详情 → 目录 → 正文全链路在线阅读。基于 Flutter 构建。

🎀 **自带看板娘**：粉发少女——Q 版 App 图标、樱花树下开屏立绘、空书架互动表情包、时段问候语、6 张 AI 场景默认封面，全部由 AI 素材管线产出（详见下文）。

## 功能一览

- **书架**：网格封面（真实封面 / 6 张 AI 场景默认封面按书名稳定分配）、阅读进度胶囊、搜索、各类排列方式、长按菜单、最近阅读；顶部看板娘头像（点按换台词）+ 时段问候语
  - **排列方式**（右上角「≡」图标）：6 种排序（最近阅读 / 添加时间 / 书名 / 作者 / 阅读进度 / 字数）× 正序 / 倒序 × 3 种样式（网格 / 小图 / 列表），选择自动记忆
- **朗读（TTS）**：系统语音合成朗读正文——按段落播报、播放/暂停/停止、上/下一段、语速与音调可调；朗读时自动跟随（翻页/滚动到正在读的位置）；读完整章自动连播下一章；无可用引擎时给出安装引导
- **看板娘桌宠**（全局悬浮）：**自由拖动**（不自动贴边，拖到哪停在哪；拖动时有倾斜摇晃 + 落地小跳 + 随机台词）、位置记忆、呼吸浮动动画；**点击**在屏幕内随机弧线蹦跳 + 可爱台词 + 亲密度（+1）；**双击**摸头（+2 亲密度 + 害羞差分 + 头顶飘心）；**长按**打开养成面板；深夜或长时间未互动自动打瞌睡（睡容差分，一碰就醒）
  - **生气系统**：拖动（**概率很低，只有频繁拖动才明显**）/ 睡觉被叫醒（必定）/ 频繁点击 → 生气差分 + 专属台词；**生气不涨亲密度**
  - **奔跑乱跑**：会自己在屏幕上到处跑（小步起伏 + 弧线路径 + 前倾），主界面低频、**阅读时高频捣乱**（配专属台词）
  - **隐藏彩蛋**：**第 4 次起**生气才有概率触发（概率随次数递增）→ 全屏黑幕锁定，阴沉脸桌宠 + "你以为我是好惹的？" + 鲜红血字"小樱禁止你使用该软件"（返回键也被拦截）
  - **透明立绘**：背景已去除（算法抠图 + 边缘羽化），只显示人物本身；轮廓阴影（非矩形投影）
  - **显示时机**：开屏动画结束 + 权限就绪后才出现（不会提前打扰开屏）
  - **阅读时也显示**：阅读设置面板 / 软件设置 都有开关（开启后她会在你书页上跑来跑去）
  - **新手引导**：首次启动小樱带着走一遍核心入口（自我介绍 → 在线搜书 → 导入本地书 → 设置），开头可跳过；不按指引点会**劝导 5 次**（语气逐次变差），**第 6 次直接锁屏**
  - **亲密度系统**：7 级阶梯（初遇 → 相识 → 书友 → 好友 → 知己 → 亲密 → 挚爱）；点击互动 +1/次（每日上限 20）；摸头 +2/次（每日上限 10）；投喂点心 +5~+20
  - **等级台词**：台词随亲密度等级分档变化（初遇时客气 → 挚爱时亲昵），共 7 档 21 句
  - **点心获取**：只靠阅读时长兑换——樱饼🍪（20 分钟）/ 团子🍡（1 小时）/ 大福🍓（5 小时）/ 蛋糕🍰（20 小时）；每天首次阅读额外送 1 个团子；点心到手桌宠主动冒泡提醒
- **导入**：内置文件浏览器多选导入；自动识别编码与章节；支持批量扫描常见目录
- **书源（阅读 3.0 兼容）**：导入书源 JSON（文件 / 粘贴 / 订阅链接）、启停 / 删除 / 导出；多源并发搜书（8 并发、单源 15s 超时、错误隔离、限流）
  - **内置源为「公版内容源」**（中文维基文库，已进入公有领域的古籍文献，CC BY-SA，无版权风险）：搜「论语」「红楼梦」「唐诗」等即可阅读；现代网文请自行导入书源
  - 历史版本内置的第三方聚合源会在升级时**自动清理**（用户自己导入的同地址源不受影响）
- **在线阅读**：搜到书 → 详情页（封面 / 作者 / 简介 / 完整目录）→ 一键加入书架 → 正文阅读；断点续读 / 进度与本地书一致；正文经隐藏浏览器渲染，可穿透 JS 令牌墙等反爬；**多源搜索结果自动合并 + 相关性排序（完全匹配优先）；搜索详情页 / 书架详情页 / 阅读器内均可一键换源（保留进度）**
- **TXT 解析**：UTF-8 / UTF-16 / GBK 自动探测；章节正则（第 N 章·回·节·卷·篇·话 + 序章 / 楔子 / 番外 + Chapter N）；正文误报防护
- **EPUB 解析**：EPUB2（NCX）/ EPUB3（nav）双目录；封面自动提取；HTML 转纯文本
- **阅读器**：
  - 四种翻页：滑动 / 覆盖（对照阅读 3.0 CoverPageDelegate 逐行移植：跟手滑出、显式裁剪、前缘 30px 渐变投影；**页面全屏出血，翻页时内容覆盖到屏幕最左 / 最右边缘**）/ 淡入 / 滚动（竖向连续）
  - 内置字体「霞鹜文楷」（LXGW WenKai Lite，OFL-1.1），另有宋体 / 黑体 / 等宽 / 系统默认
  - 字号 / 行距 / 字距 / 页边距 / 首行缩进可调；6 种阅读背景（纸白 / 米黄 / 护眼绿 / 浅灰 / 夜间 / 纯黑）
  - 页眉章节名、页脚「时间 · 页码 / 进度 · 电量」沉浸式状态信息（呼出菜单时自动淡出）
  - 跨章连页：翻越章界与常规翻页同样顺滑（相邻章节静默预加载，落稳后无痕落章）
  - 目录跳章、进度滑块、上一章 / 下一章、阅读进度自动保存、屏幕常亮
  - **日夜一键切换**（阅读设置面板内，阅读背景 + 全局主题同步、记住日间背景）
  - **书签**：收藏当前位置 / 列表查看 / 一键跳回 / 删除（同位置自动判重），设置页可跨书总览
  - **阅读统计**：累计时长 / 最近 7 天柱状图 / 连续阅读天数 / 读完书数（前台活跃计时，单次 ≤90s 防挂机）
- **外观**：樱粉 + 薰衣草主题、5 种主题色、浅 / 深 / 跟随系统（设置页悬浮按钮一键切换）、樱花花瓣飘落；**Q 版看板娘 App 图标**（自适应图标 + Android 13 主题图标）；冷启动「樱花树下美少女」开屏（赛璐璐动画风立绘 + 花瓣飘落 + 标题浮现）；**空书架互动看板娘**（点击切换 6 张 Q 版表情 + 台词气泡）
- **存储**：书架数据本地 JSON 持久化

## 技术方案

- Flutter stable + Dart 3
- 依赖：`archive`（EPUB 解包）、`xml` / `html`（EPUB 解析）、`fast_gbk`（GBK 解码）、`http`（书源网络请求）、`webview_flutter`（在线正文渲染）
- 原生桥（MethodChannel `sakuramanga/native`，见 `android/.../MainActivity.kt`）：
  - `hasStoragePermission` / `requestStoragePermission`：所有文件访问权限（Android 11+ 走系统设置页）
  - `setKeepScreenOn`：阅读时常亮（FLAG_KEEP_SCREEN_ON）
  - `getStorageRoot` / `getDirs`：存储根目录与 App 私有目录
  - `getBattery`：页脚电量（读取系统粘性广播，无需第三方插件）
- **隐藏 WebView 正文引擎**（`webview_flutter`）：App 根部挂 1×1 像素、不可交互的 WebView；打开章节页后等待 JS 跑完（令牌墙 / SPA 路由 / 加密接口全由页面自身完成），从渲染后的 DOM 抽取正文并清洗水印

## 目录结构

```
lib/
├── main.dart
└── src/
    ├── app.dart                  # MaterialApp / 主题装配
    ├── data/                     # 数据层
    │   ├── models.dart           # Book / ChapterRef 模型
    │   ├── book_store.dart       # 书架存储（JSON 持久化 + 进度）
    │   ├── book_source.dart      # TXT / EPUB 内容读取
    │   ├── txt_parser.dart       # TXT 编码探测 + 章节切分
    │   ├── epub_parser.dart      # EPUB 元数据 / 目录 / 封面 / 正文
    │   ├── paginator.dart        # 分页测量器（TextPainter 二分测量）
    │   ├── file_scan.dart        # 常见目录扫描
    │   ├── natural_sort.dart     # 自然排序（第2章 < 第10章）
    │   └── prefs.dart            # 应用与阅读设置
    ├── platform/native_bridge.dart
    ├── source/                   # 书源引擎（规则分析 / 请求层 / 并发搜索 / 详情目录解析 / 隐藏浏览器正文引擎）
    ├── theme/app_theme.dart      # 二次元主题（樱粉 + 薰衣草）
    ├── util/format.dart
    └── ui/
        ├── home_page.dart        # 底部导航（书架 / 最近 / 设置）
        ├── shelf_page.dart       # 书架 + 导入流程
        ├── book_detail_page.dart # 书籍详情（模糊封面头图）
        ├── recent_page.dart      # 最近阅读
        ├── settings_page.dart    # 设置
        ├── folder_picker_page.dart      # 内置文件浏览器
        ├── storage_permission_page.dart # 权限引导
        ├── source/               # 书源管理 / 在线搜书 / 在线书详情
        ├── widgets/              # cute.dart / sakura_petals.dart / book_cover.dart / battery_badge.dart
        └── reader/
            ├── reader_page.dart  # 沉浸式阅读器（4 种翻页模式）
            └── reader_settings_panel.dart  # 阅读设置面板

tool/
├── make_fixtures.py              # 生成测试用 TXT / EPUB 素材
├── make_icon.py                  # 生成 App 图标（legacy + 自适应 + 单色 + 启动 logo）
├── artwork/                      # AI 素材管线
│   ├── manifest_wave*.json       # 各批次生成任务（prompt / 模型 / seed / 负面词）
│   ├── prompts/                  # 提示词
│   └── src/                      # 生产用源图（如 Q 版图标源）
├── sf_batch.py                   # 硅基流动批量文生图（需自备 API Key）
├── sf_image.sh                   # 单张生成
├── vlm_look.py / vlm_compare.py  # 用视觉模型质检 / 对比素材
├── shrink_images.dart            # 素材压缩（控制 APK 体积）
└── wait_for.sh                   # 有界等待助手（检查后台任务完成）
```

## 构建与运行

> 本仓库自带的 `android/setup_android_env.sh` 可完成 Flutter / Android SDK / Gradle 环境初始化（含 ARM64 主机的模拟适配）。

```bash
bash android/setup_android_env.sh   # 1) 环境（首次）

export PATH="$HOME/flutter/bin:$PATH"
flutter pub get                     # 2) 依赖与检查
flutter analyze
flutter test

flutter build apk --release --target-platform android-arm,android-arm64   # 3) 构建 APK
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### ARM64 主机的两个已知环境补丁（本机已应用）

1. **gen_snapshot**：ARM64 主机上 Android release AOT 需要 linux-arm64 版 gen_snapshot，
   引擎包未附带，已用 box64 包装：
   `android-{arm,arm64}-release/linux-arm64/gen_snapshot` → `box64 .../linux-x64/gen_snapshot`
2. **libflutter.so 未 strip**（导致 APK 从 37MB 膨胀到 330MB+）：已对以下位置的
   `libflutter.so` 做 `strip --strip-unneeded` 替换：
   - `bin/cache/artifacts/engine/android-*-release/flutter.jar`
   - Gradle 模块缓存 `io.flutter:arm64_v8a_release` / `io.flutter:armeabi_v7a_release`

> 上述补丁作用于 **Flutter SDK / Gradle 缓存**，不在仓库内；
> 随附的 `android/tools/`（aapt2 等平台专用二进制）同样属于本机适配产物，
> 已在 `.gitignore` 中排除，**克隆仓库后无需这些文件即可在 x86_64 主机正常构建**。

### 一键发布

```bash
./tool/release.sh              # 格式化 → analyze → test → 构建 APK
./tool/release.sh --no-build   # 只跑检查与测试
```

CI（`.github/workflows/ci.yml`）会在 push / PR 时执行同样的检查并产出 APK 工件。

## 安装

>APK 位于 `Download/樱读-v1.3.5.apk`，安装后：

1. 跟随引导授予「所有文件访问」权限
2. 点「＋」导入 TXT / EPUB（或扫描常见目录）
3. 打开小说即可阅读；进度、字体、背景等会自动记录
4. 在线看书：书架「＋」→ 在线搜书 → 输入书名 → 点结果进详情页 → 「加入书架」/「开始阅读」

- 最低支持：Android 7.0（minSdk 24）
- 包名：`com.operit.sakuraread`

## 测试

- `flutter analyze`：No issues found
- `flutter test`：**164 项全部通过**
  - 桌宠状态机（`pet_mood`）：频繁点击判定、**第 4 次生气的锁屏门槛与递增概率**、拖动低概率、台词池完整性
  - 桌宠资源（`pet_store`）：亲密度 / 点心 / 每日上限 / 位置记忆 / 阅读时长兑换
  - 新手引导（`pet_guide`）：**流程长度、逐步推进、跳过、劝导 5 次、第 6 次锁屏、锚点缺失软化**
  - 内置书源合规（`source_legal_builtin`）：**只含公版源、盗版源已清除、对真实页面/接口夹具解析有效**
  - 书源升级（`source_store_legacy`）：首启全量导入、**旧盗版源自动清理（用户自建源不受影响）**、幂等、保留用户启停
  - 书源引擎：规则拆分 / CSS / JSONPath / XPath / 正则 / URL 模板 夹具测试
  - 书源网络层：编码探测 / 超时 / Cookie / 限流 / 多源并发（MockClient 离线测试）
  - TXT：UTF-8 / GBK 编码探测、章节切分、无章节回退、误报防护
  - EPUB：EPUB3 元数据 / nav 目录 / 封面 / 正文
  - 覆盖翻页像素级回归测试（钉住页裁剪 / 前缘投影）
  - 翻页吸附物理（固定速率 300ms/页、短距 110ms 收敛、无二次微调循环）
  - 应用启动 widget 测试

## 看板娘 & AI 素材

看板娘全部素材由 AI 生成管线生产（工具见 `tool/`），流程：**批量文生图 → 视觉模型质检 → 压缩入库 → 算法抠图（去背景）**。

- 生成模型：[硅基流动](https://siliconflow.cn) 平台上的 `Qwen/Qwen-Image`、`Tongyi-MAI/Z-Image(-Turbo)`、`Kwai-Kolors` 等
- 质检模型：`Qwen/Qwen3-VL-32B-Instruct`（风格核验 / 缺陷检查 / 角色一致性对比）
- 关键提示词手法：锁定「日本电视动画赛璐璐上色」+ 负面词排除「写实 / 3D / 厚涂 / 电影感」
- 素材清单：Q 版表情 ×6（含生气 / 阴沉差分）、开屏立绘 ×1、默认场景封面 ×2、桌宠透明立绘 ×8、App 图标全套（`assets/images/`）
- App 图标三层齐全：legacy 圆角方形 + 自适应前景/背景 + **Android 13+ 主题图标（monochrome 白色人物剪影）**

> 复现管线需要自备硅基流动 API Key（工具从 `/tmp/sf_key` 读取，**Key 不入库**）。

## 许可

- **代码**：MIT License（见 `LICENSE`）
- **字体**：内置「霞鹜文楷 Lite」（LXGW WenKai Lite，作者 LXGW），遵循 SIL Open Font License 1.1（全文见 `assets/fonts/OFL.txt`）
- **AI 生成素材**：由上述生成模型产出，随本仓库一并以 MIT 许可分发
- **内置书源**：仅收录**已进入公有领域**的文献索引规则（中文维基文库，内容 CC BY-SA 4.0）；
  本仓库**不内置任何有版权风险的第三方聚合书源**。用户自行导入的书源由其自行承担合规责任。
- **开源仓库**中的 `tool/artwork/candidates`、`tool/probe_out`、`tool/shots` 等**中间产物不入库**（见 `.gitignore`）
