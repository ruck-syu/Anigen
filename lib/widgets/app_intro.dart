import 'package:flutter/material.dart';
import 'package:anigen/widgets/title_cards.dart';

/// The opening animation: the wordmark opens out from the centre with a red
/// glow, holds, then rushes towards the viewer as the app fades in behind it.
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
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  late final _reveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
  );
  late final _glow = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 0.6, curve: Curves.easeInOut),
  );
  late final _exit = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.68, 1, curve: Curves.easeInCubic),
  );

  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Skipped when the system asks for less motion
    if (MediaQuery.disableAnimationsOf(context)) {
      _done = true;
      return;
    }
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    final logoSize = (MediaQuery.sizeOf(context).shortestSide * 0.14).clamp(
      40.0,
      96.0,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Stays in the same slot when the intro goes, so it keeps its state
        widget.child,
        // Opaque, so taps don't reach the app until it's showing
        if (!_done)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final exit = _exit.value;
              return Opacity(
                opacity: 1 - exit,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Transform.scale(
                      scale: (0.88 + 0.12 * _reveal.value) * (1 + 5 * exit),
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
                          // Opens out from the centre
                          ClipRect(
                            child: Align(
                              widthFactor: _reveal.value,
                              child: Opacity(
                                opacity: _reveal.value,
                                child: AnigenLogo(size: logoSize),
                              ),
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
