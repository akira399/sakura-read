# 樱读 · 书源系统规划（兼容阅读 3.0）

> 状态：**草案 v0.1 · 待拍板**（已对照 Legado 真实源码核对字段与机制）

---

## 1. 目标

1. **直接导入阅读 3.0（Legado）书源 JSON**，无需转换；
2. 打通全流程：**搜索 → 详情 → 目录 → 正文 → 阅读**；
3. 行为对齐：同一书源在樱读与 Legado 得到**相近结果**（以"行为测试"验收）；
4. 分阶段交付，每阶段 `flutter analyze` 0 问题 + 全测试绿 + 真机可验。

## 2. 兼容性矩阵（对照 Legado 实际能力）

| Legado 能力 | 樱读计划 | 备注 |
|---|---|---|
| 书源 JSON 全部字段 | ✅ 解析并存储 | 未知字段保留（向前兼容） |
| CSS 规则（默认模式） | ✅ | Dart `html` 包 + 选择器增强 |
| XPath 规则 | ✅ | `xml` 包 XPath |
| JSONPath 规则（含 Legado 扩展） | ✅ | 独立实现（`[*]`、`@` 后缀等） |
| 正则规则 | ✅ | `RegExp` |
| `##` 替换链 / `{{}}` 模板 | ✅ | 对照 RuleAnalyzer / AnalyzeUrl 语义 |
| 编码探测（GBK 等） | ✅ | 复用 `fast_gbk` + 探测 |
| Header / POST / Cookie | ✅ | 自建请求层 |
| `@js` / `loginCheckJs` / `webJs` | ⏳ **Phase 2 评估** | 规则层 JS 引擎待评估；正文级 JS 反爬已由 M3 隐藏 WebView 解决 |
| exploreUrl 分类发现 | ⏳ M4 | 可选 |
| concurrentRate 限流 | ✅ 简易实现 | 单源每秒请求数限制 |
| bookSourceType=0 小说文本源 | ✅ | 漫画 / 音频 / 视频源**不做** |
| 登录 / 代理 | ✘ 明确不做 | 文档中说明边界 |
| JS 渲染阅读（隐藏 WebView） | ✅ **M3 落地** | 1×1 像素隐藏 WebView 渲染令牌墙 / SPA 页面后抽取正文（`webview_engine.dart`） |

> 预期覆盖率：**无 JS 的纯文本小说源 ≳ 70%**（M2 阶段用真实源抽样统计后再决定 JS 引擎投入）。

## 3. 核心数据结构（已对照 Legado 源码逐字段核对）

**BookSource 顶层**：`bookSourceUrl / bookSourceName / bookSourceGroup / bookSourceType / bookUrlPattern / customOrder / enabled / enabledExplore / enabledCookieJar / concurrentRate / header / loginUrl / loginUi / loginCheckJs / bookSourceComment / variableComment / lastUpdateTime / respondTime / weight / exploreUrl / ruleExplore / searchUrl / ruleSearch / ruleBookInfo / ruleToc / ruleContent`

**SearchRule**：`checkKeyWord / bookList / name / author / intro / kind / lastChapter / updateTime / bookUrl / coverUrl / wordCount`

**BookInfoRule**：`init / name / author / intro / kind / lastChapter / updateTime / coverUrl / tocUrl / wordCount / canReName / downloadUrls`

**TocRule**：`preUpdateJs / chapterList / chapterName / chapterUrl / isVolume / isVip / isPay / updateTime / nextTocUrl`

**ContentRule**：`content / nextContentUrl / webJs / sourceRegex / replaceRegex / imageStyle / payAction`

**分析引擎机制（AnalyzeRule.kt 实测）**：规则模式按前缀分派——`@json:` → JSONPath、`@xpath:` → XPath、`@css:` → CSS、其余默认 CSS/正则；结果经 `replaceRegex`（`##` 链）后处理；URL 经模板渲染（`{{key}}`、`{{page}}`、`{{...}}` 编码）。

## 4. 架构设计

```
lib/src/source/
├── models.dart          # BookSource / SearchRule / ... / SearchBook / OnlineToc / OnlineChapter
├── rule_analyzer.dart   # 规则拆分：|| 组合、## 替换链、{{}} 模板、@ 后缀
├── analyze_rule.dart    # 核心求值器：Mode 分派 + 后处理（对照 AnalyzeRule 行为）
├── analyze_css.dart     # CSS 分析（对照 AnalyzeByJSoup 语义）
├── analyze_json.dart    # JSONPath（Legado 扩展语法）
├── analyze_xpath.dart   # XPath 分析
├── analyze_regex.dart   # 正则分析
├── analyze_url.dart     # URL 模板分析（对照 AnalyzeUrl）
├── http_client.dart     # 请求层：超时 / 重试 / 编码 / Cookie / 限流
├── source_store.dart    # 书源导入导出 + 持久化（JSON 文件）
└── online_repo.dart     # 搜索/详情/目录/正文 聚合（多源并发）

lib/src/ui/source/
├── source_manager_page.dart   # 书源管理（启用/删除/分组/排序）
├── source_import.dart         # 导入（文件/粘贴/网络订阅链接）
├── source_search_page.dart    # 在线搜索（多源并发 + 结果列表）
└── online_book_page.dart      # 在线书籍详情（加入书架）
```

**阅读器接入**：新增 `content_provider` 抽象——
- `LocalContentProvider`（现有 TXT/EPUB 逻辑）；
- `OnlineContentProvider`（章节文本按需拉取 + LRU/磁盘缓存）；
- 阅读器与书架感知两种来源，进度 = `章节序号 + 章内偏移`。

## 5. 数据流

```
搜索:  关键词 ─→ 每源 searchUrl 渲染 ─→ HTTP ─→ ruleSearch.bookList ─→ [SearchBook]
详情:  bookUrl ─→ ruleBookInfo(init/name/author/../tocUrl) ─→ BookInfo
目录:  tocUrl ─→ ruleToc.chapterList ─→ [章节名, chapterUrl]
正文:  chapterUrl ─→ ruleContent.content(+nextContentUrl 续页) ─→ 文本 ─→ 现有分页器渲染
```

## 6. 分期计划（每期独立可验）

| 期 | 交付物 | 验收标准 |
|---|---|---|
| **M1 规则引擎**（纯内部，不动 UI） | models + 5 类分析器 + 替换链/模板 | 夹具测试 30+ 例全绿：给定 HTML/JSON 输入，输出与预期一致 |
| **M2 书源管理 + 搜索** | 导入（文件/粘贴/订阅）、管理页、搜索页（多源并发 8、单源 15s 超时、错误隔离） | 真机：导入真实源 → 搜索出书 → 列表展示 |
| **M3 在线阅读** | 详情/目录/正文 + 加入书架 + 断点续读 + 缓存 | 真机：搜到书 → 加书架 → 读到第 N 章 → 重进续读 |
| **M4 打磨** | 发现页、订阅源市场、响应速度统计、JS 支持评估 | 回归全绿 + 覆盖率报告 |

> **进度（2026-09-20）**：M1 规则引擎已落地 —— `lib/src/source/` 8 个文件（models / rule_analyzer / analyze_rule / analyze_css / analyze_json / analyze_xpath / analyze_regex / analyze_url），`test/source_engine_test.dart` **45 项夹具测试全绿**，`flutter analyze` 0 问题。
>
> **进度（2026-09-21）**：**M2 已实现（待真机验收）** —— 新增 请求层（超时/编码探测/Cookie/限流/`preRequest` 预热请求扩展）、书源仓库（导入·导出·持久化）、多源并发搜索（8 并发、15s 单源超时、错误隔离）、书源管理页与在线搜索页；**内置源方案 A 首次落地**（笔趣阁 bqgiu.cc，真实响应夹具测试通过）。
>
> **进度（2026-09-21 · v1.2.0）**：**M3 已落地** —— ①隐藏 WebView 正文引擎（`webview_engine.dart`：1×1 宿主 / 桌面 UA 规避移动版重定向 / 轮询抽取）；②在线服务层（`online_book_service.dart`：详情 OG meta、目录解析 + JS 伪链接过滤、`/userverify` 网关重写、正文清洗）；③在线书详情页（封面·简介·目录·加入书架·开始阅读；`BookFormat.online` + `sourceUrl` 数据模型扩展）；④内置源升级为 **hkmtxt + bqgiu 双源全规则**（2079 章真实夹具验证）；⑤内置源随版本自动更新（保留用户启停状态）。90 项测试全绿，`flutter analyze` 0 问题。
>
> **进度（2026-09-21 · v1.2.1）**：体验优化 —— ①多源搜索结果合并（同名同作者合并为一条 · 详情页书源切换 · 已在架书一键换源，保留进度并清空旧源章节缓存）；②阅读器页面改为全屏出血（根治覆盖翻页时屏幕左右两侧静止的空白缝，与阅读 3.0 翻页视觉对齐）。
>
> **进度（2026-09-21 · v1.2.2）**：换源全打通 + 搜索排序 —— ①搜索相关性排序（完全书名 > 前缀派生 > 包含 > 作者匹配，无关书沉底）；②通用换源面板（自动用书名搜索候选、按相关性排序、切前校验目录、保留进度）；③换源入口三处：搜索详情页 / 书架详情页 / 阅读器底栏（换源后自动清缓存重载当前章）。
>
> **进度（2026-09-21 · v1.2.3）**：全局体验 —— ①书架搜索界面新增「在线搜书」按钮（关键词直接带到在线搜索，书架搜索保留在下层，返回即切回）；②设置页新增日/夜快速切换悬浮按钮（"跟随系统"时按当前实际外观翻转）；③全局主题覆盖补全：权限引导页 / 开屏页深色适配、系统状态栏图标色随主题、关于卡版本号勘误。
>
> **进度（2026-09-21 · v1.2.4）**：阅读体验收尾 + 记录 —— ①阅读设置面板（阅读器底栏「设置」）新增**浅色/夜间一键切换**：切换时阅读背景与全局主题**同步**变化，且记住日间背景（`lightBgIndex`）供切回；②**书签**：阅读器底栏「书签」入口（添加当前位置 / 列表 / 跳回定位 / 删除，同位置 ±12 字符判重），设置页新增「我的书签」跨书列表；③**阅读统计**：阅读器前台活跃计时（30 秒结算一次、单次 ≤90 秒防挂机），统计页展示累计时长 / 最近 7 天柱状图 / 连续天数 / 读完书数；④删书自动清理该书书签；⑤新增 10 项 bookmarks/stats 单测（累计 102 项）。
>
> **进度（2026-09-21 · v1.2.5）**：**书架排列方式全面升级** —— ①排序方式从 3 种扩展到 **6 种**（最近阅读 / 添加时间 / 书名 / 作者 / 阅读进度 / 字数，新增的后三种带合理默认方向）；②支持 **正序 / 倒序** 方向切换（连点同一排序方式或点方向按钮）；③显示样式 **3 种**（网格 / 小图 / 列表——列表模式含封面、章节数、字数、阅读状态等信息）；④全部选择持久化记忆（`shelfSort` / `shelfAscending` / `shelfView`）；⑤新增 8 项 shelf_sort 单测（累计 110 项）。
>
> **进度（2026-09-21 · v1.2.6）**：**桌宠 + 亲密度养成系统** —— ①全局悬浮 Q 版桌宠（`PetOverlay` 挂载于 MaterialApp 层）：可拖动 + 松手吸边 + 位置记忆 + 呼吸浮动；点击换表情/台词并 +1 亲密度，长按打开养成面板；开屏 / 权限页 / 阅读器内自动隐藏（阅读中静默积累收益）；②**亲密度 7 级**（初遇 → 挚爱，阈值 0/30/90/200/400/700/1200）；点击互动每日上限 20 防刷；③**点心系统**：4 种食物（樱饼/团子/大福/蛋糕，投喂 +5/+8/+12/+20），只靠阅读时长兑换（20min/1h/5h/20h 档位，增量式不重复发放），每天首次阅读送团子，到手时桌宠主动冒泡；④点心盒面板：库存 / 投喂 / 统计（互动数、投喂数、获得总数）/ 桌宠归位；⑤设置页新增「看板娘」卡片入口；⑥修复测试工具图标幂等性（内容不变不重写，避免每次跑测试刷新 512 预览图时间戳）；⑦新增 13 项 pet_store 单测（**累计 123 项**）。
>
> **进度（2026-09-21 · v1.2.7）**：**桌宠深化（M6-A 第一批）** —— ①**透明立绘**：算法抠图工具（`tool/make_pet_cutouts.dart`，洪泛填充 + 边缘羽化）把 6 张看板娘图去背景，输出透明 PNG（`pet_*.png`），桌宠/空书架/设置页/关于卡全部换装，只显示人物本身；VLM 质检 9/10 分；②**双击摸头**：+2 亲密度（每日上限 10，独立计数）+ 害羞差分 + 专属台词；③**等级台词**：7 档 × 3 句 = 21 句台词随亲密度分档（初遇客气 → 挚爱亲昵），点击时按等级抽取；④**书架左上角表情切换入口移除**（互动统一收进桌宠，头像改为装饰），清理 `kanban_sheet.dart`；⑤新增 1 项摸头单测（**累计 124 项**）。
>
> **进度（2026-09-21 · v1.2.8）**：**桌宠修复 + 打瞌睡（M6-A 第二批）** —— ①**修复桌宠黑圈**：原容器矩形投影改为**轮廓阴影**（同立绘染黑 + 高斯模糊，形状跟随人物剪影）；②**修复开屏提前出现**：桌宠显示门槛改为"开屏结束 **且** 权限就绪"双条件（`petMarkSplashDone` + `petMarkHomeReady`），开屏动画期间不再提前出现；③**打瞌睡系统**：深夜时段（23:00~6:00）或白天 ≥5 分钟无互动 → 自动切换睡容差分；任一互动（点击/摸头/长按）自动"叫醒"；④新增 2 项打瞌睡单测（**累计 126 项**）。
>
> **进度（2026-09-21 · v1.2.9）**：**桌宠互动反馈升级（M6-A 第三批）** —— ①**升级/投喂庆祝**：亲密度升级或投喂点心时，桌宠弹跳（缩放 1→1.12 + easeOutBack）+ 切换开心差分 + 专属台词；②**点击小跳 / 拖拽摇晃**：点击时轻量弹跳反馈；拖动中桌宠按水平方向倾斜（±0.2 rad），松手回正 + 落地小跳；③**摸头飘心**：双击摸头时从头顶飘出 3 颗粉心（上飘 + 淡出 0.9s）；④**时段问候**：进入后首次出现时按当前时段打招呼（清晨/上午/午后/下午/晚上/深夜共 6 档）；⑤修复时段问候 Timer 未取消导致的测试挂起；⑥新增 1 项时段问候单测（**累计 127 项**）。
>
> **进度（2026-09-21 · v1.2.10）**：**桌宠出界修复** —— 用户反馈"点击时桌宠有时跳出屏幕外"（贴右边缘时弹跳缩放向右扩张 + 台词气泡向右生长，全部朝屏幕外）。三处修复：①移动范围留 8px 安全边距（容纳弹跳扩张量）；②弹跳缩放锚点贴边自适应（贴右锚右缘→向屏幕内扩张，贴左同理）；③贴边时定位锚点切换（`Positioned.right`）+ 台词气泡反向生长（`CrossAxisAlignment` 与 margin 跟随），气泡永远朝屏幕内；④顺手修复 3 个持久化单测的时序脆弱（固定 sleep 等防抖 → `debugFlush()` 确定性落盘）。测试**累计 127 项**全绿。
>
> **进度（2026-09-21 · v1.3.0）**：**朗读（TTS）上线（M6-D 第一批）** —— ①**原生 TTS 通道**：`MainActivity.kt` 新增 `ttsInit/ttsSpeak/ttsStop/ttsSetRate/ttsSetPitch/ttsEngines/ttsState` 等接口（标准 `android.speech.tts.TextToSpeech`），中文优先（`zh-CN` → `zh` 回退），播报进度经 `UtteranceProgressListener` 回传 Dart；②**`TtsService`（Dart 封装）**：按段落朗读（播完自动下一段）、播放/暂停/停止、上/下一段、语速与音调实时调节；③**朗读分段算法** `splitForSpeechWithOffsets`：按行切分 → 合并短行（≤200 字）→ 超长行按中文标点断句，并保留**原文偏移**用于自动跟随；④**阅读器集成**：底栏新增「朗读」入口（当前阅读位置起读）+ 悬浮朗读控制条（进度 / 上一段 / 暂停 / 下一段 / 语速音调 / 退出）；⑤**自动跟随**：朗读推进时自动翻页 / 滚动到正在读的位置；⑥**章节连播**：读完整章自动进入下一章继续朗读；⑦**引擎缺失引导**：设备无可用语音引擎时给出可操作的安装提示；⑧设置持久化（语速 / 音调 / 自动跟随 / 自动连播）；⑨新增 9 项 TTS 分段单测（**累计 136 项**）。
>
> 注：本机（OPPO/ColorOS）实测存在 `com.oplus.ttsaccessibilityengine` 引擎但未设为默认，App 会主动初始化并给出引导。
>
> **进度（2026-09-22 · v1.3.1）**：**桌宠自由拖动 + 生气系统 + 隐藏彩蛋** —— ①**去掉自动贴边**（原来松手会吸附左右边缘）：现在想拖到哪就停在哪，完全自由；②**拖动台词**：放下时随机说一句（9 句池，如"呜哇——！别晃了别晃了""放、放我下来啦……"）；③**点击随机蹦跳**：点击时在屏幕内做弧线弹跳（距离 40~180px 随机、方向随机、带抛物线，约 180ms），并配 8 句可爱台词（"哎哟！""嘿咻～"），频次比之前高很多；④**生气系统**（`pet_mood.dart` 状态机，可单测）：拖动（35% 概率）/ 睡觉被叫醒（**必定**）/ 频繁点击（6 秒内 5 次）→ 触发**生气差分**（新增 AI 生成素材 `pet_angry.png`）＋对应生气台词池；⑤**隐藏彩蛋**：生气**第二次及以上**按概率（2 次 60% / 3 次起 85%）进入——全屏**黑幕锁定**，正中只有阴沉脸桌宠（新增 `pet_rage.png`，缓慢呼吸 + 幽暗红晕），对话框"你以为我是好惹的？"，下方**鲜红血字**"小樱禁止你使用该软件，只有重启才能恢复正常"；彩蛋层拦截所有手势 + `PopScope` 禁止返回键 → 真正只有重启才能脱离；⑥新增 13 项 PetMood 单测（**累计 149 项**）。

## 7. 测试策略

- **夹具驱动**：`test/fixtures/source/` 存放「真实书源节选 + 对应固定响应（HTML/JSON）」→ **离线全链路测试**（不依赖网络）；
- 每分析器 ≥8 例单测（含中文站点、GBK、相对链接、多结果、空结果）；
- 端到端：一个"本地 mock 书源"（指向测试夹具"站点"）跑 搜索→阅读 全链路；
- 真机：由你连 2~3 个真实源做人工回归。

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| JS 规则源占比不明 | M2 抽样统计；引擎选项：`flutter_js`(QuickJS) 或纯 Dart 子集翻译——**待评估后再定** |
| ARM64 环境原生插件编译 | 优先选**纯 Dart**方案；如需原生（JS 引擎）先在环境里做可行性验证 |
| 站点反爬/Cloudflare | 不做对抗（文档写明边界，源失效属常态） |
| 多源并发风暴 | 全局并发上限 + 单源限流 + 超时隔离 |
| 书源 JSON 变体多 | 解析器容错：空字段/未知字段/类型混用全兼容 |

## 9. 许可与合规

- 只借鉴 **公开数据格式（书源 JSON schema）与可观察行为**；**不复制 Legado（GPLv3）代码文本**，引擎为独立 Dart 重写，以"行为一致"验收；
- 软件**不捆绑、不分发**任何内容源的内容；书源由用户自行导入（与 Legado 生态一致）；
- README 将说明：樱读仅提供"阅读工具"，第三方书源内容与本项目无关。

## 10. 待拍板决策点（3 个）

1. **内置书源方案**：
   - A：硬内置几个站点源（最方便，法律/维护风险高）；
   - B：**内置"推荐源订阅链接"**，首启一键导入（推荐，与生态一致）；
   - C：完全空置，用户自行导入。
2. **JS 规则策略**：默认路线 = **M1–M4 先做"无 JS 核心"**，M4 用实测数据决定是否引入 JS 引擎（避免 JS 拖垮整个工期）。
3. **分期确认**：同意按 M1→M2→M3→M4 推进（每期全绿再进下一期）？

---

*参考源码（已拉取，用于核对行为，不入库）：`/tmp/legado_src/` 下 BookSource / SearchRule / BookInfoRule / TocRule / ContentRule / ExploreRule / AnalyzeRule / AnalyzeUrl / AnalyzeByJSoup / AnalyzeByJSonPath / AnalyzeByXPath / AnalyzeByRegex / RuleAnalyzer。*