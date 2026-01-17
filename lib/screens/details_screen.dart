import 'package:flutter/material.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/screens/player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Anime anime;

  const DetailsScreen({super.key, required this.anime});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final AnimeProvider _provider = AnimeProvider();
  List<Episode> _episodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEpisodes();
  }

  void _fetchEpisodes() async {
    try {
      final episodes = await _provider.getEpisodes(widget.anime.url);
      setState(() {
        _episodes = episodes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching episodes: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.anime.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Episodes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _episodes.length,
                    itemBuilder: (context, index) {
                      final ep = _episodes[index];
                      return ListTile(
                        title: Text('Episode ${ep.number}'),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlayerScreen(
                                animeId: widget.anime.url,
                                episode: ep,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
