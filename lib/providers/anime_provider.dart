import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/anime.dart';

class AnimeProvider {
  static const String _allAnimeBase = "allanime.day";
  static const String _allAnimeApi = "https://api.$_allAnimeBase";
  static const String _allAnimeRefr = "https://allmanga.to";
  static const String _agent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0";

  Future<List<Anime>> search(String query) async {
    const String searchGql = r'''
      query( $search: SearchInput $limit: Int $page: Int $translationType: VaildTranslationTypeEnumType $countryOrigin: VaildCountryOriginEnumType ) {
        shows( search: $search limit: $limit page: $page translationType: $translationType countryOrigin: $countryOrigin ) {
          edges { _id name availableEpisodes __typename }
        }
      }
    ''';

    final Uri url = Uri.parse("$_allAnimeApi/api");
    final Map<String, dynamic> variables = {
      "search": {"allowAdult": false, "allowUnknown": false, "query": query},
      "limit": 40,
      "page": 1,
      "translationType": "sub",
      "countryOrigin": "ALL",
    };

    final http.Response response = await http.get(
      url.replace(
        queryParameters: {
          "variables": jsonEncode(variables),
          "query": searchGql,
        },
      ),
      headers: {"User-Agent": _agent, "Referer": _allAnimeRefr},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> edges = data['data']['shows']['edges'];

      return edges.map((edge) {
        return Anime(
          title: edge['name'],
          url: edge['_id'], // Using ID as the identifier
        );
      }).toList();
    } else {
      throw Exception('Failed to search anime');
    }
  }

  Future<List<Episode>> getEpisodes(String animeId) async {
    const String episodesListGql = r'''
      query ($showId: String!) {
        show( _id: $showId ) { _id availableEpisodesDetail }
      }
    ''';

    final Uri url = Uri.parse("$_allAnimeApi/api");
    final Map<String, dynamic> variables = {"showId": animeId};

    final http.Response response = await http.get(
      url.replace(
        queryParameters: {
          "variables": jsonEncode(variables),
          "query": episodesListGql,
        },
      ),
      headers: {"User-Agent": _agent, "Referer": _allAnimeRefr},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final Map<String, dynamic> details =
          data['data']['show']['availableEpisodesDetail'];

      // Extract 'sub' episodes
      final List<dynamic> subEpisodes = details['sub'] ?? [];

      // Sort episodes numerically if possible, otherwise keep order
      subEpisodes.sort((a, b) {
        try {
          return double.parse(a).compareTo(double.parse(b));
        } catch (e) {
          return 0;
        }
      });

      return subEpisodes.map((ep) {
        return Episode(
          number: ep.toString(),
          url: ep
              .toString(), // Episode number serves as identifier for fetching link
        );
      }).toList();
    } else {
      throw Exception('Failed to get episodes');
    }
  }

  Future<Map<String, String>?> getStreamLink(
    String animeId,
    String episodeNumber,
  ) async {
    const String episodeEmbedGql = r'''
      query ($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) {
        episode( showId: $showId translationType: $translationType episodeString: $episodeString ) {
          episodeString sourceUrls
        }
      }
    ''';

    final Uri url = Uri.parse("$_allAnimeApi/api");
    final Map<String, dynamic> variables = {
      "showId": animeId,
      "translationType": "sub",
      "episodeString": episodeNumber,
    };

    final http.Response response = await http.get(
      url.replace(
        queryParameters: {
          "variables": jsonEncode(variables),
          "query": episodeEmbedGql,
        },
      ),
      headers: {"User-Agent": _agent, "Referer": _allAnimeRefr},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> sourceUrls = data['data']['episode']['sourceUrls'];

      // Filter for known good providers as used by ani-cli
      // 1) Default (WixMP)
      // 2) Yt-mp4
      // 3) S-mp4
      // 4) Luf-Mp4
      final allowedProviders = ['Default', 'S-mp4', 'Luf-Mp4', 'Yt-mp4'];

      Map<String, String>? fallbackResult;

      for (var source in sourceUrls) {
        String? sourceName = source['sourceName'];

        // Skip providers that are not in our allowed list
        if (sourceName == null || !allowedProviders.contains(sourceName)) {
          continue;
        }

        String? sourceUrl = source['sourceUrl'];
        if (sourceUrl != null && sourceUrl.startsWith('--')) {
          sourceUrl = _decodeSourceUrl(sourceUrl);
        }

        if (sourceUrl != null && sourceUrl.startsWith('http')) {
          if (sourceUrl.contains('repackager.wixmp.com')) {
            // ani-cli logic: sed 's|repackager.wixmp.com/||g;s|\.urlset.*||g'
            // This effectively extracts the underlying direct link
            String processed = sourceUrl
                .replaceAll('repackager.wixmp.com/', '')
                .replaceAll(RegExp(r'\.urlset.*'), '');
            return {"url": processed};
          }
          return {"url": sourceUrl};
        }

        if (sourceUrl != null) {
          // It's likely a relative path like /clock?id=...
          try {
            final Uri fetchUrl = Uri.parse("https://$_allAnimeBase$sourceUrl");

            final http.Response streamResponse = await http.get(
              fetchUrl,
              headers: {"User-Agent": _agent, "Referer": _allAnimeRefr},
            );

            if (streamResponse.statusCode == 200) {
              Map<String, String>? currentResult;
              final Map<String, dynamic> streamData = jsonDecode(
                streamResponse.body,
              );

              String? extractedReferer;
              for (var key in streamData.keys) {
                if (key.toLowerCase() == 'referer') {
                  extractedReferer = streamData[key]?.toString();
                }
              }

              if (streamData['links'] != null && streamData['links'] is List) {
                final List<dynamic> links = streamData['links'];
                for (var linkObj in links) {
                  if (linkObj['link'] != null &&
                      linkObj['link'].toString().startsWith('http')) {
                    String resolved = await _resolveUrl(linkObj['link']);
                    currentResult = {"url": resolved};
                    break;
                  }
                  if (linkObj['hls'] != null &&
                      linkObj['hls'] is Map &&
                      linkObj['hls']['url'] != null) {
                    String resolved = await _resolveUrl(linkObj['hls']['url']);
                    currentResult = {"url": resolved};
                    break;
                  }
                }
              }

              if (currentResult == null &&
                  streamData['hls'] != null &&
                  streamData['hls'] is Map &&
                  streamData['hls']['url'] != null) {
                String resolved = await _resolveUrl(streamData['hls']['url']);
                currentResult = {"url": resolved};
              }

              if (currentResult != null) {
                if (extractedReferer != null) {
                  currentResult["referer"] = extractedReferer;
                  // Found a valid link but it needs referer. Keep as fallback.
                  fallbackResult ??= currentResult;
                } else {
                  // Found a clean link without referer! Return immediately.
                  return currentResult;
                }
              }
            }
          } catch (e) {
            // Error fetching stream, continue to next source
            continue;
          }
        }
      }

      // If we finished the loop and didn't find a clean link, return the fallback (referrer-required) link if we found one.
      return fallbackResult;
    } else {
      throw Exception('Failed to get stream link');
    }
  }

  Future<String> _resolveUrl(String url) async {
    // Optimization: If it looks like a direct link and not a known redirector, return it.
    if ((url.endsWith('.mp4') || url.endsWith('.m3u8')) &&
        !url.contains('uns.bio')) {
      return url;
    }

    String currentUrl = url;
    int redirectCount = 0;
    const int maxRedirects = 10;
    final client = http.Client();

    try {
      while (redirectCount < maxRedirects) {
        final Uri uri = Uri.parse(currentUrl);
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll({"User-Agent": _agent, "Referer": _allAnimeRefr});

        final response = await client.send(request);

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            if (location.startsWith('/')) {
              currentUrl = uri.resolve(location).toString();
            } else {
              currentUrl = location;
            }
            redirectCount++;
            continue;
          }
        }

        // If it's a 200 OK or we stopped redirecting, this is likely the final URL.
        // However, we should check if the final URL is actually different.
        return currentUrl;
      }
    } catch (e) {
      return currentUrl;
    } finally {
      client.close();
    }
    return currentUrl;
  }

  String _decodeSourceUrl(String input) {
    if (input.startsWith('--')) {
      input = input.substring(2);
    }

    final Map<String, String> map = {
      '01': '9',
      '08': '0',
      '09': '1',
      '0a': '2',
      '0b': '3',
      '0c': '4',
      '0d': '5',
      '0e': '6',
      '0f': '7',
      '00': '8',
      '59': 'a',
      '5a': 'b',
      '5b': 'c',
      '5c': 'd',
      '5d': 'e',
      '5e': 'f',
      '5f': 'g',
      '50': 'h',
      '51': 'i',
      '52': 'j',
      '53': 'k',
      '54': 'l',
      '55': 'm',
      '56': 'n',
      '57': 'o',
      '48': 'p',
      '49': 'q',
      '4a': 'r',
      '4b': 's',
      '4c': 't',
      '4d': 'u',
      '4e': 'v',
      '4f': 'w',
      '40': 'x',
      '41': 'y',
      '42': 'z',
      '79': 'A',
      '7a': 'B',
      '7b': 'C',
      '7c': 'D',
      '7d': 'E',
      '7e': 'F',
      '7f': 'G',
      '70': 'H',
      '71': 'I',
      '72': 'J',
      '73': 'K',
      '74': 'L',
      '75': 'M',
      '76': 'N',
      '77': 'O',
      '68': 'P',
      '69': 'Q',
      '6a': 'R',
      '6b': 'S',
      '6c': 'T',
      '6d': 'U',
      '6e': 'V',
      '6f': 'W',
      '60': 'X',
      '61': 'Y',
      '62': 'Z',
      '15': '-',
      '16': '.',
      '67': '_',
      '46': '~',
      '02': ':',
      '17': '/',
      '07': '?',
      '1b': '#',
      '63': '[',
      '65': ']',
      '78': '@',
      '19': '!',
      '1c': '\$',
      '1e': '&',
      '10': '(',
      '11': ')',
      '12': '*',
      '13': '+',
      '14': ',',
      '03': ';',
      '05': '=',
      '1d': '%',
    };

    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < input.length; i += 2) {
      if (i + 2 <= input.length) {
        String segment = input.substring(i, i + 2);
        buffer.write(map[segment] ?? segment);
      }
    }

    String result = buffer.toString();
    if (result.contains('/clock')) {
      result = result.replaceFirst('/clock', '/clock.json');
    }
    return result;
  }
}
