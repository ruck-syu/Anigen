import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anigen/providers/anilist_client.dart';
import 'package:anigen/providers/scraper_config.dart';
import 'package:anigen/providers/scraper_config_store.dart';
import 'package:anigen/services/app_update.dart';
import 'package:anigen/services/episode_alerts.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

const _repoUrl = 'https://github.com/ruck-syu/Anigen';

/// Playback, subtitles, notifications, storage and the app itself.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _library = LibraryStore.instance;
  ScraperConfig? _config;
  bool _isUpdating = false;
  bool _isCheckingApp = false;
  bool _isTogglingAlerts = false;

  /// Bytes in the temporary directory, null until measured or where it
  /// isn't the app's own.
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _measureCache();
    AppUpdate.onInstallFailed = (message) {
      if (!mounted) return;
      _snack('update failed: $message');
    };
  }

  @override
  void dispose() {
    AppUpdate.onInstallFailed = null;
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _checkForAppUpdate() async {
    setState(() => _isCheckingApp = true);
    AppRelease? release;
    String? error;
    try {
      release = await AppUpdate.latest();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _isCheckingApp = false);
    if (release == null || !AppUpdate.isNewer(release)) {
      _snack(
        error != null
            ? 'couldn\'t check for updates: $error'
            : release == null
            ? 'no releases yet'
            : 'you\'re on the latest version',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _UpdateDialog(release: release!),
    );
  }

  Future<void> _loadConfig() async {
    final config = await ScraperConfigStore.get();
    if (mounted) {
      setState(() {
        _config = config;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isUpdating = true;
    });
    final updated = await ScraperConfigStore.refresh();
    await _loadConfig();
    if (!mounted) return;
    setState(() {
      _isUpdating = false;
    });
    _snack(updated ? 'scraper updated' : 'scraper is up to date');
  }

  Future<void> _toggleAlerts(bool on) async {
    setState(() => _isTogglingAlerts = true);
    var granted = true;
    try {
      if (on) {
        granted = await EpisodeAlerts.enable();
      } else {
        await EpisodeAlerts.disable();
      }
    } catch (e) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _isTogglingAlerts = false);
    if (on && !granted) {
      _snack('notifications are blocked, allow them in system settings');
    }
  }

  /// The temporary directory is the app's own on Android and in the macOS
  /// sandbox. On Windows it's shared, so it's left alone.
  static bool get _ownsTempDir => Platform.isAndroid || Platform.isMacOS;

  Future<void> _measureCache() async {
    if (!_ownsTempDir) return;
    var bytes = 0;
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) bytes += await entity.length();
      }
    } catch (_) {
      // Files can vanish mid-walk; whatever was counted will do
    }
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final ok = await _confirm(
      'clear cache?',
      'artwork and anilist data load again as you browse. your list and '
          'history stay.',
      'clear',
    );
    if (!ok) return;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    AniListClient.instance.clearCache();
    if (_ownsTempDir) {
      try {
        final dir = await getTemporaryDirectory();
        await for (final entity in dir.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // In use; it goes next time
          }
        }
      } catch (_) {}
    }
    await _measureCache();
    if (mounted) _snack('cache cleared');
  }

  Future<void> _clearHistory() async {
    final ok = await _confirm(
      'clear watch history?',
      'continue watching and your progress on every episode are removed '
          'from this device. favourites and anilist stay.',
      'clear',
    );
    if (!ok) return;
    _library.clearHistory();
    if (mounted) _snack('watch history cleared');
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _snack('couldn\'t open $url');
  }

  String get _versionLabel => AppUpdate.currentVersion.isNotEmpty
      ? 'v${AppUpdate.currentVersion}'
      : 'local build';

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final width = MediaQuery.sizeOf(context).width;
    // Centred column on big screens; full-width switches read badly there
    final padding = width >= wideWidth
        ? ((width - 720) / 2).clamp(24.0, double.infinity)
        : 16.0;

    List<Widget> section(String title, List<Widget> tiles) => [
      SectionHeader(title, padding: padding),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        ),
      ),
    ];

    Widget toggle({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) => SwitchListTile(
      tileColor: Colors.transparent,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );

    const spinner = SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('settings')),
      body: ListenableBuilder(
        listenable: _library,
        builder: (context, _) => ListView(
          children: [
            ...section('playback', [
              toggle(
                icon: Icons.playlist_play,
                title: 'autoplay next episode',
                value: _library.autoplay,
                onChanged: _library.setAutoplay,
              ),
              toggle(
                icon: Icons.fast_forward,
                title: 'skip intros automatically',
                value: _library.autoSkipIntro,
                onChanged: _library.setAutoSkipIntro,
              ),
              toggle(
                icon: Icons.skip_next,
                title: 'skip outros automatically',
                value: _library.autoSkipOutro,
                onChanged: _library.setAutoSkipOutro,
              ),
              toggle(
                icon: Icons.history,
                title: 'resume where you left off',
                subtitle: _library.resume
                    ? null
                    : 'episodes start from the beginning',
                value: _library.resume,
                onChanged: _library.setResume,
              ),
              _ChoiceTile<int>(
                icon: Icons.forward_10,
                title: 'double-tap to seek',
                value: _library.seekSeconds,
                choices: {
                  for (final s in LibraryStore.seekChoices) s: '$s seconds',
                },
                onChanged: _library.setSeekSeconds,
              ),
            ]),
            ...section('subtitles', [
              _ChoiceTile<String>(
                icon: Icons.format_size,
                title: 'text size',
                value: _library.subtitleSize,
                choices: {
                  for (final s in LibraryStore.subtitleSizes.keys) s: s,
                },
                onChanged: _library.setSubtitleSize,
              ),
              toggle(
                icon: Icons.subtitles_outlined,
                title: 'background box',
                subtitle: _library.subtitleBox ? null : 'outlined text instead',
                value: _library.subtitleBox,
                onChanged: _library.setSubtitleBox,
              ),
            ]),
            ...section('appearance', [
              toggle(
                icon: Icons.animation,
                title: 'opening animation',
                subtitle: 'the logo when anigen starts',
                value: _library.showIntro,
                onChanged: _library.setShowIntro,
              ),
            ]),
            if (EpisodeAlerts.isSupported)
              ...section('notifications', [
                toggle(
                  icon: Icons.notifications_outlined,
                  title: 'new episodes',
                  subtitle: EpisodeAlerts.checksInBackground
                      ? 'for your favourites and what you\'re watching'
                      : 'for your favourites and what you\'re watching, '
                            'while anigen is open',
                  value: _library.episodeAlerts,
                  onChanged: _isTogglingAlerts ? null : _toggleAlerts,
                ),
              ]),
            ...section('source', [
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('scraper'),
                subtitle: Text(
                  config == null
                      ? 'loading...'
                      : '${Uri.parse(config.baseUrl).host} · v${config.configVersion}',
                ),
                trailing: _isUpdating
                    ? spinner
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'check for update',
                        onPressed: _checkForUpdate,
                      ),
              ),
            ]),
            ...section('storage', [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('clear cache'),
                subtitle: Text(
                  _cacheBytes == null
                      ? 'artwork and anilist data'
                      : 'artwork and anilist data · '
                            '${_formatBytes(_cacheBytes!)} on disk',
                ),
                onTap: _clearCache,
              ),
              ListTile(
                leading: const Icon(Icons.history_toggle_off),
                title: const Text('clear watch history'),
                subtitle: const Text('continue watching and episode progress'),
                onTap: _clearHistory,
              ),
            ]),
            ...section('about', [
              ListTile(
                leading: const Icon(Icons.new_releases_outlined),
                title: const Text('version'),
                subtitle: Text(_versionLabel),
                trailing: !AppUpdate.isSupported
                    ? null
                    : _isCheckingApp
                    ? spinner
                    : TextButton(
                        onPressed: _checkForAppUpdate,
                        child: const Text('check for update'),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('changelog'),
                subtitle: const Text('what\'s new in each release'),
                onTap: () => showDialog<void>(
                  context: context,
                  useRootNavigator: true,
                  builder: (context) => const _ChangelogDialog(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('disclaimer'),
                subtitle: const Text('anigen hosts no content'),
                onTap: () => showDialog<void>(
                  context: context,
                  useRootNavigator: true,
                  builder: (context) => const _DisclaimerDialog(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('licences'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Anigen',
                  applicationVersion: _versionLabel,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('report a problem'),
                subtitle: const Text('open an issue on github'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open('$_repoUrl/issues'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('source code'),
                subtitle: const Text('github.com/ruck-syu/Anigen'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open(_repoUrl),
              ),
            ]),
            SizedBox(height: bottomInset(context) + 24),
          ],
        ),
      ),
    );
  }
}

/// A setting with a few fixed values, picked from a menu.
class _ChoiceTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    initialValue: value,
    onSelected: onChanged,
    tooltip: title,
    position: PopupMenuPosition.under,
    itemBuilder: (context) => [
      for (final MapEntry(key: choice, value: label) in choices.entries)
        CheckedPopupMenuItem(
          value: choice,
          checked: choice == value,
          child: Text(label),
        ),
    ],
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            choices[value] ?? '$value',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}

/// Release notes from GitHub, newest first.
class _ChangelogDialog extends StatefulWidget {
  const _ChangelogDialog();

  @override
  State<_ChangelogDialog> createState() => _ChangelogDialogState();
}

class _ChangelogDialogState extends State<_ChangelogDialog> {
  late final Future<List<({String name, String date, String notes})>>
  _releases = _load();

  static Future<List<({String name, String date, String notes})>>
  _load() async {
    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/ruck-syu/Anigen/releases?per_page=10',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('github returned ${response.statusCode}');
    }
    return [
      for (final raw in jsonDecode(response.body) as List)
        if (raw is Map<String, dynamic> && raw['draft'] != true)
          (
            name: raw['name'] as String? ?? raw['tag_name'] as String? ?? '',
            date: (raw['published_at'] as String? ?? '').split('T').first,
            notes: (raw['body'] as String? ?? '').trim(),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: const Text('changelog'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: FutureBuilder(
          future: _releases,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'couldn\'t load the changelog: '
                '${snapshot.error.toString().replaceFirst('Exception: ', '')}',
              );
            }
            final releases = snapshot.data;
            if (releases == null) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (releases.isEmpty) return const Text('no releases yet');
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in releases) ...[
                    Text(r.name, style: theme.textTheme.titleSmall),
                    if (r.date.isNotEmpty) Text(r.date, style: muted),
                    const SizedBox(height: 6),
                    Text(
                      r.notes.isEmpty ? 'no notes' : r.notes,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('close'),
        ),
      ],
    );
  }
}

/// The README's disclaimer.
class _DisclaimerDialog extends StatelessWidget {
  const _DisclaimerDialog();

  static const _points = [
    'anigen does not host any content. no video files, subtitles or other '
        'media are hosted, stored, uploaded, cached or distributed by anigen '
        'or its developers.',
    'like a web browser or a search engine, anigen only finds and plays '
        'links that third-party websites already make publicly available. '
        'streams load directly from those sites to your device, and anigen '
        'can\'t verify whether they are licensed.',
    'all anime, artwork, titles, logos and trademarks belong to their '
        'respective copyright owners. metadata and artwork come from anilist.',
    'anigen is an independent, non-commercial, open-source project, not '
        'affiliated with any studio, publisher, streaming service, anilist '
        'or the sites it links to.',
    'you are responsible for how you use anigen and for following the '
        'copyright laws where you live. if accessing such content isn\'t '
        'legal in your country, don\'t use this app.',
    'anigen hosts no files, so takedown notices belong with the websites '
        'and hosts that hold the content.',
    'if you enjoy a show, please support the creators: watch it on an '
        'official, licensed service.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('disclaimer'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final point in _points) ...[
                Text(point, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('close'),
        ),
      ],
    );
  }
}

/// Shows what's new, then downloads and installs the release.
class _UpdateDialog extends StatefulWidget {
  final AppRelease release;

  const _UpdateDialog({required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;
  bool _needsPermission = false;

  bool get _downloading => _progress != null;

  Future<void> _update() async {
    if (!await AppUpdate.canInstall()) {
      // Android wants the "install unknown apps" switch on first
      setState(() => _needsPermission = true);
      await AppUpdate.openInstallSettings();
      return;
    }
    setState(() {
      _needsPermission = false;
      _error = null;
      _progress = 0;
    });
    try {
      final apk = await AppUpdate.download(
        widget.release,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      await AppUpdate.install(apk);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = widget.release;
    final sizeMb = release.apkSize / (1024 * 1024);
    return AlertDialog(
      title: Text('v${release.version} is out'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppUpdate.currentVersion.isNotEmpty
                    ? 'you have v${AppUpdate.currentVersion}'
                    : 'you have a local build',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(release.notes, style: theme.textTheme.bodyMedium),
              ],
              if (_needsPermission) ...[
                const SizedBox(height: 12),
                const Text(
                  'allow anigen to install apps, then come back and tap '
                  'update again',
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  _progress! >= 1
                      ? 'installing...'
                      : 'downloading ${(_progress! * 100).round()}%',
                  style: theme.textTheme.labelSmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('later'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _update,
          child: Text(
            sizeMb > 0 ? 'update · ${sizeMb.toStringAsFixed(0)} MB' : 'update',
          ),
        ),
      ],
    );
  }
}
