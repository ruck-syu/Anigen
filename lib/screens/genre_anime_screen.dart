import 'package:flutter/material.dart';
import 'package:jikan_api/jikan_api.dart';
import 'package:anigen/providers/jikan_provider.dart';
import 'package:anigen/screens/anime_info_screen.dart';

class GenreAnimeScreen extends StatefulWidget {
  final int genreId;
  final String genreName;
  final ValueChanged<String>? onSearchPressed;

  const GenreAnimeScreen({
    super.key,
    required this.genreId,
    required this.genreName,
    this.onSearchPressed,
  });

  @override
  State<GenreAnimeScreen> createState() => _GenreAnimeScreenState();
}

class _GenreAnimeScreenState extends State<GenreAnimeScreen> {
  final JikanProvider _jikanProvider = JikanProvider();
  List<Anime> _animeList = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnime();
  }

  Future<void> _loadAnime() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final anime = await _jikanProvider.getAnimeByGenre(widget.genreId);
      setState(() {
        _animeList = anime.take(50).toList();
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
        title: Text(widget.genreName),
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _isLoading
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
                          'failed to load anime',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _loadAnime,
                          icon: const Icon(Icons.refresh),
                          label: const Text('retry'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadAnime,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.58,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _animeList.length,
                      itemBuilder: (context, index) {
                        final anime = _animeList[index];
                        return GestureDetector(
                          onTap: () {
                            if (anime.malId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AnimeInfoScreen(
                                    malId: anime.malId!,
                                    animeTitle: anime.title ?? 'Unknown',
                                    onSearchPressed: widget.onSearchPressed,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: 0.7,
                                  child: anime.imageUrl != null
                                      ? Image.network(
                                          anime.imageUrl!,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: Theme.of(context).colorScheme.surfaceContainer,
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        )
                                      : Container(
                                          color: Theme.of(context).colorScheme.surfaceContainer,
                                          child: const Icon(Icons.movie),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                anime.title ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                      height: 1.1,
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
