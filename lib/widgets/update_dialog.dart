import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anigen/services/app_update.dart';

/// Tells you, once the app has settled, when a newer release is out.
///
/// Closing the notice skips that version; letting it time out shows it again
/// next launch.
class UpdateNotice {
  UpdateNotice._();

  static const _skippedKey = 'update_skipped_version';
  static bool _checked = false;

  /// Checks GitHub once per launch and shows a snack bar from [context]'s
  /// messenger if there's something newer.
  static Future<void> check(BuildContext context) async {
    if (_checked || !AppUpdate.canCheck) return;
    _checked = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    AppRelease? release;
    try {
      release = await AppUpdate.latest();
    } catch (_) {
      // Offline or rate limited; the next launch tries again
      return;
    }
    if (release == null || !AppUpdate.isNewer(release)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_skippedKey) == release.version) return;
    if (!navigator.mounted) return;

    final found = release;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('anigen v${found.version} is out'),
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
        action: SnackBarAction(
          label: AppUpdate.isSupported ? 'update' : 'view release',
          onPressed: () => AppUpdate.isSupported
              ? showDialog<void>(
                  context: navigator.context,
                  builder: (context) => UpdateDialog(release: found),
                )
              : openReleasePage(found),
        ),
      ),
    );
    unawaited(
      controller.closed.then((reason) {
        if (reason == SnackBarClosedReason.dismiss) {
          prefs.setString(_skippedKey, found.version);
        }
      }),
    );
  }
}

Future<void> openReleasePage(AppRelease release) =>
    launchUrl(Uri.parse(release.pageUrl), mode: LaunchMode.externalApplication);

/// Shows what's new. On Android it then downloads and installs the release;
/// elsewhere it opens the release page.
class UpdateDialog extends StatefulWidget {
  final AppRelease release;

  const UpdateDialog({super.key, required this.release});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  String? _error;
  bool _needsPermission = false;

  bool get _downloading => _progress != null;

  bool get _installs => widget.release.apkUrl != null;

  Future<void> _update() async {
    if (!_installs) {
      await openReleasePage(widget.release);
      if (mounted) Navigator.of(context).pop();
      return;
    }
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
        if (_installs)
          TextButton(
            onPressed: _downloading ? null : () => openReleasePage(release),
            child: const Text('release page'),
          ),
        FilledButton(
          onPressed: _downloading ? null : _update,
          child: Text(
            !_installs
                ? 'view release'
                : sizeMb > 0
                ? 'update · ${sizeMb.toStringAsFixed(0)} MB'
                : 'update',
          ),
        ),
      ],
    );
  }
}
