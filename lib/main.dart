import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: Sub3App()));
}

class Sub3App extends StatelessWidget {
  const Sub3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sub3',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeShell(),
    );
  }
}
