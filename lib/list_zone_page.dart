import 'package:beacon_track_app/select_zone_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ZoneListPage extends StatefulWidget {
  const ZoneListPage({super.key});

  @override
  State<ZoneListPage> createState() => _ZoneListPageState();
}

class _ZoneListPageState extends State<ZoneListPage> {
  final CollectionReference zones = FirebaseFirestore.instance.collection(
    'zones',
  );

  void _deleteZone(String docId, String zoneName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm delete'),
        content: Text('Are you sure to delete "$zoneName" position?'),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [

                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Cancel', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await zones.doc(docId).delete();
                      Navigator.pop(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('"$zoneName" has been deleted.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'OK',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editZoneDialog(DocumentSnapshot doc) {
    String name = doc['name'];
    double lat = doc['lat'];
    double lng = doc['lng'];

    final TextEditingController nameController = TextEditingController(
      text: name,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              TextField(
                decoration: const InputDecoration(
                  labelText: "Name of location",
                  labelStyle: TextStyle(color: Colors.black54),
                ),
                controller: nameController,
                onChanged: (value) => name = value,
              ),
              
              // Container(
              //   margin: const EdgeInsets.symmetric(vertical: 10),
              //   child: Align(
              //     alignment: Alignment.centerLeft,
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         Text(
              //           "ตำแหน่งบนแผนที่",
              //           style: TextStyle(fontSize: 12, color: Colors.black54),
              //         ),
              //         Text(
              //           "ละติจูด: ${doc['lat'].toStringAsFixed(5)}\nลองจิจูด: ${doc['lng'].toStringAsFixed(5)}",
              //           style: const TextStyle(color: Colors.black87),
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
              
              const SizedBox(height: 16),
              
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_location, color: Colors.white),
                label: const Text(
                  "Edit position in the map",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context); // ปิด dialog ก่อน
                  final LatLng? selectedPos = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SelectZonePage(
                        initialLatLng: LatLng(lat, lng),
                        docId: doc.id,
                        readOnly: false, // เพิ่ม docId
                      ),
                    ),
                  );
                  if (selectedPos != null) {
                    await zones.doc(doc.id).update({
                      'name': name,
                      'lat': selectedPos.latitude,
                      'lng': selectedPos.longitude,
                    });
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          
          actions: [
            SizedBox(
              width: double.infinity,
              child: Row(
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
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please, enter the location name'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        await zones.doc(doc.id).update({'name': name});
                        Navigator.pop(context);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Name has been stored'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }

                        setState(() {});
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
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "List of position",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SelectZonePage(readOnly: false),
            ),
          ).then((value) => setState(() {}));
        },
        tooltip: 'Add new zone',
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      
      body: StreamBuilder<QuerySnapshot>(
        stream: zones.orderBy("created_at", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text("An error occurred", style: TextStyle(fontSize: 18)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No location",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () async {
                    final zoneId = doc.id;

                    // หา beacon ที่เจอใน zone นี้ล่าสุด
                    final hitsQuery = await FirebaseFirestore.instance
                        .collection('beacon_zone_hits')
                        .where('zoneId', isEqualTo: zoneId)
                        .orderBy('timestamp', descending: true)
                        .limit(1)
                        .get();

                    if (hitsQuery.docs.isNotEmpty) {
                      final latest = hitsQuery.docs.first.data();
                      final double zoneLat = doc['lat'];
                      final double zoneLng = doc['lng'];
                      final double beaconLat = latest['deviceLat'];
                      final double beaconLng = latest['deviceLng'];

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SelectZonePage(
                            initialLatLng: LatLng(zoneLat, zoneLng),
                            beaconLatLng: LatLng(beaconLat, beaconLng),
                            readOnly: true,
                          ),
                        ),
                      );
                    } else {
                      // ถ้าไม่มี beacon เจอในโซนนี้
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("No iBeacon found in the zone ${doc['name']}"),
                          duration: Duration(milliseconds: 1600),
                        ),
                      );
                    }
                  },

                  leading: const Icon(
                    Icons.location_on,
                    color: Colors.deepPurple,
                    size: 32,
                  ),
                  title: Text(
                    doc['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  // subtitle: Text(
                  //   "ละติจูด: ${doc['lat'].toStringAsFixed(5)}  |  ลองจิจูด: ${doc['lng'].toStringAsFixed(5)}",
                  //   style: const TextStyle(color: Colors.black87),
                  // ),

                  trailing: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: "edit zone",
                          onPressed: () => _editZoneDialog(doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "delete zone",
                          onPressed: () => _deleteZone(doc.id, doc['name']),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}