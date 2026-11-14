import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

/// Thin wrapper around Firebase Auth.
///
/// Users sign in anonymously; the name they pick is stored as the Firebase
/// profile `displayName`, so it survives app restarts without extra storage.
class AuthService {
  AuthService(this._auth);

  static const int maxNameLength = 20;

  final FirebaseAuth _auth;

  /// The user restored from the previous session, if any.
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  /// Emits on sign-in, sign-out and profile (display name) updates.
  Stream<AppUser?> userChanges() => _auth.userChanges().map(_toAppUser);

  /// Signs in anonymously when needed and stores [name] on the profile.
  Future<AppUser> join(String name) async {
    final trimmed = name.trim();
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'null-user',
        message: 'Anonymous sign-in returned no user.',
      );
    }
    if (user.displayName != trimmed) await user.updateDisplayName(trimmed);
    return AppUser(uid: user.uid, name: trimmed);
  }

  /// Ends the session. Anonymous accounts cannot be signed into again, so
  /// the account is removed instead of being left orphaned.
  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.delete();
        return;
      } on FirebaseAuthException {
        // For example `requires-recent-login`: fall back to a plain sign-out.
      }
    }
    await _auth.signOut();
  }

  /// Human readable text for the errors users can actually act on.
  static String describeError(Object error) {
    if (error is! FirebaseAuthException) {
      return 'Something went wrong. Please try again.';
    }
    final code = error.code;
    final message = error.message?.trim() ?? '';
    switch (code) {
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
        return 'Anonymous sign-in is disabled. Enable it in the Firebase '
            'console under Authentication → Sign-in method.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
    }
    // Named by the code in a browser, inside the message on a phone.
    if (code == 'configuration-not-found' ||
        message.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication is not set up yet. In the Firebase '
          'console open Authentication, press Get started and enable '
          'Anonymous.';
    }
    if (code.contains('api-key')) {
      return 'Firebase rejected the API key of this app. '
          'Run flutterfire configure again.';
    }
    // In a browser the SDK describes most failures as just "Error".
    if (message.isEmpty || message == 'Error') {
      return 'Sign-in failed ($code).';
    }
    return message;
  }

  static AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(uid: user.uid, name: user.displayName?.trim() ?? '');
  }
}
