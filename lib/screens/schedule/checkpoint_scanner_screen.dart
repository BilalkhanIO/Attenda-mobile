import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

class CheckpointScannerScreen extends StatefulWidget {
  const CheckpointScannerScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  State<CheckpointScannerScreen> createState() =>
      _CheckpointScannerScreenState();
}

class _CheckpointScannerScreenState extends State<CheckpointScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  bool _complete = false;
  String? _message;
  String? _progress;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _complete) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.trim().isEmpty) return;
    setState(() {
      _processing = true;
      _message = null;
    });
    try {
      final result = await api.scanShiftCheckpoint(
        assignmentId: widget.assignmentId,
        qrCode: code,
      );
      if (!mounted) return;
      final checkpoint =
          (result['checkpoint'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final progress = (result['progress'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      setState(() {
        _complete = true;
        _progress =
            '${progress['completed'] ?? 0} of ${progress['required'] ?? 0} required points checked';
        _message = '${checkpoint['name'] ?? 'Checkpoint'} recorded';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) context.pop(true);
    } catch (error) {
      if (!mounted) return;
      final failure = ApiFailure.fromError(error);
      setState(() {
        _processing = false;
        _message = failure is ValidationFailure
            ? (failure.serverMessage ??
                'That QR code is not a shift checkpoint.')
            : failure.userMessage;
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan safety checkpoint'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Toggle camera light',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        if (!_complete)
          MobileScanner(controller: _controller, onDetect: _onDetect),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(
                    color: _complete ? AppColors.success500 : primary,
                    width: 3),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 36,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  _complete
                      ? Icons.verified_rounded
                      : Icons.qr_code_scanner_rounded,
                  color: _complete ? AppColors.success500 : primary,
                  size: 28),
              const SizedBox(height: 8),
              Text(
                  _message ??
                      (_processing
                          ? 'Recording checkpoint…'
                          : 'Scan the QR code fixed at this site point'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              if (_progress != null) ...[
                const SizedBox(height: 5),
                Text(_progress!,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              if (!_complete && !_processing) ...[
                const SizedBox(height: 5),
                const Text('Keep the full code inside the frame.',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
              if (_processing) ...[
                const SizedBox(height: 14),
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: primary)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
