import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:wakelock_plus/wakelock_plus.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:permission_handler/permission_handler.dart';

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

Future<void> initializeService() async {
  print("✅🕒 INITIALIZE SERVICE 🕒✅: ${DateTime.now()}");
  // await Firebase.initializeApp();

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Beacon tracker',
      initialNotificationContent: 'Starting track beacon',
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

bool _isScanning = false;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    print("✅ SET AS FOREGROUND ✅");
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: "Beacon tracking in background",
      content: "Tap to open",
    );
    print("✅ NOTIFICATION SET ✅");
  }
  // WakelockPlus.enable();

  // Timer.periodic(Duration(seconds: 25), (_) {
  //   service.invoke('start_scan');
  // });

  // await platform.invokeMethod('startScan');
  // startBackground(service);

  startBeaconService();
  startBeaconListener();

  service.on('stop').listen((event) async {
    print("🛑 รับคำสั่ง stop แล้ว 🛑");
    print("-----------------------------------------");
    await FlutterBluePlus.stopScan();
    await service.stopSelf();

    stopBeaconService();
    // await platform.invokeMethod('stopScan');
    return;
  });
}

void startBackground(ServiceInstance service) async {
  //   print("✅🕒 START FOREGROUND SERVICE 🕒✅: ${DateTime.now()}");

  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  // Future.delayed(const Duration(seconds: 1), () async {
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    print("-----------------------------------------");
    print("🕒 BG TICK: ${DateTime.now()}");
    loadZones();

    if (service is AndroidServiceInstance &&
        !(await service.isForegroundService())) {
      return;
    }

    // print("⏩ before isScanning : ${_isScanning}");
    if (_isScanning) {
      print("🔔 ข้ามรอบนี้เพราะกำลังสแกนอยู่");
      print("-----------------------------------------");
      return;
    }

    _isScanning = true;

    try {
      final position = await Geolocator.getCurrentPosition();

      print("📳📳📳 Start Scan 📳📳📳");

      FlutterBluePlus.startScan(
        withServices: [],
        androidScanMode: AndroidScanMode.balanced,
      );

      await Future.delayed(const Duration(seconds: 20));

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
        // String beaconName;
        String beaconId;
        // double deviceLat;
        // double deviceLng;

        print('🛑🛑🛑 Detected beacon: ${results}');

        for (var r in results) {
          final data = r.advertisementData;

          for (var entry in data.manufacturerData.entries) {
            final bytes = entry.value;
            if (bytes.length < 3) {
              continue;
            }

            final serial = String.fromCharCodes(bytes.sublist(3));

            if (scannedSerials.contains(serial)) continue;
            scannedSerials.add(serial);

            if (data.advName != "") {
              print("${data.advName}");
            }
            if (kidBeacons.contains(serial)) {
              print("✅ พบ beacon ของเด็ก: $serial");
              // service.invoke('log_beacon', {
              //   'name': r.advertisementData.advName,
              //   'beaconId': serial,
              //   'lat': position.latitude,
              //   'lng': position.longitude,
              // });

              beaconId = serial.trim();
              double? minDistance;
              Map<String, dynamic>? closestZone;

              for (var zone in zones) {
                final zoneLat = double.tryParse(zone['lat'].toString()) ?? 0.0;
                final zoneLng = double.tryParse(zone['lng'].toString()) ?? 0.0;

                final distance = calculateDistance(
                  position.latitude.toDouble(),
                  position.longitude.toDouble(),
                  zoneLat,
                  zoneLng,
                );

                if (distance <= zone['radius'] &&
                    (minDistance == null || distance < minDistance)) {
                  minDistance = distance;
                  closestZone = zone;
                }
              }

              if (closestZone == null) {
                print("❌ ไม่พบโซนที่ใกล้พอ");
                try {
                  await FirebaseFirestore.instance
                      .collection('kids')
                      .doc(beaconId)
                      .update({'status': 'offline'});
                  print("✅ อัปเดต status ของเด็กเป็น offline");
                } catch (e) {
                  print("❌ ไม่สามารถอัปเดต status: $e");
                }
                return;
              }

              final kidQuery = await FirebaseFirestore.instance
                  .collection('kids')
                  .where('beaconId', isEqualTo: beaconId)
                  .limit(1)
                  .get();
              final kidDoc = kidQuery.docs.first;
              final status = kidDoc.data()['status'];

              if (status == 'offline') {
                try {
                  await FirebaseFirestore.instance
                      .collection('kids')
                      .doc(kidDoc.id)
                      .update({'status': 'online'});
                  await FirebaseFirestore.instance
                      .collection('beacon_zone_hits')
                      .add({
                        'zoneId': closestZone['id'],
                        'userId': closestZone['userId'],
                        'beaconName': r.advertisementData.advName,
                        'type': closestZone['type'],
                        'beaconId': beaconId,
                        'deviceLat': position.latitude,
                        'deviceLng': position.latitude,
                        'timestamp': Timestamp.now(),
                      });
                  print(
                    "✅ เด็ก offline → บันทึก zone=${closestZone['id']} beaconId=$beaconId และอัปเดต status เป็น online",
                  );
                } catch (e) {
                  print(
                    "❌ ไม่สามารถบันทึก beacon_zone_hits หรืออัปเดต status: $e",
                  );
                }
              } else {
                print("❌ เด็กออนไลน์อยู่แล้ว → ไม่บันทึกซ้ำ");
              }
            }
          }
        }
      });

      // print("⏩ after isScanning : ${_isScanning}");
      print("⏩ Loop done");
      await FlutterBluePlus.stopScan();

      final missingKids = kidBeacons.difference(scannedSerials);
      for (var missing in missingKids) {
        final kidQuery = await FirebaseFirestore.instance
            .collection('kids')
            .where('beaconId', isEqualTo: missing)
            .limit(1)
            .get();

        if (kidQuery.docs.isNotEmpty &&
            kidQuery.docs.first['status'] == 'online') {
          await FirebaseFirestore.instance
              .collection('kids')
              .doc(kidQuery.docs.first.id)
              .update({'status': 'offline'});

          print("❌ ไม่เจอ b. $missing → set offline");
        }
      }
      print("🔔 clean diff offline kid");

      await scanSubscription.cancel();
      scannedSerials.clear();
      print("🔔 clean diff done");
    } catch (e) {
      print('[BG] Error: $e');
    }

    // print("⏩ check : ${_isScanning}");
    _isScanning = false;
    // print("⏩ change state : ${_isScanning}");
  });
  // });
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  print('iOS background fetch activated');
  return true;
}

List<Map<String, dynamic>> zones = [];

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
