import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/home/home_page.dart';
import 'features/settings/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: OmniForgeApp()));
}

class OmniForgeApp extends ConsumerWidget {
  const OmniForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'OmniForge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: settings.seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: switch (settings.themeMode) {
        ThemeMode.system => ThemeMode.system,
        ThemeMode.light => ThemeMode.light,
        ThemeMode.dark => ThemeMode.dark,
      },
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
