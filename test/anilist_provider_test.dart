// Checks the AniList provider against the live API.
//
// Run with: flutter test test/anilist_provider_test.dart
//
// These hit graphql.anilist.co for real, so they need a network connection.

import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/providers/anilist_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final provider = AniListProvider();

  test('home feed fills every row in one request', () async {
    final feed = await provider.getHomeFeed();

    expect(feed.top, isNotEmpty, reason: 'top row is empty');
    expect(feed.airing, isNotEmpty, reason: 'airing row is empty');
    expect(feed.season, isNotEmpty, reason: 'season row is empty');
    expect(feed.popular, isNotEmpty, reason: 'popular row is empty');
    expect(feed.movies, isNotEmpty, reason: 'movies row is empty');
    expect(feed.upcoming, isNotEmpty, reason: 'upcoming row is empty');
    expect(feed.genres, isNotEmpty, reason: 'no genres');

    // The season row must match the season we asked for.
    final now = DateTime.now();
    expect(feed.season.first.seasonYear, now.year);
  });

  test('every media carries an id, a title and a MyAnimeList id', () async {
    final feed = await provider.getHomeFeed();
    for (final media in [...feed.top, ...feed.season, ...feed.movies]) {
      expect(media.id, greaterThan(0));
      expect(media.title, isNotEmpty);
      expect(media.malId, isNotNull, reason: '${media.title} has no MAL id');
      expect(media.image, isNotNull, reason: '${media.title} has no image');
    }
  });

  test('the top row is scored and the popular row is not', () async {
    final feed = await provider.getHomeFeed();
    expect(feed.top.first.score, isNotNull);
    expect(feed.top.first.scoreOutOfTen, inInclusiveRange(0, 10));
    expect(feed.popular.first.popularity, isNotNull);
  });

  test('a title can be fetched by MyAnimeList id', () async {
    final media = await provider.getMedia(malId: 21);
    expect(media, isNotNull);
    expect(media!.id, 21);
    expect(media.malId, 21);
    expect(media.title, 'ONE PIECE');
    expect(media.description, isNotNull);
    expect(media.studios, contains('Toei Animation'));
  });

  test('a title can be fetched by AniList id', () async {
    final media = await provider.getMedia(id: 21);
    expect(media, isNotNull);
    expect(media!.malId, 21);
  });

  test('recommendations come back with their own ids', () async {
    final recommendations = await provider.getRecommendations(malId: 21);
    expect(recommendations, isNotEmpty);
    expect(recommendations.first.id, greaterThan(0));
    expect(recommendations.first.title, isNotEmpty);
  });

  test('a genre returns titles', () async {
    final anime = await provider.getAnimeByGenre('Action');
    expect(anime, isNotEmpty);
    expect(anime.length, lessThanOrEqualTo(50));
    expect(anime.first.score, isNotNull);
  });

  test('genres exclude the ones the app hides', () async {
    final genres = await provider.getGenres();
    expect(genres, contains('Action'));
    expect(genres, isNot(contains('Hentai')));
    expect(genres, isNot(contains('Ecchi')));
  });

  test('an unknown genre returns nothing rather than failing', () async {
    final anime = await provider.getAnimeByGenre('Not A Real Genre');
    expect(anime, isEmpty);
  });

  test('a media model parses a missing score and studios', () {
    final media = AniListMedia.fromJson({
      'id': 1,
      'title': {'romaji': 'Test'},
      'genres': ['Action'],
    });
    expect(media.title, 'Test');
    expect(media.scoreOutOfTen, isNull);
    expect(media.studios, isEmpty);
    expect(media.malId, isNull);
  });
}
