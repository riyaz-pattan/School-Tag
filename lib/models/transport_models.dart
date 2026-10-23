class BusModel {
  final String busId;
  final String busNumber;
  final String schoolCode;
  final String? driverId;
  final String? routeId;

  BusModel({
    required this.busId,
    required this.busNumber,
    required this.schoolCode,
    this.driverId,
    this.routeId,
  });

  factory BusModel.fromMap(Map<String, dynamic> data, String documentId) {
    return BusModel(
      busId: documentId,
      busNumber: data['busNumber'] ?? '',
      schoolCode: data['schoolCode'] ?? '',
      driverId: data['driverId'],
      routeId: data['routeId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'busNumber': busNumber,
      'schoolCode': schoolCode,
      'driverId': driverId,
      'routeId': routeId,
    };
  }
}

class Waypoint {
  final double lat;
  final double lng;

  Waypoint({required this.lat, required this.lng});

  factory Waypoint.fromMap(Map<String, dynamic> data) {
    return Waypoint(
      lat: (data['lat'] ?? 0.0).toDouble(),
      lng: (data['lng'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}

class RouteModel {
  final String routeId;
  final String routeName;
  final String schoolCode;
  final List<Waypoint> waypoints;
  final bool isActive;
  final String? activeDriverId;
  final String? activeBusId;
  final DateTime? startTime;

  RouteModel({
    required this.routeId,
    required this.routeName,
    required this.schoolCode,
    required this.waypoints,
    this.isActive = false,
    this.activeDriverId,
    this.activeBusId,
    this.startTime,
  });

  factory RouteModel.fromMap(Map<String, dynamic> data, String documentId) {
    List<Waypoint> waypointsList = [];
    if (data['waypoints'] != null) {
      waypointsList = (data['waypoints'] as List)
          .map((item) => Waypoint.fromMap(item))
          .toList();
    }

    return RouteModel(
      routeId: documentId,
      routeName: data['routeName'] ?? '',
      schoolCode: data['schoolCode'] ?? '',
      waypoints: waypointsList,
      isActive: data['isActive'] ?? false,
      activeDriverId: data['activeDriverId'],
      activeBusId: data['activeBusId'],
      startTime: data['startTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['startTime'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'routeName': routeName,
      'schoolCode': schoolCode,
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
      'isActive': isActive,
      'activeDriverId': activeDriverId,
      'activeBusId': activeBusId,
      'startTime': startTime?.millisecondsSinceEpoch,
    };
  }
}

class LiveLocationModel {
  final double lat;
  final double lng;
  final double heading;
  final int lastUpdated;

  LiveLocationModel({
    required this.lat,
    required this.lng,
    required this.heading,
    required this.lastUpdated,
  });

  factory LiveLocationModel.fromMap(Map<dynamic, dynamic> data) {
    return LiveLocationModel(
      lat: (data['lat'] ?? 0.0).toDouble(),
      lng: (data['lng'] ?? 0.0).toDouble(),
      heading: (data['heading'] ?? 0.0).toDouble(),
      lastUpdated: data['lastUpdated'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'lastUpdated': lastUpdated,
    };
  }
}
