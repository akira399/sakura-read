import 'package:flutter/material.dart';

import '../../core/theme/sakura_layout.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/pet_store.dart';
import '../../data/prefs.dart';
import '../../ui/reader/reader_settings_panel.dart';

/// 阅读与排版默认设置页：顶部附实时纸感排版预览窗，下方挂载精排设置面板。
class ReadingDefaultsPage extends StatelessWidget {
  const ReadingDefaultsPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读与排版默认')),
      body: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) {
          final bg = prefs.readerBg;
          final isWide = SakuraLayout.isWide(context);
          final hInsets = SakuraLayout.horizontalInsets(context);

          final previewCard = Container(
            padding: EdgeInsets.symmetric(
              horizontal: prefs.readerMarginH.clamp(12, 32),
              vertical: 16,
            ),
            decoration: BoxDecoration(
              color: bg.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sakura.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '实时排版预览 · ${bg.name} · ${prefs.fontSize.round()}pt',
                  style: TextStyle(
                    color: bg.textColor.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${prefs.paragraphIndent ? '　　' : ''}穿过县界长长的隧道，便是雪国。夜空下一片白茫茫。火车在信号所前停了下来。',
                  style: TextStyle(
                    color: bg.textColor,
                    fontSize: prefs.fontSize.clamp(14, 24),
                    height: prefs.lineHeight,
                    letterSpacing: prefs.letterSpacing,
                    fontFamily: prefs.fontFamily.isEmpty
                        ? null
                        : prefs.fontFamily,
                  ),
                ),
              ],
            ),
          );

          final settingsCard = Material(
            color: sakura.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: sakura.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ReaderSettingsPanel(
                prefs: prefs,
                petStore: PetStore.shared,
              ),
            ),
          );

          if (isWide) {
            return SafeArea(
              top: false,
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: SakuraLayout.contentMaxWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      hInsets.left,
                      10,
                      hInsets.right,
                      20,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(child: previewCard),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 6,
                          child: SingleChildScrollView(child: settingsCard),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(hInsets.left, 8, hInsets.right, 36),
            children: [previewCard, const SizedBox(height: 16), settingsCard],
          );
        },
      ),
    );
  }
}
