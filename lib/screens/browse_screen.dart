import 'dart:async';
import 'package:flutter/material.dart';
import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/providers/anilist_provider.dart';
import 'package:anigen/screens/genre_anime_screen.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

/// Home tab: featured titles up top, then rows of shows.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _anilist = AniListProvider();
  final _scroll = ScrollController();
  final _barOpacity = ValueNotifier<double>(0);

  List<AniListMedia> _season = [];
  List<AniListMedia> _top = [];
  List<AniListMedia> _airing = [];
  List<AniListMedia> _popular = [];
  List<AniListMedia> _movies = [];
  List<AniListMedia> _upcoming = [];
  List<String> _genres = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      _barOpacity.value = (_scroll.offset / 200).clamp(0.0, 1.0);
    });
    _loadData();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _barOpacity.dispose();
    super.dispose();
  }

  /// Every row comes from a single AniList request, so the whole page
  /// arrives at once instead of trickling in one call at a time.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final feed = await _anilist.getHomeFeed();
      if (!mounted) return;
      setState(() {
        _season = feed.season;
        _top = feed.top;
        _airing = feed.airing;
        _popular = feed.popular;
        _movies = feed.movies;
        _upcoming = feed.upcoming;
        _genres = feed.genres;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('browse: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  List<AniListMedia> get _featured {
    final candidates = (_season.isNotEmpty ? _season : _top)
        .where((a) => a.description != null && (a.score ?? 0) > 0)
        .take(8)
        .toList();
    if (candidates.isEmpty) return candidates;
    // A different one first each day
    final start = DateTime.now().day % candidates.length;
    return [...candidates.skip(start), ...candidates.take(start)];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final padding = wide ? 24.0 : 16.0;
    final posterWidth = width >= 1200
        ? 160.0
        : wide
        ? 140.0
        : 112.0;
    final posterRowHeight = posterWidth * 3 / 2 + 42;
    final nothingLoaded =
        !_isLoading &&
        _error != null &&
        _season.isEmpty &&
        _top.isEmpty &&
        _popular.isEmpty;

    return Scaffold(
      body: Stack(
        children: [
          if (nothingLoaded)
            _ErrorState(error: _error!, onRetry: _loadData)
          else
            RefreshIndicator(
              onRefresh: _loadData,
              edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
              child: ListenableBuilder(
                listenable: LibraryStore.instance,
                builder: (context, _) => CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _featured.isEmpty
                          ? SizedBox(
                              height: 420,
                              child: Center(
                                child: _isLoading
                                    ? const CircularProgressIndicator()
                                    : const SizedBox.shrink(),
                              ),
                            )
                          : _HeroCarousel(items: _featured, wide: wide),
                    ),
                    SliverList.list(
                      children: [
                        _continueWatchingRow(padding, wide),
                        if (_top.isNotEmpty)
                          CardRow(
                            title: 'top 10 anime',
                            padding: padding,
                            height: posterWidth * 3 / 2,
                            itemCount: _top.length.clamp(0, 10),
                            itemBuilder: (context, i) => RankedCard(
                              rank: i + 1,
                              title: _top[i].title,
                              image: _top[i].image,
                              posterWidth: posterWidth,
                              onTap: () =>
                                  openTitle(context, titleFromAnilist(_top[i])),
                            ),
                          ),
                        _mediaRow(
                          'airing now',
                          _airing,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _mediaRow(
                          'new this season',
                          _season,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _mediaRow(
                          'most popular',
                          _popular,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _mediaRow(
                          'top movies',
                          _movies,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _mediaRow(
                          'coming soon',
                          _upcoming,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        if (_genres.isNotEmpty) ...[
                          SectionHeader('categories', padding: padding),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final genre in _genres)
                                  ActionChip(
                                    label: Text(genre.toLowerCase()),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => GenreAnimeScreen(
                                          genre: genre,
                                          genreName: genre,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        SizedBox(height: bottomInset(context) + 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Top bar fades in as the page scrolls past the hero
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _barOpacity,
              builder: (context, opacity, child) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7 + 0.25 * opacity),
                      mantle.withValues(alpha: opacity * 0.95),
                    ],
                  ),
                ),
                child: child,
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: const Row(
                      children: [AnigenLogo(size: 22, shadow: true)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueWatchingRow(double padding, bool wide) {
    final library = LibraryStore.instance;
    final entries = library.continueWatching;
    return CardRow(
      title: 'continue watching',
      padding: padding,
      height: (wide ? 260 : 200) * 9 / 16 + 40,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return ContinueCard(
          entry: entry,
          width: wide ? 260 : 200,
          onTap: () => openTitle(context, entry.title, autoplay: true),
          onInfo: () => openTitle(context, entry.title),
          onRemove: () => library.removeFromHistory(entry.title.animeId!),
        );
      },
    );
  }

  Widget _mediaRow(
    String title,
    List<AniListMedia> items,
    double padding,
    double posterWidth,
    double height,
  ) {
    return CardRow(
      title: title,
      padding: padding,
      height: height,
      itemCount: items.length.clamp(0, 20),
      itemBuilder: (context, i) => PosterCard(
        title: items[i].title,
        image: items[i].image,
        width: posterWidth,
        onTap: () => openTitle(context, titleFromAnilist(items[i])),
      ),
    );
  }
}

/// The featured titles at the top of home: swipe through them, and they
/// move on by themselves until you do.
class _HeroCarousel extends StatefulWidget {
  final List<AniListMedia> items;
  final bool wide;

  const _HeroCarousel({required this.items, required this.wide});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _interval = Duration(seconds: 8);
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      // Not while another tab or the player covers home.
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (!_controller.hasClients || widget.items.length < 2) return;
      final next = (_page + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final width = MediaQuery.sizeOf(context).width;
    final posterWidth = (width - 64).clamp(0.0, 340.0);
    const dotsHeight = 22.0;
    final height = widget.wide
        ? 520.0
        : topPadding + 8 + posterWidth * 3 / 2 + 8 + dotsHeight;

    final background = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // One backdrop behind all the cards that cross-fades as you swipe,
          // so there's no seam between them.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final position =
                    _controller.hasClients &&
                        _controller.position.haveDimensions
                    ? _controller.page!
                    : _page.toDouble();
                final index = position.floor().clamp(0, items.length - 1);
                final t = (position - index).clamp(0.0, 1.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _Backdrop(key: ValueKey(index), media: items[index]),
                    if (t > 0 && index + 1 < items.length)
                      Opacity(
                        key: ValueKey(index + 1),
                        opacity: t,
                        child: _Backdrop(media: items[index + 1]),
                      ),
                  ],
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.6, 1],
                  colors: [
                    Colors.transparent,
                    background.withValues(alpha: 0.6),
                    background,
                  ],
                ),
              ),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Swiping by hand resets the countdown.
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _restartTimer();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(bottom: widget.wide ? 0 : dotsHeight),
                child: _Hero(media: items[i], wide: widget.wide),
              ),
            ),
          ),
          if (items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.wide ? 16 : 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A featured title's art, soft and wide. AniList's landscape banner when
/// there is one, so it doesn't have to be a stretched portrait.
class _Backdrop extends StatelessWidget {
  final AniListMedia media;

  const _Backdrop({super.key, required this.media});

  @override
  Widget build(BuildContext context) => media.banner != null
      ? SoftBackdrop(media.banner, decodeWidth: 160)
      : SoftBackdrop(media.image, decodeWidth: 24);
}

/// One featured title, drawn over the carousel's backdrop.
class _Hero extends StatelessWidget {
  final AniListMedia media;
  final bool wide;

  const _Hero({required this.media, required this.wide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = LibraryStore.instance;
    final title = titleFromAnilist(media);
    final favourite = library.isFavourite(title);
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final genres = media.genres
        .take(4)
        .map((g) => g.toLowerCase())
        .join('  •  ');

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.onSurface,
            foregroundColor: crust,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () => openTitle(context, title, autoplay: true),
          icon: const Icon(Icons.play_arrow),
          label: const Text(
            'play',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () => library.toggleFavourite(title),
          icon: Icon(favourite ? Icons.favorite : Icons.favorite_border),
          label: const Text('favourite'),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'info',
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () => openTitle(context, title),
        ),
      ],
    );

    final info = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.title,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (wide
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w900, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          genres,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        if (wide && media.description != null) ...[
          const SizedBox(height: 12),
          Text(
            media.description!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        buttons,
      ],
    );

    if (wide) {
      return SizedBox(
        height: 520,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(48, topPadding + 16, 48, 32),
              child: Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 48),
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: _Poster(url: media.image),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final posterWidth = (width - 64).clamp(0.0, 340.0);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 8),
          child: Center(
            child: SizedBox(
              width: posterWidth,
              child: GestureDetector(
                onTap: () => openTitle(context, title),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Poster(url: media.image),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.45, 1],
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(left: 12, right: 12, bottom: 14, child: info),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;

  const _Poster({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: NetImage(url),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              "couldn't reach anilist",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('retry'),
            ),
          ],
        ),
      ),
    );
  }
}
