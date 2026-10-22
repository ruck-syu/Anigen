import '../models/anime.dart';
import 'hianime_scraper.dart';
import 'scraper_config_store.dart';

class AnimeProvider {
  /// hianime ids are slugs ending in a numeric id. Anything else is an id
  /// saved by an older version of the app (AllAnime) and can't be resolved.
  static bool isSupportedId(String animeId) =>
      RegExp(r'-\d+$').hasMatch(animeId);

  /// Runs [action] with the current scraper config. If it fails, pulls the
  /// latest config from the repo and, if that changed anything, tries again.
  Future<T> _withConfig<T>(
    Future<T> Function(HianimeScraper scraper) action, {
    bool Function(T result)? isFailure,
  }) async {
    late T result;
    Object? error;
    try {
      result = await action(HianimeScraper(await ScraperConfigStore.get()));
      if (isFailure == null || !isFailure(result)) return result;
    } catch (e) {
      error = e;
    }

    if (await ScraperConfigStore.refresh()) {
      return action(HianimeScraper(await ScraperConfigStore.get()));
    }
    if (error != null) throw error;
    return result;
  }

  Future<List<Anime>> search(String query) {
    return _withConfig((scraper) => scraper.search(query));
  }

  Future<List<Episode>> getEpisodes(String animeId) {
    if (!isSupportedId(animeId)) {
      throw Exception(
        'This entry is from an older version, search for it again',
      );
    }
    return _withConfig(
      (scraper) => scraper.getEpisodes(animeId),
      isFailure: (episodes) => episodes.isEmpty,
    );
  }

  Future<Map<String, String>?> getStreamLink(
    String animeId,
    String episodeNumber, {
    String? episodeId,
  }) {
    return _withConfig(
      (scraper) =>
          scraper.getStreamLink(animeId, episodeNumber, episodeId: episodeId),
      isFailure: (result) => result == null,
    );
  }
}
