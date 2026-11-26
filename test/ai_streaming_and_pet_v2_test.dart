import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/core/database/sakura_database.dart';
import 'package:sakura_read/src/data/ai_service.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/features/ai_companion/inline_ai_reader_sheet.dart';
import 'package:sakura_read/src/features/ai_companion/spoiler_free_memory.dart';
import 'package:sakura_read/src/features/pet/live_sakura_pet.dart';
import 'package:sakura_read/src/features/pet/pet_mood_bus.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/ui/ai_chat_page.dart';
import 'package:sakura_read/src/ui/ai_settings_page.dart';
import 'package:sakura_read/src/ui/widgets/pet_overlay.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AppPrefs _configuredPrefs() => AppPrefs()
  ..aiBaseUrl = 'https://api.deepseek.com/v1'
  ..aiApiKey = 'sk-test-key'
  ..aiModel = 'deepseek-chat'
  ..aiIncludeReading = true;

MockClient _sseClient(
  List<String> tokens, {
  void Function(http.BaseRequest req)? onRequest,
}) {
  return MockClient.streaming((request, bodyStream) async {
    onRequest?.call(request);
    final chunks = <List<int>>[
      for (final token in tokens)
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': token},
              },
            ],
          })}\n\n',
        ),
      utf8.encode('data: [DONE]\n\n'),
    ];
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  });
}

void main() {
  tearDown(() {
    kPetMoodBus.reset();
    kPetEggActive.value = false;
  });

  group('Streaming AI SSE Engine', () {
    test('parseSseByteStream 支持跨分片 UTF-8 中文并正确终止于 [DONE]', () async {
      final raw =
          'data: {"choices":[{"delta":{"content":"樱花"}}]}\n\n'
          'data:{"choices":[{"delta":{"content":"飘落"}}]}\n\n'
          'data: [DONE]\n\n'
          'data: {"choices":[{"delta":{"content":"不应出现"}}]}\n\n';
      final bytes = utf8.encode(raw);
      // 故意按 3 字节切分，把中文 UTF-8 字符截断在相邻块中
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 3) {
        chunks.add(bytes.sublist(i, (i + 3).clamp(0, bytes.length)));
      }
      final out = await AiService.parseSseByteStream(
        Stream<List<int>>.fromIterable(chunks),
      ).toList();
      expect(out.join(), '樱花飘落');
    });

    test('chatStream 逐段返回 SSE token 且可由 AiCancelToken 优雅中止', () async {
      final service = AiService(
        client: _sseClient(const ['第一段', '，第二段', '，第三段']),
      );
      addTearDown(service.dispose);

      final all = await service
          .chatStream(
            prefs: _configuredPrefs(),
            history: const [AiTurn.user('你好')],
          )
          .toList();
      expect(all, ['第一段', '，第二段', '，第三段']);

      final token = AiCancelToken();
      final partial = <String>[];
      await for (final piece in service.chatStream(
        prefs: _configuredPrefs(),
        history: const [AiTurn.user('继续')],
        cancelToken: token,
      )) {
        partial.add(piece);
        token.cancel();
      }
      expect(partial, ['第一段']);
    });

    testWidgets('AiSettingsPage 提供 5 大一键预设芯片（含 Gemini）并自动填充', (tester) async {
      final prefs = AppPrefs();
      await tester.pumpWidget(MaterialApp(home: AiSettingsPage(prefs: prefs)));
      await tester.pump();

      for (final preset in kAiProviderPresets) {
        expect(find.text(preset.name), findsOneWidget);
      }

      await tester.tap(find.text('Gemini'));
      await tester.pump();

      final baseFields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        baseFields.first.controller?.text,
        'https://generativelanguage.googleapis.com/v1beta/openai',
      );
      expect(baseFields.elementAt(2).controller?.text, 'gemini-2.5-flash');
    });
  });

  group('InlineAiReaderSheet & Streaming AiConversationPage', () {
    testWidgets('InlineAiReaderSheet 渲染 4 个即时标签、流式输出并支持「存为本书笔记」', (
      tester,
    ) async {
      final marks = BookmarkStore();
      addTearDown(marks.dispose);

      final ai = AiService(
        client: _sseClient(const ['这句话用**樱花意象**点明了重逢的宿命感。']),
      );
      addTearDown(ai.dispose);

      final book = Book(
        id: 'b-inline',
        title: '春日来信',
        format: BookFormat.txt,
        path: '/tmp/b.txt',
        chapters: [ChapterRef(title: '第一章 樱花坡')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineAiReaderSheet(
              book: book,
              chapterIndex: 0,
              selectedText: '风穿过樱花坡，把旧信吹向了山谷。',
              prefs: _configuredPrefs(),
              aiService: ai,
              bookmarkStore: marks,
            ),
          ),
        ),
      );

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('语境解释'), findsOneWidget);
      expect(find.text('翻译'), findsOneWidget);
      expect(find.text('人物设定'), findsOneWidget);
      expect(find.text('赏析'), findsOneWidget);
      expect(find.textContaining('樱花意象'), findsOneWidget);
      expect(find.text('停止'), findsNothing, reason: '流式完成后应隐藏停止按钮');

      final saveBtn = find.widgetWithText(FilledButton, '存为本书笔记');
      expect(saveBtn, findsOneWidget);
      expect(
        tester.widget<FilledButton>(saveBtn).onPressed,
        isNotNull,
        reason: '存为本书笔记按钮应已启用',
      );
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(marks.count, 1);
      expect(marks.items.first.excerpt, contains('小樱伴读 · 语境解释'));
      expect(marks.items.first.excerpt, contains('樱花意象'));
      expect(find.widgetWithText(FilledButton, '已存为本书笔记'), findsOneWidget);

      kPetMoodBus.reset();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('AiConversationPage 显示快捷胶囊并支持实时流式回答', (tester) async {
      final ai = AiService(client: _sseClient(const ['推荐你继续读', '《春日来信》哦～']));
      addTearDown(ai.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AiConversationPage(
            store: BookStore(),
            prefs: _configuredPrefs(),
            aiService: ai,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('前情提要'), findsOneWidget);
      expect(find.text('帮我选下一本'), findsOneWidget);
      expect(find.text('整理人物关系'), findsOneWidget);
      expect(find.text('阅读习惯分析'), findsOneWidget);

      await tester.tap(find.text('帮我选下一本'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.textContaining('推荐你继续读《春日来信》哦～'), findsOneWidget);

      kPetMoodBus.reset();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Live Interactive Pet 2.0', () {
    test('PetMoodBus 正确桥接 AI 思考/回复与阅读里程碑情绪', () {
      final bus = PetMoodBus();
      addTearDown(bus.dispose);

      expect(bus.value, PetLiveMood.idle);
      bus.onAiThinking();
      expect(bus.value, PetLiveMood.thinking);
      bus.onAiSpeaking();
      expect(bus.value, PetLiveMood.speaking);
      bus.onAiIdle();
      expect(bus.value, PetLiveMood.idle);

      bus.onReadingMilestone('读完一章啦');
      expect(bus.value, PetLiveMood.happy);
      expect(bus.latestLine.value, '读完一章啦');
      bus.reset();
      expect(bus.value, PetLiveMood.idle);
    });

    test('petDockSideFor 智能贴边判定左右边缘与中间区', () {
      expect(petDockSideFor(dx: 10, maxX: 300), -1);
      expect(petDockSideFor(dx: 280, maxX: 300), 1);
      expect(petDockSideFor(dx: 150, maxX: 300), 0);
    });

    testWidgets('LiveSakuraPet 渲染原版 assets/images/pet_*.png 立绘及 8 种情绪与视线跟随', (
      tester,
    ) async {
      for (final mood in PetLiveMood.values) {
        final expectedAsset = petSpriteForMood(mood);
        expect(expectedAsset, startsWith('assets/images/pet_'));
        expect(expectedAsset, endsWith('.png'));
        expect(File(expectedAsset).existsSync(), isTrue);
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiveSakuraPet(
                mood: PetLiveMood.happy,
                size: 84,
                lookTarget: Offset(0.6, -0.4),
                motionEnabled: false,
                showSparkles: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<LiveSakuraPet>(find.byType(LiveSakuraPet)).resolvedAsset,
        'assets/images/pet_cheer.png',
      );
      final img = tester.widget<Image>(find.byType(Image).first);
      expect(img.image, isA<AssetImage>());
      expect(
        (img.image as AssetImage).assetName,
        'assets/images/pet_cheer.png',
      );

      // 验证专属动作立绘 assetOverride（如喝茶 pet_tea.png）同样使用原版图片
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiveSakuraPet(
                mood: PetLiveMood.idle,
                assetOverride: 'assets/images/pet_tea.png',
                motionEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<LiveSakuraPet>(find.byType(LiveSakuraPet)).resolvedAsset,
        'assets/images/pet_tea.png',
      );
    });

    testWidgets('PetOverlay 点击呼出快捷操作条（摸头/喂点心/问小樱/安静陪伴/隐藏），且连续狂点绝不锁屏', (
      tester,
    ) async {
      final pet = PetStore();
      addTearDown(pet.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              PetOverlay(pet: pet),
            ],
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // 单击呼出气泡快捷条
      await tester.tap(find.byKey(const ValueKey('pet_positioned')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('pet_quick_actions')), findsOneWidget);
      expect(find.text('摸头'), findsOneWidget);
      expect(find.text('喂点心'), findsOneWidget);
      expect(find.text('问小樱'), findsOneWidget);
      expect(find.text('安静陪伴'), findsOneWidget);
      expect(find.text('隐藏'), findsOneWidget);

      // 点「摸头」+2 亲密度
      final beforeAffinity = pet.affinity;
      await tester.tap(find.text('摸头'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pet.affinity, beforeAffinity + kPetPatPoints);

      // 连续狂点 12 次也绝不会触发永久黑屏锁定（只会可爱鼓嘴求点心）
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byType(LiveSakuraPet));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(kPetEggActive.value, isFalse);

      // 收尾清理定时器
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 65));
    });
  });

  group('Spoiler-Free Memory & SQLite ai_book_memory', () {
    test('严格防剧透：永远不读取大于 book.safeChapterIndex 的后续章节，并正确读写 SQLite 缓存', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('sakura_spoiler_test');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final db = await SakuraDatabase.open(
        dbPath: ':memory:',
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);

      final store = BookStore(
        dirsOverride: AppDirs(files: dir.path, cache: dir.path),
        database: db,
      );
      await store.load();

      final book = Book(
        id: 'book-spoiler-1',
        title: '雾都侦探录',
        format: BookFormat.online,
        path: 'https://example.test/novel/1',
        chapters: [
          ChapterRef(title: '第一章 雨夜来客'),
          ChapterRef(title: '第二章 失踪的怀表'),
          ChapterRef(title: '第三章 真凶现身'),
          ChapterRef(title: '第四章 终局反转'),
        ],
        chapterIndex: 1, // 读者当前仅读到第 2 章（下标 1）
      );

      final cacheDir = store.chapterCacheDir(book.id);
      await cacheDir.create(recursive: true);
      await File('${cacheDir.path}/ch_v2_0000.txt')
          .writeAsString('侦探林默在雨夜收到一封信。');
      await File('${cacheDir.path}/ch_v2_0001.txt')
          .writeAsString('管家发现书房里的金色怀表不见了。');
      await File('${cacheDir.path}/ch_v2_0002.txt')
          .writeAsString('【绝对剧透】真凶其实是管家本人！');
      await File('${cacheDir.path}/ch_v2_0003.txt')
          .writeAsString('【终局剧透】林默最后离开了雾都。');

      // 即使恶意传入 maxChapterOverride: 3，也必须被强行夹在 safeChapterIndex=1
      final ctx = await SpoilerFreeMemoryService.collectSafeContext(
        store,
        book,
        maxChapterOverride: 3,
      );
      expect(ctx.maxChapterIndex, 1);
      expect(ctx.includedChapterIndices, [0, 1]);
      expect(ctx.combinedText, contains('金色怀表'));
      expect(ctx.combinedText, isNot(contains('绝对剧透')));
      expect(ctx.combinedText, isNot(contains('终局剧透')));

      var apiCalls = 0;
      final ai = AiService(
        client: _sseClient(const [
          '**故事脉络**\n',
          '- 雨夜收到神秘信件\n',
          '- 书房金色怀表失踪',
        ], onRequest: (_) => apiCalls++),
      );
      addTearDown(ai.dispose);

      final memory = SpoilerFreeMemoryService(aiService: ai, database: db);
      final firstRun = await memory
          .streamRecap(store: store, book: book, prefs: _configuredPrefs())
          .join();
      expect(firstRun, contains('金色怀表失踪'));
      expect(apiCalls, 1);

      // 第二次同进度调用必须命中 SQLite ai_book_memory 缓存，不再发网络请求
      final secondRun = await memory
          .streamRecap(store: store, book: book, prefs: _configuredPrefs())
          .join();
      expect(secondRun, firstRun);
      expect(apiCalls, 1);

      // 如果读者进度回退到第 1 章（index=0），原 index=1 的缓存绝不允许倒灌剧透
      book.chapterIndex = 0;
      final leaked = await memory.loadCached(
        book: book,
        kind: SpoilerFreeMemoryService.kindRecap,
      );
      expect(leaked, isNull);
    });
  });
}
