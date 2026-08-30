package com.yashwantsingh.riyaz

import android.appwidget.AppWidgetManager
import android.content.ComponentName
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
                    // Asks the launcher to place the widget.
                    //
                    // Widget discovery on Android is genuinely bad — long-press
                    // the wallpaper, find Widgets, scroll an alphabetical list
                    // of every app on the phone — and a feature nobody can find
                    // is a feature that does not exist. `requestPinAppWidget`
                    // hands the launcher a one-tap confirmation instead.
                    //
                    // The launcher decides, not us: it may refuse, and older or
                    // unusual launchers do not support pinning at all. Both
                    // cases return false rather than throwing, so the caller
                    // can say something useful instead of failing silently.
                    "pinWidget" -> {
                        val manager = AppWidgetManager.getInstance(this)
                        if (!manager.isRequestPinAppWidgetSupported) {
                            result.success(false)
                        } else {
                            result.success(
                                manager.requestPinAppWidget(
                                    ComponentName(
                                        this,
                                        RiyazWidgetProvider::class.java
                                    ),
                                    null,
                                    null
                                )
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
