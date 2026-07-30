import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/approvals/approvals_screen.dart';

import '../home_widgets/harness.dart';

// ApprovalsScreen itself fetches from the ApiService singleton in initState,
// so it is not pumped here — its list widgets are tested with injected
// sample data instead.

void main() {
  group('CorrectionApprovalCard', () {
    final correction = {
      'id': 'c1',
      'date': '2026-07-01T00:00:00.000Z',
      'reason': 'Forgot to check out',
      'requested_check_out': '2026-07-01T17:30:00.000Z',
      'user': {'name': 'Jane Doe', 'department': 'Sales'},
    };

    testWidgets('renders the requester, requested times and reason',
        (tester) async {
      await pumpHomeWidget(
        tester,
        CorrectionApprovalCard(correction: correction),
      );

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Requested Check Out'), findsOneWidget);
      // No check-in was requested, so that row is omitted entirely.
      expect(find.text('Requested Check In'), findsNothing);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Forgot to check out'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('fires the approve and reject callbacks', (tester) async {
      var approved = false;
      var rejected = false;
      await pumpHomeWidget(
        tester,
        CorrectionApprovalCard(
          correction: correction,
          onApprove: () => approved = true,
          onReject: () => rejected = true,
        ),
      );

      await tester.tap(find.text('Approve'));
      await tester.tap(find.text('Reject'));
      expect(approved, isTrue);
      expect(rejected, isTrue);
    });
  });

  group('LateSummaryTile', () {
    testWidgets('renders rank, name, late totals and points', (tester) async {
      await pumpHomeWidget(
        tester,
        const LateSummaryTile(
          rank: 2,
          row: {
            'name': 'John Smith',
            'late_count': 3,
            'total_late_minutes': 45,
            'points': 4,
          },
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('John Smith'), findsOneWidget);
      expect(find.text('3× late · 45m total'), findsOneWidget);
      expect(find.text('4 pts'), findsOneWidget);
    });

    testWidgets('shows zero points neutrally', (tester) async {
      await pumpHomeWidget(
        tester,
        const LateSummaryTile(
          rank: 1,
          row: {
            'name': 'Amy Lee',
            'late_count': 1,
            'total_late_minutes': 5,
            'points': 0,
          },
        ),
      );

      expect(find.text('1× late · 5m total'), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
    });
  });
}
