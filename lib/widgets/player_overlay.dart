import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:anigen/models/anime.dart';
import 'package:anigen/screens/title_screen.dart';
import 'package:anigen/services/library_store.dart';
import 'package:anigen/services/playback_controller.dart';
import 'package:anigen/widgets/title_cards.dart';

const double miniPlayerHeight = 64;

/// The app-wide player. [sheet] is 0 when docked as a mini player and 1 when
/// it fills the screen; the video moves smoothly between the two.
class PlayerOverlay extends StatefulWidget {
  final AnimationController sheet;

  /// Distance between the bottom of the screen and the mini player.
  final double miniBottom;

  /// Wide layouts dock the mini player in the bottom-right corner.
  final bool wide;

  final void Function(LibraryTitle title) onOpenTitle;

  const PlayerOverlay({
    super.key,
    required this.sheet,
    required this.miniBottom,
    required this.wide,
    required this.onOpenTitle,
  });

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  final _playback = PlaybackController.instance;
  final _videoKey = GlobalKey();
  double _dragExtent = 1;

  void _onDragStart(DragStartDetails details) {
    // Take over from any settle animation still running.
    widget.sheet.stop();
    _dragExtent =
        (context.size?.height ?? 600) - miniPlayerHeight - widget.miniBottom;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    widget.sheet.value -= details.primaryDelta! / _dragExtent;
  }

  /// Settles with the finger's speed, so a flick carries on instead of
  /// stopping dead and restarting at a fixed pace.
  void _onDragEnd(DragEndDetails details) {
    final velocity = -(details.primaryVelocity ?? 0) / _dragExtent;
    final expand = velocity.abs() > 0.6
        ? velocity > 0
        : widget.sheet.value > 0.5;
    expand ? _playback.expand() : _playback.minimize();
    // Replaces the fixed-pace animation that may have just started.
    widget.sheet.fling(
      velocity: expand
          ? velocity.clamp(1.5, double.infinity)
          : velocity.clamp(double.negativeInfinity, -1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: Listenable.merge([widget.sheet, _playback]),
        builder: (context, _) => _build(context, constraints.biggest),
      ),
    );
  }

  Widget _build(BuildContext context, Size size) {
    final t = widget.sheet.value;
    final padding = MediaQuery.paddingOf(context);
    final theme = Theme.of(context);

    final miniWidth = widget.wide ? 420.0 : size.width - 16;
    final miniRect = Rect.fromLTWH(
      widget.wide ? size.width - miniWidth - 16 : 8,
      size.height - widget.miniBottom - miniPlayerHeight - 8,
      miniWidth,
      miniPlayerHeight,
    );
    final rect = Rect.lerp(miniRect, Offset.zero & size, t)!;

    // Where the video sits once expanded, relative to the overlay
    final landscapePhone = !widget.wide && size.width > size.height;
    final sidePanel = widget.wide ? 400.0 : 0.0;
    Rect fullVideo;
    if (landscapePhone) {
      fullVideo = Offset.zero & size;
    } else {
      final width = size.width - sidePanel;
      final height = (width * 9 / 16).clamp(0.0, size.height * 0.7);
      fullVideo = Rect.fromLTWH(0, padding.top, width, height);
    }
    const miniVideo = Rect.fromLTWH(
      0,
      0,
      miniPlayerHeight * 16 / 9,
      miniPlayerHeight,
    );
    final video = Rect.lerp(miniVideo, fullVideo, t)!;
    final expanded = t == 1;
    final miniOpacity = (1 - t * 4).clamp(0.0, 1.0);
    final detailsOpacity = ((t - 0.5) * 2).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Dim the page behind while dragging
        if (t > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * t)),
            ),
          ),
        Positioned.fromRect(
          rect: rect,
          child: Material(
            color: Color.lerp(
              theme.colorScheme.surfaceContainerHighest,
              theme.scaffoldBackgroundColor,
              t,
            ),
            elevation: 8 * (1 - t),
            borderRadius: BorderRadius.circular(lerpDouble(12, 0, t)!),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (expanded && !landscapePhone)
                  // Status bar area above the video
                  Positioned(
                    left: 0,
                    top: 0,
                    width: fullVideo.width,
                    height: padding.top,
                    child: const ColoredBox(color: Colors.black),
                  ),
                Positioned.fromRect(
                  rect: video,
                  child: GestureDetector(
                    onTap: expanded ? null : _playback.expand,
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: ColoredBox(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            child: _PlayerVideo(
                              key: _videoKey,
                              // Follows the player's state rather than the
                              // drag, so controls don't flicker mid-swipe.
                              expanded: _playback.isExpanded,
                              edgeToEdge: landscapePhone,
                            ),
                          ),
                          if (_playback.isLoading || _playback.error != null)
                            _LoadingOrError(compact: !expanded),
                        ],
                      ),
                    ),
                  ),
                ),
                if (miniOpacity > 0)
                  Positioned(
                    left: miniVideo.width,
                    top: 0,
                    right: 0,
                    height: miniPlayerHeight,
                    child: Opacity(
                      opacity: miniOpacity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _playback.expand,
                        onVerticalDragStart: _onDragStart,
                        onVerticalDragUpdate: _onDragUpdate,
                        onVerticalDragEnd: _onDragEnd,
                        child: const _MiniControls(),
                      ),
                    ),
                  ),
                if (miniOpacity > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: miniPlayerHeight - 2,
                    height: 2,
                    child: Opacity(
                      opacity: miniOpacity,
                      child: const _MiniProgress(),
                    ),
                  ),
                if (detailsOpacity > 0 && !landscapePhone)
                  Positioned(
                    left: 0,
                    top: fullVideo.bottom,
                    width: fullVideo.width,
                    height: size.height - fullVideo.bottom,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: Opacity(
                        opacity: detailsOpacity,
                        child: _Details(
                          showEpisodes: !widget.wide,
                          onDragStart: _onDragStart,
                          onDragUpdate: _onDragUpdate,
                          onDragEnd: _onDragEnd,
                          onOpenTitle: widget.onOpenTitle,
                        ),
                      ),
                    ),
                  ),
                if (detailsOpacity > 0 && widget.wide)
                  Positioned(
                    left: fullVideo.right,
                    top: padding.top,
                    width: sidePanel,
                    height: size.height - padding.top,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: Opacity(
                        opacity: detailsOpacity,
                        child: const _EpisodePanel(),
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

class _PlayerVideo extends StatelessWidget {
  final bool expanded;

  /// The video fills the screen, so controls keep clear of the edges where
  /// Android's back and home swipes live.
  final bool edgeToEdge;

  const _PlayerVideo({
    super.key,
    required this.expanded,
    required this.edgeToEdge,
  });

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    final topBar = [
      MaterialCustomButton(
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: playback.minimize,
      ),
      const Spacer(),
      MaterialCustomButton(
        icon: const Icon(Icons.speed),
        onPressed: () => showSpeedSheet(context),
      ),
    ];
    final fullscreenTopBar = [
      Expanded(
        child: Text(
          '${playback.title?.title ?? ''} · E${playback.episode?.number ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      MaterialCustomButton(
        icon: const Icon(Icons.speed),
        onPressed: () => showSpeedSheet(context),
      ),
    ];
    final primary = [
      const Spacer(flex: 2),
      MaterialCustomButton(
        iconSize: 36,
        icon: const Icon(Icons.skip_previous),
        onPressed: playback.playPrevious,
      ),
      const Spacer(),
      const MaterialPlayOrPauseButton(iconSize: 56),
      const Spacer(),
      MaterialCustomButton(
        iconSize: 36,
        icon: const Icon(Icons.skip_next),
        onPressed: playback.playNext,
      ),
      const Spacer(flex: 2),
    ];
    final bottomBar = [
      const MaterialPositionIndicator(),
      const Spacer(),
      const MaterialFullscreenButton(),
    ];
    MaterialVideoControlsThemeData controlsTheme(
      List<Widget> topButtonBar, {
      required bool edgeSafe,
    }) => MaterialVideoControlsThemeData(
      seekOnDoubleTap: true,
      volumeGesture: false,
      brightnessGesture: false,
      speedUpOnLongPress: true,
      seekBarPositionColor: Theme.of(context).colorScheme.error,
      seekBarThumbColor: Theme.of(context).colorScheme.error,
      topButtonBar: topButtonBar,
      primaryButtonBar: primary,
      bottomButtonBar: bottomBar,
      // Edge to edge, keep clear of Android's back and home swipe areas and
      // give the seek bar a taller touch target.
      padding: edgeSafe ? const EdgeInsets.fromLTRB(24, 12, 24, 20) : null,
      topButtonBarMargin: EdgeInsets.symmetric(horizontal: edgeSafe ? 8 : 16),
      seekBarMargin: edgeSafe
          ? const EdgeInsets.symmetric(horizontal: 8)
          : EdgeInsets.zero,
      seekBarContainerHeight: edgeSafe ? 48 : 36,
      bottomButtonBarMargin: edgeSafe
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.only(left: 16, right: 8),
    );
    final desktopTheme = MaterialDesktopVideoControlsThemeData(
      seekBarPositionColor: Theme.of(context).colorScheme.error,
      seekBarThumbColor: Theme.of(context).colorScheme.error,
      topButtonBar: topBar,
      bottomButtonBar: [
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.skip_previous),
          onPressed: playback.playPrevious,
        ),
        const MaterialDesktopPlayOrPauseButton(),
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.skip_next),
          onPressed: playback.playNext,
        ),
        const MaterialDesktopVolumeButton(),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        const MaterialDesktopFullscreenButton(),
      ],
    );

    return MaterialVideoControlsTheme(
      normal: controlsTheme(topBar, edgeSafe: edgeToEdge),
      fullscreen: controlsTheme(fullscreenTopBar, edgeSafe: true),
      child: MaterialDesktopVideoControlsTheme(
        normal: desktopTheme,
        fullscreen: desktopTheme.copyWith(topButtonBar: fullscreenTopBar),
        child: Video(
          controller: playback.video,
          controls: expanded ? _controls : NoVideoControls,
        ),
      ),
    );
  }

  static Widget _controls(VideoState state) {
    return Stack(
      children: [AdaptiveVideoControls(state), const _SkipButtons()],
    );
  }
}

/// Netflix-style "skip intro" / "next episode" buttons over the video.
class _SkipButtons extends StatelessWidget {
  const _SkipButtons();

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => StreamBuilder<Duration>(
        stream: playback.player.stream.position,
        builder: (context, snapshot) {
          if (playback.isLoading) return const SizedBox.shrink();
          final position = snapshot.data ?? playback.player.state.position;
          final duration = playback.player.state.duration;
          final skip = playback.skipAt(position);
          final next = playback.nextEpisode;
          final hasEnding = playback.skips.any((s) => s.type == 'ed');
          final nearEnd =
              duration > Duration.zero &&
              duration - position < const Duration(seconds: 90);

          Widget? button;
          if (skip?.type == 'op' && !LibraryStore.instance.autoSkipIntro) {
            button = _OverlayButton(
              icon: Icons.fast_forward,
              label: 'skip intro',
              onPressed: () => playback.player.seek(skip!.end),
            );
          } else if (next != null &&
              (skip?.type == 'ed' || (!hasEnding && nearEnd))) {
            button = _OverlayButton(
              icon: Icons.skip_next,
              label: 'next episode',
              onPressed: playback.playNext,
            );
          } else if (skip?.type == 'ed') {
            button = _OverlayButton(
              icon: Icons.fast_forward,
              label: 'skip credits',
              onPressed: () => playback.player.seek(skip!.end),
            );
          }

          return Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 64),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: button ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _OverlayButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: ValueKey(label),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _LoadingOrError extends StatelessWidget {
  final bool compact;

  const _LoadingOrError({required this.compact});

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    final error = playback.error;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.35,
          child: NetImage(
            playback.title?.image,
            alignment: const Alignment(0, -0.4),
          ),
        ),
        Center(
          child: error == null
              ? SizedBox(
                  width: compact ? 20 : 36,
                  height: compact ? 20 : 36,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                )
              : compact
              ? Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: playback.retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('retry'),
                      ),
                    ],
                  ),
                ),
        ),
        if (!compact)
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              onPressed: playback.minimize,
            ),
          ),
      ],
    );
  }
}

class _MiniControls extends StatelessWidget {
  const _MiniControls();

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playback.title?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                playback.error != null
                    ? 'playback failed'
                    : 'episode ${playback.episode?.number ?? ''}',
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<bool>(
          stream: playback.player.stream.playing,
          initialData: playback.player.state.playing,
          builder: (context, snapshot) => IconButton(
            icon: Icon(snapshot.data! ? Icons.pause : Icons.play_arrow),
            color: theme.colorScheme.onSurface,
            onPressed: playback.isLoading ? null : playback.player.playOrPause,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: theme.colorScheme.onSurface,
          onPressed: playback.close,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) {
    final player = PlaybackController.instance.player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snapshot) {
        final duration = player.state.duration.inMilliseconds;
        final position =
            (snapshot.data ?? player.state.position).inMilliseconds;
        return LinearProgressIndicator(
          value: duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0,
          backgroundColor: Colors.transparent,
          color: Theme.of(context).colorScheme.error,
        );
      },
    );
  }
}

/// Title, actions and (on phones) the episode list under the video.
class _Details extends StatelessWidget {
  final bool showEpisodes;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final void Function(LibraryTitle title) onOpenTitle;

  const _Details({
    required this.showEpisodes,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onOpenTitle,
  });

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    final library = LibraryStore.instance;
    final theme = Theme.of(context);
    final title = playback.title;
    if (title == null) return const SizedBox.shrink();

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onDragStart,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => onOpenTitle(title),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'episode ${playback.episode?.number} of ${playback.episodes.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: library,
              builder: (context, _) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Pill(
                      icon: Icons.skip_previous,
                      label: 'previous',
                      onTap: playback.previousEpisode == null
                          ? null
                          : playback.playPrevious,
                    ),
                    _Pill(
                      icon: Icons.skip_next,
                      label: 'next',
                      onTap: playback.nextEpisode == null
                          ? null
                          : playback.playNext,
                    ),
                    _Pill(
                      icon: library.isFavourite(title)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: 'favourite',
                      onTap: () => library.toggleFavourite(title),
                    ),
                    _Pill(
                      icon: Icons.speed,
                      label: '${playback.rate}x',
                      onTap: () => showSpeedSheet(context),
                    ),
                    _Pill(
                      icon: library.autoplay
                          ? Icons.toggle_on
                          : Icons.toggle_off,
                      label: 'autoplay',
                      onTap: () => library.setAutoplay(!library.autoplay),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!showEpisodes) return SingleChildScrollView(child: header);
    return Column(
      children: [
        header,
        const Divider(height: 16),
        const Expanded(child: _EpisodeList()),
      ],
    );
  }
}

class _EpisodePanel extends StatelessWidget {
  const _EpisodePanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'episodes',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Expanded(child: _EpisodeList()),
      ],
    );
  }
}

class _EpisodeList extends StatefulWidget {
  const _EpisodeList();

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  static const _extent = 76.0;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final playback = PlaybackController.instance;
    final index = playback.episodes.indexWhere(
      (e) => e.url == playback.episode?.url,
    );
    // Start with the current episode near the top
    _controller = ScrollController(
      initialScrollOffset: index > 1 ? (index - 1) * _extent : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    return ListenableBuilder(
      listenable: LibraryStore.instance,
      builder: (context, _) {
        final history = LibraryStore.instance.historyFor(
          playback.title?.animeId,
        );
        final List<Episode> episodes = playback.episodes;
        return ListView.builder(
          controller: _controller,
          itemExtent: _extent,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            return EpisodeTile(
              episode: episode,
              image: playback.title?.image,
              progress: history?.episodes[episode.number],
              isPlaying: episode.url == playback.episode?.url,
              onTap: () => playback.playEpisode(episode),
            );
          },
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Pill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    );
  }
}

void showSpeedSheet(BuildContext context) {
  final playback = PlaybackController.instance;
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            tileColor: Colors.transparent,
            title: Text('playback speed'),
          ),
          for (final speed in speeds)
            ListTile(
              tileColor: Colors.transparent,
              leading: Icon(
                speed == playback.rate ? Icons.check : null,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('${speed}x'),
              onTap: () {
                playback.setRate(speed);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  );
}
