import 'package:admin_panel/core/admin_session.dart';
import 'package:admin_panel/core/admin_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists and restores an admin session without password data',
      () async {
    const session = AdminSession(
      token: 'session-token',
      id: 'admin-1',
      username: 'operator',
      fullName: 'Panel Operator',
      role: 'manager',
      permissions: {'map.view', 'rides.read'},
    );
    final storage = AdminSessionStorage();

    await storage.write(session);

    expect(await storage.read(), isNotNull);
    expect((await storage.read())!.toJson(), session.toJson());
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('admin_session'), isNot(contains('password')));
  });

  test('clears the stored session on logout', () async {
    const session = AdminSession(
      token: 'session-token',
      id: 'admin-1',
      username: 'operator',
      role: 'manager',
      permissions: {'map.view'},
    );
    final storage = AdminSessionStorage();
    await storage.write(session);

    await storage.clear();

    expect(await storage.read(), isNull);
  });
}
