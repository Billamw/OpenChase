import 'package:flutter/material.dart';

class UiHelper {
  static EdgeInsets getResponsivePadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width > 600 ? 100 : 16,
    );
  }

  static double getResponsiveWidth(BuildContext context) {
    return MediaQuery.of(context).size.width > 600 ? 100 : 16;
  }

  static const double vertical = 16;

  static String getLogoPath(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? 'images/logo_light_1024.png'
        : 'images/logo_dark_1024.png';
  }
}
