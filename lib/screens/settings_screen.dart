import 'package:flutter/material.dart';
import 'package:anigen/providers/scraper_config.dart';
import 'package:anigen/providers/scraper_config_store.dart';
import 'package:anigen/services/app_update.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

/// Playback and source settings.
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

  @override
  void initState() {
    super.initState();
    _loadConfig();
    AppUpdate.onInstallFailed = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('update failed: $message')));
    };
  }

  @override
  void dispose() {
    AppUpdate.onInstallFailed = null;
    super.dispose();
  }

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
    if (release == null || release.build <= AppUpdate.currentBuild) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error != null
                ? 'couldn\'t check for updates: $error'
                : release == null
                ? 'no releases yet'
                : 'you\'re on the latest build',
          ),
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated ? 'scraper updated' : 'scraper is up to date'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final width = MediaQuery.sizeOf(context).width;
    // Centred column on big screens; full-width switches read badly there
    final padding = width >= wideWidth
        ? ((width - 720) / 2).clamp(24.0, double.infinity)
        : 16.0;

    return Scaffold(
      appBar: AppBar(title: const Text('settings')),
      body: ListenableBuilder(
        listenable: _library,
        builder: (context, _) => ListView(
          children: [
            SectionHeader('playback', padding: padding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      tileColor: Colors.transparent,
                      secondary: const Icon(Icons.playlist_play),
                      title: const Text('autoplay next episode'),
                      value: _library.autoplay,
                      onChanged: _library.setAutoplay,
                    ),
                    SwitchListTile(
                      tileColor: Colors.transparent,
                      secondary: const Icon(Icons.fast_forward),
                      title: const Text('skip intros automatically'),
                      value: _library.autoSkipIntro,
                      onChanged: _library.setAutoSkipIntro,
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader('source', padding: padding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('scraper'),
                  subtitle: Text(
                    config == null
                        ? 'loading...'
                        : 'ani-cli ${config.aniCliVersion} · config v${config.configVersion}\n'
                              '${Uri.parse(config.baseUrl).host}',
                  ),
                  isThreeLine: true,
                  trailing: _isUpdating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'check for update',
                          onPressed: _checkForUpdate,
                        ),
                ),
              ),
            ),
            if (AppUpdate.isSupported) ...[
              SectionHeader('app', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.new_releases_outlined),
                    title: const Text('app version'),
                    subtitle: Text(
                      AppUpdate.currentBuild > 0
                          ? 'build ${AppUpdate.currentBuild}'
                          : 'local build',
                    ),
                    trailing: _isCheckingApp
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _checkForAppUpdate,
                            child: const Text('check for update'),
                          ),
                  ),
                ),
              ),
            ],
            SizedBox(height: bottomInset(context) + 24),
          ],
        ),
      ),
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
      title: Text('build ${release.build} is out'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppUpdate.currentBuild > 0
                    ? 'you have build ${AppUpdate.currentBuild}'
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
