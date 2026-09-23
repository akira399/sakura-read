import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/native_bridge.dart';
import 'widgets/cute.dart';
import 'widgets/sakura_petals.dart';

/// 首次启动的存储权限引导页（浅色 / 深色两套配色）。
class StoragePermissionPage extends StatelessWidget {
  const StoragePermissionPage({super.key, required this.onRecheck});

  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? const Color(0xFFF3E8F5)
        : const Color(0xFF5A3A55);
    final bodyColor = isDark
        ? const Color(0xFFCBB8CE)
        : const Color(0xFF7A5E75);
    final hintColor = isDark
        ? const Color(0xFF9C8BA0)
        : const Color(0xFF9A7E93);
    final stepTextColor = isDark
        ? const Color(0xFFDCCDE0)
        : const Color(0xFF6A4E65);
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SakuraPetals(
          count: 18,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [Color(0xFF1E1526), Color(0xFF241A33)]
                    : const [Color(0xFFFFE3EF), Color(0xFFEDE4FF)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Spacer(),
                    const PetalLogo(size: 96),
                    const SizedBox(height: 20),
                    Text(
                      '欢迎来到樱读',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '为了整理你的本地小说，\n需要授予「所有文件访问」权限。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: bodyColor, height: 1.6),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: .06)
                            : Colors.white.withValues(alpha: .75),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Step(
                            index: 1,
                            text: '点击下方按钮，进入系统权限页面',
                            color: stepTextColor,
                          ),
                          const SizedBox(height: 10),
                          _Step(
                            index: 2,
                            text: '允许「所有文件访问」权限',
                            color: stepTextColor,
                          ),
                          const SizedBox(height: 10),
                          _Step(
                            index: 3,
                            text: '回到应用即可自动继续',
                            color: stepTextColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        await NativeBridge.requestStoragePermission();
                        await onRecheck();
                      },
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('去授权'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => onRecheck(),
                      child: const Text('我已授权，刷新一下'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '如果无法跳转，请在系统「设置 → 应用 → 权限」中手动开启',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, required this.color});

  final int index;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFFFB7C5),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color, height: 1.4)),
        ),
      ],
    );
  }
}
