/// A full knowledge-base article as returned by `/v1/widget/kb/article`.
class ChatlyKbArticle {
  /// Creates a [ChatlyKbArticle]. Generally constructed via [fromJson].
  const ChatlyKbArticle({
    required this.id,
    required this.slug,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.bodyHtml,
  });

  /// Article id.
  final String id;

  /// URL-friendly slug.
  final String slug;

  /// Display title.
  final String title;

  /// Plain markdown body.
  final String body;

  /// Pre-rendered HTML body (when available).
  final String? bodyHtml;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Parses an article from the wire format.
  factory ChatlyKbArticle.fromJson(Map<String, Object?> json) {
    return ChatlyKbArticle(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      bodyHtml: json['bodyHtml'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  /// Serialises this article to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'body': body,
        'bodyHtml': bodyHtml,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}
