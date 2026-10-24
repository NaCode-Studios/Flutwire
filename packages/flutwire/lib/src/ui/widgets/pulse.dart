import 'package:flutter/material.dart';

/// Fades its child out and in a few times, to say that something is going on,
/// and then holds still.
///
/// It beats when it first appears active, when it becomes active, and when
/// [restartOn] notifies after the beats are over. It never goes on until told
/// to stop: an animation that runs for as long as the inspector is open keeps
/// the app drawing a frame on every refresh for nothing. It holds still as well
/// when the system asks for reduced motion.
class Pulse extends StatefulWidget {
  /// Pulses [child].
  const Pulse({
    super.key,
    required this.child,
    this.active = true,
    this.restartOn,
  });

  /// What pulses.
  final Widget child;

  /// Whether it pulses at all.
  final bool active;

  /// Makes it beat again each time it notifies, as new traffic does.
  final Listenable? restartOn;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  static const int _beats = 3;
  static const Duration _beat = Duration(milliseconds: 2200);

  /// Out to a dim and back in, once for each beat, ending as it began.
  static final Animatable<double> _fade = TweenSequence<double>([
    for (var i = 0; i < _beats; i++) ...[
      _half(from: 1, to: 0.4),
      _half(from: 0.4, to: 1),
    ],
  ]);

  static TweenSequenceItem<double> _half({
    required double from,
    required double to,
  }) => TweenSequenceItem(
    tween: Tween<double>(
      begin: from,
      end: to,
    ).chain(CurveTween(curve: Curves.easeInOut)),
    weight: 1,
  );

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _beat * _beats,
  );
  late final Animation<double> _opacity = _controller.drive(_fade);

  bool _reduced = false;

  /// Whether the beats for the current activation have been started.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.restartOn?.addListener(_restart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _hold();
    } else if (widget.active && !_started) {
      _begin();
    }
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (old.restartOn != widget.restartOn) {
      old.restartOn?.removeListener(_restart);
      widget.restartOn?.addListener(_restart);
    }
    if (!widget.active) {
      if (old.active) _hold();
    } else if (!_started && !_reduced) {
      _begin();
    }
  }

  @override
  void dispose() {
    widget.restartOn?.removeListener(_restart);
    _controller.dispose();
    super.dispose();
  }

  void _begin() {
    _started = true;
    _controller.forward(from: 0);
  }

  void _hold() {
    _started = false;
    _controller.stop();
    _controller.value = 0;
  }

  /// Notifications come in bursts, and one call tells of itself several times
  /// as it goes. Those that arrive while the beats play do not add to them.
  void _restart() {
    if (!widget.active || _reduced || _controller.isAnimating) return;
    _begin();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _reduced) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
