import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/core/database/sakura_database.dart';
import 'package:sakura_read/src/core/theme/sakura_tokens.dart';
import 'package:sakura_read/src/features/book_source/replace_rule.dart';
import 'package:sakura_read/src/features/book_source/replace_rule_store.dart';
import 'package:sakura_read/src/features/book_source/replace_rules_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('ReplaceRule Legado 3.0 模型与作用域匹配', () {
    test('兼容 Legado JSON 字段导入与导出', () {
      final raw = jsonEncode([
        {
          'id': 1001,
          'name': '去网址水印',
          'pattern': r'请记住本书.*$',
          'replacement': '',
          'isRegex': true,
          'scope': '诡秘之主, https://biquge.example',
          'isEnabled': true,
          'order': 5,
        },
        {
          'name': '字面量替换',
          'pattern': '错别字',
          'replacement': '正确字',
          'isRegex': false,
          'enabled': false,
          'sortOrder': 12,
        },
      ]);

      final list = ReplaceRule.listFromJsonText(raw);
      expect(list, hasLength(2));

      final first = list.first;
      expect(first.id, '1001');
      expect(first.name, '去网址水印');
      expect(first.isRegex, isTrue);
      expect(first.isEnabled, isTrue);
      expect(first.order, 5);
      expect(first.toJson()['isEnabled'], isTrue);
      expect(first.toJson()['order'], 5);

      final second = list.last;
      expect(second.isRegex, isFalse);
      expect(second.isEnabled, isFalse);
      expect(second.order, 12);
    });

    test('正则捕获组替换、非法正则容错与作用域过滤（含排除 !规则）', () {
      const regexRule = ReplaceRule(
        id: 'r1',
        name: '方括号转书名号',
        pattern: r'\[([^\]]+)\]',
        replacement: r'《$1》',
        isRegex: true,
        scope: '诡秘之主, !番外',
      );
      expect(regexRule.matchesScope(bookTitle: '诡秘之主'), isTrue);
      expect(regexRule.matchesScope(bookTitle: '诡秘之主番外'), isFalse);
      expect(regexRule.matchesScope(bookTitle: '斗破苍穹'), isFalse);
      expect(regexRule.applyTo('他打开了[罗塞尔日记]。'), '他打开了《罗塞尔日记》。');

      const badRegex = ReplaceRule(
        id: 'r_bad',
        name: '坏正则',
        pattern: '[unclosed',
        replacement: '',
        isRegex: true,
      );
      expect(badRegex.validatePattern(), isNotNull);
      expect(badRegex.applyTo('原文不变'), '原文不变');
    });
  });

  group('ReplaceRuleStore SQLite DAO 持久化与 applyRules API', () {
    late SakuraDatabase db;

    setUp(() async {
      db = await SakuraDatabase.open(
        dbPath: ':memory:',
        factory: databaseFactoryFfi,
      );
    });

    tearDown(() async {
      await db.close();
      await ReplaceRuleStore.shared.clearAll();
    });

    test('CRUD 持久化到 SakuraDatabase 并按 order 依次净化正文', () async {
      final store = ReplaceRuleStore(database: db);
      await store.load();
      expect(store.isEmpty, isTrue);

      await store.upsert(
        const ReplaceRule(
          id: 'r_order_2',
          name: '清理多余空行',
          pattern: r'\n{3,}',
          replacement: '\n\n',
          isRegex: true,
          order: 20,
        ),
      );
      await store.upsert(
        const ReplaceRule(
          id: 'r_order_1',
          name: '去广告行',
          pattern: r'【广告[^\n]*】',
          replacement: '',
          isRegex: true,
          order: 10,
        ),
      );
      await store.upsert(
        const ReplaceRule(
          id: 'r_scoped',
          name: '仅对特定书源生效',
          pattern: '旧称呼',
          replacement: '新称呼',
          isRegex: false,
          scope: 'https://source-a.example',
          order: 15,
        ),
      );

      // 重载验证 SQLite 持久化
      final reloaded = ReplaceRuleStore(database: db);
      await reloaded.load();
      expect(reloaded.rules.map((r) => r.id), [
        'r_order_1',
        'r_scoped',
        'r_order_2',
      ]);

      const rawText = '第一段旧称呼。\n\n\n【广告：请收藏】\n\n\n第二段。';
      final cleanedA = reloaded.apply(
        rawText,
        bookTitle: '测试书',
        sourceUrl: 'https://source-a.example/book/1',
      );
      expect(cleanedA, '第一段新称呼。\n\n第二段。');

      final cleanedB = reloaded.apply(
        rawText,
        bookTitle: '测试书',
        sourceUrl: 'https://source-b.example/book/1',
      );
      expect(cleanedB, '第一段旧称呼。\n\n第二段。');

      // 停用规则并持久化校验
      await reloaded.setEnabled('r_order_1', false);
      final afterToggle = ReplaceRuleStore(database: db);
      await afterToggle.load();
      expect(
        afterToggle.rules.firstWhere((r) => r.id == 'r_order_1').isEnabled,
        isFalse,
      );

      // 删除规则
      await afterToggle.delete('r_scoped');
      final afterDelete = ReplaceRuleStore(database: db);
      await afterDelete.load();
      expect(afterDelete.rules.length, 2);
    });

    test('静态快捷入口 ReplaceRuleStore.applyRules 供阅读器直接调用', () async {
      await ReplaceRuleStore.shared.clearAll();
      await ReplaceRuleStore.shared.upsert(
        const ReplaceRule(
          id: 'shared_1',
          name: '去水印',
          pattern: '首发网址：test.com',
          replacement: '',
          isRegex: false,
        ),
      );

      expect(ReplaceRuleStore.applyRules('正文内容首发网址：test.com！'), '正文内容！');
    });

    test('Legado JSON 批量导入与导出', () async {
      final store = ReplaceRuleStore(database: db);
      final report = await store.importFromJson(
        jsonEncode([
          {'id': 'a', 'name': '规则A', 'pattern': 'foo', 'replacement': 'bar'},
          {'id': 'b', 'name': '无效空规则', 'pattern': ''},
        ]),
      );
      expect(report.ok, isTrue);
      expect(report.added, 1);
      expect(report.skipped, 1);
      expect(store.exportJson(), contains('规则A'));
    });
  });

  group('ReplaceRulesPage Widget UI 测试', () {
    testWidgets('空状态加载预设、切换开关并打开净化试测面板', (tester) async {
      final store = ReplaceRuleStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [SakuraColors.light(SakuraAccents.sakura)],
          ),
          home: ReplaceRulesPage(store: store),
        ),
      );

      expect(find.text('正文净化规则'), findsOneWidget);
      expect(find.text('还没有正文净化规则'), findsOneWidget);

      await tester.tap(find.text('一键添加常用预设'));
      await tester.pumpAndSettle();
      expect(store.rules.length, greaterThanOrEqualTo(3));
      expect(find.text('去除常见网址广告'), findsOneWidget);

      // 打开净化试测面板
      await tester.tap(find.byTooltip('净化试测'));
      await tester.pumpAndSettle();
      expect(find.text('净化效果实时试测'), findsOneWidget);
    });
  });
}
