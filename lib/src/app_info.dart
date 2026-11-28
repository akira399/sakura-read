/// 一条开源引用与致谢记录（关于页与仓库文档共用）。
class OpenSourceCredit {
  const OpenSourceCredit({
    required this.name,
    required this.repo,
    required this.note,
  });

  final String name;
  final String repo;
  final String note;
}

/// 应用基本信息（版本 / 作者 / 主页 / 协议 / 免责声明 / 引用致谢）——设置页、更新弹窗与「关于」页共用。
///
/// 版本号与 `pubspec.yaml` 的 `version` 保持同步（发版时一起改）。
class AppInfo {
  AppInfo._();

  /// 语义化版本（不含 build 号）。
  static const String version = '2.2.0';

  /// 作者。
  static const String author = 'akira399';

  /// 开源仓库地址。
  static const String repo = 'https://github.com/akira399/sakura-read';

  /// 酷安个人主页。
  static const String coolapk = 'https://www.coolapk.com/u/21255431';

  /// 许可证。
  static const String license = 'GPL-3.0';

  /// 仓库许可证全文链接。
  static const String licenseUrl =
      'https://github.com/akira399/sakura-read/blob/main/LICENSE';

  /// 标语（与仓库 README 保持一致）。
  static const String slogan = '如果樱读陪你静静多读完了几章书，欢迎点亮一颗 ⭐️ Star 支持项目！';

  /// 借鉴与引用的个人开源项目与作者主页清单。
  static const List<OpenSourceCredit> openSourceCredits = [
    OpenSourceCredit(
      name: 'AzukiReader',
      repo: 'https://github.com/AzukiPann/AzukiReader',
      note: '立体等轴测书脊书架交互设计、滚动落点物理方程与目录排布灵感来源',
    ),
    OpenSourceCredit(
      name: 'Wenku8_Flutter',
      repo: 'https://github.com/P5UEDGK/Wenku8_Flutter',
      note: '立体书架平行投影美学与档案式视觉动效上游参考',
    ),
    OpenSourceCredit(
      name: 'Legado（阅读 3.0）',
      repo: 'https://github.com/gedoor/legado',
      note: '兼容书源 JSON 规则生态、JS 扩展约定与书架备份格式参考（全套以 Dart 独立实现）',
    ),
    OpenSourceCredit(
      name: 'legado-with-MD3',
      repo: 'https://github.com/HapeLee/legado-with-MD3',
      note: 'Material 3 阅读器交互细节与设置分类思路参考',
    ),
    OpenSourceCredit(
      name: '米安第一深情',
      repo: 'https://www.coolapk.com/u/12223114',
      note: 'AI 写源抓页取证与调试回修闭环思路及体验反馈参考',
    ),
    OpenSourceCredit(
      name: '霞鹜文楷 Lite',
      repo: 'https://github.com/lxgw/LxgwWenKai-Lite',
      note: '内置默认中文阅读字体（SIL OFL-1.1 开源授权）',
    ),
  ];

  /// 免责声明条款（首启声明页与「关于」页共用语义）。
  static const List<String> disclaimerItems = [
    '1. 樱读仅作为本地文件阅读器与规则解析工具，本身不提供、不分发、不存储任何书籍内容。',
    '2. 通过书源获取的目录、封面与正文均来自第三方网站，其版权与合法性由原作者及原站点负责。',
    '3. 请支持正版阅读；自行导入或编写的书源、字体及内容，请自行确认合规后使用。',
    '4. 本软件遵循 GNU GPL-3.0 协议开源，按“现状”免费提供，作者不对第三方内容与服务承担连带责任。',
  ];
}
