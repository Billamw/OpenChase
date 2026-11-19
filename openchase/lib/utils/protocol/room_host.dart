import 'dart:math';

import 'package:openchase/utils/protocol/room_items.dart';
import 'package:openchase/utils/protocol/room_models.dart';

/// Items v1 host authority for one round. Pure Dart state machine: every
/// decision comes out as a publish (room-channel payload and/or targeted
/// per-seeker payload), no networking inside — RoomClient wires it to the
/// relay. Clock is injected so tests can run time deterministically.
class RoomHost {
  /// Room-channel publish (kind 20001 content, signed by the room key).
  final void Function(Map<String, dynamic> payload) publishRoom;

  /// Targeted publish to one seeker (kind 20005 signed by the host *player*
  /// session key, content encrypted by RoomClient before calling out).
  final void Function(String seekerPk, Map<String, dynamic> payload)
  publishTargeted;

  final int Function() now;
  final Random rnd;

  RoomHost({
    required this.publishRoom,
    required this.publishTargeted,
    required this.now,
    Random? rng,
  }) : rnd = rng ?? Random.secure();

  RoundStartData? round;
  final Set<String> hiders = {};
  final Set<String> caught = {};
  final Set<String> roster = {}; // round participants (session pubkeys)

  final Map<String, List<String>> banks = {}; // pk -> banked itemIds
  final Set<String> usedItems = {}; // consumed by an accepted use
  final Set<String> droppedItems = {}; // vanished (caught hider)
  final Map<String, ItemEffect> effects = {}; // itemId -> active effect
  final Map<String, String> infoSlot = {}; // seeker pk -> active info itemId
  final Map<String, int> seekerFreezes = {}; // seeker pk -> freeze endsAt
  final Map<String, TrapWire> wires = {}; // wireId -> armed wire
  int jamEndsAt = 0;
  int endsAt = 0;
  String phase = RoundPhase.lobby;
  int headStartEndsAt = 0;
  bool anchorRevealed = false;

  final TrailBuffer trail = TrailBuffer();
  final Map<String, LocationData> lastPos = {};
  // Eyes hysteresis: "hider|seeker" -> streaming.
  final Map<String, bool> eyes = {};
  // Soft-lock bookkeeping (head start zone): seeker -> consecutive misses.
  final Map<String, int> zoneMisses = {};
  final Set<String> softlocked = {};

  String hostPlayerPk = '';

  Map<String, ItemData> get _itemsById => {
    for (final it in round?.items ?? const <ItemData>[]) it.id: it,
  };

  List<String> _seekers() =>
      roster.difference(hiders).toList(growable: false)..sort();
  List<String> _uncaughtHiders() =>
      hiders.difference(caught).toList(growable: false)..sort();

  bool get _live => round != null && phase != RoundPhase.roundOver;

  bool get _jammed => now() < jamEndsAt;
  // ── round lifecycle ────────────────────────────────────────────────────

  /// Fresh pool: density count + rarity roll over the given positions.
  /// When no density is configured (pre-v1 flow), placements pass through
  /// untouched for backward compatibility.
  List<ItemData> prepareItems({
    required List<ItemData> placed,
    required String density,
    required double centerLat,
    required double centerLng,
    required int radiusM,
  }) {
    if (density.isEmpty) return placed;
    final count = densityCount(density);
    final positions = <ItemData>[
      ...placed.take(count),
      ...scatterPositions(centerLat, centerLng, radiusM, count - placed.length, rnd, 'x'),
    ];
    final types = rollItemTypes(count, rnd);
    return [
      for (var i = 0; i < positions.length; i++)
        ItemData(
          id: 'i$i',
          type: types[i],
          lat: positions[i].lat,
          lng: positions[i].lng,
        ),
    ];
  }

  void onRoundStart(RoundStartData r) {
    round = r;
    endsAt = r.endsAt;
    headStartEndsAt = r.headStartEndsAt;
    hiders
      ..clear()
      ..addAll(r.hiders);
    caught.clear();
    roster.addAll(r.hiders); // participants are registered before the round;
    // hiders are participants too
    banks.clear();
    usedItems.clear();
    droppedItems.clear();
    effects.clear();
    infoSlot.clear();
    seekerFreezes.clear();
    wires.clear();
    eyes.clear();
    zoneMisses.clear();
    softlocked.clear();
    trail.clear();
    lastPos.clear();
    jamEndsAt = 0;
    anchorRevealed = false;
    if (headStartEndsAt > now()) {
      phase = RoundPhase.headStart;
      publishRoom({
        'msg': RoomMsg.phaseChanged,
        'roundId': r.roundId,
        'phase': phase,
        'at': now(),
      });
    } else {
      enterHunt();
    }
  }

  void addParticipant(String pk) => roster.add(pk);

  /// Host timer fired at headStartEndsAt (idempotent; also used directly
  /// when the round starts without a head start).
  void enterHunt() {
    if (round == null || phase == RoundPhase.hunt || phase == RoundPhase.roundOver) {
      return;
    }
    phase = RoundPhase.hunt;
    publishRoom({
      'msg': RoomMsg.phaseChanged,
      'roundId': round!.roundId,
      'phase': phase,
      'at': now(),
    });
    _anchorReveal();
    _armBankedTrapwires();
  }

  void _anchorReveal() {
    if (anchorRevealed || round == null) return;
    anchorRevealed = true;
    final positions = <List<Object>>[];
    for (final pk in _uncaughtHiders()) {
      final p = lastPos[pk];
      if (p == null) continue;
      positions.add([pk, p.lat, p.lng]);
    }
    publishRoom({
      'msg': RoomMsg.anchorReveal,
      'roundId': round!.roundId,
      'at': now(),
      'positions': positions,
    });
  }

  /// decisions.trapwire: auto-arm at hunt start at the owner's last position.
  void _armBankedTrapwires() {
    if (round == null) return;
    final items = _itemsById;
    var n = 0;
    banks.forEach((pk, bank) {
      for (final itemId in bank) {
        final it = items[itemId];
        if (it == null || it.type != ItemIds.trapwire) continue;
        if (usedItems.contains(itemId) || droppedItems.contains(itemId)) {
          continue;
        }
        final p = lastPos[pk];
        if (p == null) continue;
        wires['w${n++}'] = TrapWire(
          id: 'w${n - 1}',
          owner: pk,
          itemId: itemId,
          lat: p.lat,
          lng: p.lng,
        );
      }
    });
  }

  // ── location stream ────────────────────────────────────────────────────

  void ingestLocation(String pk, LocationData loc) {
    if (round == null) return;
    lastPos[pk] = loc;
    if (!_live) return;
    final isHider = hiders.contains(pk);
    if (phase == RoundPhase.headStart && !isHider) {
      _zoneCheck(pk, loc);
    }
    if (phase != RoundPhase.hunt) {
      trail.add(pk, loc.lat, loc.lng, loc.ts);
      return;
    }
    _reapEffects();
    if (isHider) {
      trail.add(pk, loc.lat, loc.lng, loc.ts);
      _eyesBroadcastFor(pk);
    } else {
      // frozen / soft-locked seekers: suppressed for trails and effects
      // (honor stand-still; no server teleport).
      if (seekerFreezes.containsKey(pk) && now() < seekerFreezes[pk]!) return;
      if (softlocked.contains(pk)) return;
      trail.add(pk, loc.lat, loc.lng, loc.ts);
      _eyesEvaluateFromSeeker(pk);
      _trapwireCheck(pk, loc);
    }
  }

  void _zoneCheck(String pk, LocationData loc) {
    final r = round!;
    final out =
        distanceMeters(loc.lat, loc.lng, r.centerLat, r.centerLng) >
        r.radiusM + zoneGraceM;
    if (out) {
      final misses = (zoneMisses[pk] ?? 0) + 1;
      zoneMisses[pk] = misses;
      if (misses >= zoneSoftlockPings && !softlocked.contains(pk)) {
        softlocked.add(pk);
        publishRoom({
          'msg': RoomMsg.zoneSoftlock,
          'roundId': r.roundId,
          'seeker': pk,
          'at': now(),
        });
      }
    } else {
      zoneMisses[pk] = 0;
      if (softlocked.remove(pk)) {
        publishRoom({
          'msg': RoomMsg.zoneSoftlock,
          'roundId': r.roundId,
          'seeker': pk,
          'at': now(),
          'released': true,
        });
      }
    }
  }

  /// Evaluate eyes pairs using the seeker's fresh position, then push each
  /// entitled hider's current position to this seeker.
  void _eyesEvaluateFromSeeker(String seeker) {
    final sl = lastPos[seeker];
    if (sl == null) return;
    for (final h in _uncaughtHiders()) {
      final hl = lastPos[h];
      if (hl == null) continue;
      final dist = distanceMeters(hl.lat, hl.lng, sl.lat, sl.lng);
      _eyesTransition(h, seeker, dist);
      if (eyes[_eyeKey(h, seeker)] == true && !_jammed) {
        _publishHiderTo(h, seeker, hl);
      }
    }
  }

  bool _eyesTransition(String hider, String seeker, double dist) {
    final key = _eyeKey(hider, seeker);
    final st = eyes[key];
    if (st == true) {
      if (dist > eyesHoldM) {
        eyes[key] = false; // actively dropped: re-acquire needs <= 45 m
        return false;
      }
      return true; // keep streaming inside the hold band
    }
    final acq = st == null ? eyesAcquireM : eyesReacquireM;
    if (dist <= acq) {
      eyes[key] = true;
      return true;
    }
    return false;
  }

  String _eyeKey(String hider, String seeker) => '$hider|$seeker';

  void _eyesBroadcastFor(String hider) {
    final hl = lastPos[hider];
    if (hl == null || caught.contains(hider)) return;
    for (final s in _seekers()) {
      if (_jammed) continue; // jam: seekers get no map-relevant publishes
      if (seekerFreezes.containsKey(s) && now() < seekerFreezes[s]!) continue;
      final reveal = effects.values.any(
        (ef) =>
            ef.type == ItemIds.reveal &&
            ef.seeker == s &&
            ef.target == hider &&
            ef.endsAt > now(),
      );
      final drone = effects.values.any(
        (ef) =>
            ef.type == ItemIds.drone &&
            ef.seeker == s &&
            ef.endsAt > now() &&
            ef.center != null &&
            distanceMeters(hl.lat, hl.lng, ef.center![0], ef.center![1]) <=
                droneRadiusM,
      );
      final streaming = eyes[_eyeKey(hider, s)] == true;
      if (streaming || reveal || drone) _publishHiderTo(hider, s, hl);
    }
  }

  void _publishHiderTo(String hider, String seeker, LocationData hl) {
    publishTargeted(seeker, {
      'hider': hider,
      'lat': hl.lat,
      'lng': hl.lng,
      'acc': hl.accuracy,
      'ts': hl.ts,
      'roundId': round?.roundId ?? '',
      'trail': trail.points(hider).map((p) => [p[0], p[1]]).toList(),
    });
  }

  void _trapwireCheck(String seeker, LocationData loc) {
    for (final w in wires.values) {
      if (w.tripped) continue;
      if (distanceMeters(loc.lat, loc.lng, w.lat, w.lng) > trapwireRadiusM) {
        continue;
      }
      w.tripped = true;
      final ends = now() + trapwireFreezeS;
      seekerFreezes[seeker] = ends;
      publishRoom({
        'msg': RoomMsg.freeze,
        'roundId': round!.roundId,
        'seeker': seeker,
        'by': w.owner,
        'reason': 'trapwire',
        'endsAt': ends,
        'at': now(),
      });
    }
  }

  void _reapEffects() {
    final t = now();
    final expired = effects.entries
        .where((e) => e.value.endsAt <= t)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      final ef = effects.remove(id)!;
      if (infoSlot[ef.seeker] == id) infoSlot.remove(ef.seeker);
    }
  }

  // ── pickup claims ──────────────────────────────────────────────────────

  void handleItemHit(String pk, String itemId) {
    if (!_live) return;
    final item = _itemsById[itemId];
    if (item == null) return;
    if (banks.values.any((b) => b.contains(itemId))) return; // claimed
    if (roster.isNotEmpty && !roster.contains(pk)) return;
    final loc = lastPos[pk];
    if (loc == null) return;
    if (now() - loc.ts > claimStaleSec) return; // stale position
    final slack =
        pickupRadiusM + claimDistSlackM + (loc.accuracy ?? 0);
    if (distanceMeters(loc.lat, loc.lng, item.lat, item.lng) > slack) {
      return; // out of range
    }
    final bank = banks.putIfAbsent(pk, () => []);
    final cap = round?.bankCap ?? 3;
    if (bank.length >= cap) {
      publishRoom({
        'msg': RoomMsg.itemRejected,
        'roundId': round!.roundId,
        'itemId': itemId,
        'reason': EffectReason.bankFull,
        'to': pk,
        'at': now(),
      });
      return;
    }
    bank.add(itemId);
    publishRoom({
      'msg': RoomMsg.itemCollected,
      'roundId': round!.roundId,
      'itemId': itemId,
      'by': pk,
      'at': now(),
    });
  }

  // ── item use requests ──────────────────────────────────────────────────

  void handleItemUse(
    String pk,
    String itemId, {
    String? target,
    List<double>? center,
  }) {
    if (round == null || !roster.contains(pk)) return;
    void reject(String reason) => publishRoom({
      'msg': RoomMsg.effectRejected,
      'roundId': round!.roundId,
      'itemId': itemId,
      'reason': reason,
      'to': pk,
      'at': now(),
    });

    final item = _itemsById[itemId];
    if (item == null ||
        banks[pk] == null ||
        !banks[pk]!.contains(itemId)) {
      reject(EffectReason.notInBank);
      return;
    }
    if (usedItems.contains(itemId)) {
      reject(EffectReason.alreadyUsed);
      return;
    }
    if (phase != RoundPhase.hunt) {
      reject(EffectReason.notHuntPhase);
      return;
    }
    if (_jammed && !hiders.contains(pk)) {
      reject(EffectReason.jammed);
      return;
    }
    final role = itemRole[item.type] ?? 'both';
    final isHider = hiders.contains(pk);
    if (item.type == ItemIds.walkyTalky) {
      reject(EffectReason.alreadyUsed); // voice server deferred: no effect
      return;
    }
    if (role == 'seeker' && isHider) {
      reject(EffectReason.wrongRole);
      return;
    }
    if (role == 'hider' && !isHider) {
      reject(EffectReason.wrongRole);
      return;
    }
    if (item.type == ItemIds.trapwire) {
      reject(
        wires.values.any((w) => w.itemId == itemId && w.owner == pk)
            ? EffectReason.alreadyTripped
            : EffectReason.alreadyUsed,
      );
      return;
    }
    if (!isHider && seekerInfoSlot.contains(item.type)) {
      final held = infoSlot[pk];
      if (held != null && (effects[held]?.endsAt ?? 0) > now()) {
        reject(EffectReason.alreadyActive);
        return;
      }
    }

    final at = now();
    final rid = round!.roundId;
    switch (item.type) {
      case ItemIds.reveal:
        if (target == null ||
            !hiders.contains(target) ||
            caught.contains(target) ||
            target == pk) {
          reject(EffectReason.targetInvalid);
          return;
        }
        final ends = at + revealDurationS;
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk,
          target: target,
          endsAt: ends,
          at: at,
        );
        infoSlot[pk] = itemId;
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'target': target,
          'endsAt': ends,
          'at': at,
          'to': pk,
        });
        publishRoom({
          'msg': RoomMsg.revealNotice,
          'roundId': rid,
          'by': pk,
          'target': target,
          'at': at,
        });
        // immediate first pin for the seeker
        final hl = lastPos[target];
        if (hl != null && !_jammed) _publishHiderTo(target, pk, hl);
      case ItemIds.foundClue:
        if (target == null ||
            !hiders.contains(target) ||
            caught.contains(target) ||
            target == pk) {
          reject(EffectReason.targetInvalid);
          return;
        }
        final pin = trail.pointAt(target, at - clueAgeS);
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk,
          target: target,
          endsAt: at,
          center: pin == null ? null : [pin[0], pin[1]],
          at: at,
        );
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'target': target,
          'center': pin == null ? null : [pin[0], pin[1]],
          'pinAgeS': pin == null ? null : (at - pin[2].round()),
          'endsAt': at,
          'at': at,
          'to': pk,
        });
      case ItemIds.radarPulse:
        final near = _nearestUncaughtHider(pk);
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk,
          endsAt: at,
          at: at,
        );
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'found': near != null,
          'bearing': near?.bearing,
          'distanceM': near?.distanceM.round(),
          'endsAt': at,
          'at': at,
          'to': pk,
        });
      case ItemIds.proofOfLife:
        final found = _anyUncaughtHiderWithin(pk, proofOfLifeRadiusM);
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk,
          endsAt: at,
          at: at,
        );
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'found': found,
          'endsAt': at,
          'at': at,
          'to': pk,
        });
      case ItemIds.drone:
        if (center == null || center.length != 2) {
          reject(EffectReason.targetInvalid);
          return;
        }
        final ends = at + droneDurationS;
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk,
          center: [center[0], center[1]],
          endsAt: ends,
          at: at,
        );
        infoSlot[pk] = itemId;
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'center': [center[0], center[1]],
          'radiusM': droneRadiusM,
          'endsAt': ends,
          'at': at,
          'to': pk,
        });
        _eyesBroadcastForAllInsideZone(center[0], center[1], pk);
      case ItemIds.decoy:
        final self = lastPos[pk];
        if (self == null) {
          reject(EffectReason.targetInvalid);
          return;
        }
        final samples = trail.replay(pk, at);
        if (samples.isEmpty) {
          samples.add([self.lat, self.lng, 0]);
        }
        // Spawn point: random offset <= decoyRadiusM from the hider; the
        // replay rides from that anchor so the fake marker "walks" the
        // hider's recent trail.
        final ang = rnd.nextDouble() * 2 * pi;
        final rr = decoyRadiusM * (0.5 + rnd.nextDouble() * 0.5);
        final dDeg = rr / 111200.0;
        final spawn = [
          self.lat + sin(ang) * dDeg,
          self.lng + cos(ang) * dDeg,
        ];
        final first = samples.first;
        final replay = [
          for (final s in samples) [
            s[0] - first[0] + spawn[0],
            s[1] - first[1] + spawn[1],
            s[2],
          ],
        ];
        final ends = at + decoyLifetimeS;
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk, // owner is the hider; seeker field = owner here
          center: spawn,
          endsAt: ends,
          at: at,
        );
        publishRoom({
          'msg': RoomMsg.effectStarted,
          'roundId': rid,
          'itemId': itemId,
          'type': item.type,
          'by': pk,
          'center': spawn,
          'replay': replay,
          'endsAt': ends,
          'at': at,
        });
      case ItemIds.disturber:
        final ends = at + jamDurationS;
        jamEndsAt = ends;
        effects[itemId] = ItemEffect(
          itemId: itemId,
          type: item.type,
          seeker: pk, // owner (hider)
          endsAt: ends,
          at: at,
        );
        publishRoom({
          'msg': RoomMsg.jam,
          'roundId': rid,
          'by': pk,
          'endsAt': ends,
          'at': at,
        });
        // Cancel every active seeker info-effect; spent items are not
        // refunded.
        final doomed = effects.entries
            .where(
              (e) =>
                  e.key != itemId &&
                  seekerInfoSlot.contains(e.value.type) &&
                  e.value.endsAt > at,
            )
            .toList();
        for (final e in doomed) {
          effects.remove(e.key);
          if (infoSlot[e.value.seeker] == e.key) {
            infoSlot.remove(e.value.seeker);
          }
          publishRoom({
            'msg': RoomMsg.effectCancelled,
            'roundId': rid,
            'itemId': e.key,
            'reason': EffectReason.jammed,
            'at': at,
          });
        }
      case ItemIds.clockPlus:
        endsAt += clockPlusDeltaS;
        publishRoom({
          'msg': RoomMsg.roundTimer,
          'roundId': rid,
          'endsAt': endsAt,
          'at': at,
        });
      case ItemIds.clockMinus:
        final floor = at + clockHuntFloorS;
        final target0 = endsAt + clockMinusDeltaS;
        endsAt = target0 < floor ? floor : target0;
        publishRoom({
          'msg': RoomMsg.roundTimer,
          'roundId': rid,
          'endsAt': endsAt,
          'at': at,
        });
    }
    usedItems.add(itemId);
  }

  void _eyesBroadcastForAllInsideZone(double lat, double lng, String seeker) {
    for (final h in _uncaughtHiders()) {
      final hl = lastPos[h];
      if (hl == null) continue;
      if (distanceMeters(hl.lat, hl.lng, lat, lng) <= droneRadiusM) {
        _publishHiderTo(h, seeker, hl);
      }
    }
  }

  ({double bearing, double distanceM})? _nearestUncaughtHider(String seeker) {
    final s = lastPos[seeker];
    if (s == null) return null;
    double bestD = double.infinity;
    double bestB = 0;
    for (final h in _uncaughtHiders()) {
      final hl = lastPos[h];
      if (hl == null) continue;
      final d = distanceMeters(s.lat, s.lng, hl.lat, hl.lng);
      if (d < bestD) {
        bestD = d;
        bestB = bearingDegrees(s.lat, s.lng, hl.lat, hl.lng);
      }
    }
    if (bestD == double.infinity) return null;
    return (bearing: bestB, distanceM: bestD);
  }

  bool _anyUncaughtHiderWithin(String seeker, double radiusM) {
    final s = lastPos[seeker];
    if (s == null) return false;
    for (final h in _uncaughtHiders()) {
      final hl = lastPos[h];
      if (hl == null) continue;
      if (distanceMeters(s.lat, s.lng, hl.lat, hl.lng) <= radiusM) return true;
    }
    return false;
  }

  // ── capture ────────────────────────────────────────────────────────────

  /// Returns true when this catch ends the round (all hiders caught).
  bool handleCaught(String pk) {
    if (round == null) return false;
    caught.add(pk);
    final bank = banks.remove(pk) ?? const <String>[];
    for (final itemId in bank) {
      droppedItems.add(itemId);
    }
    // Hider-owned effects vanish with them.
    final doomed = effects.entries
        .where(
          (e) =>
              (e.value.type == ItemIds.decoy ||
                  e.value.type == ItemIds.trapwire ||
                  e.value.type == ItemIds.disturber) &&
              hiders.contains(e.value.seeker) &&
              e.value.seeker == pk,
        )
        .map((e) => e.key)
        .toList();
    for (final id in doomed) {
      effects.remove(id);
    }
    wires.removeWhere((_, w) => w.owner == pk);
    publishRoom({
      'msg': RoomMsg.itemBankCleared,
      'roundId': round!.roundId,
      'by': pk,
      'at': now(),
    });
    return hiders.isNotEmpty && caught.containsAll(hiders);
  }

  // ── views ──────────────────────────────────────────────────────────────

  List<String> bankOf(String pk) => List.unmodifiable(banks[pk] ?? const []);

  bool isSoftlocked(String pk) => softlocked.contains(pk);
  bool isFrozen(String pk) =>
      seekerFreezes.containsKey(pk) && now() < seekerFreezes[pk]!;
}

class ItemEffect {
  final String itemId;
  final String type;
  final String seeker; // seeker owner, or the hider owner for hider items
  final String? target;
  final List<double>? center;
  final int endsAt;
  final int at;
  ItemEffect({
    required this.itemId,
    required this.type,
    required this.seeker,
    this.target,
    this.center,
    required this.endsAt,
    required this.at,
  });
}

class TrapWire {
  final String id;
  final String owner;
  final String itemId;
  final double lat;
  final double lng;
  bool tripped = false;
  TrapWire({
    required this.id,
    required this.owner,
    required this.itemId,
    required this.lat,
    required this.lng,
  });
}
