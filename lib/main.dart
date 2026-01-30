import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:anigen/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  // Set system navigation bar color
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF1e1e2e), // Catppuccin Mocha base
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const AnigenApp());
}

class AnigenApp extends StatelessWidget {
  const AnigenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Catppuccin Mocha colors
    const base = Color(0xFF1e1e2e);
    const mantle = Color(0xFF181825);
    const crust = Color(0xFF11111b);
    const surface0 = Color(0xFF313244);
    const surface1 = Color(0xFF45475a);
    const surface2 = Color(0xFF585b70);
    const text = Color(0xFFcdd6f4);
    const subtext0 = Color(0xFFa6adc8);
    const lavender = Color(0xFFb4befe);
    const blue = Color(0xFF89b4fa);
    const sapphire = Color(0xFF74c7ec);
    const mauve = Color(0xFFcba6f7);
    const red = Color(0xFFf38ba8);
    
    return MaterialApp(
      title: 'Anigen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: mauve,
          secondary: lavender,
          surface: base,
          surfaceContainerHighest: surface0,
          surfaceContainer: surface1,
          onSurface: text,
          onSurfaceVariant: subtext0,
          error: red,
        ),
        scaffoldBackgroundColor: base,
        appBarTheme: AppBarTheme(
          backgroundColor: mantle,
          foregroundColor: text,
          elevation: 0,
          titleTextStyle: GoogleFonts.jetBrainsMono(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface0,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface0,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mauve, width: 2),
          ),
          hintStyle: GoogleFonts.jetBrainsMono(color: subtext0),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: lavender,
          textColor: text,
          tileColor: surface0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        iconTheme: const IconThemeData(color: lavender),
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(
          ThemeData.dark().textTheme.apply(
            bodyColor: text,
            displayColor: text,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: mauve,
            foregroundColor: crust,
            textStyle: GoogleFonts.jetBrainsMono(
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: mauve,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
