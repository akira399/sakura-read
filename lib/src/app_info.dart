/// 应用基本信息（版本 / 作者 / 主页 / 协议 / 免责声明）——设置页、更新弹窗与「关于」页共用。
///
/// 版本号与 `pubspec.yaml` 的 `version` 保持同步（发版时一起改）。
class AppInfo {
  AppInfo._();

  /// 语义化版本（不含 build 号）。
  static const String version = '2.1.1';

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

  /// 免责声明条款（首启声明页与「关于」页共用语义）。
  static const List<String> disclaimerItems = [
    '1. 樱读仅作为本地文件阅读器与规则解析工具，本身不提供、不分发、不存储任何书籍内容。',
    '2. 通过书源获取的目录、封面与正文均来自第三方网站，其版权与合法性由原作者及原站点负责。',
    '3. 请支持正版阅读；自行导入或编写的书源、字体及内容，请自行确认合规后使用。',
    '4. 本软件遵循 GNU GPL-3.0 协议开源，按“现状”免费提供，作者不对第三方内容与服务承担连带责任。',
  ];
}
