package com.example.beacon_track_app

import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Context
import android.os.PowerManager
import android.util.Log
import org.altbeacon.beacon.*

class BeaconJobService : JobService() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartJob(params: JobParameters?): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BeaconJob::WakeLock")
        wakeLock?.acquire(10 * 1000L)
        Log.d("BeaconJob", "Job started - wake lock acquired")
        // ❌ อย่า bind BeaconManager ใหม่
        // ✅ Foreground service scan จะทำงานต่อ
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        wakeLock?.release()
        Log.d("BeaconJob", "Job stopped - wake lock released")
        return false
    }
}
