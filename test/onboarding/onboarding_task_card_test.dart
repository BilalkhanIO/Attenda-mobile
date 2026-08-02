import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:attenda/screens/onboarding/onboarding_screen.dart';
import 'package:attenda/utils/theme.dart';

import '../home_widgets/harness.dart';

void main() {
  Map<String, dynamic> task({
    String status = 'pending',
    String? dueDate,
    String hireId = 'me',
    String hireName = 'Alice Johnson',
  }) =>
      {
        'id': 't1',
        'user_id': hireId,
        'item_title': 'Sign employment contract',
        'item_description': 'Read and sign it via the document portal.',
        'due_date': dueDate,
        'status': status,
        'completed_at': status == 'pending' ? null : '2026-07-30T10:00:00Z',
        'user': {'id': hireId, 'name': hireName, 'department': 'Design'},
        'assignee': {'id': 'me', 'name': 'Me'},
      };

  final past = DateTime.now().subtract(const Duration(days: 3));
  final future = DateTime.now().add(const Duration(days: 3));

  group('isOnboardingTaskOverdue', () {
    test('true only for pending tasks with a due date before today', () {
      expect(
        isOnboardingTaskOverdue(task(dueDate: past.toIso8601String())),
        isTrue,
      );
      expect(
        isOnboardingTaskOverdue(task(dueDate: future.toIso8601String())),
        isFalse,
      );
      // A task due today is not overdue yet.
      expect(
        isOnboardingTaskOverdue(
            task(dueDate: DateTime.now().toIso8601String())),
        isFalse,
      );
      // Terminal states never count as overdue.
      expect(
        isOnboardingTaskOverdue(
            task(status: 'done', dueDate: past.toIso8601String())),
        isFalse,
      );
      // Missing or malformed due dates are tolerated.
      expect(isOnboardingTaskOverdue(task()), isFalse);
      expect(isOnboardingTaskOverdue(task(dueDate: 'not-a-date')), isFalse);
    });
  });

  group('OnboardingTaskCard', () {
    testWidgets('renders title, description and a normal due date',
        (tester) async {
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(
          task: task(dueDate: future.toIso8601String()),
          myUserId: 'me',
        ),
      );

      expect(find.text('Sign employment contract'), findsOneWidget);
      expect(find.text('Read and sign it via the document portal.'),
          findsOneWidget);
      final dueLabel = DateFormat('EEE, d MMM yyyy').format(future);
      expect(find.text('Due $dueLabel'), findsOneWidget);
      expect(find.byKey(OnboardingTaskCard.overdueBadgeKey), findsNothing);

      final dueText = tester.widget<Text>(find.text('Due $dueLabel'));
      expect(dueText.style?.color, AppColors.textSecondary);
    });

    testWidgets('tints the due date and shows the badge once overdue',
        (tester) async {
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(
          task: task(dueDate: past.toIso8601String()),
          myUserId: 'me',
        ),
      );

      expect(find.byKey(OnboardingTaskCard.overdueBadgeKey), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);

      final dueLabel = DateFormat('EEE, d MMM yyyy').format(past);
      final dueText = tester.widget<Text>(find.text('Due $dueLabel'));
      expect(dueText.style?.color, AppColors.danger500);
      expect(dueText.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('shows the hire chip only for someone else\'s onboarding',
        (tester) async {
      // My own onboarding — no chip.
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(task: task(), myUserId: 'me'),
      );
      expect(find.byKey(OnboardingTaskCard.hireChipKey), findsNothing);

      // A hire's task assigned to me (their manager) — chip with their name.
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(
          task: task(hireId: 'u2', dueDate: future.toIso8601String()),
          myUserId: 'me',
        ),
      );
      expect(find.byKey(OnboardingTaskCard.hireChipKey), findsOneWidget);
      expect(find.text('For Alice Johnson'), findsOneWidget);
    });

    testWidgets('fires the complete and skip callbacks while pending',
        (tester) async {
      var completed = false;
      var skipped = false;
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(
          task: task(),
          myUserId: 'me',
          onComplete: () => completed = true,
          onSkip: () => skipped = true,
        ),
      );

      await tester.tap(find.text('Complete'));
      expect(completed, isTrue);
      expect(skipped, isFalse);

      await tester.tap(find.text('Skip'));
      expect(skipped, isTrue);
    });

    testWidgets('completed tasks show a status chip instead of actions',
        (tester) async {
      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(task: task(status: 'done'), myUserId: 'me'),
      );
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Skip'), findsNothing);

      await pumpHomeWidget(
        tester,
        OnboardingTaskCard(task: task(status: 'skipped'), myUserId: 'me'),
      );
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
    });
  });
}
