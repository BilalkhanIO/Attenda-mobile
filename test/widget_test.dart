import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/models/capabilities.dart';
import 'package:attenda/services/auth_provider.dart';

void main() {
  group('AuthUser role helpers', () {
    AuthUser userWithRole(String role) => AuthUser(
          id: 'u1',
          orgId: 'o1',
          role: role,
          name: 'Test User',
          email: 'test@example.com',
        );

    test('employee has no elevated roles', () {
      final u = userWithRole('employee');
      expect(u.isManager, isFalse);
      expect(u.isHRAdmin, isFalse);
      expect(u.isSuperAdmin, isFalse);
    });

    test('manager is manager but not HR admin', () {
      final u = userWithRole('manager');
      expect(u.isManager, isTrue);
      expect(u.isHRAdmin, isFalse);
      expect(u.isSuperAdmin, isFalse);
    });

    test('hr_admin is manager and HR admin but not super admin', () {
      final u = userWithRole('hr_admin');
      expect(u.isManager, isTrue);
      expect(u.isHRAdmin, isTrue);
      expect(u.isSuperAdmin, isFalse);
    });

    test('super_admin has all role helpers', () {
      final u = userWithRole('super_admin');
      expect(u.isManager, isTrue);
      expect(u.isHRAdmin, isTrue);
      expect(u.isSuperAdmin, isTrue);
    });
  });

  group('Capabilities', () {
    test('parses features and permissions from JSON', () {
      final caps = Capabilities.fromJson({
        'features': {'leave_management': true, 'shifts': false},
        'permissions': ['attendance.view', 'leave.request'],
      });
      expect(caps.hasFeature('leave_management'), isTrue);
      expect(caps.hasFeature('shifts'), isFalse);
      expect(caps.hasFeature('unknown_feature'), isFalse);
      expect(caps.hasPermission('attendance.view'), isTrue);
      expect(caps.hasPermission('payroll.manage'), isFalse);
    });

    test('tolerates missing keys', () {
      final caps = Capabilities.fromJson({});
      expect(caps.hasFeature('anything'), isFalse);
      expect(caps.hasPermission('anything'), isFalse);
    });
  });
}
