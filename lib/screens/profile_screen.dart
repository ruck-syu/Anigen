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
              if (signedIn) ..._stats(context, padding),
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
              SectionHeader('anilist', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: const Card(child: _AniListTile()),
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
