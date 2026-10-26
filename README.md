<div align="center">

<img src="docs/images/banner.png" alt="樱读 Sakura Read" width="100%"/>

# 樱读 · Sakura Read

**在樱花树下，慢慢读完一本书。**

一款**二次元风格的 Android 小说阅读器**：本地 TXT / EPUB 阅读 + 兼容「阅读 3.0」书源的在线搜书，自带一只会撒娇、会生气、还会捣乱的**看板娘桌宠**。

[![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-lightgrey?logo=android)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Version](https://img.shields.io/badge/version-1.2.4-ec5f8f)]()
[![Tests](https://img.shields.io/badge/tests-349%20passed-brightgreen)]()
[![Analyze](https://img.shields.io/badge/analyze-0%20issues-brightgreen)]()

[功能特性](#-功能特性) · [截图预览](#-截图预览) · [下载安装](#-下载安装) · [从源码构建](#-从源码构建) · [常见问题](#-常见问题) · [更新日志](../../releases)

</div>

---

## ✨ 为什么是「樱读」？

阅读器不少，但大多数只有功能，没有"人味"。樱读往里面塞了一个小樱：

- 🎀 **她是活的** —— 一位粉发看板娘陪着你：会跟你打招呼、被你拖来拖去、看书时在你书页上跑来跑去，惹急了还会……（彩蛋自己找）
- 🌸 **她是漂亮的** —— 图标、开屏、封面、空书架，一整套日系赛璐璐上色的二次元皮肤（AI 出图 + 人工筛选）
- 📖 **她是很能干的** —— TXT / EPUB 全格式、4 种翻页、TTS 朗读（内置离线语音）、书签统计、多源搜书、一键换源，该有的一个不少
- 💬 **她还会聊天** —— 接上 AI 助手后，你可以问她「我最近读到哪了」「这本书讲了什么」，本地小模型模式下**阅读数据不出手机**
- 🔓 **她是开源的** —— MIT 协议，代码干净、测试充分（349 项自动化测试），欢迎你来改

---

## 🎀 自带看板娘「小樱」

| 能力 | 说明 |
| --- | --- |
| 🌸 **全局悬浮** | 自由拖动（拖到哪停在哪）、位置记忆、呼吸浮动，拖动时有摇晃感 + 落地小跳 + 随机台词 |
| 💬 **点击互动** | 屏幕内随机弧线蹦跳 + 可爱台词 + 亲密度 +1（每日上限 20） |
| 🫶 **双击摸头** | 害羞差分 + 头顶飘心 + 亲密度 +2（每日上限 10） |
| 😴 **打瞌睡** | 深夜时段或长时间无互动自动入睡（睡容差分），一碰就醒 |
| 😠 **生气系统** | 被反复拖动 / 睡觉被叫醒 / 频繁点击 → 生气表情 + 专属台词（**生气不涨好感度**） |
| 🏃 **奔跑乱跑** | 会自己在屏幕上到处跑（小步起伏 + 弧线路径 + 前倾），**阅读时高频捣乱** |
| 🍡 **点心投喂** | 只靠阅读时长兑换：樱饼（20 分）/ 团子（1 时）/ 大福（5 时）/ 蛋糕（20 时） |
| 💗 **亲密度 7 级** | 初遇 → 相识 → 书友 → 好友 → 知己 → 亲密 → 挚爱，台词随等级变化（7 档 21 句） |
| 🖤 **隐藏彩蛋** | 生气第 4 次起才有概率触发……触发之后嘛，自己去看（提示：返回键也没用） |

<div align="center">

<img src="docs/images/faces.png" alt="看板娘表情差分" width="96%"/>

</div>

<div align="center">
<img src="docs/images/mascot.png" alt="桌宠悬浮在书架上" width="28%"/>
&nbsp;&nbsp;
<img src="docs/images/shelf_empty.png" alt="空书架的看板娘" width="28%"/>
</div>

> 看板娘的每一次点击、每一次拖动，都可能换来一个新的表情与台词。

---

## 📖 功能特性

### 📚 书架 & 本地阅读

- **格式支持**：TXT（UTF-8 / UTF-16 / GBK 自动探测）、EPUB（EPUB2 NCX / EPUB3 nav 双目录解析 + 封面提取 + **正文插图渲染**）
- **导入方式**：内置文件浏览器多选导入、批量扫描常见目录
- **排列方式**：6 种排序（最近阅读 / 添加时间 / 书名 / 作者 / 阅读进度 / 字数）× 正序倒序 × 4 种样式（网格 / 小图 / 列表 / **大封面**）
- **移除书籍**：可选「同时删除本地文件」（默认不勾，防误删），会先显示将被删除的路径
- **智能封面**：优先真实封面；无封面时按书名稳定分配 6 张 AI 场景插画

### 📖 沉浸式阅读器

- **四种翻页**：滑动 / 覆盖（跟手滑出 + 前缘投影，对照阅读 3.0 逐行移植）/ 淡入 / 滚动
- **音量键翻页**：音量上 = 上一页、音量下 = 下一页，默认开启，只在阅读页内生效
- **排版调节**：字号 / 行距（1.0–2.6）/ 段间距 / 字距 / 页边距 / 首行缩进；内置「霞鹜文楷」字体 + 4 种备选
- **6 种背景**：纸白 / 米黄 / 护眼绿 / 浅灰 / 夜间 / 纯黑，日夜间一键切换（全局主题同步）
- **跨章连页**：翻越章界与常规翻页同样顺滑（相邻章节静默预加载）；**滚动模式同样无缝**——一直往下滑就自动接上下一章，往回滑会接回上一章
- **宽屏适配**：正文版心最宽 680 逻辑像素，平板上不会一行排到 40 多字
- **页眉页脚**：章节名 / 时间 / 页码进度 / 电量，沉浸在状态栏里
- **书签系统**：阅读器内收藏 + 设置页跨书总览 + 一键跳回
- **目录定位**：打开目录自动滚到并高亮当前章节，长书不用手动翻几十屏
- **阅读统计**：累计时长 / **阅读时长曲线（7 / 14 / 30 天可切）** / 连续阅读天数 / 读完书数

### 🔊 语音朗读（TTS）

- 系统语音合成按段落朗读，播完自动下一段
- **内置离线语音**：随包自带一份中文模型（sherpa-onnx + VITS「超文」，CC0 授权），手机没装任何系统 TTS 引擎也能朗读，离线可用、不联网
- 播放 / 暂停 / 停止、上下一段、**语速与音调实时调节**
- **朗读自动跟随**：翻页 / 滚动到正在读的位置
- **读完整章自动连播下一章**
- 系统引擎与内置语音自动择优：装了系统引擎优先用系统引擎，没有就自动接管；也能在设置里手动指定
- 无可用引擎时给出可操作的安装引导，并可直接跳到系统「文字转语音」设置页

### 🤖 AI 阅读助手（小樱）

- **在线接口**：兼容 OpenAI Chat Completions，OpenAI / DeepSeek / Kimi / 本地 Ollama 都能接，内置预设一键填好地址与模型名
- **内置本地小模型**：可选下载 **Qwen2.5-0.5B-Instruct**（q8，521 MB，Apache-2.0），用 MediaPipe LLM Inference 在手机端侧推理 —— 不联网、不花钱、阅读数据不出手机
- **下载走国内镜像**：modelscope → hf-mirror → huggingface 依次回退，带进度条、可删除模型文件
- **懂你的阅读数据**：把书架、进度、阅读时长、最近在读整理成上下文（可在设置里关掉），回答「我最近读到哪了」这类问题
- **流式输出**：逐字显示，可中途停止；本地模型首次加载约 8 秒，之后有 XNNPACK 权重缓存，再开秒进

### 🌐 在线搜书（兼容「阅读 3.0」书源）

- **书源管理**：导入 JSON（文件 / 粘贴 / 订阅链接）、启用停用、删除、导出
- **多源并发搜索**：8 并发、单源 15s 超时、错误隔离、限流
- **智能合并排序**：同名同作者结果自动合并为一条，按相关性排序（完全匹配优先）
- **一键换源**：搜索详情页 / 书架详情页 / 阅读器内三处入口，换源保留阅读进度
- **隐藏浏览器引擎**：1×1 像素的隐藏 WebView 渲染，穿透 JS 令牌墙 / SPA 路由 / 加密接口
- **内置书源**：公版内容源（中文维基文库）+ 第三方聚合源（好看吗 / 笔趣阁）
- **书源体检**：发现页把书源分成「可用 / 使用 JS 脚本（暂不支持）」，不会对着一个空列表反复点

### 🎨 外观 & 主题

- 樱粉 + 薰衣草配色，5 种主题色可选，浅色 / 深色 / 跟随系统
- 樱花花瓣飘落动画、Q 版看板娘 App 图标（含 Android 13+ 主题图标）
- 冷启动「樱花树下美少女」开屏动画

### 🔄 检查更新

- **启动自动检查**：进入主界面后台静默检查，有新版弹出「更新公告」（可关闭）
- **国内镜像下载**：gh-proxy / ghproxy / ghfast 多线路自动回退，带进度与取消
- **一键升级**：下载完成自动调起系统安装器（FileProvider 授权，不跳浏览器）
- **设置页手动检查**：失败可重试；「以后再说」的版本不再自动打扰

---

## 📸 截图预览

<div align="center">

| 首次启动 | 书架 | 阅读器（日间） | 阅读器（夜间） |
|:---:|:---:|:---:|:---:|
| <img src="docs/images/agreement.png" width="200"/> | <img src="docs/images/shelf.png" width="200"/> | <img src="docs/images/reader_day.png" width="200"/> | <img src="docs/images/reader_night.png" width="200"/> |
| 阅读排版设置 | 阅读统计（时长曲线） | 最近阅读 | 在线搜书 |
| <img src="docs/images/reader_settings.png" width="200"/> | <img src="docs/images/stats.png" width="200"/> | <img src="docs/images/recent.png" width="200"/> | <img src="docs/images/search_idle.png" width="200"/> |
| AI 助手 | AI 助手（对话） | AI 设置（本地小模型） | 设置 |
| <img src="docs/images/ai_chat.png" width="200"/> | <img src="docs/images/ai_chat_talk.png" width="200"/> | <img src="docs/images/ai_settings.png" width="200"/> | <img src="docs/images/settings.png" width="200"/> |
| 设置（开源信息） | 开屏动画 | 空书架看板娘 | 隐藏彩蛋 |
| <img src="docs/images/settings_about.png" width="200"/> | <img src="docs/images/splash.png" width="200"/> | <img src="docs/images/shelf_empty.png" width="200"/> | <img src="docs/images/egg.png" width="200"/> |

</div>

> 截图由 `tool/screenshots/` 里的离线渲染脚本生成（`flutter test tool/screenshots`），
> 每次 UI 改动重跑一遍就能保持 README 与真实界面一致。

---

## 🖼️ App 图标

<div align="center">
<img src="docs/images/icon_showcase.png" alt="图标展示" width="80%"/>
</div>

Q 版看板娘头像，三种形态（方形 / 圆角 / 圆形）+ 自适应图标（前景层 / 背景层）+ Android 13+ 主题图标（纯白剪影）。

---

## 📲 下载安装

### 直接下载 APK

前往 [Releases](../../releases/latest) 页面下载最新版 APK：

- **手机 / 平板（绝大多数设备）**：`SakuraRead-v1.2.4-arm64.apk`（约 48 MB）
- **模拟器 / x86_64 设备**：`SakuraRead-v1.2.4-x86_64.apk`

两个包签名一致，可直接覆盖安装旧版本。

> 也可以在 `Download/樱读-vX.Y.Z.apk` 找到构建产物（自行构建时）。

**系统要求**：Android 7.0（API 24）及以上

### 首次使用

1. 阅读并同意「使用条款与声明」（首启一次，说明内容来源与版权归属）
2. 跟随引导授予「所有文件访问」权限
3. 点右下角「＋」导入本地 TXT / EPUB（或扫描常见目录）
4. 在线看书：点书架右上角放大镜 → 输入书名 → 点结果进详情页 → 「加入书架」

---

## 🛠️ 从源码构建

### 环境要求

- [Flutter](https://flutter.dev) stable 分支（Dart 3）
- Android SDK + NDK
- Java 17

### 构建步骤

```bash
# 1) 拉取依赖
flutter pub get

# 2) 静态检查
flutter analyze

# 3) 运行测试（349 项）
flutter test

# 4) 构建 release APK（单架构 arm64 体积最小）
flutter build apk --release --target-platform android-arm64
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

> 一键发布脚本：`./tool/release.sh`（格式化 → 检查 → 测试 → 构建）
> CI：`.github/workflows/ci.yml` 会在 push / PR 时自动跑同样的检查并产出 APK。

---

## 🧪 测试

| 项目 | 状态 |
| --- | --- |
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ✅ **349 项全部通过** |

覆盖范围：

- **书源引擎**：规则拆分 / CSS（含 `h3@text` 这类裸标签选择器）/ JSONPath / XPath / 正则 / URL 模板夹具测试
- **书源网络层**：编码探测 / 超时 / 死连接重建与重试 / Cookie / 限流 / 多源并发（MockClient 离线）
- **内置书源**：「令牌 + POST」搜索链路（Mock 复刻站点校验）+ 4 个源的真实夹具解析
- **TXT**：编码探测、章节切分、目录误报防护（纯数字 / 缩进行内容不算章）、无章节回退
- **EPUB**：EPUB3 元数据 / nav 目录 / 封面 / 正文 / **插图抽取与渲染**
- **AI 助手**：在线接口请求体与流式解析、阅读上下文裁剪、离线错误文案、本地模型管理与下载镜像回退
- **朗读**：引擎回退链、内置离线语音资源完整性、分段剔除插图标记、语速音调
- **阅读器**：覆盖翻页像素级回归、翻页吸附物理、滚动跨章位置映射、目录定位、音量键翻页
- **桌宠**：状态机（生气门槛与概率）、亲密度、点心、每日上限、时段问候
- **新手引导**：流程推进 / 跳过 / 劝导 / 跨页锚点
- **UI 渲染**：引导层 / 彩蛋层（防止 `Positioned` 类布局崩溃回归）、书架样式、阅读时长曲线

> 另有**真实联网冒烟**（人工执行，不随 CI 跑）：
> `flutter test tool/live/live_sources_test.dart`
> README 截图也可本地重跑：`flutter test tool/screenshots`

---

## 🗂️ 项目结构

```
lib/
├── main.dart
└── src/
    ├── app.dart                  # MaterialApp / 主题装配
    ├── data/                     # 数据层（书架 / 解析 / 设置 / 桌宠 / 统计 / AI 服务 / 本地模型）
    ├── platform/                 # 原生桥（TTS / 内置离线语音 / 音量键 / 文件）
    ├── source/                   # 书源引擎（规则 / 请求 / 并发搜索 / 隐藏浏览器）
    ├── theme/app_theme.dart      # 二次元主题（樱粉 + 薰衣草）
    └── ui/                       # 页面与组件
        ├── home_page.dart        # 底部导航（毛玻璃）
        ├── shelf_page.dart       # 书架 + 导入
        ├── reader/               # 沉浸式阅读器（翻页 / 滚动跨章 / 排版 / 朗读）
        ├── ai_chat_page.dart     # AI 阅读助手（在线接口 / 本地小模型）
        ├── ai_settings_page.dart # AI 与模型管理
        ├── source/               # 书源管理 / 在线搜书 / 发现 / 在线书详情
        └── widgets/              # 桌宠 / 花瓣 / 封面 / 引导层

android/app/src/main/kotlin/.../  # MainActivity（音量键 / MediaPlayer 朗读播放）+ LocalLlmEngine.kt（MediaPipe 端侧推理）

tool/
├── screenshots/                  # README 截图生成器（离线渲染）
├── live/                         # 真实联网冒烟测试
├── make_fixtures.py              # 测试素材生成
├── artwork/                      # AI 素材管线（提示词 / 源图 / 候选）
├── sf_batch.py                   # 批量文生图（需自备 API Key）
├── vlm_look.py                   # 视觉模型质检
└── release.sh                    # 一键发布
```

---

## ❓ 常见问题

<details>
<summary><b>搜不到书 / 某本书打不开？</b></summary>

第三方书源站点经常改版、关闭或换域名，这是常态。可以：

1. 在「设置 → 书源管理」停用失效的源
2. 导入你自己的书源（支持「阅读 3.0」格式）
3. 换源：在书籍详情页 / 阅读器内一键切换到其它源
</details>

<details>
<summary><b>朗读没有声音？</b></summary>

樱读自带一份**内置离线语音**，所以即使手机没装任何 TTS 引擎也能朗读：到「设置 → 朗读」把引擎选成「内置离线语音 · 小樱」即可（首次使用会释放约 20 MB 模型，需要几秒）。

如果你更想用系统语音（音色更自然、可装第三方引擎）：在「系统设置 → 无障碍 → 文字转语音」里安装并设为默认，然后在樱读的引擎下拉里选它。检测不到系统引擎时，App 会给出安装引导，也能一键跳到系统设置页。
</details>

<details>
<summary><b>AI 助手怎么配？一定要联网吗？</b></summary>

两种模式，在「设置 → AI 助手」里二选一：

1. **在线接口**（默认）：填 OpenAI 兼容的 Base URL + API Key + 模型名即可，
   内置了 OpenAI / DeepSeek / Kimi / 本地 Ollama 的预设。
2. **内置本地模型**：点「下载模型」拉 **Qwen2.5-0.5B-Instruct**（q8，约 521 MB，
   走 modelscope 国内镜像），下载完在手机端侧推理 —— **不需要网络，阅读数据也不出手机**。
   代价是回答质量与速度不如云端大模型，且首次加载需要几秒。

不管哪种模式，AI 都能读到你的书架与阅读进度（可在设置里关掉「附带阅读数据」）。
</details>

<details>
<summary><b>导入书源成功了，但书源列表里一本书都没有？</b></summary>

先看「发现」页顶部的书源统计：如果这个源被标成「使用 JS 脚本（暂不支持）」，
说明它靠 `@js:` 脚本生成分类或书单，樱读目前还没有 JS 规则引擎，只能跳过他。
其余的书源如果列表为空，通常是站点改版导致规则失效 —— 换源或等书源作者更新。
</details>

<details>
<summary><b>安装包为什么只有 arm64 版本？</b></summary>

内置离线语音与本地小模型都要带原生库（onnxruntime / TFLite），三条 ABI 全打进包里
会到 170 MB 以上。所以 release 只发布 arm64（现在绝大多数手机都是），
原生库还做了压缩存储，安装包因此控制在 45 MB 左右。
</details>

<details>
<summary><b>不想让桌宠在阅读时跑来跑去？</b></summary>

阅读器底栏「设置」面板或软件设置页都有「阅读时显示桌宠」开关，关掉即可。
</details>

<details>
<summary><b>新手引导跳过了，还能再看吗？</b></summary>

可以。「设置 → 帮助 → 重看新手引导」随时能再看一遍（默认只在首次启动自动出现一次，右上角「跳过引导」可随时结束）。
</details>

---

## 🎨 关于美术素材

看板娘与全部插画由 **AI 生成管线**生产（见 `tool/artwork/`），流程：

**批量文生图 → 视觉模型质检 → 人工筛选 → 压缩入库 → 算法抠图（去背景）**

- 生成模型：[硅基流动](https://siliconflow.cn) 平台的 `Qwen-Image` / `Z-Image` 等
- 质检模型：`Qwen3-VL-32B-Instruct`（风格核验 / 缺陷检查 / 角色一致性）
- 风格锁定：**日本电视动画赛璐璐上色**（负面词排除「写实 / 3D / 厚涂 / 电影感」）

---

## ⚖️ 免责声明与合规

- 本项目是**阅读工具**，**不捆绑、不分发、不存储任何受版权保护的书籍内容**
- 内置书源包含公版内容源（中文维基文库，CC BY-SA）与第三方聚合源；
  **第三方源的所有内容版权归原站与原作者所有**，本项目仅提供索引与阅读工具，
  请支持正版阅读
- 用户自行导入的书源与内容，由用户自行承担相应的合规责任
- 书源 JSON 格式兼容「阅读 3.0」（Legado），**代码为独立 Dart 实现**，未复制任何 GPL 代码

---

## 🤝 参与贡献

欢迎提交 Issue 与 PR！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

- 🐛 [报告 Bug](../../issues/new)
- 💡 [功能建议](../../issues/new)
- 📖 更新日志：[CHANGELOG.md](CHANGELOG.md)

---

## 📄 许可证

- **代码**：[MIT License](LICENSE)
- **字体**：内置「霞鹜文楷 Lite」（LXGW WenKai Lite，OFL-1.1）
- **AI 生成素材**：随本仓库一并以 MIT 许可分发

---

<div align="center">

**⭐ 如果这个项目让你会心一笑，就给小樱点个 Star 吧~**

<img src="docs/images/mascot.png" width="120"/>

</div>
