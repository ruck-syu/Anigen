import 'package:flutter/material.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/widgets/title_cards.dart';

/// Your whole AniList list, one tab per status.
class AniListListScreen extends StatelessWidget {
  final String? initialStatus;

  const AniListListScreen({super.key, this.initialStatus});

  @override
  Widget build(BuildContext context) {
    const statuses = AniListEntry.statuses;
    return ListenableBuilder(
      listenable: AniListAccount.instance,
      builder: (context, _) {
        final entries = AniListAccount.instance.entries;
        final byStatus = {
          for (final status in statuses)
            status: [
              for (final e in entries)
                if (e.status == status) e,
            ],
        };
        return DefaultTabController(
          length: statuses.length,
          initialIndex: initialStatus == null
              ? 0
              : statuses.indexOf(initialStatus!).clamp(0, statuses.length - 1),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('anilist list'),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final status in statuses)
                    Tab(
                      text:
                          '${AniListEntry.labelFor(status)} '
                          '${byStatus[status]!.length}',
                    ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final status in statuses)
                  _EntryGrid(entries: byStatus[status]!),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntryGrid extends StatelessWidget {
  final List<AniListEntry> entries;

  const _EntryGrid({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'nothing here yet',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 900 ? 24.0 : 16.0;
    const spacing = 10.0;
    final columns =
        ((width - 2 * padding + spacing) /
                ((width >= 900 ? 150 : 112) + spacing))
            .floor()
            .clamp(2, 12);
    final itemWidth = (width - 2 * padding - spacing * (columns - 1)) / columns;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        padding,
        16,
        padding,
        bottomInset(context) + 24,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        // Poster, two lines of title and the progress line.
        mainAxisExtent: itemWidth * 3 / 2 + 62,
        crossAxisSpacing: spacing,
        mainAxisSpacing: 14,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosterCard(
              title: entry.title.title,
              image: entry.title.image,
              width: itemWidth,
              onTap: () => openTitle(context, entry.title),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (entry.progress > 0) '${entry.progress} eps',
                if (entry.score > 0) '★ ${_score(entry.score)}',
              ].join(' · '),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

String _score(double score) =>
    score == score.roundToDouble() ? '${score.round()}' : '$score';
