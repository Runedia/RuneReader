import 'package:flutter/services.dart';

/// Shared-storage access for the folder browser (see `MainActivity.kt`).
class StorageAccess {
  StorageAccess._();

  static const _channel = MethodChannel('rune_reader/storage');

  static Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } on MissingPluginException {
      return true; // Not Android: plain file access.
    }
  }

  /// Opens the system permission screen. Re-check with [hasAccess] when the
  /// app resumes.
  static Future<void> requestAccess() async {
    try {
      await _channel.invokeMethod<void>('requestAccess');
    } on MissingPluginException {
      // Not Android.
    }
  }

  static Future<List<String>> roots() async {
    try {
      final list = await _channel.invokeListMethod<String>('roots');
      return list ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
