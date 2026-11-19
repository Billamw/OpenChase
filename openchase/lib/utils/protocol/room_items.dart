import 'dart:math';

import 'package:openchase/utils/protocol/room_models.dart';

/// Rules constants for items v1 (docs/items_v1.json is the design source;
/// ids here must stay identical to lib/item_catalog.dart).

class ItemIds {
  static const reveal = 'reveal';
  static const decoy = 'decoy';
  static const drone = 'drone';
  static const foundClue = 'found_clue';
  static const radarPulse = 'radar_pulse';
  static const trapwire = 'trapwire';
  static const clockPlus = 'clock_plus';
  static const clockMinus = 'clock_minus';
  static const proofOfLife = 'proof_of_life';
  static const disturber = 'disturber';
  static const walkyTalky = 'walky_talky';
}

/// 'seeker' | 'hider' | 'both' — role-lock is enforced at use time.
const Map<String, String> itemRole = {
  ItemIds.reveal: 'seeker',
  ItemIds.decoy: 'hider',
  ItemIds.drone: 'seeker',
  ItemIds.foundClue: 'seeker',
  ItemIds.radarPulse: 'seeker',
  ItemIds.trapwire: 'hider',
  ItemIds.clockPlus: 'hider',
  ItemIds.clockMinus: 'seeker',
  ItemIds.proofOfLife: 'seeker',
  ItemIds.disturber: 'hider',
  ItemIds.walkyTalky: 'both',
};

const Map<String, String> itemRarity = {
  ItemIds.reveal: 'rare',
  ItemIds.decoy: 'uncommon',
  ItemIds.drone: 'rare',
  ItemIds.foundClue: 'common',
  ItemIds.radarPulse: 'common',
  ItemIds.trapwire: 'rare',
  ItemIds.clockPlus: 'uncommon',
  ItemIds.clockMinus: 'uncommon',
  ItemIds.proofOfLife: 'common',
  ItemIds.disturber: 'rare',
  ItemIds.walkyTalky: 'uncommon',
};

/// Anti-stack: these share one active info-effect slot per seeker.
const Set<String> seekerInfoSlot = {
  ItemIds.reveal,
  ItemIds.drone,
  ItemIds.foundClue,
  ItemIds.radarPulse,
  ItemIds.proofOfLife,
};

/// Auto-armed at hunt start for every banked copy; a use request for them
/// is rejected (ALREADY_USED / ALREADY_TRIPPED).
const Set<String> autoArmedItems = {ItemIds.trapwire};

/// Effect/args constants from docs/items_v1.json.
const revealDurationS = 30;
const droneDurationS = 60;
const droneRadiusM = 75.0;
const decoyRadiusM = 50.0;
const decoyLifetimeS = 120;
const decoyReplayWindowS = 180;
const trapwireRadiusM = 8.0;
const trapwireFreezeS = 30;
const jamDurationS = 30;
const clockPlusDeltaS = 180;
const clockMinusDeltaS = -120;
const clockHuntFloorS = 60; // clock_minus clamps endsAt to now + this
const clueAgeS = 60; // found_clue pin age
const proofOfLifeRadiusM = 150.0;

/// Pickup + host validation (auto-grab within 15 m, decisions.pickup).
const pickupRadiusM = 15.0;
const claimStaleSec = 5; // reject claims against positions older than this
const claimDistSlackM = 15.0; // + GPS accuracy allowance

/// Head-start zone soft-lock (decisions.zone_lock: forgiving).
const zoneGraceM = 15.0;
const zoneSoftlockPings = 2; // consecutive out-of-zone pings

/// Hunt eyes-radius (decisions.hunt_visibility) with hysteresis:
/// acquire at <=50 m, keep publishing while <=55 m, re-acquire only <=45 m.
const eyesAcquireM = 50.0;
const eyesHoldM = 55.0;
const eyesReacquireM = 45.0;

/// Host trail-buffer retention (decoy replay + found_clue need >=180 s).
const trailRetentionSec = 180;

/// Density name -> item count (docs/settings.density_options).
int densityCount(String density) => switch (density) {
  'less' => 4,
  'more' => 9,
  _ => 6,
};

/// All catalog ids that may appear in a rolled pool. walky_talky is in the
/// catalog but the voice server is deferred, so it is not rolled.
const List<String> rollableIds = [
  ItemIds.reveal,
  ItemIds.decoy,
  ItemIds.drone,
  ItemIds.foundClue,
  ItemIds.radarPulse,
  ItemIds.trapwire,
  ItemIds.clockPlus,
  ItemIds.clockMinus,
  ItemIds.proofOfLife,
  ItemIds.disturber,
];

/// One type per placed position, rarity weights 60/30/10 (common/uncommon/rare).
List<String> rollItemTypes(int count, Random rnd) {
  final byRarity = <String, List<String>>{};
  for (final id in rollableIds) {
    byRarity.putIfAbsent(itemRarity[id]!, () => []).add(id);
  }
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    final roll = rnd.nextInt(100);
    final rarity = roll < 60
        ? 'common'
        : roll < 90
        ? 'uncommon'
        : 'rare';
    final pool = byRarity[rarity]!;
    out.add(pool[rnd.nextInt(pool.length)]);
  }
  return out;
}

/// Scatter [count] fresh positions uniformly inside the play area (used when
/// placement provides fewer positions than the density count).
List<ItemData> scatterPositions(
  double centerLat,
  double centerLng,
  int radiusM,
  int count,
  Random rnd,
  String idPrefix,
) {
  final out = <ItemData>[];
  final rDeg = radiusM / 111200.0;
  for (var i = 0; i < count; i++) {
    final lat = centerLat + (rnd.nextDouble() * 2 - 1) * rDeg;
    final lng = centerLng + (rnd.nextDouble() * 2 - 1) * rDeg;
    out.add(ItemData(id: '$idPrefix$i', type: 'item', lat: lat, lng: lng));
  }
  return out;
}

/// Host-side per-player position history with >=180 s retention. Feeds
/// decoy replay and found_clue. Independent of the fan-out visibility
/// policy — the host always keeps its own stream.
class TrailBuffer {
  final int retentionSec;
  final int maxPoints;
  final Map<String, List<List<double>>> _byPlayer = {};

  TrailBuffer({this.retentionSec = trailRetentionSec, this.maxPoints = 600});

  void add(String pk, double lat, double lng, int ts) {
    final list = _byPlayer.putIfAbsent(pk, () => []);
    if (list.isNotEmpty &&
        list.last[0] == lat &&
        list.last[1] == lng &&
        list.last[2] >= ts) {
      return;
    }
    list.add([lat, lng, ts.toDouble()]);
    _prune(list, ts);
  }

  void _prune(List<List<double>> list, int nowTs) {
    final cutoff = nowTs - retentionSec;
    var drop = 0;
    while (drop < list.length && list[drop][2] < cutoff) {
      drop++;
    }
    if (drop > 0) list.removeRange(0, drop);
    if (list.length > maxPoints) {
      list.removeRange(0, list.length - maxPoints);
    }
  }

  /// Snapshot [lat, lng, ts] points; only events at/older than [olderThanTs].
  List<List<double>> points(String pk, {int? olderThanTs}) {
    final list = _byPlayer[pk];
    if (list == null) return const [];
    if (olderThanTs == null) return List.of(list.map(List<double>.of));
    return [
      for (final p in list)
        if (p[2] <= olderThanTs) List<double>.of(p),
    ];
  }

  /// Point nearest to targetTs, or null when the buffer is empty.
  List<double>? pointAt(String pk, int targetTs) {
    final list = _byPlayer[pk];
    if (list == null || list.isEmpty) return null;
    var best = list.first;
    var bestGap = (best[2] - targetTs).abs();
    for (final p in list) {
      final gap = (p[2] - targetTs).abs();
      if (gap < bestGap) {
        best = p;
        bestGap = gap;
      }
    }
    return List<double>.of(best);
  }

  /// Downsampled replay samples [lat, lng, ageSec] (oldest first), relative
  /// to [nowTs]. Used for the decoy fake-hider replay; capped at ~30 samples.
  List<List<double>> replay(String pk, int nowTs, {int windowSec = decoyReplayWindowS}) {
    final list = _byPlayer[pk];
    if (list == null) return const [];
    final cutoff = nowTs - windowSec;
    final src = [for (final p in list) if (p[2] >= cutoff) p];
    if (src.isEmpty) return const [];
    final stride = max(1, (src.length / 30).ceil());
    final out = <List<double>>[];
    for (var i = 0; i < src.length; i += stride) {
      final p = src[i];
      out.add([p[0], p[1], (nowTs - p[2].round()).toDouble()]);
    }
    final lp = src.last;
    if (out.last[0] != lp[0] || out.last[1] != lp[1]) {
      out.add([lp[0], lp[1], (nowTs - lp[2].round()).toDouble()]);
    }
    return out;
  }

  void clear() => _byPlayer.clear();
}

/// Great-circle bearing in degrees (0 = north, clockwise) from a to b.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * pi / 180.0;
  final y = sin(rad(lng2 - lng1)) * cos(rad(lat2));
  final x =
      cos(rad(lat1)) * sin(rad(lat2)) -
      sin(rad(lat1)) * cos(rad(lat2)) * cos(rad(lng2 - lng1));
  return (atan2(y, x) * 180 / pi + 360) % 360;
}
