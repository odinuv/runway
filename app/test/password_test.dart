import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runway_app/auth/password.dart';

void main() {
  final hash = sha256.convert(utf8.encode('abheslo')).toString();

  test('correct password verifies', () {
    expect(verifyPassword('heslo', salt: 'ab', hash: hash), isTrue);
    expect(verifyPassword('heslo', salt: 'ab', hash: hash.toUpperCase()), isTrue);
  });

  test('wrong password or missing config rejects', () {
    expect(verifyPassword('Heslo', salt: 'ab', hash: hash), isFalse);
    expect(verifyPassword('', salt: '', hash: ''), isFalse);
  });
}
