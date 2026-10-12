import 'package:flutter/material.dart';

/// Visual theme applied to the bundled Chatly UI.
///
/// All colours default to Chatly's brand palette. Override individual fields
/// to match your product. Pass an instance through [ChatlyConfig.theme].
class ChatlyTheme {
  /// Creates a [ChatlyTheme]. All parameters have sensible defaults.
  const ChatlyTheme({
    this.primary = const Color(0xFF2563EB),
    this.onPrimary = const Color(0xFFFFFFFF),
    this.background = const Color(0xFFFFFFFF),
    this.foreground = const Color(0xFF0F172A),
    this.mutedForeground = const Color(0xFF64748B),
    this.surface = const Color(0xFFF8FAFC),
    this.border = const Color(0xFFE2E8F0),
    this.danger = const Color(0xFFDC2626),
    this.borderRadius = 16.0,
    this.fontFamily,
    this.headerTitle = 'Chat with us',
  });

  /// Primary brand colour. Applied to send buttons, agent bubbles, etc.
  final Color primary;

  /// Foreground colour on top of [primary] (button label / icon).
  final Color onPrimary;

  /// Page background colour.
  final Color background;

  /// Primary text / icon colour.
  final Color foreground;

  /// Secondary text colour (timestamps, hints).
  final Color mutedForeground;

  /// Surface colour for contact bubbles, input fields, cards.
  final Color surface;

  /// Border / divider colour.
  final Color border;

  /// Destructive action colour (errors).
  final Color danger;

  /// Corner radius applied to bubbles, inputs, and cards.
  final double borderRadius;

  /// Optional font family. Defaults to the platform's Material 3 default.
  final String? fontFamily;

  /// Header text shown at the top of the chat page.
  final String headerTitle;

  /// Returns a [ColorScheme] derived from this theme, suitable for Material
  /// 3 widgets.
  ColorScheme toColorScheme(Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      surface: background,
      onSurface: foreground,
      surfaceContainerHighest: surface,
      outline: border,
      error: danger,
    );
  }

  /// Returns a [ThemeData] derived from this theme.
  ThemeData toThemeData(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final scheme = toColorScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
    );
  }
}
