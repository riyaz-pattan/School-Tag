import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transport_models.dart';
import '../services/transport_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/fcm_service.dart';
import 'school_code_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  final String schoolCode;
  
  const DriverDashboardScreen({Key? key, required this.schoolCode}) : super(key: key);

  @override
  _DriverDashboardScreenState createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final TransportService _transportService = TransportService();
  
  RouteModel? _activeRoute;
  BusModel? _assignedBus;
  RouteModel? _assignedRoute;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAssignedBusAndRoute();
  }

  Future<void> _fetchAssignedBusAndRoute() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null) return;

    try {
      final busSnapshot = await FirebaseFirestore.instance
          .collection('Buses')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .where('driverId', isEqualTo: driverId)
          .limit(1)
          .get();

      if (busSnapshot.docs.isNotEmpty) {
        final bus = BusModel.fromMap(busSnapshot.docs.first.data(), busSnapshot.docs.first.id);
        
        if (bus.routeId != null) {
          final routeSnapshot = await FirebaseFirestore.instance
              .collection('Routes')
              .doc(bus.routeId)
              .get();
              
          if (routeSnapshot.exists) {
             setState(() {
               _assignedBus = bus;
               _assignedRoute = RouteModel.fromMap(routeSnapshot.data() as Map<String, dynamic>, routeSnapshot.id);
             });
          }
        }
      }
    } catch (e) {
      print("Error fetching assigned bus/route: $e");
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startTrip() async {
    if (_assignedRoute == null || _assignedBus == null) return;
    setState(() => _isLoading = true);
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied')));
        setState(() => _isLoading = false);
        return;
      }
    }

    final driverId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_driver';
    
    final success = await _transportService.startTrip(_assignedRoute!.routeId, driverId, _assignedBus!.busId);
    
    if (success) {
      setState(() {
        _activeRoute = _assignedRoute;
      });
      
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Requesting frequent updates
      );

      _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position? position) {
          if (position != null && _activeRoute != null) {
            _transportService.updateLiveLocation(_activeRoute!.routeId, position);
          }
        }
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start trip. Route may already be active.')));
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _endTrip() async {
    if (_activeRoute == null) return;
    
    setState(() => _isLoading = true);
    
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    
    await _transportService.endTrip(_activeRoute!.routeId);
    
    setState(() {
      _activeRoute = null;
      _isLoading = false;
    });
  }

  Future<void> _clearSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> _logout() async {
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmLogout != true) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final driverId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_driver';
      FCMService.unsubscribeFromAllNonBlocking(
        widget.schoolCode,
        driverId,
        'driver',
      );
      await _clearSharedPreferences();
      await FirebaseAuth.instance.signOut();
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SchoolCodeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error during logout: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FC),
      appBar: AppBar(
        title: const Text('Driver Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF451EBB), // Royal Purple
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_activeRoute != null) ...[
                  // Active Trip Card
                  Card(
                    color: const Color(0xFFFCD400), // Gold
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Active Trip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF221B00))),
                          const SizedBox(height: 8),
                          Text(_activeRoute!.routeName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFBA1A1A), // Red
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.stop),
                            label: const Text('END TRIP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            onPressed: _endTrip,
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                const Text('Your Assigned Route', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
                const SizedBox(height: 16),
                
                if (_assignedRoute == null)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No route assigned to you. Please contact admin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                  ))
                else if (_activeRoute == null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE9ECEF)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      title: Text(_assignedRoute!.routeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text('Bus: ${_assignedBus?.busNumber ?? 'Unknown'}'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF451EBB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _startTrip,
                        child: const Text('Start'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}
