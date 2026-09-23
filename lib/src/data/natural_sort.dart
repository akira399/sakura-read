/// 自然排序：让 "第2话" 排在 "第10话" 前面。
int naturalCompare(String a, String b) {
  final ca = _chunk(a);
  final cb = _chunk(b);
  final n = ca.length < cb.length ? ca.length : cb.length;
  for (var i = 0; i < n; i++) {
    final x = ca[i];
    final y = cb[i];
    if (x is int && y is int) {
      final c = x.compareTo(y);
      if (c != 0) return c;
    } else {
      final c = x.toString().toLowerCase().compareTo(
        y.toString().toLowerCase(),
      );
      if (c != 0) return c;
    }
  }
  return ca.length.compareTo(cb.length);
}

List<Object> _chunk(String s) {
  final out = <Object>[];
  final buf = StringBuffer();
  var numeric = false;

  void flush() {
    if (buf.isEmpty) return;
    final text = buf.toString();
    if (numeric) {
      out.add(int.tryParse(text) ?? text);
    } else {
      out.add(text);
    }
    buf.clear();
  }

  for (final rune in s.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    if (buf.isEmpty) {
      numeric = isDigit;
      buf.writeCharCode(rune);
    } else if (isDigit == numeric) {
      buf.writeCharCode(rune);
    } else {
      flush();
      numeric = isDigit;
      buf.writeCharCode(rune);
    }
  }
  flush();
  return out;
}
