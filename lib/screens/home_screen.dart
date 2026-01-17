import 'package:flutter/material.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/anime_provider.dart';
import 'package:anigen/screens/details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AnimeProvider _provider = AnimeProvider();
  final TextEditingController _searchController = TextEditingController();
  List<Anime> _results = [];
  bool _isLoading = false;

  void _search() async {
    if (_searchController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _provider.search(_searchController.text);
      setState(() {
        _results = results;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anigen'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Anime...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final anime = _results[index];
                      return ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text(anime.title),
                        onTap: () {
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
        ],
      ),
    );
  }
}