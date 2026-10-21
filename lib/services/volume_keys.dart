import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Bridges Android volume keys to page turns (see `MainActivity.kt`).
///
/// Only one owner (reader page) receives keys at a time. When a reader is
/// replaced by another, the new one enables before the old one disposes;
/// [disable] therefore ignores calls from a previous owner.
class VolumeKeys {
  VolumeKeys._();

  static const _channel = MethodChannel('rune_reader/volume_keys');
  static Object? _owner;
  static void Function(bool next)? _listener;

  static Future<void> enable(Object owner, void Function(bool next) onKey) async {
    _owner = owner;
    _listener = onKey;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'key') _listener?.call(call.arguments == 'next');
    });
    await _invoke(true);
  }

  static Future<void> disable(Object owner) async {
    if (!identical(_owner, owner)) return;
    _owner = null;
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

/// Reference-counted reader chrome: restores system bars and releases the
/// wakelock only when the last open reader closes.
class ReaderChrome {
  ReaderChrome._();

  static int _active = 0;

  static void acquire() => _active++;

  static void release() {
    _active = (_active - 1).clamp(0, 1 << 20);
    if (_active > 0) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((Object _) {});
  }
}
