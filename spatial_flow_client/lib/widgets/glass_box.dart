import 'dart:ui';
import 'package:flutter/material.dart';

class GlassBox extends StatelessWidget {
  final Widget child;
  final double width;
  final double? height;
  final double opacity;
  final EdgeInsets padding;
  final bool borderGlow; // If true, border glows (for Conference Mode)

  const GlassBox({
    Key? key,
    required this.child,
    this.width = double.infinity,
    this.height,
    this.opacity = 0.1,
    this.padding = const EdgeInsets.all(20),
    this.borderGlow = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        // The Blur Effect
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            // The "Frost" Gradient
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(opacity + 0.1),
                Colors.white.withOpacity(opacity),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // The "Ice" Border
            border: Border.all(
              color: borderGlow 
                  ? Colors.purpleAccent.withOpacity(0.6) 
                  : Colors.white.withOpacity(0.2),
              width: borderGlow ? 2 : 1.5,
            ),
            boxShadow: borderGlow 
                ? [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 20)] 
                : [],
          ),
          child: child,
        ),
      ),
    );
  }
}