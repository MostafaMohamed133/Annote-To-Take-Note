package com.example.road_guard_annotator

import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val clockChannel = "road_guard/clock"

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(TAG, "MainActivity onCreate")
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "Flutter engine configured; registering clock channel")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, clockChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureClockSnapshot" -> {
                        try {
                            // SensorEvent.timestamp uses the elapsed-realtime time base.
                            // Keep this as the authoritative timestamp for IMU alignment.
                            val monotonicNs = SystemClock.elapsedRealtimeNanos()
                            val utcEpochMs = System.currentTimeMillis()
                            val offsetMinutes = TimeZone.getDefault()
                                .getOffset(utcEpochMs) / 60_000

                            result.success(
                                mapOf(
                                    "monotonicNs" to monotonicNs,
                                    "utcEpochMs" to utcEpochMs,
                                    "timezoneOffsetMinutes" to offsetMinutes
                                )
                            )
                        } catch (exception: Exception) {
                            Log.e(TAG, "Clock snapshot failed", exception)
                            result.error(
                                "CLOCK_CAPTURE_FAILED",
                                exception.message ?: "Unknown clock capture error",
                                null
                            )
                        }
                    }
                    "setKeepScreenOn" -> {
                        try {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        } catch (exception: Exception) {
                            Log.e(TAG, "Could not update keep-screen-on flag", exception)
                            result.error(
                                "KEEP_SCREEN_ON_FAILED",
                                exception.message ?: "Unknown window error",
                                null
                            )
                        }
                    }
                    "diagnosticPing" -> result.success("road_guard_native_ok")
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val TAG = "RoadGuardAnnotator"
    }
}
