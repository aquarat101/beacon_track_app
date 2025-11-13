// BeaconScanner.kt (modified to call backend API instead of Firestore / direct LINE)
package com.example.beacon_track_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Base64
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.altbeacon.beacon.*
import org.json.JSONArray
import org.json.JSONObject

object BeaconScanner : BeaconConsumer {

    private const val IBEACON_LAYOUT = "m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24"
    private const val SCAN_INTERVAL = 60_000L // 60s
    private const val SCAN_DURATION = 15_000L // 15s
    private const val OFFLINE_COOLDOWN = 120_000L // 2 minutes

    private val API_BASE = "https://beacon-api.ksta.co/"
    // private val API_BASE = "https://5w01z325-3001.asse.devtunnels.ms"

    private lateinit var beaconManager: BeaconManager
    private var appContext: Context? = null
    private var region: Region? = null
    var eventSink: EventChannel.EventSink? = null

    private var isScanning = false
    private var bleAdapter: BluetoothAdapter? = null

    private var scanHandler: Handler? = null
    private var scanRunnable: Runnable? = null

    private var wakeLock: PowerManager.WakeLock? = null
    private lateinit var fusedLocationClient: FusedLocationProviderClient

    val zones = mutableListOf<Map<String, Any>>()

    private val detectedBeacons =
            mutableMapOf<String, Long>() // beaconId -> lastSeenMs (device local)
    private val lastStatusUpdate = mutableMapOf<String, Long>()
    private val STATUS_COOLDOWN = 15_000L // 15s
    private val loggedBeacons = mutableSetOf<String>()

    private val okClient =
            OkHttpClient.Builder()
                    .callTimeout(30, TimeUnit.SECONDS)
                    .connectTimeout(10, TimeUnit.SECONDS)
                    .build()

    private val executor = Executors.newSingleThreadExecutor()
    private val bgExecutor = Executors.newCachedThreadPool()

    private var offlineHandler: Handler? = null
    private var offlineRunnable: Runnable? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        eventSink = null

        beaconManager = BeaconManager.getInstanceForApplication(appContext!!)
        BeaconManager.setDistanceModelUpdateUrl("")
        beaconManager.setEnableScheduledScanJobs(false)

        val channelId = "my_foreground"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm =
                    appContext!!.getSystemService(Context.NOTIFICATION_SERVICE) as
                            NotificationManager
            nm.createNotificationChannel(
                    NotificationChannel(
                            channelId,
                            "Beacon Scan",
                            NotificationManager.IMPORTANCE_HIGH
                    )
            )
        }
        val notification =
                NotificationCompat.Builder(appContext!!, channelId)
                        .setContentTitle("Beacon scanning")
                        .setContentText("Running in background")
                        .setSmallIcon(android.R.drawable.ic_search_category_default)
                        .build()
        beaconManager.enableForegroundServiceScanning(notification, 456)

        beaconManager.beaconParsers.clear()
        beaconManager.beaconParsers.add(BeaconParser().setBeaconLayout(IBEACON_LAYOUT))
        beaconManager.beaconParsers.add(
                BeaconParser().setBeaconLayout("m:2-3=beac,i:4-19,i:20-21,i:22-23,p:24-24")
        )
        beaconManager.beaconParsers.add(
                BeaconParser().setBeaconLayout("m:4-5=4c00,i:6-21,i:22-23,i:24-25,p:26-26")
        )

        region = Region("all-beacons-region", null, null, null)
        beaconManager.bind(this)

        bleAdapter = BluetoothAdapter.getDefaultAdapter()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(appContext!!)
        acquireWakeLock()

        // preload zones & kids beacons
        loadZones()
        loadKidsBeacons { /* no-op */}
    }

    private fun acquireWakeLock() {
        val pm = appContext?.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (wakeLock == null) {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MyApp::BeaconScanWakeLock")
            wakeLock?.acquire()
            Log.d("BeaconScanner", "✅ WakeLock acquired")
        }
    }

    fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
            wakeLock = null
            Log.d("BeaconScanner", "✅ WakeLock released")
        }
    }

    fun startScanning() {
        if (isScanning) return
        isScanning = true
        updateScanMode()
        region?.let {
            try {
                beaconManager.startMonitoringBeaconsInRegion(it)
                beaconManager.startRangingBeaconsInRegion(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        startIntermittentBleScan()
        startOfflineChecker()
    }

    fun stopScanning() {
        if (!isScanning) return
        isScanning = false
        try {
            region?.let {
                beaconManager.stopMonitoringBeaconsInRegion(it)
                beaconManager.stopRangingBeaconsInRegion(it)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        stopIntermittentBleScan()
        stopOfflineChecker()
        releaseWakeLock()
    }

    private fun startIntermittentBleScan() {
        if (scanHandler != null) return
        scanHandler = Handler(Looper.getMainLooper())
        scanRunnable =
                object : Runnable {
                    override fun run() {
                        if (!isScanning) return
                        val scanner = bleAdapter?.bluetoothLeScanner ?: return
                        val settings =
                                ScanSettings.Builder()
                                        .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                                        .setReportDelay(0)
                                        .build()
                        val filters: List<ScanFilter> = listOf(ScanFilter.Builder().build())
                        scanner.startScan(filters, settings, scanCallback)
                        Log.d("BLE Scanner", ">>> Start BLE scan")

                        loadZones()

                        scanHandler?.postDelayed(
                                {
                                    scanner.stopScan(scanCallback)
                                    Log.d("BLE Scanner", "<<< Stop BLE scan")
                                },
                                SCAN_DURATION
                        )

                        scanHandler?.postDelayed(this, SCAN_INTERVAL)
                    }
                }
        scanHandler?.post(scanRunnable!!)
    }

    private fun stopIntermittentBleScan() {
        scanHandler?.removeCallbacksAndMessages(null)
        scanHandler = null
        scanRunnable = null
        bleAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
    }

    private val scanCallback =
            object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val device = result.device
                    val name = device.name ?: return
                    if (name == "Unknown BLE") return

                    val scanRecord = result.scanRecord ?: return
                    for (i in 0 until scanRecord.manufacturerSpecificData.size()) {
                        val data = scanRecord.manufacturerSpecificData.valueAt(i)
                        if (data.size <= 3) continue

                        val beaconIdBytes = data.copyOfRange(3, data.size)
                        val beaconId = Base64.encodeToString(beaconIdBytes, Base64.NO_WRAP)

                        if (!loggedBeacons.contains(beaconId)) {
                            Log.d("BLE Scanner", "Beacon found: $beaconId")
                            loggedBeacons.add(beaconId)
                        }

                        val now = System.currentTimeMillis()
                        val lastUpdate = lastStatusUpdate[beaconId] ?: 0L
                        if (now - lastUpdate < STATUS_COOLDOWN) return

                        lastStatusUpdate[beaconId] = now
                        detectedBeacons[beaconId] = now

                        loadKidsBeacons { kidBeacons ->
                            if (kidBeacons.contains(beaconId)) {
                                // Get current location once and call update status
                                getCurrentLocation { lat, lng ->
                                    updateKidStatus(beaconId, name, lat, lng)
                                }
                            }
                        }
                    }
                }

                override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                    super.onBatchScanResults(results)
                    markOfflineBeacons()
                }

                override fun onScanFailed(errorCode: Int) {
                    super.onScanFailed(errorCode)
                    Log.e("BLE Scanner", "Scan failed: $errorCode")
                }
            }

    // ---------------- offline checker (device side sends detected map to backend) ----------------
    private fun startOfflineChecker() {
        if (offlineHandler != null) return
        offlineHandler = Handler(Looper.getMainLooper())
        offlineRunnable =
                object : Runnable {
                    override fun run() {
                        markOfflineBeacons()
                        offlineHandler?.postDelayed(this, OFFLINE_COOLDOWN)
                    }
                }
        offlineHandler?.post(offlineRunnable!!)
        Log.d("BeaconScanner", "✅ Offline checker started")
    }

    private fun stopOfflineChecker() {
        offlineHandler?.removeCallbacksAndMessages(null)
        offlineHandler = null
        offlineRunnable = null
        Log.d("BeaconScanner", "✅ Offline checker stopped")
    }

    /**
     * markOfflineBeacons -- ส่ง detectedBeacons map ไป backend เพื่อให้ backend ตัดสินใจ offline /
     * re-alert
     */
    private fun markOfflineBeacons() {
        Log.d("BeaconScanner", "Mark Offline Called (device -> backend)")

        val payload = JSONObject()
        val map = JSONObject()
        for ((beaconId, lastSeen) in detectedBeacons) {
            map.put(beaconId, lastSeen)
        }
        payload.put("detectedBeacons", map)
        payload.put("timestampMs", System.currentTimeMillis())

        val url = "$API_BASE/kid/checkOffline"
        bgExecutor.execute {
            try {
                val mediaType = "application/json; charset=utf-8".toMediaType()
                val body = payload.toString().toRequestBody(mediaType)

                val req = Request.Builder().url(url).post(body).build()
                okClient.newCall(req).execute().use { resp ->
                    val respBody = resp.body?.string()
                    if (respBody != null) Log.d("BeaconScanner", "checkOffline body: $respBody")
                }
            } catch (e: Exception) {
                Log.e("BeaconScanner", "checkOffline error: $e")
            }
        }
    }

    /** loadZones -> GET /api/zones */
    fun loadZones() {
        val url = "$API_BASE/zone/getZones"
        bgExecutor.execute {
            val req = Request.Builder().url(url).get().build()
            try {
                okClient.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) {
                        return@use
                    }
                    val body = resp.body?.string() ?: ""
                    val json = JSONObject(body)
                    if (!json.optBoolean("success", true)) {
                        Log.e("BeaconScanner", "loadZones success=false")
                        return@use
                    }
                    val arr = json.optJSONArray("data") ?: JSONArray()
                    zones.clear()
                    for (i in 0 until arr.length()) {
                        val o = arr.getJSONObject(i)
                        val zone = mutableMapOf<String, Any>()
                        zone["id"] = o.optString("id")
                        zone["userId"] = o.optString("userId")
                        zone["lat"] = o.optDouble("lat", 0.0)
                        zone["lng"] = o.optDouble("lng", 0.0)
                        zone["name"] = o.optString("name")
                        zone["type"] = o.optString("type")
                        zone["radius"] = o.optDouble("radius", 500.0)
                        zones.add(zone)
                    }
                    Log.d("BeaconScanner", "✅ Zones loaded: ${zones.size}")
                }
            } catch (e: Exception) {
                Log.e("BeaconScanner", "loadZones error: $e")
            }
        }
    }

    /** loadKidsBeacons -> GET /api/kids/beacons */
    fun loadKidsBeacons(onComplete: (Set<String>) -> Unit) {
        val url = "$API_BASE/kid/beacons"
        bgExecutor.execute {
            val req = Request.Builder().url(url).get().build()
            try {
                okClient.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) {
                        return@use
                    }
                    val body = resp.body?.string() ?: ""
                    val json = JSONObject(body)
                    val arr = json.optJSONArray("data") ?: JSONArray()
                    val set = mutableSetOf<String>()
                    for (i in 0 until arr.length()) {
                        set.add(arr.optString(i))
                    }
                    onComplete(set)
                }
            } catch (e: Exception) {
                Log.e("BeaconScanner", "loadKidsBeacons error: $e")
                onComplete(emptySet())
            }
        }
    }

    /**
     * updateKidStatus -> POST /api/kids/updateStatus body: beaconId, beaconName, lat, lng,
     * timestampMs
     */
    private fun updateKidStatus(
            beaconId: String,
            beaconName: String,
            currentLat: Double,
            currentLng: Double
    ) {
        Log.d("Function called", "✅ update kid status (device -> backend) for $beaconId")
        val url = "$API_BASE/kid/updateStatus"
        val payload = JSONObject()
        payload.put("beaconId", beaconId)
        payload.put("beaconName", beaconName)
        payload.put("lat", currentLat)
        payload.put("lng", currentLng)
        payload.put("timestampMs", System.currentTimeMillis())

        bgExecutor.execute {
            val mediaType = "application/json; charset=utf-8".toMediaType()
            val body = payload.toString().toRequestBody(mediaType)

            val req = Request.Builder().url(url).post(body).build()
            try {
                okClient.newCall(req).execute().use { resp ->
                    // optional: parse response for debug
                    val respBody = resp.body?.string()

                    if (respBody != null) Log.d("BeaconScanner", "updateKidStatus body: $respBody")
                }
            } catch (e: Exception) {
                Log.e("BeaconScanner", "updateKidStatus error: $e")
            }
        }
    }

    private fun getCurrentLocation(callback: (lat: Double, lng: Double) -> Unit) {
        Log.d("Function called", "✅ Get current location")
        try {
            if (ActivityCompat.checkSelfPermission(
                            appContext!!,
                            Manifest.permission.ACCESS_FINE_LOCATION
                    ) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.e("BeaconScanner", "Location permission not granted")
                return
            }
            fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                if (location != null) callback(location.latitude, location.longitude)
            }
        } catch (e: Exception) {
            Log.e("BeaconScanner", "getCurrentLocation error: $e")
        }
    }

    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a =
                Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                        Math.cos(Math.toRadians(lat1)) *
                                Math.cos(Math.toRadians(lat2)) *
                                Math.sin(dLon / 2) *
                                Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    fun updateScanMode() {
        if (!::beaconManager.isInitialized) return
        val pm = appContext?.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isInteractive) {
            beaconManager.backgroundScanPeriod = 100_000L
            beaconManager.backgroundBetweenScanPeriod = 0L
        } else {
            beaconManager.foregroundScanPeriod = 10_000L
            beaconManager.foregroundBetweenScanPeriod = 5_000L
        }
    }

    override fun onBeaconServiceConnect() {
        beaconManager.addMonitorNotifier(
                object : MonitorNotifier {
                    override fun didEnterRegion(region: Region?) {
                        sendEvent("ENTER", region)
                    }

                    override fun didExitRegion(region: Region?) {
                        sendEvent("EXIT", region)
                    }

                    override fun didDetermineStateForRegion(state: Int, region: Region?) {}
                }
        )
    }

    private fun sendEvent(event: String, region: Region?) {
        eventSink?.success(mapOf("event" to event, "id" to region?.uniqueId))
    }

    override fun getApplicationContext(): Context = appContext!!

    override fun unbindService(conn: ServiceConnection) {
        appContext?.unbindService(conn)
    }

    override fun bindService(
            intent: Intent?,
            serviceConnection: ServiceConnection,
            mode: Int
    ): Boolean {
        if (intent == null) return false
        return try {
            appContext?.bindService(intent, serviceConnection, mode) ?: false
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
