import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/services/auth_service.dart';

void main() {
  group('AuthService.describeError', () {
    String describe(String code, [String? message]) {
      final error = FirebaseAuthException(code: code, message: message);
      return AuthService.describeError(error);
    }

    test('says where to enable anonymous sign-in', () {
      const codes = ['operation-not-allowed', 'admin-restricted-operation'];
      for (final code in codes) {
        expect(describe(code, 'Error'), contains('Sign-in method'));
      }
    });

    test('says how to set up Authentication, on every platform', () {
      const hint = 'press Get started and enable Anonymous';
      // A browser names the code, a phone only mentions it in the message.
      const onPhone =
          'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]';
      expect(describe('configuration-not-found', 'Error'), contains(hint));
      expect(describe('unknown', onPhone), contains(hint));
    });

    test('points at the configuration when the API key is rejected', () {
      const codes = [
        'invalid-api-key',
        'api-key-not-valid.-please-pass-a-valid-api-key.',
      ];
      for (final code in codes) {
        expect(describe(code, 'Error'), contains('flutterfire configure'));
      }
    });

    test('names connection problems and rate limits', () {
      expect(describe('network-request-failed'), contains('internet'));
      expect(describe('too-many-requests'), contains('wait'));
    });

    test('shows the code instead of a message that says nothing', () {
      const text = 'Sign-in failed (quota-exceeded).';
      expect(describe('quota-exceeded', 'Error'), text);
      expect(describe('quota-exceeded', '  '), text);
      expect(describe('quota-exceeded'), text);
    });

    test('keeps a message that explains the failure', () {
      const text = 'This account has been disabled.';
      expect(describe('user-disabled', text), text);
    });

    test('anything that is not a sign-in error is a generic failure', () {
      expect(
        AuthService.describeError(StateError('offline')),
        'Something went wrong. Please try again.',
      );
    });
  });
}
