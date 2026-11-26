import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../core/icons/sakura_icons.dart';
import '../../core/theme/sakura_layout.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/book_store.dart';
import '../../data/pet_guide.dart';
import '../../data/prefs.dart';
import '../../platform/display_service.dart';
import '../../platform/update_service.dart';
import '../../platform/url_launcher.dart';
import '../../ui/update_dialog.dart';
import '../../util/format.dart';

/// 系统、性能、存储清理、更新检查与关于页。
class SystemAboutPage extends StatefulWidget {
  const SystemAboutPage({super.key, required this.prefs, required this.store});

  final AppPrefs prefs;
  final BookStore store;

  @override
  State<SystemAboutPage> createState() => _SystemAboutPageState();
}

class _SystemAboutPageState extends State<SystemAboutPage> {
  int? _cacheBytes;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await widget.store.cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = size);
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final hInsets = SakuraLayout.horizontalInsets(context);
    return Scaffold(
      appBar: AppBar(title: const Text('性能、缓存与关于')),
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
                  8,
                  hInsets.right,
                  36,
                ),
                children: [
                  _card(
                    context,
                    children: [
                      _cardTitle(context, SakuraGlyph.performance, '性能与网络并发'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '高刷新率',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '120Hz 屏幕按最高刷新率出帧；关闭更省电',
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        value: widget.prefs.highRefreshRate,
                        onChanged: (v) {
                          widget.prefs.setHighRefreshRate(v);
                          DisplayService.setHighRefresh(v);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '显示帧率',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '在屏幕上方叠加实时帧率与耗时',
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        value: widget.prefs.showPerformanceOverlay,
                        onChanged: widget.prefs.setShowPerformanceOverlay,
                      ),
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '搜书并发线程数',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '同时搜索 ${widget.prefs.searchConcurrency} 个书源',
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => _customConcurrency(context),
                          child: const Text('自定义'),
                        ),
                      ),
                      Slider(
                        value: widget.prefs.searchConcurrency
                            .clamp(1, 32)
                            .toDouble(),
                        min: 1,
                        max: 32,
                        divisions: 31,
                        label: '${widget.prefs.searchConcurrency} 个',
                        onChanged: (v) =>
                            widget.prefs.setSearchConcurrency(v.round()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _card(
                    context,
                    children: [
                      _cardTitle(context, SakuraGlyph.backup, '存储与帮助'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '章节与 EPUB 缓存',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          _cacheBytes == null
                              ? '计算中…'
                              : formatBytes(_cacheBytes!),
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        trailing: OutlinedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await widget.store.clearCache();
                            await _loadCacheSize();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(content: Text('缓存已清空')),
                            );
                          },
                          child: const Text('清除缓存'),
                        ),
                      ),
                      const Divider(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '重看新手引导',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '小樱再带你走一遍搜书、导入等功能',
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          final already = kPetGuideActive.value;
                          petGuideRequestReplay();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                already ? '小樱正在给你带路呢～' : '小樱马上就来找你～',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _card(
                    context,
                    children: [
                      _cardTitle(context, SakuraGlyph.about, '检查更新与关于'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '检查新版本',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '当前版本 v${AppInfo.version}',
                          style: TextStyle(
                            fontSize: 12,
                            color: sakura.inkSecondary,
                          ),
                        ),
                        trailing: _checkingUpdate
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: _checkingUpdate ? null : _checkUpdate,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '启动时自动检查更新',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: widget.prefs.autoCheckUpdate,
                        onChanged: widget.prefs.setAutoCheckUpdate,
                      ),
                      const Divider(height: 20),
                      Center(
                        child: Column(
                          children: [
                            SizedBox(
                              width: 92,
                              height: 92,
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
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'v${AppInfo.version} · ${AppInfo.license} · ${AppInfo.author}',
                              style: TextStyle(
                                color: sakura.inkSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                final ok = await launchUrlString(AppInfo.repo);
                                if (!context.mounted || ok) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('没有找到可用的浏览器')),
                                );
                              },
                              child: Text(
                                'github.com/akira399/sakura-read',
                                style: TextStyle(color: accent, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

  Future<void> _customConcurrency(BuildContext context) async {
    final controller = TextEditingController(
      text: '${widget.prefs.searchConcurrency}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义并发数'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '同时搜索的书源个数',
            helperText: '1 ~ 999',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(v);
            },
            child: const Text('好'),
          ),
        ],
      ),
    );
    if (value != null) {
      widget.prefs.setSearchConcurrency(value.clamp(1, 999));
    }
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
}
