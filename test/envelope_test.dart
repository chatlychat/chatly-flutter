import 'package:chatly/chatly.dart';
import 'package:chatly/src/realtime/envelope.dart';
import 'package:chatly/src/realtime/event_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealtimeEnvelope', () {
    test('parses a valid v1 envelope', () {
      final raw = <String, Object?>{
        'v': 1,
        'type': 'message.created',
        'id': '0190abcd-0000-7000-8000-000000000000',
        'ts': 1700000000000,
        'workspace_id': '0190abcd-1111-7000-8000-000000000000',
        'payload': {
          'id': '0190abcd-2222-7000-8000-000000000000',
          'conversationId': '0190abcd-3333-7000-8000-000000000000',
          'authorType': 'agent',
          'authorId': 'agent_1',
          'body': 'Hello!',
          'attachments': <Object?>[],
          'createdAt': '2024-01-01T00:00:00.000Z',
        },
      };
      final env = RealtimeEnvelope.fromJson(raw);
      expect(env.version, 1);
      expect(env.type, RealtimeEventType.messageCreated);
      expect(env.workspaceId, '0190abcd-1111-7000-8000-000000000000');
      expect(env.payload['authorType'], 'agent');
      expect(env.timestampDate.year, 2023);
    });

    test('rejects mismatched protocol version', () {
      expect(
        () => RealtimeEnvelope.fromJson(<String, Object?>{
          'v': 2,
          'type': 'message.created',
          'id': 'x',
          'ts': 0,
          'workspace_id': 'y',
          'payload': <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('preserves unknown event types in rawType', () {
      final env = RealtimeEnvelope.fromJson(<String, Object?>{
        'v': 1,
        'type': 'future.event',
        'id': '0190abcd-0000-7000-8000-000000000000',
        'ts': 1,
        'workspace_id': '0190abcd-1111-7000-8000-000000000000',
        'payload': <String, Object?>{},
      });
      expect(env.type, RealtimeEventType.unknown);
      expect(env.rawType, 'future.event');
    });

    test('round-trips through toJson', () {
      final original = const RealtimeEnvelope(
        version: 1,
        type: RealtimeEventType.typingStart,
        id: '0190abcd-0000-7000-8000-000000000000',
        timestamp: 1700000000000,
        workspaceId: '0190abcd-1111-7000-8000-000000000000',
        payload: <String, Object?>{
          'conversationId': '0190abcd-3333-7000-8000-000000000000',
          'actorType': 'contact',
          'actorId': 'c_1',
        },
      );
      final round = RealtimeEnvelope.fromJson(original.toJson());
      expect(round.type, original.type);
      expect(round.payload['actorId'], 'c_1');
    });
  });

  group('RealtimeEventType.parse', () {
    test('maps known wire strings', () {
      expect(RealtimeEventTypeExt.parse('message.created'),
          RealtimeEventType.messageCreated);
      expect(RealtimeEventTypeExt.parse('typing.stop'),
          RealtimeEventType.typingStop);
    });

    test('falls back to unknown', () {
      expect(RealtimeEventTypeExt.parse('nope'), RealtimeEventType.unknown);
      expect(RealtimeEventTypeExt.parse(null), RealtimeEventType.unknown);
    });
  });
}
