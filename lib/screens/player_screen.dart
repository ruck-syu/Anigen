import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';

class PlayerScreen extends StatefulWidget {
  final String animeId;
  final Episode episode;
  final String animeTitle;
  final List<Episode> allEpisodes;

  const PlayerScreen({
    super.key,
    required this.animeId,
    required this.episode,
    required this.animeTitle,
    required this.allEpisodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;

  bool _isLoading = true;
  String? _error;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    
    try {
      player = Player();
      controller = VideoController(player);

      player.stream.error.listen((event) {
        if (mounted) {
          setState(() {
            _error = 'Player Error: $event';
          });
        }
      });

      _fetchStream();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize player: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _fetchStream() async {
    try {
      final streamData = await AnimeProvider().getStreamLink(
        widget.animeId,
        widget.episode.number,
      );

      if (!mounted) return;

      if (streamData != null && streamData['url'] != null) {
        final url = streamData['url']!;
        final referer = streamData['referer'];

        final Map<String, String> headers = {
          "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
        };
        if (referer != null) {
          headers["Referer"] = referer;
        }

        await player.open(Media(url, httpHeaders: headers));

        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'No stream found';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showSpeedDialog() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('playback speed'),
        content: SizedBox(
          width: double.minPositive,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: speeds.length,
            itemBuilder: (context, index) {
              final speed = speeds[index];
              return RadioListTile<double>(
                tileColor: Colors.transparent,
                title: Text('${speed}x'),
                value: speed,
                groupValue: _playbackSpeed,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _playbackSpeed = value;
                    });
                    player.setRate(value);
                    Navigator.pop(context);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.animeTitle),
      ),
      body: SafeArea(
        bottom: false,
        child: ClipRect(
          child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        ),
      ),
    );
  }
  
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Video player at the top
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoPlayer(),
        ),
        
        const SizedBox(height: 8),
        
        // Episode info
        _buildEpisodeInfo(),
        
        const Divider(height: 1),
        
        const SizedBox(height: 8),
        
        // Episodes list
        Expanded(
          child: _buildEpisodesList(),
        ),
      ],
    );
  }
  
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side: Video and info
        Expanded(
          flex: 7,
          child: Column(
            children: [
              // Video player
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildVideoPlayer(),
              ),
              
              const SizedBox(height: 8),
              
              // Episode info
              _buildEpisodeInfo(),
            ],
          ),
        ),
        
        // Right side: Episodes list
        SizedBox(
          width: 350,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'episodes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildEpisodesList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildVideoPlayer() {
    return Stack(
      children: [
        Container(
          color: Colors.black,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _fetchStream();
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('retry'),
                          ),
                        ],
                      ),
                    )
                  : MaterialVideoControlsTheme(
                      normal: MaterialVideoControlsThemeData(
                        primaryButtonBar: [
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.replay_10),
                            onPressed: () {
                              final currentPos = player.state.position;
                              player.seek(currentPos - const Duration(seconds: 10));
                            },
                          ),
                          const MaterialPlayOrPauseButton(),
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.forward_10),
                            onPressed: () {
                              final currentPos = player.state.position;
                              player.seek(currentPos + const Duration(seconds: 10));
                            },
                          ),
                        ],
                        topButtonBar: [
                          const Spacer(),
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.speed),
                            onPressed: () => _showSpeedDialog(),
                          ),
                        ],
                      ),
                      fullscreen: MaterialVideoControlsThemeData(
                        primaryButtonBar: [
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.replay_10),
                            onPressed: () {
                              final currentPos = player.state.position;
                              player.seek(currentPos - const Duration(seconds: 10));
                            },
                          ),
                          const MaterialPlayOrPauseButton(),
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.forward_10),
                            onPressed: () {
                              final currentPos = player.state.position;
                              player.seek(currentPos + const Duration(seconds: 10));
                            },
                          ),
                        ],
                        topButtonBar: [
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          MaterialDesktopCustomButton(
                            icon: const Icon(Icons.speed),
                            onPressed: () => _showSpeedDialog(),
                          ),
                        ],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                      ),
                      child: Video(controller: controller),
                    ),
        ),
      ],
    );
  }
  
  Widget _buildEpisodeInfo() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'episode ${widget.episode.number}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.animeTitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEpisodesList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: widget.allEpisodes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ep = widget.allEpisodes[index];
        final isCurrentEpisode = ep.number == widget.episode.number;
        
        return ListTile(
          selected: isCurrentEpisode,
          selectedTileColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Text(
            'episode ${ep.number}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isCurrentEpisode 
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: isCurrentEpisode ? FontWeight.w600 : null,
                ),
          ),
          trailing: Icon(
            isCurrentEpisode ? Icons.play_circle : Icons.play_arrow_rounded,
            color: isCurrentEpisode 
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          onTap: isCurrentEpisode ? null : () {
            // Replace current screen with new episode
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(
                  animeId: widget.animeId,
                  episode: ep,
                  animeTitle: widget.animeTitle,
                  allEpisodes: widget.allEpisodes,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
