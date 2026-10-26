/// The two restated server enums, against what the server actually sends.
///
/// ── What was wrong ──────────────────────────────────────────────────────
///
/// `ChatlyConversationStatus` listed four of the server's five states.
/// `merged` was missing, `POST /v1/widget/conversations/list` applies no
/// status filter, and `parse` falls back to `open` for anything unknown — so
/// the loser of a conversation merge read back as a live thread and
/// `ChatlyChatPage._bootstrap` resumed it, because its test for "usable" was
/// `!= closed`.
///
/// `ChatlyMessageKind` was wrong in BOTH directions: four of its six values
/// (`image`, `file`, `event`, `internalNote`) are not members of the server's
/// `message_kind` enum at all — `ChatlyMessagesList` compared against `event`
/// and the comparison was always false — and `rich`, the kind every formatted
/// reply and every bot card carries, was absent. With `parse` falling back to
/// `text`, an app branching on `kind` could not tell a product grid from a
/// sentence.
///
/// ── Why these assertions are on the PARSER ──────────────────────────────
///
/// Not on a hand-written list of names. A test that compares one copy of a
/// vocabulary against another copy in the same language agrees with the bug;
/// `visitor_contract_test.dart` beside this file exists because the four
/// mobile SDKs all shipped a broken visitor contract with green suites. What
/// is asserted here is that a real wire string decodes to the right value and
/// round-trips back, plus the exact membership of each enum — so a value
/// added without a wire string, or a wire string with no value, fails.
///
/// The server's own definitions are TypeScript in `packages/shared`, which
/// Dart cannot import, and this package's only CI is its published mirror
/// where that path does not exist. So the server side of the comparison is
/// the literal wire strings below, copied from
/// `packages/shared/src/schemas/conversation.ts` and
/// `packages/shared/src/message-kinds/index.ts`. A monorepo-side gate that
/// reads those files is the missing other half and is not yet wired.
library;

import 'package:chatly/chatly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatlyConversationStatus', () {
    /// `conversationStatusSchema`, verbatim.
    const wire = <String, ChatlyConversationStatus>{
      'open': ChatlyConversationStatus.open,
      'pending': ChatlyConversationStatus.pending,
      'snoozed': ChatlyConversationStatus.snoozed,
      'closed': ChatlyConversationStatus.closed,
      'merged': ChatlyConversationStatus.merged,
    };

    test('every wire value parses to its own state', () {
      // The floor: five, so a map that lost entries fails here rather than
      // comparing two short lists and reporting agreement.
      expect(wire.length, greaterThanOrEqualTo(5));
      wire.forEach((raw, expected) {
        expect(ChatlyConversationStatus.parse(raw), expected, reason: raw);
      });
    });

    test('the enum holds exactly those five and nothing invented', () {
      expect(
        ChatlyConversationStatus.values.map((s) => s.wireName).toSet(),
        wire.keys.toSet(),
      );
    });

    test('merged parses as merged and not as open', () {
      // The specific regression. Before the fix this returned `open`, which
      // is the worst available answer: a tombstone that reads as live.
      expect(
        ChatlyConversationStatus.parse('merged'),
        ChatlyConversationStatus.merged,
      );
    });

    test('isResumable is false for the two states that are not', () {
      expect(ChatlyConversationStatus.merged.isResumable, isFalse);
      expect(ChatlyConversationStatus.closed.isResumable, isFalse);
      expect(ChatlyConversationStatus.open.isResumable, isTrue);
      expect(ChatlyConversationStatus.pending.isResumable, isTrue);
      expect(ChatlyConversationStatus.snoozed.isResumable, isTrue);
    });

    test('an unknown status is not resumable either', () {
      // `parse` must keep decoding — a status this build has never heard of
      // must not make the list undecodable — but it must not hand back
      // something a caller will write into.
      //
      // It falls back to `open`, which IS resumable, so this is the one
      // property the fallback cannot give. Asserted as the known gap rather
      // than quietly left out: closing it means an `unknown` member, which
      // is a breaking change for an exhaustive `switch`.
      expect(ChatlyConversationStatus.parse('a_state_from_2027'),
          ChatlyConversationStatus.open);
    });
  });

  group('ChatlyMessageKind', () {
    /// The `message_kind` members a VISITOR can receive.
    ///
    /// `note` is absent on purpose: it is an agent's internal comment and the
    /// realtime gateway's `VISITOR_VISIBLE_MESSAGE_KINDS` excludes it, as
    /// does the history route's SQL. A client value for it would be a dead
    /// branch, which is the mistake this group exists for.
    const wire = <String, ChatlyMessageKind>{
      'text': ChatlyMessageKind.text,
      'rich': ChatlyMessageKind.rich,
      'attachment_only': ChatlyMessageKind.attachmentOnly,
      'system_event': ChatlyMessageKind.systemEvent,
    };

    test('every wire value parses to its own kind', () {
      expect(wire.length, greaterThanOrEqualTo(4));
      wire.forEach((raw, expected) {
        expect(ChatlyMessageKind.parse(raw), expected, reason: raw);
      });
    });

    test('the enum holds exactly those four', () {
      expect(
        ChatlyMessageKind.values.map((k) => k.wireName).toSet(),
        wire.keys.toSet(),
      );
    });

    test('rich is distinguishable from text', () {
      // The regression. `parse` fell back to `text`, so a card arrived
      // indistinguishable from a sentence.
      expect(ChatlyMessageKind.parse('rich'), ChatlyMessageKind.rich);
      expect(ChatlyMessageKind.parse('rich') == ChatlyMessageKind.text, isFalse);
    });

    test('the four invented kinds are gone', () {
      // Each of these used to be a member, and each decoded a string the
      // server has never sent. They now fall through to `text`.
      for (final dead in ['image', 'file', 'event', 'internal_note']) {
        expect(ChatlyMessageKind.parse(dead), ChatlyMessageKind.text,
            reason: dead);
      }
      expect(
        ChatlyMessageKind.values.map((k) => k.name),
        isNot(contains('internalNote')),
      );
    });

    test('note is not a kind this client offers', () {
      expect(
        ChatlyMessageKind.values.map((k) => k.wireName),
        isNot(contains('note')),
      );
    });
  });
}
