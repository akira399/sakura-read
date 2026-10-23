import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/data/ai_service.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';

Book _book() => Book(
  id: 'b1',
  title: '测试书',
  author: '作者甲',
  format: BookFormat.txt,
  path: '/tmp/b1.txt',
  intro: '一本用于测试的书。',
  chapters: [
    ChapterRef(title: '第一章 起点', start: 0, end: 100, charCount: 100),
  ],
  totalChars: 100,
  chapterIndex: 0,
  charOffset: 50,
  addedAt: 1700000000000,
  lastReadAt: 1700000000000,
);

ReadingSnapshot _snapshot() => ReadingSnapshot(
  totalBooks: 1,
  readingBooks: 1,
  finishedBooks: 0,
  totalSeconds: 3600,
  streak: 3,
  readDays: 5,
  recentDays: const [('2026-10-20', 600)],
  books: [_book()],
  recentlyAdded: [_book()],
);

AppPrefs _prefs({bool includeReading = true}) => AppPrefs()
  ..aiBaseUrl = 'https://example.com/v1'
  ..aiModel = 'test-model'
  ..aiIncludeReading = includeReading;

void main() {
  group('AiService.endpointFor', () {
    test('只填到 /v1 时补全 /chat/completions', () {
      expect(
        AiService.endpointFor('https://example.com/v1'),
        'https://example.com/v1/chat/completions',
      );
    });

    test('末尾斜杠会被清理', () {
      expect(
        AiService.endpointFor('https://example.com/v1/'),
        'https://example.com/v1/chat/completions',
      );
    });

    test('已经填完整路径时保持不变', () {
      const full = 'https://example.com/v1/chat/completions';
      expect(AiService.endpointFor(full), full);
    });

    test('空地址返回空字符串', () {
      expect(AiService.endpointFor('  '), '');
    });
  });

  group('阅读数据快照', () {
    test('toPrompt 包含书架与进度信息', () {
      final prompt = _snapshot().toPrompt();
      expect(prompt, contains('共 1 本'));
      expect(prompt, contains('测试书'));
      expect(prompt, contains('作者甲'));
      expect(prompt, contains('连续阅读 3 天'));
    });

    test('空书架有明确说明', () {
      final prompt = ReadingSnapshot(
        totalBooks: 0,
        readingBooks: 0,
        finishedBooks: 0,
        totalSeconds: 0,
        streak: 0,
        readDays: 0,
        recentDays: const [],
        books: const [],
        recentlyAdded: const [],
      ).toPrompt();
      expect(prompt, contains('书架是空的'));
    });
  });

  group('AiService.chat', () {
    test('请求体包含模型、历史与阅读数据，并返回回复文本', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': ' 你好，我是小樱～ '},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AiService(client: client);

      final reply = await service.chat(
        prefs: _prefs(),
        history: const [AiTurn.user('我最近读到哪了？')],
        snapshot: _snapshot(),
      );

      expect(reply, '你好，我是小樱～');
      expect(requests, hasLength(1));
      expect(
        requests.single.url.toString(),
        'https://example.com/v1/chat/completions',
      );
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('测试书'));
      expect(messages.last['role'], 'user');
      expect(messages.last['content'], '我最近读到哪了？');
    });

    test('关闭阅读数据共享时，提示词里不含书架数据', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '好的'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = AiService(client: client);

      await service.chat(
        prefs: _prefs(includeReading: false),
        history: const [AiTurn.user('你好')],
        snapshot: _snapshot(),
      );

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      final system = messages.first['content'] as String;
      expect(system, contains('关闭了阅读数据共享'));
      expect(system, isNot(contains('测试书')));
    });

    test('401 会变成可展示的提示', () async {
      final client = MockClient(
        (request) async => http.Response('{"error":"bad key"}', 401),
      );
      final service = AiService(client: client);

      await expectLater(
        service.chat(prefs: _prefs(), history: const [AiTurn.user('你好')]),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });

    test('没有 choices 时抛出异常', () async {
      final client = MockClient(
        (request) async => http.Response('{"choices":[]}', 200),
      );
      final service = AiService(client: client);

      await expectLater(
        service.chat(prefs: _prefs(), history: const [AiTurn.user('你好')]),
        throwsA(isA<AiException>()),
      );
    });

    test('地址未填写时直接提示', () async {
      final service = AiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final prefs = AppPrefs()..aiModel = 'test-model';

      await expectLater(
        service.chat(prefs: prefs, history: const [AiTurn.user('你好')]),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('接口地址'),
          ),
        ),
      );
    });
  });
}
