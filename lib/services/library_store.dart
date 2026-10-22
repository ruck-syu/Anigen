import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A show as the library knows it. [animeId] is the hianime slug (needed to
/// play), [anilistId] the AniList id and [malId] the MyAnimeList id (needed
/// for metadata). Any of them may be missing.
class LibraryTitle {
  final String title;
  final String? image;
  final String? animeId;
  final int? anilistId;
  final int? malId;

  const LibraryTitle({
    required this.title,
    this.image,
    this.animeId,
    this.anilistId,
    this.malId,
  });

  String get key => animeId ?? 'mal:$malId';

  factory LibraryTitle.fromJson(Map<String, dynamic> json) => LibraryTitle(
    title: json['title'] as String? ?? '',
    image: json['image'] as String?,
    animeId: json['animeId'] as String?,
    anilistId: json['anilistId'] as int?,
    malId: json['malId'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    if (image != null) 'image': image,
    if (animeId != null) 'animeId': animeId,
    if (anilistId != null) 'anilistId': anilistId,
    if (malId != null) 'malId': malId,
  };

  /// Keeps whatever this copy is missing from [other].
  LibraryTitle mergedWith(LibraryTitle other) => LibraryTitle(
    title: title.isNotEmpty ? title : other.title,
    image: image ?? other.image,
    animeId: animeId ?? other.animeId,
    anilistId: anilistId ?? other.anilistId,
    malId: malId ?? other.malId,
  );
}

class EpisodeProgress {
  final int positionMs;
  final int durationMs;

  const EpisodeProgress(this.positionMs, this.durationMs);

  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// Close enough to the end (credits) to count as watched.
  bool get isWatched =>
      durationMs > 0 && (durationMs - positionMs < 120000 || fraction > 0.9);
}

/// Watch history for one show: per-episode progress and the episode the
/// user was last on.
class HistoryEntry {
  final LibraryTitle title;
  final String lastEpisode;
  final int updatedAt;
  final Map<String, EpisodeProgress> episodes;

  const HistoryEntry({
    required this.title,
    required this.lastEpisode,
    required this.updatedAt,
    required this.episodes,
  });

  EpisodeProgress? get lastProgress => episodes[lastEpisode];

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    title: LibraryTitle.fromJson(json['title'] as Map<String, dynamic>),
    lastEpisode: json['lastEpisode'] as String,
    updatedAt: json['updatedAt'] as int,
    episodes: {
      for (final e in (json['episodes'] as Map<String, dynamic>).entries)
        e.key: EpisodeProgress(e.value[0] as int, e.value[1] as int),
    },
  );

  Map<String, dynamic> toJson() => {
    'title': title.toJson(),
    'lastEpisode': lastEpisode,
    'updatedAt': updatedAt,
    'episodes': {
      for (final e in episodes.entries)
        e.key: [e.value.positionMs, e.value.durationMs],
    },
  };
}

/// Watch history, favourites and playback settings, persisted locally.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore instance = LibraryStore._();

  static const _historyKey = 'library_history';
  static const _favouritesKey = 'library_my_list';
  // Cached AniList list from when it stood in for the local list.
  static const _oldRemoteListKey = 'library_anilist_list';
  static const _sourcesKey = 'library_sources';
  static const _autoplayKey = 'settings_autoplay';
  static const _autoSkipKey = 'settings_auto_skip_intro';

  SharedPreferences? _prefs;
  final Map<String, HistoryEntry> _history = {};
  final List<LibraryTitle> _favourites = [];
  // malId -> hianime title picked for it
  final Map<int, LibraryTitle> _sources = {};
  bool autoplay = true;
  bool autoSkipIntro = false;

  /// Hook for AniList progress sync, so the library doesn't depend on it.
  void Function(LibraryTitle title, String episode)? onEpisodeWatched;

  Future<void> load() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      final history = prefs.getString(_historyKey);
      if (history != null) {
        for (final e in (jsonDecode(history) as Map<String, dynamic>).entries) {
          _history[e.key] = HistoryEntry.fromJson(e.value);
        }
      }
      for (final item
          in prefs.getStringList(_favouritesKey) ?? const <String>[]) {
        _favourites.add(LibraryTitle.fromJson(jsonDecode(item)));
      }
      prefs.remove(_oldRemoteListKey);
      final sources = prefs.getString(_sourcesKey);
      if (sources != null) {
        for (final e in (jsonDecode(sources) as Map<String, dynamic>).entries) {
          _sources[int.parse(e.key)] = LibraryTitle.fromJson(e.value);
        }
      }
      autoplay = prefs.getBool(_autoplayKey) ?? true;
      autoSkipIntro = prefs.getBool(_autoSkipKey) ?? false;
    } catch (e) {
      // Start with an empty library rather than not at all
    }
    notifyListeners();
  }

  /// Most recently watched first.
  List<HistoryEntry> get continueWatching {
    final entries = _history.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  List<LibraryTitle> get favourites => List.unmodifiable(_favourites);

  HistoryEntry? historyFor(String? animeId) =>
      animeId == null ? null : _history[animeId];

  HistoryEntry? historyForMal(int? malId) {
    if (malId == null) return null;
    final source = _sources[malId];
    if (source?.animeId != null) return _history[source!.animeId];
    for (final entry in _history.values) {
      if (entry.title.malId == malId) return entry;
    }
    return null;
  }

  LibraryTitle? sourceFor(int malId) => _sources[malId];

  void setSource(int malId, LibraryTitle source) {
    _sources[malId] = source;
    _prefs?.setString(
      _sourcesKey,
      jsonEncode({
        for (final e in _sources.entries) '${e.key}': e.value.toJson(),
      }),
    );
    notifyListeners();
  }

  void updateProgress(
    LibraryTitle title,
    String episode,
    Duration position,
    Duration duration,
  ) {
    final animeId = title.animeId;
    if (animeId == null) return;
    final previous = _history[animeId];
    final progress = EpisodeProgress(
      position.inMilliseconds,
      duration.inMilliseconds,
    );
    final wasWatched = previous?.episodes[episode]?.isWatched ?? false;
    _history[animeId] = HistoryEntry(
      title: previous == null ? title : title.mergedWith(previous.title),
      lastEpisode: episode,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      episodes: {...?previous?.episodes, episode: progress},
    );
    _saveHistory();
    notifyListeners();
    if (progress.isWatched && !wasWatched) {
      onEpisodeWatched?.call(_history[animeId]!.title, episode);
    }
  }

  void removeFromHistory(String animeId) {
    if (_history.remove(animeId) != null) {
      _saveHistory();
      notifyListeners();
    }
  }

  void _saveHistory() {
    _prefs?.setString(
      _historyKey,
      jsonEncode({for (final e in _history.entries) e.key: e.value.toJson()}),
    );
  }

  bool isFavourite(LibraryTitle title) => _indexOf(title) != -1;

  int _indexOf(LibraryTitle title) => _favourites.indexWhere(
    (t) =>
        (title.anilistId != null && t.anilistId == title.anilistId) ||
        (title.animeId != null && t.animeId == title.animeId) ||
        (title.malId != null && t.malId == title.malId),
  );

  /// Returns whether the title is a favourite afterwards.
  bool toggleFavourite(LibraryTitle title) {
    final index = _indexOf(title);
    if (index == -1) {
      _favourites.insert(0, title);
    } else {
      _favourites.removeAt(index);
    }
    _prefs?.setStringList(
      _favouritesKey,
      _favourites.map((t) => jsonEncode(t.toJson())).toList(),
    );
    notifyListeners();
    return index == -1;
  }

  void setAutoplay(bool value) {
    autoplay = value;
    _prefs?.setBool(_autoplayKey, value);
    notifyListeners();
  }

  void setAutoSkipIntro(bool value) {
    autoSkipIntro = value;
    _prefs?.setBool(_autoSkipKey, value);
    notifyListeners();
  }
}
