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
  static const _autoSkipOutroKey = 'settings_auto_skip_outro';
  static const _resumeKey = 'settings_resume';
  static const _seekKey = 'settings_seek_seconds';
  static const _subtitleSizeKey = 'settings_subtitle_size';
  static const _subtitleBoxKey = 'settings_subtitle_box';
  static const _introKey = 'settings_intro';
  static const _alertsKey = 'settings_episode_alerts';

  /// Double-tap seek lengths offered in settings.
  static const seekChoices = [5, 10, 15, 30];

  /// Subtitle sizes offered in settings, in media_kit's units (32 is its
  /// default).
  static const subtitleSizes = {
    'small': 24.0,
    'medium': 32.0,
    'large': 40.0,
    'huge': 48.0,
  };

  SharedPreferences? _prefs;
  final Map<String, HistoryEntry> _history = {};
  final List<LibraryTitle> _favourites = [];
  // malId -> hianime title picked for it
  final Map<int, LibraryTitle> _sources = {};
  bool autoplay = true;
  bool autoSkipIntro = false;
  bool autoSkipOutro = false;

  /// Start an episode where you left it, rather than from the beginning.
  bool resume = true;
  int seekSeconds = 10;
  String subtitleSize = 'medium';
  bool subtitleBox = true;
  bool showIntro = true;
  bool episodeAlerts = false;

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
      autoSkipOutro = prefs.getBool(_autoSkipOutroKey) ?? false;
      resume = prefs.getBool(_resumeKey) ?? true;
      seekSeconds = prefs.getInt(_seekKey) ?? 10;
      final size = prefs.getString(_subtitleSizeKey);
      if (subtitleSizes.containsKey(size)) subtitleSize = size!;
      subtitleBox = prefs.getBool(_subtitleBoxKey) ?? true;
      showIntro = prefs.getBool(_introKey) ?? true;
      episodeAlerts = prefs.getBool(_alertsKey) ?? false;
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
    _saveSources();
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

  /// Forgets every show's progress. Favourites stay.
  void clearHistory() {
    _history.clear();
    _saveHistory();
    notifyListeners();
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
    _saveFavourites();
    notifyListeners();
    return index == -1;
  }

  void _saveFavourites() {
    _prefs?.setStringList(
      _favouritesKey,
      _favourites.map((t) => jsonEncode(t.toJson())).toList(),
    );
  }

  void _saveSources() {
    _prefs?.setString(
      _sourcesKey,
      jsonEncode({
        for (final e in _sources.entries) '${e.key}': e.value.toJson(),
      }),
    );
  }

  /// Favourites, watch history and picked sources, for a backup file.
  Map<String, dynamic> exportData() => {
    'app': 'anigen',
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'favourites': [for (final t in _favourites) t.toJson()],
    'history': {for (final e in _history.entries) e.key: e.value.toJson()},
    'sources': {
      for (final e in _sources.entries) '${e.key}': e.value.toJson(),
    },
  };

  /// Merges a backup from [exportData] into the library: the newer progress
  /// wins for each show, and favourites and sources are added to. Returns
  /// how many shows and favourites came in. Throws on a file that isn't one.
  ({int shows, int favourites}) importData(Map<String, dynamic> data) {
    if (data['app'] != 'anigen' || data['version'] is! int) {
      throw const FormatException('not an anigen backup');
    }
    var shows = 0;
    var favourites = 0;
    final history = data['history'] as Map<String, dynamic>? ?? const {};
    for (final e in history.entries) {
      final entry = HistoryEntry.fromJson(e.value as Map<String, dynamic>);
      final current = _history[e.key];
      if (current == null || entry.updatedAt > current.updatedAt) {
        _history[e.key] = entry;
        shows++;
      }
    }
    for (final raw in data['favourites'] as List? ?? const []) {
      final title = LibraryTitle.fromJson(raw as Map<String, dynamic>);
      if (_indexOf(title) == -1) {
        _favourites.add(title);
        favourites++;
      }
    }
    final sources = data['sources'] as Map<String, dynamic>? ?? const {};
    for (final e in sources.entries) {
      final id = int.tryParse(e.key);
      if (id == null) continue;
      _sources.putIfAbsent(
        id,
        () => LibraryTitle.fromJson(e.value as Map<String, dynamic>),
      );
    }
    _saveHistory();
    _saveFavourites();
    _saveSources();
    notifyListeners();
    return (shows: shows, favourites: favourites);
  }

  /// Totals for the profile when there's no AniList account to ask.
  ({int shows, int episodes, Duration watched}) get stats {
    var episodes = 0;
    var watchedMs = 0;
    for (final entry in _history.values) {
      for (final progress in entry.episodes.values) {
        if (progress.isWatched) episodes++;
        watchedMs += progress.positionMs;
      }
    }
    return (
      shows: _history.length,
      episodes: episodes,
      watched: Duration(milliseconds: watchedMs),
    );
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

  void setAutoSkipOutro(bool value) {
    autoSkipOutro = value;
    _prefs?.setBool(_autoSkipOutroKey, value);
    notifyListeners();
  }

  void setResume(bool value) {
    resume = value;
    _prefs?.setBool(_resumeKey, value);
    notifyListeners();
  }

  void setSeekSeconds(int value) {
    seekSeconds = value;
    _prefs?.setInt(_seekKey, value);
    notifyListeners();
  }

  void setSubtitleSize(String value) {
    subtitleSize = value;
    _prefs?.setString(_subtitleSizeKey, value);
    notifyListeners();
  }

  void setSubtitleBox(bool value) {
    subtitleBox = value;
    _prefs?.setBool(_subtitleBoxKey, value);
    notifyListeners();
  }

  void setShowIntro(bool value) {
    showIntro = value;
    _prefs?.setBool(_introKey, value);
    notifyListeners();
  }

  void setEpisodeAlerts(bool value) {
    episodeAlerts = value;
    _prefs?.setBool(_alertsKey, value);
    notifyListeners();
  }
}
