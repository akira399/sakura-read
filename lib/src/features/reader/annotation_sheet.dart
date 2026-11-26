import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import 'annotation_models.dart';
import 'quote_card_dialog.dart';

/// 长按 / 选段后弹出的阅读器批注动作面板：
/// - 四色荧光划线（樱绯 / 暖杏 / 若竹 / 晴空）
/// - 写批注
/// - 复制原文
/// - 生成金句书摘卡片
/// - 问小樱 (AI) 回调入口
Future<void> showReaderAnnotationActionSheet(
  BuildContext context, {
  required String bookId,
  required String bookTitle,
  String author = '',
  required int chapterIndex,
  required String chapterTitle,
  required int startOffset,
  required int endOffset,
  required String selectedText,
  required ReaderAnnotationStore store,
  ReaderAnnotation? existing,
  void Function(String excerpt)? onAskAi,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => ReaderAnnotationActionSheet(
      bookId: bookId,
      bookTitle: bookTitle,
      author: author,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      startOffset: startOffset,
      endOffset: endOffset,
      selectedText: selectedText,
      store: store,
      existing: existing,
      onAskAi: onAskAi,
    ),
  );
}

class ReaderAnnotationActionSheet extends StatefulWidget {
  const ReaderAnnotationActionSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.author = '',
    required this.chapterIndex,
    required this.chapterTitle,
    required this.startOffset,
    required this.endOffset,
    required this.selectedText,
    required this.store,
    this.existing,
    this.onAskAi,
  });

  final String bookId;
  final String bookTitle;
  final String author;
  final int chapterIndex;
  final String chapterTitle;
  final int startOffset;
  final int endOffset;
  final String selectedText;
  final ReaderAnnotationStore store;
  final ReaderAnnotation? existing;
  final void Function(String excerpt)? onAskAi;

  @override
  State<ReaderAnnotationActionSheet> createState() =>
      _ReaderAnnotationActionSheetState();
}

class _ReaderAnnotationActionSheetState
    extends State<ReaderAnnotationActionSheet> {
  late int _colorIndex = widget.existing?.colorIndex ?? 0;
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  bool _showNoteField = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _showNoteField = (widget.existing?.note.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAnnotation({int? overrideColor}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = _noteCtrl.text.trim();
    final colorIdx = overrideColor ?? _colorIndex;
    final ann = widget.existing != null
        ? widget.existing!.copyWith(
            note: note,
            colorIndex: colorIdx,
            kind: note.isEmpty ? 'highlight' : 'note',
            updatedAt: now,
          )
        : ReaderAnnotation(
            id: ReaderAnnotation.newId(),
            bookId: widget.bookId,
            chapterIndex: widget.chapterIndex,
            startOffset: widget.startOffset,
            endOffset: widget.endOffset,
            quote: widget.selectedText.trim(),
            note: note,
            colorIndex: colorIdx,
            kind: note.isEmpty ? 'highlight' : 'note',
            createdAt: now,
            updatedAt: now,
          );
    await widget.store.save(ann);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(note.isEmpty ? '已添加划线' : '已保存划线与批注'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cleanText = widget.selectedText.trim();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 摘录预览
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AnnotationColor.fromIndex(_colorIndex).highlightFill(
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color: AnnotationColor.fromIndex(_colorIndex).swatch,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  cleanText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.55),
                ),
              ),
              const SizedBox(height: 14),
              // 四色荧光划线快捷条
              Row(
                children: [
                  Text(
                    '划线配色',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  for (var i = 0; i < AnnotationColor.values.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _colorIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AnnotationColor.values[i].swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _colorIndex == i
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: _colorIndex == i
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _saving ? null : () => _saveAnnotation(),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(widget.existing == null ? '划线' : '更新'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 快捷功能按钮组：写批注 / 复制 / 金句卡片 / 问小樱 (AI)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.edit_note_rounded, size: 17),
                    label: const Text('写批注'),
                    onPressed: () =>
                        setState(() => _showNoteField = !_showNoteField),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: cleanText));
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制选中文字'),
                          duration: Duration(milliseconds: 1000),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: const Text('金句卡片'),
                    onPressed: () {
                      final noteText = _noteCtrl.text.trim();
                      Navigator.of(context).pop();
                      showQuoteCardDialog(
                        context,
                        quote: cleanText,
                        note: noteText,
                        bookTitle: widget.bookTitle,
                        author: widget.author,
                        chapterTitle: widget.chapterTitle,
                      );
                    },
                  ),
                  ActionChip(
                    avatar: Icon(
                      Icons.local_florist_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                    label: const Text('问小樱 (AI)'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (widget.onAskAi != null) {
                        widget.onAskAi!(cleanText);
                      } else {
                        _showDefaultAiPreviewSheet(
                          context,
                          bookTitle: widget.bookTitle,
                          chapterTitle: widget.chapterTitle,
                          excerpt: cleanText,
                        );
                      }
                    },
                  ),
                ],
              ),
              if (_showNoteField) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  minLines: 2,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '写下此刻的想法或批注…',
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _saveAnnotation(),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('保存批注'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _showDefaultAiPreviewSheet(
  BuildContext context, {
  required String bookTitle,
  required String chapterTitle,
  required String excerpt,
}) {
  final scheme = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_florist_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '小樱 · 段内伴读',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '「$excerpt」',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '来自《$bookTitle》· $chapterTitle。配置 AI 模型后可在此直接解读语境、翻译与赏析。',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 书籍全部划线 / 批注管理抽屉。
Future<void> showBookAnnotationsSheet(
  BuildContext context, {
  required Book book,
  required ReaderAnnotationStore store,
  required void Function(int chapterIndex, int offset) onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetCtx).height * 0.66,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final items = store.highlightsAndNotes;
            final scheme = Theme.of(context).colorScheme;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 16, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '划线与批注 · 共 ${items.length} 条',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              '还没有划线或批注\n长按正文段落即可划线、写笔记或生成金句卡片',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final chapterTitle =
                                item.chapterIndex >= 0 &&
                                    item.chapterIndex < book.chapters.length
                                ? book.chapters[item.chapterIndex].title
                                : '第 ${item.chapterIndex + 1} 章';
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.of(sheetCtx).pop();
                                onJump(item.chapterIndex, item.startOffset);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(
                                    left: BorderSide(
                                      color: item.color.swatch,
                                      width: 3.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            chapterTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: scheme.primary,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.auto_awesome_outlined,
                                            size: 17,
                                          ),
                                          tooltip: '金句卡片',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => showQuoteCardDialog(
                                            context,
                                            quote: item.quote,
                                            note: item.note,
                                            bookTitle: book.title,
                                            author: book.author,
                                            chapterTitle: chapterTitle,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 17,
                                          ),
                                          tooltip: '删除',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              store.remove(item.id),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      item.quote,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        height: 1.55,
                                      ),
                                    ),
                                    if (item.hasNote) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '批注：${item.note}',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: scheme.onSurfaceVariant,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
