import 'package:flutter/material.dart';

import 'core/di/injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupCoreDependencies();
  runApp(const CerneApp());
}

/// Root widget. Portrait-only, light-mode-only, fixed 390x844 frame — no
/// breakpoint, landscape or dark-mode path anywhere in the app (per the
/// epic's UX constraints). Feature screens/navigation ship in later stories;
/// this story is core infrastructure only.
class CerneApp extends StatelessWidget {
  const CerneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: Text('Cerne')),
      ),
    );
  }
}
