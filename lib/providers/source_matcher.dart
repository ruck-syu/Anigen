import '../models/anime.dart';

/// Picks the search result that is the same show as an AniList entry.
///
/// Titles alone aren't enough: a search for "Jujutsu Kaisen" lists the
/// third season before the first, which the site calls "Jujutsu Kaisen
/// (TV)". So each result is scored on how close its title is, then on
/// whether its episode count and format agree with AniList's.
class SourceMatcher {
  /// The show's names on AniList: English, romaji, whatever was clicked.
  final Set<String> names;

  /// AniList's episode count, null while unknown.
  final int? episodes;

  /// AniList's format: TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL, MUSIC.
  final String? format;

  /// Still airing, so the site may not have every episode yet.
  final bool airing;

  SourceMatcher({
    required Iterable<String> names,
    this.episodes,
    this.format,
    this.airing = false,
  }) : names = {for (final n in names) _normalise(n)}..remove('');

  /// Same title, same episode count, same format: no need to search further.
  static const confident = 1.5;

  double score(Anime anime) {
    final titles = {
      _normalise(anime.title),
      if (anime.japaneseTitle != null) _normalise(anime.japaneseTitle!),
    };
    var best = 0.0;
    for (final name in names) {
      for (final title in titles) {
        final s = _similarity(name, title);
        if (s > best) best = s;
      }
    }
    return best + _episodeScore(anime.episodes) + _formatScore(anime.type);
  }

  /// The best of [results], earlier ones winning ties. Null if none is
  /// anything like the show.
  ({Anime anime, double score})? best(Iterable<Anime> results) {
    ({Anime anime, double score})? best;
    for (final anime in results) {
      final s = score(anime);
      if (best == null || s > best.score) best = (anime: anime, score: s);
    }
    return best == null || best.score <= 0 ? null : best;
  }

  double _episodeScore(int? found) {
    final expected = episodes;
    if (expected == null || found == null) return 0;
    if (found == expected) return 0.4;
    // An airing season fills in over the weeks
    if (airing && found < expected) return 0.1;
    // Off by a recap or a bonus episode is still probably the show
    if ((found - expected).abs() <= 1) return 0.1;
    return -0.4;
  }

  double _formatScore(String? type) {
    final expected = switch (format) {
      'TV' || 'TV_SHORT' => 'tv',
      'MOVIE' => 'movie',
      'OVA' => 'ova',
      'ONA' => 'ona',
      'SPECIAL' => 'special',
      'MUSIC' => 'music',
      _ => null,
    };
    if (expected == null || type == null) return 0;
    return type.toLowerCase() == expected ? 0.1 : -0.15;
  }

  /// Lower case words, with the site's "(TV)" tag dropped and "2nd Season"
  /// written the same way as "Season 2".
  static String _normalise(String title) => title
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'\((tv|uncensored|dub|sub)\)'), ' ')
      .replaceAllMapped(
        RegExp(r'\b(\d+)(?:st|nd|rd|th) season\b'),
        (m) => 'season ${m[1]}',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// 1 for the same words, falling with each word one has and the other
  /// doesn't (Dice coefficient).
  static double _similarity(String a, String b) {
    if (a == b) return 1;
    final x = a.split(' ').toSet();
    final y = b.split(' ').toSet();
    final shared = x.intersection(y).length;
    return 2 * shared / (x.length + y.length);
  }
}
