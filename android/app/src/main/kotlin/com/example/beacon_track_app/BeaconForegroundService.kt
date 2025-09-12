package com.example.beacon_track_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
// aimport android.app.ServiceInfo
import android.app.ForegroundServiceTypeException
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.beacon_track_app.BeaconJobService

class BeaconForegroundService : Service() {
        private lateinit var wakeLock: PowerManager.WakeLock

        override fun onCreate() {
                super.onCreate()

                val pm = getSystemService(POWER_SERVICE) as PowerManager
                wakeLock =
                        pm.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "beacon_track_app::ForegroundWakeLock"
                        )
                wakeLock.acquire()

                val channelId = "my_foreground"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val nm = getSystemService(NotificationManager::class.java)
                        nm.createNotificationChannel(
                                NotificationChannel(
                                        channelId,
                                        "Beacon Scanner",
                                        NotificationManager.IMPORTANCE_HIGH
                                )
                        )
                }

                val notification =
                        NotificationCompat.Builder(this, channelId)
                                .setContentTitle("Beacon tracking foreground")
                                .setContentText("Tap to open")
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .build()

                startForeground(
                        1,
                        notification,
                        // ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                        // ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                        // ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )

                BeaconScanner.init(this)
                Log.d("Debug", "Scanning HERE")
                BeaconScanner.startScanning()
        }

        override fun onDestroy() {
                super.onDestroy()
                BeaconScanner.stopScanning()
        }

        override fun onBind(intent: Intent?): IBinder? = null
}
