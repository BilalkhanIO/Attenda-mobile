import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attenda/screens/kudos/give_kudos_sheet.dart';
import 'package:attenda/services/api_failure.dart';
import 'package:attenda/services/theme_controller.dart';
import 'package:attenda/utils/theme.dart';

/// Presents [sheet] through a real modal bottom-sheet route (like the app
/// does), so `Navigator.pop` after a successful submit has a route to pop.
Future<void> pumpKudosSheet(WidgetTester tester, Widget sheet) async {
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

const _colleagues = [
  {'id': 'u1', 'name': 'Sam Carter', 'department': 'Support'},
  {'id': 'u2', 'name': 'Aisha Khan', 'department': 'Design'},
];

void main() {
  group('GiveKudosSheet', () {
    testWidgets('renders picker, emoji quick picks and message field',
        (tester) async {
      await pumpKudosSheet(
          tester, const GiveKudosSheet(colleagues: _colleagues));

      expect(find.text('Give Kudos'), findsOneWidget);
      expect(_fieldWithHint('Search colleagues'), findsOneWidget);
      expect(find.text('Sam Carter'), findsOneWidget);
      expect(find.text('Aisha Khan'), findsOneWidget);
      for (final e in kKudosEmojiQuickPicks) {
        expect(find.text(e), findsOneWidget);
      }
      expect(_fieldWithHint('What did they do well?'), findsOneWidget);
      expect(find.text('Send Kudos'), findsOneWidget);
    });

    testWidgets('filters colleagues by the search term', (tester) async {
      await pumpKudosSheet(
          tester, const GiveKudosSheet(colleagues: _colleagues));

      await tester.enterText(_fieldWithHint('Search colleagues'), 'aisha');
      await tester.pump();

      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('Sam Carter'), findsNothing);
    });

    testWidgets('blocks submission without a recipient', (tester) async {
      var submitted = false;
      await pumpKudosSheet(
        tester,
        GiveKudosSheet(
          colleagues: _colleagues,
          onSubmit: (to, msg, emoji) async => submitted = true,
        ),
      );

      await tester.enterText(
          _fieldWithHint('What did they do well?'), 'Great work on the launch');
      await tester.ensureVisible(find.text('Send Kudos'));
      await tester.tap(find.text('Send Kudos'));
      await tester.pump();

      expect(find.text('Choose a recipient.'), findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('blocks submission when the message is under 3 characters',
        (tester) async {
      var submitted = false;
      await pumpKudosSheet(
        tester,
        GiveKudosSheet(
          colleagues: _colleagues,
          onSubmit: (to, msg, emoji) async => submitted = true,
        ),
      );

      await tester.tap(find.text('Sam Carter'));
      await tester.pump();
      await tester.enterText(_fieldWithHint('What did they do well?'), 'ok');
      await tester.ensureVisible(find.text('Send Kudos'));
      await tester.tap(find.text('Send Kudos'));
      await tester.pump();

      expect(
          find.text('Message must be at least 3 characters.'), findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('submits recipient, message and picked emoji, then closes',
        (tester) async {
      String? gotTo;
      String? gotMessage;
      String? gotEmoji;
      await pumpKudosSheet(
        tester,
        GiveKudosSheet(
          colleagues: _colleagues,
          onSubmit: (to, msg, emoji) async {
            gotTo = to;
            gotMessage = msg;
            gotEmoji = emoji;
          },
        ),
      );

      await tester.tap(find.text('Aisha Khan'));
      await tester.pump();
      await tester.tap(find.text('👏'));
      await tester.pump();
      await tester.enterText(_fieldWithHint('What did they do well?'),
          'Thanks for covering my shift!');
      await tester.ensureVisible(find.text('Send Kudos'));
      await tester.tap(find.text('Send Kudos'));
      await tester.pumpAndSettle();

      expect(gotTo, 'u2');
      expect(gotMessage, 'Thanks for covering my shift!');
      expect(gotEmoji, '👏');
      // The sheet popped after a successful submit.
      expect(find.text('Give Kudos'), findsNothing);
    });

    testWidgets('surfaces the daily cap (429) as friendly copy',
        (tester) async {
      await pumpKudosSheet(
        tester,
        GiveKudosSheet(
          colleagues: _colleagues,
          onSubmit: (to, msg, emoji) async =>
              throw const RateLimitedFailure(),
        ),
      );

      await tester.tap(find.text('Sam Carter'));
      await tester.pump();
      await tester.enterText(_fieldWithHint('What did they do well?'),
          'Always going the extra mile');
      await tester.ensureVisible(find.text('Send Kudos'));
      await tester.tap(find.text('Send Kudos'));
      await tester.pump();

      expect(find.text(kKudosLimitMessage), findsOneWidget);
      // Still open for a retry tomorrow (or editing).
      expect(find.text('Give Kudos'), findsOneWidget);
    });
  });
}
