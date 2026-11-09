import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart' as config;
import 'data/repository.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('cs');
  Intl.defaultLocale = 'cs';

  final repository = EntriesRepository(
    client: http.Client(),
    sasUrl: config.sasUrl,
    cacheFile: () async => File('${(await getApplicationSupportDirectory()).path}/$documentBlob'),
  );
  final state = AppState(
    prefs: await SharedPreferences.getInstance(),
    loader: repository.load,
    salt: config.passwordSalt,
    hash: config.passwordHash,
  );
  if (state.loggedIn) state.refresh();
  runApp(RunwayApp(state: state));
}

class RunwayApp extends StatelessWidget {
  const RunwayApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Runway',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B6FD8)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF3B6FD8), brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.loggedIn ? HomeScreen(state: state) : LoginScreen(state: state),
      ),
    );
  }
}
