import 'package:flutter/material.dart';

/// Shown briefly at startup while the stored auth token (if any) is being
/// validated, before the router decides between the login screen and home.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
