<div align="center">

<img src="docs/images/banner.png" alt="樱读 Sakura Read" width="100%"/>

# 樱读 · Sakura Read

**一款有点任性的二次元小说阅读器。**

本地 TXT / EPUB 随便看，也能塞「阅读 3.0」书源联网找书；
桌宠会陪你读书，惹急了会生气，AI 助手还知道你昨天读到第几章。

[![CI](https://github.com/akira399/sakura-read/actions/workflows/ci.yml/badge.svg)](../../actions)
[![Platform](https://img.shields.io/badge/Android-7.0%2B-lightgrey?logo=android)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Version](https://img.shields.io/badge/version-1.2.4-ec5f8f)]()

[下载](#-下载) · [功能](#-能做什么) · [截图](#-看看长什么样) · [自己编译](#-自己编译) · [常见问题](#-常见问题)

</div>

---

<div align="center">

<img src="docs/images/shelf.png" width="260"/>
<img src="docs/images/reader_day.png" width="260"/>
<img src="docs/images/reader_night.png" width="260"/>

</div>

## 🍡 这是个什么 App

一个给自己看的 Android 阅读器。做它的原因很简单：手机上要么是塞满广告的阅读软件，要么是
功能强大但界面停留在十年前的「阅读」。我想要的是——字好看、翻页顺手、能听、能问 AI，
顺便养一只会闹别扭的桌宠。

所以有了樱读：MIT 协议，代码在仓库里，功能不砍、不加广告、不要账号。

## ✨ 能做什么

**读书**

- 本地 TXT / EPUB，自动识别编码、自动切章；EPUB 的插图会直接画出来
- 字号、行距、段距、字距、页边距、缩进、六种背景色，怎么舒服怎么来
- 翻页与滚动两种模式，滚到底自动接下一章，往回滑能接回上一章
- 目录打开就定位在当前章，几百章的书不用手动翻
- 页眉页脚显示章节、时间、电量；书签、阅读时长曲线（7 / 14 / 30 天）

**找书**

- 兼容「阅读 3.0」（Legado）书源：导入 JSON、多源并发搜索、同名结果自动合并
- 一键换源，换完进度还在
- 源失效了会有体检结果，不会让你对着空列表干瞪眼
- 说明一下：**靠 JS 脚本跑的书源目前不支持**，会明确标出来

**听书**

- 自带一份中文离线语音（sherpa-onnx + VITS 超文，CC0），不装任何系统 TTS 也能读
- 也可以换成系统语音，语速、音调随时调；读完自动往下章走

**聊天**

- AI 助手兼容 OpenAI 接口，DeepSeek、Kimi、本地 Ollama 都能接
- 也可以在手机上下载一个 **Qwen2.5-0.5B** 小模型，断网也能聊，阅读数据不出手机
- 它知道你书架上有哪些书、读到哪了，问「我上次读到哪」它答得上来

**细节**

- 花瓣会飘，桌面宠物会跑，长按它还会记仇（彩蛋自己找）
- 启动自动检查更新，下载走国内镜像，装完自动弹安装器
- 高刷新率开关、帧率浮层，卡不卡一眼看得出来

## 📸 看看长什么样

<div align="center">

| 书架 | 阅读（日间） | 阅读（夜间） | 排版设置 |
|:---:|:---:|:---:|:---:|
| <img src="docs/images/shelf.png" width="180"/> | <img src="docs/images/reader_day.png" width="180"/> | <img src="docs/images/reader_night.png" width="180"/> | <img src="docs/images/reader_settings.png" width="180"/> |
| 阅读统计 | 最近阅读 | 在线搜书 | AI 助手 |
| <img src="docs/images/stats.png" width="180"/> | <img src="docs/images/recent.png" width="180"/> | <img src="docs/images/search_idle.png" width="180"/> | <img src="docs/images/ai_chat.png" width="180"/> |
| AI 对话 | AI 设置 | 设置 | 关于 |
| <img src="docs/images/ai_chat_talk.png" width="180"/> | <img src="docs/images/ai_settings.png" width="180"/> | <img src="docs/images/settings.png" width="180"/> | <img src="docs/images/settings_about.png" width="180"/> |
| 开屏 | 空书架 | 首启声明 | 彩蛋 |
| <img src="docs/images/splash.png" width="180"/> | <img src="docs/images/shelf_empty.png" width="180"/> | <img src="docs/images/agreement.png" width="180"/> | <img src="docs/images/egg.png" width="180"/> |

</div>

<sub>截图不是手截的，是 `flutter test tool/screenshots` 渲染出来的，所以 UI 一改就会跟着变。</sub>

## 📥 下载

到 [Releases](../../releases/latest) 拿最新 APK：

| 包 | 适合 |
| --- | --- |
| `SakuraRead-v1.2.4-arm64.apk`（约 48 MB） | 绝大多数手机、平板 |
| `SakuraRead-v1.2.4-x86_64.apk`（约 50 MB） | 模拟器（MuMu、雷电等） |

两个包签名一致，可以直接覆盖升级。要求 **Android 7.0（API 24）** 以上。

**第一次打开**：同意使用条款 → 给「所有文件访问」权限（本机书架要靠它扫目录）→
点右下角「＋」导入 TXT / EPUB，或者点书架右上角的放大镜联网找书。

## 🔨 自己编译

需要 Flutter stable（Dart 3）、Android SDK、JDK 17。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。
`.github/workflows/ci.yml` 会在每次 push / PR 跑同样的检查并产出 APK，`tool/release.sh` 是一键发版脚本。

## 🗂 代码在哪

```
lib/src/
├── data/       # 书架、TXT/EPUB 解析、设置、阅读统计、AI 服务、本地模型
├── source/     # 书源引擎：规则拆分、请求、并发搜索、隐藏 WebView
├── platform/   # 原生桥：TTS、离线语音、音量键、文件
├── theme/      # 樱粉 + 薰衣草主题
└── ui/         # 页面：书架、发现、阅读器、AI 助手、设置、引导、桌宠
```

`android/` 里只有两件事需要原生：朗读播放（MediaPlayer）和本地模型的 MediaPipe 推理。

## ❓ 常见问题

<details>
<summary><b>某本书搜不到 / 打不开？</b></summary>

第三方书源改版、关站、换域名都是常事。先去「设置 → 书源管理」停掉失效的源，再导入新的
（支持「阅读 3.0」格式），或者在详情页直接换源。
</details>

<details>
<summary><b>朗读没声音？</b></summary>

樱读自带离线语音，手机没装任何 TTS 引擎也能读：「设置 → 朗读」里把引擎选成「内置离线语音」
即可，首次会释放约 20 MB 模型。想用系统语音就去「系统设置 → 无障碍 → 文字转语音」装一个再回来选。
</details>

<details>
<summary><b>AI 一定要联网吗？</b></summary>

不一定。在线模式填 OpenAI 兼容的地址和 Key 就行；也可以在「设置 → AI 助手」里下载
Qwen2.5-0.5B 小模型（约 521 MB，走 modelscope 国内镜像），下载完在手机本地推理，断网可用。
代价是回答质量不如云端。两种模式都能关掉「附带阅读数据」。
</details>

<details>
<summary><b>导入书源后列表是空的？</b></summary>

先看「发现」页顶部的书源状态：标了「使用 JS 脚本（暂不支持）」的源靠 `@js:` 生成目录或书单，
目前还没有 JS 引擎，只能跳过；其余为空一般是站点改版导致规则失效。
</details>

<details>
<summary><b>为什么只发 arm64？</b></summary>

离线语音和本地模型都带原生库（onnxruntime / TFLite），三个 ABI 全打进去要 170 MB 以上。
现在绝大多数手机都是 arm64，所以只发它，压缩后 48 MB 左右；模拟器用 x86_64 包。
</details>

<details>
<summary><b>引导跳过了还能再看吗？</b></summary>

能。「设置 → 帮助 → 重看新手引导」，随时重来一遍。
</details>

## 🎨 素材是怎么来的

看板娘和插画都是 AI 生成 + 人工挑的，管线在 `tool/artwork/`：
批量文生图 → 视觉模型质检（风格 / 缺陷 / 角色一致性）→ 人工筛选 → 压缩入库 → 抠图。
风格锁定在日本电视动画的赛璐璐上色，负面词里排掉了写实、3D 和厚涂。

## ⚖️ 说明

- 这是个**阅读工具**：不提供、不分发、不存储任何书籍内容
- 内置书源有公版源（中文维基文库，CC BY-SA）和第三方聚合源，第三方内容版权归原站所有
- 自己导入的书源和内容，请自行确认合规；也请尽量支持正版
- 书源 JSON 兼容「阅读 3.0」的格式，但代码是独立 Dart 实现，没有复制 Legado 的任何 GPL 代码

## 📄 许可证

代码 [MIT](LICENSE)；内置字体「霞鹜文楷 Lite」遵循 OFL-1.1；AI 生成的素材随仓库以 MIT 分发。

---

<div align="center">

<b>如果它让你多读了半小时书，就给小樱点个 Star 吧。</b>

<img src="docs/images/mascot.png" width="110"/>

</div>
