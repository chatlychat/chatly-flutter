import 'package:chatly/chatly.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule under test everywhere here: render what you can, never throw.
///
/// A server newer than the app sends block types and fields this release has
/// never heard of, and the reader's job is to drop those and keep the rest —
/// so most of these cases assert on what SURVIVED a bad value, not on a
/// refusal.

Map<String, Object?> envelope(List<Object?> blocks) =>
    <String, Object?>{'v': 1, 'blocks': blocks};

/// One readable block, so a case can prove the REST of a message survived.
const Map<String, Object?> textBlock = <String, Object?>{
  'type': 'text',
  'markdown': 'Here you go',
};

void main() {
  group('envelope', () {
    test('reads a v1 envelope', () {
      final read = readChatlyBlocks(envelope(<Object?>[textBlock]));
      expect(read, isNotNull);
      expect(read!.blocks, hasLength(1));
      expect((read.blocks.single as ChatlyTextBlock).markdown, 'Here you go');
    });

    test('refuses anything that is not a v1 envelope, without throwing', () {
      for (final Object? raw in <Object?>[
        null,
        'blocks',
        42,
        <Object?>[textBlock],
        <String, Object?>{'v': 2, 'blocks': <Object?>[textBlock]},
        <String, Object?>{'v': 1, 'blocks': 'nope'},
        <String, Object?>{'v': 1},
        <String, Object?>{},
      ]) {
        expect(readChatlyBlocks(raw), isNull, reason: 'for $raw');
      }
    });

    test('an envelope of garbage reads as nothing, not as an exception', () {
      expect(
        readChatlyBlocks(envelope(<Object?>[null, 1, 'x', <Object?>[], {}])),
        isNull,
      );
    });

    test('an UNKNOWN block type is dropped and the rest renders', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{'type': 'hologram', 'spin': 3},
        textBlock,
        <String, Object?>{'type': 'quantum_card', 'title': 'From the future'},
      ]));
      expect(read!.blocks, hasLength(1));
      expect(read.blocks.single, isA<ChatlyTextBlock>());
    });

    test('a non-string block id is dropped, not the block', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{...textBlock, 'id': 7},
      ]));
      expect(read!.blocks.single.id, isNull);
    });
  });

  group('media guard', () {
    test('accepts https and nothing else', () {
      expect(isSafeMediaSrc('https://cdn.example.com/a.png'), isTrue);
      for (final src in <String>[
        'http://cdn.example.com/a.png',
        'data:image/png;base64,AAAA',
        'javascript:alert(1)',
        'file:///etc/passwd',
        ' https://cdn.example.com/a.png',
        'https://cdn.example.com/a.png ',
        'https://cdn.example.com/\u0000a.png',
        'https://cdn.example.com/\na.png',
        '',
        'not a url',
      ]) {
        expect(isSafeMediaSrc(src), isFalse, reason: src);
      }
      expect(isSafeMediaSrc('https://e.com/${'a' * 2000}'), isFalse);
    });

    test('a media block IS its image, so a refused src drops the block', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'media',
          'kind': 'image',
          'url': 'http://cdn.example.com/a.png',
          'alt': 'A photo',
        },
        textBlock,
      ]));
      expect(read!.blocks, hasLength(1));
      expect(read.blocks.single, isA<ChatlyTextBlock>());
    });

    test('a media block needs alt and a known kind', () {
      for (final bad in <Map<String, Object?>>[
        <String, Object?>{'kind': 'image', 'url': 'https://e.com/a.png'},
        <String, Object?>{
          'kind': 'hologram',
          'url': 'https://e.com/a.png',
          'alt': 'x',
        },
      ]) {
        expect(
          readChatlyBlocks(envelope(<Object?>[
            <String, Object?>{'type': 'media', ...bad},
          ])),
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  group('action guard', () {
    test('a url action takes https, mailto and tel only', () {
      expect(isSafeActionHref('https://shop.example.com/x'), isTrue);
      expect(isSafeActionHref('mailto:help@example.com'), isTrue);
      expect(isSafeActionHref('tel:+15551234567'), isTrue);
      for (final href in <String>[
        'http://shop.example.com',
        'intent://scan#Intent;scheme=zxing;end',
        'itms-apps://apps.apple.com/app/id1',
        'javascript:alert(1)',
        'myapp://pay',
      ]) {
        expect(isSafeActionHref(href), isFalse, reason: href);
      }
    });

    test('each kind needs its own required field', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'actions',
          'actions': <Object?>[
            <String, Object?>{
              'kind': 'url',
              'label': 'Open',
              'href': 'https://e.com',
            },
            <String, Object?>{'kind': 'url', 'label': 'No href'},
            <String, Object?>{
              'kind': 'url',
              'label': 'Downgrade',
              'href': 'http://e.com',
            },
            <String, Object?>{
              'kind': 'postback',
              'label': 'Yes',
              'value': 'yes',
              'silent': true,
              'payload': <String, Object?>{'sku': 'A1'},
            },
            <String, Object?>{'kind': 'postback', 'label': 'No value'},
            <String, Object?>{
              'kind': 'host_event',
              'label': 'Pay',
              'event': 'checkout',
              'data': <String, Object?>{'total': 4820},
            },
            <String, Object?>{
              'kind': 'step',
              'label': 'Form',
              'canvasId': 'c1',
            },
            <String, Object?>{'kind': 'copy', 'label': 'Copy', 'text': 'ABC'},
            <String, Object?>{
              'kind': 'navigate',
              'label': 'Cart',
              'path': '/cart',
            },
            <String, Object?>{
              'kind': 'teleport',
              'label': 'Future kind',
              'value': 'x',
            },
            <String, Object?>{'kind': 'postback', 'value': 'no label'},
          ],
        },
      ]));
      final actions = (read!.blocks.single as ChatlyActionsBlock).actions;
      expect(
        actions.map((a) => a.label),
        <String>['Open', 'Yes', 'Pay', 'Form', 'Copy', 'Cart'],
      );
      final postback = actions[1];
      expect(postback.kind, ChatlyBlockActionKind.postback);
      expect(postback.value, 'yes');
      expect(postback.silent, isTrue);
      expect(postback.data, <String, Object?>{'sku': 'A1'});
      expect(actions[2].value, 'checkout');
      expect(actions[2].data, <String, Object?>{'total': 4820});
      expect(actions[3].value, 'c1');
      expect(actions[5].kind, ChatlyBlockActionKind.navigate);
    });

    test('an actions block with nothing readable is dropped', () {
      expect(
        readChatlyBlocks(envelope(<Object?>[
          <String, Object?>{
            'type': 'actions',
            'actions': <Object?>[
              <String, Object?>{'kind': 'url', 'label': 'x'},
            ],
          },
        ])),
        isNull,
      );
    });
  });

  group('order_status', () {
    List<ChatlyOrderStep>? steps(List<Object?> raw) {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{'type': 'order_status', 'steps': raw},
      ]));
      final block = read?.blocks.single;
      return block is ChatlyOrderStatusBlock ? block.steps : null;
    }

    test('an unknown state is COERCED, so the row survives', () {
      final read = steps(<Object?>[
        <String, Object?>{'label': 'Packed', 'state': 'done'},
        <String, Object?>{'label': 'Payment failed', 'state': 'failed'},
        <String, Object?>{'label': 'Delivered'},
        <String, Object?>{'state': 'done'},
      ])!;
      expect(read.map((s) => s.label),
          <String>['Packed', 'Payment failed', 'Delivered']);
      expect(read[0].state, ChatlyStepState.done);
      // The words "Payment failed" are what a person reads; only the dot's
      // shape is lost.
      expect(read[1].state, ChatlyStepState.pending);
    });

    test('an unparseable timestamp drops the DATE, not the step', () {
      final read = steps(<Object?>[
        <String, Object?>{
          'label': 'Shipped',
          'state': 'done',
          'at': '2026-02-03T10:00:00.000Z',
        },
        <String, Object?>{'label': 'Soon', 'state': 'pending', 'at': 'whenever'},
        <String, Object?>{'label': 'Also soon', 'state': 'pending', 'at': 7},
      ])!;
      expect(read[0].at, isNotNull);
      expect(read[1].at, isNull);
      expect(read[2].at, isNull);
      expect(read, hasLength(3));
    });

    test('no readable step is no timeline', () {
      expect(steps(<Object?>[<String, Object?>{'state': 'done'}]), isNull);
      expect(steps(<Object?>[]), isNull);
    });
  });

  group('table', () {
    ChatlyTableBlock? table(Map<String, Object?> raw) {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{'type': 'table', ...raw},
      ]));
      final block = read?.blocks.single;
      return block is ChatlyTableBlock ? block : null;
    }

    test('an unreadable heading is COERCED and keeps its position', () {
      final read = table(<String, Object?>{
        'caption': 'Compare',
        'columns': <Object?>[
          <String, Object?>{'label': 'Basic'},
          <String, Object?>{'image': 'https://e.com/p.png'},
          <String, Object?>{'label': 'Pro', 'image': 'http://e.com/p.png'},
        ],
        'rows': <Object?>[
          <String, Object?>{
            'label': 'Price',
            'cells': <Object?>['USD 10', 'USD 20', 'USD 30', 'USD 40'],
          },
          <String, Object?>{'label': 'Seats', 'cells': <Object?>['1']},
          <String, Object?>{'label': 'Odd', 'cells': <Object?>[1, null, true]},
          <String, Object?>{'cells': <Object?>['no label']},
        ],
      })!;
      expect(read.caption, 'Compare');
      expect(read.columns.map((c) => c.label), <String>['Basic', '', 'Pro']);
      // The guard applies to a heading image too, and drops the image only.
      expect(read.columns[2].image, isNull);
      expect(read.rows.map((r) => r.label), <String>['Price', 'Seats', 'Odd']);
      // A longer row is truncated: a fourth cell under no heading is a
      // column the reader invented.
      expect(read.rows[0].cells, <String>['USD 10', 'USD 20', 'USD 30']);
      // A short row is deliberately fine and renders blanks.
      expect(read.rows[1].cells, <String>['1']);
      expect(read.rows[2].cells, <String>['', '', '']);
    });

    test('no readable heading and no readable row are both refusals', () {
      expect(
        table(<String, Object?>{
          'columns': <Object?>[<String, Object?>{'image': 'https://e.com/p.png'}],
          'rows': <Object?>[<String, Object?>{'label': 'Price'}],
        }),
        isNull,
      );
      expect(
        table(<String, Object?>{
          'columns': <Object?>[<String, Object?>{'label': 'Basic'}],
          'rows': <Object?>[],
        }),
        isNull,
      );
    });
  });

  group('the remaining types', () {
    test('fields needs one readable pair', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'fields',
          'items': <Object?>[
            <String, Object?>{'label': 'Order', 'value': '#1'},
            <String, Object?>{'label': 'No value'},
          ],
        },
      ]));
      expect((read!.blocks.single as ChatlyFieldsBlock).items, hasLength(1));
      expect(
        readChatlyBlocks(envelope(<Object?>[
          <String, Object?>{'type': 'fields', 'items': <Object?>[]},
        ])),
        isNull,
      );
    });

    test('quick_replies needs label and value on an option', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'quick_replies',
          'options': <Object?>[
            <String, Object?>{'label': 'Yes please', 'value': 'yes'},
            <String, Object?>{'label': 'Unanswerable'},
          ],
        },
      ]));
      final options = (read!.blocks.single as ChatlyQuickRepliesBlock).options;
      expect(options.single.label, 'Yes please');
      expect(options.single.value, 'yes');
    });

    test('place keeps its label and drops non-string detail', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'place',
          'label': 'Helpdesk',
          'detail': 7,
          'ref': 'node-9',
        },
        <String, Object?>{'type': 'place', 'detail': 'No label'},
      ]));
      final place = read!.blocks.single as ChatlyPlaceBlock;
      expect(place.label, 'Helpdesk');
      expect(place.detail, isNull);
      expect(place.ref, 'node-9');
    });

    test('status needs an id — it exists to be patched', () {
      expect(
        readChatlyBlocks(envelope(<Object?>[
          <String, Object?>{'type': 'status', 'text': 'Looking…'},
        ])),
        isNull,
      );
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'status',
          'id': 's1',
          'text': 'Looking…',
          'state': 'running',
        },
      ]));
      final status = read!.blocks.single as ChatlyStatusBlock;
      expect(status.id, 's1');
      expect(status.state, ChatlyStatusState.running);
    });

    test('divider is always readable', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{'type': 'divider'},
      ]));
      expect(read!.blocks.single, isA<ChatlyDividerBlock>());
    });
  });

  group('money and labels', () {
    test('the divisor is not 100', () {
      // Two digits: the case that would pass with any implementation.
      expect(
        formatChatlyMoney(
            const ChatlyMoney(amount: 4820, currency: 'USD')),
        contains('48.20'),
      );
      // No minor unit: `amount / 100` would render this as ¥48.
      expect(
        formatChatlyMoney(const ChatlyMoney(amount: 4820, currency: 'JPY')),
        contains('4,820'),
      );
      // Three digits: `amount / 100` would render this as 48.200 KWD.
      expect(
        formatChatlyMoney(const ChatlyMoney(amount: 4820, currency: 'KWD')),
        contains('4.820'),
      );
    });

    test('a currency the formatter cannot resolve still shows a price', () {
      expect(
        formatChatlyMoney(const ChatlyMoney(amount: 4820, currency: 'ZZZ')),
        contains('48.20'),
      );
    });

    test('compareAt renders only when it is above the price', () {
      expect(
        formatChatlyCompareAt(const ChatlyMoney(
          amount: 4820,
          currency: 'USD',
          compareAt: 6000,
        )),
        contains('60.00'),
      );
      expect(
        formatChatlyCompareAt(const ChatlyMoney(
          amount: 4820,
          currency: 'USD',
          compareAt: 4000,
        )),
        isNull,
      );
      expect(
        formatChatlyCompareAt(
            const ChatlyMoney(amount: 4820, currency: 'USD')),
        isNull,
      );
    });

    test('a step line states the state in words and loses no separator', () {
      expect(
        chatlyStepLine(const ChatlyOrderStep(
          label: 'Delivered',
          state: ChatlyStepState.pending,
        )),
        'Delivered — Pending',
      );
      expect(
        chatlyStepLine(ChatlyOrderStep(
          label: 'Shipped',
          state: ChatlyStepState.done,
          at: DateTime.utc(2026, 2, 3, 10),
        )),
        startsWith('Shipped — Done · '),
      );
    });

    test('a badge carries its tone as a glyph and as a word', () {
      const badge =
          ChatlyCardBadge(text: 'Great price', tone: ChatlyBadgeTone.success);
      expect(chatlyBadgeText(badge), '✓ Great price');
      expect(chatlyBadgeSemanticLabel(badge), 'Great price (positive)');
      const plain = ChatlyCardBadge(text: 'Sale', tone: ChatlyBadgeTone.neutral);
      expect(chatlyBadgeText(plain), 'Sale');
      expect(chatlyBadgeSemanticLabel(plain), 'Sale');
    });

    test('stock is in this surface own words, not the enum member', () {
      expect(chatlyStockLabel(ChatlyCardStock.outOfStock), 'Out of stock');
    });
  });
}
