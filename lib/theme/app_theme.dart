import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_colors.dart';

/// Material 3 light and dark themes of the app.
///
/// The colors come from [ChatColors]: a warm neutral ground (stone by day,
/// charcoal by night) and one accent, marigold. Material's own color roles
/// are mapped onto them here, so that stock widgets (menus, buttons, snack
/// bars, text selection) fit in without being styled one by one.
///
/// The typeface is Rubik: one family for Latin, Arabic, Hebrew and Cyrillic,
/// so a conversation that mixes scripts keeps one voice.
///
/// Typography note: a text style created by `google_fonts` is tied to one
/// font file, so `copyWith(fontWeight: ...)` on it would only produce a
/// synthetic bold. The weights are therefore decided here, before the font is
/// applied, and widgets use the slots below without changing the weight:
///
///  * `headlineSmall`, `titleLarge`, `titleMedium`, `labelLarge`,
///    `labelMedium` - bold
///  * everything else - regular
abstract final class AppTheme {
  static final ThemeData light = build(Brightness.light);
  static final ThemeData dark = build(Brightness.dark);

  /// Builds the theme for [brightness].
  ///
  /// [applyFont] puts the typeface on the finished type scale. Tests replace
  /// it, because they cannot download fonts.
  static ThemeData build(
    Brightness brightness, {
    TextTheme Function(TextTheme textTheme) applyFont =
        GoogleFonts.rubikTextTheme,
  }) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? ChatColors.dark : ChatColors.light;
    final scheme = _scheme(brightness, colors);
    final base = ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
    final textTheme = applyFont(_typeScale(base.textTheme));

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      // Every filled button is a marigold one, in both themes.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          iconColor: colors.onAccent,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: colors.hairline),
        ),
        textStyle: textTheme.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      // Selected text looks as if it was marked with a highlighter.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: colors.accent.withValues(alpha: isDark ? 0.35 : 0.55),
        selectionHandleColor: scheme.primary,
      ),
    );
  }

  /// Material's color roles, filled from the chat palette.
  ///
  /// The accent is too light to be read as text on a light surface, so the
  /// light theme uses ink as `primary` (text buttons, the cursor, focus
  /// rings) and keeps marigold for fills. The dark theme uses marigold for
  /// both.
  static ColorScheme _scheme(Brightness brightness, ChatColors colors) {
    final seeded = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    );
    if (brightness == Brightness.dark) {
      return seeded.copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        primaryContainer: const Color(0xFF4A3B0A),
        onPrimaryContainer: const Color(0xFFFFE39A),
        secondary: const Color(0xFFCBC8BA),
        onSecondary: const Color(0xFF1B1A15),
        secondaryContainer: const Color(0xFF3A3212),
        onSecondaryContainer: const Color(0xFFFFE08A),
        surface: const Color(0xFF141412),
        onSurface: const Color(0xFFF0EEE6),
        onSurfaceVariant: const Color(0xFFB5B2A6),
        surfaceContainerLowest: const Color(0xFF0E0E0D),
        surfaceContainerLow: const Color(0xFF181816),
        surfaceContainer: const Color(0xFF1B1B18),
        surfaceContainerHigh: const Color(0xFF262623),
        surfaceContainerHighest: const Color(0xFF31312D),
        surfaceTint: Colors.transparent,
        outline: const Color(0xFF8D8A7E),
        outlineVariant: const Color(0xFF3A3934),
        inverseSurface: const Color(0xFFF0EEE6),
        onInverseSurface: const Color(0xFF1B1A15),
        inversePrimary: const Color(0xFF6B5200),
      );
    }
    return seeded.copyWith(
      primary: const Color(0xFF1B1A15),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFFFE49A),
      onPrimaryContainer: const Color(0xFF241A00),
      secondary: const Color(0xFF5C5A50),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFFFE7A6),
      onSecondaryContainer: const Color(0xFF2A2000),
      surface: const Color(0xFFF1F0EB),
      onSurface: const Color(0xFF1B1A15),
      onSurfaceVariant: const Color(0xFF5F5D54),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8F7F3),
      surfaceContainer: const Color(0xFFFFFFFF),
      surfaceContainerHigh: const Color(0xFFFFFFFF),
      surfaceContainerHighest: const Color(0xFFE9E7E0),
      surfaceTint: Colors.transparent,
      outline: const Color(0xFF8A887E),
      outlineVariant: const Color(0xFFD9D7CF),
      inverseSurface: const Color(0xFF2A2925),
      onInverseSurface: const Color(0xFFF3F1EA),
      inversePrimary: colors.accent,
    );
  }

  /// Material's type scale with the weights and the tracking this app uses.
  ///
  /// Two weights only, regular and bold: every further weight is one more
  /// font file to download. Material's tracking is made for Roboto. Rubik is
  /// wider, so running text gets none and titles are set a little tighter.
  static TextTheme _typeScale(TextTheme base) {
    TextStyle? tuned(TextStyle? style, FontWeight weight, double tracking) =>
        style?.copyWith(fontWeight: weight, letterSpacing: tracking);
    const regular = FontWeight.w400;
    const bold = FontWeight.w700;
    return base.copyWith(
      headlineSmall: tuned(base.headlineSmall, bold, -0.3),
      titleLarge: tuned(base.titleLarge, bold, -0.2),
      titleMedium: tuned(base.titleMedium, bold, -0.1),
      titleSmall: tuned(base.titleSmall, regular, 0),
      bodyLarge: tuned(base.bodyLarge, regular, 0),
      bodyMedium: tuned(base.bodyMedium, regular, 0),
      bodySmall: tuned(base.bodySmall, regular, 0.1),
      labelLarge: tuned(base.labelLarge, bold, 0),
      labelMedium: tuned(base.labelMedium, bold, 0.1),
      labelSmall: tuned(base.labelSmall, regular, 0.1),
    );
  }
}
