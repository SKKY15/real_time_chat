import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'auth/auth_gate.dart';
import 'chat/chat_app_bar.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/rounded_window.dart';

/// Root widget: Material 3 light and dark themes around the auth gate.
class ChatApp extends ConsumerWidget {
  const ChatApp({super.key, this.theme, this.darkTheme});

  /// Replace [AppTheme.light] and [AppTheme.dark]. Tests use this, because
  /// the real themes download their font.
  final ThemeData? theme;
  final ThemeData? darkTheme;

  /// Transparent status bar and a navigation bar in the color of the input
  /// bar, both with icons that stay readable in the current theme.
  static SystemUiOverlayStyle _systemBars(ThemeData theme) {
    final iconBrightness = theme.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: theme.colorScheme.surfaceContainer,
      systemNavigationBarIconBrightness: iconBrightness,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: ChatAppBar.roomName,
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.light,
      darkTheme: darkTheme ?? AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeOutCubic,
      // The window decides: a phone gets the app as it is, a browser window
      // gets the rounded screen and the walls around it.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemBars(Theme.of(context)),
        child: RoundedWindow(child: child ?? const SizedBox.shrink()),
      ),
      home: const AuthGate(),
    );
  }
}
