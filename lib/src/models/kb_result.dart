/// A single hit returned by `POST /v1/widget/kb/search`.
class ChatlyKbResult {
  /// Creates a [ChatlyKbResult]. Generally constructed via [fromJson].
  const ChatlyKbResult({
    required this.id,
    required this.slug,
    required this.title,
    required this.excerpt,
  });

  /// Article id.
  final String id;

  /// URL-friendly slug.
  final String slug;

  /// Display title.
  final String title;

  /// Plain-text excerpt highlighting the match.
  final String excerpt;

  /// Parses a result hit from the wire format.
  factory ChatlyKbResult.fromJson(Map<String, Object?> json) {
    return ChatlyKbResult(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      excerpt: json['excerpt'] as String? ?? '',
    );
  }

  /// Serialises this result hit to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'excerpt': excerpt,
      };
}
