import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Ověří statické heslo proti hashi `sha256(salt + heslo)` zapečenému při buildu.
bool verifyPassword(String input, {required String salt, required String hash}) {
  if (hash.isEmpty) return false;
  final computed = sha256.convert(utf8.encode(salt + input)).toString();
  return computed == hash.toLowerCase();
}
