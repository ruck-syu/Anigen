import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/providers/anilist_provider.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/title_cards.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

/// Searches AniList, so opened titles come with their details. The details
/// page then finds the matching stream, like titles opened from home.
class SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'recent_titles';
  static const _maxRecent = 3;
  // Hianime-only results from before search used AniList.
  static const _oldRecentKey = 'recent_anime';

  final _provider = AniListProvider();
  final TextEditingController _searchController = TextEditingController();
  List<AniListMedia> _results = [];
  List<LibraryTitle> _recentAnime = [];
  SearchFilter _filter = const SearchFilter();
  final _genres = ValueNotifier<List<String>>([]);
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;
  Timer? _debounce;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _loadRecentAnime();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _genres.dispose();
    super.dispose();
  }

  void setSearchQuery(String query) {
    _searchController.text = query;
    _search(query: query);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    _debounce?.cancel();
    if (query.isEmpty && !_filter.isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 400), _search);
      return;
    }
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _results = [];
        _error = null;
      });
      return;
    }
    if (query.length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 400), () {
        _search(query: query);
      });
    }
  }

  Future<void> _loadRecentAnime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.remove(_oldRecentKey);
      final recent = [
        for (final item in prefs.getStringList(_recentKey) ?? const <String>[])
          LibraryTitle.fromJson(jsonDecode(item)),
      ].take(_maxRecent).toList();
      if (mounted) setState(() => _recentAnime = recent);
    } catch (e) {
      if (mounted) setState(() => _recentAnime = []);
    }
  }

  Future<void> _saveRecentAnime(LibraryTitle title) async {
    _recentAnime.removeWhere((t) => t.anilistId == title.anilistId);
    _recentAnime.insert(0, title);
    if (_recentAnime.length > _maxRecent) {
      _recentAnime = _recentAnime.sublist(0, _maxRecent);
    }
    setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _recentKey,
        _recentAnime.map((t) => jsonEncode(t.toJson())).toList(),
      );
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _clearRecentAnime() async {
    setState(() {
      _recentAnime = [];
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _search({String? query}) async {
    final searchQuery = query ?? _searchController.text;
    if (searchQuery.isEmpty && _filter.isEmpty) return;
    final id = ++_searchId;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      final results = await _provider.search(searchQuery, filter: _filter);
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openFilters() async {
    FocusScope.of(context).unfocus();
    if (_genres.value.isEmpty) {
      _provider.getGenres().then((genres) {
        if (mounted) _genres.value = genres;
      }, onError: (_) {});
    }
    final filter = await showModalBottomSheet<SearchFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (context) => _FilterSheet(initial: _filter, genres: _genres),
    );
    if (filter == null || !mounted) return;
    setState(() => _filter = filter);
    if (_searchController.text.isEmpty && filter.isEmpty) {
      setState(() {
        _hasSearched = false;
        _results = [];
        _error = null;
      });
    } else {
      _search();
    }
  }

  void _open(LibraryTitle title) {
    FocusScope.of(context).unfocus();
    _saveRecentAnime(title);
    openTitle(context, title);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 900 ? 24.0 : 16.0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (query) => _search(query: query),
                        decoration: InputDecoration(
                          hintText: 'search shows, movies...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _searchController.clear,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'filters',
                      onPressed: _openFilters,
                      icon: Badge(
                        isLabelVisible: !_filter.isEmpty,
                        label: Text('${_filter.count}'),
                        child: const Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _hasSearched
                    ? _buildResults(padding, width)
                    : _buildIdle(padding),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdle(double padding) {
    if (_recentAnime.isEmpty) {
      return const _Message(
        icon: Icons.search,
        text: 'find something to watch',
      );
    }
    return ListView(
      children: [
        CardRow(
          title: 'recent searches',
          padding: padding,
          height: 112 * 3 / 2 + 42,
          itemCount: _recentAnime.length,
          trailing: TextButton(
            onPressed: _clearRecentAnime,
            child: const Text('clear'),
          ),
          itemBuilder: (context, i) => PosterCard(
            title: _recentAnime[i].title,
            image: _recentAnime[i].image,
            width: 112,
            onTap: () => _open(_recentAnime[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(double padding, double width) {
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _error!,
        action: TextButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.refresh),
          label: const Text('retry'),
        ),
      );
    }
    if (_results.isEmpty) {
      return _isLoading
          ? const SizedBox.shrink()
          : const _Message(icon: Icons.search_off, text: 'no results found');
    }
    final columns = (width / 150).floor().clamp(3, 8);
    return RefreshIndicator(
      onRefresh: _search,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          padding,
          8,
          padding,
          bottomInset(context) + 16,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.5,
        ),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final media = _results[index];
          return PosterCard(
            title: media.title,
            image: media.image,
            width: double.infinity,
            onTap: () => _open(titleFromAnilist(media)),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Sort, format, status, year and genres for search.
class _FilterSheet extends StatefulWidget {
  final SearchFilter initial;

  /// Genres arrive from AniList while the sheet may already be open.
  final ValueListenable<List<String>> genres;

  const _FilterSheet({required this.initial, required this.genres});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort = widget.initial.sort;
  late final Set<String> _formats = {...widget.initial.formats};
  late String? _status = widget.initial.status;
  late final Set<String> _genres = {...widget.initial.genres};
  late int? _year = widget.initial.year;

  void _reset() => setState(() {
    _sort = SearchFilter.defaultSort;
    _formats.clear();
    _status = null;
    _genres.clear();
    _year = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final thisYear = DateTime.now().year;

    Widget section(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: label),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: chips),
        ],
      ),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                section('sort', [
                  for (final MapEntry(key: value, value: name)
                      in SearchFilter.sorts.entries)
                    ChoiceChip(
                      label: Text(name),
                      selected: _sort == value,
                      onSelected: (_) => setState(() => _sort = value),
                    ),
                ]),
                section('format', [
                  for (final MapEntry(key: value, value: name)
                      in SearchFilter.formatLabels.entries)
                    FilterChip(
                      label: Text(name),
                      selected: _formats.contains(value),
                      onSelected: (on) => setState(
                        () => on ? _formats.add(value) : _formats.remove(value),
                      ),
                    ),
                ]),
                section('status', [
                  for (final MapEntry(key: value, value: name)
                      in SearchFilter.statusLabels.entries)
                    ChoiceChip(
                      label: Text(name),
                      selected: _status == value,
                      onSelected: (on) =>
                          setState(() => _status = on ? value : null),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Text('year', style: label),
                      const Spacer(),
                      DropdownButton<int?>(
                        value: _year,
                        underline: const SizedBox.shrink(),
                        onChanged: (year) => setState(() => _year = year),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('any'),
                          ),
                          for (var y = thisYear + 1; y >= 1970; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: widget.genres,
                  builder: (context, genres, _) {
                    if (genres.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return section('genres', [
                      for (final genre in genres)
                        FilterChip(
                          label: Text(genre.toLowerCase()),
                          selected: _genres.contains(genre),
                          onSelected: (on) => setState(
                            () =>
                                on ? _genres.add(genre) : _genres.remove(genre),
                          ),
                        ),
                    ]);
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(onPressed: _reset, child: const Text('reset')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      SearchFilter(
                        sort: _sort,
                        formats: {..._formats},
                        status: _status,
                        genres: {..._genres},
                        year: _year,
                      ),
                    ),
                    child: const Text('show results'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
