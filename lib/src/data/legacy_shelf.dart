import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

List<Map<String, dynamic>> parseLegacyShelf(Uint8List bytes) {
  if (bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('备份文件超过 30 MB');
  }
  if (bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entry = archive.files
        .where(
          (f) =>
              f.isFile &&
              f.name.split('/').last.toLowerCase() == 'bookshelf.json',
        )
        .firstOrNull;
    if (entry == null || entry.size > 30 * 1024 * 1024) {
      throw const FormatException('备份中未找到 bookshelf.json 或文件过大');
    }
    bytes = Uint8List.fromList(entry.content as List<int>);
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  final list = decoded is List
      ? decoded
      : decoded is Map
      ? decoded['books']
      : null;
  if (list is! List || list.length > 10000) {
    throw const FormatException('请选择阅读导出的 bookshelf.json 或含该文件的备份 ZIP');
  }
  return list
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
