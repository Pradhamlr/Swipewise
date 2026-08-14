import 'package:flutter/material.dart';

/// The app's design tokens, exposed as a [ThemeExtension].
///
/// Everything visual reads colours and spacing from here rather than from
/// `neopop` directly. `neopop` is CRED's published design system and using it
/// is a deliberate signal, but scattering its widgets through the tree would
/// make this a demo *of* neopop and would weld the app to it. Behind a token
/// layer the design system is swappable and the app keeps its own identity.
///
/// Reached via `Theme.of(context).extension<SwipewiseTokens>()!`, or the
/// shorter `context.tokens` below.
@immutable
class SwipewiseTokens extends ThemeExtension<SwipewiseTokens> {
  const SwipewiseTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.accent,
    required this.warning,
    required this.danger,
    required this.textHigh,
    required this.textMuted,
  });

  static const dark = SwipewiseTokens(
    background: Color(0xFF08080C),
    surface: Color(0xFF14141C),
    surfaceRaised: Color(0xFF1E1E2A),
    border: Color(0xFF2A2A38),
    accent: Color(0xFF00E0A4),
    warning: Color(0xFFFFB020),
    danger: Color(0xFFFF5A5F),
    textHigh: Color(0xFFF4F4F7),
    textMuted: Color(0xFF8A8A9E),
  );

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;

  /// Used for the healthy portion of a cap, and for the winning card.
  final Color accent;

  /// A cap that this transaction will push close to its limit.
  final Color warning;

  /// A cap already exhausted.
  final Color danger;

  final Color textHigh;
  final Color textMuted;

  /// Spacing scale. Kept as a ramp so padding never becomes arbitrary.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;

  static const double radius = 14;

  /// Colour for a bucket that is [fraction] consumed.
  Color forUtilisation(double fraction) {
    if (fraction >= 1) return danger;
    if (fraction >= 0.8) return warning;
    return accent;
  }

  @override
  SwipewiseTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? accent,
    Color? warning,
    Color? danger,
    Color? textHigh,
    Color? textMuted,
  }) {
    return SwipewiseTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      textHigh: textHigh ?? this.textHigh,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  SwipewiseTokens lerp(ThemeExtension<SwipewiseTokens>? other, double t) {
    if (other is! SwipewiseTokens) return this;
    return SwipewiseTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      textHigh: Color.lerp(textHigh, other.textHigh, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

extension SwipewiseThemeContext on BuildContext {
  SwipewiseTokens get tokens =>
      Theme.of(this).extension<SwipewiseTokens>() ?? SwipewiseTokens.dark;
}

/// Builds the app's [ThemeData] from a token set.
ThemeData buildSwipewiseTheme(SwipewiseTokens tokens) {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: tokens.background,
    colorScheme: base.colorScheme.copyWith(
      primary: tokens.accent,
      surface: tokens.surface,
      error: tokens.danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: tokens.textHigh,
      displayColor: tokens.textHigh,
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}
