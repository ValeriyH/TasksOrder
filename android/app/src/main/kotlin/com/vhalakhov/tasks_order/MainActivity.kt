package com.vhalakhov.tasks_order

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The home-screen widget (T-601, ADR-22): the app hands over the cache
        // of the coming days, lib/data/home_widget/channel_home_screen_widget.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasks_order/home_widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        TodayWidgetProvider.save(this, call.arguments as String)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
