import 'package:flutter/material.dart';

class MadaLogo extends StatelessWidget {
  final double height;
  const MadaLogo({super.key, this.height = 48});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        widthFactor: 0.68,
        heightFactor: 0.66,
        child: Image.asset(
          dark
              ? 'assets/images/mada_logo_dark.png'
              : 'assets/images/mada_logo.png',
          height: height / 0.66,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
