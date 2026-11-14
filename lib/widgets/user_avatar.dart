import 'package:material_ui/material_ui.dart';

/// The colors of one participant: [fill] for the avatar, [onLight] and
/// [onDark] for the name inside an incoming bubble of each theme.
class _Tone {
  const _Tone(this.fill, this.onLight, this.onDark);

  final Color fill;
  final Color onLight;
  final Color onDark;
}

/// Hand-picked instead of spread around the color wheel: every tone keeps
/// its distance from the marigold of my own bubbles, and every name stays
/// readable on its bubble (see `test/theme_test.dart`).
const List<_Tone> _tones = <_Tone>[
  _Tone(Color(0xFF3B7DDD), Color(0xFF1F5FBF), Color(0xFF7FB2FF)), // blue
  _Tone(Color(0xFF1A9C90), Color(0xFF0E766D), Color(0xFF5FD0C4)), // teal
  _Tone(Color(0xFFD95A8C), Color(0xFFB62F6B), Color(0xFFFF8FB8)), // rose
  _Tone(Color(0xFFB27650), Color(0xFF8A5632), Color(0xFFDDAA85)), // clay
  _Tone(Color(0xFF6C7A8C), Color(0xFF4A596B), Color(0xFFAAB7C8)), // slate
  _Tone(Color(0xFF3E9F5A), Color(0xFF23783F), Color(0xFF74CF8E)), // green
  _Tone(Color(0xFFE2573F), Color(0xFFBF3A22), Color(0xFFFF8B74)), // tomato
];

_Tone _toneOf(String userId) {
  var hash = 0;
  for (final unit in userId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _tones[hash % _tones.length];
}

/// Stable color for a participant's name, derived from their id.
Color colorForUser(String userId, Brightness brightness) {
  final tone = _toneOf(userId);
  return brightness == Brightness.dark ? tone.onDark : tone.onLight;
}

/// Stable color for a participant's avatar, derived from their id.
Color avatarColorForUser(String userId) => _toneOf(userId).fill;

/// Round avatar with the participant's initial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.size = 28,
  });

  final String userId;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColorForUser(userId),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontSize: size * 0.46,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
