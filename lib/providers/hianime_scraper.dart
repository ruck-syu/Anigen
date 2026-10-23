import 'dart:convert';
import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../models/anime.dart';
import 'scraper_config.dart';

/// Port of the hianime scraper from ani-cli (see `aniCliVersion` in the
/// config). All site-specific values come from [ScraperConfig].
class HianimeScraper {
  final ScraperConfig config;

  HianimeScraper(this.config);

  Future<String> _get(String url, {String? referer}) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            "User-Agent": config.userAgent,
            if (referer != null) "Referer": referer,
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.body.contains('<title>Just a moment')) {
      throw Exception('Blocked by Cloudflare');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} from $url');
    }
    return response.body;
  }

  /// The episode/server APIs return JSON with the markup in an `html` field.
  Future<dom.Document> _getHtmlFragment(String url) async {
    final Map<String, dynamic> data = jsonDecode(await _get(url));
    return html_parser.parse(data['html'] as String? ?? '');
  }

  Future<List<Anime>> search(String query) async {
    final page = await _get(
      config.buildUrl(config.searchUrl, {'query': query}),
    );
    final document = html_parser.parse(page);

    final results = <Anime>[];
    for (final item in document.querySelectorAll(config.searchItemSelector)) {
      final link = item.querySelector(config.searchTitleSelector);
      final href = link?.attributes['href'];
      if (link == null || href == null) continue;

      final slug = Uri.parse(href).pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      if (slug.isEmpty) continue;

      final poster = item.querySelector(config.searchPosterSelector);
      final counts = [
        for (final tick in item.querySelectorAll(config.searchEpisodesSelector))
          ?int.tryParse(tick.text.trim()),
      ];
      final type = item.querySelector(config.searchTypeSelector)?.text.trim();
      final japanese = link.attributes[config.searchJapaneseTitleAttribute]
          ?.trim();
      results.add(
        Anime(
          title: link.attributes['title'] ?? link.text.trim(),
          url: slug, // e.g. "frieren-beyond-journeys-end-481"
          thumbnail:
              poster?.attributes['data-src'] ?? poster?.attributes['src'],
          japaneseTitle: japanese == null || japanese.isEmpty ? null : japanese,
          episodes: counts.isEmpty ? null : counts.reduce(math.max),
          type: type == null || type.isEmpty ? null : type,
        ),
      );
    }
    return results;
  }

  Future<List<Episode>> getEpisodes(String animeId) async {
    final document = await _getHtmlFragment(
      config.buildUrl(config.episodesUrl, {'id': animeId.split('-').last}),
    );

    final episodes = <Episode>[];
    for (final item in document.querySelectorAll(config.episodeItemSelector)) {
      final number = item.attributes['data-number'];
      final id = item.attributes['data-id'];
      final href = item.attributes['href'] ?? '';
      // Numeric ids are shared with other slugs, so make sure the episode
      // links back to this show (same check as ani-cli)
      if (number == null || id == null || !href.contains('/watch/$animeId?')) {
        continue;
      }
      episodes.add(Episode(number: number, url: id));
    }

    episodes.sort((a, b) {
      final x = double.tryParse(a.number);
      final y = double.tryParse(b.number);
      return x != null && y != null ? x.compareTo(y) : 0;
    });
    return episodes;
  }

  /// Returns `url` (HLS master playlist), `referer`, `userAgent` and, when
  /// available, `subtitle` (the default WebVTT), `subtitles` (every track, as
  /// JSON `[{src, label, default}]`) and `malId` (from the embed URL, used for
  /// intro/outro skip times). Null if no supported server is found.
  Future<Map<String, String>?> getStreamLink(
    String animeId,
    String episodeNumber, {
    String? episodeId,
  }) async {
    episodeId ??= (await getEpisodes(
      animeId,
    )).where((e) => e.number == episodeNumber).firstOrNull?.url;
    if (episodeId == null) return null;

    final document = await _getHtmlFragment(
      config.buildUrl(config.serversUrl, {'episodeId': episodeId}),
    );
    final servers = document
        .querySelectorAll(config.serverItemSelector)
        .where((s) => s.attributes['data-type'] == config.translationType)
        .toList();

    // Try servers in the order the config lists them
    for (final name in config.serverNames) {
      for (final server in servers) {
        final hash = server.attributes['data-hash'];
        if (server.attributes['data-server-name'] != name || hash == null) {
          continue;
        }
        try {
          final result = await _resolveEmbed(
            utf8.decode(base64.decode(base64.normalize(hash.trim()))),
          );
          if (result != null) return result;
        } catch (e) {
          // Try the next server
          continue;
        }
      }
    }
    return null;
  }

  Future<Map<String, String>?> _resolveEmbed(String embedUrl) async {
    final embed = Uri.parse(embedUrl);
    // The stream host wants the embed site as referer
    final referer = '${embed.scheme}://${embed.host}/';

    final page = await _get(embedUrl);
    final blob = RegExp(config.embedBlobPattern).firstMatch(page)?.group(1);
    if (blob == null) return null;

    final Map<String, dynamic> player = jsonDecode(_deobfuscate(blob));
    final src = player['src'] as String?;
    if (src == null || !src.contains('.m3u8')) return null;

    final result = {
      "url": src,
      "referer": referer,
      "userAgent": config.userAgent,
    };

    final malId = RegExp(r'/mal/(\d+)/').firstMatch(embed.path)?.group(1);
    if (malId != null) result["malId"] = malId;

    final subtitles = player['subtitles'];
    if (subtitles is List) {
      final tracks = [
        for (final s in subtitles)
          if (s is Map && s['src'] is String)
            {
              'src': s['src'],
              'label': (s['label'] ?? s['lang'] ?? s['language'] ?? '')
                  .toString(),
              'default': s['default'] == true,
            },
      ];
      if (tracks.isNotEmpty) {
        final subtitle = tracks.firstWhere(
          (t) => t['default'] == true,
          orElse: () => tracks.first,
        );
        result["subtitle"] = subtitle['src'] as String;
        result["subtitles"] = jsonEncode(tracks);
      }
    }
    return result;
  }

  /// The embed page ships its player config as base64(json XOR key).
  String _deobfuscate(String blob) {
    final bytes = base64.decode(base64.normalize(blob));
    final key = utf8.encode(config.embedXorKey);
    return utf8.decode([
      for (var i = 0; i < bytes.length; i++) bytes[i] ^ key[i % key.length],
    ]);
  }
}
