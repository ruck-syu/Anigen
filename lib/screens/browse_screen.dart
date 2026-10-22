import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jikan_api/jikan_api.dart';
import 'package:anigen/providers/jikan_provider.dart';
import 'package:anigen/screens/genre_anime_screen.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

/// Home tab: a featured title up top, then rows of shows.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _hiddenGenres = [
    'boys love',
    'girls love',
    'ecchi',
    'erotica',
    'hentai',
    'adult cast',
    'anthropomorphic',
    'cgdct',
  ];

  final _jikan = JikanProvider();
  final _scroll = ScrollController();
  final _barOpacity = ValueNotifier<double>(0);

  List<Anime> _season = [];
  List<Anime> _top = [];
  List<Anime> _airing = [];
  List<Anime> _popular = [];
  List<Anime> _movies = [];
  List<Anime> _upcoming = [];
  List<Genre> _genres = [];
  bool _isLoading = true;
  int _failures = 0;

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

  /// Jikan allows about 3 requests a second, so rows load one after another
  /// and each fills in as it arrives. One failing row doesn't sink the page.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _failures = 0;
    });
    Future<void> load<T>(
      Future<List<T>> Function() fetch,
      void Function(List<T>) apply,
    ) async {
      try {
        final result = await fetch();
        if (mounted) setState(() => apply(result));
      } catch (e) {
        debugPrint('browse: $e');
        _failures++;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    await load(_jikan.getSeasonAnime, (r) => _season = r);
    await load(_jikan.getTopAnime, (r) => _top = r);
    await load(_jikan.getAiringToday, (r) => _airing = r);
    await load(_jikan.getPopularAnime, (r) => _popular = r);
    await load(_jikan.getTopMovies, (r) => _movies = r);
    await load(_jikan.getUpcomingAnime, (r) => _upcoming = r);
    await load(_jikan.getAnimeGenres, (r) {
      _genres =
          r.where((g) => !_hiddenGenres.contains(g.name.toLowerCase())).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
    });
    if (mounted) setState(() => _isLoading = false);
  }

  Anime? get _featured {
    final candidates = (_season.isNotEmpty ? _season : _top)
        .where((a) => a.synopsis != null && (a.score ?? 0) > 0)
        .take(6)
        .toList();
    if (candidates.isEmpty) return null;
    // A different pick each day
    return candidates[DateTime.now().day % candidates.length];
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
        _failures > 0 &&
        _season.isEmpty &&
        _top.isEmpty &&
        _popular.isEmpty;

    return Scaffold(
      body: Stack(
        children: [
          if (nothingLoaded)
            _ErrorState(onRetry: _loadData)
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
                      child: _featured == null
                          ? SizedBox(
                              height: 420,
                              child: Center(
                                child: _isLoading
                                    ? const CircularProgressIndicator()
                                    : const SizedBox.shrink(),
                              ),
                            )
                          : _Hero(anime: _featured!, wide: wide),
                    ),
                    SliverList.list(
                      children: [
                        _continueWatchingRow(padding, wide),
                        _myListRow(padding, posterWidth, posterRowHeight),
                        if (_top.isNotEmpty)
                          CardRow(
                            title: 'top 10 anime',
                            padding: padding,
                            height: posterWidth * 3 / 2,
                            itemCount: _top.length.clamp(0, 10),
                            itemBuilder: (context, i) => RankedCard(
                              rank: i + 1,
                              title: _top[i].title,
                              image: _top[i].imageUrl,
                              posterWidth: posterWidth,
                              onTap: () =>
                                  openTitle(context, titleFromJikan(_top[i])),
                            ),
                          ),
                        _jikanRow(
                          'airing today',
                          _airing,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _jikanRow(
                          'new this season',
                          _season,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _jikanRow(
                          'most popular',
                          _popular,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _jikanRow(
                          'top movies',
                          _movies,
                          padding,
                          posterWidth,
                          posterRowHeight,
                        ),
                        _jikanRow(
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
                                    label: Text(genre.name.toLowerCase()),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => GenreAnimeScreen(
                                          genreId: genre.malId,
                                          genreName: genre.name,
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
              builder: (context, opacity, child) => ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 12 * opacity,
                    sigmaY: 12 * opacity,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6 + 0.3 * opacity),
                          mantle.withValues(alpha: opacity * 0.9),
                        ],
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: const Row(children: [AnigenLogo(size: 22)]),
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

  Widget _myListRow(double padding, double posterWidth, double height) {
    final items = LibraryStore.instance.myList;
    return CardRow(
      title: 'my list',
      padding: padding,
      height: height,
      itemCount: items.length,
      itemBuilder: (context, i) => PosterCard(
        title: items[i].title,
        image: items[i].image,
        width: posterWidth,
        onTap: () => openTitle(context, items[i]),
      ),
    );
  }

  Widget _jikanRow(
    String title,
    List<Anime> items,
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
        title: items[i].titleEnglish ?? items[i].title,
        image: items[i].imageUrl,
        width: posterWidth,
        onTap: () => openTitle(context, titleFromJikan(items[i])),
      ),
    );
  }
}

/// The big featured title at the top of home.
class _Hero extends StatelessWidget {
  final Anime anime;
  final bool wide;

  const _Hero({required this.anime, required this.wide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = LibraryStore.instance;
    final title = titleFromJikan(anime);
    final inList = library.isInMyList(title);
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final genres = anime.genres
        .take(4)
        .map((g) => g.name.toLowerCase())
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
          onPressed: () => library.toggleMyList(title),
          icon: Icon(inList ? Icons.check : Icons.add),
          label: const Text('my list'),
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
        if (wide && anime.synopsis != null) ...[
          const SizedBox(height: 12),
          Text(
            anime.synopsis!,
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

    final backdrop = [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Opacity(opacity: 0.6, child: NetImage(anime.imageUrl)),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.6, 1],
            colors: [
              Colors.transparent,
              theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
      ),
    ];

    if (wide) {
      return SizedBox(
        height: 520,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ...backdrop,
            Padding(
              padding: EdgeInsets.fromLTRB(48, topPadding + 16, 48, 32),
              child: Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 48),
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: _Poster(url: anime.imageUrl),
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
        Positioned.fill(
          child: Stack(fit: StackFit.expand, children: backdrop),
        ),
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
                      _Poster(url: anime.imageUrl),
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
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
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
            "couldn't reach myanimelist (jikan)",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('retry'),
          ),
        ],
      ),
    );
  }
}
