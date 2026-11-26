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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
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
                    errorBuilder: (_, _, _) => const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 42,
                          color: Colors.white54,
                        ),
                        SizedBox(height: 8),
                        Text(
                          '图片无法加载',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
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
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '双指缩放 · 双击放大',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
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
