import 'ui/chatly_theme.dart';

/// Immutable configuration for the [Chatly] singleton.
///
/// Pass an instance to [Chatly.instance.configure] exactly once during app
/// startup. Subsequent calls replace the active config and reset any in-flight
/// session.
class ChatlyConfig {
  /// Creates a configuration block.
  ///
  /// [publicId] is the workspace's public widget identifier (looks like
  /// `pub_abc123`). [apiHost] is the host name of the Chatly REST API — no
  /// scheme, no trailing slash (e.g. `api.chatlychat.com`).
  const ChatlyConfig({
    required this.publicId,
    required this.apiHost,
    this.realtimeHost,
    this.useTls = true,
    this.locale,
    this.timezone,
    this.theme = const ChatlyTheme(),
    this.autoConnectRealtime = true,
    this.requestTimeout = const Duration(seconds: 20),
  });

  /// Public widget id for the workspace. Required.
  final String publicId;

  /// REST API host name. Required. Example: `api.chatlychat.com`.
  final String apiHost;

  /// Optional realtime gateway host. Defaults to [apiHost] when null.
  final String? realtimeHost;

  /// Whether to use TLS (`https://` / `wss://`). Defaults to `true`.
  final bool useTls;

  /// Optional BCP-47 locale hint sent on `/v1/widget/init`.
  final String? locale;

  /// Optional IANA timezone hint sent on `/v1/widget/init`.
  final String? timezone;

  /// Visual theme applied to the bundled chat UI.
  final ChatlyTheme theme;

  /// If true (default) the SDK opens its realtime socket as soon as
  /// [Chatly.configure] succeeds.
  final bool autoConnectRealtime;

  /// HTTP request timeout for REST calls.
  final Duration requestTimeout;

  /// Returns the base REST URL (`https://api.chatlychat.com`).
  String get restBaseUrl => '${useTls ? 'https' : 'http'}://$apiHost';

  /// Returns the realtime WebSocket URL (`wss://api.chatlychat.com`).
  String get realtimeBaseUrl =>
      '${useTls ? 'wss' : 'ws'}://${realtimeHost ?? apiHost}';

  /// Returns a new config with the supplied fields overridden.
  ChatlyConfig copyWith({
    String? publicId,
    String? apiHost,
    String? realtimeHost,
    bool? useTls,
    String? locale,
    String? timezone,
    ChatlyTheme? theme,
    bool? autoConnectRealtime,
    Duration? requestTimeout,
  }) {
    return ChatlyConfig(
      publicId: publicId ?? this.publicId,
      apiHost: apiHost ?? this.apiHost,
      realtimeHost: realtimeHost ?? this.realtimeHost,
      useTls: useTls ?? this.useTls,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      theme: theme ?? this.theme,
      autoConnectRealtime: autoConnectRealtime ?? this.autoConnectRealtime,
      requestTimeout: requestTimeout ?? this.requestTimeout,
    );
  }
}
