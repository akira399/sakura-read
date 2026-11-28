// 「发现新版本」更新的公告弹窗：版本对比 + 更新说明 + 多线路优选进度 + 换线 + 安装引导。
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/prefs.dart';
import '../platform/native_bridge.dart';
import '../platform/update_service.dart';
import '../platform/url_launcher.dart';
import '../util/format.dart';

/// 弹出「发现新版本」公告。
Future<bool?> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required bool isAuto,
  required AppPrefs prefs,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(info: info, isAuto: isAuto, prefs: prefs),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.info,
    required this.isAuto,
    required this.prefs,
  });

  final UpdateInfo info;
  final bool isAuto;
  final AppPrefs prefs;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, done, error }

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = 0;
  bool _cancelled = false;
  bool _switchRequested = false;
  UpdateDownloadStatus? _status;
  String? _error;

  /// 已下载的安装包路径（done 阶段进入系统安装器）。
  String? _apkPath;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = widget.info.sizeBytes;
      _cancelled = false;
      _switchRequested = false;
      _status = null;
      _error = null;
    });
    final dirs = await NativeBridge.appDirs();
    final fileName = _fileNameOf(widget.info.downloadUrl);
    final target = '${dirs.cache}/update/$fileName';

    final ok = await UpdateService.instance.download(
      widget.info,
      target,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          if (total > 0) _total = total;
        });
      },
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _status = status);
      },
      isCancelled: () => _cancelled,
      shouldSwitchRoute: () {
        if (!_switchRequested) return false;
        _switchRequested = false;
        return true;
      },
    );

    if (!mounted) return;
    if (_cancelled) {
      setState(() => _phase = _Phase.idle);
      return;
    }
    if (ok) {
      setState(() {
        _phase = _Phase.done;
        _apkPath = target;
      });
      await _install();
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = '所有加速线路均下载失败，可尝试重试或前往浏览器下载';
      });
    }
  }

  /// 调起系统安装；未授权时引导去系统设置授权。
  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;

    final canInstall = await NativeBridge.canInstallApk();
    if (!canInstall) {
      if (!mounted) return;
      setState(() {
        _error = '需要先允许「安装未知来源应用」，授权后请重新点安装';
        _phase = _Phase.done;
      });
      await NativeBridge.openInstallPermission();
      return;
    }
    final ok = await NativeBridge.installApk(path);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _phase = _Phase.error;
        _error = '无法调起系统安装界面，请确认安装包已完整下载';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = widget.info;
    final busy = _phase == _Phase.downloading;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        title: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Image.asset(
                'assets/images/pet_wave.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '发现新版本',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${info.version} · 当前 v${AppInfo.version}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) ..._buildDownloading(scheme) else ..._buildInfo(scheme),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: _buildActions(),
      ),
    );
  }

  List<Widget> _buildInfo(ColorScheme scheme) {
    return [
      Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SingleChildScrollView(
          child: Text(
            widget.info.notes.isEmpty ? '（该版本暂无更新说明）' : widget.info.notes,
            style: const TextStyle(fontSize: 12.5, height: 1.7),
          ),
        ),
      ),
      if (widget.info.sizeBytes > 0) ...[
        const SizedBox(height: 8),
        Text(
          '安装包大小：${formatBytes(widget.info.sizeBytes)} · 支持多线路测速与断点续传',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
      if (_phase == _Phase.error) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _error ?? '下载失败',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          ],
        ),
      ],
      if (_phase == _Phase.done && _apkPath != null) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '下载完成，正在调起系统安装…若未弹出请点「重新安装」',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _buildDownloading(ColorScheme scheme) {
    final status = _status;
    final probing = status?.phase == UpdateDownloadPhase.probing;
    final percent = probing
        ? null
        : (_total > 0 ? (_received / _total).clamp(0.0, 1.0) : null);
    final speedLabel = (status != null && status.bytesPerSecond > 0)
        ? '${formatBytes(status.bytesPerSecond)}/s'
        : '';
    final headline = status == null
        ? '正在优选最快下载线路…'
        : (status.message.isNotEmpty ? status.message : status.mirrorLabel);

    return [
      Text(
        headline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(value: percent, minHeight: 8),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              _total > 0
                  ? '${(_received / _total * 100).toStringAsFixed(0)}% · '
                        '${formatBytes(_received)} / ${formatBytes(_total)}'
                  : formatBytes(_received),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          if (speedLabel.isNotEmpty)
            Text(
              speedLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _buildActions() {
    if (_phase == _Phase.downloading) {
      final canSwitch = _status?.phase == UpdateDownloadPhase.downloading;
      return [
        if (canSwitch)
          TextButton(
            onPressed: () {
              setState(() => _switchRequested = true);
            },
            child: const Text('换条线路'),
          ),
        TextButton(
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('取消下载'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () {
          if (widget.isAuto) {
            widget.prefs.setSkipUpdateVersion(widget.info.version);
          }
          Navigator.of(context).pop(false);
        },
        child: Text(widget.isAuto ? '以后再说' : '关闭'),
      ),
      if (_phase == _Phase.error) ...[
        TextButton(
          onPressed: () => launchUrlString(widget.info.pageUrl),
          child: const Text('浏览器下载'),
        ),
        FilledButton(onPressed: _startDownload, child: const Text('重试下载')),
      ] else
        FilledButton(
          onPressed: () {
            if (_phase == _Phase.done) {
              _install();
            } else {
              _startDownload();
            }
          },
          child: Text(_phase == _Phase.done ? '重新安装' : '立即更新'),
        ),
    ];
  }
}

/// 文件名提取：从下载地址取最后一段（去 query），失败给默认名。
String _fileNameOf(String url) {
  try {
    final uri = Uri.parse(url);
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (name.toLowerCase().endsWith('.apk')) return name;
  } catch (_) {}
  return 'SakuraRead-update.apk';
}
