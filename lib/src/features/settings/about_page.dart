import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_info.dart';
import '../../core/icons/sakura_icons.dart';
import '../../core/theme/sakura_layout.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/prefs.dart';
import '../../platform/update_service.dart';
import '../../platform/url_launcher.dart';
import '../../ui/update_dialog.dart';

/// 独立「关于樱读」页面：标语、版本号、多线路更新检查、GitHub / 酷安主页、开源许可与免责声明。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;

  Future<void> _openOrCopy(String url, String label) async {
    final ok = await launchUrlString(url);
    if (!mounted || ok) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('未检测到浏览器，已复制$label：$url')));
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制$label：$value')));
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        await showUpdateDialog(
          context,
          info: result.info!,
          isAuto: false,
          prefs: widget.prefs,
        );
      case UpdateCheckStatus.upToDate:
        messenger.showSnackBar(const SnackBar(content: Text('已经是最新版本啦～')));
      case UpdateCheckStatus.failed:
        messenger.showSnackBar(
          SnackBar(
            content: const Text('检查更新失败，请稍后重试'),
            action: SnackBarAction(label: '重试', onPressed: _checkUpdate),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    final hInsets = SakuraLayout.horizontalInsets(context);

    return Scaffold(
      backgroundColor: sakura.canvas,
      appBar: AppBar(title: const Text('关于樱读')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SakuraLayout.detailMaxWidth,
            ),
            child: AnimatedBuilder(
              animation: widget.prefs,
              builder: (context, _) => ListView(
                padding: EdgeInsets.fromLTRB(
                  hInsets.left,
                  10,
                  hInsets.right,
                  36,
                ),
                children: [
                  _buildHeroCard(context, sakura, scheme),
                  const SizedBox(height: 14),
                  _buildVersionUpdateCard(context, sakura, scheme),
                  const SizedBox(height: 14),
                  _buildLinksCard(context, sakura, scheme),
                  const SizedBox(height: 14),
                  _buildOpenSourceCard(context, sakura, scheme),
                  const SizedBox(height: 14),
                  _buildCreditsCard(context, sakura, scheme),
                  const SizedBox(height: 14),
                  _buildDisclaimerCard(context, sakura),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    return _card(
      context,
      children: [
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Image.asset(
                  'assets/images/pet_read.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '樱读 · Sakura Read',
                style: TextStyle(
                  color: sakura.inkPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _pill(
                    sakura,
                    scheme.primary,
                    'v${AppInfo.version}',
                    filled: true,
                  ),
                  _pill(sakura, scheme.primary, AppInfo.license),
                  _pill(sakura, scheme.primary, 'by ${AppInfo.author}'),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: sakura.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  AppInfo.slogan,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sakura.inkPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVersionUpdateCard(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    return _card(
      context,
      children: [
        _cardTitle(context, SakuraGlyph.about, '版本与更新'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('当前版本', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            'v${AppInfo.version} · 点击复制版本信息',
            style: TextStyle(fontSize: 12, color: sakura.inkSecondary),
          ),
          trailing: Text(
            'v${AppInfo.version}',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: () => _copyText('樱读 v${AppInfo.version} (Android)', '版本号'),
        ),
        const Divider(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('检查新版本', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            '支持多线路测速优选、断点续传与低速自动切换',
            style: TextStyle(fontSize: 12, color: sakura.inkSecondary),
          ),
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: _checkingUpdate ? null : _checkUpdate,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启动时自动检查更新', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            '发现新版时弹窗提醒并加速下载',
            style: TextStyle(fontSize: 12, color: sakura.inkSecondary),
          ),
          value: widget.prefs.autoCheckUpdate,
          onChanged: widget.prefs.setAutoCheckUpdate,
        ),
      ],
    );
  }

  Widget _buildLinksCard(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    return _card(
      context,
      children: [
        _cardTitle(context, SakuraGlyph.sources, '作者与主页'),
        _linkTile(
          sakura: sakura,
          scheme: scheme,
          icon: Icons.code_rounded,
          title: 'GitHub 开源仓库',
          url: AppInfo.repo,
          label: 'GitHub 仓库地址',
        ),
        const Divider(height: 10),
        _linkTile(
          sakura: sakura,
          scheme: scheme,
          icon: Icons.forum_outlined,
          title: '酷安个人主页',
          url: AppInfo.coolapk,
          label: '酷安主页地址',
        ),
      ],
    );
  }

  Widget _linkTile({
    required SakuraColors sakura,
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required String url,
    required String label,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: sakura.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: scheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.primary),
      ),
      trailing: IconButton(
        tooltip: '复制链接',
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () => _copyText(url, label),
      ),
      onTap: () => _openOrCopy(url, label),
    );
  }

  Widget _buildOpenSourceCard(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    return _card(
      context,
      children: [
        _cardTitle(context, SakuraGlyph.backup, '开源信息与致谢'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('开源协议：GNU GPL-3.0', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            '强传染性开源许可：基于本项目的修改、二次开发或重新分发须同样以 GPL-3.0 开源并保留原作者署名，禁止闭源商用。',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: sakura.inkSecondary,
            ),
          ),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _openOrCopy(AppInfo.licenseUrl, 'GPL-3.0 协议全文'),
        ),
        const Divider(height: 12),
        Text(
          '核心开源组件与字体致谢',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: sakura.inkPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '· Flutter & Dart（跨平台 UI 与渲染框架）\n'
          '· sherpa-onnx + VITS 超文（内置中文离线语音）\n'
          '· Google LiteRT-LM（端侧离线小模型推理）\n'
          '· QuickJS-NG & paper_curl（书源脚本与 3D 翻页）\n'
          '· 霞鹜文楷 Lite（默认正文字体 · SIL OFL-1.1）',
          style: TextStyle(
            fontSize: 12,
            height: 1.65,
            color: sakura.inkSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('查看第三方开源许可', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            '浏览 Flutter 及全部依赖包许可证通知',
            style: TextStyle(fontSize: 12, color: sakura.inkSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(
            context: context,
            applicationName: '樱读 · Sakura Read',
            applicationVersion: 'v${AppInfo.version}',
            applicationLegalese:
                'Copyright © 2026 ${AppInfo.author} · GNU GPL-3.0',
          ),
        ),
      ],
    );
  }

  Widget _buildCreditsCard(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    return Material(
      color: sakura.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: sakura.hairline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          leading: SakuraIcon(
            glyph: SakuraGlyph.appearance,
            size: 18,
            color: scheme.primary,
            accent: scheme.primary,
          ),
          title: Row(
            children: [
              Text(
                '引用致谢',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: sakura.inkPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _pill(
                sakura,
                scheme.primary,
                '${AppInfo.openSourceCredits.length} 项',
                filled: true,
              ),
            ],
          ),
          subtitle: Text(
            '点击展开查看借鉴与引用的个人开源项目与作者主页',
            style: TextStyle(fontSize: 11.5, color: sakura.inkSecondary),
          ),
          children: [
            for (var i = 0; i < AppInfo.openSourceCredits.length; i++) ...[
              if (i > 0) const Divider(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        AppInfo.openSourceCredits[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: sakura.inkPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AppInfo.openSourceCredits[i].repo
                            .replaceFirst('https://github.com/', '')
                            .replaceFirst('https://www.', '')
                            .replaceFirst('https://', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  AppInfo.openSourceCredits[i].note,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: sakura.inkSecondary,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () => _openOrCopy(
                  AppInfo.openSourceCredits[i].repo,
                  AppInfo.openSourceCredits[i].name,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimerCard(BuildContext context, SakuraColors sakura) {
    return _card(
      context,
      children: [
        _cardTitle(context, SakuraGlyph.purify, '免责声明'),
        Text(
          AppInfo.disclaimerItems.join('\n'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.7,
            color: sakura.inkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _pill(
    SakuraColors sakura,
    Color accent,
    String text, {
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? sakura.accentSoft : sakura.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? accent.withValues(alpha: 0.35) : sakura.hairline,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: filled ? accent : sakura.inkSecondary,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final sakura = context.sakura;
    return Material(
      color: sakura.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: sakura.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _cardTitle(BuildContext context, SakuraGlyph glyph, String title) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SakuraIcon(
            glyph: glyph,
            color: sakura.inkPrimary,
            accent: accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: sakura.inkPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
