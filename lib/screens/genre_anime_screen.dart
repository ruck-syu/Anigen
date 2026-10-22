import 'package:flutter/material.dart';
import 'package:jikan_api/jikan_api.dart';
import 'package:anigen/providers/jikan_provider.dart';
import 'package:anigen/widgets/title_cards.dart';

class GenreAnimeScreen extends StatefulWidget {
  final int genreId;
  final String genreName;
  const GenreAnimeScreen({
    super.key,
    required this.genreId,
    required this.genreName,
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
      appBar: AppBar(title: Text(widget.genreName)),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = constraints.maxWidth;
                    final isDesktop = screenWidth > 600;
                    final crossAxisCount = isDesktop ? 5 : 3;
                    final childAspectRatio = isDesktop ? 0.56 : 0.5;

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        bottomInset(context) + 16,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _animeList.length,
                      itemBuilder: (context, index) {
                        final anime = _animeList[index];
                        return PosterCard(
                          title: anime.titleEnglish ?? anime.title,
                          image: anime.imageUrl,
                          width: double.infinity,
                          onTap: () =>
                              openTitle(context, titleFromJikan(anime)),
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}
