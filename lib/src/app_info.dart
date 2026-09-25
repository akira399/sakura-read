/// 应用基本信息（版本 / 作者 / 仓库）——设置页与「关于」卡共用。
///
/// 版本号与 `pubspec.yaml` 的 `version` 保持同步（发版时一起改）。
class AppInfo {
  AppInfo._();

  /// 语义化版本（不含 build 号）。
  static const String version = '1.0.0';

  /// 作者。
  static const String author = 'akira399';

  /// 开源仓库地址。
  static const String repo = 'https://github.com/akira399/sakura-read';

  /// 许可证。
  static const String license = 'MIT License';
}
