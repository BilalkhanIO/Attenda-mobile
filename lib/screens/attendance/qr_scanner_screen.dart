import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
      await api.checkIn(type: 'qr', qrCode: code);
      setState(() { _done = true; _message = 'Checked In!'; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.pop();
    } catch (e) {
      final err = e.toString();
      setState(() {
        _error      = true;
        _processing = false;
        _message    = err.contains('expired') ? 'QR code has expired' :
                      err.contains('invalid')  ? 'Invalid QR code' :
                      err.contains('already')  ? 'Already checked in today' :
                      'Check-in failed. Try again.';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() { _error = false; _message = ''; });
    }
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
              color: AppColors.success700.withOpacity(0.9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 80),
                  const SizedBox(height: 16),
                  const Text('Checked In!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  Text(
                    TimeOfDay.now().format(context),
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
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
