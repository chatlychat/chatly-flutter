import 'dart:convert';

import 'package:chatly/chatly.dart';
import 'package:chatly/src/transport/rest_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ChatlyRestClient', () {
    late String currentToken;

    ChatlyRestClient buildClient(MockClient mock) {
      return ChatlyRestClient(
        config: const ChatlyConfig(
          publicId: 'pub_test',
          apiHost: 'api.chatly.test',
        ),
        visitorToken: () => currentToken,
        httpClient: mock,
      );
    }

    setUp(() {
      currentToken = '';
    });

    test('init() decodes the session block + carries identity', () async {
      Map<String, Object?>? lastBody;
      final mock = MockClient((http.Request req) async {
        expect(req.url.path, '/v1/widget/init');
        expect(req.url.host, 'api.chatly.test');
        lastBody =
            jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'session': {
              'token': 'vt_abc',
              'contactId': 'c_1',
              'workspaceId': 'w_1',
              'brandId': 'b_1',
              'channelId': 'ch_1',
            },
            'workspace': {'id': 'w_1', 'name': 'Acme'},
            'branding': {'primary': '#000'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = buildClient(mock);
      final res = await client.init(
        identity: const ChatlyIdentity(externalId: 'u_42', email: 'a@b.co'),
      );
      expect(res.session.token, 'vt_abc');
      expect(res.workspace.name, 'Acme');
      expect(lastBody?['publicId'], 'pub_test');
      final identity = lastBody?['identity'];
      expect(identity is Map, true);
      expect((identity as Map)['externalId'], 'u_42');
    });

    test('startConversation() returns conv id + seeded message', () async {
      currentToken = 'vt_xyz';
      final mock = MockClient((http.Request req) async {
        expect(req.url.path, '/v1/widget/conversations');
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect(body['visitorToken'], 'vt_xyz');
        expect(body['body'], 'hi');
        return http.Response(
          jsonEncode({
            'conversation': {'id': 'conv_1'},
            'message': {
              'id': 'msg_1',
              'body': 'hi',
              'createdAt': '2024-01-01T00:00:00.000Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final res = await buildClient(mock).startConversation('hi');
      expect(res.conversationId, 'conv_1');
      expect(res.message.body, 'hi');
      expect(res.message.conversationId, 'conv_1');
    });

    test('listConversations() parses status enum', () async {
      currentToken = 'vt_xyz';
      final mock = MockClient((http.Request req) async {
        return http.Response(
          jsonEncode({
            'conversations': [
              {
                'id': 'conv_a',
                'status': 'closed',
                'subject': null,
                'lastMessagePreview': 'thanks!',
                'lastMessageAt': '2024-01-02T00:00:00.000Z',
                'unreadContactCount': 0,
                'createdAt': '2024-01-01T00:00:00.000Z',
              },
              {
                'id': 'conv_b',
                'status': 'open',
                'subject': null,
                'lastMessagePreview': null,
                'lastMessageAt': null,
                'unreadContactCount': 2,
                'createdAt': '2024-01-03T00:00:00.000Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final list = await buildClient(mock).listConversations();
      expect(list, hasLength(2));
      expect(list[0].status, ChatlyConversationStatus.closed);
      expect(list[1].unreadContactCount, 2);
    });

    test('searchKb() returns typed results', () async {
      final mock = MockClient((http.Request req) async {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'a_1',
                'slug': 'getting-started',
                'title': 'Getting Started',
                'excerpt': 'A short intro…',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final hits = await buildClient(mock).searchKb(query: 'intro');
      expect(hits, hasLength(1));
      expect(hits.first.slug, 'getting-started');
    });

    test('non-2xx throws ChatlyRestException', () async {
      final mock = MockClient((http.Request req) async {
        return http.Response('boom', 500);
      });
      expect(
        () => buildClient(mock).startConversation('hi'),
        throwsA(isA<ChatlyRestException>()),
      );
    });
  });

  group('ChatlyIdentity', () {
    test('serialises only the populated fields', () {
      final j =
          const ChatlyIdentity(externalId: 'u_1', email: 'x@y.co').toJson();
      expect(j['externalId'], 'u_1');
      expect(j['email'], 'x@y.co');
      expect(j.containsKey('name'), false);
      expect(j.containsKey('userHash'), false);
    });
  });
}
