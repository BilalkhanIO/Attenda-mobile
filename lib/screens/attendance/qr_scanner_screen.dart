import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});
  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;
  bool _done       = false;
  bool _error      = false;
  bool _isCheckout = false;
  String _message  = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _done) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _processing = true);
    final code = barcode!.rawValue!;

    try {
      final result = await api.checkIn(type: 'qr', qrCode: code);
      final action = result['action'] as String?;

      if (action == 'checkout_prompt') {
        // Already checked in — offer checkout
        setState(() => _processing = false);
        if (!mounted) return;
        final confirmed = await _showCheckoutConfirmation(result['record'] as Map<String, dynamic>? ?? {});
        if (confirmed == true) {
          setState(() => _processing = true);
          await api.checkOut();
          setState(() { _done = true; _message = 'Checked Out!'; _isCheckout = true; });
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) context.pop();
        } else {
          setState(() => _processing = false);
        }
      } else {
        setState(() { _done = true; _message = 'Checked In!'; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.pop();
      }
    } catch (e) {
      final err = e.toString();
      setState(() {
        _error      = true;
        _processing = false;
        _message    = err.contains('expired') ? 'QR code has expired' :
                      err.contains('invalid')  ? 'Invalid QR code' :
                      'Scan failed. Try again.';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() { _error = false; _message = ''; });
    }
  }

  Future<bool?> _showCheckoutConfirmation(Map<String, dynamic> record) async {
    final checkInStr   = record['check_in_at'] as String?;
    final checkInTime  = checkInStr != null ? DateTime.parse(checkInStr) : null;
    final elapsed      = checkInTime != null ? DateTime.now().difference(checkInTime) : Duration.zero;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    final timeDisplay = checkInTime != null
        ? DateFormat('hh:mm a').format(checkInTime)
        : '--';
    final durationDisplay = h > 0 ? '${h}h ${m}m' : '${m}m';

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDark2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(Icons.logout_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text('Check Out?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text('You checked in at $timeDisplay',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 4),
          Text('Time in office: $durationDisplay',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Check Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera viewfinder
          MobileScanner(controller: _ctrl, onDetect: _onDetect),

          // Dimmed overlay with scan window
          CustomPaint(painter: _ScanOverlayPainter()),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const Text('Scan QR Code', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.flash_auto, color: Colors.white),
                    onPressed: () => _ctrl.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),

          // Instruction text
          Positioned(
            bottom: 120,
            left: 0, right: 0,
            child: const Text(
              'Point your camera at the office QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),

          // Success overlay
          if (_done)
            Container(
              color: (_isCheckout ? AppColors.primary600 : AppColors.success700).withOpacity(0.9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isCheckout ? Icons.logout_rounded : Icons.check_circle_rounded, color: Colors.white, size: 80),
                  const SizedBox(height: 16),
                  Text(_message, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  Text(TimeOfDay.now().format(context), style: const TextStyle(color: Colors.white70, fontSize: 18)),
                ],
              ),
            ),

          // Error overlay
          if (_error)
            Container(
              color: AppColors.danger800.withOpacity(0.9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cancel_rounded, color: Colors.white, size: 80),
                  const SizedBox(height: 16),
                  Text(_message, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                ],
              ),
            ),

          // Processing
          if (_processing && !_done && !_error)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const sz    = 260.0;
    const corner = 20.0;
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: sz, height: sz);

    // Dim everything outside scan window
    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12))),
      ),
      paint,
    );

    // Corner brackets
    final linePaint = Paint()..color = Colors.white..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final corners = [
      [rect.topLeft,     Offset(rect.left + corner, rect.top),    Offset(rect.left, rect.top + corner)],
      [rect.topRight,    Offset(rect.right - corner, rect.top),   Offset(rect.right, rect.top + corner)],
      [rect.bottomLeft,  Offset(rect.left + corner, rect.bottom), Offset(rect.left, rect.bottom - corner)],
      [rect.bottomRight, Offset(rect.right - corner, rect.bottom),Offset(rect.right, rect.bottom - corner)],
    ];
    for (final c in corners) {
      canvas.drawLine(c[1], c[0], linePaint);
      canvas.drawLine(c[0], c[2], linePaint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
