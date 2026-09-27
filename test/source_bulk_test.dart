// 书源「批量管理」数据层回归测试。
//
// 背景（用户反馈「书源没法批量管理」）：书源只能逐个开关 / 删除，
// 导入大量书源后管理成本极高。本次给 SourceStore 增加批量 API：
//   - setEnabledAll：批量启用 / 停用（返回实际变更数）；
//   - removeMany：批量删除（返回实际删除数）；
// 并新增书源管理页的「批量管理模式」（全选 / 批量操作）与单源详情页。
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/source_store.dart';

BookSource _src(String url, {bool enabled = true}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url.replaceAll('https://', ''),
  enabled: enabled,
);

void main() {
  group('批量启用 / 停用（setEnabledAll）', () {
    test('批量停用：仅影响目标集合，返回变更数', () {
      final store = SourceStore(
        initial: [
          _src('https://a.com'),
          _src('https://b.com'),
          _src('https://c.com'),
        ],
      );

      final changed = store.setEnabledAll([
        'https://a.com',
        'https://b.com',
      ], false);
      expect(changed, 2);
      expect(store.byUrl('https://a.com')!.enabled, isFalse);
      expect(store.byUrl('https://b.com')!.enabled, isFalse);
      expect(store.byUrl('https://c.com')!.enabled, isTrue, reason: '未选中项不受影响');
    });

    test('已是目标状态的不计入变更数（幂等）', () {
      final store = SourceStore(
        initial: [
          _src('https://a.com', enabled: false),
          _src('https://b.com', enabled: true),
        ],
      );

      // a 已是 false 不需要改；b 需要改 → 只算 1
      expect(store.setEnabledAll(['https://a.com', 'https://b.com'], false), 1);
      // 再来一次：全部已 false → 0
      expect(store.setEnabledAll(['https://a.com', 'https://b.com'], false), 0);
    });

    test('批量启用：全部选中 → 全启用', () {
      final all = [
        _src('https://a.com', enabled: false),
        _src('https://b.com', enabled: false),
      ];
      final store = SourceStore(initial: all);
      expect(store.setEnabledAll(all.map((s) => s.bookSourceUrl), true), 2);
      expect(store.enabledCount, 2);
    });

    test('空集合 / 不存在的 URL：返回 0 且不报错', () {
      final store = SourceStore(initial: [_src('https://a.com')]);
      expect(store.setEnabledAll(const [], false), 0);
      expect(store.setEnabledAll(['https://gone.com'], false), 0);
    });
  });

  group('批量删除（removeMany）', () {
    test('删除选中项，返回删除数，其余保留', () {
      final store = SourceStore(
        initial: [
          _src('https://a.com'),
          _src('https://b.com'),
          _src('https://c.com'),
        ],
      );

      final removed = store.removeMany(['https://a.com', 'https://c.com']);
      expect(removed, 2);
      expect(store.sources.length, 1);
      expect(store.byUrl('https://b.com'), isNotNull);
    });

    test('包含不存在的 URL：按实际删除计数', () {
      final store = SourceStore(initial: [_src('https://a.com')]);
      expect(store.removeMany(['https://a.com', 'https://gone.com']), 1);
      expect(store.isEmpty, isTrue);
    });

    test('空集合：返回 0 且不触发变更', () {
      final store = SourceStore(initial: [_src('https://a.com')]);
      expect(store.removeMany(const []), 0);
      expect(store.sources.length, 1);
    });

    test('全删后为空（管理页据此退出批量模式）', () {
      final all = ['https://a.com', 'https://b.com'];
      final store = SourceStore(initial: all.map((u) => _src(u)).toList());
      expect(store.removeMany(all), 2);
      expect(store.isEmpty, isTrue);
    });
  });
}
