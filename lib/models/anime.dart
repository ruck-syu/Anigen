class Anime {
  final String title;
  final String url;
  final String? thumbnail;

  /// The romanised Japanese title the site shows alongside [title].
  final String? japaneseTitle;

  /// Episodes the site has, the most of sub, dub and total.
  final int? episodes;

  /// As the site writes it: TV, Movie, OVA, ONA, Special...
  final String? type;

  Anime({
    required this.title,
    required this.url,
    this.thumbnail,
    this.japaneseTitle,
    this.episodes,
    this.type,
  });
}

class Episode {
  final String number;
  final String url;

  Episode({required this.number, required this.url});
}
