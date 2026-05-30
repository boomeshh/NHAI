// Device & geo-fence models (Phase 1 / Phase 4 future-ready).
import 'dart:math' as math;

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'appVersion': appVersion,
      };
}

/// Circular geo-fence zone (Phase 4). Membership is a haversine distance test.
class GeoFenceZone {
  final String zoneId;
  final String name;
  final double centerLat;
  final double centerLng;
  final double radiusMeters;

  const GeoFenceZone({
    required this.zoneId,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
  });

  /// True when [lat],[lng] lie within [radiusMeters] of the zone centre.
  bool contains(double lat, double lng) =>
      distanceMeters(lat, lng) <= radiusMeters;

  double distanceMeters(double lat, double lng) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat - centerLat);
    final dLng = rad(lng - centerLng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(centerLat)) *
            math.cos(rad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, dynamic> toJson() => {
        'zoneId': zoneId,
        'name': name,
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusMeters': radiusMeters,
      };
}
