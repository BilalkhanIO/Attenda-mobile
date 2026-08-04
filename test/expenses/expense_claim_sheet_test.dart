import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attenda/screens/expenses/expense_claim_sheet.dart';
import 'package:attenda/services/theme_controller.dart';
import 'package:attenda/utils/theme.dart';

/// Presents [sheet] through a real modal bottom-sheet route (like the app
/// does), so `Navigator.pop` after a successful submit has a route to pop.
Future<void> pumpExpenseSheet(WidgetTester tester, Widget sheet) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => sheet,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  final date = DateTime(2026, 7, 1);

  group('ExpenseClaimSheet', () {
    testWidgets(
        'renders amount, category quick picks, date and description fields',
        (tester) async {
      await pumpExpenseSheet(tester, ExpenseClaimSheet(initialDate: date));

      expect(find.text('New Expense Claim'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(_fieldWithHint('0.00'), findsOneWidget);
      // Quick-pick category chips.
      expect(find.text('Travel'), findsOneWidget);
      expect(find.text('Meals'), findsOneWidget);
      expect(find.text('Supplies'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Wed, 1 Jul 2026'), findsOneWidget);
      expect(_fieldWithHint('What was this expense for?'), findsOneWidget);
      expect(find.text('Submit Claim'), findsOneWidget);
    });

    testWidgets('blocks submission when the amount is missing or invalid',
        (tester) async {
      var submitted = false;
      await pumpExpenseSheet(
        tester,
        ExpenseClaimSheet(
          initialDate: date,
          onSubmit: (a, c, d, dt) async => submitted = true,
        ),
      );

      // Empty amount.
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pump();
      expect(find.text('Enter an amount greater than 0.'), findsOneWidget);

      // Zero amount is still invalid.
      await tester.enterText(_fieldWithHint('0.00'), '0');
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pump();
      expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('blocks submission when the category is empty',
        (tester) async {
      var submitted = false;
      await pumpExpenseSheet(
        tester,
        ExpenseClaimSheet(
          initialDate: date,
          onSubmit: (a, c, d, dt) async => submitted = true,
        ),
      );

      await tester.enterText(_fieldWithHint('0.00'), '42.50');
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pump();

      expect(find.text('Choose or enter a category.'), findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('blocks submission when the description is too short',
        (tester) async {
      var submitted = false;
      await pumpExpenseSheet(
        tester,
        ExpenseClaimSheet(
          initialDate: date,
          onSubmit: (a, c, d, dt) async => submitted = true,
        ),
      );

      await tester.enterText(_fieldWithHint('0.00'), '42.50');
      await tester.tap(find.text('Meals'));
      await tester.pump();
      await tester.enterText(
          _fieldWithHint('What was this expense for?'), 'abc');
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pump();

      expect(find.text('Please describe the expense (5+ chars)'),
          findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets(
        'submits the amount, category, description and date, then closes',
        (tester) async {
      double? gotAmount;
      String? gotCategory;
      String? gotDescription;
      String? gotDate;
      await pumpExpenseSheet(
        tester,
        ExpenseClaimSheet(
          initialDate: date,
          onSubmit: (a, c, d, dt) async {
            gotAmount = a;
            gotCategory = c;
            gotDescription = d;
            gotDate = dt;
          },
        ),
      );

      await tester.enterText(_fieldWithHint('0.00'), '42.50');
      await tester.tap(find.text('Travel'));
      await tester.pump();
      await tester.enterText(_fieldWithHint('What was this expense for?'),
          'Taxi from the airport to the client site');
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pumpAndSettle();

      expect(gotAmount, 42.50);
      expect(gotCategory, 'Travel');
      expect(gotDescription, 'Taxi from the airport to the client site');
      expect(gotDate, '2026-07-01');
      // The sheet popped after a successful submit.
      expect(find.text('New Expense Claim'), findsNothing);
    });
  });
}
