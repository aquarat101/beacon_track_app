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
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.plugin.common.EventChannel
import org.altbeacon.beacon.*

object BeaconScanner : BeaconConsumer {

    private const val IBEACON_LAYOUT = "m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24"
    private const val SCAN_INTERVAL = 60_000L // ช่วงห่างของเวลาที่จะสแกน 60 วิ
    private const val SCAN_DURATION = 5_000L // ช่วงเวลาที่จะสแกน 5 วิ

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
    }

    private fun acquireWakeLock() {
        val pm = appContext?.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (wakeLock == null) {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MyApp::BeaconScanWakeLock")
            wakeLock?.acquire() // ไม่จำกัดเวลา ต้อง release เองตอน stopScanning
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
        releaseWakeLock()
    }

    private fun startIntermittentBleScan() {
        if (scanHandler != null) return
        scanHandler = Handler(Looper.getMainLooper())
        scanRunnable =
                object : Runnable {
                    override fun run() {
                        if (!isScanning) return
                        if (checkBlePermission()) {
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
                        }
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

    private fun checkBlePermission(): Boolean = true

    // key = beaconId, value = last seen timestamp (ms)
    private val detectedBeacons = mutableMapOf<String, Long>()
    private val DETECT_COOLDOWN = 15_000L // 15 วินาที

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
                        val beaconId = beaconIdBytes.toString(Charsets.US_ASCII)

                        val now = System.currentTimeMillis()
                        val lastSeen = detectedBeacons[beaconId] ?: 0L
                        if (now - lastSeen < DETECT_COOLDOWN) return // ยัง cooldown -> ข้าม

                        detectedBeacons[beaconId] = now // update timestamp

                        Log.d("BLE Scanning", "✅ $name , $beaconId")

                        loadKidsBeacons { kidBeacons ->
                            if (kidBeacons.contains(beaconId)) {
                                Log.d("BeaconScanner", "✅ Contains kid beacons: $beaconId ($name)")
                                eventSink?.success(
                                        mapOf(
                                                "name" to name,
                                                "beaconId" to beaconId,
                                                "type" to "BLE",
                                                "timestamp" to now
                                        )
                                )

                                getCurrentLocation { lat, lng ->
                                    Log.d("Debug", "✅ Current location: $lat, $lng")
                                    updateKidStatus(beaconId, lat, lng)
                                }
                            }
                        }
                    }
                }
            }

    fun loadZones() {
        val db = FirebaseFirestore.getInstance()
        db.collection("places").get().addOnSuccessListener { snapshot ->
            zones.clear()
            for (doc in snapshot.documents) {
                val data = doc.data ?: continue

                val lat =
                        when (val v = data["lat"]) {
                            is Number -> v.toDouble()
                            is String -> v.toDoubleOrNull() ?: continue
                            else -> continue
                        }

                val lng =
                        when (val v = data["lng"]) {
                            is Number -> v.toDouble()
                            is String -> v.toDoubleOrNull() ?: continue
                            else -> continue
                        }

                zones.add(
                        mapOf(
                                "id" to doc.id,
                                "userId" to data["userId"]!!,
                                "lat" to lat,
                                "lng" to lng,
                                "radius" to 500.0
                        )
                )
                // Log.d("BeaconScanner", "✅ Zone loaded: ${doc.id} lat=$lat lng=$lng")
            }
            Log.d("BeaconScanner", "✅ Zones loaded: ${zones.size}")
        }
    }

    fun loadKidsBeacons(onComplete: (Set<String>) -> Unit) {
        val db = FirebaseFirestore.getInstance()
        db.collection("kids")
                .get()
                .addOnSuccessListener { snapshot ->
                    val beacons = snapshot.documents.mapNotNull { it.getString("beaconId") }.toSet()
                    onComplete(beacons)
                }
                .addOnFailureListener { e ->
                    Log.e("BeaconScanner", "❌ Cannot load kids beacons: $e")
                    onComplete(emptySet())
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
        // Log.d("Function called", "✅ calculate distance")
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

    private fun updateKidStatus(beaconId: String, currentLat: Double, currentLng: Double) {
        Log.d("Function called", "✅ update kid staus")
        val db = FirebaseFirestore.getInstance()
        // Log.d("Debug", "✅ Current location: $zones")
        val closestZone =
                zones.minByOrNull { zone ->
                    calculateDistance(
                            currentLat,
                            currentLng,
                            zone["lat"] as Double,
                            zone["lng"] as Double
                    )
                }

        if (closestZone != null) {
            db.enableNetwork().addOnCompleteListener {
                db.collection("kids")
                        .whereEqualTo("beaconId", beaconId)
                        .limit(1)
                        .get()
                        .addOnSuccessListener { docs ->
                            if (docs.documents.isNotEmpty()) {
                                val kidDoc = docs.first()
                                val currentStatus = kidDoc.getString("status")

                                if (currentStatus == "online") {
                                    Log.d(
                                            "BeaconScanner",
                                            "ℹ️  Kid $beaconId is already online, skip update"
                                    )
                                    return@addOnSuccessListener
                                }

                                // ถ้า status ไม่ใช่ online ให้ update
                                kidDoc.reference
                                        .update("status", "online")
                                        .addOnSuccessListener {
                                            Log.d("BeaconScanner", "✅ Updated status=online")

                                            db.collection("beacon_zone_hits")
                                                    .add(
                                                            mapOf(
                                                                    "zoneId" to closestZone["id"],
                                                                    "userId" to
                                                                            closestZone["userId"],
                                                                    "beaconId" to beaconId,
                                                                    "timestamp" to Timestamp.now()
                                                            )
                                                    )
                                        }
                                        .addOnFailureListener { e ->
                                            Log.e("BeaconScanner", "❌ Failed update status: $e")
                                        }
                            } else {
                                Log.d("BeaconScanner", "❌ No docs for beaconId $beaconId")
                            }
                        }
                        .addOnFailureListener { e ->
                            Log.e("BeaconScanner", "❌ Firestore query failed: $e")
                        }
            }
        } else {
            Log.d("BeaconScanner", "❌ No closest zone")
        }
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
