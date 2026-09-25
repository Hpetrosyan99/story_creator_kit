import 'package:flutter/material.dart';

import 'home_page.dart';

void main() => runApp(const StoryKitExampleApp());

class StoryKitExampleApp extends StatelessWidget {
  const StoryKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Story Creator Kit',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFFE4572E),
      scaffoldBackgroundColor: const Color(0xFF0E0E0E),
    ),
    home: const HomePage(),
  );
}
