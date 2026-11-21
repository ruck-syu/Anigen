import 'package:anigen/models/anime.dart';
import 'package:anigen/providers/source_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Anime _anime(String title, {int? episodes, String? type, String? japanese}) =>
    Anime(
      title: title,
      url: '/$title',
      episodes: episodes,
      type: type,
      japaneseTitle: japanese,
    );

void main() {
  final matcher = SourceMatcher(
    names: const ['Frieren: Beyond Journey\'s End', 'Sousou no Frieren'],
    episodes: 28,
    format: 'TV',
  );

  test('picks the show whose title, episodes and format agree', () {
    const title = 'Frieren: Beyond Journey\'s End';
    final correct = _anime(title, episodes: 28, type: 'TV');
    final best = matcher.best([
      _anime('$title (TV)', episodes: 2, type: 'TV'),
      _anime('$title (Dub)', episodes: 28, type: 'Special'),
      correct,
    ]);
    expect(best?.anime, same(correct));
    expect(best?.score, greaterThanOrEqualTo(SourceMatcher.confident));
  });

  test('matches a title by its Japanese alias', () {
    final alias = _anime('The Lost Mage', japanese: 'Sousou no Frieren');
    expect(matcher.best([alias])?.anime, same(alias));
  });

  test('rejects a show whose title barely overlaps', () {
    // Before the minimum title similarity, the episode and format bonuses
    // alone made these match: no shared words, and one incidental word
    expect(
      matcher.best([_anime('Completely Different', episodes: 28, type: 'TV')]),
      isNull,
    );
    expect(
      matcher.best([
        _anime('The End of a Long Story', episodes: 28, type: 'TV'),
      ]),
      isNull,
    );
  });

  test('names that normalise to nothing match nothing', () {
    final symbols = SourceMatcher(names: const ['!!!'], episodes: 12);
    expect(symbols.names, isEmpty);
    // Two empty titles would otherwise count as identical
    expect(symbols.best([_anime('???', episodes: 12)]), isNull);
  });
}
