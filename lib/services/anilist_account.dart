import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:anigen/providers/anilist_client.dart';
import 'package:anigen/services/library_store.dart';

/// Your entry for one title on AniList.
class AniListEntry {
  final int id;
  final LibraryTitle title;
  final String status;
  final int progress;
  final int updatedAt;

  /// Out of 10, 0 when unscored.
  final double score;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const AniListEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.progress,
    required this.updatedAt,
    this.score = 0,
    this.startedAt,
    this.completedAt,
  });

  /// "watching", "plan to watch", ...
  String get label => labelFor(status);

  static String labelFor(String status) => switch (status) {
    'CURRENT' => 'watching',
    'PLANNING' => 'plan to watch',
    'COMPLETED' => 'completed',
    'DROPPED' => 'dropped',
    'PAUSED' => 'paused',
    'REPEATING' => 'rewatching',
    _ => status.toLowerCase(),
  };

  /// The order the profile shows the lists in.
  static const statuses = [
    'CURRENT',
    'REPEATING',
    'PLANNING',
    'PAUSED',
    'COMPLETED',
    'DROPPED',
  ];
}

/// The signed-in AniList account.
///
/// Signed in, the details page tracks titles on AniList, My List shows your
/// AniList stats, and finishing an episode moves your progress. Favourites
/// stay on the device either way.
class AniListAccount extends ChangeNotifier {
  AniListAccount._();
  static final AniListAccount instance = AniListAccount._();

  /// The API client registered at https://anilist.co/settings/developer,
  /// with the redirect URL `anigen://oauth/callback`. Sign-in uses the
  /// implicit grant, so the client secret is never needed in the app.
  /// Override with `--dart-define=ANILIST_CLIENT_ID=<id>`.
  static const clientId = String.fromEnvironment(
    'ANILIST_CLIENT_ID',
    defaultValue: '54578',
  );
  static const _callbackScheme = 'anigen';

  static const _tokenKey = 'anilist_token';
  static const _expiresKey = 'anilist_token_expires';
  static const _nameKey = 'anilist_name';

  final _storage = const FlutterSecureStorage();
  final _client = AniListClient.instance;
  final _library = LibraryStore.instance;

  String? userName;
  String? avatar;
  DateTime? expiresAt;

  /// The token was rejected or ran out (they last a year and can't be
  /// refreshed), so the user has to connect again.
  bool needsReconnect = false;
  bool isBusy = false;
  String? error;

  /// mediaId -> your entry, from the last sync.
  final Map<int, AniListEntry> _entries = {};

  bool get isConfigured => clientId.isNotEmpty;
  bool get isSignedIn => _client.accessToken != null;

  AniListEntry? entryFor(int? mediaId) =>
      mediaId == null ? null : _entries[mediaId];

  /// Like [entryFor], for titles that may only know their MAL id.
  AniListEntry? entryForTitle(LibraryTitle title) =>
      entryFor(title.anilistId) ??
      (title.malId == null
          ? null
          : _entries.values
                .where((e) => e.title.malId == title.malId)
                .firstOrNull);

  Future<void> load() async {
    _library.onEpisodeWatched = _onEpisodeWatched;
    try {
      final token = await _storage.read(key: _tokenKey);
      final expires = int.tryParse(await _storage.read(key: _expiresKey) ?? '');
      if (token == null) return;
      expiresAt = expires == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expires);
      if (expiresAt != null && expiresAt!.isBefore(DateTime.now())) {
        _expire();
        return;
      }
      _client.accessToken = token;
      userName = await _storage.read(key: _nameKey);
      notifyListeners();
      // Don't hold up startup on the network. Until this finishes, AniList
      // shows the copy of your AniList list from the last sync.
      sync();
    } catch (e) {
      debugPrint('anilist: $e');
    }
  }

  Future<void> signIn() async {
    if (!isConfigured || isBusy) return;
    _setBusy(true);
    try {
      final result = await FlutterWebAuth2.authenticate(
        url:
            'https://anilist.co/api/v2/oauth/authorize'
            '?client_id=$clientId&response_type=token',
        callbackUrlScheme: _callbackScheme,
      );
      // The token comes back in the fragment:
      // anigen://oauth/callback#access_token=...&token_type=Bearer&expires_in=...
      final params = Uri.splitQueryString(Uri.parse(result).fragment);
      final token = params['access_token'];
      if (token == null || token.isEmpty) {
        throw Exception(params['error_description'] ?? 'no token returned');
      }
      final expiresIn = int.tryParse(params['expires_in'] ?? '');
      expiresAt = expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn));
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(
        key: _expiresKey,
        value: expiresAt?.millisecondsSinceEpoch.toString(),
      );
      _client.accessToken = token;
      _client.clearCache();
      needsReconnect = false;
      error = null;
      _setBusy(false);
      await sync();
    } catch (e) {
      // Closing the browser lands here too, which isn't worth a message.
      final message = e.toString();
      error = message.contains('CANCELED') ? null : _clean(message);
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiresKey);
    await _storage.delete(key: _nameKey);
    _client.accessToken = null;
    _client.clearCache();
    userName = null;
    avatar = null;
    expiresAt = null;
    needsReconnect = false;
    error = null;
    _entries.clear();
    notifyListeners();
  }

  /// Pulls your AniList anime list.
  Future<void> sync() async {
    if (!isSignedIn || isBusy) return;
    _setBusy(true);
    try {
      final viewer =
          (await _client.request(_viewerQuery, cacheable: false))['Viewer']
              as Map<String, dynamic>;
      userName = viewer['name'] as String?;
      avatar =
          (viewer['avatar'] as Map<String, dynamic>?)?['medium'] as String?;
      if (userName != null) {
        await _storage.write(key: _nameKey, value: userName);
      }

      final data = await _client.request(
        _listQuery,
        variables: {'userId': viewer['id']},
        cacheable: false,
      );
      final lists =
          (data['MediaListCollection'] as Map<String, dynamic>?)?['lists']
              as List? ??
          const [];
      _entries.clear();
      for (final list in lists) {
        for (final raw in (list as Map<String, dynamic>)['entries'] as List) {
          final entry = _parseEntry(raw as Map<String, dynamic>);
          // Custom lists repeat entries; keep the first.
          if (entry != null) {
            _entries.putIfAbsent(entry.title.anilistId!, () => entry);
          }
        }
      }
      error = null;
    } catch (e) {
      _handleError(e);
    }
    _setBusy(false);
  }

  /// Adds or edits your entry for [title]. Dates left null are cleared.
  /// Returns whether AniList saved it.
  Future<bool> saveEntry(
    LibraryTitle title, {
    required String status,
    required int progress,
    required double score,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    if (!isSignedIn) return false;
    try {
      final id = await _mediaId(title);
      if (id == null) throw Exception('this show isn\'t on anilist');
      final saved = await _client.request(
        _saveMutation,
        variables: {
          'mediaId': id,
          'status': status,
          'progress': progress,
          'scoreRaw': (score * 10).round(),
          'startedAt': _fuzzyDate(startedAt),
          'completedAt': _fuzzyDate(completedAt),
        },
        cacheable: false,
      );
      _remember(saved, title);
      error = null;
      return true;
    } catch (e) {
      _handleError(e);
      return false;
    }
  }

  static Map<String, int?> _fuzzyDate(DateTime? date) => {
    'year': date?.year,
    'month': date?.month,
    'day': date?.day,
  };

  static DateTime? _parseDate(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final year = json['year'] as int?;
    if (year == null) return null;
    return DateTime(year, json['month'] as int? ?? 1, json['day'] as int? ?? 1);
  }

  /// Your AniList titles, most recently updated first.
  List<AniListEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _onEpisodeWatched(LibraryTitle title, String episode) {
    if (!isSignedIn) return;
    final number = double.tryParse(episode)?.floor();
    if (number == null || number <= 0) return;
    _saveProgress(title, number).catchError(_handleError);
  }

  /// Deletes your AniList entry for [title], status, progress and score
  /// included. Returns whether it's gone.
  Future<bool> deleteEntry(LibraryTitle title) async {
    try {
      await _delete(title);
      error = null;
      return true;
    } catch (e) {
      _handleError(e);
      return false;
    }
  }

  Future<void> _delete(LibraryTitle title) async {
    final id = await _mediaId(title);
    if (id == null) return;
    var entryId = _entries[id]?.id;
    if (entryId == null) {
      final data = await _client.request(
        _entryQuery,
        variables: {'id': id},
        cacheable: false,
      );
      entryId =
          ((data['Media'] as Map<String, dynamic>?)?['mediaListEntry']
                  as Map<String, dynamic>?)?['id']
              as int?;
    }
    if (entryId != null) {
      await _client.request(
        _deleteMutation,
        variables: {'id': entryId},
        cacheable: false,
      );
    }
    _client.clearCache();
    _entries.remove(id);
    notifyListeners();
  }

  /// Moves your AniList progress forward to [episode], adding the title as
  /// "watching" if it isn't on your list. Never moves progress back, so
  /// rewatching an early episode doesn't undo anything.
  Future<void> _saveProgress(LibraryTitle title, int episode) async {
    final id = await _mediaId(title);
    if (id == null) return;
    final data = await _client.request(
      _entryQuery,
      variables: {'id': id},
      cacheable: false,
    );
    final media = data['Media'] as Map<String, dynamic>?;
    final entry = media?['mediaListEntry'] as Map<String, dynamic>?;
    final progress = entry?['progress'] as int? ?? 0;
    if (episode <= progress) return;
    final total = media?['episodes'] as int?;
    final status = total != null && episode >= total
        ? 'COMPLETED'
        : entry?['status'] == 'REPEATING'
        ? 'REPEATING'
        : 'CURRENT';
    final saved = await _client.request(
      _saveMutation,
      variables: {'mediaId': id, 'progress': episode, 'status': status},
      cacheable: false,
    );
    _remember(saved, title);
  }

  void _remember(Map<String, dynamic> saved, LibraryTitle title) {
    _client.clearCache();
    final raw = saved['SaveMediaListEntry'] as Map<String, dynamic>?;
    final entry = raw == null ? null : _parseEntry(raw, fallback: title);
    if (entry == null) return;
    _entries[entry.title.anilistId!] = entry;
    notifyListeners();
  }

  AniListEntry? _parseEntry(
    Map<String, dynamic> json, {
    LibraryTitle? fallback,
  }) {
    final media = json['media'] as Map<String, dynamic>?;
    final id = media?['id'] as int?;
    if (media == null || id == null) return null;
    final titles = media['title'] as Map<String, dynamic>? ?? const {};
    final title = LibraryTitle(
      title:
          titles['english'] as String? ??
          titles['romaji'] as String? ??
          fallback?.title ??
          '',
      image:
          (media['coverImage'] as Map<String, dynamic>?)?['extraLarge']
              as String? ??
          fallback?.image,
      anilistId: id,
      malId: media['idMal'] as int? ?? fallback?.malId,
    );
    return AniListEntry(
      id: json['id'] as int,
      title: fallback == null ? title : title.mergedWith(fallback),
      status: json['status'] as String,
      progress: json['progress'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      startedAt: _parseDate(json['startedAt']),
      completedAt: _parseDate(json['completedAt']),
    );
  }

  Future<int?> _mediaId(LibraryTitle title) async {
    if (title.anilistId != null) return title.anilistId;
    if (title.malId == null) return null;
    final data = await _client.request(
      r'query ($malId: Int) { Media(idMal: $malId, type: ANIME) { id } }',
      variables: {'malId': title.malId},
    );
    return (data['Media'] as Map<String, dynamic>?)?['id'] as int?;
  }

  void _handleError(Object e) {
    final message = e.toString();
    if (message.contains('Invalid token') ||
        message.contains('Unauthorized') ||
        message.contains('401')) {
      _expire();
      return;
    }
    error = _clean(message);
    debugPrint('anilist: $message');
    notifyListeners();
  }

  /// The sign-in is no longer valid until the user reconnects.
  void _expire() {
    needsReconnect = true;
    _client.accessToken = null;
    _entries.clear();
    notifyListeners();
  }

  void _setBusy(bool value) {
    isBusy = value;
    notifyListeners();
  }

  static String _clean(String message) =>
      message.replaceFirst(RegExp(r'^(Exception|PlatformException)\W*'), '');

  static const _entryFields = '''
    id
    status
    progress
    updatedAt
    score(format: POINT_10_DECIMAL)
    startedAt { year month day }
    completedAt { year month day }
    media {
      id
      idMal
      title { english romaji }
      coverImage { extraLarge }
    }
''';

  static const _viewerQuery = r'''
query {
  Viewer {
    id
    name
    avatar { medium }
  }
}
''';

  static const _listQuery =
      r'''
query ($userId: Int) {
  MediaListCollection(userId: $userId, type: ANIME) {
    lists {
      entries {'''
      '$_entryFields'
      '''
      }
    }
  }
}
''';

  static const _entryQuery = r'''
query ($id: Int) {
  Media(id: $id) {
    episodes
    mediaListEntry { id status progress }
  }
}
''';

  static const _saveMutation =
      r'''
mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int,
    $scoreRaw: Int, $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) {
  SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress,
      scoreRaw: $scoreRaw, startedAt: $startedAt, completedAt: $completedAt) {'''
      '$_entryFields'
      '''
  }
}
''';

  static const _deleteMutation = r'''
mutation ($id: Int) {
  DeleteMediaListEntry(id: $id) { deleted }
}
''';
}
