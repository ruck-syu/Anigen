import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin GraphQL client for AniList.
///
/// AniList limits by request count rather than by time (90 a minute, 30 while
/// the API is degraded), so the provider asks for everything a screen needs in
/// one query instead of one request per row. A 429 is waited out rather than
/// thrown, since losing one row is much worse than waiting a few seconds.
class AniListClient {
  AniListClient._();
  static final AniListClient instance = AniListClient._();

  static const _endpoint = 'https://graphql.anilist.co';

  /// How long a catalogue response stays usable before it is fetched again.
  /// Kept in memory only: AniList is a live catalogue, not a place to keep
  /// our own copy of the data.
  static const _cacheTtl = Duration(seconds: 90);

  /// Set once the user signs in. Empty for the public catalogue.
  String? accessToken;

  final _http = http.Client();
  final _cache = <String, _CachedResponse>{};

  Future<Map<String, dynamic>> request(
    String document, {
    Map<String, dynamic>? variables,
    bool cacheable = true,
  }) async {
    final key = '$document|${jsonEncode(variables ?? const {})}|$accessToken';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) {
      return hit.data;
    }

    final data = await _send(document, variables);

    if (cacheable) {
      _cache[key] = _CachedResponse(data);
      // Don't let the cache grow without bound on a long session.
      if (_cache.length > 64) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest);
      }
    }
    return data;
  }

  /// Drops everything cached, used after the user changes their list.
  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> _send(
    String document,
    Map<String, dynamic>? variables,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final http.Response response;
      try {
        response = await _http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                if (accessToken != null)
                  'Authorization': 'Bearer $accessToken',
              },
              body: jsonEncode({
                'query': document,
                if (variables != null) 'variables': variables,
              }),
            )
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        throw Exception('anilist timed out');
      } catch (e) {
        throw Exception('could not reach anilist');
      }

      if (response.statusCode == 429) {
        await Future.delayed(_retryAfter(response));
        continue;
      }

      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('anilist returned ${response.statusCode}');
      }

      final errors = body['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first as Map<String, dynamic>;
        throw Exception(first['message'] ?? 'anilist request failed');
      }
      if (response.statusCode >= 400) {
        throw Exception('anilist returned ${response.statusCode}');
      }

      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('anilist returned no data');
      }
      return data;
    }
    throw Exception('anilist is rate limiting us, try again shortly');
  }

  /// How long to wait before trying again after a 429.
  Duration _retryAfter(http.Response response) {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null) return Duration(seconds: retryAfter.clamp(1, 60));

    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (reset != null) {
      final seconds = reset - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return Duration(seconds: seconds.clamp(1, 60));
    }
    return const Duration(seconds: 30);
  }
}

class _CachedResponse {
  _CachedResponse(this.data);

  final Map<String, dynamic> data;
  final DateTime at = DateTime.now();
}
