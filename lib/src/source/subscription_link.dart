/// Accept a JSON subscription URL or the interoperable Legado import scheme.
String subscriptionUrl(String input) {
  var uri = Uri.tryParse(input.trim());
  if (uri?.scheme == 'legado' &&
      uri?.host == 'import' &&
      uri?.path.toLowerCase() == '/booksource') {
    uri = Uri.tryParse(uri!.queryParameters['src'] ?? '');
  }
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const FormatException(
      '请输入 HTTP(S) 书源订阅地址或 legado://import/bookSource 链接',
    );
  }
  return uri.toString();
}
