// 内置离线语音的资源完整性测试。
//
// 背景（用户反馈「朗读暂时不可用 · 系统未安装语音合成引擎」）：很多机型根本没装
// 系统 TTS 引擎，所以内置了一份 sherpa-onnx + VITS 中文模型。模型是二进制资产，
// 一旦发布时漏打进 APK（pubspec 的 assets 漏配、文件被 .gitignore 吃掉、模型换版本
// 改名），运行期只会看到「内置语音加载失败」，很难定位。这里用最便宜的方式钉住：
// 清单里的每个文件都存在且不是空文件，pubspec 也确实声明了这个目录。
//
// 这里**不**加载原生库（CI 上没有 sherpa 的桌面 dll），只校验资源与接线常量。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/platform/offline_tts.dart';

void main() {
  group('内置离线语音资源', () {
    test('模型清单里的文件都存在且非空', () {
      for (final name in OfflineTtsEngine.assetFiles) {
        final f = File('${OfflineTtsEngine.assetDir}/$name');
        expect(f.existsSync(), isTrue, reason: '缺少内置语音文件 $name');
        expect(f.lengthSync(), greaterThan(16), reason: '$name 看起来是空文件或占位文件');
      }
    });

    test('主模型是 onnx，且 lexicon/tokens 也在清单里', () {
      final names = OfflineTtsEngine.assetFiles;
      expect(names.where((n) => n.endsWith('.onnx')).length, 1);
      expect(names, contains('lexicon.txt'));
      expect(names, contains('tokens.txt'));
    });

    test('pubspec 声明了内置语音 asset 目录', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- ${OfflineTtsEngine.assetDir}/'));
    });

    test('内置引擎 id 与系统引擎不冲突', () {
      // 设置页用它区分「内置」和系统引擎名；系统引擎名是包名（含点号），
      // 带冒号前缀保证不会撞车。
      expect(OfflineTtsEngine.engineId, startsWith('builtin:'));
    });
  });
}
