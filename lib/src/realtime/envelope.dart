import 'event_types.dart';

/// Realtime protocol version this SDK speaks.
///
/// Mirrors `REALTIME_PROTOCOL_VERSION` in
/// `packages/shared/src/realtime/index.ts`.
const int kRealtimeProtocolVersion = 1;

/// Versioned wire envelope for realtime events.
///
/// Every frame sent or received over the realtime socket has this shape:
///
/// ```json
/// { "v": 1, "type": "message.created", "id": "...", "ts": 0,
///   "workspace_id": "...", "payload": { ... } }
/// ```
class RealtimeEnvelope {
  /// Creates a new envelope.
  const RealtimeEnvelope({
    required this.version,
    required this.type,
    required this.id,
    required this.timestamp,
    required this.workspaceId,
    required this.payload,
    this.rawType,
  });

  /// Protocol version. Always [kRealtimeProtocolVersion] for this SDK.
  final int version;

  /// Parsed event type. [RealtimeEventType.unknown] when the wire string
  /// is not recognised.
  final RealtimeEventType type;

  /// Original wire string (preserves unknown event names).
  final String? rawType;

  /// UUID v7 of this event.
  final String id;

  /// Server timestamp in milliseconds since the Unix epoch.
  final int timestamp;

  /// Workspace this event belongs to.
  final String workspaceId;

  /// Opaque event-specific payload (matches the server-side discriminated
  /// union).
  final Map<String, Object?> payload;

  /// Convenience: timestamp as a [DateTime] in UTC.
  DateTime get timestampDate =>
      DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);

  /// Parses an envelope from a decoded JSON map.
  ///
  /// Throws [FormatException] if the protocol version mismatches the SDK or
  /// required fields are missing.
  factory RealtimeEnvelope.fromJson(Map<String, Object?> json) {
    final v = json['v'];
    if (v is! int || v != kRealtimeProtocolVersion) {
      throw FormatException(
        'Unsupported realtime protocol version: $v (expected $kRealtimeProtocolVersion)',
      );
    }
    final id = json['id'];
    final ts = json['ts'];
    final workspaceId = json['workspace_id'];
    final rawType = json['type'];
    if (id is! String || workspaceId is! String || rawType is! String) {
      throw const FormatException('Realtime envelope missing required fields');
    }
    if (ts is! int) {
      throw const FormatException('Realtime envelope: ts must be int');
    }
    final payload = json['payload'];
    return RealtimeEnvelope(
      version: v,
      type: RealtimeEventTypeExt.parse(rawType),
      rawType: rawType,
      id: id,
      timestamp: ts,
      workspaceId: workspaceId,
      payload: payload is Map
          ? Map<String, Object?>.from(payload)
          : <String, Object?>{},
    );
  }

  /// Serialises this envelope to JSON.
  Map<String, Object?> toJson() => {
        'v': version,
        'type': rawType ?? type.wireName,
        'id': id,
        'ts': timestamp,
        'workspace_id': workspaceId,
        'payload': payload,
      };
}
