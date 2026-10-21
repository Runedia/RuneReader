import 'package:flutter/services.dart';

/// Bridges Android volume keys to page turns (see `MainActivity.kt`).
class VolumeKeys {
  VolumeKeys._();

  static const _channel = MethodChannel('rune_reader/volume_keys');
  static void Function(bool next)? _listener;

  static Future<void> enable(void Function(bool next) onKey) async {
    _listener = onKey;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'key') _listener?.call(call.arguments == 'next');
    });
    await _invoke(true);
  }

  static Future<void> disable() async {
    _listener = null;
    await _invoke(false);
  }

  static Future<void> _invoke(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // Not running on Android.
    } on PlatformException {
      // Ignore; volume keys keep their default behavior.
    }
  }
}
