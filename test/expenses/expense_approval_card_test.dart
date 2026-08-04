import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/approvals/approvals_screen.dart';

import '../home_widgets/harness.dart';

void main() {
  group('ExpenseApprovalCard', () {
    final claim = {
      'id': 'e1',
      'amount': 42.5,
      'currency': 'USD',
      'category': 'Travel',
      'description': 'Taxi from the airport to the client site',
      'expense_date': '2026-07-01T00:00:00.000Z',
      'status': 'pending',
      'user': {'name': 'Jane Doe', 'department': 'Sales'},
    };

    testWidgets(
        'renders the claimant, amount, category, date and description',
        (tester) async {
      await pumpHomeWidget(tester, ExpenseApprovalCard(claim: claim));

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Wed, 1 Jul 2026'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('USD 42.50'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Taxi from the airport to the client site'),
          findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('tolerates string amounts and missing optional fields',
        (tester) async {
      await pumpHomeWidget(
        tester,
        ExpenseApprovalCard(claim: const {
          'id': 'e2',
          'amount': '1234.5',
          'currency': 'PKR',
          'user': {'name': 'John Smith'},
        }),
      );

      expect(find.text('John Smith'), findsOneWidget);
      expect(find.text('PKR 1,234.50'), findsOneWidget);
      // Missing expense_date renders the placeholder rather than throwing.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('fires the approve and reject callbacks', (tester) async {
      var approved = false;
      var rejected = false;
      await pumpHomeWidget(
        tester,
        ExpenseApprovalCard(
          claim: claim,
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
}
