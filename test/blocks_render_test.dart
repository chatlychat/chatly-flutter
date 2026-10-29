import 'package:chatly/chatly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Does a `rich` message actually DRAW?
///
/// The defect these tests exist for was not a bad renderer, it was no
/// renderer: `blocks` was documented on the message model and absent from it,
/// so every card arrived as bare `body` text with no error anywhere. So the
/// assertions here are about the mount — a card's title reaching the screen
/// through the ordinary list widget — rather than about pixels.

ChatlyMessage richMessage(Object? blocks, {String body = ''}) => ChatlyMessage(
      id: 'm1',
      author: ChatlyMessageAuthor.bot,
      kind: ChatlyMessageKind.rich,
      body: body,
      createdAt: DateTime.utc(2026, 2, 3, 10),
      blocks: blocks,
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    ChatlyMessage message, {
    ChatlyBlockActionHandler? onBlockAction,
    ChatlyQuickReplyHandler? onQuickReply,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatlyMessagesList(
          messages: <ChatlyMessage>[message],
          theme: const ChatlyTheme(),
          onBlockAction: onBlockAction,
          onQuickReply: onQuickReply,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a card renders through the ordinary message list',
      (tester) async {
    await pump(
      tester,
      richMessage(<String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{
            'type': 'card',
            'title': 'Brass desk lamp',
            'subtitle': 'Warm white, dimmable',
            'image': 'https://cdn.example.com/lamp.png',
            'badge': <Object?>[
              'Sale',
              <String, Object?>{'text': 'Great price', 'tone': 'success'},
            ],
            'price': <String, Object?>{
              'amount': 4820,
              'currency': 'USD',
              'compareAt': 6000,
            },
            'stock': 'low',
            'fields': <Object?>[
              <String, Object?>{'label': 'Ships', 'value': 'Tomorrow'},
            ],
            'variants': <Object?>[
              <String, Object?>{'label': 'Brass', 'value': 'brass'},
            ],
            'actions': <Object?>[
              <String, Object?>{
                'kind': 'host_event',
                'label': 'Add to cart',
                'event': 'cart.add',
              },
            ],
            'reactions': <Object?>['like', 'dislike'],
            'reaction': 'like',
          },
        ],
      }),
      onBlockAction: (_) {},
    );

    expect(find.text('Brass desk lamp'), findsOne);
    expect(find.text('Warm white, dimmable'), findsOne);
    expect(find.text('Sale'), findsOne);
    expect(find.text('✓ Great price'), findsOne);
    expect(find.textContaining('48.20'), findsOne);
    expect(find.textContaining('Was '), findsOne);
    expect(find.text('Low stock'), findsOne);
    expect(find.text('Ships: Tomorrow'), findsOne);
    expect(find.text('Brass'), findsOne);
    expect(find.text('Add to cart'), findsOne);
    expect(find.text('Helpful'), findsOne);
    expect(find.text('Not helpful'), findsOne);
  });

  testWidgets('an UNKNOWN block type still renders the message text',
      (tester) async {
    await pump(
      tester,
      richMessage(
        <String, Object?>{
          'v': 1,
          'blocks': <Object?>[
            <String, Object?>{'type': 'hologram', 'spin': 3},
            <String, Object?>{'type': 'text', 'markdown': 'Here is the one I meant'},
          ],
        },
        body: 'Here is the one I meant',
      ),
    );

    // The body, plus the text block that survived beside the unknown one.
    expect(find.text('Here is the one I meant'), findsExactly(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a malformed blocks value draws nothing and throws nothing',
      (tester) async {
    for (final Object? blocks in <Object?>[
      'not an envelope',
      42,
      <Object?>[],
      <String, Object?>{'v': 2, 'blocks': <Object?>[]},
      <String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{'type': 'card'},
        ],
      },
    ]) {
      await pump(tester, richMessage(blocks, body: 'Plain words'));
      expect(find.text('Plain words'), findsOne, reason: '$blocks');
      expect(tester.takeException(), isNull, reason: '$blocks');
    }
  });

  testWidgets('a pressed action reaches the host; a quick reply is sent',
      (tester) async {
    final pressed = <ChatlyBlockAction>[];
    final sent = <String>[];
    await pump(
      tester,
      richMessage(<String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{
            'type': 'actions',
            'actions': <Object?>[
              <String, Object?>{
                'kind': 'host_event',
                'label': 'Pay now',
                'event': 'checkout.start',
                'data': <String, Object?>{'total': 4820},
              },
            ],
          },
          <String, Object?>{
            'type': 'quick_replies',
            'options': <Object?>[
              <String, Object?>{'label': 'Yes please', 'value': 'yes'},
            ],
          },
        ],
      }),
      onBlockAction: pressed.add,
      onQuickReply: sent.add,
    );

    await tester.tap(find.text('Pay now'));
    await tester.tap(find.text('Yes please'));
    await tester.pump();

    expect(pressed.single.kind, ChatlyBlockActionKind.hostEvent);
    expect(pressed.single.value, 'checkout.start');
    expect(pressed.single.data, <String, Object?>{'total': 4820});
    // The VALUE is sent, never the label.
    expect(sent, <String>['yes']);
  });

  testWidgets('with no handler a block button renders disabled, not dead',
      (tester) async {
    await pump(
      tester,
      richMessage(<String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{
            'type': 'actions',
            'actions': <Object?>[
              <String, Object?>{
                'kind': 'postback',
                'label': 'Yes',
                'value': 'yes',
              },
            ],
          },
        ],
      }),
    );
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.enabled, isFalse);
  });

  testWidgets('a grid, a timeline, a table, a place and a divider all draw',
      (tester) async {
    await pump(
      tester,
      richMessage(<String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{
            'type': 'card_grid',
            'layout': 'carousel',
            'cards': <Object?>[
              <String, Object?>{'title': 'One'},
              <String, Object?>{'title': 'Two'},
            ],
            'more': <String, Object?>{
              'label': 'Show all 60',
              'action': <String, Object?>{
                'kind': 'postback',
                'label': 'More',
                'value': 'next',
              },
            },
          },
          <String, Object?>{
            'type': 'order_status',
            'steps': <Object?>[
              <String, Object?>{'label': 'Packed', 'state': 'done'},
              <String, Object?>{'label': 'Delivered', 'state': 'pending'},
            ],
          },
          <String, Object?>{
            'type': 'table',
            'caption': 'Compare',
            'columns': <Object?>[
              <String, Object?>{'label': 'Basic'},
              <String, Object?>{'label': 'Pro'},
            ],
            'rows': <Object?>[
              <String, Object?>{
                'label': 'Price',
                'cells': <Object?>['USD 10', 'USD 20'],
              },
            ],
          },
          <String, Object?>{
            'type': 'place',
            'label': 'Helpdesk',
            'detail': 'Second floor',
          },
          <String, Object?>{'type': 'status', 'id': 's1', 'text': 'Looking', 'state': 'failed'},
          <String, Object?>{'type': 'divider'},
        ],
      }),
      onBlockAction: (_) {},
    );

    expect(find.text('One'), findsOne);
    expect(find.text('Two'), findsOne);
    // The TILE's label renders, not the action's.
    expect(find.text('Show all 60'), findsOne);
    expect(find.text('More'), findsNothing);
    expect(find.text('Packed — Done'), findsOne);
    expect(find.text('Delivered — Pending'), findsOne);
    expect(find.text('Compare'), findsOne);
    expect(find.text('Basic · Pro'), findsOne);
    expect(find.text('Price: USD 10 · USD 20'), findsOne);
    expect(find.text('Helpdesk — Second floor'), findsOne);
    expect(find.text('Looking — failed'), findsOne);
    expect(tester.takeException(), isNull);
  });

  group('the message model', () {
    test('blocks survive fromJson, toJson and copyWith', () {
      final blocks = <String, Object?>{
        'v': 1,
        'blocks': <Object?>[
          <String, Object?>{'type': 'text', 'markdown': 'Hi'},
        ],
      };
      final message = ChatlyMessage.fromJson(<String, Object?>{
        'id': 'm1',
        'authorType': 'bot',
        'kind': 'rich',
        'body': 'Hi',
        'createdAt': '2026-02-03T10:00:00.000Z',
        'blocks': blocks,
      });
      expect(message.kind, ChatlyMessageKind.rich);
      expect(readChatlyBlocks(message.blocks)!.blocks, hasLength(1));
      expect(message.toJson()['blocks'], blocks);
      expect(message.copyWith(body: 'Hello').blocks, blocks);
      // A message with no blocks does not invent the key.
      expect(
        ChatlyMessage.fromJson(<String, Object?>{
          'id': 'm2',
          'authorType': 'agent',
          'kind': 'text',
          'body': 'Hi',
          'createdAt': '2026-02-03T10:00:00.000Z',
        }).toJson().containsKey('blocks'),
        isFalse,
      );
    });

    test('a realtime card keeps its kind AND its blocks', () {
      // This hard-coded `text`, so a card arriving live looked like a
      // sentence until a reload re-fetched it over REST.
      final message = ChatlyMessage.fromRealtime(<String, Object?>{
        'id': 'm1',
        'conversationId': 'c1',
        'authorType': 'bot',
        'kind': 'rich',
        'body': 'Brass desk lamp — USD 48.20',
        'createdAt': '2026-02-03T10:00:00.000Z',
        'blocks': <String, Object?>{
          'v': 1,
          'blocks': <Object?>[
            <String, Object?>{'type': 'card', 'title': 'Brass desk lamp'},
          ],
        },
      });
      expect(message.kind, ChatlyMessageKind.rich);
      final block = readChatlyBlocks(message.blocks)!.blocks.single;
      expect((block as ChatlyCardBlock).card.title, 'Brass desk lamp');
    });

    test('a realtime payload with no kind still reads as text', () {
      expect(
        ChatlyMessage.fromRealtime(<String, Object?>{
          'id': 'm1',
          'authorType': 'agent',
          'body': 'Hello',
          'createdAt': '2026-02-03T10:00:00.000Z',
        }).kind,
        ChatlyMessageKind.text,
      );
    });
  });
}
