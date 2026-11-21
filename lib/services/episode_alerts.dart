import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:anigen/providers/anilist_client.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/services/library_store.dart';

/// Notifies when a new episode of a show you follow airs: your favourites,
/// what you're watching on AniList, and what you've been watching here.
///
/// AniList's airing schedule is checked while the app is open and, on
/// Android, about every hour in the background. Each check covers the time
/// since the last one, so an episode is announced once.
class EpisodeAlerts {
  EpisodeAlerts._();

  // AniList ids to watch, kept for the background check, which can't reach
  // the library or the AniList sign-in.
  static const _idsKey = 'alerts_media_ids';
  // Unix seconds the last check ran up to
  static const _lastKey = 'alerts_last_check';
  static const _task = 'episode-alerts';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initFuture;
  static bool _checking = false;
  static Timer? _startupTimer;
  static Timer? _timer;

  static bool get isSupported =>
      Platform.isAndroid || Platform.isMacOS || Platform.isWindows;

  /// Background checks need Android's WorkManager.
  static bool get checksInBackground => Platform.isAndroid;

  static Future<void> _initialise() =>
      _initFuture ??= _initialiseNotifications();

  static Future<void> _initialiseNotifications() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'Anigen',
            appUserModelId: 'Anigen.Anigen',
            guid: '6f0f4f7c-6a0e-4a43-9d7e-5b3c1b7a2e61',
          ),
        ),
      );
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  /// Called at startup: resumes checking if alerts are on.
  static Future<void> start() async {
    if (!isSupported || !LibraryStore.instance.episodeAlerts) return;
    try {
      await _initialise();
      if (checksInBackground) {
        await Workmanager().initialize(episodeAlertsDispatcher);
      }
      _schedule();
    } catch (e) {
      debugPrint('episode alerts failed to start: $e');
    }
  }

  /// Turns alerts on, asking for permission first. Returns whether they're
  /// on afterwards.
  static Future<bool> enable() async {
    if (!isSupported) return false;
    await _initialise();
    final granted = Platform.isAndroid
        ? await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission()
        : Platform.isMacOS
        ? await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true)
        : true;
    if (granted == false) return false;

    // Start from now, rather than announcing everything that already aired
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastKey, _now() - 1);
    await _saveIds(prefs);
    await LibraryStore.instance.setEpisodeAlerts(true);
    if (checksInBackground) {
      await Workmanager().initialize(episodeAlertsDispatcher);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(hours: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
    _schedule();
    return true;
  }

  static Future<void> disable() async {
    final saving = LibraryStore.instance.setEpisodeAlerts(false);
    _startupTimer?.cancel();
    _startupTimer = null;
    _timer?.cancel();
    _timer = null;
    await saving;
    if (checksInBackground) {
      try {
        await Workmanager().cancelByUniqueName(_task);
      } catch (e) {
        debugPrint('could not cancel episode alerts: $e');
      }
    }
  }

  /// Checks shortly after launch, then every half
  /// hour while the app is open.
  static void _schedule() {
    if (!LibraryStore.instance.episodeAlerts) return;
    _startupTimer?.cancel();
    _timer?.cancel();
    _startupTimer = Timer(const Duration(seconds: 30), _foregroundCheck);
    _timer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _foregroundCheck(),
    );
  }

  static Future<void> _foregroundCheck() async {
    try {
      await _check(foreground: true);
    } catch (e) {
      debugPrint('episode alert check failed: $e');
    }
  }

  /// The AniList ids of the shows you follow.
  static Future<void> _saveIds(SharedPreferences prefs) async {
    final library = LibraryStore.instance;
    final account = AniListAccount.instance;
    final ids = <int>{
      if (!account.hasLoaded || (account.isSignedIn && !account.hasSynced))
        for (final id in prefs.getStringList(_idsKey) ?? const <String>[])
          ?int.tryParse(id),
      for (final t in library.favourites)
        if (t.anilistId != null) t.anilistId!,
      for (final e in account.entries)
        if (e.status == 'CURRENT' && e.title.anilistId != null)
          e.title.anilistId!,
      for (final h in library.continueWatching.take(30))
        if (h.title.anilistId != null) h.title.anilistId!,
    };
    await prefs.setStringList(_idsKey, [for (final id in ids) '$id']);
  }

  /// Announces episodes that aired since the last check.
  static Future<void> _check({bool foreground = false}) async {
    if (_checking || (foreground && !LibraryStore.instance.episodeAlerts)) {
      return;
    }
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Another isolate may have checked or disabled alerts.
      await prefs.reload();
      if (prefs.getBool(LibraryStore.episodeAlertsKey) != true) return;
      if (foreground) await _saveIds(prefs);
      await _notifyAired(prefs, foreground: foreground);
    } finally {
      _checking = false;
    }
  }

  static Future<void> _notifyAired(
    SharedPreferences prefs, {
    required bool foreground,
  }) async {
    final ids = [
      for (final id in prefs.getStringList(_idsKey) ?? const <String>[])
        ?int.tryParse(id),
    ];
    final now = _now();
    final from = prefs.getInt(_lastKey);
    if (ids.isEmpty || from == null) {
      if (from == null || from < now - 1) await prefs.setInt(_lastKey, now - 1);
      return;
    }
    if (from >= now - 1) return;

    var lastAired = from;
    for (var page = 1; ; page++) {
      final data = await AniListClient.instance.request(
        _airedQuery,
        variables: {'ids': ids, 'from': from, 'to': now, 'page': page},
        cacheable: false,
      );
      await prefs.reload();
      if (prefs.getBool(LibraryStore.episodeAlertsKey) != true) return;

      final results = data['Page'] as Map<String, dynamic>;
      final aired = results['airingSchedules'] as List;
      final checkedThrough = prefs.getInt(_lastKey) ?? from;
      for (final raw in aired) {
        if (foreground && !LibraryStore.instance.episodeAlerts) return;
        final item = raw as Map<String, dynamic>;
        final airingAt = item['airingAt'] as int;
        if (airingAt <= checkedThrough) continue;
        await _showEpisode(item);
        if (airingAt > lastAired) lastAired = airingAt;
      }
      if (results['pageInfo']['hasNextPage'] != true) break;
    }

    // The upper bound is exclusive, so leave the current second for next time.
    final through = lastAired == from ? now - 1 : lastAired;
    await prefs.reload();
    if (prefs.getBool(LibraryStore.episodeAlertsKey) == true &&
        through > (prefs.getInt(_lastKey) ?? from)) {
      await prefs.setInt(_lastKey, through);
    }
  }

  static Future<void> _showEpisode(Map<String, dynamic> item) async {
    final media = item['media'] as Map<String, dynamic>;
    final title = media['title'] as Map<String, dynamic>;
    final name =
        title['english'] ?? title['userPreferred'] ?? title['romaji'] ?? '';
    final episode = item['episode'] as int;
    await _initialise();
    await _plugin.show(
      id: ((media['id'] as int) * 1000 + episode) & 0x7fffffff,
      title: '$name',
      body: 'episode $episode is out',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'new_episodes',
          'New episodes',
          channelDescription: 'When a show you follow gets a new episode',
        ),
        macOS: DarwinNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  /// Runs in WorkManager's background isolate.
  static Future<void> runInBackground() => _check();

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static const _airedQuery = r'''
query ($ids: [Int], $from: Int, $to: Int, $page: Int) {
  Page(page: $page, perPage: 50) {
    pageInfo { hasNextPage }
    airingSchedules(mediaId_in: $ids, airingAt_greater: $from,
        airingAt_lesser: $to, sort: [TIME, ID]) {
      airingAt
      episode
      media { id title { english romaji userPreferred } }
    }
  }
}''';
}

/// WorkManager's entry point for the background check.
@pragma('vm:entry-point')
void episodeAlertsDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await EpisodeAlerts.runInBackground();
    } catch (e) {
      debugPrint('background episode alert check failed: $e');
    }
    return true;
  });
}
