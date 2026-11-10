// Vygeneruje sůl a hash statického hesla a zapíše je do .dart-defines.json.
// Použití: dart run tool/hash_password.dart <heslo>
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length != 1 || args.first.isEmpty) {
    stderr.writeln('Použití: dart run tool/hash_password.dart <heslo>');
    exit(64);
  }
  final random = Random.secure();
  final salt = List.generate(16, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final hash = sha256.convert(utf8.encode(salt + args.first)).toString();

  final file = File('.dart-defines.json');
  final defines = file.existsSync()
      ? Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map)
      : <String, dynamic>{};
  defines['RUNWAY_PASSWORD_SALT'] = salt;
  defines['RUNWAY_PASSWORD_HASH'] = hash;
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(defines));
  stdout.writeln('Zapsáno do .dart-defines.json (sůl $salt).');
}
