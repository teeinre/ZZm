import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';

class BrandLogo extends StatelessWidget {
  final double? height;
  final double? width;

  const BrandLogo({super.key, this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      height: height,
      width: width,
      semanticsLabel: 'ZZmore Store Logo',
    );
  }
}

// Fallback logo widget in case SVG isn't available
class BrandLogoFallback extends StatelessWidget {
  final double fontSize;
  const BrandLogoFallback({super.key, this.fontSize = 28});

  @override
  Widget build(BuildContext context) {
    return Text(
      'ZZmore.store',
      style: TextStyle(
        color: AppColors.goldColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        fontFamily: 'Fraunces',
      ),
    );
  }
}