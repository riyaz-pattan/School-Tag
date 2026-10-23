import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/transport_models.dart';
import '../services/transport_service.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String schoolCode;

  const LiveTrackingScreen({Key? key, required this.schoolCode}) : super(key: key);

  @override
  _LiveTrackingScreenState createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final TransportService _transportService = TransportService();
  final Completer<GoogleMapController> _controller = Completer();
  
  RouteModel? _selectedRoute;
  StreamSubscription<LiveLocationModel?>? _locationSubscription;
  Marker? _busMarker;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090), // Default center (New Delhi)
    zoom: 14.0,
  );

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _onRouteSelected(RouteModel route) {
    setState(() {
      _selectedRoute = route;
      _busMarker = null; // Clear old marker
    });
    
    _locationSubscription?.cancel();
    _locationSubscription = _transportService.getLiveLocationStream(route.routeId).listen((location) async {
      if (location != null) {
        final GoogleMapController mapController = await _controller.future;
        final latLng = LatLng(location.lat, location.lng);
        
        mapController.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 16.0)
        ));

        setState(() {
          _busMarker = Marker(
            markerId: const MarkerId('bus_marker'),
            position: latLng,
            rotation: location.heading,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet), // Placeholder for custom bus icon
            infoWindow: const InfoWindow(title: 'School Bus'),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Bus Tracking', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF451EBB), // Royal Purple
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            markers: _busMarker != null ? {_busMarker!} : {},
            myLocationEnabled: true,
          ),
          
          // Route Selector
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: StreamBuilder<List<RouteModel>>(
                  stream: _transportService.getRoutesStream(widget.schoolCode),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    
                    final activeRoutes = snapshot.data!.where((r) => r.isActive).toList();
                    
                    return DropdownButtonHideUnderline(
                      child: DropdownButton<RouteModel>(
                        hint: const Text('Select an active route to track'),
                        isExpanded: true,
                        value: _selectedRoute,
                        items: activeRoutes.map((route) {
                          return DropdownMenuItem(
                            value: route,
                            child: Text(route.routeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                        onChanged: (RouteModel? newRoute) {
                          if (newRoute != null) _onRouteSelected(newRoute);
                        },
                      ),
                    );
                  }
                ),
              ),
            ),
          ),
          
          // Status Card
          if (_selectedRoute != null)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Card(
                elevation: 8,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF451EBB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions_bus, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedRoute!.routeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('Status: En Route', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}
