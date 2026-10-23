import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/transport_models.dart';
import 'services/transport_service.dart';

class AdminBusManagementScreen extends StatefulWidget {
  final String schoolCode;

  const AdminBusManagementScreen({Key? key, required this.schoolCode})
      : super(key: key);

  @override
  _AdminBusManagementScreenState createState() =>
      _AdminBusManagementScreenState();
}

class _AdminBusManagementScreenState extends State<AdminBusManagementScreen> {
  final TransportService _transportService = TransportService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _drivers = [];
  List<RouteModel> _routes = [];

  @override
  void initState() {
    super.initState();
    _fetchDriversAndRoutes();
  }

  Future<void> _fetchDriversAndRoutes() async {
    try {
      final driverSnapshot = await _firestore
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'driver')
          .get();
      
      final routeSnapshot = await _firestore
          .collection('Routes')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      setState(() {
        _drivers = driverSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _routes = routeSnapshot.docs.map((doc) => RouteModel.fromMap(doc.data(), doc.id)).toList();
      });
    } catch (e) {
      print("Error fetching drivers/routes: $e");
    }
  }

  void _showAddEditBusDialog({BusModel? bus}) {
    final TextEditingController busNumberController =
        TextEditingController(text: bus?.busNumber ?? '');
    String? selectedDriverId = bus?.driverId;
    String? selectedRouteId = bus?.routeId;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(bus == null ? 'Add New Bus' : 'Edit Bus'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: busNumberController,
                    decoration: const InputDecoration(labelText: 'Bus Number / Name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Assign Driver'),
                    value: selectedDriverId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No Driver Assigned')),
                      ..._drivers.map((driver) {
                        return DropdownMenuItem<String>(
                          value: driver['id'],
                          child: Text(driver['username'] ?? 'Unknown'),
                        );
                      })
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedDriverId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Assign Route'),
                    value: selectedRouteId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No Route Assigned')),
                      ..._routes.map((route) {
                        return DropdownMenuItem<String>(
                          value: route.routeId,
                          child: Text(route.routeName),
                        );
                      })
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedRouteId = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (busNumberController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bus Number is required')));
                    return;
                  }

                  final newBusRef = bus == null
                      ? _firestore.collection('Buses').doc()
                      : _firestore.collection('Buses').doc(bus.busId);

                  final busData = BusModel(
                    busId: newBusRef.id,
                    busNumber: busNumberController.text.trim(),
                    schoolCode: widget.schoolCode,
                    driverId: selectedDriverId,
                    routeId: selectedRouteId,
                  );

                  await newBusRef.set(busData.toMap());

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(bus == null
                            ? 'Bus Added Successfully'
                            : 'Bus Updated Successfully')));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  void _deleteBus(String busId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bus'),
        content: const Text('Are you sure you want to delete this bus?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('Buses').doc(busId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bus Deleted Successfully')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Buses'),
      ),
      body: StreamBuilder<List<BusModel>>(
        stream: _transportService.getBusesStream(widget.schoolCode),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final buses = snapshot.data ?? [];

          if (buses.isEmpty) {
            return const Center(child: Text('No buses found. Add one!'));
          }

          return ListView.builder(
            itemCount: buses.length,
            itemBuilder: (context, index) {
              final bus = buses[index];
              final driver = _drivers.firstWhere(
                  (d) => d['id'] == bus.driverId,
                  orElse: () => {'username': 'Unassigned'});
              final route = _routes.firstWhere(
                  (r) => r.routeId == bus.routeId,
                  orElse: () => RouteModel(
                      routeId: '', routeName: 'Unassigned', schoolCode: '', waypoints: [], isActive: false));

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.directions_bus, color: Colors.white),
                  ),
                  title: Text(bus.busNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Driver: ${driver['username']}\nRoute: ${route.routeName}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditBusDialog(bus: bus),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteBus(bus.busId),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditBusDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
