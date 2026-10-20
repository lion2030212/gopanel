import 'package:admin_panel/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase Web options target the configured GoDrive project', () {
    const options = DefaultFirebaseOptions.web;

    expect(options.projectId, 'godrive-d7f94');
    expect(options.storageBucket, 'godrive-d7f94.firebasestorage.app');
    expect(options.authDomain, 'godrive-d7f94.firebaseapp.com');
    expect(options.messagingSenderId, '1072024537202');
    expect(options.appId, '1:1072024537202:web:11d77f16534a6ffab15aeb');
    expect(options.measurementId, 'G-3W5LY87J0N');
  });
}
