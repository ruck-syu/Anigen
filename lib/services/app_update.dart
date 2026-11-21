import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  /// The `sha256sum` file published next to the APK, if the release has one.
  final String? apkSha256Url;

  const AppRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSize = 0,
    this.apkSha256Url,
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
  static const _timeout = Duration(seconds: 15);
  static bool _downloading = false;
  static const _releaseHosts = {
    'github.com',
    'api.github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };
  static final _abiSuffix = RegExp(
    r'-(armeabi(?:-v7a)?|arm64-v8a|x86(?:_64)?|mips(?:64)?|riscv64)\.apk$',
    caseSensitive: false,
  );

  static Uri? _releaseUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !_releaseHosts.contains(uri.host)) {
      return null;
    }
    return uri;
  }

  static Future<http.StreamedResponse> _get(
    http.Client client,
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response = await client
          .send(
            http.Request('GET', uri)
              ..followRedirects = false
              ..headers.addAll(headers),
          )
          .timeout(_timeout);
      if (!response.isRedirect) return response;
      final location = response.headers['location'];
      final target = location == null
          ? null
          : _releaseUri(uri.resolve(location).toString());
      if (target == null) throw Exception('invalid release redirect');
      await response.stream.drain<void>().timeout(_timeout);
      uri = target;
    }
    throw Exception('too many release redirects');
  }

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

  static void listenForInstallStatus() {
    if (!isSupported || _listening || onInstallFailed == null) return;
    _listening = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'installFailed') {
        throw MissingPluginException(call.method);
      }
      try {
        final report = onInstallFailed;
        if (report == null) throw MissingPluginException(call.method);
        final args = Map<String, dynamic>.from(call.arguments as Map);
        report(args['message'] as String? ?? 'the update wasn\'t installed');
      } catch (_) {
        _listening = false;
        rethrow;
      }
    });
    // Native delivers queued failures through the same handler as live ones.
    _channel.invokeMethod<void>('takePendingInstallFailure').catchError((
      Object _,
    ) {
      _listening = false;
    });
  }

  /// The latest release, or null if there isn't one for this platform.
  static Future<AppRelease?> latest() async {
    final client = http.Client();
    final Map<String, dynamic> json;
    try {
      final response = await _get(
        client,
        Uri.parse(_latestUrl),
        headers: const {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw Exception('github answered ${response.statusCode}');
      }
      final body = await response.stream.bytesToString().timeout(_timeout);
      json = jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
    // Tags look like v1.6.2; anything else isn't a release we can compare
    final tag = json['tag_name'] as String? ?? '';
    final version = _parse(tag);
    if (version == null) return null;

    final page =
        _releaseUri(json['html_url'])?.toString() ?? '$_releasesUrl/tag/$tag';
    final releaseAssets = [
      for (final asset
          in (json['assets'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
        if (asset['name'] case final String name)
          (
            name: name.toLowerCase(),
            url: _releaseUri(asset['browser_download_url']),
            size: asset['size'] as int? ?? 0,
          ),
    ];
    final assets = [
      for (final asset in releaseAssets)
        if (asset.url case final url?)
          (name: asset.name, url: url, size: asset.size),
    ];
    final desktopExtension = Platform.isWindows
        ? '.exe'
        : Platform.isMacOS
        ? '.dmg'
        : null;
    if (desktopExtension != null &&
        !assets.any((asset) => asset.name.endsWith(desktopExtension))) {
      return null;
    }

    ({String name, Uri url, int size})? apk;
    Uri? checksumUrl;
    if (Platform.isAndroid) {
      final abis = await _channel.invokeListMethod<String>('abis') ?? const [];
      for (final abi in abis) {
        apk = assets.where((a) => a.name.endsWith('-$abi.apk')).firstOrNull;
        if (apk != null) break;
      }
      apk ??= assets
          .where((a) => a.name.endsWith('.apk') && !_abiSuffix.hasMatch(a.name))
          .firstOrNull;
      // Nothing this device can install
      if (apk == null) return null;

      final checksumName = '${apk.name}.sha256';
      final checksum = releaseAssets
          .where((a) => a.name == checksumName)
          .firstOrNull;
      if (checksum != null) {
        checksumUrl = checksum.url;
        if (checksumUrl == null) throw Exception('invalid APK checksum URL');
      }
    }

    return AppRelease(
      version: version.join('.'),
      name: json['name'] as String? ?? tag,
      notes: (json['body'] as String? ?? '').trim(),
      pageUrl: page,
      apkUrl: apk?.url.toString(),
      apkSize: apk?.size ?? 0,
      apkSha256Url: checksumUrl?.toString(),
    );
  }

  /// Downloads [release]'s APK, reporting progress from 0 to 1, and returns
  /// the file.
  static Future<File> download(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final url = _releaseUri(release.apkUrl);
    if (url == null) throw Exception('invalid APK download URL');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/anigen-update.apk');
    final part = File('${file.path}.part');
    if (_downloading) throw Exception('an APK download is already in progress');
    final client = http.Client();
    _downloading = true;
    try {
      final expectedSha256 = await _expectedSha256(client, release);
      final response = await _get(
        client,
        url,
        headers: const {'Accept-Encoding': 'identity'},
      );
      if (response.statusCode != 200) {
        throw Exception('download failed (${response.statusCode})');
      }
      final total = release.apkSize > 0
          ? release.apkSize
          : response.contentLength ?? 0;
      final sink = part.openWrite();
      var received = 0;
      try {
        await sink.addStream(
          response.stream.timeout(_timeout).map((chunk) {
            received += chunk.length;
            if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
            return chunk;
          }),
        );
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw Exception('APK download size did not match the expected size');
      }
      if (expectedSha256 != null) {
        final digest = await sha256.bind(part.openRead()).first;
        if (digest.toString() != expectedSha256) {
          throw Exception('APK checksum did not match the release');
        }
      }
      return await part.rename(file.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
      _downloading = false;
    }
  }

  /// The APK's SHA-256 from the release's `.sha256` file, or null for older
  /// releases published without one.
  static Future<String?> _expectedSha256(
    http.Client client,
    AppRelease release,
  ) async {
    if (release.apkSha256Url == null) return null;
    final url = _releaseUri(release.apkSha256Url);
    if (url == null) throw Exception('invalid APK checksum URL');
    final response = await _get(client, url);
    if (response.statusCode != 200) {
      throw Exception('checksum download failed (${response.statusCode})');
    }
    final body = await response.stream.bytesToString().timeout(_timeout);
    // sha256sum writes "<hex>  <file name>"
    final hash = body.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw Exception('invalid APK checksum file');
    }
    return hash;
  }

  /// Whether Android lets this app install APKs. If not, [openInstallSettings]
  /// takes the user to the switch.
  static Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  static Future<void> openInstallSettings() =>
      _channel.invokeMethod('openInstallSettings');

  /// Starts the system install; Android asks the user to confirm.
  static Future<void> install(File apk) async {
    listenForInstallStatus();
    await _channel.invokeMethod('install', {'path': apk.path});
  }
}
