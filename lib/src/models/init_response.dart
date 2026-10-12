/// Response payload from `POST /v1/widget/init`.
///
/// Carries the visitor session token, workspace identity, and branding hints.
class InitResponse {
  /// Creates an [InitResponse]. Generally constructed via [fromJson].
  const InitResponse({
    required this.session,
    required this.workspace,
    required this.branding,
  });

  /// Visitor session details, including the token that must be persisted.
  final InitSession session;

  /// Workspace identity (id + display name).
  final InitWorkspace workspace;

  /// Workspace branding map — opaque JSON consumed by the chat UI.
  final Map<String, Object?> branding;

  /// Parses an [InitResponse] from the raw JSON body.
  factory InitResponse.fromJson(Map<String, Object?> json) {
    final sessionJson = json['session'];
    final workspaceJson = json['workspace'];
    final brandingJson = json['branding'];
    if (sessionJson is! Map || workspaceJson is! Map) {
      throw const FormatException('init: missing session or workspace');
    }
    return InitResponse(
      session: InitSession.fromJson(Map<String, Object?>.from(sessionJson)),
      workspace:
          InitWorkspace.fromJson(Map<String, Object?>.from(workspaceJson)),
      branding: brandingJson is Map
          ? Map<String, Object?>.from(brandingJson)
          : <String, Object?>{},
    );
  }

  /// Serialises this [InitResponse] to JSON.
  Map<String, Object?> toJson() => {
        'session': session.toJson(),
        'workspace': workspace.toJson(),
        'branding': branding,
      };
}

/// Visitor session block returned by `/v1/widget/init`.
class InitSession {
  /// Creates an [InitSession]. Generally constructed via [fromJson].
  const InitSession({
    required this.token,
    required this.contactId,
    required this.workspaceId,
    required this.brandId,
    required this.channelId,
  });

  /// Opaque visitor token. Must be persisted and replayed on every subsequent
  /// request.
  final String token;

  /// Contact id assigned to this visitor.
  final String contactId;

  /// Workspace id this session belongs to.
  final String workspaceId;

  /// Brand id for this session (may equal the workspace id for single-brand
  /// customers).
  final String brandId;

  /// Channel id (web widget, mobile widget, etc.).
  final String channelId;

  /// Parses an [InitSession] from JSON.
  factory InitSession.fromJson(Map<String, Object?> json) {
    return InitSession(
      token: json['token'] as String? ?? '',
      contactId: json['contactId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      brandId: json['brandId'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
    );
  }

  /// Serialises this [InitSession] to JSON.
  Map<String, Object?> toJson() => {
        'token': token,
        'contactId': contactId,
        'workspaceId': workspaceId,
        'brandId': brandId,
        'channelId': channelId,
      };
}

/// Workspace identity block returned by `/v1/widget/init`.
class InitWorkspace {
  /// Creates an [InitWorkspace]. Generally constructed via [fromJson].
  const InitWorkspace({required this.id, required this.name});

  /// Workspace id.
  final String id;

  /// Workspace display name.
  final String name;

  /// Parses an [InitWorkspace] from JSON.
  factory InitWorkspace.fromJson(Map<String, Object?> json) {
    return InitWorkspace(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  /// Serialises this [InitWorkspace] to JSON.
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}
