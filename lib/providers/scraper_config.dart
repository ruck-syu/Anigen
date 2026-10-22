import 'dart:convert';

/// Every site-specific value the scraper depends on.
///
/// ani-cli breaks whenever the upstream site changes a domain, a path, the
/// player markup or the embed key. Keeping all of those in
/// `scraper_config.json` lets the app pick up a fix by downloading that file
/// instead of shipping a new build. See [ScraperConfigStore].
class ScraperConfig {
  /// Bump when the app needs new fields, so older builds ignore configs
  /// they don't understand instead of breaking.
  static const int supportedSchemaVersion = 1;

  final int schemaVersion;
  final int configVersion;
  final String aniCliVersion;
  final String userAgent;
  final String baseUrl;
  final String searchUrl;
  final String episodesUrl;
  final String serversUrl;
  final String searchItemSelector;
  final String searchTitleSelector;
  final String searchPosterSelector;
  final String episodeItemSelector;
  final String serverItemSelector;
  final List<String> serverNames;
  final String translationType;
  final String embedBlobPattern;
  final String embedXorKey;

  const ScraperConfig({
    required this.schemaVersion,
    required this.configVersion,
    required this.aniCliVersion,
    required this.userAgent,
    required this.baseUrl,
    required this.searchUrl,
    required this.episodesUrl,
    required this.serversUrl,
    required this.searchItemSelector,
    required this.searchTitleSelector,
    required this.searchPosterSelector,
    required this.episodeItemSelector,
    required this.serverItemSelector,
    required this.serverNames,
    required this.translationType,
    required this.embedBlobPattern,
    required this.embedXorKey,
  });

  factory ScraperConfig.fromJson(Map<String, dynamic> json) {
    return ScraperConfig(
      schemaVersion: json['schemaVersion'] as int,
      configVersion: json['configVersion'] as int,
      aniCliVersion: json['aniCliVersion'] as String,
      userAgent: json['userAgent'] as String,
      baseUrl: json['baseUrl'] as String,
      searchUrl: json['searchUrl'] as String,
      episodesUrl: json['episodesUrl'] as String,
      serversUrl: json['serversUrl'] as String,
      searchItemSelector: json['searchItemSelector'] as String,
      searchTitleSelector: json['searchTitleSelector'] as String,
      searchPosterSelector: json['searchPosterSelector'] as String,
      episodeItemSelector: json['episodeItemSelector'] as String,
      serverItemSelector: json['serverItemSelector'] as String,
      serverNames: List<String>.from(json['serverNames'] as List),
      translationType: json['translationType'] as String,
      embedBlobPattern: json['embedBlobPattern'] as String,
      embedXorKey: json['embedXorKey'] as String,
    );
  }

  /// Parses and validates a config file. Returns null if it is malformed or
  /// written for a schema this build doesn't support.
  static ScraperConfig? tryParse(String source) {
    try {
      final config = ScraperConfig.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
      if (config.schemaVersion != supportedSchemaVersion) return null;
      RegExp(config.embedBlobPattern); // throws if the pattern is invalid
      return config;
    } catch (e) {
      return null;
    }
  }

  String buildUrl(String template, Map<String, String> params) {
    var url = template.replaceAll('{base}', baseUrl);
    params.forEach((key, value) {
      url = url.replaceAll('{$key}', Uri.encodeQueryComponent(value));
    });
    return url;
  }
}
