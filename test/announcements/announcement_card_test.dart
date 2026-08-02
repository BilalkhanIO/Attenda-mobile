import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/announcements/announcements_screen.dart';

import '../home_widgets/harness.dart';

void main() {
  Map<String, dynamic> announcement({String? myReadAt}) => {
        'id': 'a1',
        'title': 'Office closed on Friday',
        'body': 'The office will be closed on Friday for maintenance. '
            'Please plan to work remotely and coordinate with your manager.',
        'published_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'my_read_at': myReadAt,
        'author': {'name': 'Sam Carter'},
        'department_id': null,
      };

  group('announcementTimeAgo', () {
    test('formats on the notifications scale and tolerates bad input', () {
      expect(announcementTimeAgo(null), '');
      expect(announcementTimeAgo('not-a-date'), '');
      expect(
        announcementTimeAgo(DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String()),
        '5m ago',
      );
      expect(
        announcementTimeAgo(
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String()),
        '2d ago',
      );
    });
  });

  group('AnnouncementCard', () {
    testWidgets('renders author, title, relative time and unread dot',
        (tester) async {
      await pumpHomeWidget(
        tester,
        AnnouncementCard(announcement: announcement()),
      );

      expect(find.text('Office closed on Friday'), findsOneWidget);
      expect(find.text('Sam Carter'), findsOneWidget);
      expect(find.text('2h ago'), findsOneWidget);
      expect(find.byKey(AnnouncementCard.unreadDotKey), findsOneWidget);

      final title = tester.widget<Text>(find.text('Office closed on Friday'));
      expect(title.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('hides the unread indicator once my_read_at is set',
        (tester) async {
      await pumpHomeWidget(
        tester,
        AnnouncementCard(
          announcement:
              announcement(myReadAt: '2026-07-30T10:00:00.000Z'),
        ),
      );

      expect(find.byKey(AnnouncementCard.unreadDotKey), findsNothing);
      final title = tester.widget<Text>(find.text('Office closed on Friday'));
      expect(title.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('collapses the body to a preview and expands on demand',
        (tester) async {
      final data = announcement();

      await pumpHomeWidget(
        tester,
        AnnouncementCard(announcement: data),
      );
      var body = tester
          .widget<Text>(find.textContaining('closed on Friday for maintenance'));
      expect(body.maxLines, 2);

      await pumpHomeWidget(
        tester,
        AnnouncementCard(announcement: data, expanded: true),
      );
      body = tester
          .widget<Text>(find.textContaining('closed on Friday for maintenance'));
      expect(body.maxLines, isNull);
    });

    testWidgets('fires the tap callback', (tester) async {
      var tapped = false;
      await pumpHomeWidget(
        tester,
        AnnouncementCard(
          announcement: announcement(),
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('Office closed on Friday'));
      expect(tapped, isTrue);
    });
  });
}
