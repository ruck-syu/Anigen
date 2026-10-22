import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'scraper_config.dart';

/// Loads the scraper config: last downloaded copy if there is one, otherwise
/// the copy bundled with the app. [refresh] pulls the latest copy from the
/// repo, so scraper fixes ship by editing `scraper_config.json` on `main`.
class ScraperConfigStore {
  static const String remoteUrl =
      'https://raw.githubusercontent.com/ruck-syu/Anigen/main/scraper_config.json';
  static const String _assetPath = 'scraper_config.json';
  static const String _cacheKey = 'scraper_config';

  static ScraperConfig? _current;
  static Future<bool>? _refreshing;

  static Future<ScraperConfig> get() async {
    if (_current != null) return _current!;

    final bundled = ScraperConfig.tryParse(
      await rootBundle.loadString(_assetPath),
    )!;
    ScraperConfig? cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final source = prefs.getString(_cacheKey);
      if (source != null) cached = ScraperConfig.tryParse(source);
    } catch (e) {
      // Fall back to the bundled config
    }

    // A newer app build may bundle a newer config than the cached download
    _current = cached != null && cached.configVersion > bundled.configVersion
        ? cached
        : bundled;
    return _current!;
  }

  /// Downloads the latest config. Returns true if a newer one was applied.
  /// Concurrent callers share the same request.
  static Future<bool> refresh() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  static Future<bool> _refresh() async {
    final current = await get();
    try {
      final response = await http
          .get(Uri.parse(remoteUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;

      final remote = ScraperConfig.tryParse(response.body);
      if (remote == null || remote.configVersion <= current.configVersion) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, response.body);
      _current = remote;
      return true;
    } catch (e) {
      return false;
    }
  }
}
