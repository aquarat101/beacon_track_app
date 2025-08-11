import 'dart:math';
import 'package:beacon_track_app/list_zone_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
// import 'package:android_intent_plus/android_intent.dart';

import 'select_zone_page.dart';
import 'package:beacon_track_app/service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Test',
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
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool scanning = false;
  List<String> inZoneBeacons = [];
  final Map<String, DateTime> beaconZoneLastHitTimes = {};
  final Set<String> pendingZoneHits = {};
  final Map<String, DateTime> zoneHitTimes = {};
  Map<String, Map<String, dynamic>> zoneHitData = {};
  String? userId = "";
  String? placeName = "";

  List<Map<String, dynamic>> zones = [];

  @override
  void initState() {
    super.initState();
    loadZones();
    FlutterBackgroundService().on('log_beacon').listen((event) {
      if (event == null) return;
      loadZones();
      // beaconRssi: (event['rssi'] ?? -100).toDouble(),
      checkBeaconInZones(
        beaconName: event['name'] ?? '',
        beaconId: event['beaconId'] ?? '',
        deviceLat: (event['lat'] ?? 0).toDouble(),
        deviceLng: (event['lng'] ?? 0).toDouble(),
      );
      print("✅ CheckBeaconInzones");
    });
  }

  Future<void> loadZones() async {
    final query = await FirebaseFirestore.instance.collection('places').get();
    zones = query.docs.map((doc) {
      final data = doc.data();
      userId = data['userId'].toString();
      placeName = data['name'].toString();

      return {
        'id': doc.id,
        'userId': data['userId'],
        'placeName': data['name'],
        'lat': data['lat'],
        'lng': data['lng'],
        'radius': 500.0,
      };
    }).toList();
    print('✅ โหลด zones แล้ว: ${zones.length} โซน');
  }

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

  Future<void> checkBeaconInZones({
    required String beaconName,
    required String beaconId,
    // required double beaconRssi,
    required double deviceLat,
    required double deviceLng,
  }) async {
    beaconId = beaconId.trim();

    double? minDistance;
    Map<String, dynamic>? closestZone;

    for (var zone in zones) {
      final double zoneLat = double.tryParse(zone['lat'].toString()) ?? 0.0;
      final double zoneLng = double.tryParse(zone['lng'].toString()) ?? 0.0;

      // if (zoneLat == null || zoneLng == null) continue;

      final distance = calculateDistance(
        deviceLat,
        deviceLng,
        zoneLat,
        zoneLng,
      );

      print("distance : ${distance} <= ${zone['radius']} ");
      // print("Distance: ${distance}");
      if (distance <= zone['radius']) {
        print("distance : ${distance} <= ${zone['radius']} ");
        // print("${distance} <= ${zone['radius']}");
        if (minDistance == null || distance < minDistance) {
          // print("Closest zone: ${zone}");
          minDistance = distance;
          closestZone = zone;
        }
      }
    }

    if (closestZone == null) {
      print("❌ ไม่พบโซนที่ใกล้พอ");
      return;
    }

    final zoneId = closestZone['id'];

    // ตรวจซ้ำใน Firestore (แก้เป็นเช็ค zoneId และเวลา 5(1) นาที)
    final timeNow = Timestamp.now();
    final fiveMinutesAgo = Timestamp.fromMillisecondsSinceEpoch(
      timeNow.millisecondsSinceEpoch - 1 * 60 * 1000,
    );

    final query = await FirebaseFirestore.instance
        .collection('beacon_zone_hits')
        .where('zoneId', isEqualTo: zoneId)
        .where(
          'timestamp',
          isGreaterThan: fiveMinutesAgo,
        ) // 1 minute on testing
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      print('❌ ข้าม Firestore: zoneId=$zoneId มีบันทึกใน 5 นาทีที่ผ่านมา');
      return;
    }

    await FirebaseFirestore.instance.collection('beacon_zone_hits').add({
      'zoneId': zoneId,
      'userId': userId,
      'beaconName': beaconName,
      'placeName': placeName,
      'beaconId': beaconId,
      'deviceLat': deviceLat,
      'deviceLng': deviceLng,
      'timestamp': timeNow,
    });

    // 'zoneId': zoneId,
    // 'userId': userId,
    // 'beaconName': name,
    // 'placeName': placeName,
    // 'beaconId': beaconId,
    // 'deviceLat': deviceLat,
    // 'deviceLng': deviceLng,
    // 'timestamp': timeNow,

    print("✅ บันทึก zone=${closestZone['name']} beaconId=$beaconId");
  }

  Future<void> requestPermissions(BuildContext context) async {
    // ขอ permission location, bluetooth, background location ฯลฯ
    final permissionsToRequest = [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationAlways,
    ];

    final statuses = await permissionsToRequest.request();

    // ตรวจสอบว่ามี Permission ตัวไหนบ้างที่ไม่ได้รับอนุญาต
    bool allGranted = true;
    for (var permission in permissionsToRequest) {
      if (statuses[permission] != PermissionStatus.granted) {
        allGranted = false;
        break; // พบตัวที่ไม่ได้รับอนุญาตแล้ว ออกจาก loop
      }
    }

    // ถ้ามี Permission ตัวใดตัวหนึ่งหรือมากกว่านั้นไม่ได้รับอนุญาต
    if (!allGranted) {
      // แสดง SnackBar หรือ Dialog เพื่อแจ้งผู้ใช้
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please, allow all permission for using this app.',
          ),
          action: SnackBarAction(
            label: 'Open setting',
            onPressed: () {
              // เปิดหน้าตั้งค่าแอป
              openAppSettings();
            },
          ),
        ),
      );
      // คุณอาจจะเพิ่ม Logic อื่นๆ ที่นี่ เช่น ไม่ให้ผู้ใช้เข้าถึงหน้าหลัก
    }
  }

  void startScan() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestPermissions(context);
    });
    await initializeService();
    // loadZones();
    var scanStatus = await Permission.bluetoothScan.request();
    var connectStatus = await Permission.bluetoothConnect.request();
    var locationStatus = await Permission.locationWhenInUse.request();

    if (scanStatus.isDenied ||
        connectStatus.isDenied ||
        locationStatus.isDenied) {
      // print("Permission denied");
      return;
    }

    FlutterBluePlus.startScan();
    setState(() {
      scanning = true;
    });
  }

  Future<void> stopScan() async {
    final service = FlutterBackgroundService();
    service.invoke('stop'); // ✅ ส่ง event 'stop' ไปยัง service
    print("🛑 ส่งคำสั่งหยุด service แล้ว");

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
                  scanning ? Icons.stop_circle : Icons.play_circle_fill,
                ),
                label: Text(
                  scanning ? 'Stop Scan Beacon' : 'Start Scan Beacon',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scanning ? Colors.red : Colors.green,
                ),
                onPressed: scanning ? stopScan : startScan,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Choose position in the map.'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const SelectZonePage(readOnly: false),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text('List of position.'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ZoneListPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
