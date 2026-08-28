package com.yashwantsingh.riyaz

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "dev.riyaz/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val payload = call.arguments as? String
                        if (payload == null) {
                            result.error("BAD_ARGS", "Expected a JSON string", null)
                        } else {
                            // Store then redraw. Persisting first means a
                            // launcher that redraws on its own schedule still
                            // finds current data.
                            getSharedPreferences(
                                RiyazWidgetProvider.PREFS,
                                Context.MODE_PRIVATE
                            ).edit()
                                .putString(RiyazWidgetProvider.KEY_PAYLOAD, payload)
                                .apply()
                            RiyazWidgetProvider.refreshAll(applicationContext)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
