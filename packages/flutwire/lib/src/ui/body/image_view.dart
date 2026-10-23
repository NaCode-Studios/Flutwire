import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../util/format.dart';
import '../scope.dart';

/// An image that can be zoomed from 1x to 8x, on a checkerboard so that
/// transparency can be seen.
///
/// A body that was cut short usually cannot be drawn. That is expected: the
/// view says so and offers the bytes in hex instead.
class ImageView extends StatefulWidget {
  /// Shows the image in [bytes]. [onShowHex] is called when the user asks to
  /// see the bytes of an image that could not be drawn.
  const ImageView({super.key, required this.bytes, required this.onShowHex});

  /// The encoded image.
  final Uint8List bytes;

  /// Switches the viewer to the hex view.
  final VoidCallback onShowHex;

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late MemoryImage _provider;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onError,
  );
  ImageStream? _stream;
  Size? _size;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _stream?.removeListener(_listener);
      _size = null;
      _failed = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolve() {
    _provider = MemoryImage(widget.bytes);
    _stream = _provider.resolve(ImageConfiguration.empty)
      ..addListener(_listener);
  }

  // The size comes from the decoded image, so it is known only after the
  // decode, which is why the chip first shows the byte size alone.
  void _onImage(ImageInfo info, bool synchronousCall) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    if (!mounted || size == _size) return;
    setState(() => _size = size);
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final strings = context.strings;
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 32, color: tokens.faint),
              const SizedBox(height: 10),
              Text(
                strings.imageFailed,
                textAlign: TextAlign.center,
                style: tokens.body(color: tokens.muted),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: widget.onShowHex,
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.ink,
                  side: BorderSide(color: tokens.lineStrong),
                  minimumSize: const Size(40, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(strings.viewHex),
              ),
            ],
          ),
        ),
      );
    }
    final size = _size;
    final info = [
      if (size != null)
        strings.imageSize(size.width.round(), size.height.round()),
      formatBytes(widget.bytes.length),
    ].join('  ·  ');
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: Center(
              child: CustomPaint(
                painter: _Checkerboard(
                  first: tokens.surface,
                  second: tokens.isDark ? tokens.raised : tokens.line,
                ),
                child: Image(
                  image: _provider,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.lineStrong),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                info,
                style: tokens.mono(size: 11.5, color: tokens.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two greys in a chessboard, behind the image.
class _Checkerboard extends CustomPainter {
  const _Checkerboard({required this.first, required this.second});

  final Color first;
  final Color second;

  static const double _tile = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = first);
    final paint = Paint()..color = second;
    for (var y = 0; y * _tile < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * _tile < size.width; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(x * _tile, y * _tile, _tile, _tile).intersect(bounds),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard old) =>
      old.first != first || old.second != second;
}
