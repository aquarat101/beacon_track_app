import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:beacon_track_app/service.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:wakelock_plus/wakelock_plus.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:disable_battery_optimization/disable_battery_optimization.dart';


const platform = MethodChannel('beacon_service');

Future<void> startBeaconService() async {
  try {
    await platform.invokeMethod('startScan');
  } catch (e) {
    print(e);
  }
}

Future<void> stopBeaconService() async {
  try {
    await platform.invokeMethod('stopScan');
  } catch (e) {
    print(e);
  }
}

final EventChannel _beaconChannel = EventChannel("beacon_events");

void startBeaconListener() {
  print("🟢🟢🟢 BEACON LISTENER 🟢🟢🟢");
  _beaconChannel.receiveBroadcastStream().listen(
    (event) {
      print("🟢 Beacon event: $event");
    },
    onError: (error) {
      print("🔴 Beacon event error: $error");
    },
  );
}

/// ========================
/// Main
/// ========================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeService();

  // เริ่มฟัง beacon events
  // startBeaconService();
  // startBeaconListener();

  runApp(const MyApp());

  // startBeaconService();
}

/// ========================
/// Main App Widget
/// ========================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// ========================
/// Home Page
/// ========================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool scanning = false;
  List<Map<String, dynamic>> zones = [];
  final FlutterBackgroundService service = FlutterBackgroundService();

  final Map<String, DateTime> beaconZoneLastHitTimes = {};
  final Map<String, Map<String, dynamic>> zoneHitData = {};

  @override
  void initState() {
    super.initState();
    // WakelockPlus.enable();
    // loadZones();
    startScan();
  }

  /// ========================
  /// Request Permissions
  /// ========================
  // Future<void> requestIgnoreBatteryOptimizations() async {
  //   await platform.invokeMethod('requestIgnoreBatteryOptimization');
  // }
  // Future<void> checkAndRequestBatteryOptimization() async {
  //   bool? isDisabled =
  //       await DisableBatteryOptimization.isBatteryOptimizationDisabled;
  //   print("🔋 Battery optimization disabled? $isDisabled");

  //   if (!isDisabled!) {
  //     await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
  //   }
  // }

  Future<void> requestPermissions(BuildContext context) async {
    final permissionsToRequest = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
    ];

    final statuses = await permissionsToRequest.request();
    bool allGranted = true;
    for (var permission in permissionsToRequest) {
      if (statuses[permission] != PermissionStatus.granted) {
        allGranted = false;
        print("❌❌❌ ${permission}");
        break;
      } else {
        print("✅✅ $permission");
      }
    }

    // checkAndRequestBatteryOptimization();

    if (!allGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please, allow all permission for using this app.',
          ),
          action: SnackBarAction(
            label: 'Open setting',
            onPressed: openAppSettings,
          ),
        ),
      );
    }
  }

  /// ========================
  /// Haversine distance
  /// ========================
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// ========================
  /// Load zones from Firestore
  /// ========================
  Future<void> loadZones() async {
    final query = await FirebaseFirestore.instance.collection('places').get();
    zones = query.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'userId': data['userId'],
        'type': data['type'],
        'lat': data['lat'],
        'lng': data['lng'],
        'radius': 500.0,
      };
    }).toList();
    print('✅ โหลด zones แล้ว: ${zones.length} โซน');
  }

  /// ========================
  /// Start Scan
  /// ========================
  void startScan() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestPermissions(context);
    });

    // await initializeService();

    var scanStatus = await Permission.bluetoothScan.request();
    var connectStatus = await Permission.bluetoothConnect.request();
    var locationStatus = await Permission.locationWhenInUse.request();

    if (scanStatus.isDenied ||
        connectStatus.isDenied ||
        locationStatus.isDenied) {
      return;
    }

    startBeaconListener();
    startBeaconService();
    // FlutterBluePlus.startScan();
    setState(() {
      scanning = true;
    });
  }

  /// ========================
  /// Stop Scan
  /// ========================
  Future<void> stopScan() async {
    service.invoke('stop');
    print("🛑 ส่งคำสั่งหยุด service แล้ว 🛑");

    stopBeaconService();

    setState(() {
      scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scanning ? Colors.red.shade100 : Colors.green.shade100,
      appBar: AppBar(
        title: const Text(
          "Beacon Track",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: scanning ? Colors.red : Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: Icon(
                  Icons.play_circle_fill, color: Colors.white,
                  // scanning ? Icons.stop_circle : Icons.play_circle_fill, color: Colors.white,
                ),
                label: Text(
                  "Scanning beacons...",
                  // scanning ? 'Stop Scan Beacon' : 'Start Scan Beacon',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scanning ? Colors.red : Colors.green,
                ),
                // onPressed: scanning ? stopScan : startScan,
                onPressed: () {},
              ),

              const SizedBox(height: 24),

              // ElevatedButton(
              //   onPressed: requestIgnoreBatteryOptimizations,
              //   child: const Text("ReqIgnoreBatOpt"),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
