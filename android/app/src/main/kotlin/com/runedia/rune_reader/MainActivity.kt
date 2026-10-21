package com.runedia.rune_reader

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
