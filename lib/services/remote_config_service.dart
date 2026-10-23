import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        // Use zero interval in debug so changes appear immediately
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ));
      await _remoteConfig.setDefaults(const {
        "bus_tracking_config": "{}",
      });
      final activated = await _remoteConfig.fetchAndActivate();
      debugPrint("🔧 RemoteConfig fetchAndActivate result: $activated");
      final raw = _remoteConfig.getString('bus_tracking_config');
      debugPrint("🔧 RemoteConfig bus_tracking_config raw value: '$raw'");
    } catch (e) {
      debugPrint("❌ Failed to initialize remote config: $e");
    }
  }

  bool isBusTrackingEnabled(String schoolCode) {
    try {
      String configJsonString = _remoteConfig.getString('bus_tracking_config');
      debugPrint("🔧 isBusTrackingEnabled called with schoolCode='$schoolCode', raw='$configJsonString'");
      if (configJsonString.isEmpty) {
        debugPrint("🔧 bus_tracking_config is empty, returning false");
        return false;
      }
      
      Map<String, dynamic> configMap = jsonDecode(configJsonString);
      debugPrint("🔧 Parsed configMap: $configMap");
      
      if (configMap.containsKey(schoolCode)) {
        final value = configMap[schoolCode];
        debugPrint("🔧 Found schoolCode '$schoolCode' with value: $value (type: ${value.runtimeType})");
        return value == true;
      }
      debugPrint("🔧 schoolCode '$schoolCode' NOT found in configMap keys: ${configMap.keys.toList()}");
      return false;
    } catch (e) {
      debugPrint("❌ Error parsing remote config: $e");
      return false;
    }
  }
}
