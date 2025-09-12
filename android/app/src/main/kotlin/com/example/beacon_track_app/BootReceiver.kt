package com.example.beacon_track_app

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("Debug", "Boot completed: scheduling job + starting foreground service")

            // 1) Schedule job (ทำงานทุก 15 นาที)
            scheduleJob(context)

            // 2) Start Foreground Service (รันทันที พร้อม Notification)
            val serviceIntent = Intent(context, BeaconForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }

    companion object {
        fun scheduleJob(context: Context) {
            val serviceComponent = ComponentName(context, BeaconJobService::class.java)
            val jobInfo =
                    JobInfo.Builder(1, serviceComponent)
                            .setPeriodic(15 * 60 * 1000L) // ทุก 15 นาที
                            .setPersisted(true) // survive reboot
                            .build()

            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            scheduler.schedule(jobInfo)
        }
    }
}
