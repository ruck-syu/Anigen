import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A build published by the Android workflow as a GitHub release.
class AppRelease {
  final int build;
  final String name;
  final String notes;
  final String apkUrl;
  final int apkSize;

  const AppRelease({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });
}

/// In-app updates on Android: finds the latest release on GitHub, downloads
/// the APK for this device and hands it to the system installer.
class AppUpdate {
  static const _latestUrl =
      'https://api.github.com/repos/ruck-syu/Anigen/releases/latest';
  static const _channel = MethodChannel('anigen/update');

  /// The CI run that built this app, from `--dart-define=BUILD_NUMBER`.
  /// 0 for local builds.
  static const currentBuild = int.fromEnvironment('BUILD_NUMBER');

  static bool get isSupported => Platform.isAndroid;

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

  /// The latest release, or null if there isn't one this app can install.
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
    // Tags look like build-42; older hand-made releases don't count
    final match = RegExp(
      r'^build-(\d+)$',
    ).firstMatch(json['tag_name'] as String? ?? '');
    if (match == null) return null;

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
      build: int.parse(match.group(1)!),
      name: json['name'] as String? ?? match.group(0)!,
      notes: (json['body'] as String? ?? '').trim(),
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
        http.Request('GET', Uri.parse(release.apkUrl)),
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
