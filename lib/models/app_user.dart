/// The signed-in (anonymous) user together with the name they picked.
class AppUser {
  const AppUser({required this.uid, required this.name});

  final String uid;

  /// Display name chosen on the username screen. Empty until one is picked.
  final String name;

  bool get hasName => name.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && other.uid == uid && other.name == name;

  @override
  int get hashCode => Object.hash(uid, name);

  @override
  String toString() => 'AppUser($uid, $name)';
}
