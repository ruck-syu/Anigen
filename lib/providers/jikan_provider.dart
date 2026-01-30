import 'package:jikan_api/jikan_api.dart';

class JikanProvider {
  final Jikan _jikan = Jikan();

  Future<List<Anime>> getTopAnime({int page = 1}) async {
    try {
      final response = await _jikan.getTopAnime(page: page);
      return response;
    } catch (e) {
      throw Exception('Failed to fetch top anime: $e');
    }
  }

  Future<List<Anime>> getSeasonAnime({int page = 1}) async {
    try {
      final now = DateTime.now();
      final season = _getSeason(now.month);
      final response = await _jikan.getSeason(
        year: now.year,
        season: season,
        page: page,
      );
      return response;
    } catch (e) {
      throw Exception('Failed to fetch season anime: $e');
    }
  }

  Future<List<Anime>> getPopularAnime({int page = 1}) async {
    try {
      final response = await _jikan.getTopAnime(
        page: page,
        filter: TopFilter.bypopularity,
      );
      return response;
    } catch (e) {
      throw Exception('Failed to fetch popular anime: $e');
    }
  }

  Future<List<Anime>> getUpcomingAnime({int page = 1}) async {
    try {
      final response = await _jikan.getSeasonUpcoming(page: page);
      return response;
    } catch (e) {
      throw Exception('Failed to fetch upcoming anime: $e');
    }
  }

  Future<List<Anime>> getAiringToday({int page = 1}) async {
    try {
      final now = DateTime.now();
      final weekday = _getWeekday(now.weekday);
      final response = await _jikan.getSchedules(
        weekday: weekday,
        page: page,
      );
      return response;
    } catch (e) {
      throw Exception('Failed to fetch airing schedule: $e');
    }
  }

  Future<String> getAnimeMoreInfo(int malId) async {
    try {
      final response = await _jikan.getAnimeMoreInfo(malId);
      return response;
    } catch (e) {
      throw Exception('Failed to fetch anime info: $e');
    }
  }

  Future<List<Genre>> getAnimeGenres() async {
    try {
      final response = await _jikan.getAnimeGenres();
      return response;
    } catch (e) {
      throw Exception('Failed to fetch genres: $e');
    }
  }

  Future<List<Anime>> getAnimeByGenre(int genreId) async {
    try {
      final List<Anime> allAnime = [];
      int page = 1;
      
      // Fetch multiple pages to get enough anime for the genre, sorted by score
      while (allAnime.length < 50 && page <= 3) {
        final response = await _jikan.searchAnime(
          genres: [genreId],
          orderBy: 'score',
          sort: 'desc',
          page: page,
        );
        
        if (response.isEmpty) break;
        allAnime.addAll(response);
        page++;
      }
      
      return allAnime.take(50).toList();
    } catch (e) {
      throw Exception('Failed to fetch anime by genre: $e');
    }
  }

  SeasonType _getSeason(int month) {
    if (month >= 1 && month <= 3) return SeasonType.winter;
    if (month >= 4 && month <= 6) return SeasonType.spring;
    if (month >= 7 && month <= 9) return SeasonType.summer;
    return SeasonType.fall;
  }

  WeekDay _getWeekday(int day) {
    switch (day) {
      case 1:
        return WeekDay.monday;
      case 2:
        return WeekDay.tuesday;
      case 3:
        return WeekDay.wednesday;
      case 4:
        return WeekDay.thursday;
      case 5:
        return WeekDay.friday;
      case 6:
        return WeekDay.saturday;
      case 7:
        return WeekDay.sunday;
      default:
        return WeekDay.monday;
    }
  }
}
