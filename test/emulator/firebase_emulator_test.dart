// Runs the real data layer (sign-in, Firestore repository, message feed,
// sample data) and the security rules in firestore.rules against the
// Firebase Local Emulator Suite:
//
//   firebase emulators:exec --only auth,firestore \
//     --project demo-real-time-chat \
//     "flutter test --platform chrome test/emulator"
//
// The tests run in Chrome because Cloud Firestore has no implementation for
// the Dart VM that a plain `flutter test` uses. A plain `flutter test` skips
// this file.
@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:real_time_chat/chat/message_feed.dart';
import 'package:real_time_chat/chat/message_store.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/services/auth_service.dart';
import 'package:real_time_chat/services/chat_repository.dart';
import 'package:real_time_chat/services/demo_conversation.dart';
import 'package:real_time_chat/services/demo_seeder.dart';
import 'package:real_time_chat/services/firestore_chat_repository.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:1234567890:web:0123456789abcdef',
  messagingSenderId: '1234567890',
  projectId: 'demo-real-time-chat',
);

const Duration _patience = Duration(seconds: 20);

/// One participant with a Firebase app of its own, like one phone.
class _Client {
  _Client(this.auth, this.db);

  final FirebaseAuth auth;
  final FirebaseFirestore db;

  late final AuthService authService = AuthService(auth);

  String get uid => auth.currentUser!.uid;

  AppUser get user => authService.currentUser!;

  FirestoreChatRepository repository(String room) =>
      FirestoreChatRepository(db, roomId: room);

  CollectionReference<Map<String, dynamic>> messages(String room) =>
      db.collection('rooms').doc(room).collection('messages');

  CollectionReference<Map<String, dynamic>> typing(String room) =>
      db.collection('rooms').doc(room).collection('typing');

  /// Sends [text] through the repository and returns the message id.
  Future<String> send(String room, String text, {ReplyPreview? replyTo}) async {
    final repo = repository(room);
    final id = repo.newMessageId();
    await repo.sendMessage(
      ChatMessage(
        id: id,
        text: text,
        senderId: uid,
        senderName: user.name,
        createdAt: DateTime.now(),
        replyTo: replyTo,
        hasPendingWrites: true,
        hasServerTimestamp: false,
      ),
    );
    return id;
  }
}

/// Connects a Firebase app to the emulators. [name] `null` is the default
/// app.
///
/// A browser opens at most six connections to one host, and every Firestore
/// client keeps two of them open for as long as it is busy (one per stream).
/// Three clients on the same host therefore starve each other: requests
/// queue up in the browser until an idle stream is closed a minute later.
/// [firestoreHost] lets a client reach the emulator under another name, which
/// gives it connections of its own.
Future<_Client> _connect(
  String? name, {
  String firestoreHost = 'localhost',
}) async {
  final app = name == null
      ? await Firebase.initializeApp(options: _options)
      : await Firebase.initializeApp(name: name, options: _options);
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator('localhost', 9099);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.useFirestoreEmulator(firestoreHost, 8080);
  return _Client(auth, db);
}

var _rooms = 0;

/// Every test gets a room of its own; the rules are the same for all rooms.
String _newRoom() =>
    'room-${DateTime.now().microsecondsSinceEpoch}-${_rooms++}';

/// The first event of [stream] that satisfies [test].
Future<T> _first<T>(Stream<T> stream, bool Function(T event) test) =>
    stream.firstWhere(test).timeout(_patience);

/// The first snapshot confirmed by the server that satisfies [test].
Future<MessageBatch> _confirmed(
  Stream<MessageBatch> stream, [
  bool Function(MessageBatch batch)? test,
]) => _first(
  stream,
  (batch) =>
      !batch.isFromCache &&
      batch.messages.every((message) => !message.hasPendingWrites) &&
      (test == null || test(batch)),
);

List<String> _texts(Iterable<ChatMessage> messages) => <String>[
  for (final message in messages) message.text,
];

Future<void> _expectDenied(Future<Object?> request) async {
  try {
    await request;
  } on FirebaseException catch (error) {
    expect(error.code, 'permission-denied');
    return;
  }
  fail('The security rules should have rejected this request.');
}

/// A message document exactly as the app writes it.
Map<String, dynamic> _message(String senderId, {String text = 'Hi'}) =>
    <String, dynamic>{
      'text': text,
      'senderId': senderId,
      'senderName': 'Someone',
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
      'deleted': false,
      'replyTo': null,
      'seenBy': <String>[],
    };

void main() {
  late _Client alice;
  late _Client bob;
  late _Client guest;

  setUpAll(() async {
    // `flutter test` does not run the web plugin registrant, so the web
    // implementations are registered by hand.
    FirebaseCoreWeb.registerWith(webPluginRegistrar);
    FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
    FirebaseAuthWeb.registerWith(webPluginRegistrar);

    alice = await _connect(null);
    bob = await _connect('bob');
    guest = await _connect('guest', firestoreHost: '127.0.0.1');
    await alice.authService.join('Alice');
    await bob.authService.join('Bob');
  });

  group('sign-in', () {
    test('joining signs in anonymously and stores the name', () {
      expect(alice.auth.currentUser!.isAnonymous, isTrue);
      expect(alice.user, AppUser(uid: alice.uid, name: 'Alice'));
      expect(bob.user.name, 'Bob');
      expect(bob.uid, isNot(alice.uid));
      expect(guest.authService.currentUser, isNull);
    });

    test('name changes and sign-out are announced', () async {
      final carol = await _connect('carol');
      final service = carol.authService;

      final joined = _first(service.userChanges(), (user) => user != null);
      final returned = await service.join('  Carol ');
      expect(returned.name, 'Carol');
      expect(await joined, isNotNull);
      final uid = carol.uid;

      final renamed = _first(
        service.userChanges(),
        (user) => user?.name == 'Caro',
      );
      await service.join('Caro');
      expect((await renamed)!.uid, uid);
      expect(service.currentUser, AppUser(uid: uid, name: 'Caro'));

      final signedOut = _first(service.userChanges(), (user) => user == null);
      await service.signOut();
      await signedOut;
      expect(service.currentUser, isNull);
    });
  });

  group('messages', () {
    test('a sent message shows at once and is then confirmed', () async {
      final room = _newRoom();
      final repo = alice.repository(room);
      final states = <ChatMessage>[];
      final subscription = repo.watchLatest(30).listen((batch) {
        if (batch.messages.isNotEmpty) states.add(batch.messages.single);
      });
      addTearDown(subscription.cancel);
      // Start from a live, empty query, the way the chat screen does.
      await _confirmed(repo.watchLatest(30));

      final id = await alice.send(room, 'Hello');
      final stored = await _confirmed(
        repo.watchLatest(30),
        (batch) => batch.messages.isNotEmpty,
      );

      // First the local echo: pending, no server time yet.
      expect(states.first.id, id);
      expect(states.first.hasPendingWrites, isTrue);
      expect(states.first.hasServerTimestamp, isFalse);
      expect(states.first.status, MessageStatus.sending);

      final message = stored.messages.single;
      expect(message.id, id);
      expect(message.text, 'Hello');
      expect(message.senderId, alice.uid);
      expect(message.senderName, 'Alice');
      expect(message.hasServerTimestamp, isTrue);
      expect(message.status, MessageStatus.sent);
      expect(message.editedAt, isNull);
      expect(message.deleted, isFalse);
      expect(message.replyTo, isNull);
      expect(
        message.createdAt.difference(DateTime.now()).abs(),
        lessThan(const Duration(minutes: 1)),
      );
      expect(stored.oldestCursor, isNotNull);
    });

    test(
      'the other side sees it, and its receipt reaches the author',
      () async {
        final room = _newRoom();
        final id = await alice.send(room, 'Anyone there?');

        final received = await _confirmed(
          bob.repository(room).watchLatest(30),
          (batch) => batch.messages.isNotEmpty,
        );
        expect(received.messages.single.id, id);
        expect(received.messages.single.senderName, 'Alice');

        await bob.repository(room).markSeen(<String>[id], bob.uid);
        // A second receipt for the same message changes nothing.
        await bob.repository(room).markSeen(<String>[id], bob.uid);

        final seen = await _confirmed(
          alice.repository(room).watchLatest(30),
          (batch) => batch.messages.single.seenBy.isNotEmpty,
        );
        expect(seen.messages.single.seenBy, <String>[bob.uid]);
        expect(seen.messages.single.status, MessageStatus.seen);
      },
    );

    test('a reply stores its quote', () async {
      final room = _newRoom();
      final original = await alice.send(room, 'Beach or mountains?');
      const quote = ReplyPreview(
        messageId: 'placeholder',
        text: 'Beach or mountains?',
        senderName: 'Alice',
      );
      final reply = await bob.send(
        room,
        'Beach',
        replyTo: ReplyPreview(
          messageId: original,
          text: quote.text,
          senderName: quote.senderName,
        ),
      );

      final batch = await _confirmed(
        alice.repository(room).watchLatest(30),
        (batch) => batch.messages.length == 2,
      );
      expect(batch.messages.first.id, reply);
      expect(
        batch.messages.first.replyTo,
        ReplyPreview(
          messageId: original,
          text: 'Beach or mountains?',
          senderName: 'Alice',
        ),
      );
    });

    test('the author can edit a message', () async {
      final room = _newRoom();
      final repo = alice.repository(room);
      final id = await alice.send(room, 'Frist!');

      await repo.editMessage(id, 'First!');
      final edited = await _confirmed(
        bob.repository(room).watchLatest(30),
        (batch) => batch.messages.single.text == 'First!',
      );
      expect(edited.messages.single.isEdited, isTrue);
      expect(edited.messages.single.editedAt, isNotNull);
    });

    test('the author can delete a message for everyone', () async {
      final room = _newRoom();
      final repo = alice.repository(room);
      final original = await bob.send(room, 'Question');
      final id = await alice.send(
        room,
        'Oops',
        replyTo: ReplyPreview(
          messageId: original,
          text: 'Question',
          senderName: 'Bob',
        ),
      );

      await repo.deleteMessage(id);
      final batch = await _confirmed(
        bob.repository(room).watchLatest(30),
        (batch) => batch.messages.length == 2 && batch.messages.first.deleted,
      );
      final deleted = batch.messages.first;
      expect(deleted.id, id);
      expect(deleted.text, isEmpty);
      expect(deleted.replyTo, isNull);
      expect(deleted.senderId, alice.uid);
    });

    test('windows, cursors and pages line up', () async {
      final room = _newRoom();
      final repo = alice.repository(room);
      for (var i = 0; i < 7; i++) {
        await alice.send(room, 'm$i');
      }

      final latest = await _confirmed(
        repo.watchLatest(3),
        (batch) => batch.messages.length == 3,
      );
      expect(_texts(latest.messages), <String>['m6', 'm5', 'm4']);

      final older = await _confirmed(
        repo.watchOlder(latest.oldestCursor!, 3),
        (batch) => batch.messages.length == 3,
      );
      expect(_texts(older.messages), <String>['m3', 'm2', 'm1']);

      final oldest = await _confirmed(
        repo.watchOlder(older.oldestCursor!, 3),
        (batch) => batch.messages.isNotEmpty,
      );
      expect(_texts(oldest.messages), <String>['m0']);

      // The bounded query starts at the cursor (inclusive) and is open
      // towards new messages; the limited window slides instead.
      final sinceEvents = <MessageBatch>[];
      final latestEvents = <MessageBatch>[];
      final since = repo
          .watchSince(latest.oldestCursor)
          .listen(sinceEvents.add);
      final window = repo.watchLatest(3).listen(latestEvents.add);
      addTearDown(since.cancel);
      addTearDown(window.cancel);
      await _confirmed(repo.watchSince(latest.oldestCursor));

      await bob.send(room, 'm7');
      final grown = await _confirmed(
        repo.watchSince(latest.oldestCursor),
        (batch) => batch.messages.length == 4,
      );
      expect(_texts(grown.messages), <String>['m7', 'm6', 'm5', 'm4']);
      await _confirmed(
        repo.watchLatest(3),
        (batch) => batch.messages.first.text == 'm7',
      );
      expect(_texts(sinceEvents.last.messages), <String>[
        'm7',
        'm6',
        'm5',
        'm4',
      ]);
      expect(_texts(latestEvents.last.messages), <String>['m7', 'm6', 'm5']);
      expect(sinceEvents.last.removedIds, isEmpty);
      expect(latestEvents.last.removedIds, <String>[latest.messages.last.id]);

      // Without a cursor the whole room is watched.
      final everything = await _confirmed(
        repo.watchSince(null),
        (batch) => batch.messages.length == 8,
      );
      expect(everything.messages.last.text, 'm0');
    });

    test('the message feed loads, pages and stays live', () async {
      final room = _newRoom();
      final repo = alice.repository(room);
      final ids = <String>[];
      for (var i = 0; i < 7; i++) {
        ids.add(await bob.send(room, 'm$i'));
      }

      final store = MessageStore(currentUserId: alice.uid);
      final changes = StreamController<void>.broadcast();
      final feed = MessageFeed(
        repository: repo,
        store: store,
        onChanged: () => changes.add(null),
        pageSize: 3,
      );
      addTearDown(feed.dispose);
      addTearDown(changes.close);
      Future<void> until(bool Function() condition) async {
        if (condition()) return;
        await changes.stream.firstWhere((_) => condition()).timeout(_patience);
      }

      feed.start();
      await until(() => !feed.isLoading && store.visible.length == 3);
      expect(_texts(store.visible), <String>['m6', 'm5', 'm4']);
      expect(feed.hasMore, isTrue);
      expect(feed.watchesWholeRoom, isFalse);

      await feed.loadMore();
      expect(_texts(store.visible), <String>[
        'm6',
        'm5',
        'm4',
        'm3',
        'm2',
        'm1',
      ]);
      expect(feed.hasMore, isTrue);

      await feed.loadMore();
      expect(store.visible, hasLength(7));
      expect(store.visible.last.text, 'm0');
      expect(feed.hasMore, isFalse);

      // New messages arrive on top.
      await bob.send(room, 'm7');
      await until(
        () =>
            store.visible.first.text == 'm7' &&
            store.visible.first.hasServerTimestamp,
      );
      expect(store.visible, hasLength(8));

      // Changes to messages of every page keep arriving: an edit on the
      // oldest page, a delete in the middle and a receipt on the newest.
      await bob.repository(room).editMessage(ids[0], 'm0, edited');
      await bob.repository(room).deleteMessage(ids[3]);
      await repo.markSeen(<String>[ids[6]], alice.uid);
      await until(
        () =>
            store[ids[0]]!.text == 'm0, edited' &&
            store[ids[3]]!.deleted &&
            store[ids[6]]!.seenBy.contains(alice.uid),
      );
      expect(store[ids[0]]!.isEdited, isTrue);
      expect(store.visible, hasLength(8));

      // My own message is on screen before the server has it.
      final mine = repo.newMessageId();
      final outgoing = ChatMessage(
        id: mine,
        text: 'from me',
        senderId: alice.uid,
        senderName: 'Alice',
        createdAt: DateTime.now(),
        hasPendingWrites: true,
        hasServerTimestamp: false,
      );
      store.addOutgoing(outgoing);
      expect(store.visible.first.status, MessageStatus.sending);
      await repo.sendMessage(outgoing);
      await until(() => store.visible.first.status == MessageStatus.sent);
      expect(store.visible.first.id, mine);
      expect(store.visible, hasLength(9));
    });
  });

  group('typing', () {
    test('typing documents reach the others and can be cleared', () async {
      final room = _newRoom();
      final repo = alice.repository(room);

      await repo.setTyping(alice.user);
      final typing = await _first(
        bob.repository(room).watchTyping(),
        (users) => users.isNotEmpty && users.single.updatedAt != null,
      );
      expect(typing.single.userId, alice.uid);
      expect(typing.single.name, 'Alice');

      // A refresh overwrites the same document.
      await repo.setTyping(alice.user);
      await repo.clearTyping(alice.uid);
      await _first(
        bob.repository(room).watchTyping(),
        (users) => users.isEmpty,
      );
      // Clearing twice is harmless.
      await repo.clearTyping(alice.uid);
    });
  });

  group('sample conversation', () {
    test('the seeder writes 40 backdated messages', () async {
      final room = _newRoom();
      final count = await DemoSeeder(alice.db, roomId: room).seed(alice.user);
      expect(count, 40);

      final snapshot = await alice.messages(room).orderBy('createdAt').get();
      expect(snapshot.docs, hasLength(40));
      final now = DateTime.now();
      for (final doc in snapshot.docs) {
        final createdAt = (doc.data()['createdAt'] as Timestamp).toDate();
        expect(createdAt.isBefore(now), isTrue);
      }

      final latest = await _confirmed(
        alice.repository(room).watchLatest(30),
        (batch) => batch.messages.length == 30,
      );
      final script = <DemoLine>[...demoYesterday, ...demoToday];
      expect(latest.messages.first.text, script.last.text);
      expect(latest.messages.first.senderId, alice.uid);
      expect(latest.messages.first.senderName, 'Alice');
      expect(latest.messages.first.status, MessageStatus.seen);
      expect(
        latest.messages.where((message) => message.replyTo != null),
        isNotEmpty,
      );
      expect(latest.messages.where((message) => message.deleted), hasLength(1));
      expect(latest.messages.where((message) => message.isEdited), isNotEmpty);

      // Seeded messages behave like any other: receipts, edits and deletes.
      final repo = alice.repository(room);
      final mine = latest.messages
          .firstWhere((m) => m.senderId == alice.uid)
          .id;
      final theirs = <String>[
        for (final message in latest.messages)
          if (message.senderId != alice.uid && !message.deleted) message.id,
      ];
      await repo.markSeen(theirs, alice.uid);
      await repo.editMessage(mine, 'Edited sample');
      await repo.deleteMessage(mine);
      await _expectDenied(repo.editMessage(theirs.first, 'Not mine'));
    });

    test('adding it twice gives a second, complete copy', () async {
      final room = _newRoom();
      final seeder = DemoSeeder(bob.db, roomId: room);
      await seeder.seed(bob.user);
      await seeder.seed(bob.user);
      final snapshot = await bob.messages(room).get();
      expect(snapshot.docs, hasLength(80));
    });
  });

  group('security rules', () {
    late String room;
    late String aliceMessage;

    setUp(() async {
      room = _newRoom();
      aliceMessage = await alice.send(room, 'Mine');
    });

    test('accept a message written the way the app writes it', () async {
      await bob.messages(room).doc().set(_message(bob.uid));
    });

    test('reject everything from signed-out visitors', () async {
      await _expectDenied(guest.messages(room).get());
      await _expectDenied(guest.messages(room).doc(aliceMessage).get());
      await _expectDenied(guest.typing(room).get());
      await _expectDenied(guest.messages(room).doc().set(_message('nobody')));
    });

    test('reject messages in somebody else\'s name', () async {
      await _expectDenied(bob.messages(room).doc().set(_message(alice.uid)));
      await _expectDenied(bob.messages(room).doc().set(_message('demo_sara')));
    });

    test('reject messages that are not stamped by the server', () async {
      final backdated = _message(bob.uid)
        ..['createdAt'] = Timestamp.fromDate(DateTime(2020));
      await _expectDenied(bob.messages(room).doc().set(backdated));
      final future = _message(bob.uid)
        ..['createdAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 365)),
        );
      await _expectDenied(bob.messages(room).doc().set(future));
    });

    test('reject malformed messages', () async {
      Future<void> rejects(void Function(Map<String, dynamic> data) change) {
        final data = _message(bob.uid);
        change(data);
        return _expectDenied(bob.messages(room).doc().set(data));
      }

      await rejects((data) => data['text'] = '');
      await rejects((data) => data['text'] = 'x' * 10001);
      await rejects((data) => data['text'] = 42);
      await rejects((data) => data['senderName'] = '');
      await rejects((data) => data['senderName'] = 'x' * 41);
      await rejects((data) => data['admin'] = true);
      await rejects((data) => data.remove('seenBy'));
      await rejects((data) => data.remove('replyTo'));
      await rejects((data) => data['seenBy'] = <String>['somebody']);
      await rejects((data) => data['deleted'] = true);
      await rejects((data) => data['editedAt'] = FieldValue.serverTimestamp());
      await rejects((data) => data['replyTo'] = 'm1');
      await rejects(
        (data) => data['replyTo'] = <String, dynamic>{
          'messageId': 'm1',
          'text': 'x' * 201,
          'senderName': 'Alice',
        },
      );
      await rejects(
        (data) => data['replyTo'] = <String, dynamic>{
          'messageId': 'm1',
          'text': 'Hi',
          'senderName': 'Alice',
          'extra': true,
        },
      );
    });

    test('let only the author edit, and only the text', () async {
      final mine = alice.messages(room).doc(aliceMessage);
      final asBob = bob.messages(room).doc(aliceMessage);
      final now = FieldValue.serverTimestamp();

      await _expectDenied(
        asBob.update(<String, dynamic>{'text': 'Hacked', 'editedAt': now}),
      );
      await _expectDenied(mine.update(<String, dynamic>{'text': 'No stamp'}));
      await _expectDenied(
        mine.update(<String, dynamic>{
          'text': 'Old stamp',
          'editedAt': Timestamp.fromDate(DateTime(2020)),
        }),
      );
      await _expectDenied(
        mine.update(<String, dynamic>{'text': '', 'editedAt': now}),
      );
      await _expectDenied(
        mine.update(<String, dynamic>{
          'text': 'Renamed',
          'editedAt': now,
          'senderName': 'Bob',
        }),
      );
      await _expectDenied(mine.update(<String, dynamic>{'senderId': bob.uid}));
      await _expectDenied(mine.update(<String, dynamic>{'createdAt': now}));
      await _expectDenied(
        mine.update(<String, dynamic>{
          'seenBy': <String>[alice.uid, bob.uid],
        }),
      );

      await mine.update(<String, dynamic>{'text': 'Fine', 'editedAt': now});
    });

    test('let only the author delete, and never remove the document', () async {
      final mine = alice.messages(room).doc(aliceMessage);
      final asBob = bob.messages(room).doc(aliceMessage);
      const wipe = <String, dynamic>{
        'deleted': true,
        'text': '',
        'replyTo': null,
      };

      await _expectDenied(asBob.update(wipe));
      await _expectDenied(asBob.delete());
      await _expectDenied(mine.delete());
      // Flagging without wiping the content is not a delete.
      await _expectDenied(mine.update(<String, dynamic>{'deleted': true}));

      await mine.update(wipe);

      // What is deleted stays deleted.
      await _expectDenied(
        mine.update(<String, dynamic>{
          'text': 'Back again',
          'editedAt': FieldValue.serverTimestamp(),
        }),
      );
      await _expectDenied(mine.update(<String, dynamic>{'deleted': false}));
    });

    test('let a reader add a receipt for themselves only', () async {
      final asBob = bob.messages(room).doc(aliceMessage);

      await _expectDenied(
        asBob.update(<String, dynamic>{
          'seenBy': FieldValue.arrayUnion(<String>[alice.uid]),
        }),
      );
      await _expectDenied(
        asBob.update(<String, dynamic>{
          'seenBy': <String>[bob.uid, 'somebody-else'],
        }),
      );
      await _expectDenied(
        asBob.update(<String, dynamic>{
          'seenBy': FieldValue.arrayUnion(<String>[bob.uid]),
          'text': 'Sneaky',
        }),
      );

      await asBob.update(<String, dynamic>{
        'seenBy': FieldValue.arrayUnion(<String>[bob.uid]),
      });

      // A receipt cannot be taken back, by anyone.
      await _expectDenied(
        asBob.update(<String, dynamic>{
          'seenBy': FieldValue.arrayRemove(<String>[bob.uid]),
        }),
      );
      await _expectDenied(
        alice.messages(room).doc(aliceMessage).update(<String, dynamic>{
          'seenBy': <String>[],
        }),
      );
    });

    test('keep typing documents with their owner', () async {
      final now = FieldValue.serverTimestamp();
      final mine = bob.typing(room).doc(bob.uid);
      final theirs = bob.typing(room).doc(alice.uid);
      await alice.repository(room).setTyping(alice.user);

      await _expectDenied(
        theirs.set(<String, dynamic>{'name': 'Alice', 'updatedAt': now}),
      );
      await _expectDenied(theirs.delete());
      await _expectDenied(
        mine.set(<String, dynamic>{
          'name': 'Bob',
          'updatedAt': Timestamp.fromDate(DateTime(2030)),
        }),
      );
      await _expectDenied(
        mine.set(<String, dynamic>{
          'name': 'Bob',
          'updatedAt': now,
          'extra': true,
        }),
      );
      await _expectDenied(
        mine.set(<String, dynamic>{'name': 'x' * 41, 'updatedAt': now}),
      );

      await mine.set(<String, dynamic>{'name': 'Bob', 'updatedAt': now});
      await mine.delete();
    });

    test('allow sample messages only when flagged, backdated and from a '
        'demo persona or yourself', () async {
      Map<String, dynamic> sample(String senderId, DateTime createdAt) =>
          _message(senderId)
            ..['createdAt'] = Timestamp.fromDate(createdAt)
            ..['demo'] = true;
      final past = DateTime.now().subtract(const Duration(hours: 3));
      final future = DateTime.now().add(const Duration(hours: 3));
      final messages = bob.messages(room);

      await messages.doc().set(sample('demo_sara', past));
      await messages.doc().set(sample(bob.uid, past));
      await messages.doc().set(
        sample('demo_omar', past)
          ..['seenBy'] = <String>['demo_sara']
          ..['editedAt'] = Timestamp.fromDate(past)
          ..['deleted'] = true
          ..['text'] = '',
      );

      await _expectDenied(messages.doc().set(sample(alice.uid, past)));
      await _expectDenied(messages.doc().set(sample('demo_sara', future)));
      await _expectDenied(
        messages.doc().set(sample('demo_sara', past)..remove('demo')),
      );
      await _expectDenied(
        messages.doc().set(sample('demo_sara', past)..['demo'] = false),
      );
      await _expectDenied(
        messages.doc().set(sample('demo_sara', past)..['admin'] = true),
      );
    });

    test('keep everything else closed', () async {
      await _expectDenied(
        bob.db.collection('rooms').doc(room).set(<String, dynamic>{
          'name': 'Mine now',
        }),
      );
      await _expectDenied(bob.db.collection('rooms').get());
      await _expectDenied(bob.db.collection('users').doc(bob.uid).get());
      await _expectDenied(
        bob.db.collection('users').doc(bob.uid).set(<String, dynamic>{
          'name': 'Bob',
        }),
      );
    });
  });
}
