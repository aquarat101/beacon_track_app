package com.example.beacon_track_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ScreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SCREEN_OFF -> {
                Log.d("BeaconScannerDebug", "🔒 Screen OFF → background scan")
                // BeaconScanner.startScanning(context) // background mode
                BeaconScanner.updateScanMode()
                BeaconScanner.eventSink?.success(mapOf("screenOff" to true))
            }
            Intent.ACTION_SCREEN_ON -> {
                Log.d("BeaconScannerDebug", "💡 Screen ON → foreground scan")
                BeaconScanner.updateScanMode()
                // BeaconScanner.startScanning(context) // foreground mode
                BeaconScanner.eventSink?.success(mapOf("screenOff" to false))
            }
        }
    }
}
