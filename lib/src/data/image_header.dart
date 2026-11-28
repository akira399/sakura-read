import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

final LinkedHashMap<String, Size?> _fileSizeCache =
    LinkedHashMap<String, Size?>();
const int _kMaxCacheEntries = 256;
const int _kHeaderReadBytes = 65536;

/// Reads natural pixel dimensions from encoded PNG / JPEG / GIF / WebP / BMP bytes.
Size? readImageSizeFromBytes(Uint8List bytes) {
  if (bytes.length < 12) return null;

  // PNG: 89 50 4E 47 0D 0A 1A 0A + IHDR
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    final w = _uint32BE(bytes, 16);
    final h = _uint32BE(bytes, 20);
    return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
  }

  // GIF87a / GIF89a
  if (bytes.length >= 10 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    final w = _uint16LE(bytes, 6);
    final h = _uint16LE(bytes, 8);
    return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
  }

  // WebP: RIFF....WEBP
  if (bytes.length >= 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    final c0 = bytes[12];
    final c1 = bytes[13];
    final c2 = bytes[14];
    final c3 = bytes[15];
    // "VP8 "
    if (c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x20) {
      if (bytes[23] == 0x9D && bytes[24] == 0x01 && bytes[25] == 0x2A) {
        final w = _uint16LE(bytes, 26) & 0x3FFF;
        final h = _uint16LE(bytes, 28) & 0x3FFF;
        return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
      }
    }
    // "VP8L"
    if (c0 == 0x56 &&
        c1 == 0x50 &&
        c2 == 0x38 &&
        c3 == 0x4C &&
        bytes[20] == 0x2F) {
      final bits = _uint32LE(bytes, 21);
      final w = (bits & 0x3FFF) + 1;
      final h = ((bits >> 14) & 0x3FFF) + 1;
      return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
    }
    // "VP8X"
    if (c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x58) {
      final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
    }
    return null;
  }

  // BMP: "BM"
  if (bytes.length >= 26 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    final dibSize = _uint32LE(bytes, 14);
    if (dibSize == 12) {
      final w = _uint16LE(bytes, 18);
      final h = _uint16LE(bytes, 20);
      return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
    }
    final w = _int32LE(bytes, 18);
    final h = _int32LE(bytes, 22).abs();
    return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
  }

  // JPEG: FF D8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i++];
      if (marker == 0x00 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      if (i + 1 >= bytes.length) break;
      final segLen = _uint16BE(bytes, i);
      if (segLen < 2) break;
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof && i + 6 < bytes.length) {
        final h = _uint16BE(bytes, i + 3);
        final w = _uint16BE(bytes, i + 5);
        return (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : null;
      }
      i += segLen;
    }
  }

  return null;
}

/// Reads natural image pixel size from disk using a bounded 64 KB header read
/// and caches by path + file size + mtime.
Size? readImageSizeFromFile(String path) {
  if (path.isEmpty) return null;
  try {
    final file = File(path);
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
    final key = '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    if (_fileSizeCache.containsKey(key)) {
      final cached = _fileSizeCache.remove(key);
      _fileSizeCache[key] = cached;
      return cached;
    }
    final raf = file.openSync();
    final Uint8List header;
    try {
      final toRead = stat.size < _kHeaderReadBytes
          ? stat.size
          : _kHeaderReadBytes;
      header = raf.readSync(toRead);
    } finally {
      raf.closeSync();
    }
    final size = readImageSizeFromBytes(header);
    _fileSizeCache[key] = size;
    while (_fileSizeCache.length > _kMaxCacheEntries) {
      _fileSizeCache.remove(_fileSizeCache.keys.first);
    }
    return size;
  } catch (_) {
    return null;
  }
}

int _uint16BE(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _uint16LE(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _uint32BE(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _uint32LE(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _int32LE(Uint8List b, int o) =>
    ByteData.sublistView(b, o, o + 4).getInt32(0, Endian.little);
