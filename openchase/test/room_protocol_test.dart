import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/protocol/room_models.dart';

Map<String, dynamic> fakeEvent({
  required String pubkey,
  required int kind,
  required Map<String, dynamic> content,
  int? id,
}) {
  return {
    'id': '${id ?? pubkey.length}${pubkey.substring(0, 8)}',
    'pubkey': pubkey,
    'created_at': 1750000000,
    'kind': kind,
    'tags': [],
    'content': jsonEncode(content),
  };
}

void main() {
  group('RoomEvent.tryParse', () {
    test('parses a relay EVENT frame', () {
      final raw = jsonEncode([
        'EVENT',
        'sub1',
        fakeEvent(
          pubkey: 'aa' * 32,
          kind: RoomKinds.room,
          content: {'msg': RoomMsg.roster, 'seq': 3, 'roster': []},
        ),
      ]);
      final e = RoomEvent.tryParse(raw)!;
      expect(e.kind, RoomKinds.room);
      expect(e.msg, RoomMsg.roster);
      expect(e.data['seq'], 3);
    });

    test('parses array-form event payload too', () {
      final raw = jsonEncode([
        'EVENT',
        'sub1',
        [
          'ff' * 32,
          'aa' * 32,
          1750000001,
          RoomKinds.location,
          <String>[],
          '{"lat":1.0,"lng":2.0}',
        ],
      ]);
      final e = RoomEvent.tryParse(raw)!;
      expect(e.kind, RoomKinds.location);
      expect(e.createdAt, 1750000001);
      final loc = LocationData.from(e)!;
      expect(loc.lat, 1.0);
    });

    test('round_start carries endsAt and hiders', () {
      final e = RoomEvent(
        id: 'aa',
        pubkey: 'bb',
        createdAt: 1750000000,
        kind: RoomKinds.room,
        data: {
          'msg': RoomMsg.roundStart,
          'roundId': 'r1',
          'center': [1.0, 2.0],
          'radius': 500,
          'items': [
            {'id': 'i0', 'type': 'speed', 'lat': 1.1, 'lng': 2.2},
          ],
          'endsAt': 12345,
          'hiders': ['pkH1', 'pkH2'],
        },
      );
      final r = RoundStartData.from(e)!;
      expect(r.endsAt, 12345);
      expect(r.hiders, ['pkH1', 'pkH2']);
      expect(r.items.first.type, 'speed');
    });

    test('parses items in map and pair form, legacy pairs get ids', () {
      final items = ItemData.parseList([
        {'id': 'x1', 'type': 'health', 'lat': 50.9, 'lng': 6.9},
        [50.941, 6.961],
      ]);
      expect(items.length, 2);
      expect(items[0].id, 'x1');
      expect(items[0].type, 'health');
      expect(items[1].id, 'i1');
      expect(items[1].type, 'item');
      expect(items[1].lat, 50.941);
    });

    test('distanceMeters is sane', () {
      // ~157 m for 0.001 deg latitude
      final d = distanceMeters(50.9, 6.9, 50.901, 6.9);
      expect(d, closeTo(111.2, 1.0));
      expect(distanceMeters(50.9, 6.9, 50.9, 6.9), 0);
    });

    test('returns null for non-event frames', () {
      expect(RoomEvent.tryParse('["OK","x","id",true,""]'), isNull);
      expect(RoomEvent.tryParse('not json'), isNull);
      expect(RoomEvent.tryParse('[1,2]'), isNull);
    });

    test('malformed content still parses with empty data', () {
      final ev = fakeEvent(pubkey: 'bb' * 32, kind: 9999, content: {});
      ev['content'] = 'garbage not json';
      final e = RoomEvent.tryParse(jsonEncode(['EVENT', 's', ev]))!;
      expect(e.data, isEmpty);
    });
  });

  group('RoomKeys', () {
    test('room identity is deterministic per code', () {
      final a = RoomKeys.fromCode('abcd');
      final b = RoomKeys.fromCode('ABCD');
      expect(a.roomPubkey, b.roomPubkey);
      expect(a.roomPubkey.length, 64);
    });

    test('different codes derive different identities', () {
      expect(
        RoomKeys.fromCode('ABCD').roomPubkey,
        isNot(RoomKeys.fromCode('ABCE').roomPubkey),
      );
    });

    test('player keychains are unique', () {
      final a = RoomKeys.generatePlayerKeychain();
      final b = RoomKeys.generatePlayerKeychain();
      expect(a.public, isNot(b.public));
    });
  });

  group('payload models', () {
    test('RoundStartData parses valid payload, rejects bad center', () {
      final good =
          RoomEvent.tryParse(
            jsonEncode([
              'EVENT',
              's',
              fakeEvent(
                pubkey: 'cc' * 32,
                kind: RoomKinds.room,
                content: {
                  'msg': RoomMsg.roundStart,
                  'roundId': 'r1',
                  'center': [50.9, 6.9],
                  'radius': 500,
                  'items': [
                    [50.91, 6.91],
                  ],
                },
              ),
            ]),
          )!;
      final round = RoundStartData.from(good)!;
      expect(round.roundId, 'r1');
      expect(round.centerLat, 50.9);
      expect(round.radiusM, 500);
      expect(round.items.length, 1);

      final bad =
          RoomEvent.tryParse(
            jsonEncode([
              'EVENT',
              's',
              fakeEvent(
                pubkey: 'cc' * 32,
                kind: RoomKinds.room,
                content: {'msg': RoomMsg.roundStart, 'center': 'nope'},
              ),
            ]),
          )!;
      expect(RoundStartData.from(bad), isNull);
    });

    test('LocationData parses accuracy optionality', () {
      final e =
          RoomEvent.tryParse(
            jsonEncode([
              'EVENT',
              's',
              fakeEvent(
                pubkey: 'dd' * 32,
                kind: RoomKinds.location,
                content: {'lat': 1.5, 'lng': 2.5},
              ),
            ]),
          )!;
      final loc = LocationData.from(e)!;
      expect(loc.lat, 1.5);
      expect(loc.accuracy, isNull);
      expect(loc.ts, 1750000000);
    });
  });
}
