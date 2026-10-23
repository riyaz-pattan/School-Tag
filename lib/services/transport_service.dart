import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import '../models/transport_models.dart';

class TransportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://student-app-c362d-default-rtdb.asia-southeast1.firebasedatabase.app');

  // Collection References
  CollectionReference get _routesRef => _firestore.collection('Routes');
  CollectionReference get _busesRef => _firestore.collection('Buses');

  // --- Firestore Data (Static) ---

  // Get buses for a school
  Stream<List<BusModel>> getBusesStream(String schoolCode) {
    return _busesRef
        .where('schoolCode', isEqualTo: schoolCode)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BusModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Get routes for a school
  Stream<List<RouteModel>> getRoutesStream(String schoolCode) {
    return _routesRef
        .where('schoolCode', isEqualTo: schoolCode)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RouteModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Admin creates a new route
  Future<void> createRoute(RouteModel route) async {
    await _routesRef.doc(route.routeId).set(route.toMap());
  }

  // Admin deletes a route
  Future<void> deleteRoute(String routeId) async {
    await _routesRef.doc(routeId).delete();
  }

  // --- Transactions (Locking/Unlocking Routes) ---

  // Driver starts a trip (Locks the route)
  Future<bool> startTrip(
      String routeId, String driverId, String busId) async {
    try {
      return await _firestore.runTransaction((transaction) async {
        DocumentReference routeDocRef = _routesRef.doc(routeId);
        DocumentSnapshot snapshot = await transaction.get(routeDocRef);

        if (!snapshot.exists) {
          throw Exception("Route does not exist!");
        }

        RouteModel route = RouteModel.fromMap(
            snapshot.data() as Map<String, dynamic>, snapshot.id);

        if (route.isActive) {
          // Route already active (Concurrency protection)
          return false;
        }

        // Lock the route
        transaction.update(routeDocRef, {
          'isActive': true,
          'activeDriverId': driverId,
          'activeBusId': busId,
          'startTime': FieldValue.serverTimestamp(),
        });
        
        return true;
      });
    } catch (e) {
      print("Failed to start trip transaction: \$e");
      return false;
    }
  }

  // Driver ends a trip (Unlocks the route and cleans RTDB)
  Future<void> endTrip(String routeId) async {
    // 1. Unlock in Firestore
    await _routesRef.doc(routeId).update({
      'isActive': false,
      'activeDriverId': null,
      'activeBusId': null,
      'startTime': null,
    });

    // 2. Clean up RTDB
    await _rtdb.ref('live_trips/$routeId').remove();
  }

  // --- Realtime Database (Live Tracking) ---

  // Driver pushes live location (frequent updates)
  Future<void> updateLiveLocation(String routeId, Position position) async {
    final liveData = LiveLocationModel(
      lat: position.latitude,
      lng: position.longitude,
      heading: position.heading,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );

    await _rtdb.ref('live_trips/$routeId').set(liveData.toMap());
  }

  // Students/Teachers listen to live location
  Stream<LiveLocationModel?> getLiveLocationStream(String routeId) {
    return _rtdb.ref('live_trips/$routeId').onValue.map((event) {
      if (event.snapshot.value != null) {
        return LiveLocationModel.fromMap(
            event.snapshot.value as Map<dynamic, dynamic>);
      }
      return null;
    });
  }
}
