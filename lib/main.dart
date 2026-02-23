import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'theme/app_theme.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Request gallery permission upfront so it doesn't interrupt a workout
  if (!await Gal.hasAccess(toAlbum: true)) {
    await Gal.requestAccess(toAlbum: true);
  }

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
