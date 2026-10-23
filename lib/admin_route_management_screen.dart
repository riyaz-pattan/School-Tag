import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/transport_models.dart';
import '../services/transport_service.dart';

class AdminRouteManagementScreen extends StatefulWidget {
  final String schoolCode;
  
  const AdminRouteManagementScreen({Key? key, required this.schoolCode}) : super(key: key);

  @override
  _AdminRouteManagementScreenState createState() => _AdminRouteManagementScreenState();
}

class _AdminRouteManagementScreenState extends State<AdminRouteManagementScreen> {
  final TransportService _transportService = TransportService();
  final Completer<GoogleMapController> _controller = Completer();
  
  final TextEditingController _routeNameController = TextEditingController();
  List<LatLng> _waypoints = [];
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _isSaving = false;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090), // Default center (New Delhi)
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 16.0,
        ),
      ));
    } catch (e) {
      print("Error getting current location: $e");
    }
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _waypoints.add(position);
      _updateMapOverlays();
    });
  }

  void _updateMapOverlays() {
    _markers = _waypoints.asMap().entries.map((entry) {
      final isStart = entry.key == 0;
      final isEnd = entry.key == _waypoints.length - 1 && _waypoints.length > 1;
      
      double hue = BitmapDescriptor.hueAzure; // Middle stops
      if (isStart) hue = BitmapDescriptor.hueGreen; // Start
      else if (isEnd) hue = BitmapDescriptor.hueRed; // End

      return Marker(
        markerId: MarkerId('waypoint_${entry.key}'),
        position: entry.value,
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(title: isStart ? 'Start Point' : (isEnd ? 'End Point' : 'Stop ${entry.key + 1}')),
      );
    }).toSet();

    if (_waypoints.length > 1) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route_path'),
          points: _waypoints,
          color: const Color(0xFF451EBB), // Royal Purple
          width: 5,
        )
      };
    } else {
      _polylines = {};
    }
  }

  void _clearRoute() {
    setState(() {
      _waypoints.clear();
      _updateMapOverlays();
      _routeNameController.clear();
    });
  }

  Future<void> _saveRoute() async {
    if (_routeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a route name')));
      return;
    }
    if (_waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please tap on the map to add at least 2 waypoints')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final routeId = DateTime.now().millisecondsSinceEpoch.toString();
      final newRoute = RouteModel(
        routeId: routeId,
        routeName: _routeNameController.text.trim(),
        schoolCode: widget.schoolCode,
        waypoints: _waypoints.map((latLng) => Waypoint(lat: latLng.latitude, lng: latLng.longitude)).toList(),
      );

      await _transportService.createRoute(newRoute);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route saved successfully')));
      _clearRoute();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving route: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF451EBB),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Map Section (Top Half)
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: _initialCameraPosition,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                  onTap: _onMapTapped,
                  markers: _markers,
                  polylines: _polylines,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    onPressed: _clearRoute,
                    child: const Icon(Icons.clear),
                  ),
                )
              ],
            ),
          ),
          
          // Form and List Section (Bottom Half)
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _routeNameController,
                          decoration: const InputDecoration(
                            labelText: 'Route Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF451EBB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        ),
                        onPressed: _isSaving ? null : _saveRoute,
                        child: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Saved Routes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<List<RouteModel>>(
                      stream: _transportService.getRoutesStream(widget.schoolCode),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        
                        final routes = snapshot.data!;
                        if (routes.isEmpty) return const Center(child: Text('No routes created yet.'));

                        return ListView.builder(
                          itemCount: routes.length,
                          itemBuilder: (context, index) {
                            final route = routes[index];
                            return ListTile(
                              title: Text(route.routeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${route.waypoints.length} stops • ${route.isActive ? "Active" : "Inactive"}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  if (route.isActive) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete an active route')));
                                  } else {
                                    _transportService.deleteRoute(route.routeId);
                                  }
                                },
                              ),
                            );
                          },
                        );
                      }
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
