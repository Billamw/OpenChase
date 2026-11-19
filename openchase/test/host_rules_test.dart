import 'package:flutter_test/flutter_test.dart';
import 'package:openchase/utils/protocol/room_host.dart';
import 'package:openchase/utils/protocol/room_items.dart';
import 'package:openchase/utils/protocol/room_models.dart';

/// Pure unit tests for the items-v1 host authority (RoomHost). The clock is
/// injected and every publish is captured, so all timing/visibility rules
/// are exercised deterministically without relays.
class Capture {
  int now = 1_000_000;
  final List<Map<String, dynamic>> room = [];
  final List<(String, Map<String, dynamic>)> targeted = [];

  RoomHost host() => RoomHost(
    now: () => now,
    publishRoom: room.add,
    publishTargeted: (pk, p) => targeted.add((pk, p)),
  );

  Map<String, dynamic>? last(String msg) {
    for (final p in room.reversed) {
      if (p['msg'] == msg) return p;
    }
    return null;
  }

  int count(String msg) => room.where((p) => p['msg'] == msg).length;
  int targetedCount() => targeted.length;
}

const cLat = 50.94;
const cLng = 6.96;
double latM(double m) => cLat + m / 111200.0;

RoomHost makeRound(
  Capture c, {
  required List<ItemData> items,
  List<String> hiders = const ['H'],
  List<String> all = const ['S', 'H'],
  int bankCap = 3,
  int headStartSec = 0,
  int durationSec = 1800,
}) {
  final h = c.host();
  for (final pk in all) {
    h.addParticipant(pk);
  }
  h.onRoundStart(
    RoundStartData(
      roundId: 'r1',
      centerLat: cLat,
      centerLng: cLng,
      radiusM: 300,
      items: items,
      endsAt: c.now + durationSec,
      hiders: hiders,
      density: 'normal',
      bankCap: bankCap,
      headStartEndsAt: headStartSec > 0 ? c.now + headStartSec : 0,
    ),
  );
  return h;
}

ItemData it(String id, String type, {double m = 0}) =>
    ItemData(id: id, type: type, lat: latM(m), lng: cLng);

void give(Capture c, RoomHost h, String pk, String itemId, {double m = 0}) {
  c.now += 1;
  h.ingestLocation(pk, LocationData(lat: latM(m), lng: cLng, ts: c.now));
  h.handleItemHit(pk, itemId);
}

void main() {
  group('pickup arbitration', () {
    test('in-range winner banks; out-of-range and stale claims rejected', () {
      final c = Capture();
      final h = makeRound(
        c,
        items: [it('i0', 'radar_pulse'), it('i1', 'drone')],
      );
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(500), lng: cLng, ts: c.now));
      h.handleItemHit('S', 'i0'); // 500 m away — reject silently
      expect(c.count(RoomMsg.itemCollected), 0);
      c.now += 6;
      h.ingestLocation('S', LocationData(lat: latM(0), lng: cLng, ts: c.now - 6));
      h.handleItemHit('S', 'i0'); // stale position — reject
      expect(c.count(RoomMsg.itemCollected), 0);
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(10), lng: cLng, ts: c.now));
      h.handleItemHit('S', 'i0');
      expect(c.count(RoomMsg.itemCollected), 1);
      expect(c.last(RoomMsg.itemCollected)!['by'], 'S');
      // first-come: a second claim on a claimed item publishes nothing.
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      h.handleItemHit('H', 'i0');
      expect(c.count(RoomMsg.itemCollected), 1);
      expect(h.bankOf('S'), ['i0']);
      expect(h.bankOf('H'), isEmpty);
    });

    test('bank cap: N+1th grab -> BANK_FULL; cap from round settings used', () {
      final c = Capture();
      final items = [
        it('i0', 'radar_pulse'),
        it('i1', 'proof_of_life'),
        it('i2', 'found_clue'),
        it('i3', 'radar_pulse'),
      ];
      final h = makeRound(c, items: items, bankCap: 2);
      for (final id in ['i0', 'i1', 'i2', 'i3']) {
        give(c, h, 'S', id);
      }
      expect(h.bankOf('S'), ['i0', 'i1']);
      expect(c.count(RoomMsg.itemRejected), 2);
      expect(c.last(RoomMsg.itemRejected)!['reason'], EffectReason.bankFull);
      expect(c.last(RoomMsg.itemRejected)!['to'], 'S');
      // default cap 3
      final c2 = Capture();
      final h2 = makeRound(c2, items: items);
      for (final id in ['i0', 'i1', 'i2', 'i3']) {
        give(c2, h2, 'S', id);
      }
      expect(h2.bankOf('S').length, 3);
      expect(c2.count(RoomMsg.itemRejected), 1);
    });
  });

  group('phases', () {
    test('head_start phase published; hunt transition emits anchor reveal '
        'exactly once with latest hider positions', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'drone')], headStartSec: 120);
      expect(h.phase, RoundPhase.headStart);
      expect(c.last(RoomMsg.phaseChanged)!['phase'], RoundPhase.headStart);
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(100), lng: cLng, ts: c.now));
      c.now += 120; // host timer fires at headStartEndsAt
      h.enterHunt();
      expect(h.phase, RoundPhase.hunt);
      expect(c.last(RoomMsg.phaseChanged)!['phase'], RoundPhase.hunt);
      final ar = c.last(RoomMsg.anchorReveal)!;
      final pos = ar['positions'] as List;
      expect(pos.length, 1);
      expect(pos[0][0], 'H');
      expect(pos[0][1], closeTo(latM(100), 1e-9));
      h.enterHunt();
      h.enterHunt();
      expect(c.count(RoomMsg.anchorReveal), 1);
      expect(c.count(RoomMsg.phaseChanged), 2);
    });

    test('items locked during head_start -> NOT_HUNT_PHASE', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'clock_plus')], headStartSec: 300);
      give(c, h, 'H', 'i0'); // pickups stay open during head_start
      expect(h.bankOf('H'), ['i0']);
      h.handleItemUse('H', 'i0');
      expect(
        c.last(RoomMsg.effectRejected)!['reason'],
        EffectReason.notHuntPhase,
      );
    });
  });

  group('zone soft-lock (head start)', () {
    test('1 ping nothing; 2 consecutive pings beyond grace -> zone_softlock; '
        'return releases; 15 m grace honored', () {
      final c = Capture();
      final h = makeRound(c, items: const [], headStartSec: 600);
      // outside radius but within the 15 m grace band -> treated as inside
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(310), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(310), lng: cLng, ts: c.now));
      expect(c.count(RoomMsg.zoneSoftlock), 0);
      // beyond radius+grace: ping 1 -> nothing
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(400), lng: cLng, ts: c.now));
      expect(c.count(RoomMsg.zoneSoftlock), 0);
      // ping 2 (consecutive) -> soft-lock
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(400), lng: cLng, ts: c.now));
      expect(c.count(RoomMsg.zoneSoftlock), 1);
      expect(c.last(RoomMsg.zoneSoftlock)!['seeker'], 'S');
      expect(h.isSoftlocked('S'), isTrue);
      // alternating in/out never reaches 2 consecutive misses
      final c2 = Capture();
      final h2 = makeRound(c2, items: const [], headStartSec: 600);
      for (final m in [400.0, 10.0, 400.0, 10.0]) {
        c2.now += 1;
        h2.ingestLocation(
          'S',
          LocationData(lat: latM(m), lng: cLng, ts: c2.now),
        );
      }
      expect(c2.count(RoomMsg.zoneSoftlock), 0);
      // return to zone releases
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(50), lng: cLng, ts: c.now));
      expect(h.isSoftlocked('S'), isFalse);
      expect(c.last(RoomMsg.zoneSoftlock)!['released'], true);
    });
  });

  group('clock items', () {
    test('+ extends endsAt; - subtracts; clamp to now+60; never ends round', () {
      final c = Capture();
      final h = makeRound(c, items: [
        it('i0', 'clock_plus'),
        it('i1', 'clock_minus'),
        it('i2', 'clock_minus'),
      ], durationSec: 100);
      final start = h.endsAt;
      give(c, h, 'H', 'i0');
      give(c, h, 'S', 'i1');
      give(c, h, 'S', 'i2');
      h.handleItemUse('H', 'i0'); // +180
      expect(c.last(RoomMsg.roundTimer)!['endsAt'], start + 180);
      h.handleItemUse('S', 'i1'); // -120 from start+180
      expect(c.last(RoomMsg.roundTimer)!['endsAt'], start + 60);
      // second minus: start+60-120 < now+60 -> clamped to now+60
      h.handleItemUse('S', 'i2');
      expect(c.last(RoomMsg.roundTimer)!['endsAt'], c.now + 60);
      expect(h.endsAt, greaterThan(c.now)); // round never ended by clock-
    });
  });

  group('anti-stack slot', () {
    test('second info-effect while active -> ALREADY_ACTIVE; expired frees '
        'the slot; exempt items unaffected', () {
      final c = Capture();
      final h = makeRound(c, items: [
        it('i0', 'reveal'),
        it('i1', 'drone'),
        it('i2', 'decoy'),
      ]);
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(200), lng: cLng, ts: c.now));
      give(c, h, 'S', 'i0');
      give(c, h, 'S', 'i1');
      give(c, h, 'H', 'i2');
      h.handleItemUse('S', 'i0', target: 'H');
      expect(c.last(RoomMsg.effectStarted)!['type'], 'reveal');
      h.handleItemUse('S', 'i1', center: [cLat, cLng]);
      expect(
        c.last(RoomMsg.effectRejected)!['reason'],
        EffectReason.alreadyActive,
      );
      c.now += revealDurationS + 1;
      h.handleItemUse('S', 'i1', center: [cLat, cLng]);
      expect(c.last(RoomMsg.effectStarted)!['type'], 'drone');
      // exempt: hider items never touch the seeker slot
      h.handleItemUse('H', 'i2');
      expect(c.last(RoomMsg.effectStarted)!['type'], 'decoy');
    });
  });

  group('eyes radius (hunt visibility)', () {
    test('49 m publishes to that seeker, 51 m suppressed; hysteresis at the '
        'boundary (hold <=55, re-acquire <=45)', () {
      final c = Capture();
      final h = makeRound(c, items: const []);
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(51), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 0); // 51 m fresh: no acquisition
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(49), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 1); // acquired at 49 m
      expect(c.targeted.last.$1, 'S');
      expect(c.targeted.last.$2['hider'], 'H');
      // hold band: 51 m still streams once acquired (<= 55)
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(51), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 2);
      // 52 m also streams (<= 55)
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(52), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 3);
      // 60 m -> drop
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(60), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 3);
      // 48 m -> NOT reacquired yet (must reach <= 45)
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(48), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 3);
      // 44 m -> reacquired
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(44), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 4);
    });

    test('hider pings fan out to seekers holding an eyes pair', () {
      final c = Capture();
      final h = makeRound(c, items: const []);
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(30), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 0); // pair unknown when S pinged first
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(30), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 1); // acquire
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(28), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 2); // hider ping streams to holder
    });

    test('second seeker outside the radius gets nothing', () {
      final c = Capture();
      final h = makeRound(c, items: const [], all: ['S1', 'S2', 'H']);
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('S1', LocationData(lat: latM(40), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('S2', LocationData(lat: latM(90), lng: cLng, ts: c.now));
      expect(c.targetedCount(), 1);
      expect(c.targeted.every((t) => t.$1 == 'S1'), isTrue);
    });
  });

  group('disturber jam', () {
    test('jam suppresses seeker-bound publishes, rejects seeker item_use '
        'with JAMMED, cancels active seeker effects once each, no refund', () {
      final c = Capture();
      final h = makeRound(c, items: [
        it('i0', 'reveal'),
        it('i1', 'disturber'),
        it('i2', 'clock_minus'),
      ]);
      give(c, h, 'H', 'i1', m: 0);
      give(c, h, 'S', 'i0');
      give(c, h, 'S', 'i2', m: 10);
      final tBefore = c.targetedCount(); // eyes pairs already formed
      h.handleItemUse('S', 'i0', target: 'H');
      expect(c.last(RoomMsg.effectStarted)!['type'], 'reveal');
      h.handleItemUse('H', 'i1');
      expect(c.last(RoomMsg.jam)!['by'], 'H');
      expect(c.last(RoomMsg.jam)!['endsAt'], c.now + jamDurationS);
      // one cancellation for the single active seeker effect
      expect(c.count(RoomMsg.effectCancelled), 1);
      expect(c.last(RoomMsg.effectCancelled)!['itemId'], 'i0');
      expect(c.last(RoomMsg.effectCancelled)!['reason'], EffectReason.jammed);
      // no refund: reveal stays consumed
      h.handleItemUse('S', 'i0', target: 'H');
      expect(c.last(RoomMsg.effectRejected)!['reason'], EffectReason.alreadyUsed);
      // seeker item_use rejected with JAMMED
      c.now += 1;
      h.handleItemUse('S', 'i2');
      expect(c.last(RoomMsg.effectRejected)!['reason'], EffectReason.jammed);
      // seeker-bound publishes suppressed for the jam window
      c.now += 2;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(40), lng: cLng, ts: c.now));
      expect(c.targetedCount(), tBefore + 1); // only the reveal-time push
      // jam over -> streaming resumes
      c.now += jamDurationS + 1;
      h.ingestLocation('S', LocationData(lat: latM(40), lng: cLng, ts: c.now));
      expect(c.targetedCount(), tBefore + 2);
    });
  });

  group('trapwire', () {
    test('auto-armed at hunt start at owner position; trip freezes seeker '
        '30 s + notifies hider; single trigger; use -> ALREADY_TRIPPED', () {
      final c = Capture();
      final h = makeRound(
        c,
        items: [it('i0', 'trapwire')],
        headStartSec: 120,
      );
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      h.handleItemHit('H', 'i0'); // banked during head_start
      expect(h.bankOf('H'), ['i0']);
      c.now += 121;
      h.enterHunt(); // arms at the owner's last position
      // use request on an armed wire -> ALREADY_TRIPPED
      h.handleItemUse('H', 'i0');
      expect(
        c.last(RoomMsg.effectRejected)!['reason'],
        EffectReason.alreadyTripped,
      );
      // seeker crossing: freeze + hider notification
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(4), lng: cLng, ts: c.now));
      final fz = c.last(RoomMsg.freeze)!;
      expect(fz['seeker'], 'S');
      expect(fz['by'], 'H');
      expect(fz['reason'], 'trapwire');
      expect(fz['endsAt'], c.now + trapwireFreezeS);
      expect(h.isFrozen('S'), isTrue);
      // second crossing while frozen -> nothing (single trigger)
      c.now += 1;
      h.ingestLocation('S', LocationData(lat: latM(6), lng: cLng, ts: c.now));
      expect(c.count(RoomMsg.freeze), 1);
      // after the freeze ends the wire is spent: crossing -> no new freeze
      c.now += trapwireFreezeS + 1;
      h.ingestLocation('S', LocationData(lat: latM(4), lng: cLng, ts: c.now));
      expect(c.count(RoomMsg.freeze), 1);
      h.handleItemUse('H', 'i0');
      expect(
        c.last(RoomMsg.effectRejected)!['reason'],
        EffectReason.alreadyTripped,
      );
    });
  });

  group('decoy + found_clue + trail buffers', () {
    test('decoy spawns <= 50 m, replays host trail buffer, expires at 120 s', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'decoy', m: 40)]);
      for (var i = 0; i < 5; i++) {
        c.now += 1;
        h.ingestLocation(
          'H',
          LocationData(lat: latM(i * 10), lng: cLng, ts: c.now),
        );
      }
      h.handleItemHit('H', 'i0');
      expect(h.bankOf('H'), ['i0']);
      h.handleItemUse('H', 'i0');
      final eff = c.last(RoomMsg.effectStarted)!;
      expect(eff['type'], 'decoy');
      final center = (eff['center'] as List).cast<num>();
      final d = distanceMeters(
        center[0].toDouble(),
        center[1].toDouble(),
        latM(40),
        cLng,
      );
      expect(d, lessThanOrEqualTo(decoyRadiusM + 1));
      expect(eff['endsAt'], c.now + decoyLifetimeS);
      final replay = (eff['replay'] as List).cast<List>();
      expect(replay.length, greaterThanOrEqualTo(2));
      // replay starts at the spawn anchor (offset hider trail)
      final dFirst = distanceMeters(
        (replay.first[0] as num).toDouble(),
        (replay.first[1] as num).toDouble(),
        center[0].toDouble(),
        center[1].toDouble(),
      );
      expect(dFirst, lessThan(1.0));
    });

    test('found_clue reads the 60 s old pin from the host trail buffer; '
        'retention >= 180 s', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'found_clue')]);
      final t0 = c.now;
      for (var i = 0; i <= 120; i += 10) {
        c.now = t0 + i;
        h.ingestLocation(
          'H',
          LocationData(lat: latM(i.toDouble()), lng: cLng, ts: c.now),
        );
      }
      give(c, h, 'S', 'i0', m: 0);
      expect(h.bankOf('S'), ['i0']);
      h.handleItemUse('S', 'i0', target: 'H');
      final eff = c.last(RoomMsg.effectStarted)!;
      expect(eff['type'], 'found_clue');
      final pin = (eff['center'] as List).cast<num>();
      // nearest buffer point to (now - 60): t0+60 -> latM(60)
      expect(pin[0], closeTo(latM(60), 1e-6));
      // retention: the t0 point survives to t0+175, is gone past t0+180
      final pts = h.trail.points('H', olderThanTs: t0 + 5);
      expect(pts.any((p) => (p[2] - t0).abs() < 1), isTrue);
      c.now = t0 + 181;
      h.ingestLocation('H', LocationData(lat: latM(999), lng: cLng, ts: c.now));
      final pts2 = h.trail.points('H', olderThanTs: t0 + 5);
      expect(pts2.any((p) => (p[2] - t0).abs() < 1), isFalse);
    });
  });

  group('caught clears banks', () {
    test('item_bank_cleared published; bank vanishes; wires removed; ends '
        'round when last hider', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'trapwire'), it('i1', 'decoy')]);
      c.now += 1;
      h.ingestLocation('H', LocationData(lat: latM(0), lng: cLng, ts: c.now));
      h.handleItemHit('H', 'i0');
      h.handleItemHit('H', 'i1');
      h.enterHunt();
      expect(h.bankOf('H'), containsAll(['i0', 'i1']));
      final end = h.handleCaught('H');
      expect(end, isTrue);
      expect(c.last(RoomMsg.itemBankCleared)!['by'], 'H');
      expect(h.bankOf('H'), isEmpty);
      expect(h.wires, isEmpty);
    });
  });

  group('role + target validation', () {
    test('wrong-role use -> WRONG_ROLE', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'reveal'), it('i1', 'decoy')]);
      give(c, h, 'H', 'i0'); // mixed pool: hider grabs a seeker item
      give(c, h, 'S', 'i1');
      h.handleItemUse('H', 'i0', target: 'H');
      expect(c.last(RoomMsg.effectRejected)!['reason'], EffectReason.wrongRole);
      h.handleItemUse('S', 'i1');
      expect(c.last(RoomMsg.effectRejected)!['reason'], EffectReason.wrongRole);
    });

    test('not-in-bank -> NOT_IN_BANK; caught target -> TARGET_INVALID', () {
      final c = Capture();
      final h = makeRound(c, items: [it('i0', 'reveal')]);
      h.handleItemUse('S', 'i0', target: 'H');
      expect(c.last(RoomMsg.effectRejected)!['reason'], EffectReason.notInBank);
      give(c, h, 'S', 'i0');
      h.handleCaught('H');
      h.handleItemUse('S', 'i0', target: 'H');
      expect(
        c.last(RoomMsg.effectRejected)!['reason'],
        EffectReason.targetInvalid,
      );
    });
  });

  group('pool roll', () {
    test('density count sizes the pool; types come from the catalog; '
        'placements kept, extras scattered', () {
      final c = Capture();
      final h = c.host();
      final rolled = h.prepareItems(
        placed: [it('p0', 'item', m: 5)],
        density: 'more',
        centerLat: cLat,
        centerLng: cLng,
        radiusM: 100,
      );
      expect(rolled.length, densityCount('more'));
      expect(rolled.first.lat, latM(5)); // placements kept in order
      for (final r in rolled) {
        expect(rollableIds, contains(r.type));
        expect(r.id, startsWith('i'));
      }
      expect(densityCount('less'), 4);
      expect(densityCount('normal'), 6);
      final pass = h.prepareItems(
        placed: [it('p0', 'item', m: 5)],
        density: '', // pre-v1 flow: untouched
        centerLat: cLat,
        centerLng: cLng,
        radiusM: 100,
      );
      expect(pass.length, 1);
      expect(pass.first.type, 'item');
    });
  });
}
