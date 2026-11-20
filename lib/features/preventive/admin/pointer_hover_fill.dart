import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PointerHoverFill extends StatefulWidget {
  const PointerHoverFill({
    super.key,
    required this.content,
    required this.minHeight,
  });

  final Widget Function(Color foreground) content;
  final double minHeight;

  @override
  State<PointerHoverFill> createState() => _PointerHoverFillState();
}

class _PointerHoverFillState extends State<PointerHoverFill>
    with SingleTickerProviderStateMixin {
  late final _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 140),
  );
  Offset _origin = Offset.zero;
  Timer? _delay;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  void _enter(PointerEvent event) {
    _delay?.cancel();
    _origin = event.localPosition;
    _fill.value = 0;
    _delay = Timer(const Duration(milliseconds: 110), () {
      if (_reduceMotion) {
        _fill.value = 1;
      } else {
        _fill.forward();
      }
    });
  }

  void _exit(PointerEvent event) {
    _delay?.cancel();
    if (_reduceMotion) {
      _fill.value = 0;
    } else {
      _fill.reverse();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: _enter,
    onHover: (event) {
      if (_delay?.isActive == true) _origin = event.localPosition;
    },
    onExit: _exit,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: AnimatedBuilder(
        animation: _fill,
        child: widget.content(Colors.black),
        builder: (context, child) => Stack(
          fit: StackFit.passthrough,
          children: [
            child!,
            if (_fill.value > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ClipPath(
                      clipper: _CursorFillClipper(
                        _origin,
                        Curves.easeOutCubic.transform(_fill.value),
                      ),
                      child: ColoredBox(
                        color: Colors.black,
                        child: widget.content(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CursorFillClipper extends CustomClipper<Path> {
  const _CursorFillClipper(this.origin, this.progress);

  final Offset origin;
  final double progress;

  @override
  Path getClip(Size size) {
    final farthestCorner = Offset(
      math.max(origin.dx, size.width - origin.dx),
      math.max(origin.dy, size.height - origin.dy),
    );
    return Path()..addOval(
      Rect.fromCircle(
        center: origin,
        radius: farthestCorner.distance * progress,
      ),
    );
  }

  @override
  bool shouldReclip(_CursorFillClipper oldClipper) =>
      oldClipper.origin != origin || oldClipper.progress != progress;
}
