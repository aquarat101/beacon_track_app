import 'dart:async';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// import 'package:permission_handler/permission_handler.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  // await Firebase.initializeApp();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'กำลังทำงานอยู่',
      initialNotificationContent: 'แอปกำลังติดตาม Beacon อยู่',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  await service.startService();
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  print('iOS background fetch activated');
  return true;
}

Future<Position> getCurrentPosition() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services disabled');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions denied');
    }
  }
  return await Geolocator.getCurrentPosition();
}

bool _isScanning = false;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  service.on('stop').listen((event) async {
    print("🛑 รับคำสั่ง stop แล้ว");
    print("-----------------------------------------");
    await FlutterBluePlus.stopScan();
    await service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    print("-----------------------------------------");
    print("🕒 BG TICK: ${DateTime.now()}");
    if (service is AndroidServiceInstance &&
        !(await service.isForegroundService())) {
      return;
    }

    if (_isScanning) {
      print("⚠️ ข้ามรอบนี้เพราะกำลังสแกนอยู่");
      return;
    }

    _isScanning = true;

    try {
      final position = await Geolocator.getCurrentPosition();

      print("📳 !!!!! Start Scan !!!!! 📳");

      FlutterBluePlus.startScan(withServices: []);

      // โหลด beaconId จาก Firebase
      final kidsSnapshot = await FirebaseFirestore.instance
          .collection('kids')
          .get();
      final kidBeacons = kidsSnapshot.docs
          .map((doc) => doc.data()['beaconId'].toString())
          .toSet();

      final scannedSerials = <String>{};
      final scanSubscription = FlutterBluePlus.scanResults.listen((
        results,
      ) async {
        // ใน loop scanResults
        for (var r in results) {
          final data = r.advertisementData;

          // แปลง manufacturerData ทั้งหมดเป็น String
          for (var entry in data.manufacturerData.entries) {
            final bytes = entry.value;
            final serial = String.fromCharCodes(bytes.sublist(3));

            if (scannedSerials.contains(serial)) continue;
            scannedSerials.add(serial);

            // print("✅ พบ Hoco Tag: $serial");
            // 'rssi': r.rssi,

            if (kidBeacons.contains(serial)) {
              print("✅ พบ beacon ของเด็ก: $serial");
              service.invoke('log_beacon', {
                'name': r.advertisementData.advName,
                'beaconId': serial,
                'lat': position.latitude,
                'lng': position.longitude,
              });
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 6));
      await FlutterBluePlus.stopScan();
      await scanSubscription.cancel();
      scannedSerials.clear();
    } catch (e) {
      print('[BG] Error: $e');
    }

    _isScanning = false;
  });
}
