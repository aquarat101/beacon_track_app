import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_place/google_place.dart';

const String kGoogleApiKey = 'AIzaSyAfI8c5HYga6T0VEbCxIELta_8FGOcX67U';

class SelectZonePage extends StatefulWidget {
  final LatLng? initialLatLng;
  final LatLng? beaconLatLng;
  final String? docId;
  final bool readOnly;

  const SelectZonePage({
    super.key,
    this.initialLatLng,
    this.beaconLatLng,
    this.docId,
    required this.readOnly,
  });

  @override
  State<SelectZonePage> createState() => _SelectZonePageState();
}

class _SelectZonePageState extends State<SelectZonePage> {
  LatLng? selectedPos;
  GoogleMapController? _mapController;
  final double zoneRadiusMeters = 100;
  BitmapDescriptor? bluetoothIcon;
  final TextEditingController _searchController = TextEditingController();
  late GooglePlace googlePlace;
  List<AutocompletePrediction> predictions = [];
  Set<Marker> markers = {};

  @override
  void initState() {
    super.initState();
    googlePlace = GooglePlace(kGoogleApiKey);
    if (!widget.readOnly) {
      selectedPos = widget.initialLatLng;
    }
    _loadIcons();
  }

  void _onMapTap(LatLng latLng) {
    setState(() {
      selectedPos = latLng;
    });
  }

  Future<void> _loadIcons() async {
    bluetoothIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/bluetooth_icon.png',
    );
    setState(() {});
  }

  Future<void> _saveZone() async {
    if (selectedPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please, choose the position first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    double roundedLat = double.parse(selectedPos!.latitude.toStringAsFixed(5));
    double roundedLng = double.parse(selectedPos!.longitude.toStringAsFixed(5));

    if (widget.docId != null) {
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(widget.docId)
          .update({'lat': roundedLat, 'lng': roundedLng});

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location has been updated'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('zones')
          .where('lat', isEqualTo: roundedLat)
          .where('lng', isEqualTo: roundedLng)
          .get();

      if (!mounted) return;

      if (querySnapshot.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This position already exists and cannot be duplicated',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      String? name;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Name the location'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "such as home, school",
              ),
              onChanged: (value) => name = value,
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        side: const BorderSide(color: Colors.deepPurple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Cancel", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        if (name == null || name!.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please, enter the location'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        await FirebaseFirestore.instance
                            .collection('zones')
                            .add({
                              'name': name!.trim(),
                              'lat': roundedLat,
                              'lng': roundedLng,
                              'created_at': Timestamp.now(),
                            });
                        if (context.mounted) {
                          Navigator.pop(context);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Name and position has been stored',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          "OK",
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }
  }

  void _clearSelection() {
    setState(() {
      selectedPos = null;
      _searchController.clear();
      predictions.clear();
    });
  }

  void _handleSearch(String keyword, {bool autoSelectFirst = false}) async {
    print("🔍 เริ่มค้นหา: $keyword");

    final result = await googlePlace.autocomplete.get(keyword);
    if (result != null) {
      print("✅ Status: ${result.status}");
      print("✅ Predictions count: ${result.predictions?.length}");

      result.predictions?.forEach((p) {
        print("→ ${p.description} (${p.placeId})");
      });
    } else {
      print("❌ result = null");
      return;
    }

    if (result.predictions == null) {
      print("❌ ไม่มี predictions ใน response");
      return;
    }

    print("✅ ได้ผลลัพธ์: ${result.predictions!.length} รายการ");

    setState(() {
      predictions = result.predictions!;
    });

    if (autoSelectFirst && predictions.isNotEmpty) {
      _selectPrediction(predictions.first);
    }
  }

  void _selectPrediction(AutocompletePrediction prediction) async {
    print("------ SelectPrediction ------");
    final placeId = prediction.placeId;
    if (placeId != null) {
      final details = await googlePlace.details.get(placeId);
      final location = details!.result?.geometry?.location;

      if (location != null) {
        final latLng = LatLng(location.lat!, location.lng!);

        setState(() {
          selectedPos = latLng;
          markers = {
            Marker(
              markerId: const MarkerId('selected'),
              position: latLng,
              infoWindow: InfoWindow(
                title: prediction.description ?? 'Selected Location',
              ),
            ),
          };
          predictions = []; // ซ่อนรายการผลลัพธ์
          _searchController.text = prediction.description ?? '';
        });

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCameraPos = CameraPosition(
      target: widget.readOnly
          ? widget.beaconLatLng ??
                widget.initialLatLng ??
                const LatLng(13.7563, 100.5018)
          : widget.initialLatLng ?? const LatLng(13.7563, 100.5018),
      zoom: 17.5,
    );

    Set<Marker> setMarkers = {};
    if (widget.initialLatLng != null) {
      setMarkers.add(
        Marker(
          markerId: const MarkerId('initial'),
          position: widget.initialLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    if (widget.beaconLatLng != null && bluetoothIcon != null) {
      setMarkers.add(
        Marker(
          markerId: const MarkerId('beacon'),
          position: widget.beaconLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }
    if (selectedPos != null) {
      setMarkers.add(
        Marker(
          markerId: const MarkerId('selected'),
          position: selectedPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Choose the location",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (selectedPos != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSelection,
              tooltip: 'Clear',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: initialCameraPos,
                  markers: setMarkers,
                  circles: selectedPos != null && !widget.readOnly
                      ? {
                          Circle(
                            circleId: const CircleId('zoneRadius'),
                            center: selectedPos!,
                            radius: zoneRadiusMeters,
                            fillColor: Colors.red.withAlpha(
                              (0.2 * 255).round(),
                            ),
                            strokeColor: Colors.red,
                            strokeWidth: 2,
                          ),
                        }
                      : widget.initialLatLng != null
                      ? {
                          Circle(
                            circleId: const CircleId('zoneBeacon'),
                            center: widget.initialLatLng!,
                            radius: zoneRadiusMeters,
                            fillColor: Colors.red.withAlpha(
                              (0.2 * 255).round(),
                            ),
                            strokeColor: Colors.red,
                            strokeWidth: 2,
                          ),
                        }
                      : {},
                  onTap: widget.readOnly ? null : _onMapTap,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  myLocationButtonEnabled: true,
                  myLocationEnabled: true,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _handleSearch,
                          onSubmitted: (text) => _handleSearch(text, autoSelectFirst: true),
                          decoration: InputDecoration(
                            hintText: 'Search location...',
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSelection,
                            ),
                          ),
                        ),
                      ),
                      if (predictions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: ListView.builder(
                            itemCount: predictions.length,
                            itemBuilder: (context, index) {
                              return ListTile(
                                title: Text(
                                  predictions[index].description ?? '',
                                ),
                                onTap: () =>
                                    _selectPrediction(predictions[index]),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            color: Colors.grey.shade100,
            width: double.infinity,
            child: Text(
              selectedPos == null
                  ? 'Tap the map to select a location'
                  : 'Selected position: (${selectedPos!.latitude.toStringAsFixed(5)}, ${selectedPos!.longitude.toStringAsFixed(5)})',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: selectedPos == null ? Colors.grey : Colors.black87,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text(
                  'Confirm to store this localtion',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: widget.readOnly ? null : _saveZone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
