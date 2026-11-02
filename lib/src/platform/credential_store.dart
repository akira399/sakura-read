import 'dart:io';
import 'package:flutter/services.dart';

/// Android backend encrypts with a non-exportable Android Keystore AES key.
/// Desktop previews keep credentials in memory only; never fall back to JSON.
class CredentialStore {
  static const channel = MethodChannel('sakuraread/credentials');
  String? _memory;

  Future<String?> read() async =>
      Platform.isAndroid ? channel.invokeMethod<String>('read') : _memory;

  Future<void> write(String value) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('write', value);
    } else {
      _memory = value;
    }
  }
}
