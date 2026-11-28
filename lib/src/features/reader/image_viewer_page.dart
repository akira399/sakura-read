import 'dart:io';

import 'package:flutter/material.dart';

/// 全屏插图缩放查看器（用于 EPUB / TXT 内嵌插图点击放大）。
///
/// 支持双指捏合缩放、双击放大/复原以及单击关闭。
class ReaderImageViewerPage extends StatefulWidget {
  const ReaderImageViewerPage({
    super.key,
    required this.imageProvider,
    this.caption,
  });

  factory ReaderImageViewerPage.file(File file, {Key? key, String? caption}) =>
      ReaderImageViewerPage(
        key: key,
        imageProvider: FileImage(file),
        caption: caption,
      );

  final ImageProvider imageProvider;
  final String? caption;

  @override
  State<ReaderImageViewerPage> createState() => _ReaderImageViewerPageState();
}

class _ReaderImageViewerPageState extends State<ReaderImageViewerPage> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  bool _lightCanvas = false;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleDoubleTapZoom() {
    setState(() {
      _zoomed = !_zoomed;
      _transform.value = _zoomed
          ? Matrix4.diagonal3Values(2.2, 2.2, 1.0)
          : Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _lightCanvas ? const Color(0xFFF7F3EA) : Colors.black;
    final chromeFg = _lightCanvas ? const Color(0xFF2B2620) : Colors.white;
    final chromePillBg = _lightCanvas ? Colors.black12 : Colors.black54;
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _chromeVisible = !_chromeVisible),
              onDoubleTap: _toggleDoubleTapZoom,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.8,
                maxScale: 5.0,
                boundaryMargin: const EdgeInsets.all(48),
                child: Center(
                  child: Image(
                    image: widget.imageProvider,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 42,
                          color: chromeFg.withValues(alpha: 0.54),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '图片无法加载',
                          style: TextStyle(
                            color: chromeFg.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_chromeVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: chromePillBg,
                          foregroundColor: chromeFg,
                        ),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '关闭',
                      ),
                      if (widget.caption != null &&
                          widget.caption!.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: chromeFg.withValues(alpha: 0.78),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      IconButton(
                        onPressed: () =>
                            setState(() => _lightCanvas = !_lightCanvas),
                        style: IconButton.styleFrom(
                          backgroundColor: chromePillBg,
                          foregroundColor: chromeFg,
                        ),
                        icon: Icon(
                          _lightCanvas
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                        ),
                        tooltip: _lightCanvas ? '切换深色底色' : '切换浅色纸面底色',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_chromeVisible)
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: chromePillBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '双指缩放 · 双击放大 · 单击隐藏控制栏',
                      style: TextStyle(
                        color: chromeFg.withValues(alpha: 0.78),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
