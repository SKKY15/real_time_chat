import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/theme/app_theme.dart';
import 'package:real_time_chat/theme/chat_colors.dart';
import 'package:real_time_chat/widgets/user_avatar.dart';

/// Contrast ratio of [foreground] drawn on [background], as defined by WCAG
/// (1 = no contrast, 21 = black on white). A translucent foreground is
/// blended onto the background first.
double contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.build(Brightness.light, applyFont: (text) => text),
    'dark': AppTheme.build(Brightness.dark, applyFont: (text) => text),
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    final colors = theme.extension<ChatColors>()!;
    final scheme = theme.colorScheme;

    group('$name theme', () {
      test('message text is easy to read on its bubble', () {
        expect(contrast(colors.onAccent, colors.accent), greaterThan(7));
        expect(contrast(colors.onIncoming, colors.incoming), greaterThan(7));
      });

      test('times and labels reach the contrast of small text', () {
        expect(contrast(colors.outgoingMeta, colors.accent), greaterThan(4.5));
        expect(
          contrast(colors.incomingMeta, colors.incoming),
          greaterThan(4.5),
        );
        expect(contrast(colors.onPill, colors.pill), greaterThan(4.5));
        // The typing label and the hint of the message field.
        expect(contrast(colors.incomingMeta, scheme.surface), greaterThan(4));
        expect(contrast(colors.incomingMeta, colors.inputFill), greaterThan(4));
      });

      test('delivery icons stand out on my bubbles', () {
        expect(contrast(colors.seen, colors.accent), greaterThan(3));
        expect(contrast(colors.outgoingAlert, colors.accent), greaterThan(3));
      });

      test('names of the other participants are readable', () {
        final brightness = theme.brightness;
        final tones = <Color>{
          for (var i = 0; i < 200; i++) colorForUser('user$i', brightness),
        };
        expect(tones.length, greaterThan(4));
        for (final tone in tones) {
          expect(contrast(tone, colors.incoming), greaterThan(4.5));
        }
      });

      test('text buttons, the cursor and icons are readable on the bars', () {
        expect(
          contrast(scheme.primary, scheme.surfaceContainer),
          greaterThan(7),
        );
        expect(
          contrast(scheme.onSurfaceVariant, scheme.surfaceContainer),
          greaterThan(4.5),
        );
      });
    });
  }

  test('an initial is readable on every avatar', () {
    final fills = <Color>{
      for (var i = 0; i < 200; i++) avatarColorForUser('user$i'),
    };
    expect(fills.length, greaterThan(4));
    for (final fill in fills) {
      expect(contrast(Colors.white, fill), greaterThan(3));
    }
  });

  test('a participant keeps the same color', () {
    expect(avatarColorForUser('sara'), avatarColorForUser('sara'));
    expect(
      colorForUser('sara', Brightness.light),
      colorForUser('sara', Brightness.light),
    );
  });

  test('the chat palette blends from one theme into the other', () {
    const light = ChatColors.light;
    const dark = ChatColors.dark;
    expect(light.lerp(dark, 0).incoming, light.incoming);
    expect(light.lerp(dark, 1).incoming, dark.incoming);
    final halfway = light.lerp(dark, 0.5);
    expect(halfway.incoming, isNot(light.incoming));
    expect(halfway.incoming, isNot(dark.incoming));
    // The accent is the same in both themes and does not move.
    expect(halfway.accent, ChatColors.marigold);
  });
}
