class Anime {
  final String title;
  final String url;
  final String? thumbnail;

  Anime({
    required this.title,
    required this.url,
    this.thumbnail,
  });
}

class Episode {
  final String number;
  final String url;

  Episode({required this.number, required this.url});
}
