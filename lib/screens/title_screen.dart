import 'package:flutter/material.dart';
import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anilist_provider.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/services/playback_controller.dart';
import 'package:anigen/widgets/title_cards.dart';

/// Details page for a show. Works from an AniList or MyAnimeList id
/// (metadata from AniList, video source found by searching hianime) or from
/// a hianime id.
class TitleScreen extends StatefulWidget {
  final LibraryTitle title;

  /// Start playing (or resume) as soon as the episodes are known.
  final bool autoplay;

  const TitleScreen({super.key, required this.title, this.autoplay = false});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  final _library = LibraryStore.instance;
  final _playback = PlaybackController.instance;
  final _anilist = AniListProvider();

  AniListMedia? _info;
  List<AniListMedia> _recommendations = [];
  List<AniListMedia> _seasons = [];
  LibraryTitle? _source;
  List<Episode>? _episodes;
  String? _sourceError;
  bool _descriptionExpanded = false;
  _Tab _tab = _Tab.episodes;

  int? get _anilistId => widget.title.anilistId ?? _info?.id;

  int? get _malId => widget.title.malId ?? _info?.malId;

  LibraryTitle get _title => LibraryTitle(
    title: _info?.title ?? widget.title.title,
    image: _info?.image ?? widget.title.image ?? _source?.image,
    animeId: _source?.animeId ?? widget.title.animeId,
    anilistId: _anilistId,
    malId: _malId,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final anilistId = widget.title.anilistId;
    final malId = widget.title.malId;
    if (anilistId != null || malId != null) {
      try {
        final info = await _anilist.getMedia(id: anilistId, malId: malId);
        if (mounted && info != null) setState(() => _info = info);
      } catch (e) {
        // The page still works from the title we were given
      }
    }
    if (_anilistId != null) _loadSeasons(_anilistId!);
    await _resolveSource();
    if (anilistId != null || malId != null) {
      _loadRecommendations(anilistId: anilistId, malId: malId);
    }
  }

  Future<void> _loadSeasons(int id) async {
    try {
      final seasons = await _anilist.getSeasons(id);
      if (mounted) setState(() => _seasons = seasons);
    } catch (e) {
      // Optional section
    }
  }

  Future<void> _loadRecommendations({int? anilistId, int? malId}) async {
    try {
      final recommendations = await _anilist.getRecommendations(
        id: anilistId,
        malId: malId,
      );
      if (mounted) {
        setState(() => _recommendations = recommendations.take(18).toList());
      }
    } catch (e) {
      // Optional section
    }
  }

  Future<void> _resolveSource() async {
    setState(() {
      _sourceError = null;
      _episodes = null;
    });
    try {
      var source = widget.title.animeId != null
          ? widget.title
          : _malId != null
          ? _library.sourceFor(_malId!)
          : null;
      source ??= await _findSource();
      if (source == null) {
        throw Exception(
          "couldn't find a stream for this show, try changing the source",
        );
      }
      final episodes = await AnimeProvider().getEpisodes(source.animeId!);
      if (!mounted) return;
      setState(() {
        _source = source;
        _episodes = episodes;
      });
      if (widget.autoplay && episodes.isNotEmpty) _play();
    } catch (e) {
      if (mounted) {
        setState(
          () => _sourceError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  /// Searches hianime for the show, preferring an exact title match.
  Future<LibraryTitle?> _findSource() async {
    final names = {
      if (_info?.title != null) _info!.title,
      if (_info?.titleRomaji != null) _info!.titleRomaji!,
      widget.title.title,
    };
    for (final name in names) {
      final results = await AnimeProvider().search(name);
      if (results.isEmpty) continue;
      final exact = results.where(
        (r) => names.any((n) => n.toLowerCase() == r.title.toLowerCase()),
      );
      final match = exact.firstOrNull ?? results.first;
      return LibraryTitle(
        title: match.title,
        image: match.thumbnail,
        animeId: match.url,
      );
    }
    return null;
  }

  Future<void> _changeSource() async {
    final picked = await showModalBottomSheet<Anime>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => _SourcePicker(initialQuery: _title.title),
    );
    if (picked == null || !mounted) return;
    final source = LibraryTitle(
      title: picked.title,
      image: picked.thumbnail,
      animeId: picked.url,
    );
    if (_malId != null) _library.setSource(_malId!, source);
    setState(() {
      _source = source;
      _episodes = null;
      _sourceError = null;
    });
    try {
      final episodes = await AnimeProvider().getEpisodes(source.animeId!);
      if (mounted) setState(() => _episodes = episodes);
    } catch (e) {
      if (mounted) setState(() => _sourceError = e.toString());
    }
  }

  /// The episode to resume, or the first one.
  Episode? get _resumeEpisode {
    final episodes = _episodes;
    if (episodes == null || episodes.isEmpty) return null;
    final history = _library.historyFor(_source?.animeId);
    if (history == null) return episodes.first;
    final last = episodes.indexWhere((e) => e.number == history.lastEpisode);
    if (last == -1) return episodes.first;
    // Finished the last one: move on to the next
    if ((history.lastProgress?.isWatched ?? false) &&
        last + 1 < episodes.length) {
      return episodes[last + 1];
    }
    return episodes[last];
  }

  void _play([Episode? episode]) {
    final target = episode ?? _resumeEpisode;
    if (target == null || _episodes == null) return;
    _playback.play(title: _title, episodes: _episodes!, episode: target);
  }

  void _toggleFavourite() {
    final added = _library.toggleFavourite(_title);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'added to favourites' : 'removed from favourites',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// AniList status, progress, score and dates, for signed-in users.
  void _openTracking() {
    final account = AniListAccount.instance;
    if (!account.isSignedIn || _anilistId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            account.isSignedIn
                ? 'this show isn\'t on anilist'
                : 'sign in to anilist in my list to track shows',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TrackingSheet(
        title: _title,
        entry: account.entryFor(_anilistId),
        totalEpisodes: _info?.episodes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= wideWidth;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_library, _playback]),
        builder: (context, _) => CustomScrollView(
          slivers: [
            if (wide)
              SliverToBoxAdapter(child: _buildWideHeader())
            else ...[
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildDetails(wide: false),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16),
                    child: _buildTabs(),
                  ),
                ),
              ),
            ),
            ...switch (_tab) {
              _Tab.episodes => _buildEpisodes(width, wide),
              _Tab.seasons => [_buildSeasons()],
              _Tab.moreLikeThis => [_buildMoreLikeThis(width)],
            },
            SliverToBoxAdapter(
              child: SizedBox(height: bottomInset(context) + 24),
            ),
          ],
        ),
      ),
    );
  }

  /// How wide the page's content gets on big screens.
  static const _maxWidth = 1100.0;

  /// Blurred, zoomed poster as the backdrop, fading into the page.
  List<Widget> _backdrop() => [
    SoftBackdrop(_title.image, decodeWidth: 24, opacity: 0.55),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
    ),
  ];

  Widget _poster(double height) => Container(
    height: height,
    width: height * 2 / 3,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: NetImage(_title.image),
  );

  Widget _buildHeader() {
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    const posterHeight = 240.0;
    return SizedBox(
      height: topPadding + posterHeight + 24,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._backdrop(),
          Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: Center(child: _poster(posterHeight)),
          ),
        ],
      ),
    );
  }

  /// Poster beside the details, so a big screen doesn't open on a lone
  /// centred poster with everything else below the fold.
  Widget _buildWideHeader() {
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(fit: StackFit.expand, children: _backdrop()),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, topPadding + 8, 32, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _poster(360),
                  const SizedBox(width: 32),
                  Expanded(child: _buildDetails(wide: true)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails({required bool wide}) {
    final theme = Theme.of(context);
    final info = _info;
    final history = _library.historyFor(_source?.animeId);
    final resume = _resumeEpisode;
    final isPlayingThis =
        _playback.title?.animeId != null &&
        _playback.title?.animeId == _source?.animeId;

    final meta = <Widget>[
      if (info?.score != null)
        Text(
          '★ ${info!.scoreOutOfTen!.toStringAsFixed(1)}',
          style: const TextStyle(color: green, fontWeight: FontWeight.w700),
        ),
      if (info?.seasonYear != null) Text('${info!.seasonYear}'),
      if (info?.format != null) _Badge(info!.format!),
      if (info?.episodes != null)
        Text('${info!.episodes} eps')
      else if (_episodes != null)
        Text('${_episodes!.length} eps'),
      if (info?.duration != null) Text('${info!.duration} min'),
      if (info?.isAiring ?? false) const _Badge('airing'),
    ];

    String playLabel = 'play';
    if (isPlayingThis) {
      playLabel = 'now playing · E${_playback.episode?.number}';
    } else if (history != null && resume != null) {
      playLabel = resume.number == history.lastEpisode
          ? 'resume E${resume.number}'
          : 'play E${resume.number}';
    }
    final resumeProgress = resume == null
        ? null
        : history?.episodes[resume.number];

    final align = wide ? TextAlign.start : TextAlign.center;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _title.title,
          textAlign: align,
          style:
              (wide
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (info != null &&
            info.titleRomaji != null &&
            info.titleRomaji != info.title)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              info.titleRomaji!,
              textAlign: align,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          child: Wrap(
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: meta,
          ),
        ),
        const SizedBox(height: 16),
        _fitPlayBlock(
          wide,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.onSurface,
                    foregroundColor: crust,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _episodes == null || _episodes!.isEmpty
                      ? null
                      : isPlayingThis
                      ? _playback.expand
                      : () => _play(),
                  icon: _episodes == null && _sourceError == null
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: crust,
                          ),
                        )
                      : Icon(
                          isPlayingThis ? Icons.open_in_full : Icons.play_arrow,
                        ),
                  label: Text(
                    _episodes == null && _sourceError == null
                        ? 'finding episodes'
                        : playLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (resumeProgress != null && !isPlayingThis) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: WatchProgressBar(resumeProgress.fraction),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${((resumeProgress.durationMs - resumeProgress.positionMs) / 60000).ceil()}m left',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_sourceError != null) ...[
          const SizedBox(height: 12),
          Text(
            _sourceError!,
            textAlign: align,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          Row(
            mainAxisAlignment: wide
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _resolveSource,
                icon: const Icon(Icons.refresh),
                label: const Text('retry'),
              ),
              TextButton.icon(
                onPressed: _changeSource,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('pick source'),
              ),
            ],
          ),
        ],
        if (info?.description != null) ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () =>
                setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: Text(
                info!.description!,
                maxLines: _descriptionExpanded ? null : 4,
                overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ),
        ],
        if (info != null && info.genres.isNotEmpty) ...[
          const SizedBox(height: 10),
          _LabeledLine('genres', info.genres.join(', ')),
        ],
        if (info != null && info.studios.isNotEmpty)
          _LabeledLine('studio', info.studios.join(', ')),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: wide
              ? MainAxisAlignment.start
              : MainAxisAlignment.spaceEvenly,
          children: [
            _ActionIcon(
              icon: _library.isFavourite(_title)
                  ? Icons.favorite
                  : Icons.favorite_border,
              label: 'favourite',
              onTap: _toggleFavourite,
            ),
            ListenableBuilder(
              listenable: AniListAccount.instance,
              builder: (context, _) {
                final account = AniListAccount.instance;
                final tracked = account.entryFor(_anilistId) != null;
                return _ActionIcon(
                  icon: tracked ? Icons.playlist_add_check : Icons.playlist_add,
                  label: 'tracking',
                  color: !account.isSignedIn
                      ? theme.disabledColor
                      : tracked
                      ? theme.colorScheme.primary
                      : null,
                  onTap: _openTracking,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// A full-width play button is a long bar on a desktop; keep it
  /// button-sized there.
  Widget _fitPlayBlock(bool wide, Widget child) => wide
      ? Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: child,
          ),
        )
      : child;

  Widget _buildTabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _TabLabel(
                label: 'episodes',
                selected: _tab == _Tab.episodes,
                onTap: () => setState(() => _tab = _Tab.episodes),
              ),
              // Only worth a tab when there is more than this one title
              if (_seasons.length > 1)
                _TabLabel(
                  label: 'seasons',
                  selected: _tab == _Tab.seasons,
                  onTap: () => setState(() => _tab = _Tab.seasons),
                ),
              if (_anilistId != null || _malId != null)
                _TabLabel(
                  label: 'more like this',
                  selected: _tab == _Tab.moreLikeThis,
                  onTap: () => setState(() => _tab = _Tab.moreLikeThis),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEpisodes(double width, bool wide) {
    final episodes = _episodes;
    if (episodes == null) {
      return [
        if (_sourceError == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ];
    }
    if (episodes.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('no episodes available')),
          ),
        ),
      ];
    }
    final history = _library.historyFor(_source?.animeId);
    final playing = _playback.title?.animeId == _source?.animeId
        ? _playback.episode?.url
        : null;
    Widget tile(Episode episode) => EpisodeTile(
      episode: episode,
      image: _title.image,
      progress: history?.episodes[episode.number],
      isPlaying: episode.url == playing,
      onTap: () => _play(episode),
    );
    if (wide) {
      // Two columns, so a long show isn't a mile of half-empty rows
      return [
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: width > _maxWidth ? (width - _maxWidth) / 2 + 16 : 16,
            vertical: 8,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisExtent: 76,
            ),
            itemCount: episodes.length,
            itemBuilder: (context, index) => tile(episodes[index]),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final episode = episodes[index];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: tile(episode),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildSeasons() {
    return SliverList.builder(
      itemCount: _seasons.length,
      itemBuilder: (context, index) {
        final media = _seasons[index];
        final isCurrent = media.id == _anilistId;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: _SeasonTile(
              media: media,
              isCurrent: isCurrent,
              onTap: isCurrent
                  ? null
                  : () => openTitle(context, titleFromAnilist(media)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreLikeThis(double width) {
    if (_recommendations.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('nothing to recommend yet')),
        ),
      );
    }
    final columns = (width.clamp(0, _maxWidth) / 140).floor().clamp(3, 8);
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: width > _maxWidth ? (width - _maxWidth) / 2 + 16 : 16,
        vertical: 12,
      ),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2 / 3,
        ),
        itemCount: _recommendations.length,
        itemBuilder: (context, index) {
          final media = _recommendations[index];
          return PosterCard(
            title: media.title,
            image: media.image,
            width: double.infinity,
            showTitle: false,
            onTap: () => openTitle(context, titleFromAnilist(media)),
          );
        },
      ),
    );
  }
}

class EpisodeTile extends StatelessWidget {
  final Episode episode;
  final String? image;
  final EpisodeProgress? progress;
  final bool isPlaying;
  final VoidCallback onTap;

  const EpisodeTile({
    super.key,
    required this.episode,
    required this.image,
    required this.progress,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = this.progress;
    String status = '';
    if (isPlaying) {
      status = 'now playing';
    } else if (progress != null) {
      status = progress.isWatched
          ? 'watched'
          : '${((progress.durationMs - progress.positionMs) / 60000).ceil()}m left';
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: isPlaying
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: progress?.isWatched ?? false ? 0.4 : 0.8,
                      child: NetImage(
                        image,
                        alignment: const Alignment(0, -0.4),
                      ),
                    ),
                    Center(
                      child: Icon(
                        isPlaying ? Icons.equalizer : Icons.play_circle_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: WatchProgressBar(progress.fraction),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'episode ${episode.number}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isPlaying ? theme.colorScheme.primary : null,
                    ),
                  ),
                  if (status.isNotEmpty)
                    Text(
                      status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (progress?.isWatched ?? false)
              Icon(
                Icons.check_circle,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

enum _Tab { episodes, seasons, moreLikeThis }

/// Edits your AniList entry: status, progress, score and dates.
class _TrackingSheet extends StatefulWidget {
  final LibraryTitle title;
  final AniListEntry? entry;
  final int? totalEpisodes;

  const _TrackingSheet({
    required this.title,
    required this.entry,
    required this.totalEpisodes,
  });

  @override
  State<_TrackingSheet> createState() => _TrackingSheetState();
}

class _TrackingSheetState extends State<_TrackingSheet> {
  late String _status = widget.entry?.status ?? 'PLANNING';
  late int _progress = widget.entry?.progress ?? 0;
  late double _score = widget.entry?.score ?? 0;
  late DateTime? _startedAt = widget.entry?.startedAt;
  late DateTime? _completedAt = widget.entry?.completedAt;
  bool _saving = false;

  int? get _total => widget.totalEpisodes;

  /// Fill in what the status implies, like AniList's own editor does.
  void _setStatus(String status) {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _status = status;
      if (status == 'CURRENT' || status == 'REPEATING') {
        _startedAt ??= today;
      }
      if (status == 'COMPLETED') {
        _startedAt ??= today;
        _completedAt ??= today;
        if (_total != null) _progress = _total!;
      }
    });
  }

  void _setProgress(int value) {
    final total = _total;
    setState(() {
      _progress = value.clamp(0, total ?? 9999);
      if (_progress > 0 && _status == 'PLANNING') _setStatus('CURRENT');
      if (total != null && _progress == total && _status != 'COMPLETED') {
        _setStatus('COMPLETED');
      }
    });
  }

  Future<void> _pickDate(bool started) async {
    final current = started ? _startedAt : _completedAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => started ? _startedAt = picked : _completedAt = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final account = AniListAccount.instance;
    final ok = await account.saveEntry(
      widget.title,
      status: _status,
      progress: _progress,
      score: _score,
      startedAt: _startedAt,
      completedAt: _completedAt,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(account.error ?? 'couldn\'t save to anilist')),
      );
    }
  }

  Future<void> _remove() async {
    final entry = widget.entry;
    if (entry == null || !await confirmAniListRemoval(context, entry)) return;
    setState(() => _saving = true);
    final account = AniListAccount.instance;
    final ok = await account.deleteEntry(widget.title);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(account.error ?? 'couldn\'t remove it')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final label = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget dateField(String name, DateTime? value, bool started) => Expanded(
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: name,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          suffixIcon: value == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'clear',
                  onPressed: () => setState(
                    () => started ? _startedAt = null : _completedAt = null,
                  ),
                ),
        ),
        child: InkWell(
          onTap: () => _pickDate(started),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_formatDate(value) ?? 'not set'),
          ),
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text('status', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final status in AniListEntry.statuses)
                  ChoiceChip(
                    label: Text(AniListEntry.labelFor(status)),
                    selected: _status == status,
                    onSelected: (_) => _setStatus(status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('progress', style: label),
            Row(
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.remove),
                  onPressed: _progress > 0
                      ? () => _setProgress(_progress - 1)
                      : null,
                ),
                Expanded(
                  child: Text(
                    '$_progress${total != null ? ' / $total' : ''} eps',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton.outlined(
                  icon: const Icon(Icons.add),
                  onPressed: total == null || _progress < total
                      ? () => _setProgress(_progress + 1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('score', style: label),
                const Spacer(),
                Text(
                  _score > 0 ? '★ ${_formatScore(_score)} / 10' : 'no score',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              value: _score,
              max: 10,
              divisions: 20,
              label: _score > 0 ? _formatScore(_score) : 'none',
              onChanged: (value) => setState(() => _score = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                dateField('started', _startedAt, true),
                const SizedBox(width: 12),
                dateField('finished', _completedAt, false),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.entry != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatScore(double score) => score == score.roundToDouble()
    ? '${score.round()}'
    : score.toStringAsFixed(1);

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

String? _formatDate(DateTime? date) =>
    date == null ? null : '${date.day} ${_months[date.month - 1]} ${date.year}';

/// One title in the show's prequel and sequel chain.
class _SeasonTile extends StatelessWidget {
  final AniListMedia media;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _SeasonTile({
    required this.media,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (media.format != null)
        media.format!.toLowerCase().replaceAll('_', ' '),
      if (media.seasonYear != null) '${media.seasonYear}',
      if (media.episodes != null) '${media.episodes} eps',
      if (media.isAiring) 'airing',
      if (media.status == 'NOT_YET_RELEASED') 'upcoming',
    ];
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isCurrent
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 84,
                child: NetImage(media.image),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCurrent
                        ? ['current', ...details].join(' · ')
                        : details.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!isCurrent)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text.toLowerCase()),
    );
  }
}

class _LabeledLine extends StatelessWidget {
  final String label;
  final String value;

  const _LabeledLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(text: value.toLowerCase()),
          ],
        ),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color ?? Theme.of(context).colorScheme.onSurface),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
        margin: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: selected ? theme.colorScheme.error : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick which hianime entry plays for this show.
class _SourcePicker extends StatefulWidget {
  final String initialQuery;

  const _SourcePicker({required this.initialQuery});

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  List<Anime>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final results = await AnimeProvider().search(_controller.text);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                hintText: 'search source...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : results == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scrollController,
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final anime = results[index];
                      return ListTile(
                        tileColor: Colors.transparent,
                        leading: SizedBox(
                          width: 40,
                          child: NetImage(anime.thumbnail),
                        ),
                        title: Text(anime.title),
                        onTap: () => Navigator.pop(context, anime),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
