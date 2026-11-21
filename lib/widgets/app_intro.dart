import 'dart:io';

import 'package:flutter/material.dart';

import 'package:anigen/services/library_store.dart';
import 'package:anigen/widgets/wordmark.dart';

/// The opening animation: the app icon's arched A, lying on its side as on
/// the icon, turns 90° right to stand up, then "NIGEN" slides out from
/// behind it to spell the wordmark. It holds, then rushes towards the viewer
/// as the app fades in behind it.
///
/// [child] is built from the start, so the home screen loads during it.
class AppIntro extends StatefulWidget {
  final Widget child;

  const AppIntro({super.key, required this.child});

  @override
  State<AppIntro> createState() => _AppIntroState();
}

class _AppIntroState extends State<AppIntro>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final CurvedAnimation _appear;
  late final CurvedAnimation _turn;
  late final CurvedAnimation _slide;
  late final CurvedAnimation _glow;
  late final CurvedAnimation _exit;
  Wordmark? _wordmark;
  double? _logoSize;

  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _controller != null) return;
    // Skipped when turned off in settings or the system asks for less motion
    if (!LibraryStore.instance.showIntro ||
        MediaQuery.disableAnimationsOf(context)) {
      _done = true;
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _appear = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.1, curve: Curves.easeOut),
    );
    _turn = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.16, 0.42, curve: Curves.easeInOutBack),
    );
    _slide = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.42, 0.68, curve: Curves.easeOutCubic),
    );
    _glow = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.5, 0.82, curve: Curves.easeInOut),
    );
    _exit = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.82, 1, curve: Curves.easeInCubic),
    );
    _controller = controller;
    controller.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _wordmark?.dispose();
    final controller = _controller;
    if (controller != null) {
      _appear.dispose();
      _turn.dispose();
      _slide.dispose();
      _glow.dispose();
      _exit.dispose();
      controller.dispose();
    }
    super.dispose();
  }

  Wordmark _wordmarkFor(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    // Same proportions as AnigenLogo
    final logoSize = (MediaQuery.sizeOf(context).shortestSide * 0.14).clamp(
      40.0,
      96.0,
    );
    if (_logoSize != logoSize || _wordmark?.color != red) {
      _wordmark?.dispose();
      _wordmark = Wordmark(
        fontSize: logoSize * 1.4,
        letterSpacing: logoSize * 0.06,
        color: red,
      );
      _logoSize = logoSize;
    }
    return _wordmark!;
  }

  @override
  Widget build(BuildContext context) {
    final wordmark = _done ? null : _wordmarkFor(context);
    if (wordmark == null) {
      _wordmark?.dispose();
      _wordmark = null;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Stays in the same slot when the intro goes, so it keeps its state
        widget.child,
        // Opaque, so taps don't reach the app until it's showing
        if (wordmark != null)
          AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final exit = _exit.value;
              final logoSize = _logoSize!;
              final red = wordmark.color;
              return Opacity(
                opacity: 1 - exit,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 5 * exit,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Glow behind the wordmark
                          Opacity(
                            opacity: _glow.value * (1 - _glow.value * 0.35),
                            child: Container(
                              width: logoSize * 6,
                              height: logoSize * 3,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    red.withValues(alpha: 0.45),
                                    red.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          CustomPaint(
                            size: wordmark.size,
                            painter: WordmarkPainter(
                              wordmark: wordmark,
                              // Android 12+ has just shown the icon on its
                              // splash, so the A is already there
                              opacity: Platform.isAndroid ? 1 : _appear.value,
                              turn: _turn.value,
                              slide: _slide.value,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
