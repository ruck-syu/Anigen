import 'package:flutter/material.dart';
import 'package:jikan_api/jikan_api.dart' as jikan;
import 'package:anigen/screens/title_screen.dart';
import 'package:anigen/services/library_store.dart';

const crust = Color(0xFF000000);
const mantle = Color(0xFF0A0A0A);
const green = Color(0xFF46D369);

LibraryTitle titleFromJikan(jikan.Anime anime) => LibraryTitle(
  title: anime.titleEnglish ?? anime.title,
  image: anime.imageUrl,
  malId: anime.malId,
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

/// The gradient wordmark.
class AnigenLogo extends StatelessWidget {
  final double size;

  const AnigenLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFFFF2A35),
          Color(0xFFE50914),
          Color(0xFFB20710),
        ],
      ).createShader(bounds),
      child: Text(
        'Anigen',
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
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
    return Image.network(
      url!,
      fit: fit,
      alignment: alignment,
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

/// A titled, horizontally scrolling row of cards.
class CardRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, padding: padding, trailing: trailing),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: padding),
            itemCount: itemCount,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetImage(image),
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
