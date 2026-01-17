import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';

class PlayerScreen extends StatefulWidget {
  final String animeId;
  final Episode episode;

  const PlayerScreen({super.key, required this.animeId, required this.episode});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Episode ${widget.episode.number}')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      _fetchStream();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              )
            : Video(controller: controller),
      ),
    );
  }
}
