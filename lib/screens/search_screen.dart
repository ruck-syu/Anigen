import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final AnimeProvider _provider = AnimeProvider();
  final TextEditingController _searchController = TextEditingController();
  List<Anime> _results = [];
  List<Anime> _recentAnime = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;
  Timer? _debounce;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _loadRecentAnime();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void setSearchQuery(String query) {
    _searchController.text = query;
    _search(query: query);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _results = [];
        _error = null;
      });
      return;
    }
    if (query.length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 400), () {
        _search(query: query);
      });
    }
  }

  Future<void> _loadRecentAnime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('recent_anime') ?? [];
      setState(() {
        _recentAnime = jsonList
            .map((jsonStr) {
              final json = jsonDecode(jsonStr);
              return Anime(
                title: json['title'],
                url: json['url'],
                thumbnail: json['thumbnail'],
              );
            })
            .where((anime) => AnimeProvider.isSupportedId(anime.url))
            .toList();
      });
    } catch (e) {
      setState(() {
        _recentAnime = [];
      });
    }
  }

  Future<void> _saveRecentAnime(Anime anime) async {
    _recentAnime.removeWhere((a) => a.url == anime.url);
    _recentAnime.insert(0, anime);
    if (_recentAnime.length > 10) {
      _recentAnime = _recentAnime.sublist(0, 10);
    }
    setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'recent_anime',
        _recentAnime
            .map(
              (a) => jsonEncode({
                'title': a.title,
                'url': a.url,
                'thumbnail': a.thumbnail,
              }),
            )
            .toList(),
      );
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _clearRecentAnime() async {
    setState(() {
      _recentAnime = [];
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_anime');
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _search({String? query}) async {
    final searchQuery = query ?? _searchController.text;
    if (searchQuery.isEmpty) return;
    final id = ++_searchId;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      final results = await _provider.search(searchQuery);
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _open(Anime anime) {
    FocusScope.of(context).unfocus();
    _saveRecentAnime(anime);
    openTitle(
      context,
      LibraryTitle(
        title: anime.title,
        image: anime.thumbnail,
        animeId: anime.url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 900 ? 24.0 : 16.0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) => _search(query: query),
                  decoration: InputDecoration(
                    hintText: 'search shows, movies...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _searchController.clear,
                          )
                        : null,
                  ),
                ),
              ),
              if (_isLoading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _hasSearched
                    ? _buildResults(padding, width)
                    : _buildIdle(padding),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdle(double padding) {
    final library = LibraryStore.instance;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final history = library.continueWatching;
        if (_recentAnime.isEmpty && history.isEmpty) {
          return _Message(icon: Icons.search, text: 'find something to watch');
        }
        return ListView(
          children: [
            CardRow(
              title: 'recent searches',
              padding: padding,
              height: 112 * 3 / 2 + 42,
              itemCount: _recentAnime.length,
              trailing: TextButton(
                onPressed: _clearRecentAnime,
                child: const Text('clear'),
              ),
              itemBuilder: (context, i) => PosterCard(
                title: _recentAnime[i].title,
                image: _recentAnime[i].thumbnail,
                width: 112,
                onTap: () => _open(_recentAnime[i]),
              ),
            ),
            if (history.isNotEmpty) ...[
              SectionHeader('recently watched', padding: padding),
              for (final entry in history.take(8))
                ListTile(
                  tileColor: Colors.transparent,
                  contentPadding: EdgeInsets.symmetric(horizontal: padding),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 40,
                      height: 56,
                      child: NetImage(entry.title.image),
                    ),
                  ),
                  title: Text(
                    entry.title.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('episode ${entry.lastEpisode}'),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => openTitle(context, entry.title, autoplay: true),
                ),
            ],
            SizedBox(height: bottomInset(context) + 16),
          ],
        );
      },
    );
  }

  Widget _buildResults(double padding, double width) {
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _error!,
        action: TextButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.refresh),
          label: const Text('retry'),
        ),
      );
    }
    if (_results.isEmpty) {
      return _isLoading
          ? const SizedBox.shrink()
          : const _Message(icon: Icons.search_off, text: 'no results found');
    }
    final columns = (width / 150).floor().clamp(3, 8);
    return RefreshIndicator(
      onRefresh: _search,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          padding,
          8,
          padding,
          bottomInset(context) + 16,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.5,
        ),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final anime = _results[index];
          return PosterCard(
            title: anime.title,
            image: anime.thumbnail,
            width: double.infinity,
            onTap: () => _open(anime),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
