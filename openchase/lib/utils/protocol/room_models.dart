import 'dart:convert';
import 'dart:math';

/// Room-protocol event kinds (regular nostr range).
class RoomKinds {
  static const room =
      20001; // authored by room key: announcement / roster / round lifecycle
  static const join = 20002; // authored by player session key: join request
  static const leave = 20003; // authored by player session key
  static const itemHit = 20004; // authored by player session key: pickup claim
  static const location = 20005; // authored by player session key, 1 Hz
  static const caught = 20006; // authored by hider session key: admit capture
}

/// Sub-types carried inside kind `room` content.
class RoomMsg {
  static const roomInit = 'room_init';
  static const roster = 'roster';
  static const roundStart = 'round_start';
  static const roundEnd = 'round_end';
  static const itemCollected = 'item_collected';
  static const hiderCaught = 'hider_caught';
}

/// One parsed room event, relay-agnostic.
class RoomEvent {
  final String id;
  final String pubkey; // author
  final int createdAt;
  final int kind;
  final Map<String, dynamic> data;

  /// True when this event was authored by our room key (host identity).
  bool fromRoomKey = false;

  /// True when authored by our player session key.
  bool fromSelf = false;

  RoomEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.data,
  });

  String get msg => data['msg']?.toString() ?? '';

  /// Parse a raw relay `["EVENT", subId, event]` frame. Event is array-form
  /// `[id, pubkey, created_at, kind, tags, content]` (what relays emit per
  /// NIP-01) or object-form. Returns null for any non-event or non-JSON frame.
  /// Never throws on malformed payloads — such events simply carry an empty
  /// data map.
  static RoomEvent? tryParse(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! List || decoded.length < 3 || decoded[0] != 'EVENT') {
      return null;
    }
    final ev = decoded[2];
    String? id;
    String? pubkey;
    int createdAt = 0;
    int kind = 0;
    dynamic content;
    if (ev is Map) {
      id = ev['id'] as String?;
      pubkey = ev['pubkey'] as String?;
      createdAt = ev['created_at'] is int ? ev['created_at'] as int : 0;
      kind = ev['kind'] is int ? ev['kind'] as int : 0;
      content = ev['content'];
    } else if (ev is List &&
        ev.length >= 6 &&
        ev[0] is String &&
        ev[1] is String &&
        ev[2] is int &&
        ev[3] is int) {
      id = ev[0] as String;
      pubkey = ev[1] as String;
      createdAt = ev[2] as int;
      kind = ev[3] as int;
      content = ev[5];
    }
    if (id == null || pubkey == null) return null;
    Map<String, dynamic> data = const {};
    if (content is String) {
      try {
        final parsed = jsonDecode(content);
        if (parsed is Map<String, dynamic>) data = parsed;
      } catch (_) {
        /* foreign event — keep identity, empty payload */
      }
    }
    return RoomEvent(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      data: data,
    );
  }
}

class PlayerEntry {
  final String pubkey;
  final String name;
  final int
  lastSeen; // unix seconds of last proof-of-life (join/heartbeat/location)

  PlayerEntry(this.pubkey, this.name, this.lastSeen);

  Map<String, dynamic> toJson() => {'pk': pubkey, 'name': name};
}

class LocationData {
  final double lat;
  final double lng;
  final double? accuracy;
  final int ts;

  LocationData({
    required this.lat,
    required this.lng,
    this.accuracy,
    required this.ts,
  });

  static LocationData? from(RoomEvent e) {
    final lat = e.data['lat'], lng = e.data['lng'];
    if (lat is! num || lng is! num) return null;
    return LocationData(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      accuracy: e.data['acc'] is num ? (e.data['acc'] as num).toDouble() : null,
      ts: e.createdAt,
    );
  }
}

class RoundStartData {
  final String roundId;
  final double centerLat;
  final double centerLng;
  final int radiusM;
  final List<ItemData> items;
  final int endsAt; // host wall-clock second when the round expires
  final List<String> hiders; // hider pubkeys for this round

  RoundStartData({
    required this.roundId,
    required this.centerLat,
    required this.centerLng,
    required this.radiusM,
    required this.items,
    this.endsAt = 0,
    this.hiders = const [],
  });

  static RoundStartData? from(RoomEvent e) {
    final center = e.data['center'];
    final radius = e.data['radius'];
    if (center is! List || center.length != 2) return null;
    if (center[0] is! num || center[1] is! num || radius is! num) return null;
    return RoundStartData(
      roundId: e.data['roundId']?.toString() ?? '',
      centerLat: (center[0] as num).toDouble(),
      centerLng: (center[1] as num).toDouble(),
      radiusM: radius.toInt(),
      items: ItemData.parseList(e.data['items']),
      endsAt: e.data['endsAt'] is num ? (e.data['endsAt'] as num).toInt() : 0,
      hiders:
          (e.data['hiders'] is List)
              ? (e.data['hiders'] as List).whereType<String>().toList(
                growable: false,
              )
              : const [],
    );
  }
}

/// One placed item travelling with a round. Canonical wire form is
/// `{id, type, lat, lng}`; legacy bare `[lat, lng]` pairs are accepted and
/// get positional ids (i0, i1, …) with type "item".
class ItemData {
  final String id;
  final String type;
  final double lat;
  final double lng;

  ItemData({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
  });

  static List<ItemData> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <ItemData>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is Map) {
        final lat = entry['lat'];
        final lng = entry['lng'];
        if (lat is num && lng is num) {
          out.add(
            ItemData(
              id: entry['id']?.toString() ?? 'i$i',
              type: entry['type']?.toString() ?? 'item',
              lat: lat.toDouble(),
              lng: lng.toDouble(),
            ),
          );
        }
      } else if (entry is List &&
          entry.length == 2 &&
          entry[0] is num &&
          entry[1] is num) {
        out.add(
          ItemData(
            id: 'i$i',
            type: 'item',
            lat: (entry[0] as num).toDouble(),
            lng: (entry[1] as num).toDouble(),
          ),
        );
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'lat': lat,
    'lng': lng,
  };
}

/// Great-circle distance in metres.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthR = 6371000.0;
  double rad(double d) => d * 3.141592653589793 / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
}
