import 'package:flutter/material.dart';

import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.state.login(_password.text)) {
      widget.state.refresh();
    } else {
      setState(() => _error = 'Nesprávné heslo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Runway', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(labelText: 'Heslo', errorText: _error),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _submit, child: const Text('Přihlásit')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
