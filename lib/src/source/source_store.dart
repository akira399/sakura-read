// 书源仓库：导入 / 导出 / 持久化（JSON 文件）/ 启用状态管理。
//
// 持久化位置：App files 目录下的 book_sources.json
// 结构：{"version": 1, "sources": [ {...书源JSON...} ]}
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../platform/native_bridge.dart';
import 'models.dart';

/// 导入结果统计。
class SourceImportReport {
  const SourceImportReport({
    this.added = 0,
    this.updated = 0,
    this.invalid = 0,
    this.error,
  });

  final int added;
  final int updated;
  final int invalid;
  final String? error;

  bool get hasAny => added + updated > 0;

  String get summary {
    if (error != null) return error!;
    final parts = <String>[
      if (added > 0) '新增 $added 个',
      if (updated > 0) '更新 $updated 个',
      if (invalid > 0) '跳过 $invalid 个无效条目',
    ];
    return parts.isEmpty ? '没有可导入的书源' : parts.join('，');
  }
}

/// 书源仓库（可监听，UI 依赖它刷新）。
class SourceStore extends ChangeNotifier {
  SourceStore({AppDirs? dirsOverride, List<BookSource>? initial})
    : _dirsOverride = dirsOverride {
    if (initial != null) _sources.addAll(initial);
  }

  /// 进程内共享实例（在线书籍内容读取器按 bookSourceUrl 查找书源时使用）。
  static SourceStore? shared;

  final AppDirs? _dirsOverride;
  final List<BookSource> _sources = [];
  AppDirs? _dirs;
  File? _file;
  Timer? _saveTimer;

  List<BookSource> get sources => List.unmodifiable(_sources);

  int get enabledCount => _sources.where((s) => s.enabled).length;

  bool get isEmpty => _sources.isEmpty;

  BookSource? byUrl(String url) {
    for (final s in _sources) {
      if (s.bookSourceUrl == url) return s;
    }
    return null;
  }

  List<BookSource> get enabled =>
      _sources.where((s) => s.enabled).toList(growable: false);

  // ---------- 加载 / 保存 ----------

  Future<void> load() async {
    _dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${_dirs!.files}/book_sources.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map && data['sources'] is List) {
          for (final item in data['sources'] as List) {
            try {
              final s = BookSource.fromJson(item);
              if (s.bookSourceUrl.isNotEmpty) _sources.add(s);
            } catch (_) {
              // 跳过坏条目
            }
          }
        }
      }
    } catch (_) {
      // 读取失败时以空列表启动
    }
    notifyListeners();
  }

  // ---------- 变更 ----------

  /// 批量导入；同一 bookSourceUrl 视为更新（保留原启用状态）。
  ({int added, int updated}) addAll(List<BookSource> items) {
    var added = 0;
    var updated = 0;
    for (final s in items) {
      final i = _sources.indexWhere((x) => x.bookSourceUrl == s.bookSourceUrl);
      if (i >= 0) {
        // 保留用户当前的启用状态
        final keepEnabled = _sources[i].enabled;
        _sources[i] = s.enabled == keepEnabled
            ? s
            : s.copyWith(enabled: keepEnabled);
        updated++;
      } else {
        _sources.add(s);
        added++;
      }
    }
    if (added + updated > 0) {
      _saveSoon();
      notifyListeners();
    }
    return (added: added, updated: updated);
  }

  void remove(String url) {
    final before = _sources.length;
    _sources.removeWhere((s) => s.bookSourceUrl == url);
    if (_sources.length != before) {
      _saveSoon();
      notifyListeners();
    }
  }

  void setEnabled(String url, bool value) {
    final i = _sources.indexWhere((s) => s.bookSourceUrl == url);
    if (i < 0 || _sources[i].enabled == value) return;
    _sources[i] = _sources[i].copyWith(enabled: value);
    _saveSoon();
    notifyListeners();
  }

  // ---------- 导入 / 导出 ----------

  /// 从 JSON 文本导入（支持数组或单个对象；容忍 BOM 与首尾空白）。
  SourceImportReport importFromText(String text) {
    final trimmed = text.trim().replaceFirst('\uFEFF', '');
    if (trimmed.isEmpty) {
      return const SourceImportReport(error: '内容为空');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return const SourceImportReport(error: '不是合法的 JSON（书源应为 JSON 数组或对象）');
    }
    final items = BookSource.listFromJson(decoded);
    if (items.isEmpty) {
      return const SourceImportReport(
        error: '没有解析到有效书源（需要 bookSourceUrl 与 bookSourceName）',
      );
    }
    final total = decoded is List ? decoded.length : 1;
    final r = addAll(items);
    return SourceImportReport(
      added: r.added,
      updated: r.updated,
      invalid: total - items.length,
    );
  }

  /// 从文件导入。
  Future<SourceImportReport> importFromFile(String path) async {
    try {
      final text = await File(path).readAsString();
      return importFromText(text);
    } catch (e) {
      return SourceImportReport(error: '读取文件失败：$e');
    }
  }

  /// 导出为 JSON 文本（数组格式，与阅读 3.0 互通）。
  String exportJson() {
    final list = _sources.map((s) => s.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// 立即落盘（测试与退出前调用；平时是防抖保存）。
  Future<void> flush() => _save();

  /// 导入 / 更新内置书源（App 启动时调用）。
  ///
  /// - 首次启动（书源为空）：全量导入；
  /// - 已有书源：同地址的源以版本内置内容为准更新（保留用户启停状态），
  ///   并补齐版本升级新增的内置源；
  /// - 版本升级时，清掉历史内置的**盗版聚合源**（见内置资产的
  ///   `legacyBuiltinUrls` 元数据）——这些源版权风险高、稳定性差。
  Future<int> ensureBuiltinSources() async {
    try {
      final text = await rootBundle.loadString(
        'assets/sources/builtin_sources.json',
      );
      final removed = _dropLegacyBuiltinSources(text);
      final report = importFromText(text);
      await flush();
      return report.added + report.updated + removed;
    } catch (_) {
      return 0;
    }
  }

  /// 按内置资产里的 `legacyBuiltinUrls` 清单移除历史内置源。
  ///
  /// 只删「书源地址完全一致」的条目：用户自己导入的同名站点不受影响。
  int _dropLegacyBuiltinSources(String builtinJson) {
    final legacy = <String>{};
    try {
      final decoded = jsonDecode(builtinJson);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final urls = item['legacyBuiltinUrls'];
          if (urls is List) {
            legacy.addAll(urls.map((u) => u.toString().trim()));
          }
        }
      }
    } catch (_) {
      return 0;
    }
    legacy.removeWhere((u) => u.isEmpty);
    if (legacy.isEmpty) return 0;
    final before = _sources.length;
    _sources.removeWhere((s) => legacy.contains(s.bookSourceUrl));
    return before - _sources.length;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ---------- 持久化 ----------

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'version': 1,
          'sources': _sources.map((s) => s.toJson()).toList(),
        }),
      );
      await tmp.rename(file.path);
    } catch (_) {
      // 忽略保存失败
    }
  }
}
