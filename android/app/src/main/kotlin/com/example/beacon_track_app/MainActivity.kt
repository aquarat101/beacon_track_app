package com.example.beacon_track_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    init {
        Log.d("Debug", "🚀 MainActivity init block")
    }

    private lateinit var screenReceiver: ScreenReceiver
    private lateinit var wakeLock: PowerManager.WakeLock

    private val CHANNEL = "beacon_service"

    // ✅ อยู่แยก ไม่ได้อยู่ใน configureFlutterEngine
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("Debug", "✅ onCreate called")

        // --- WakeLock ---
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock =
                powerManager.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "beacon_track_app::BeaconWakeLock"
                )
        wakeLock.acquire() // เริ่มถือ wake lock

        // สร้าง receiver
        screenReceiver = ScreenReceiver()

        val filter =
                android.content.IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_OFF)
                    addAction(Intent.ACTION_SCREEN_ON)
                }

        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)

        if (wakeLock.isHeld) {
            wakeLock.release()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d("Debug", "🔥 configureFlutterEngine called")

        BootReceiver.scheduleJob(this)

        // สร้าง notification channel สำหรับ foreground service
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.d("Debug", "✅ Noti called")

            val channel =
                    NotificationChannel(
                            "my_foreground",
                            "Foreground Service",
                            NotificationManager.IMPORTANCE_HIGH
                    )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> {
                    Log.d("Debug", "⏩ Main startScan called")

                    // ✅ ขอ Ignore Battery Optimization
                    val packageName = applicationContext.packageName
                    val pm = getSystemService(PowerManager::class.java)
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        val intent = Intent()
                        intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        intent.data = Uri.parse("package:$packageName")
                        startActivity(intent)
                    }   

                    // 🔹 เรียก Foreground Service แทนการ start BeaconScanner ตรง ๆ
                    val serviceIntent = Intent(this, BeaconForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Log.d("VERSION", "🛑 VERSION >=")
                        startForegroundService(serviceIntent)
                    } else {
                        Log.d("VERSION", "🛑 VERSION <")
                        startService(serviceIntent)
                    }

                    result.success(null)
                }

                "stopScan" -> {
                    Log.d("Debug", "🛑 Main stopScan called")
                    BeaconScanner.stopScanning()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val eventChannel =
                EventChannel(
                        flutterEngine.dartExecutor.binaryMessenger,
                        "beacon_events"
                )
        eventChannel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        BeaconScanner.eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        BeaconScanner.eventSink = null
                    }
                }
        )
    }
}
