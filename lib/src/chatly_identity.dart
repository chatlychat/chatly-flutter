/// A known end-user, passed to [Chatly.identify].
///
/// All fields are optional except [externalId] which is the stable identifier
/// of the user in your own system. Pair with [userHash] (a server-side HMAC)
/// if your workspace has Identity Verification enabled.
class ChatlyIdentity {
  /// Creates an identity block. [externalId] is required.
  const ChatlyIdentity({
    required this.externalId,
    this.email,
    this.name,
    this.userHash,
    this.attributes,
  });

  /// Stable id for the user in your system.
  final String externalId;

  /// Optional email address.
  final String? email;

  /// Optional display name.
  final String? name;

  /// Optional HMAC of [externalId] computed server-side. Required when
  /// Identity Verification is enabled on the workspace.
  final String? userHash;

  /// Arbitrary custom attributes. Values must be JSON-serialisable scalars,
  /// lists, or maps.
  final Map<String, Object?>? attributes;

  /// Serialises this identity as the JSON body fragment expected by
  /// `/v1/widget/init`.
  Map<String, Object?> toJson() {
    final out = <String, Object?>{'externalId': externalId};
    if (email != null) out['email'] = email;
    if (name != null) out['name'] = name;
    if (userHash != null) out['userHash'] = userHash;
    if (attributes != null) out['attributes'] = attributes;
    return out;
  }
}
