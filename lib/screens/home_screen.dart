import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anigen/screens/browse_screen.dart';
import 'package:anigen/screens/search_screen.dart';
import 'package:anigen/screens/profile_screen.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/services/playback_controller.dart';
import 'package:anigen/widgets/player_overlay.dart';
import 'package:anigen/widgets/title_cards.dart';

/// App shell. Each tab keeps its own navigation stack (so the bottom bar
/// stays put, like YouTube) and the player floats above everything, so it
/// keeps playing while the user browses.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _navBarHeight = 64.0;

  final _playback = PlaybackController.instance;
  final _navigatorKeys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  int _index = 0;
  bool _wasActive = false;
  bool _wasExpanded = false;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    _playback.removeListener(_onPlaybackChanged);
    _sheet.dispose();
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (_playback.isActive != _wasActive) {
      _wasActive = _playback.isActive;
      if (!_playback.isActive) {
        _sheet.value = 0;
        _wasExpanded = false;
      }
      setState(() {});
    }
    if (!_playback.isActive) return;
    // Only react when expanded/minimized actually changes: playback notifies
    // for plenty else, and mid-swipe that would yank the sheet away.
    if (_playback.isExpanded == _wasExpanded) return;
    _wasExpanded = _playback.isExpanded;
    final target = _wasExpanded ? 1.0 : 0.0;
    if (_sheet.value != target) {
      _sheet.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _selectTab(int index) {
    if (_playback.isExpanded) _playback.minimize();
    if (index == _index) {
      // Tapping the current tab goes back to its start
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = index);
    }
  }

  void _handleBack() {
    if (_playback.isActive && _playback.isExpanded) {
      _playback.minimize();
      return;
    }
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    SystemNavigator.pop();
  }

  void _openTitle(LibraryTitle title) {
    _playback.minimize();
    final context = _navigatorKeys[_index].currentContext;
    if (context != null) openTitle(context, title);
  }

  Widget _buildTab(int index, Widget root) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(settings: settings, builder: (context) => root),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = IndexedStack(
      index: _index,
      children: [
        _buildTab(0, const BrowseScreen()),
        _buildTab(1, const SearchScreen()),
        _buildTab(2, const ProfileScreen()),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= mediumWidth
            ? _buildWide(context, tabs, constraints.maxWidth >= wideWidth)
            : _buildNarrow(context, tabs),
      ),
    );
  }

  /// Gives the tab pages enough bottom padding to scroll clear of the
  /// floating bar and mini player, and [size] when they don't get the whole
  /// window, so their breakpoints go by the space they really have.
  Widget _withBottomInset(
    BuildContext context,
    Widget child,
    double inset, {
    Size? size,
  }) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        size: size,
        padding: media.padding.copyWith(bottom: inset),
        viewPadding: media.viewPadding.copyWith(bottom: inset),
      ),
      child: child,
    );
  }

  Widget _buildNarrow(BuildContext context, Widget tabs) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final navTotal = _navBarHeight + systemBottom;
    final active = _playback.isActive;

    return Scaffold(
      // The tab pages resize for the keyboard themselves; resizing here
      // too would shrink them twice and leave a black gap
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: _withBottomInset(
              context,
              tabs,
              navTotal + (active ? miniPlayerHeight + 16 : 0),
            ),
          ),
          AnimatedBuilder(
            animation: _sheet,
            builder: (context, child) => Positioned(
              left: 0,
              right: 0,
              bottom: -navTotal * _sheet.value,
              height: navTotal,
              child: child!,
            ),
            child: _BottomBar(
              index: _index,
              onSelect: _selectTab,
              bottomPadding: systemBottom,
            ),
          ),
          if (active)
            Positioned.fill(
              child: PlayerOverlay(
                sheet: _sheet,
                miniBottom: navTotal,
                wide: false,
                onOpenTitle: _openTitle,
              ),
            ),
        ],
      ),
    );
  }

  /// The rail layout, for tablets and desktops. [wide] gives the player its
  /// floating mini player and episode side panel.
  Widget _buildWide(BuildContext context, Widget tabs, bool wide) {
    final active = _playback.isActive;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _selectTab,
                labelType: NavigationRailLabelType.all,
                backgroundColor: crust,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: AnigenLogo(size: 18),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search),
                    label: Text('search'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.video_library_outlined),
                    selectedIcon: Icon(Icons.video_library),
                    label: Text('my list'),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) => _withBottomInset(
                          context,
                          tabs,
                          active ? miniPlayerHeight + 24 : 0,
                          size: constraints.biggest,
                        ),
                      ),
                    ),
                    // Fades the rail into the page instead of a hard edge
                    // where artwork meets it
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 24,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [crust, Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active)
            Positioned.fill(
              child: PlayerOverlay(
                sheet: _sheet,
                miniBottom: 8,
                wide: wide,
                onOpenTitle: _openTitle,
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  /// How far the fade reaches above the bar.
  static const _fadeAbove = 32.0;

  final int index;
  final ValueChanged<int> onSelect;
  final double bottomPadding;

  const _BottomBar({
    required this.index,
    required this.onSelect,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const items = [
      (Icons.home_outlined, Icons.home, 'home'),
      (Icons.search_outlined, Icons.search, 'search'),
      (Icons.video_library_outlined, Icons.video_library, 'my list'),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Fades up into the page rather than sitting on it as a slab, and
        // starts above the bar so the content behind the icons stays dark
        Positioned(
          left: 0,
          right: 0,
          top: -_fadeAbove,
          bottom: 0,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    crust,
                    crust.withValues(alpha: 0.9),
                    crust.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        ClipRect(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: InkResponse(
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            i == index ? items[i].$2 : items[i].$1,
                            color: i == index
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            items[i].$3,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: i == index
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: i == index ? FontWeight.w700 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
