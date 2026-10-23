import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A version published by the Android workflow as a GitHub release.
class AppRelease {
  /// Like 1.6.2, from the v1.6.2 tag.
  final String version;
  final String name;
  final String notes;

  /// The release on GitHub, for platforms that update by hand.
  final String pageUrl;

  /// The APK for this device. Android only.
  final String? apkUrl;
  final int apkSize;

  const AppRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSize = 0,
  });
}

/// Finds the latest release on GitHub. On Android it also downloads the APK
/// for this device and hands it to the system installer; elsewhere the
/// release page has the download.
class AppUpdate {
  static const _latestUrl =
      'https://api.github.com/repos/ruck-syu/Anigen/releases/latest';
  static const _releasesUrl = 'https://github.com/ruck-syu/Anigen/releases';
  static const _channel = MethodChannel('anigen/update');

  /// This app's version, from `--dart-define=APP_VERSION`. Empty for local
  /// builds.
  static const currentVersion = String.fromEnvironment('APP_VERSION');

  /// Whether [release] is newer than this app. Local builds take any release.
  static bool isNewer(AppRelease release) {
    final current = _parse(currentVersion);
    if (current == null) return true;
    final latest = _parse(release.version)!;
    for (var i = 0; i < 3; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return false;
  }

  static final _versionPattern = RegExp(r'^v?(\d+)\.(\d+)(?:\.(\d+))?$');

  /// [major, minor, patch], or null if [version] isn't one.
  static List<int>? _parse(String version) {
    final match = _versionPattern.firstMatch(version);
    if (match == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i) ?? '0')];
  }

  /// Whether updates install from inside the app.
  static bool get isSupported => Platform.isAndroid;

  /// Whether this build can tell if it's out of date: a release build, on a
  /// platform the workflow publishes.
  static bool get canCheck => currentVersion.isNotEmpty && hasReleases;

  /// Whether the release workflow builds for this platform.
  static bool get hasReleases =>
      Platform.isAndroid || Platform.isMacOS || Platform.isWindows;

  /// Called when the system installer gives up, with its reason.
  static void Function(String message)? onInstallFailed;

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installFailed') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onInstallFailed?.call(
          args['message'] as String? ?? 'the update wasn\'t installed',
        );
      }
    });
  }

  /// The latest release, or null if there isn't one for this platform.
  static Future<AppRelease?> latest() async {
    final response = await http
        .get(
          Uri.parse(_latestUrl),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('github answered ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // Tags look like v1.6.2; anything else isn't a release we can compare
    final tag = json['tag_name'] as String? ?? '';
    final version = _parse(tag);
    if (version == null) return null;

    final page = json['html_url'] as String? ?? '$_releasesUrl/tag/$tag';
    final release = (
      version: version.join('.'),
      name: json['name'] as String? ?? tag,
      notes: (json['body'] as String? ?? '').trim(),
    );
    if (!Platform.isAndroid) {
      return AppRelease(
        version: release.version,
        name: release.name,
        notes: release.notes,
        pageUrl: page,
      );
    }

    final abi = await _channel.invokeMethod<String>('abi') ?? 'arm64-v8a';
    final assets = [
      for (final asset in json['assets'] as List? ?? const [])
        asset as Map<String, dynamic>,
    ];
    final apk =
        assets
            .where((a) => (a['name'] as String).endsWith('-$abi.apk'))
            .firstOrNull ??
        assets.where((a) => (a['name'] as String).endsWith('.apk')).firstOrNull;
    if (apk == null) return null;

    return AppRelease(
      version: release.version,
      name: release.name,
      notes: release.notes,
      pageUrl: page,
      apkUrl: apk['browser_download_url'] as String,
      apkSize: apk['size'] as int? ?? 0,
    );
  }

  /// Downloads [release]'s APK, reporting progress from 0 to 1, and returns
  /// the file.
  static Future<File> download(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/anigen-update.apk');
    final client = http.Client();
    try {
      final response = await client.send(
        http.Request('GET', Uri.parse(release.apkUrl!)),
      );
      if (response.statusCode != 200) {
        throw Exception('download failed (${response.statusCode})');
      }
      final total = response.contentLength ?? release.apkSize;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Whether Android lets this app install APKs. If not, [openInstallSettings]
  /// takes the user to the switch.
  static Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  static Future<void> openInstallSettings() =>
      _channel.invokeMethod('openInstallSettings');

  /// Starts the system install; Android asks the user to confirm.
  static Future<void> install(File apk) async {
    _listen();
    await _channel.invokeMethod('install', {'path': apk.path});
  }
}
