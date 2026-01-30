import 'package:flutter/material.dart';
import 'package:anigen/screens/search_screen.dart';
import 'package:anigen/screens/profile_screen.dart';
import 'package:anigen/screens/anime_info_screen.dart';
import 'package:anigen/screens/genre_anime_screen.dart';
import 'package:anigen/providers/jikan_provider.dart';
import 'package:jikan_api/jikan_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();
  
  void _navigateToSearchWithQuery(String query) {
    setState(() {
      _currentIndex = 1;
    });
    // Use addPostFrameCallback to ensure navigation completes before setting text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchScreenKey.currentState?.setSearchQuery(query);
    });
  }
  
  List<Widget> get _screens => [
    HomeContentScreen(onNavigateToSearch: _navigateToSearchWithQuery),
    SearchScreen(key: _searchScreenKey),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(
                    _currentIndex == 0 ? Icons.home : Icons.home_outlined,
                    color: _currentIndex == 0
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    setState(() {
                      _currentIndex = 0;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    _currentIndex == 1 ? Icons.search : Icons.search_outlined,
                    color: _currentIndex == 1
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    setState(() {
                      _currentIndex = 1;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    _currentIndex == 2 ? Icons.person : Icons.person_outline,
                    color: _currentIndex == 2
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    setState(() {
                      _currentIndex = 2;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeContentScreen extends StatefulWidget {
  final ValueChanged<String>? onNavigateToSearch;
  
  const HomeContentScreen({super.key, this.onNavigateToSearch});

  @override
  State<HomeContentScreen> createState() => _HomeContentScreenState();
}

class _HomeContentScreenState extends State<HomeContentScreen> {
  final JikanProvider _jikanProvider = JikanProvider();
  List<Anime> _topAnime = [];
  List<Anime> _currentSeason = [];
  List<Anime> _popularAnime = [];
  List<Anime> _upcomingAnime = [];
  List<Anime> _airingToday = [];
  List<Genre> _genres = [];
  bool _isLoading = true;
  String? _error;
  bool _showTopAnime = true; // true for top, false for popular
  bool _showCurrentSeason = true; // true for current season, false for upcoming

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _jikanProvider.getTopAnime(),
        _jikanProvider.getSeasonAnime(),
        _jikanProvider.getPopularAnime(),
        _jikanProvider.getUpcomingAnime(),
        _jikanProvider.getAiringToday(),
        _jikanProvider.getAnimeGenres(),
      ]);

      setState(() {
        _topAnime = results[0] as List<Anime>;
        _currentSeason = results[1] as List<Anime>;
        _popularAnime = results[2] as List<Anime>;
        _upcomingAnime = results[3] as List<Anime>;
        _airingToday = results[4] as List<Anime>;
        _genres = results[5] as List<Genre>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Color(0xFFcba6f7), // Mauve
                Color(0xFFb4befe), // Lavender
                Color(0xFF89b4fa), // Blue
                Color(0xFF74c7ec), // Sapphire
              ],
            ).createShader(bounds);
          },
          child: const Text(
            'Anigen',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'failed to load data',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      // Pill-shaped switcher
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildPillButton(
                              label: 'top anime',
                              isSelected: _showTopAnime,
                              onTap: () {
                                setState(() {
                                  _showTopAnime = true;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildPillButton(
                              label: 'most popular',
                              isSelected: !_showTopAnime,
                              onTap: () {
                                setState(() {
                                  _showTopAnime = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Combined top/popular section
                      if (_showTopAnime && _topAnime.isNotEmpty) ...[
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _topAnime.length > 10 ? 10 : _topAnime.length,
                            itemBuilder: (context, index) {
                              final anime = _topAnime[index];
                              return _buildAnimeCard(anime, context);
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ] else if (!_showTopAnime && _popularAnime.isNotEmpty) ...[
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _popularAnime.length > 10 ? 10 : _popularAnime.length,
                            itemBuilder: (context, index) {
                              final anime = _popularAnime[index];
                              return _buildAnimeCard(anime, context);
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Pill-shaped switcher for season/upcoming
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildPillButton(
                              label: 'current season',
                              isSelected: _showCurrentSeason,
                              onTap: () {
                                setState(() {
                                  _showCurrentSeason = true;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildPillButton(
                              label: 'upcoming',
                              isSelected: !_showCurrentSeason,
                              onTap: () {
                                setState(() {
                                  _showCurrentSeason = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Combined current season/upcoming section
                      if (_showCurrentSeason && _currentSeason.isNotEmpty) ...[
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _currentSeason.length > 10 ? 10 : _currentSeason.length,
                            itemBuilder: (context, index) {
                              final anime = _currentSeason[index];
                              return _buildAnimeCard(anime, context);
                            },
                          ),
                        ),
                      ] else if (!_showCurrentSeason && _upcomingAnime.isNotEmpty) ...[
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _upcomingAnime.length > 10 ? 10 : _upcomingAnime.length,
                            itemBuilder: (context, index) {
                              final anime = _upcomingAnime[index];
                              return _buildAnimeCard(anime, context);
                            },
                          ),
                        ),
                      ],
                      
                      // Categories section at the bottom
                      if (_genres.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'categories',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: () {
                              final filtered = _genres
                                  .where((genre) {
                                    final name = genre.name?.toLowerCase() ?? '';
                                    return !['boys love', 'girls love', 'ecchi', 'erotica', 
                                            'hentai', 'adult cast', 'anthropomorphic', 'cgdct']
                                        .contains(name);
                                  })
                                  .take(16)
                                  .toList();
                              filtered.sort((a, b) => (a.name?.length ?? 0).compareTo(b.name?.length ?? 0));
                              return filtered.map((genre) {
                                return ActionChip(
                                  label: Text(genre.name ?? ''),
                                  onPressed: () {
                                    if (genre.malId != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => GenreAnimeScreen(
                                            genreId: genre.malId!,
                                            genreName: genre.name ?? 'Genre',
                                            onSearchPressed: widget.onNavigateToSearch,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }).toList();
                            }(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildPillButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }

  Widget _buildAnimeCard(Anime anime, BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (anime.malId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AnimeInfoScreen(
                malId: anime.malId!,
                animeTitle: anime.title ?? 'Unknown',
                onSearchPressed: widget.onNavigateToSearch,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: anime.imageUrl != null
                  ? Image.network(
                      anime.imageUrl!,
                      height: 160,
                      width: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 160,
                        width: 120,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Icon(Icons.broken_image),
                      ),
                    )
                  : Container(
                      height: 160,
                      width: 120,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Icon(Icons.movie),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title ?? 'Unknown',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
