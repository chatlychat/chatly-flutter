import 'package:chatly/chatly.dart';
import 'package:flutter_test/flutter_test.dart';

import 'blocks_read_test.dart' show envelope;

/// The card and the grid, split out of `blocks_read_test.dart` to keep both
/// files under this repo's 650-line ceiling. The card is where most of the
/// reader's rulings live: a bad field drops that FIELD and keeps the card,
/// except for the two — a missing title, an empty grid — where there would be
/// nothing left to draw.

void main() {
  group('card', () {
    ChatlyCard? readCard(Map<String, Object?> card) {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{'type': 'card', ...card},
      ]));
      final block = read?.blocks.single;
      return block is ChatlyCardBlock ? block.card : null;
    }

    test('needs a title', () {
      expect(readCard(<String, Object?>{'subtitle': 'No title'}), isNull);
    });

    test('an unsafe image drops the IMAGE, not the card', () {
      final card = readCard(<String, Object?>{
        'title': 'Lamp',
        'image': 'http://cdn.example.com/lamp.png',
      });
      expect(card, isNotNull);
      expect(card!.title, 'Lamp');
      expect(card.image, isNull);
    });

    test('an unreadable price drops the PRICE, not the card', () {
      for (final Object? price in <Object?>[
        'cheap',
        <String, Object?>{'amount': 4820},
        <String, Object?>{'amount': 4820, 'currency': 'usd'},
        <String, Object?>{'amount': -1, 'currency': 'USD'},
        <String, Object?>{'amount': 48.2, 'currency': 'USD'},
        <String, Object?>{'amount': '4820', 'currency': 'USD'},
      ]) {
        final card = readCard(<String, Object?>{'title': 'Lamp', 'price': price});
        expect(card?.price, isNull, reason: '$price');
        expect(card?.title, 'Lamp');
      }
    });

    test('a price in minor units survives, compareAt included', () {
      final card = readCard(<String, Object?>{
        'title': 'Lamp',
        'price': <String, Object?>{
          'amount': 4820,
          'currency': 'USD',
          'compareAt': 6000,
        },
      });
      expect(card!.price!.amount, 4820);
      expect(card.price!.currency, 'USD');
      expect(card.price!.compareAt, 6000);
    });

    test('badges collapse from all three spellings, tone coerced', () {
      expect(
        readCard(<String, Object?>{'title': 'A', 'badge': 'Sale'})!.badges.single.tone,
        ChatlyBadgeTone.neutral,
      );
      final object = readCard(<String, Object?>{
        'title': 'A',
        'badge': <String, Object?>{'text': 'Great price', 'tone': 'success'},
      })!;
      expect(object.badges.single.text, 'Great price');
      expect(object.badges.single.tone, ChatlyBadgeTone.success);

      final mixed = readCard(<String, Object?>{
        'title': 'A',
        'badge': <Object?>[
          'Sale',
          <String, Object?>{'text': 'Above typical', 'tone': 'warning'},
          <String, Object?>{'text': 'Final sale', 'tone': 'iridescent'},
          <String, Object?>{'tone': 'danger'},
          42,
        ],
      })!;
      expect(mixed.badges.map((b) => b.text),
          <String>['Sale', 'Above typical', 'Final sale']);
      // An unrecognised tone keeps the WORDS and loses only the colour.
      expect(mixed.badges.last.tone, ChatlyBadgeTone.neutral);
      expect(readCard(<String, Object?>{'title': 'A', 'badge': 42})!.badges,
          isEmpty);
    });

    test('reactions are filtered and deduped; a reaction must be offered', () {
      final card = readCard(<String, Object?>{
        'title': 'A',
        'reactions': <Object?>['like', 'like', 'shrug', 'dislike', 7],
        'reaction': 'dislike',
      })!;
      expect(card.reactions,
          <ChatlyCardReaction>[ChatlyCardReaction.like, ChatlyCardReaction.dislike]);
      expect(card.reaction, ChatlyCardReaction.dislike);

      final unoffered = readCard(<String, Object?>{
        'title': 'A',
        'reactions': <Object?>['like'],
        'reaction': 'dislike',
      })!;
      expect(unoffered.reaction, isNull);
      expect(readCard(<String, Object?>{'title': 'A', 'reaction': 'like'})!.reaction,
          isNull);
    });

    test('variants keep inStock tri-state and need both halves', () {
      final card = readCard(<String, Object?>{
        'title': 'A',
        'variants': <Object?>[
          <String, Object?>{'label': 'S', 'value': 's'},
          <String, Object?>{'label': 'M', 'value': 'm', 'inStock': false},
          <String, Object?>{'label': 'L', 'value': 'l', 'inStock': 'false'},
          <String, Object?>{'label': 'XL'},
        ],
      })!;
      expect(card.variants.map((v) => v.label), <String>['S', 'M', 'L']);
      expect(card.variants[0].inStock, isNull);
      expect(card.variants[1].inStock, isFalse);
      // The string "false" is truthy in JS and `== false` nowhere: it has to
      // normalise to absent or two renderers disagree about it.
      expect(card.variants[2].inStock, isNull);
    });

    test('an unrecognised stock state is dropped', () {
      expect(
        readCard(<String, Object?>{'title': 'A', 'stock': 'in_stock'})!.stock,
        ChatlyCardStock.inStock,
      );
      expect(
        readCard(<String, Object?>{'title': 'A', 'stock': 'backordered'})!.stock,
        isNull,
      );
    });

    test('the tap target refuses a postback and an unknown kind', () {
      expect(
        readCard(<String, Object?>{
          'title': 'A',
          'action': <String, Object?>{
            'kind': 'postback',
            'label': 'Tap',
            'value': 'tapped',
          },
        })!.action,
        isNull,
      );
      expect(
        readCard(<String, Object?>{
          'title': 'A',
          'action': <String, Object?>{
            'kind': 'url',
            'label': 'Open',
            'href': 'https://e.com/p',
          },
        })!.action!.value,
        'https://e.com/p',
      );
    });

    test('fields and actions are always present, even when absent', () {
      final card = readCard(<String, Object?>{'title': 'A'})!;
      expect(card.fields, isEmpty);
      expect(card.actions, isEmpty);
      expect(card.badges, isEmpty);
    });
  });

  group('card_grid', () {
    test('drops unreadable cards, keeps the grid, honours carousel', () {
      final read = readChatlyBlocks(envelope(<Object?>[
        <String, Object?>{
          'type': 'card_grid',
          'layout': 'carousel',
          'cards': <Object?>[
            <String, Object?>{'title': 'One'},
            <String, Object?>{'subtitle': 'No title'},
            null,
          ],
        },
      ]));
      final grid = read!.blocks.single as ChatlyCardGridBlock;
      expect(grid.cards.map((c) => c.title), <String>['One']);
      expect(grid.carousel, isTrue);
    });

    test('a grid with no readable card is dropped', () {
      expect(
        readChatlyBlocks(envelope(<Object?>[
          <String, Object?>{'type': 'card_grid', 'cards': <Object?>[]},
        ])),
        isNull,
      );
    });

    test('the more tile is narrowed to the kinds that can page', () {
      ChatlyCardGridBlock grid(Object? more) =>
          readChatlyBlocks(envelope(<Object?>[
            <String, Object?>{
              'type': 'card_grid',
              'cards': <Object?>[
                <String, Object?>{'title': 'One'},
              ],
              'more': more,
            },
          ]))!.blocks.single as ChatlyCardGridBlock;

      expect(
        grid(<String, Object?>{
          'label': 'Show all 60',
          'action': <String, Object?>{
            'kind': 'postback',
            'label': 'More',
            'value': 'next',
          },
        }).more!.label,
        'Show all 60',
      );
      // A copy / host_event / step tile is a button that shows no more cards.
      expect(
        grid(<String, Object?>{
          'label': 'Copy',
          'action': <String, Object?>{
            'kind': 'copy',
            'label': 'Copy',
            'text': 'x',
          },
        }).more,
        isNull,
      );
      expect(grid(<String, Object?>{'label': 'No action'}).more, isNull);
      // Losing the tile must never lose the twenty-four cards.
      expect(grid('rubbish').cards, hasLength(1));
    });
  });
}
