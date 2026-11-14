/// A participant who is currently typing (`rooms/{roomId}/typing/{userId}`).
class TypingUser {
  const TypingUser({required this.userId, required this.name, this.updatedAt});

  final String userId;
  final String name;

  /// Server time of the last keystroke ping. `null` while the write is still
  /// pending locally.
  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypingUser &&
          other.userId == userId &&
          other.name == name &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(userId, name, updatedAt);
}
