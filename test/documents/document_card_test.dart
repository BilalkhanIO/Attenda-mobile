import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/documents/documents_screen.dart';

import '../home_widgets/harness.dart';

void main() {
  group('formatFileSize', () {
    test('formats KB and MB and tolerates strings', () {
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(500), '1 KB');
      expect(formatFileSize(1572864), '1.5 MB');
      expect(formatFileSize('2048'), '2 KB');
      expect(formatFileSize(null), '—');
      expect(formatFileSize(0), '—');
    });
  });

  group('DocumentCard', () {
    Map<String, dynamic> doc({
      String? expiresAt,
      Map<String, dynamic>? uploader,
    }) =>
        {
          'id': 'd1',
          'title': 'Employment Contract',
          'category': 'contract',
          'file_name': 'contract.pdf',
          'file_size': 1572864,
          'mime_type': 'application/pdf',
          'expires_at': expiresAt,
          'uploader': uploader ?? {'id': 'u1', 'name': 'Jane Doe'},
          'created_at': '2026-07-01T00:00:00.000Z',
        };

    testWidgets('renders title, category chip, size and uploader',
        (tester) async {
      await pumpHomeWidget(
        tester,
        DocumentCard(
          doc: doc(uploader: {'id': 'hr1', 'name': 'HR Admin'}),
          currentUserId: 'u1',
        ),
      );

      expect(find.text('Employment Contract'), findsOneWidget);
      expect(find.text('Contract'), findsOneWidget);
      expect(find.text('1.5 MB'), findsOneWidget);
      expect(find.text('Added by HR Admin'), findsOneWidget);
      // No expires_at → no expiry line at all.
      expect(find.textContaining('Expires'), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('hides the uploader line for self-uploaded documents',
        (tester) async {
      await pumpHomeWidget(
        tester,
        DocumentCard(
          doc: doc(uploader: {'id': 'u1', 'name': 'Jane Doe'}),
          currentUserId: 'u1',
        ),
      );

      expect(find.textContaining('Added by'), findsNothing);
    });

    testWidgets('shows a warning-tinted expiry line within 30 days',
        (tester) async {
      final soon =
          DateTime.now().add(const Duration(days: 10)).toIso8601String();
      await pumpHomeWidget(
        tester,
        DocumentCard(doc: doc(expiresAt: soon), currentUserId: 'u1'),
      );

      expect(find.textContaining('Expires'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows a plain expiry line when expiry is far out',
        (tester) async {
      final far =
          DateTime.now().add(const Duration(days: 200)).toIso8601String();
      await pumpHomeWidget(
        tester,
        DocumentCard(doc: doc(expiresAt: far), currentUserId: 'u1'),
      );

      expect(find.textContaining('Expires'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('marks past expiry dates as expired', (tester) async {
      final past =
          DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      await pumpHomeWidget(
        tester,
        DocumentCard(doc: doc(expiresAt: past), currentUserId: 'u1'),
      );

      expect(find.textContaining('Expired'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('fires the tap callback', (tester) async {
      var tapped = false;
      await pumpHomeWidget(
        tester,
        DocumentCard(doc: doc(), currentUserId: 'u1', onTap: () => tapped = true),
      );

      await tester.tap(find.text('Employment Contract'));
      expect(tapped, isTrue);
    });
  });
}
