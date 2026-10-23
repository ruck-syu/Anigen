import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:anigen/screens/home_screen.dart';
import 'package:anigen/providers/scraper_config_store.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/services/library_store.dart';

// Custom HTTP client to handle certificate issues on Windows
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Fix certificate verification issues on Windows
  HttpOverrides.global = MyHttpOverrides();

  // Pick up scraper fixes published in the repo without a new build
  ScraperConfigStore.refresh();

  // Watch history and My List, needed by the first screen
  await LibraryStore.instance.load();

  // AniList sign-in, if any; syncs in the background
  AniListAccount.instance.load();

  // Set system navigation bar color
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const AnigenApp());
}

class AnigenApp extends StatelessWidget {
  const AnigenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Black and red
    const base = Color(0xFF000000);
    const mantle = Color(0xFF0A0A0A);
    const surface0 = Color(0xFF1A1A1A);
    const surface1 = Color(0xFF262626);
    const text = Color(0xFFF5F5F5);
    const subtext0 = Color(0xFFA3A3A3);
    const red = Color(0xFFE50914);
    const darkRed = Color(0xFFB20710);

    return MaterialApp(
      title: 'Anigen',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: red,
          onPrimary: Colors.white,
          secondary: darkRed,
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
            borderSide: BorderSide(color: red, width: 2),
          ),
          hintStyle: GoogleFonts.jetBrainsMono(color: subtext0),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : null,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? red : null,
          ),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: text,
          textColor: text,
          tileColor: surface0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        iconTheme: const IconThemeData(color: text),
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(
          ThemeData.dark().textTheme.apply(bodyColor: text, displayColor: text),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: red,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: red),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Lets a mouse drag rows and carousels too, as on touch screens.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
