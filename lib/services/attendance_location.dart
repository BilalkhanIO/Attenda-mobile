import 'package:geolocator/geolocator.dart';

class AttendanceLocationEvidence {
  const AttendanceLocationEvidence({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.isMocked,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;
  final bool isMocked;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'is_mocked': isMocked,
      };
}

Future<AttendanceLocationEvidence?> captureAttendanceLocation({required bool enabled}) async {
  if (!enabled) return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return AttendanceLocationEvidence(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      isMocked: position.isMocked,
    );
  } catch (_) {
    return null;
  }
}
