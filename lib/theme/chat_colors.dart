import 'package:material_ui/material_ui.dart';

/// The chat's own palette: everything Material's [ColorScheme] has no slot
/// for.
///
/// The look rests on two colors. [marigold] fills what is mine or asks to be
/// pressed (my bubbles, the send button, badges, the logo) and [ink] is drawn
/// on top of it. Everything else is a warm neutral: stone by day, charcoal by
/// night. Nothing is a gradient.
///
/// To restyle the app, change [marigold] and [ink] and adjust the neutrals
/// in [light] and [dark]. `test/theme_test.dart` checks that text stays
/// readable.
///
/// Read with `ChatColors.of(context)`.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.accent,
    required this.onAccent,
    required this.outgoingMeta,
    required this.outgoingQuote,
    required this.outgoingAlert,
    required this.incoming,
    required this.onIncoming,
    required this.incomingMeta,
    required this.incomingQuote,
    required this.seen,
    required this.highlight,
    required this.pill,
    required this.onPill,
    required this.inputFill,
    required this.hairline,
    required this.bezel,
  });

  /// The accent. The same in both themes, so the app is recognisable in
  /// either.
  static const Color marigold = Color(0xFFFFC83D);

  /// Text and icons on [marigold].
  static const Color ink = Color(0xFF1A1708);

  static const ChatColors light = ChatColors(
    accent: marigold,
    onAccent: ink,
    outgoingMeta: Color(0xB31A1708), // ink at 70 %
    outgoingQuote: Color(0x14000000),
    outgoingAlert: Color(0xFFA51D14),
    incoming: Color(0xFFFFFFFF),
    onIncoming: Color(0xFF1B1A15),
    incomingMeta: Color(0xFF716F65),
    incomingQuote: Color(0xFFF3F2ED),
    seen: Color(0xFF1D4ED8),
    highlight: Color(0x66FFC83D), // marigold at 40 %
    pill: Color(0xFFE6E4DD),
    onPill: Color(0xFF605E55),
    inputFill: Color(0xFFF1F0EB),
    hairline: Color(0x14000000),
    bezel: Color(0xFF3A382F),
  );

  static const ChatColors dark = ChatColors(
    accent: marigold,
    onAccent: ink,
    outgoingMeta: Color(0xB31A1708), // ink at 70 %
    outgoingQuote: Color(0x17000000),
    outgoingAlert: Color(0xFFA51D14),
    incoming: Color(0xFF272724),
    onIncoming: Color(0xFFF0EEE6),
    incomingMeta: Color(0xFF9C9A8F),
    incomingQuote: Color(0xFF33332F),
    seen: Color(0xFF1D4ED8),
    highlight: Color(0x38FFC83D), // marigold at 22 %
    pill: Color(0xFF22221F),
    onPill: Color(0xFFA3A196),
    inputFill: Color(0xFF272724),
    hairline: Color(0x14FFFFFF),
    bezel: Color(0xFF0C0C0B),
  );

  static ChatColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChatColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// Fill of my own bubbles, the send button, badges and the logo.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Time, "edited" and the delivery icon inside my own bubbles.
  final Color outgoingMeta;

  /// Background of a quote inside my own bubbles.
  final Color outgoingQuote;

  /// "Not sent" icon inside my own bubbles.
  final Color outgoingAlert;

  final Color incoming;
  final Color onIncoming;
  final Color incomingMeta;
  final Color incomingQuote;

  /// Color of the double check once a message has been seen.
  final Color seen;

  /// Tint flashed over a message after jumping to it from a quote.
  final Color highlight;

  /// Background and text of the date separator pill.
  final Color pill;
  final Color onPill;

  /// Fill of the message field inside the input bar.
  final Color inputFill;
  final Color hairline;

  /// The wall around the rounded screen (see `RoundedWindow`). Darker than the
  /// canvas in both themes, so the edge of the screen reads as an edge.
  final Color bezel;

  @override
  ChatColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? outgoingMeta,
    Color? outgoingQuote,
    Color? outgoingAlert,
    Color? incoming,
    Color? onIncoming,
    Color? incomingMeta,
    Color? incomingQuote,
    Color? seen,
    Color? highlight,
    Color? pill,
    Color? onPill,
    Color? inputFill,
    Color? hairline,
    Color? bezel,
  }) {
    return ChatColors(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      outgoingMeta: outgoingMeta ?? this.outgoingMeta,
      outgoingQuote: outgoingQuote ?? this.outgoingQuote,
      outgoingAlert: outgoingAlert ?? this.outgoingAlert,
      incoming: incoming ?? this.incoming,
      onIncoming: onIncoming ?? this.onIncoming,
      incomingMeta: incomingMeta ?? this.incomingMeta,
      incomingQuote: incomingQuote ?? this.incomingQuote,
      seen: seen ?? this.seen,
      highlight: highlight ?? this.highlight,
      pill: pill ?? this.pill,
      onPill: onPill ?? this.onPill,
      inputFill: inputFill ?? this.inputFill,
      hairline: hairline ?? this.hairline,
      bezel: bezel ?? this.bezel,
    );
  }

  @override
  ChatColors lerp(ThemeExtension<ChatColors>? other, double t) {
    if (other is! ChatColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return ChatColors(
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      outgoingMeta: mix(outgoingMeta, other.outgoingMeta),
      outgoingQuote: mix(outgoingQuote, other.outgoingQuote),
      outgoingAlert: mix(outgoingAlert, other.outgoingAlert),
      incoming: mix(incoming, other.incoming),
      onIncoming: mix(onIncoming, other.onIncoming),
      incomingMeta: mix(incomingMeta, other.incomingMeta),
      incomingQuote: mix(incomingQuote, other.incomingQuote),
      seen: mix(seen, other.seen),
      highlight: mix(highlight, other.highlight),
      pill: mix(pill, other.pill),
      onPill: mix(onPill, other.onPill),
      inputFill: mix(inputFill, other.inputFill),
      hairline: mix(hairline, other.hairline),
      bezel: mix(bezel, other.bezel),
    );
  }
}
