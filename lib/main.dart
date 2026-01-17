import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:anigen/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const AnigenApp());
}

class AnigenApp extends StatelessWidget {
  const AnigenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anigen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
