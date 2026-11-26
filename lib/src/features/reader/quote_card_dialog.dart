import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 书摘金句卡片主题风格。
enum QuoteCardStyle {
  ivory('素宣', Color(0xFFFAF6EE), Color(0xFF2D2720), Color(0xFFE86A92)),
  sakura('樱笺', Color(0xFFFFF4F7), Color(0xFF3A232D), Color(0xFFE05784)),
  bamboo('竹影', Color(0xFFEEF6F1), Color(0xFF21352B), Color(0xFF3F9A76)),
  obsidian('墨韵', Color(0xFF1A1C24), Color(0xFFECEEF4), Color(0xFFF08BAE));

  const QuoteCardStyle(this.label, this.bg, this.ink, this.accent);

  final String label;
  final Color bg;
  final Color ink;
  final Color accent;
}

/// 打开「文艺书摘金句卡片」预览与导出弹窗。
Future<void> showQuoteCardDialog(
  BuildContext context, {
  required String quote,
  required String bookTitle,
  String author = '',
  String chapterTitle = '',
  String note = '',
  Future<void> Function(Uint8List pngBytes)? onExportPng,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => QuoteCardDialog(
      quote: quote,
      bookTitle: bookTitle,
      author: author,
      chapterTitle: chapterTitle,
      note: note,
      onExportPng: onExportPng,
    ),
  );
}

/// 可独立渲染与测试的金句卡片弹窗（内含 [RepaintBoundary] 截图区）。
class QuoteCardDialog extends StatefulWidget {
  const QuoteCardDialog({
    super.key,
    required this.quote,
    required this.bookTitle,
    this.author = '',
    this.chapterTitle = '',
    this.note = '',
    this.onExportPng,
  });

  final String quote;
  final String bookTitle;
  final String author;
  final String chapterTitle;
  final String note;
  final Future<void> Function(Uint8List pngBytes)? onExportPng;

  @override
  State<QuoteCardDialog> createState() => _QuoteCardDialogState();
}

class _QuoteCardDialogState extends State<QuoteCardDialog> {
  final GlobalKey _cardKey = GlobalKey();
  QuoteCardStyle _style = QuoteCardStyle.ivory;
  bool _exporting = false;
  String? _statusMessage;

  Future<void> _copyQuote() async {
    final buf = StringBuffer('「${widget.quote.trim()}」');
    if (widget.note.trim().isNotEmpty) {
      buf.write('\n\n笔记：${widget.note.trim()}');
    }
    buf.write('\n——《${widget.bookTitle}》');
    if (widget.author.trim().isNotEmpty) {
      buf.write(' · ${widget.author.trim()}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    setState(() => _statusMessage = '书摘文案已复制');
  }

  Future<void> _exportCard() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _statusMessage = null;
    });
    try {
      final renderObj = _cardKey.currentContext?.findRenderObject();
      if (renderObj is! RenderRepaintBoundary) {
        throw StateError('卡片尚未完成渲染');
      }
      final image = await renderObj.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('导出图片字节失败');
      final bytes = data.buffer.asUint8List();
      if (widget.onExportPng != null) {
        await widget.onExportPng!(bytes);
      } else {
        final dir = Directory('${Directory.systemTemp.path}/sakura_quotes');
        await dir.create(recursive: true);
        final file = File(
          '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      setState(
        () =>
            _statusMessage = '已生成高清金句卡片 (${(bytes.length / 1024).round()} KB)',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '金句书摘卡片',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              RepaintBoundary(
                key: _cardKey,
                child: _EditorialQuoteCard(
                  style: _style,
                  quote: widget.quote,
                  note: widget.note,
                  bookTitle: widget.bookTitle,
                  author: widget.author,
                  chapterTitle: widget.chapterTitle,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final s in QuoteCardStyle.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _style == s,
                      visualDensity: VisualDensity.compact,
                      avatar: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: s.bg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.accent.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      onSelected: (_) => setState(() => _style = s),
                    ),
                ],
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyQuote,
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('复制文案'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _exportCard,
                      icon: _exporting
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined, size: 17),
                      label: const Text('保存卡片'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorialQuoteCard extends StatelessWidget {
  const _EditorialQuoteCard({
    required this.style,
    required this.quote,
    required this.note,
    required this.bookTitle,
    required this.author,
    required this.chapterTitle,
  });

  final QuoteCardStyle style;
  final String quote;
  final String note;
  final String bookTitle;
  final String author;
  final String chapterTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.ink.withValues(alpha: 0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '“',
                style: TextStyle(
                  fontSize: 42,
                  height: 0.75,
                  fontWeight: FontWeight.w800,
                  color: style.accent.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: style.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '樱花阅读 · 摘录',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: style.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            quote.trim(),
            style: TextStyle(
              fontSize: 15.5,
              height: 1.85,
              letterSpacing: 0.3,
              color: style.ink,
            ),
          ),
          if (note.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: style.ink.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: style.accent, width: 2.5),
                ),
              ),
              child: Text(
                note.trim(),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: style.ink.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(height: 0.75, color: style.ink.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '《$bookTitle》${author.trim().isEmpty ? '' : ' · ${author.trim()}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: style.ink.withValues(alpha: 0.85),
                      ),
                    ),
                    if (chapterTitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        chapterTitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: style.ink.withValues(alpha: 0.52),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.local_florist_rounded,
                size: 16,
                color: style.accent.withValues(alpha: 0.75),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
