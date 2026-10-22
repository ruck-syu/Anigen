import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/providers/anilist_client.dart';

/// The rows the home screen shows.
class AniListHomeFeed {
  final List<AniListMedia> top;
  final List<AniListMedia> airing;
  final List<AniListMedia> season;
  final List<AniListMedia> popular;
  final List<AniListMedia> movies;
  final List<AniListMedia> upcoming;
  final List<String> genres;

  const AniListHomeFeed({
    required this.top,
    required this.airing,
    required this.season,
    required this.popular,
    required this.movies,
    required this.upcoming,
    required this.genres,
  });

  bool get isEmpty =>
      top.isEmpty &&
      airing.isEmpty &&
      season.isEmpty &&
      popular.isEmpty &&
      movies.isEmpty &&
      upcoming.isEmpty;
}

/// Reads the catalogue from AniList's GraphQL API.
///
/// Every screen asks for everything it needs in one query, because AniList
/// counts requests rather than bandwidth and is currently limited to 30 a
/// minute.
class AniListProvider {
  final AniListClient _client = AniListClient.instance;

  /// Genres the app doesn't show.
  static const _hiddenGenres = {'hentai', 'ecchi'};

  static const _fields = r'''
fragment MediaFields on Media {
  id
  idMal
  title { english romaji }
  coverImage { extraLarge }
  bannerImage
  description(asHtml: false)
  averageScore
  popularity
  episodes
  duration
  genres
  format
  status
  seasonYear
  studios { nodes { name } }
}
''';

  static const _homeQuery = r'''
query HomeFeed($season: MediaSeason!, $year: Int!) {
  top: Page(perPage: 10) {
    media(type: ANIME, isAdult: false, sort: SCORE_DESC) { ...MediaFields }
  }
  airing: Page(perPage: 20) {
    media(type: ANIME, isAdult: false, status: RELEASING, sort: POPULARITY_DESC) { ...MediaFields }
  }
  season: Page(perPage: 20) {
    media(type: ANIME, isAdult: false, season: $season, seasonYear: $year, sort: POPULARITY_DESC) { ...MediaFields }
  }
  popular: Page(perPage: 20) {
    media(type: ANIME, isAdult: false, sort: POPULARITY_DESC) { ...MediaFields }
  }
  movies: Page(perPage: 20) {
    media(type: ANIME, isAdult: false, format: MOVIE, sort: SCORE_DESC) { ...MediaFields }
  }
  upcoming: Page(perPage: 20) {
    media(type: ANIME, isAdult: false, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) { ...MediaFields }
  }
  genres: GenreCollection
}
''';

  static const _genreQuery = r'''
query ByGenre($genre: String!) {
  Page(perPage: 50) {
    media(type: ANIME, isAdult: false, genre: $genre, sort: SCORE_DESC) { ...MediaFields }
  }
}
''';

  static const _searchQuery = r'''
query Search($search: String, $sort: [MediaSort], $formats: [MediaFormat],
    $status: MediaStatus, $genres: [String], $year: Int) {
  Page(perPage: 30) {
    media(type: ANIME, isAdult: false, search: $search, sort: $sort,
        format_in: $formats, status: $status, genre_in: $genres,
        seasonYear: $year) { ...MediaFields }
  }
}
''';

  /// The fields a season card shows. The relations are nested two deep, so
  /// each request walks two hops along the prequel and sequel chain.
  static const _seasonFields = r'''
fragment SeasonFields on Media {
  id
  idMal
  type
  title { english romaji }
  coverImage { extraLarge }
  format
  status
  episodes
  seasonYear
  startDate { year month day }
}
''';

  static const _seasonsQuery = r'''
query Seasons($ids: [Int]) {
  Page(perPage: 50) {
    media(id_in: $ids) {
      ...SeasonFields
      relations {
        edges {
          relationType
          node {
            ...SeasonFields
            relations { edges { relationType node { id type } } }
          }
        }
      }
    }
  }
}
''';

  static const _genresQuery = r'''
query Genres {
  GenreCollection
}
''';

  /// Everything the home screen shows, in one request.
  Future<AniListHomeFeed> getHomeFeed() async {
    final now = DateTime.now();
    final data = await _client.request(
      '$_homeQuery\n$_fields',
      variables: {'season': _seasonFor(now.month), 'year': now.year},
    );

    List<AniListMedia> row(String alias) => [
      for (final media
          in ((data[alias] as Map<String, dynamic>?)?['media'] as List? ??
              const []))
        AniListMedia.fromJson(media as Map<String, dynamic>),
    ];

    final genres = (data['genres'] as List? ?? const [])
        .cast<String>()
        .where((g) => !_hiddenGenres.contains(g.toLowerCase()))
        .toList();

    return AniListHomeFeed(
      top: row('top'),
      airing: row('airing'),
      season: row('season'),
      popular: row('popular'),
      movies: row('movies'),
      upcoming: row('upcoming'),
      genres: genres,
    );
  }

  /// Details for one title. Pass [id] for an AniList id or [malId] for a
  /// MyAnimeList id.
  Future<AniListMedia?> getMedia({int? id, int? malId}) async {
    final (document, variables) = _mediaSelection(id: id, malId: malId);
    final data = await _client.request(document, variables: variables);
    final media = data['Media'];
    if (media is! Map<String, dynamic>) return null;
    return AniListMedia.fromJson(media);
  }

  /// Titles AniList recommends alongside the given one.
  Future<List<AniListMedia>> getRecommendations({int? id, int? malId}) async {
    final (document, variables) = _recommendationSelection(
      id: id,
      malId: malId,
    );
    final data = await _client.request(document, variables: variables);
    final media = data['Media'];
    if (media is! Map<String, dynamic>) return const [];
    final nodes =
        (media['recommendations'] as Map<String, dynamic>?)?['nodes']
            as List? ??
        const [];
    return [
      for (final node in nodes)
        if ((node as Map<String, dynamic>)['mediaRecommendation']
            is Map<String, dynamic>)
          AniListMedia.fromJson(
            node['mediaRecommendation'] as Map<String, dynamic>,
          ),
    ];
  }

  /// Every season of the show [id] belongs to, oldest first.
  ///
  /// AniList has no notion of a show's seasons, only prequel and sequel links
  /// between titles, so the chain is followed outwards in both directions.
  /// Each request covers two hops, so even a long show takes a few requests.
  Future<List<AniListMedia>> getSeasons(int id) async {
    final found = <int, Map<String, dynamic>>{};
    var frontier = <int>{id};

    void visit(Map<String, dynamic> media) {
      found[media['id'] as int] = media;
      final edges =
          (media['relations'] as Map<String, dynamic>?)?['edges'] as List? ??
          const [];
      for (final edge in edges.cast<Map<String, dynamic>>()) {
        final node = edge['node'] as Map<String, dynamic>?;
        if (node == null ||
            node['type'] != 'ANIME' ||
            found.containsKey(node['id']) ||
            (edge['relationType'] != 'PREQUEL' &&
                edge['relationType'] != 'SEQUEL')) {
          continue;
        }
        // Nodes one hop out come with their own fields and links; the ones
        // past them only have an id and are fetched in the next round.
        if (node.containsKey('format') && node.containsKey('relations')) {
          visit(node);
        } else {
          frontier.add(node['id'] as int);
        }
      }
    }

    for (var round = 0; round < 6 && frontier.isNotEmpty; round++) {
      final data = await _client.request(
        '$_seasonsQuery\n$_seasonFields',
        variables: {'ids': frontier.toList()},
      );
      frontier = {};
      final media =
          (data['Page'] as Map<String, dynamic>?)?['media'] as List? ??
          const [];
      for (final m in media.cast<Map<String, dynamic>>()) {
        visit(m);
      }
      frontier.removeAll(found.keys);
    }

    final ordered = found.values.toList()
      ..sort((a, b) => _startKey(a).compareTo(_startKey(b)));
    return [for (final m in ordered) AniListMedia.fromJson(m)];
  }

  /// Sorts by first air date, with titles that have no date yet last.
  static int _startKey(Map<String, dynamic> media) {
    final date = media['startDate'] as Map<String, dynamic>? ?? const {};
    final year = date['year'] as int?;
    if (year == null) return 1 << 30;
    return year * 10000 +
        ((date['month'] as int?) ?? 12) * 100 +
        ((date['day'] as int?) ?? 31);
  }

  /// Every genre AniList knows about.
  Future<List<String>> getGenres() async {
    final data = await _client.request(_genresQuery);
    return (data['GenreCollection'] as List? ?? const [])
        .cast<String>()
        .where((g) => !_hiddenGenres.contains(g.toLowerCase()))
        .toList();
  }

  /// The highest rated titles in a genre.
  Future<List<AniListMedia>> getAnimeByGenre(String genre) async {
    final data = await _client.request(
      '$_genreQuery\n$_fields',
      variables: {'genre': genre},
    );
    final page = data['Page'];
    if (page is! Map<String, dynamic>) return const [];
    return [
      for (final media in (page['media'] as List? ?? const []))
        AniListMedia.fromJson(media as Map<String, dynamic>),
    ];
  }

  /// Titles matching [query] and [filter]. Either may be empty, so the
  /// filter alone can be used to browse.
  Future<List<AniListMedia>> search(
    String query, {
    SearchFilter filter = const SearchFilter(),
  }) async {
    final data = await _client.request(
      '$_searchQuery\n$_fields',
      // Unset filters are left out rather than sent as null.
      variables: {
        if (query.isNotEmpty) 'search': query,
        'sort': [
          query.isNotEmpty && filter.sort == SearchFilter.defaultSort
              ? 'SEARCH_MATCH'
              : filter.sort,
        ],
        if (filter.formats.isNotEmpty) 'formats': filter.formats.toList(),
        if (filter.status != null) 'status': filter.status,
        if (filter.genres.isNotEmpty) 'genres': filter.genres.toList(),
        if (filter.year != null) 'year': filter.year,
      },
    );
    final page = data['Page'];
    if (page is! Map<String, dynamic>) return const [];
    return [
      for (final media in (page['media'] as List? ?? const []))
        AniListMedia.fromJson(media as Map<String, dynamic>),
    ];
  }

  /// AniList answers 404 when [Media] is given an id that is null next to an
  /// idMal, so only the argument that is actually known is sent.
  (String, Map<String, dynamic>) _mediaSelection({int? id, int? malId}) {
    if (id != null) {
      return (
        r'query MediaDetails($id: Int!) { Media(id: $id) { ...MediaFields } }'
            '\n$_fields',
        {'id': id},
      );
    }
    return (
      r'query MediaDetails($malId: Int!) { Media(idMal: $malId) { ...MediaFields } }'
          '\n$_fields',
      {'malId': malId},
    );
  }

  (String, Map<String, dynamic>) _recommendationSelection({
    int? id,
    int? malId,
  }) {
    final head = id != null
        ? r'query Recommendations($id: Int!) { Media(id: $id) {'
        : r'query Recommendations($malId: Int!) { Media(idMal: $malId) {';
    final document =
        '$head recommendations(sort: RATING_DESC) { nodes { mediaRecommendation { ...MediaFields } } } } }\n$_fields';
    return (document, id != null ? {'id': id} : {'malId': malId});
  }

  /// AniList counts winter as January to March, spring as April to June,
  /// summer as July to September and fall as October to December.
  static String _seasonFor(int month) {
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
  }
}

/// Search filters, in AniList's own values.
class SearchFilter {
  /// Best match while there's a query, most popular otherwise.
  static const defaultSort = 'POPULARITY_DESC';

  static const sorts = {
    'POPULARITY_DESC': 'popular',
    'SCORE_DESC': 'top rated',
    'TRENDING_DESC': 'trending',
    'START_DATE_DESC': 'newest',
  };
  static const formatLabels = {
    'TV': 'tv',
    'MOVIE': 'movie',
    'OVA': 'ova',
    'ONA': 'ona',
    'SPECIAL': 'special',
  };
  static const statusLabels = {
    'RELEASING': 'airing',
    'FINISHED': 'finished',
    'NOT_YET_RELEASED': 'upcoming',
  };

  final String sort;
  final Set<String> formats;
  final String? status;
  final Set<String> genres;
  final int? year;

  const SearchFilter({
    this.sort = defaultSort,
    this.formats = const {},
    this.status,
    this.genres = const {},
    this.year,
  });

  /// How many filters are set, for the badge on the filter button.
  int get count =>
      (sort == defaultSort ? 0 : 1) +
      formats.length +
      (status == null ? 0 : 1) +
      genres.length +
      (year == null ? 0 : 1);

  bool get isEmpty => count == 0;
}
