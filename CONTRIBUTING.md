# 参与开发

感谢对「樱读」感兴趣！本文档说明本地开发、验证与提交规范。

## 环境要求

| 项目 | 版本 |
|------|------|
| Flutter | stable（Dart 3.9+） |
| Android SDK | compileSdk 36 / minSdk 24 |
| Java | 17（Flutter 默认） |

```bash
flutter pub get
flutter run                      # 调试运行
flutter build apk --release --target-platform android-arm64   # 打包（见下方说明）
```

> **单架构构建**：本项目的 AOT 在低内存设备上多架构并构建容易 OOM/崩溃，
> 日常出包统一用 `--target-platform android-arm64`。

## 代码结构

```
lib/
  main.dart                  # 入口：初始化各 Store + ensureBuiltinSources
  src/
    app.dart                 # MaterialApp + 全局覆盖层（桌宠 / 引导 / 彩蛋）
    data/                    # 数据层（无 UI 依赖，可单测）
      book_store.dart        # 书架与进度
      pet_store.dart         # 桌宠亲密度 / 点心 / 位置 / 显示开关
      pet_mood.dart          # 桌宠情绪状态机（生气、锁屏门槛、台词池）
      pet_guide.dart         # 新手引导控制器（步骤、劝导、软化解锁）
      prefs.dart             # 应用与阅读设置
      stats_store.dart       # 阅读统计与书签
    source/                  # 书源引擎（规则分析 / 请求层 / 并发搜索 / 正文解析）
    ui/                      # 页面与组件
      widgets/pet_overlay.dart      # 全局悬浮桌宠
      widgets/pet_guide_overlay.dart# 新手引导层
      widgets/pet_egg.dart          # 全屏锁定彩蛋
    platform/native_bridge.dart     # MethodChannel（权限 / 常亮 / 电量 / 目录）
tool/                        # 开发工具（图标生成、素材管线、诊断脚本）
docs/                        # 路线图与专项记录
```

## 验证基线（每次改动都要过）

```bash
dart format lib test           # 0 改动
flutter analyze                # No issues found
flutter test                   # 全部通过
```

三条全绿才算完成。新增功能请**同时补测试**（数据层优先做成可单测的纯逻辑，UI 尽量薄）。

## 提交流范

- 提交信息：`类型: 简述`，类型用 `feat` / `fix` / `docs` / `test` / `refactor` / `chore`。
  例：`feat: 桌宠阅读时乱跑`、`fix: 在线正文只取第一段`。
- 一个提交只做一件事；涉及行为变更时同步更新 `CHANGELOG.md`。
- 新增或调整 UI 时，如涉及美术资源，请说明素材来源（AI 生成 / 手绘 / 授权）。

## 关于书源与素材合规（重要）

- **不要**向 `assets/sources/builtin_sources.json` 添加有版权风险的第三方聚合书源。
  内置源只收录**公有领域**或**明确授权**的内容站（当前为中文维基文库，CC BY-SA）。
- 需要下线旧内置源时，在资产的 `legacyBuiltinUrls` 里登记地址，
  `SourceStore.ensureBuiltinSources()` 会在升级时清理（用户自建源不受影响）。
- AI 生成素材请只提交**最终入库**的那一张；中间候选图属于 `tool/artwork/candidates/`，已在 `.gitignore` 中。
- API Key 等凭据**绝不入库**：管线工具统一从 `/tmp/sf_key` 读取。

## 美术风格约定

- 目标风格：**日系电视动画赛璐璐上色**（干净线条、平涂或简单光影）。
- 需要明确排除：写实、3D、厚涂、油光、电影感。
- Q 版（chibi）与常规立绘用途不同：**App 图标 / 桌宠**用 Q 版；**开屏 / 封面**用常规立绘。

## 报告问题

请附上：版本号（设置页可见）、复现步骤、期望与实际表现；
涉及 UI 的尽量带截图。桌宠彩蛋是**真锁定**（只能重启 App），截图时请注意。
