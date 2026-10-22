/// A title as AniList describes it.
///
/// [malId] is the MyAnimeList id AniList knows for the same title. The app
/// keeps using it for skip times and to remember which stream source was
/// picked for a title, so it is carried through everywhere.
class AniListMedia {
  final int id;
  final int? malId;
  final String title;

  /// The original (usually Japanese) title, shown as a subtitle.
  final String? titleRomaji;

  /// The biggest poster AniList has, 460x690.
  final String? image;

  /// Landscape art, 1900x400. Used as the backdrop behind the hero.
  final String? banner;

  final String? description;

  /// Average user score, 0-100.
  final int? score;

  final int? popularity;
  final int? episodes;

  /// Episode length in minutes.
  final int? duration;

  final List<String> genres;

  /// TV, MOVIE, OVA, ONA, SPECIAL or MUSIC.
  final String? format;

  /// RELEASING, FINISHED, NOT_YET_RELEASED, CANCELLED, HIATUS.
  final String? status;

  final int? seasonYear;
  final List<String> studios;

  const AniListMedia({
    required this.id,
    this.malId,
    required this.title,
    this.titleRomaji,
    this.image,
    this.banner,
    this.description,
    this.score,
    this.popularity,
    this.episodes,
    this.duration,
    this.genres = const [],
    this.format,
    this.status,
    this.seasonYear,
    this.studios = const [],
  });

  /// Score on a 0-10 scale, the way the app shows it.
  double? get scoreOutOfTen => score == null ? null : score! / 10;

  bool get isAiring => status == 'RELEASING';

  factory AniListMedia.fromJson(Map<String, dynamic> json) {
    final titles = json['title'] as Map<String, dynamic>? ?? const {};
    final cover = json['coverImage'] as Map<String, dynamic>? ?? const {};
    final studioNodes =
        (json['studios'] as Map<String, dynamic>?)?['nodes'] as List? ??
        const [];
    final english = titles['english'] as String?;
    final romaji = titles['romaji'] as String?;
    return AniListMedia(
      id: json['id'] as int? ?? 0,
      malId: json['idMal'] as int?,
      title: english ?? romaji ?? 'unknown',
      titleRomaji: romaji,
      image: cover['extraLarge'] as String?,
      banner: json['bannerImage'] as String?,
      description: json['description'] as String?,
      score: json['averageScore'] as int?,
      popularity: json['popularity'] as int?,
      episodes: json['episodes'] as int?,
      duration: json['duration'] as int?,
      genres: (json['genres'] as List?)?.cast<String>() ?? const <String>[],
      format: json['format'] as String?,
      status: json['status'] as String?,
      seasonYear: json['seasonYear'] as int?,
      studios: [
        for (final node in studioNodes)
          if ((node as Map<String, dynamic>)['name'] is String)
            node['name'] as String,
      ],
    );
  }
}
