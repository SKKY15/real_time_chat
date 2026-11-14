/// Denormalised snapshot of the message being replied to.
///
/// Stored inside the reply so the quote can be rendered without loading the
/// original message. Mirrors the `replyTo` map in Firestore:
/// `{messageId, text, senderName}`.
class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.text,
    required this.senderName,
  });

  /// Builds a preview from the quoted message, trimming long text down to a
  /// short single-line snippet.
  factory ReplyPreview.snippet({
    required String messageId,
    required String text,
    required String senderName,
  }) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final snippet = flat.length <= maxSnippetLength
        ? flat
        : '${flat.substring(0, maxSnippetLength - 1).trimRight()}…';
    return ReplyPreview(
      messageId: messageId,
      text: snippet,
      senderName: senderName,
    );
  }

  /// Parses the Firestore map. Returns `null` when the value is missing or
  /// malformed so a broken reply never breaks the whole message.
  static ReplyPreview? fromMap(Object? value) {
    if (value is! Map) return null;
    final messageId = value['messageId'];
    final text = value['text'];
    final senderName = value['senderName'];
    if (messageId is! String || messageId.isEmpty) return null;
    return ReplyPreview(
      messageId: messageId,
      text: text is String ? text : '',
      senderName: senderName is String ? senderName : '',
    );
  }

  static const int maxSnippetLength = 120;

  final String messageId;
  final String text;
  final String senderName;

  Map<String, Object?> toMap() => <String, Object?>{
    'messageId': messageId,
    'text': text,
    'senderName': senderName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplyPreview &&
          other.messageId == messageId &&
          other.text == text &&
          other.senderName == senderName;

  @override
  int get hashCode => Object.hash(messageId, text, senderName);
}
