package com.runedia.rune_reader

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var volumeKeyPaging = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rune_reader/volume_keys",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeyPaging = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rune_reader/storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasStorageAccess())
                "requestAccess" -> {
                    requestStorageAccess()
                    result.success(null)
                }
                "roots" -> result.success(storageRoots())
                else -> result.notImplemented()
            }
        }
    }

    // Reading arbitrary files by path in shared storage needs "All files
    // access" on Android 11+ and READ_EXTERNAL_STORAGE before that.
    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestStorageAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName"),
                    ),
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), 1)
        }
    }

    private fun storageRoots(): List<String> {
        val roots = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val manager = getSystemService(StorageManager::class.java)
            manager?.storageVolumes?.forEach { volume ->
                volume.directory?.path?.let { roots.add(it) }
            }
        }
        if (roots.isEmpty()) {
            @Suppress("DEPRECATION")
            roots.add(Environment.getExternalStorageDirectory().path)
        }
        return roots
    }

    // Activity.dispatchKeyEvent runs before the view hierarchy, so the
    // system volume change can be suppressed while paging is enabled.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        if (volumeKeyPaging &&
            (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val direction = if (code == KeyEvent.KEYCODE_VOLUME_DOWN) "next" else "previous"
                volumeChannel?.invokeMethod("key", direction)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
