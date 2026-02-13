import 'package:flutter/material.dart';
import 'package:jikan_api/jikan_api.dart';

class AnimeInfoScreen extends StatefulWidget {
  final int malId;
  final String animeTitle;
  final ValueChanged<String>? onSearchPressed;

  const AnimeInfoScreen({
    super.key,
    required this.malId,
    required this.animeTitle,
    this.onSearchPressed,
  });

  @override
  State<AnimeInfoScreen> createState() => _AnimeInfoScreenState();
}

class _AnimeInfoScreenState extends State<AnimeInfoScreen> {
  Anime? _animeData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnimeInfo();
  }

  Future<void> _loadAnimeInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jikan = Jikan();
      final anime = await jikan.getAnime(widget.malId);
      
      setState(() {
        _animeData = anime;
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
                        'failed to load anime info',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _loadAnimeInfo,
                        icon: const Icon(Icons.refresh),
                        label: const Text('retry'),
                      ),
                    ],
                  ),
                )
              : _buildAnimeInfo(),
    );
  }

  Widget _buildAnimeInfo() {
    if (_animeData == null) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;
    final expandedHeight = isDesktop ? 400.0 : 300.0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: expandedHeight,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (_animeData!.imageUrl != null)
                  Image.network(
                    _animeData!.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Icon(Icons.broken_image, size: 64),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: EdgeInsets.all(isDesktop ? 24 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _animeData!.title ?? widget.animeTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                const SizedBox(height: 8),
                
                if (_animeData!.titleEnglish != null && 
                    _animeData!.titleEnglish != _animeData!.title)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _animeData!.titleEnglish!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_animeData!.score != null)
                      Chip(
                        avatar: const Icon(Icons.star, size: 16),
                        label: Text('${_animeData!.score}'),
                      ),
                    if (_animeData!.episodes != null)
                      Chip(
                        label: Text('${_animeData!.episodes} eps'),
                      ),
                    if (_animeData!.status != null)
                      Chip(
                        label: Text(_animeData!.status!),
                      ),
                    if (_animeData!.type != null)
                      Chip(
                        label: Text(_animeData!.type!),
                      ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (widget.onSearchPressed != null) {
                        final searchQuery = _animeData!.title ?? widget.animeTitle;
                        // Pop back to home (works for both single and double push)
                        Navigator.of(context).popUntil((route) {
                          return route.isFirst || route.settings.name == '/';
                        });
                        // Call the callback to switch tabs
                        widget.onSearchPressed!(searchQuery);
                      }
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('search and watch'),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Text(
                  'synopsis',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _animeData!.synopsis ?? 'No synopsis available',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                
                const SizedBox(height: 24),
                
                if (_animeData!.genres?.isNotEmpty ?? false) ...[
                  Text(
                    'genres',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _animeData!.genres!.map((genre) {
                      return Chip(
                        label: Text(genre.name ?? ''),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
                
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'aired',
                        _animeData!.aired ?? 'N/A',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCard(
                        'duration',
                        _animeData!.duration ?? 'N/A',
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'studios',
                        _animeData!.studios?.isNotEmpty ?? false
                            ? _animeData!.studios!.map((s) => s.name).join(', ')
                            : 'N/A',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCard(
                        'source',
                        _animeData!.source ?? 'N/A',
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
