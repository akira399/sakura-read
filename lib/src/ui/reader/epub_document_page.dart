import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/epub_document.dart';
import '../../data/models.dart';
import '../../data/book_store.dart';
import '../../data/prefs.dart';

/// Optional original layout, with script execution disabled and no external resources.
class EpubDocumentPage extends StatefulWidget {
  const EpubDocumentPage({
    super.key,
    required this.book,
    required this.store,
    required this.prefs,
    required this.chapter,
  });
  final Book book;
  final BookStore store;
  final AppPrefs prefs;
  final int chapter;
  @override
  State<EpubDocumentPage> createState() => _EpubDocumentPageState();
}

class _EpubDocumentPageState extends State<EpubDocumentPage> {
  WebViewController? _controller;
  HttpServer? _server;
  Map<String, Uint8List> _resources = {};
  late int _chapter = widget.chapter;
  late final String _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? _error;
  bool _noteOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Uri _url(String path) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server!.port,
    pathSegments: [_token, ...path.split('/')],
  );

  Future<void> _load() async {
    try {
      _resources = await compute(
        unpackEpubDocument,
        await File(widget.book.path).readAsBytes(),
      );
      if (!mounted) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) async {
        final segments = request.uri.pathSegments;
        final path = segments.skip(1).join('/');
        final bytes = segments.isNotEmpty && segments.first == _token
            ? _resources[path]
            : null;
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; script-src 'none'; frame-src 'none'",
        );
        request.response.headers.set('Cache-Control', 'no-store');
        if (bytes == null) {
          request.response.statusCode = 404;
        } else if (RegExp(
          r'\.(xhtml|html|htm)$',
          caseSensitive: false,
        ).hasMatch(path)) {
          request.response.headers.contentType = ContentType.html;
          final bg = widget.prefs.readerBg;
          request.response.write(
            prepareEpubHtml(
              epubResourceText(bytes),
              fontSize: widget.prefs.fontSize,
              background:
                  '#${bg.color.toARGB32().toRadixString(16).substring(2)}',
              foreground:
                  '#${bg.textColor.toARGB32().toRadixString(16).substring(2)}',
            ),
          );
        } else {
          final ext = path.split('.').last.toLowerCase();
          request.response.headers.set(
            'Content-Type',
            {
                  'css': 'text/css',
                  'svg': 'image/svg+xml',
                  'png': 'image/png',
                  'jpg': 'image/jpeg',
                  'jpeg': 'image/jpeg',
                  'webp': 'image/webp',
                  'ttf': 'font/ttf',
                  'otf': 'font/otf',
                }[ext] ??
                'application/octet-stream',
          );
          request.response.add(bytes);
        }
        await request.response.close();
      });
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                uri.host != '127.0.0.1' ||
                uri.port != server.port ||
                uri.pathSegments.firstOrNull != _token) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已阻止书内外部链接，原书排版仅访问本地内容')),
                );
              }
              return NavigationDecision.prevent;
            }
            if (uri.fragment.isNotEmpty) {
              await _showNote(uri);
              return NavigationDecision.prevent;
            }
            final path = uri.pathSegments.skip(1).join('/');
            final index = widget.book.chapters.indexWhere(
              (c) => c.href == path,
            );
            if (index >= 0 && mounted) {
              setState(() => _chapter = index);
              _saveProgress();
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null && uri.fragment.isNotEmpty) {
              unawaited(_showNote(uri));
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
      await _open(_chapter);
    } catch (error) {
      assert(() { debugPrint('EPUB original layout: ' + error.toString()); return true; }());
      if (mounted) setState(() => _error = '原书排版加载失败，可返回使用文字排版阅读');
    }
  }

  void _saveProgress() {
    widget.store.updateProgress(widget.book.id, chapter: _chapter, offset: 0);
  }

  Future<void> _open(int index) async {
    if (index < 0 || index >= widget.book.chapterCount || _controller == null) {
      return;
    }
    setState(() => _chapter = index);
    _saveProgress();
    await _controller!.loadRequest(_url(widget.book.chapters[index].href!));
  }

  Future<void> _showNote(Uri uri) async {
    if (_noteOpen || !mounted) return;
    final data = _resources[uri.pathSegments.skip(1).join('/')];
    final text = data == null
        ? null
        : epubNote(epubResourceText(data), uri.fragment);
    if (text == null) return;
    _noteOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .65,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(text),
        ),
      ),
    );
    _noteOpen = false;
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    unawaited(widget.store.flush().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('EPUB 原书排版'),
      actions: [
        IconButton(
          tooltip: '目录',
          icon: const Icon(Icons.list),
          onPressed: () async {
            final selected = await showModalBottomSheet<int>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => ListView.builder(
                itemCount: widget.book.chapterCount,
                itemBuilder: (_, i) => ListTile(
                  title: Text(widget.book.chapters[i].title),
                  selected: i == _chapter,
                  onTap: () => Navigator.pop(ctx, i),
                ),
              ),
            );
            if (selected != null && mounted) _open(selected);
          },
        ),
      ],
    ),
    body: _error != null
        ? Center(child: Text(_error!))
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(controller: _controller!),
    bottomNavigationBar: SafeArea(
      child: Row(
        children: [
          TextButton(
            onPressed: _chapter > 0 ? () => _open(_chapter - 1) : null,
            child: const Text('上一章'),
          ),
          Expanded(
            child: Text(
              '${_chapter + 1}/${widget.book.chapterCount} · ${widget.book.chapters[_chapter].title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _chapter + 1 < widget.book.chapterCount
                ? () => _open(_chapter + 1)
                : null,
            child: const Text('下一章'),
          ),
        ],
      ),
    ),
  );
}
