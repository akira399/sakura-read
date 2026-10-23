import 'dart:io';

import 'natural_sort.dart';

/// 支持的小说扩展名。
const Set<String> kNovelExtensions = {'txt', 'epub'};

/// 书源文件的扩展名（阅读 3.0 书源为 JSON；也允许用户存成 .txt）。
const Set<String> kSourceFileExtensions = {'json', 'txt'};

const Set<String> _skippedNames = {
  '.thumbnails',
  '.git',
  '.nomedia',
  'android',
  '\$recycle.bin',
  'system volume information',
  'lost.dir',
  'node_modules',
};

bool isSkippedDirName(String name) =>
    _skippedNames.contains(name.toLowerCase()) || name.startsWith('.');

/// 最后一个路径分隔符的下标（同时兼容 `/` 与 Windows 的 `\`）。
///
/// Android 上只可能出现 `/`，但桌面端（Windows）的 `Directory.list` 回传的是
/// 反斜杠路径；只认 `/` 的话文件名 / 扩展名解析会把整条路径当成文件名，
/// 于是导入时所有文件都被扩展名过滤掉。
int _lastSeparator(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  return slash > backslash ? slash : backslash;
}

String pathFileName(String path) {
  final i = _lastSeparator(path);
  return i < 0 ? path : path.substring(i + 1);
}

String pathBaseName(String path) {
  final name = pathFileName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String pathExtension(String path) {
  final name = pathFileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isNovelFile(String path) => kNovelExtensions.contains(pathExtension(path));

/// 当前目录下的小说文件（不递归）。
Future<List<File>> novelFilesIn(Directory dir) async {
  final files = <File>[];
  await for (final e in dir.list(followLinks: false)) {
    if (e is File &&
        !pathFileName(e.path).startsWith('.') &&
        isNovelFile(e.path)) {
      files.add(e);
    }
  }
  files.sort((a, b) => naturalCompare(a.path, b.path));
  return files;
}

/// 递归扫描目录里的小说文件。
Future<List<File>> scanNovelFiles(Directory dir, {int maxDepth = 6}) async {
  final files = <File>[];
  await _collect(dir, files, 0, maxDepth);
  files.sort((a, b) => naturalCompare(a.path, b.path));
  return files;
}

Future<void> _collect(
  Directory dir,
  List<File> out,
  int depth,
  int maxDepth,
) async {
  if (depth > maxDepth) return;
  await for (final e in dir.list(followLinks: false)) {
    if (e is File) {
      if (!pathFileName(e.path).startsWith('.') && isNovelFile(e.path)) {
        out.add(e);
      }
    } else if (e is Directory) {
      if (isSkippedDirName(pathFileName(e.path))) continue;
      await _collect(e, out, depth + 1, maxDepth);
    }
  }
}
