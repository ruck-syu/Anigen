import 'package:flutter/material.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/screens/details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final AnimeProvider _provider = AnimeProvider();
  final TextEditingController _searchController = TextEditingController();
  List<Anime> _results = [];
  List<Anime> _recentAnime = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  late AnimationController _animationController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadRecentAnime();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void setSearchQuery(String query) {
    _searchController.text = query;
    _search(query: query);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _results = [];
      });
      return;
    }

    if (query.length >= 2) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
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
        _recentAnime = jsonList.map((jsonStr) {
          final json = jsonDecode(jsonStr);
          return Anime(
            title: json['title'],
            url: json['url'],
            thumbnail: json['thumbnail'],
          );
        }).toList();
      });
    } catch (e) {
      setState(() {
        _recentAnime = [];
      });
    }
  }

  Future<void> _saveRecentAnime(Anime anime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Remove if already exists
      _recentAnime.removeWhere((a) => a.url == anime.url);
      _recentAnime.insert(0, anime);
      if (_recentAnime.length > 10) {
        _recentAnime = _recentAnime.sublist(0, 10);
      }
      
      // Encode to JSON strings
      final jsonList = _recentAnime.map((a) => jsonEncode({
        'title': a.title,
        'url': a.url,
        'thumbnail': a.thumbnail,
      })).toList();
      
      await prefs.setStringList('recent_anime', jsonList);
      setState(() {}); // Update UI
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _clearRecentAnime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_anime');
    } catch (e) {
      // Silently fail
    }
    setState(() {
      _recentAnime = [];
    });
  }

  void _search({String? query}) async {
    final searchQuery = query ?? _searchController.text;
    if (searchQuery.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results = await _provider.search(searchQuery);
      setState(() {
        _results = results;
      });
      _animationController.forward(from: 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Search'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'search anime...',
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : const Icon(Icons.search),
                ),
              ),
              
              if (_recentAnime.isNotEmpty && !_hasSearched)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'recent searches',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          TextButton(
                            onPressed: _clearRecentAnime,
                            child: const Text('clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recentAnime.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final anime = _recentAnime[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetailsScreen(anime: anime),
                                  ),
                                );
                              },
                              child: SizedBox(
                                width: 120,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: anime.thumbnail != null
                                          ? Image.network(
                                              anime.thumbnail!,
                                              width: 120,
                                              height: 140,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                width: 120,
                                                height: 140,
                                                color: Theme.of(context).colorScheme.surfaceContainer,
                                                child: const Icon(Icons.broken_image),
                                              ),
                                            )
                                          : Container(
                                              width: 120,
                                              height: 140,
                                              color: Theme.of(context).colorScheme.surfaceContainer,
                                              child: const Icon(Icons.movie_outlined),
                                            ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      anime.title,
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 16),
              
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : !_hasSearched
                        ? _recentAnime.isNotEmpty
                            ? const SizedBox.shrink()
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search,
                                      size: 64,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'search for anime',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'find your favorite shows',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                          ),
                                    ),
                                  ],
                                ),
                              )
                        : _results.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.sentiment_dissatisfied,
                                      size: 64,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'no results found',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'try a different search',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _refresh,
                                child: FadeTransition(
                                  opacity: _animationController,
                                  child: ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    itemCount: _results.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final anime = _results[index];
                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: anime.thumbnail != null
                                              ? Image.network(
                                                  anime.thumbnail!,
                                                  width: 50,
                                                  height: 70,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    width: 50,
                                                    height: 70,
                                                    color: Theme.of(context).colorScheme.surfaceContainer,
                                                    child: const Icon(Icons.broken_image, size: 20),
                                                  ),
                                                )
                                              : Container(
                                                  width: 50,
                                                  height: 70,
                                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                                  child: const Icon(Icons.movie_outlined, size: 20),
                                                ),
                                        ),
                                        title: Text(
                                          anime.title,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () {
                                          _saveRecentAnime(anime);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => DetailsScreen(anime: anime),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
