import 'package:flutter/material.dart';

const Color cream = Color(0xFFF3E7CF);
const Color paper = Color(0xFFFBF4E4);
const Color ink = Color(0xFF111111);
const Color mute = Color(0xFF6B6153);
const Color orange = Color(0xFFF9812B);
const Color tomato = Color(0xFFF2705F);
const Color pink = Color(0xFFF9A8C9);
const Color blue = Color(0xFF8CB8E8);
const Color yellow = Color(0xFFF8CE46);
const Color green = Color(0xFF90D48C);
const Color teal = Color(0xFF6FC7B9);
const Color grape = Color(0xFFA98BF2);

const List<BoxShadow> brutalShadow = [
  BoxShadow(color: ink, offset: Offset(4, 4), blurRadius: 0),
];

const List<BoxShadow> brutalShadowSmall = [
  BoxShadow(color: ink, offset: Offset(2, 2), blurRadius: 0),
];

TextStyle display(
  double size, {
  Color color = ink,
  double height = 0.92,
  double letterSpacing = -0.1,
}) {
  return TextStyle(
    fontFamily: 'Archivo Black',
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
  );
}

TextStyle grotesk(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = ink,
  double? height,
  double? letterSpacing,
  TextDecoration? decoration,
}) {
  return TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
  );
}

class BrutalCard extends StatelessWidget {
  const BrutalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = paper,
    this.radius = 12,
    this.shadow = true,
    this.borderWidth = 3,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final bool shadow;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ink, width: borderWidth),
        boxShadow: shadow ? brutalShadow : null,
      ),
      child: child,
    );
  }
}

class BrutalButton extends StatefulWidget {
  const BrutalButton({
    super.key,
    required this.child,
    this.onPressed,
    this.color = orange,
    this.foreground = ink,
    this.height = 46,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.radius = 10,
    this.expand = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  final double height;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool expand;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            _pressed ? 3 : 0,
            _pressed ? 3 : 0,
            0,
          ),
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _enabled ? widget.color : widget.color.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: ink, width: 3),
            boxShadow: _pressed || !_enabled ? null : brutalShadow,
          ),
          child: Center(
            widthFactor: widget.expand ? null : 1,
            heightFactor: 1,
            child: IconTheme.merge(
              data: IconThemeData(color: widget.foreground, size: 18),
              child: DefaultTextStyle(
                style: grotesk(
                  12,
                  weight: FontWeight.w700,
                  color: widget.foreground,
                  letterSpacing: 0.2,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Sticker extends StatelessWidget {
  const Sticker({
    super.key,
    required this.child,
    this.color = pink,
    this.angle = 0,
  });

  final Widget child;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ink, width: 2),
          boxShadow: brutalShadowSmall,
        ),
        child: DefaultTextStyle(
          style: grotesk(
            10,
            weight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          child: child,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.color = paper,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ink, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        style: grotesk(9.5, weight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }
}

class DotGridPainter extends CustomPainter {
  const DotGridPainter({
    this.color = const Color(0x26111111),
    this.spacing = 22,
    this.radius = 0.9,
  });

  final Color color;
  final double spacing;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x <= size.width; x += spacing) {
      for (var y = 0.0; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.spacing != spacing ||
        oldDelegate.radius != radius;
  }
}
