import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/prefs.dart';
import 'widgets/sakura_petals.dart';

/// 首次启动的「使用条款与声明」确认页。
///
/// 同意后才进入书架与新手引导；不同意则退出应用。
///
/// 为什么要这一步：樱读内置了第三方书源，用户需要在使用前知道
/// 「正文内容来自第三方站点、版权归原作者」这件事，避免误以为
/// 软件本身提供内容。同类工具类应用通常都会在首启做一次确认。
class AgreementGate extends StatelessWidget {
  const AgreementGate({super.key, required this.prefs, required this.child});

  final AppPrefs prefs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => Stack(
        children: [
          child,
          if (!prefs.agreementAccepted)
            Positioned.fill(
              child: _AgreementView(
                onAccept: () => prefs.setAgreementAccepted(true),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgreementView extends StatefulWidget {
  const _AgreementView({required this.onAccept});

  final VoidCallback onAccept;

  @override
  State<_AgreementView> createState() => _AgreementViewState();
}

class _AgreementViewState extends State<_AgreementView> {
  bool _checked = false;

  void _accept() {
    if (!_checked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先勾选「我已阅读并同意」'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFFFFF6FA),
      child: SakuraPetals(
        count: 10,
        opacity: .35,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 品牌区
                      SizedBox(
                        width: 108,
                        height: 108,
                        child: Image.asset(
                          'assets/images/pet_chibi.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '欢迎来到樱读',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: Color(0xFF3A2B3D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '在开始之前，用一分钟了解一下她',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xB3A87E95),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // 特色介绍
                      const _Feature(
                        emoji: '📚',
                        title: '本地阅读',
                        desc: 'TXT / EPUB 全格式，自动识别编码与章节',
                      ),
                      const _Feature(
                        emoji: '🔍',
                        title: '在线搜书',
                        desc: '兼容「阅读 3.0」书源，一次搜索多个站点',
                      ),
                      const _Feature(
                        emoji: '🎀',
                        title: '看板娘小樱',
                        desc: '会陪你读书的桌宠，点她一下试试',
                      ),
                      const _Feature(
                        emoji: '🔊',
                        title: '语音朗读',
                        desc: '按段朗读、自动续读，解放双眼',
                      ),
                      const SizedBox(height: 18),
                      // 声明
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFFC7DE),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '声明与条款',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF3A2B3D),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '1. 樱读是阅读工具，本身不提供、不分发、不存储任何书籍内容。\n'
                              '2. 通过书源获取的正文来自第三方网站，版权归原作者与相应站点所有。\n'
                              '3. 请支持正版阅读；自行导入的书源与内容请确认合规。\n'
                              '4. 本软件以 MIT 协议开源，作者 akira399，欢迎反馈问题。',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.85,
                                color: Color(0xFF5B4552),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              // 勾选 + 按钮区
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _checked = !_checked),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _checked,
                              onChanged: (v) =>
                                  setState(() => _checked = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text(
                              '我已阅读并同意上述声明与条款',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5B4552),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _accept,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7EB6),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text(
                          '同意并继续',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text(
                        '暂不使用',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0x8A6B5B72),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 特色条目：emoji + 标题 + 说明。
class _Feature extends StatelessWidget {
  const _Feature({
    required this.emoji,
    required this.title,
    required this.desc,
  });

  final String emoji;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD9E8), width: 1),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2B3D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0x9E6B5B72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
