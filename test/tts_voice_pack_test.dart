import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/data/tts_voice_catalog.dart';
import 'package:sakura_read/src/data/tts_voice_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';

/// 造一个最小的 tar.bz2，里面带 sherpa 需要的那几个文件。
Uint8List buildTtsArchive({
  String root = 'unit-pack',
  bool withTokens = true,
  bool withOnnx = true,
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  if (withOnnx) add('$root/model.onnx', 'fake-onnx-bytes');
  if (withTokens) add('$root/tokens.txt', 'a 0\nb 1\n');
  add('$root/lexicon.txt', '词 词\n');
  add('$root/number.fst', 'fst');
  final tar = TarEncoder().encode(archive);
  return Uint8List.fromList(BZip2Encoder().encode(tar));
}

void main() {
  group('语音包目录', () {
    test('id 唯一，内置包排第一且不需要下载', () {
      final ids = ttsVoiceCatalog.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ttsVoiceCatalog.first.bundled, isTrue);
      expect(ttsVoiceCatalog.first.mirrors, isEmpty);
      for (final pack in ttsVoiceCatalog.where((p) => !p.bundled)) {
        expect(pack.mirrors, isNotEmpty, reason: '${pack.id} 没有下载地址');
        expect(pack.sizeMb, greaterThan(0));
      }
    });

    test('多说话人包提供男声 / 女声预设，sid 不重复', () {
      for (final pack in ttsVoiceCatalog.where((p) => p.isMultiSpeaker)) {
        expect(pack.presets.length, greaterThanOrEqualTo(2));
        final sids = pack.presets.map((p) => p.sid).toList();
        expect(sids.toSet().length, sids.length, reason: '${pack.id} 有重复 sid');
        final labels = pack.presets.map((p) => p.label).join();
        expect(labels, contains('男声'));
        expect(labels, contains('女声'));
        for (final preset in pack.presets) {
          expect(preset.sid, inInclusiveRange(0, pack.speakerCount - 1));
        }
      }
    });

    test('按 id 能取回，未知 id 返回 null', () {
      expect(
        ttsVoicePackById(builtinVoicePack.id)?.name,
        builtinVoicePack.name,
      );
      expect(ttsVoicePackById('不存在的包'), isNull);
    });
  });

  group('解析解压后的文件清单', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ttsvoice'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    void write(String name, [String content = 'x']) {
      File(
        '${tmp.path}${Platform.pathSeparator}$name',
      ).writeAsStringSync(content);
    }

    test('识别 model.onnx + tokens + lexicon + fst', () {
      write('model.onnx');
      write('tokens.txt');
      write('lexicon.txt');
      write('number.fst');
      write('date.fst');
      write('phone.fst');
      final files = resolveTtsVoiceFiles(tmp.path)!;
      expect(files.model, 'model.onnx');
      expect(files.tokens, 'tokens.txt');
      expect(files.lexicon, 'lexicon.txt');
      expect(files.ruleFsts.split(','), contains('number.fst'));
      expect(files.ruleFsts.split(',').length, 3);
    });

    test('只有具体名字的 onnx（piper 包）也能认出来', () {
      write('zh_CN-xiao_ya-medium.onnx');
      write('tokens.txt');
      write('lexicon.txt');
      expect(
        resolveTtsVoiceFiles(tmp.path)!.model,
        'zh_CN-xiao_ya-medium.onnx',
      );
      expect(resolveTtsVoiceFiles(tmp.path)!.ruleFsts, isEmpty);
    });

    test('缺 tokens 或没有 onnx 时返回 null', () {
      write('model.onnx');
      expect(resolveTtsVoiceFiles(tmp.path), isNull);
      write('tokens.txt');
      File('${tmp.path}${Platform.pathSeparator}model.onnx').deleteSync();
      expect(resolveTtsVoiceFiles(tmp.path), isNull);
    });

    test('目录不存在返回 null', () {
      expect(
        resolveTtsVoiceFiles('${tmp.path}${Platform.pathSeparator}无'),
        isNull,
      );
    });
  });

  group('下载 + 流式解压', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('ttsstore'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    TtsVoiceStore makeStore(Uint8List body, {int status = 200}) {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(body),
          status,
          contentLength: body.length,
        );
      });
      return TtsVoiceStore(
        client: client,
        dirsProvider: () async => AppDirs(files: tmp.path, cache: tmp.path),
      );
    }

    const pack = TtsVoicePack(
      id: 'unit-pack',
      name: '单元包',
      tagline: '测试用',
      sizeMb: 1,
      license: 'MIT',
      archiveName: 'unit-pack',
      mirrors: <String>['https://example.com/unit.tar.bz2'],
      bundled: false,
      speakerCount: 2,
      presets: <TtsVoicePreset>[
        TtsVoicePreset(label: '男声', sid: 0, hint: ''),
        TtsVoicePreset(label: '女声', sid: 1, hint: ''),
      ],
    );

    test('下载后解压出模型文件，顶层目录被剥掉', () async {
      final store = makeStore(buildTtsArchive());
      expect(await store.install(pack), isTrue);
      expect(store.isInstalled(pack.id), isTrue);
      final dir = await store.packDir(pack.id);
      final onnx = File('$dir${Platform.pathSeparator}model.onnx');
      expect(onnx.existsSync(), isTrue);
      expect(onnx.readAsStringSync(), 'fake-onnx-bytes');
      expect(resolveTtsVoiceFiles(dir), isNotNull);
    });

    test('压缩包里没有模型文件时判失败，不留半截目录', () async {
      final store = makeStore(buildTtsArchive(withOnnx: false));
      expect(await store.install(pack), isFalse);
      expect(store.isInstalled(pack.id), isFalse);
      expect(store.errorOf(pack.id), contains('模型文件'));
      final dir = await store.packDir(pack.id);
      expect(Directory(dir).existsSync(), isFalse);
      expect(Directory('$dir.part').existsSync(), isFalse);
    });

    test('HTTP 404 时给出中文错误，不装', () async {
      final store = makeStore(buildTtsArchive(), status: 404);
      expect(await store.install(pack), isFalse);
      expect(store.errorOf(pack.id), contains('下载失败'));
    });

    test('删除后目录消失、状态复位', () async {
      final store = makeStore(buildTtsArchive());
      await store.install(pack);
      await store.remove(pack.id);
      expect(store.isInstalled(pack.id), isFalse);
      expect(Directory(await store.packDir(pack.id)).existsSync(), isFalse);
    });

    test('内置包不需要下载，install 直接成功', () async {
      final store = makeStore(buildTtsArchive());
      expect(await store.install(builtinVoicePack), isTrue);
    });
  });
}
