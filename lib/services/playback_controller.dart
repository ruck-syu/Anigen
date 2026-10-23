import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/services/library_store.dart';

/// An opening or ending, from aniskip.
class SkipInterval {
  final String type; // 'op' or 'ed'
  final Duration start;
  final Duration end;

  const SkipInterval(this.type, this.start, this.end);

  bool contains(Duration position) => position >= start && position < end;
}

/// Owns the one player in the app, so playback keeps going while the user
/// browses. The player UI (expanded or mini) just renders this state.
class PlaybackController extends ChangeNotifier {
  PlaybackController._();
  static final PlaybackController instance = PlaybackController._();

  Player? _player;
  VideoController? _video;

  Player get player => _player ??= _createPlayer();
  VideoController get video => _video ??= VideoController(player);

  LibraryTitle? title;
  List<Episode> episodes = const [];
  Episode? episode;
  bool isLoading = false;
  String? error;
  List<SkipInterval> skips = const [];
  bool isExpanded = false;
  double rate = 1.0;

  // Bumped on every load so late responses for an old episode are dropped
  int _request = 0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _autoSkipped;

  bool get isActive => title != null;

  int get _index => episodes.indexWhere((e) => e.url == episode?.url);

  Episode? get nextEpisode {
    final i = _index;
    return i != -1 && i + 1 < episodes.length ? episodes[i + 1] : null;
  }

  Episode? get previousEpisode {
    final i = _index;
    return i > 0 ? episodes[i - 1] : null;
  }

  SkipInterval? skipAt(Duration position) =>
      skips.where((s) => s.contains(position)).firstOrNull;

  Player _createPlayer() {
    final player = Player();
    player.stream.position.listen(_onPosition);
    player.stream.playing.listen((playing) {
      if (!playing) _saveProgress();
    });
    player.stream.completed.listen((completed) {
      if (!completed || isLoading) return;
      _saveProgress();
      final next = nextEpisode;
      if (next != null && LibraryStore.instance.autoplay) {
        playEpisode(next);
      }
    });
    player.stream.error.listen((message) {
      // Only surface errors that stop playback from starting at all
      if (!isLoading && player.state.duration == Duration.zero) {
        error = message;
        notifyListeners();
      }
    });
    return player;
  }

  void _onPosition(Duration position) {
    if (isLoading || episode == null) return;

    final now = DateTime.now();
    if (now.difference(_lastSave) > const Duration(seconds: 5)) {
      _lastSave = now;
      _saveProgress();
    }

    final library = LibraryStore.instance;
    final skip = skipAt(position);
    if (skip == null) return;
    // Once per opening or ending, so seeking back into one plays it
    final key = '${episode!.url}|${skip.type}';
    final wanted = skip.type == 'op'
        ? library.autoSkipIntro
        : library.autoSkipOutro;
    if (wanted && _autoSkipped != key) {
      _autoSkipped = key;
      player.seek(skip.end);
    }
  }

  void _saveProgress() {
    final title = this.title;
    final episode = this.episode;
    final state = _player?.state;
    if (title == null || episode == null || state == null || isLoading) return;
    if (state.duration <= Duration.zero) return;
    LibraryStore.instance.updateProgress(
      title,
      episode.number,
      state.position,
      state.duration,
    );
  }

  /// Starts [episode] of [title]. If it is already playing, just shows it.
  Future<void> play({
    required LibraryTitle title,
    required List<Episode> episodes,
    required Episode episode,
    bool expand = true,
  }) async {
    final sameShow = this.title?.animeId == title.animeId;
    if (sameShow && this.episode?.url == episode.url && error == null) {
      this.title = title.mergedWith(this.title!);
      this.episodes = episodes;
      if (expand) this.expand();
      return;
    }

    _saveProgress();
    this.title = sameShow ? title.mergedWith(this.title!) : title;
    this.episodes = episodes;
    if (expand) isExpanded = true;
    await _load(episode);
  }

  Future<void> playEpisode(Episode episode) {
    _saveProgress();
    return _load(episode);
  }

  Future<void> playNext() async {
    final next = nextEpisode;
    if (next != null) await playEpisode(next);
  }

  Future<void> playPrevious() async {
    final previous = previousEpisode;
    if (previous != null) await playEpisode(previous);
  }

  Future<void> retry() async {
    final episode = this.episode;
    if (episode != null) await _load(episode);
  }

  Future<void> _load(Episode episode) async {
    final title = this.title!;
    final request = ++_request;
    this.episode = episode;
    isLoading = true;
    error = null;
    skips = const [];
    notifyListeners();

    try {
      await player.stop();
      final stream = await AnimeProvider().getStreamLink(
        title.animeId!,
        episode.number,
        episodeId: episode.url,
      );
      if (request != _request) return;
      if (stream == null || stream['url'] == null) {
        throw Exception('no stream found for this episode');
      }

      // Resume where the user left off, unless they finished it or turned
      // resuming off
      final saved = LibraryStore.instance.resume
          ? LibraryStore.instance
                .historyFor(title.animeId)
                ?.episodes[episode.number]
          : null;
      final start =
          saved != null && !saved.isWatched && saved.positionMs > 10000
          ? Duration(milliseconds: saved.positionMs)
          : null;

      await player.open(
        Media(
          stream['url']!,
          httpHeaders: {
            if (stream['userAgent'] != null) 'User-Agent': stream['userAgent']!,
            if (stream['referer'] != null) 'Referer': stream['referer']!,
          },
          start: start,
        ),
        play: false,
      );
      if (request != _request) return;
      // hianime streams ship soft subs as a separate WebVTT file
      final subtitle = stream['subtitle'];
      if (subtitle != null) _loadSubtitle(subtitle, stream, request);
      await player.setRate(rate);
      await player.play();

      isLoading = false;
      notifyListeners();
      _loadSkipTimes(
        int.tryParse(stream['malId'] ?? '') ?? title.malId,
        episode.number,
        request,
      );
    } catch (e) {
      if (request != _request) return;
      isLoading = false;
      error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  /// The subtitle host refuses requests without the embed's Referer, and mpv
  /// only sends the stream's headers once the file is loading, so fetch the
  /// WebVTT ourselves and add it after the video has loaded.
  Future<void> _loadSubtitle(
    String url,
    Map<String, String> stream,
    int request,
  ) async {
    SubtitleTrack track;
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              if (stream['userAgent'] != null)
                'User-Agent': stream['userAgent']!,
              if (stream['referer'] != null) 'Referer': stream['referer']!,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('subtitles answered ${response.statusCode}');
      }
      track = SubtitleTrack.data(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        title: 'English',
        language: 'en',
      );
    } catch (e) {
      debugPrint('subtitle download failed, letting mpv try: $e');
      track = SubtitleTrack.uri(url, title: 'English', language: 'en');
    }
    if (request != _request) return;
    // sub-add fails until mpv has the file open. Some streams never report
    // a duration, so take any sign of a loaded file, and try regardless if
    // none comes.
    await _fileLoaded(const Duration(seconds: 20));
    if (request != _request) return;
    try {
      await player.setSubtitleTrack(track);
    } catch (e) {
      debugPrint('could not add subtitles: $e');
    }
  }

  Future<void> _fileLoaded(Duration timeout) {
    final state = player.state;
    bool loaded(Tracks tracks) =>
        tracks.video.any((t) => t.id != 'auto' && t.id != 'no');
    if (state.duration > Duration.zero ||
        state.width != null ||
        loaded(state.tracks)) {
      return Future.value();
    }
    final done = Completer<void>();
    final subscriptions = <StreamSubscription>[];
    late final Timer timer;
    void finish() {
      if (done.isCompleted) return;
      done.complete();
      timer.cancel();
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    }

    timer = Timer(timeout, finish);

    subscriptions
      ..add(
        player.stream.duration.listen((d) {
          if (d > Duration.zero) finish();
        }),
      )
      ..add(
        player.stream.width.listen((w) {
          if (w != null) finish();
        }),
      )
      ..add(
        player.stream.tracks.listen((t) {
          if (loaded(t)) finish();
        }),
      );
    return done.future;
  }

  Future<void> _loadSkipTimes(int? malId, String episode, int request) async {
    final number = int.tryParse(episode);
    if (malId == null || number == null) return;
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.aniskip.com/v2/skip-times/$malId/$number'
              '?types=op&types=ed&episodeLength=0',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (request != _request || response.statusCode != 200) return;

      final results = jsonDecode(response.body)['results'] as List? ?? [];
      skips = [
        for (final r in results)
          SkipInterval(
            r['skipType'] as String,
            Duration(
              milliseconds: ((r['interval']['startTime'] as num) * 1000)
                  .round(),
            ),
            Duration(
              milliseconds: ((r['interval']['endTime'] as num) * 1000).round(),
            ),
          ),
      ];
      notifyListeners();
    } catch (e) {
      // Skip buttons are a nice-to-have
    }
  }

  Future<void> setRate(double value) async {
    rate = value;
    await player.setRate(value);
    notifyListeners();
  }

  void expand() {
    isExpanded = true;
    notifyListeners();
  }

  void minimize() {
    isExpanded = false;
    notifyListeners();
  }

  Future<void> close() async {
    _saveProgress();
    _request++;
    title = null;
    episodes = const [];
    episode = null;
    isLoading = false;
    error = null;
    skips = const [];
    isExpanded = false;
    notifyListeners();
    await _player?.stop();
  }
}
