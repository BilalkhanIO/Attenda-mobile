import 'dart:math';

/// Monotonic elapsed time for a single app process. A new epoch after restart
/// deliberately breaks the proof chain; the server then parks the event for
/// review instead of trusting a device wall-clock backdate.
class AttendanceClock {
  AttendanceClock._();
  static final Stopwatch _clock = Stopwatch()..start();
  static final String epoch = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  static double get uptimeMs => _clock.elapsedMicroseconds / 1000;

  static Map<String, dynamic>? anchor(Map<String, dynamic> status) {
    final token = status['attendance_clock_anchor'];
    final anchorUptime = status['_server_anchor_uptime_ms'];
    final anchorEpoch = status['_clock_epoch'];
    if (token is! String || anchorUptime is! num || anchorEpoch is! String) return null;
    return {
      'attendance_clock_anchor': token,
      'server_anchor_uptime_ms': anchorUptime,
      'server_anchor_epoch': anchorEpoch,
      'device_uptime_ms': uptimeMs,
      'clock_epoch': epoch,
    };
  }

  static Map<String, dynamic> attachAnchor(Map<String, dynamic> status) => {
        ...status,
        '_server_anchor_uptime_ms': uptimeMs,
        '_clock_epoch': epoch,
      };
}
