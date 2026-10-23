import 'package:flutter/material.dart';
import 'package:anigen/models/anilist_media.dart';
import 'package:anigen/screens/title_screen.dart';
import 'package:anigen/services/anilist_account.dart';
import 'package:anigen/services/library_store.dart';

const crust = Color(0xFF000000);
const mantle = Color(0xFF0A0A0A);
const green = Color(0xFF46D369);

/// From here tablets get the navigation rail instead of the bottom bar.
const mediumWidth = 600.0;

/// From here pages use their large-screen layouts.
const wideWidth = 900.0;

LibraryTitle titleFromAnilist(AniListMedia media) => LibraryTitle(
  title: media.title,
  image: media.image,
  anilistId: media.id,
  malId: media.malId,
);

/// Opens the title page in the current tab.
void openTitle(
  BuildContext context,
  LibraryTitle title, {
  bool autoplay = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => TitleScreen(title: title, autoplay: autoplay),
    ),
  );
}

/// Asks before deleting an AniList entry, unless it's only "plan to watch"
/// and has nothing to lose.
Future<bool> confirmAniListRemoval(
  BuildContext context,
  AniListEntry entry,
) async {
  if (entry.status == 'PLANNING' && entry.progress == 0 && entry.score == 0) {
    return true;
  }
  final progress = entry.progress > 0
      ? ' and your progress (${entry.progress} eps)'
      : '';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('remove from anilist?'),
      content: Text(
        '${entry.title.title} is on your anilist as "${entry.label}". '
        'Removing it deletes that entry$progress.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('remove'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The wordmark.
class AnigenLogo extends StatelessWidget {
  final double size;

  /// A dark halo, so it reads over bright artwork.
  final bool shadow;

  const AnigenLogo({super.key, this.size = 22, this.shadow = false});

  @override
  Widget build(BuildContext context) {
    // Bebas Neue is condensed, so it's drawn larger to match the old width.
    return Text(
      'ANIGEN',
      style: TextStyle(
        fontFamily: 'BebasNeue',
        color: Theme.of(context).colorScheme.primary,
        fontSize: size * 1.4,
        letterSpacing: size * 0.06,
        height: 1,
        shadows: shadow
            ? const [
                Shadow(color: Colors.black, blurRadius: 2),
                Shadow(color: Colors.black87, blurRadius: 10),
              ]
            : null,
      ),
    );
  }
}

/// Space the floating nav bar and mini player take up at the bottom.
double bottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

class NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final Alignment alignment;

  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    // Decode at the size it's drawn at, not the source size, so scrolling
    // rows of posters don't hold and sample full-resolution bitmaps.
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final decodeWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth * dpr).round()
            : null;
        return Image.network(
          url!,
          fit: fit,
          alignment: alignment,
          cacheWidth: decodeWidth != null && decodeWidth > 0
              ? decodeWidth
              : null,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => placeholder,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: child,
            );
          },
        );
      },
    );
  }
}

/// A soft, blurred-looking backdrop. Instead of a live blur (re-rendered
/// every frame while scrolling), the image is decoded tiny and stretched, so
/// it costs no more to draw than a plain image.
class SoftBackdrop extends StatelessWidget {
  final String? url;
  final int decodeWidth;
  final double opacity;

  const SoftBackdrop(
    this.url, {
    super.key,
    this.decodeWidth = 48,
    this.opacity = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    return ClipRect(
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        opacity: AlwaysStoppedAnimation(opacity),
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Thin red-style progress line used on cards and episodes.
class WatchProgressBar extends StatelessWidget {
  final double value;

  const WatchProgressBar(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.white24,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final double padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 24, padding, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A titled, horizontally scrolling row of cards. With a mouse, hovering
/// shows arrows at the ends to page through it.
class CardRow extends StatefulWidget {
  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double padding;
  final Widget? trailing;

  const CardRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = 16,
    this.trailing,
  });

  @override
  State<CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<CardRow> {
  final _scroll = ScrollController();
  bool _hovering = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _page(int direction) {
    final position = _scroll.position;
    _scroll.animateTo(
      (position.pixels + direction * position.viewportDimension * 0.8).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          widget.title,
          padding: widget.padding,
          trailing: widget.trailing,
        ),
        SizedBox(
          height: widget.height,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: Stack(
              children: [
                ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: widget.padding),
                  itemCount: widget.itemCount,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: widget.itemBuilder,
                ),
                if (_hovering)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: _scroll,
                      builder: (context, _) {
                        if (!_scroll.hasClients ||
                            !_scroll.position.hasContentDimensions) {
                          return const SizedBox.shrink();
                        }
                        final position = _scroll.position;
                        return Stack(
                          children: [
                            if (position.pixels > position.minScrollExtent)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: ScrollArrow(
                                  forward: false,
                                  onTap: () => _page(-1),
                                ),
                              ),
                            if (position.pixels < position.maxScrollExtent)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: ScrollArrow(
                                  forward: true,
                                  onTap: () => _page(1),
                                ),
                              ),
                          ],
                        );
                      },
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

/// A dark strip with a chevron at the end of a horizontal row, for mice.
class ScrollArrow extends StatelessWidget {
  final bool forward;
  final VoidCallback onTap;
  final double width;

  const ScrollArrow({
    super.key,
    required this.forward,
    required this.onTap,
    this.width = 48,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: forward ? Alignment.centerRight : Alignment.centerLeft,
                end: forward ? Alignment.centerLeft : Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0),
                ],
              ),
            ),
            child: Icon(
              forward ? Icons.chevron_right : Icons.chevron_left,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rings a poster while the mouse is over it; the ink highlight would sit
/// under the image and never show.
class HoverRing extends StatefulWidget {
  final Widget child;
  final double radius;

  const HoverRing({super.key, required this.child, this.radius = 8});

  @override
  State<HoverRing> createState() => _HoverRingState();
}

class _HoverRingState extends State<HoverRing> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _hovering ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class PosterCard extends StatelessWidget {
  final String title;
  final String? image;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showTitle;

  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.width,
    required this.onTap,
    this.onLongPress,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: HoverRing(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: NetImage(image),
                ),
              ),
            ),
            if (showTitle) ...[
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Netflix-style "Top 10" card: a huge outlined rank next to the poster.
class RankedCard extends StatelessWidget {
  final int rank;
  final String title;
  final String? image;
  final double posterWidth;
  final VoidCallback onTap;

  const RankedCard({
    super.key,
    required this.rank,
    required this.title,
    required this.image,
    required this.posterWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final height = posterWidth * 3 / 2;
    final digitStyle = TextStyle(
      fontSize: height * 0.75,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: -height * 0.08,
    );
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: posterWidth * (rank >= 10 ? 1.95 : 1.55),
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: -height * 0.06,
              child: Stack(
                children: [
                  Text(
                    '$rank',
                    style: digitStyle.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$rank',
                    style: digitStyle.copyWith(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: posterWidth,
              child: Tooltip(
                message: title,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: NetImage(image),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Landscape "Continue Watching" card with a progress bar.
class ContinueCard extends StatelessWidget {
  final HistoryEntry entry;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onInfo;

  const ContinueCard({
    super.key,
    required this.entry,
    required this.width,
    required this.onTap,
    required this.onRemove,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final progress = entry.lastProgress;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(
                      entry.title.image,
                      alignment: const Alignment(0, -0.4),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black45,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Text(
                        'E${entry.lastEpisode}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: WatchProgressBar(progress.fraction),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelected: (value) => value == 'info' ? onInfo() : onRemove(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'info', child: Text('episodes & info')),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('remove from row'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
