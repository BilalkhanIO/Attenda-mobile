import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/kudos/kudos_screen.dart';

import '../home_widgets/harness.dart';

void main() {
  Map<String, dynamic> kudos({String? emoji = '👏'}) => {
        'id': 'k1',
        'message': 'Thanks for covering my shift on Friday!',
        'emoji': emoji,
        'created_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'giver': {
          'id': 'u1',
          'name': 'Sam Carter',
          'avatar_url': null,
          'department': 'Support',
        },
        'recipient': {
          'id': 'u2',
          'name': 'Aisha Khan',
          'avatar_url': null,
          'department': 'Design',
        },
      };

  group('kudosTimeAgo', () {
    test('formats on the notifications scale and tolerates bad input', () {
      expect(kudosTimeAgo(null), '');
      expect(kudosTimeAgo('not-a-date'), '');
      expect(
        kudosTimeAgo(DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String()),
        '5m ago',
      );
      expect(
        kudosTimeAgo(
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String()),
        '2d ago',
      );
    });
  });

  group('kudosFeedParticipants', () {
    test('dedupes givers and recipients, excludes me and sorts by name', () {
      final feed = [
        kudos(),
        kudos(), // duplicate participants collapse
        {
          ...kudos(),
          'id': 'k2',
          'giver': {'id': 'me', 'name': 'Me Myself'},
          'recipient': {'id': 'u3', 'name': 'Bilal Ahmed'},
        },
      ];

      final people = kudosFeedParticipants(
        feed.cast<Map<String, dynamic>>(),
        excludeUserId: 'me',
      );

      expect(people.map((u) => u['name']).toList(),
          ['Aisha Khan', 'Bilal Ahmed', 'Sam Carter']);
    });
  });

  group('KudosCard', () {
    testWidgets('renders giver, recipient, emoji, message and relative time',
        (tester) async {
      await pumpHomeWidget(tester, KudosCard(kudos: kudos()));

      expect(find.text('Sam Carter'), findsOneWidget);
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('👏'), findsOneWidget);
      expect(find.text('Thanks for covering my shift on Friday!'),
          findsOneWidget);
      expect(find.text('2h ago'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget); // giver's department
    });

    testWidgets('omits the emoji when none was sent', (tester) async {
      await pumpHomeWidget(tester, KudosCard(kudos: kudos(emoji: null)));

      expect(find.text('👏'), findsNothing);
      expect(find.text('Thanks for covering my shift on Friday!'),
          findsOneWidget);
    });
  });
}
