import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anigen/screens/anilist_list_screen.dart';
import 'package:anigen/screens/settings_screen.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

/// "My List": AniList stats when signed in, favourites, and the account.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _library = LibraryStore.instance;

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _export() async {
    final bytes = utf8.encode(jsonEncode(_library.exportData()));
    final date = DateTime.now().toIso8601String().split('T').first;
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'export library',
        fileName: 'anigen-backup-$date.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (saved != null && mounted) _snack('library exported');
    } catch (e) {
      if (mounted) _snack('couldn\'t export: $e');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'import library',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final file = picked.firstOrNull;
      if (file == null) return;
      final data = jsonDecode(utf8.decode(await file.xFile.readAsBytes()));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('not an anigen backup');
      }
      final result = _library.importData(data);
      if (mounted) {
        _snack(
          'imported ${result.shows} shows and '
          '${result.favourites} favourites',
        );
      }
    } on FormatException catch (e) {
      if (mounted) _snack('couldn\'t import: ${e.message}');
    } catch (e) {
      if (mounted) _snack('couldn\'t import: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 900 ? 24.0 : 16.0;
    final posterWidth = width >= 900 ? 140.0 : 112.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('my list'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_library, AniListAccount.instance]),
        builder: (context, _) {
          final favourites = _library.favourites;
          final signedIn = AniListAccount.instance.isSignedIn;
          return ListView(
            children: [
              if (signedIn)
                ..._stats(context, padding)
              else
                ..._localStats(context, padding),
              if (favourites.isEmpty) ...[
                SectionHeader('favourites', padding: padding),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: Text(
                    'tap favourite on a show to keep it here',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else
                CardRow(
                  title: 'favourites',
                  padding: padding,
                  height: posterWidth * 3 / 2 + 42,
                  itemCount: favourites.length,
                  itemBuilder: (context, i) => PosterCard(
                    title: favourites[i].title,
                    image: favourites[i].image,
                    width: posterWidth,
                    onTap: () => openTitle(context, favourites[i]),
                    onLongPress: () => _library.toggleFavourite(favourites[i]),
                  ),
                ),
              SectionHeader('connect', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: const Column(
                  children: [
                    Card(child: _AniListTile()),
                    Card(child: _MalTile()),
                  ],
                ),
              ),
              SectionHeader('backup', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.upload_file),
                        title: const Text('export library'),
                        subtitle: const Text(
                          'favourites and watch progress, as a file',
                        ),
                        onTap: _export,
                      ),
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('import library'),
                        subtitle: const Text(
                          'merge in a backup, keeping the newer progress',
                        ),
                        onTap: _import,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: bottomInset(context) + 24),
            ],
          );
        },
      ),
    );
  }
}

/// Signed in, My List is your AniList list: counts per status here, the
/// titles themselves on [AniListListScreen].
List<Widget> _stats(BuildContext context, double padding) {
  final theme = Theme.of(context);
  final account = AniListAccount.instance;
  final entries = account.entries;
  // Statuses only come with a sync, which runs at startup.
  if (entries.isEmpty && (account.isBusy || account.error != null)) {
    return [
      SectionHeader('stats', padding: padding),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: Text(
          account.error ?? 'syncing with anilist...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }
  final counts = {
    for (final status in AniListEntry.statuses)
      status: entries.where((e) => e.status == status).length,
  };
  final episodes = entries.fold(0, (sum, e) => sum + e.progress);
  final scored = entries.where((e) => e.score > 0).toList();
  final meanScore = scored.isEmpty
      ? null
      : scored.fold(0.0, (sum, e) => sum + e.score) / scored.length;

  void open([String? status]) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => AniListListScreen(initialStatus: status),
    ),
  );

  return [
    SectionHeader(
      'stats',
      padding: padding,
      trailing: TextButton(onPressed: open, child: const Text('view list')),
    ),
    Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Text(
        [
          '${entries.length} shows',
          '$episodes episodes',
          if (meanScore != null) 'mean score ${meanScore.toStringAsFixed(1)}',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    const SizedBox(height: 10),
    Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 6 : 3;
          const spacing = 8.0;
          final tileWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final MapEntry(key: status, value: count) in counts.entries)
                SizedBox(
                  width: tileWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => open(status),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$count',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: status == 'CURRENT'
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                            Text(
                              AniListEntry.labelFor(status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  ];
}

/// Signed out, stats come from what you've watched on this device.
List<Widget> _localStats(BuildContext context, double padding) {
  final theme = Theme.of(context);
  final library = LibraryStore.instance;
  final stats = library.stats;
  if (stats.shows == 0 && library.favourites.isEmpty) return const [];
  final hours = stats.watched.inMinutes / 60;
  final tiles = [
    ('${stats.shows}', 'shows'),
    ('${stats.episodes}', 'episodes'),
    (hours < 10 ? hours.toStringAsFixed(1) : '${hours.round()}', 'hours'),
    ('${library.favourites.length}', 'favourites'),
  ];
  return [
    SectionHeader('stats', padding: padding),
    Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final columns = constraints.maxWidth >= 600 ? 4 : 2;
          final tileWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final (value, label) in tiles)
                SizedBox(
                  width: tileWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  ];
}

/// Placeholder until MyAnimeList sign-in exists.
class _MalTile extends StatelessWidget {
  const _MalTile();

  @override
  Widget build(BuildContext context) => const ListTile(
    enabled: false,
    leading: Icon(Icons.account_circle_outlined),
    title: Text('myanimelist'),
    subtitle: Text('coming soon'),
  );
}

/// Sign in / out of AniList and see how sync is doing.
class _AniListTile extends StatelessWidget {
  const _AniListTile();

  @override
  Widget build(BuildContext context) {
    final account = AniListAccount.instance;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final theme = Theme.of(context);
        final busy = account.isBusy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null;

        if (account.isSignedIn) {
          final avatar = account.avatar;
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: avatar == null ? null : NetworkImage(avatar),
              child: avatar == null ? const Icon(Icons.person) : null,
            ),
            title: Text(account.userName ?? 'anilist'),
            subtitle: Text(
              account.error ?? 'tracking and stats from your anilist',
              style: account.error == null
                  ? null
                  : TextStyle(color: theme.colorScheme.error),
            ),
            trailing:
                busy ??
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'sync' ? account.sync() : account.signOut(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'sync', child: Text('sync now')),
                    PopupMenuItem(value: 'signout', child: Text('sign out')),
                  ],
                ),
          );
        }

        final subtitle = !account.isConfigured
            ? 'this build has no anilist client id '
                  '(build with --dart-define=ANILIST_CLIENT_ID=...)'
            : account.needsReconnect
            ? 'your anilist sign-in expired, connect again'
            : account.error ?? 'track shows and see your stats';
        return ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(
            account.needsReconnect ? 'reconnect anilist' : 'connect anilist',
          ),
          subtitle: Text(subtitle),
          trailing:
              busy ??
              FilledButton(
                onPressed: account.isConfigured ? account.signIn : null,
                child: Text(account.needsReconnect ? 'reconnect' : 'sign in'),
              ),
        );
      },
    );
  }
}
