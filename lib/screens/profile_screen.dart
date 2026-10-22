import 'package:flutter/material.dart';
import 'package:anigen/providers/scraper_config.dart';
import 'package:anigen/providers/scraper_config_store.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

/// "My Anigen": continue watching, My List and settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _library = LibraryStore.instance;
  ScraperConfig? _config;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await ScraperConfigStore.get();
    if (mounted) {
      setState(() {
        _config = config;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isUpdating = true;
    });
    final updated = await ScraperConfigStore.refresh();
    await _loadConfig();
    if (!mounted) return;
    setState(() {
      _isUpdating = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated ? 'scraper updated' : 'scraper is up to date'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 900 ? 24.0 : 16.0;
    final posterWidth = width >= 900 ? 140.0 : 112.0;

    return Scaffold(
      appBar: AppBar(title: const Text('my anigen')),
      body: ListenableBuilder(
        listenable: _library,
        builder: (context, _) {
          final history = _library.continueWatching;
          final myList = _library.myList;
          return ListView(
            children: [
              if (history.isEmpty && myList.isEmpty)
                Padding(
                  padding: EdgeInsets.all(padding * 2),
                  child: Text(
                    'shows you watch and add to your list will show up here',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              CardRow(
                title: 'continue watching',
                padding: padding,
                height: 200 * 9 / 16 + 40,
                itemCount: history.length,
                itemBuilder: (context, i) => ContinueCard(
                  entry: history[i],
                  width: 200,
                  onTap: () =>
                      openTitle(context, history[i].title, autoplay: true),
                  onInfo: () => openTitle(context, history[i].title),
                  onRemove: () =>
                      _library.removeFromHistory(history[i].title.animeId!),
                ),
              ),
              CardRow(
                title: 'my list',
                padding: padding,
                height: posterWidth * 3 / 2 + 42,
                itemCount: myList.length,
                itemBuilder: (context, i) => PosterCard(
                  title: myList[i].title,
                  image: myList[i].image,
                  width: posterWidth,
                  onTap: () => openTitle(context, myList[i]),
                  onLongPress: () => _library.toggleMyList(myList[i]),
                ),
              ),
              SectionHeader('playback', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        tileColor: Colors.transparent,
                        secondary: const Icon(Icons.playlist_play),
                        title: const Text('autoplay next episode'),
                        value: _library.autoplay,
                        onChanged: _library.setAutoplay,
                      ),
                      SwitchListTile(
                        tileColor: Colors.transparent,
                        secondary: const Icon(Icons.fast_forward),
                        title: const Text('skip intros automatically'),
                        value: _library.autoSkipIntro,
                        onChanged: _library.setAutoSkipIntro,
                      ),
                    ],
                  ),
                ),
              ),
              SectionHeader('source', padding: padding),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update_alt),
                    title: const Text('scraper'),
                    subtitle: Text(
                      config == null
                          ? 'loading...'
                          : 'ani-cli ${config.aniCliVersion} · config v${config.configVersion}\n'
                                '${Uri.parse(config.baseUrl).host}',
                    ),
                    isThreeLine: true,
                    trailing: _isUpdating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'check for update',
                            onPressed: _checkForUpdate,
                          ),
                  ),
                ),
              ),
              SizedBox(height: bottomInset(context) + 24),
            ],
          );
        },
      ),
    );
  }
}
