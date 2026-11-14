import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'chat_repository.dart';
import 'demo_seeder.dart';
import 'firestore_chat_repository.dart';

/// Firebase entry points. Override these in tests to swap in fakes.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(firebaseAuthProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => FirestoreChatRepository(ref.watch(firestoreProvider)),
);

final demoSeederProvider = Provider<DemoSeeder>(
  (ref) => DemoSeeder(ref.watch(firestoreProvider)),
);
