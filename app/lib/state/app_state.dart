import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/password.dart';
import '../data/repository.dart';
import '../domain/runway_calculator.dart';

const maxIncome = 100000.0;
const windowOptions = [3, 6, 12, 24];

const _kLoggedIn = 'loggedIn';
const _kIncome = 'newIncome';
const _kSavings = 'savingsOverride';
const _kWindow = 'windowMonths';
const _kUnexpected = 'includeUnexpected';

/// Jediný stav appky: přihlášení, načtená data a vstupy modelu (persistované lokálně).
class AppState extends ChangeNotifier {
  AppState({
    required this._prefs,
    required this._loader,
    required this._salt,
    required this._hash,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final Future<LoadResult> Function() _loader;
  final String _salt;
  final String _hash;
  final DateTime Function() _now;

  LoadResult? load;
  bool loading = false;

  bool get loggedIn => _prefs.getBool(_kLoggedIn) ?? false;
  double get newIncome => _prefs.getDouble(_kIncome) ?? 0;
  double? get savingsOverride => _prefs.getDouble(_kSavings);
  int get windowMonths => _prefs.getInt(_kWindow) ?? 12;
  bool get includeUnexpected => _prefs.getBool(_kUnexpected) ?? false;

  double get savings {
    final current = load;
    return savingsOverride ?? (current is Loaded ? current.doc.initialBalance : 0);
  }

  RunwayResult? get result {
    final current = load;
    if (current is! Loaded) return null;
    return calculateRunway(
      current.doc,
      RunwayInput(
        savings: savings,
        newMonthlyIncome: newIncome,
        windowMonths: windowMonths,
        includeUnexpected: includeUnexpected,
        today: _now(),
      ),
    );
  }

  bool login(String password) {
    if (!verifyPassword(password, salt: _salt, hash: _hash)) return false;
    _prefs.setBool(_kLoggedIn, true);
    notifyListeners();
    return true;
  }

  void logout() {
    _prefs.setBool(_kLoggedIn, false);
    notifyListeners();
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    load = await _loader();
    loading = false;
    notifyListeners();
  }

  void setNewIncome(double value) {
    _prefs.setDouble(_kIncome, value.clamp(0, maxIncome).toDouble());
    notifyListeners();
  }

  void setSavings(double? value) {
    if (value == null) {
      _prefs.remove(_kSavings);
    } else {
      _prefs.setDouble(_kSavings, value < 0 ? 0 : value);
    }
    notifyListeners();
  }

  void setWindow(int months) {
    if (!windowOptions.contains(months)) return;
    _prefs.setInt(_kWindow, months);
    notifyListeners();
  }

  void setIncludeUnexpected(bool value) {
    _prefs.setBool(_kUnexpected, value);
    notifyListeners();
  }
}
