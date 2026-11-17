import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:nostr/nostr.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/protocol/room_models.dart';
import 'package:openchase/utils/protocol/room_transport.dart';

const defaultRelays = ['wss://relay.damus.io', 'wss://nos.lol'];

/// One websocket client per device: lobby + game channel share the connection.
/// Host mode maintains the authoritative roster and rebroadcasts it (roster
/// heartbeat = late-joiner snapshot + presence heartbeat in one). Player mode
/// renders the host's roster and talks to the host only.
class RoomClient {
  final bool host;
  final List<String> relays;
  final RoomKeys roomKeys;
  final Keychain playerKeys;

  // Reassignable: MapScreen re-registers these when it takes over from the
  // lobby screens.
  void Function() onRosterChanged;
  void Function(RoundStartData round)? onRoundStart;
  void Function(String winner)? onRoundEnd;
  void Function(String pubkey, LocationData loc)? onLocation;

  late final RoomTransport _transport;
  final Map<String, PlayerEntry> _roster = {};
  final Map<String, LocationData> _lastLocations = {};
  final Map<String, List<List<double>>> _lastTrails = {};
  final Set<String> _seenJoins = {};
  int _rosterSeq = 0;
  String _hostName = '';
  String _roomCode = '';
  bool _phasePlaying = false;
  String _roundId = '';
  RoundStartData? _lastRoundStart;

  // Item pickup bookkeeping for the current round.
  Map<String, ItemData> _roundItems = {};
  final Map<String, String> _itemCollectors = {}; // itemId -> grabber pubkey
  final Set<String> _hitsSent = {};
  static const pickupRadiusM = 30;
  static const trailSampleEveryMs = 2000;
  static const trailMaxSamples = 30;

  // Round/role state for the live round.
  final Set<String> _hiders = {};
  final Set<String> _caught = {};
  int _endsAt = 0;
  String? _winner;
  Timer? _hostEndTimer;
  Timer? _trailTimer;
  List<List<double>> _trail = const [];
  int _lastTrailSampleMs = 0;

  // Lobby bookkeeping for joiners
  final List<Map<String, dynamic>> _roomInits = [];

  RoomClient({
    required this.host,
    required this.roomKeys,
    required String playerName,
    required this.onRosterChanged,
    this.onRoundStart,
    this.onRoundEnd,
    this.onLocation,
    this.relays = defaultRelays,
  }) : playerKeys = RoomKeys.generatePlayerKeychain() {
    _hostName = playerName;
    _roomCode = roomKeys.code;
    _transport = RoomTransport(relays: relays, onEvent: _handle);
    _transport.subscribe('room', [
      {
        'authors': [roomKeys.roomPubkey],
        'since': _sinceWindow(600),
      },
    ]);
    if (host) {
      _transport.subscribe('join', [
        {
          'kinds': [
            RoomKinds.join,
            RoomKinds.leave,
            RoomKinds.itemHit,
            RoomKinds.caught,
          ],
          'since': _sinceWindow(600),
        },
      ]);
      _transport.subscribe('loc', [
        {
          'kinds': [RoomKinds.location],
          'since': _sinceWindow(300),
        },
      ]);
    } else {
      _transport.subscribe('loc', [
        {
          'kinds': [RoomKinds.location],
          'since': _sinceWindow(120),
        },
      ]);
    }
    _transport.connect();
  }

  int _sinceWindow(int seconds) => currentUnixTimestampSeconds() - seconds;

  // ── public surface ────────────────────────────────────────────────

  bool get phasePlaying => _phasePlaying;
  String get roundId => _roundId;
  List<String> get playerNames =>
      _roster.values.map((e) => e.name).toList(growable: false);
  Map<String, String> get playerPubkeys => {
    for (final e in _roster.values) e.pubkey: e.name,
  };
  Map<String, LocationData> get lastLocations =>
      Map.unmodifiable(_lastLocations);
  RoundStartData? get lastRoundStart => _lastRoundStart;
  List<ItemData> get roundItems => _roundItems.values.toList(growable: false);
  String? collectorOf(String itemId) => _itemCollectors[itemId];
  void Function(String itemId, String by)? onItemCollected;
  int get endsAt => _endsAt;
  String? get winner => _winner;
  List<String> get hiderPubkeys => _hiders.toList(growable: false);
  Set<String> get caughtHiders => Set.unmodifiable(_caught);
  bool isHider(String pubkey) => _hiders.contains(pubkey);
  bool isCaught(String pubkey) => _caught.contains(pubkey);
  String get selfPubkey => playerKeys.public;
  int get readyRelays => _transport.readyRelays;
  String get hostName => _hostName;

  /// Set once events from a *different* room keypair are observed on our room
  /// identity — means the room code is already live elsewhere.
  bool sawForeignRoomTraffic = false;

  /// Host: announce the room and enter lobby listening.
  void publishRoomInit() {
    final now = currentUnixTimestampSeconds();
    // Roster identity = session pubkey, which is also the author of our
    // location events. The room keypair only signs the room channel.
    _roster[playerKeys.public] = PlayerEntry(playerKeys.public, _hostName, now);
    _publishRoster(RoomMsg.roomInit);
  }

  /// Player: resolve the room by code. Returns host name if a room_init for
  /// this code was seen within [timeoutSeconds], else null.
  Future<String?> findRoom(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final init = _roomInits.where((i) => i['code'] == _roomCode).toList();
      if (init.isNotEmpty) {
        final latest = init.last;
        _hostName = latest['host']?.toString() ?? '';
        return _hostName;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  /// Player: announce join with a stable session key; host rebroadcasts roster.
  /// Signed by the session key so the join author == location author.
  void sendJoin(String name) {
    _publish(
      RoomKinds.join,
      playerKeys.private,
      jsonEncode({'msg': 'join', 'name': name, 'code': _roomCode}),
    );
  }

  /// Player: polite leave (host prunes on receipt; also TTL-prunes us).
  void sendLeave() {
    _publish(
      RoomKinds.leave,
      playerKeys.private,
      jsonEncode({'msg': 'leave', 'name': _hostName, 'code': _roomCode}),
    );
  }

  /// Any: publish own location. Caller throttles (≤1 Hz).
  void sendLocation(double lat, double lng, {double? accuracy}) {
    _lastLocations[playerKeys.public] = LocationData(
      lat: lat,
      lng: lng,
      ts: currentUnixTimestampSeconds(),
    );
    _publish(
      RoomKinds.location,
      playerKeys.private,
      jsonEncode({
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'acc': accuracy.round(),
        'roundId': _roundId,
        'trail': _trail,
      }),
    );
    if (_roster.containsKey(playerKeys.public)) {
      _roster[playerKeys.public] = PlayerEntry(
        playerKeys.public,
        _roster[playerKeys.public]!.name,
        currentUnixTimestampSeconds(),
      );
    }
  }

  /// Host: start the round (area/items = existing setup screens' output).
  void publishRoundStart({
    required List<double> center,
    required int radiusM,
    List<dynamic> items = const [],
    int durationSec = 1800,
    List<String> hiders = const [],
  }) {
    final roundId = _newRoundId();
    final normItems = ItemData.parseList(items);
    final endsAt = currentUnixTimestampSeconds() + durationSec;
    _rosterHeartbeat();
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.roundStart,
        'roundId': roundId,
        'center': center,
        'radius': radiusM,
        'items': normItems.map((it) => it.toJson()).toList(),
        'endsAt': endsAt,
        'hiders': hiders,
        'roster': _rosterJson(),
        'seq': ++_rosterSeq,
      }),
    );
    _applyRoundStart(
      RoundStartData(
        roundId: roundId,
        centerLat: center[0],
        centerLng: center[1],
        radiusM: radiusM,
        items: normItems,
        endsAt: endsAt,
        hiders: hiders,
      ),
    );
    // Host closes the round when the clock runs out. If the host app is
    // suspended the clients still freeze locally at endsAt (grace +20 s).
    _hostEndTimer?.cancel();
    final secs = (endsAt - currentUnixTimestampSeconds()).clamp(1, 86400);
    _hostEndTimer = Timer(Duration(seconds: secs), () {
      if (_phasePlaying && _roundId == roundId && host) {
        publishRoundEnd('hiders');
      }
    });
  }

  /// Host: authoritative round close. Winner is "chasers" (all hiders
  /// caught) or "hiders" (clock expired with hiders loose).
  void publishRoundEnd(String winner) {
    if (!host) return;
    _hostEndTimer?.cancel();
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.roundEnd,
        'code': _roomCode,
        'roundId': _roundId,
        'winner': winner,
      }),
    );
  }

  /// Hider: admit capture (honor system). Host acknowledges to everyone.
  void sendCaught() {
    _publish(
      RoomKinds.caught,
      playerKeys.private,
      jsonEncode({'code': _roomCode, 'roundId': _roundId}),
    );
  }

  void _handleCaught(RoomEvent e) {
    // kind 20006 is relay-global — only accept traffic for our code.
    if (e.data['code']?.toString() != _roomCode) return;
    final pk = e.pubkey;
    if (!_hiders.contains(pk) || _caught.contains(pk)) return;
    _caught.add(pk);
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.hiderCaught,
        'code': _roomCode,
        'roundId': _roundId,
        'hider': pk,
      }),
    );
    if (_caught.containsAll(_hiders) && _hiders.isNotEmpty) {
      publishRoundEnd('chasers');
    }
  }

  /// Periodic tick (every ~20 s): host rebroadcasts roster; everyone prunes
  /// stale entries. Stale = no join/location proof within [ttlSeconds].
  void tick({int ttlSeconds = 60}) {
    final now = currentUnixTimestampSeconds();
    final stale =
        _roster.entries
            .where((e) => now - e.value.lastSeen > ttlSeconds)
            .map((e) => e.key)
            .toList();
    var changed = false;
    for (final pk in stale) {
      _roster.remove(pk);
      _lastLocations.remove(pk);
      changed = true;
    }
    if (host && changed) _publishRoster(RoomMsg.roster);
    if (changed) onRosterChanged();
  }

  void close() {
    _hostEndTimer?.cancel();
    _trailTimer?.cancel();
    _transport.close();
  }

  // ── internals ─────────────────────────────────────────────────────

  final Random _rnd = Random.secure();
  String _newRoundId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${_rnd.nextInt(0xffffff).toRadixString(16)}';

  void _publish(int kind, String privkey, String content) {
    final event = Event.from(kind: kind, content: content, privkey: privkey);
    _transport.publish(event.serialize());
    // Apply locally — real relays never echo events back to the publisher,
    // so own room-channel events must update our own state directly.
    Map<String, dynamic> data = const {};
    try {
      final d = jsonDecode(content);
      if (d is Map<String, dynamic>) data = d;
    } catch (_) {}
    _handle(
      RoomEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: kind,
        data: data,
      ),
    );
  }

  List<Map<String, dynamic>> _rosterJson() =>
      _roster.values.map((e) => e.toJson()).toList();

  void _publishRoster(String msgType) {
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': msgType,
        'code': _roomCode,
        'host': _hostName,
        'roster': _rosterJson(),
        'seq': ++_rosterSeq,
      }),
    );
  }

  void _rosterHeartbeat() {
    if (host) _publishRoster(RoomMsg.roster);
  }

  void _handle(RoomEvent e) {
    e.fromRoomKey = e.pubkey == roomKeys.roomPubkey;
    e.fromSelf = e.pubkey == playerKeys.public;
    if (e.kind == RoomKinds.room && !e.fromRoomKey) {
      // Someone else's room key announced on this identity — room-code
      // collision (or stale replay of a past room with the same code).
      sawForeignRoomTraffic = true;
    }
    switch (e.kind) {
      case RoomKinds.room:
        if (!e.fromRoomKey) return; // forged room event
        _handleRoomEvent(e);
      case RoomKinds.join:
      case RoomKinds.leave:
        if (host) _handleJoinLeave(e);
      case RoomKinds.itemHit:
        if (host) _handleItemHit(e);
      case RoomKinds.caught:
        if (host) _handleCaught(e);
      case RoomKinds.location:
        _handleLocation(e);
    }
  }

  void _handleRoomEvent(RoomEvent e) {
    switch (e.msg) {
      case RoomMsg.roomInit:
        _roomInits.add(e.data);
        if (host) return;
        _applyRoster(e);
      case RoomMsg.roster:
        if (!host) _applyRoster(e);
      case RoomMsg.roundStart:
        if (host) return;
        final round = RoundStartData.from(e);
        if (round == null || e.data['roundId'] == _roundId) return;
        _applyRoster(e);
        _applyRoundStart(round);
      case RoomMsg.roundEnd:
        if (e.data['roundId']?.toString() != _roundId) return;
        _phasePlaying = false;
        onRoundEnd?.call(_winner ?? '');
        final w = e.data['winner']?.toString();
        if (w != null) _winner = w;
      case RoomMsg.hiderCaught:
        if (e.data['roundId']?.toString() != _roundId) return;
        final h = e.data['hider']?.toString();
        if (h != null) _caught.add(h);
      case RoomMsg.itemCollected:
        if (e.data['roundId']?.toString() != _roundId) return;
        final itemId = e.data['itemId']?.toString();
        final by = e.data['by']?.toString();
        if (itemId == null || by == null) return;
        if (_itemCollectors.putIfAbsent(itemId, () => by) == by) {
          onItemCollected?.call(itemId, by);
        }
    }
  }

  void _applyRoster(RoomEvent e) {
    final seq = e.data['seq'];
    if (seq is int && seq <= _rosterSeq) return; // older snapshot
    final roster = e.data['roster'];
    if (roster is! List) return;
    _rosterSeq = seq is int ? seq : _rosterSeq + 1;
    _roster.clear();
    for (final entry in roster) {
      if (entry is Map && entry['pk'] is String && entry['name'] is String) {
        _roster[entry['pk'] as String] = PlayerEntry(
          entry['pk'] as String,
          entry['name'] as String,
          e.createdAt,
        );
      }
    }
    _hostName = e.data['host']?.toString() ?? _hostName;
    onRosterChanged();
  }

  void _applyRoundStart(RoundStartData round) {
    _roundId = round.roundId;
    _phasePlaying = true;
    _lastRoundStart = round;
    _roundItems = {for (final it in round.items) it.id: it};
    _itemCollectors.clear();
    _hitsSent.clear();
    _endsAt = round.endsAt;
    _hiders
      ..clear()
      ..addAll(round.hiders);
    _caught.clear();
    _winner = null;
    _trail = const [];
    _startTrailSampler();
    onRoundStart?.call(round);
  }

  // ---- trails -------------------------------------------------------------

  void _startTrailSampler() {
    _trailTimer?.cancel();
    _lastTrailSampleMs = 0;
    _trailTimer = Timer.periodic(
      const Duration(milliseconds: trailSampleEveryMs),
      (_) {
        final last = _lastLocations[selfPubkey];
        if (last == null) return;
        if (_trail.isEmpty ||
            _trail.last[0] != last.lat ||
            _trail.last[1] != last.lng) {
          final keep = trailMaxSamples - 1;
          _trail = [
            ...(_trail.length > keep
                ? _trail.sublist(_trail.length - keep)
                : _trail),
            [last.lat, last.lng],
          ];
        }
      },
    );
  }

  /// Downsampled trail for a player: ours, or the last one they reported.
  List<List<double>> trailOf(String pubkey) =>
      pubkey == selfPubkey ? _trail : (_lastTrails[pubkey] ?? const []);

  void _handleJoinLeave(RoomEvent e) {
    // kinds 20002/20003 are relay-global — only accept traffic for our code.
    if (e.data['code']?.toString() != _roomCode) return;
    if (e.kind == RoomKinds.join) {
      if (!_seenJoins.add(e.id)) return; // relay replay dedupe
      final name = e.data['name']?.toString();
      if (name == null || name.isEmpty) return;
      _roster[e.pubkey] = PlayerEntry(e.pubkey, name, e.createdAt);
      _publishRoster(RoomMsg.roster);
      onRosterChanged();
    } else if (e.kind == RoomKinds.leave) {
      if (_roster.remove(e.pubkey) != null) {
        _lastLocations.remove(e.pubkey);
        _publishRoster(RoomMsg.roster);
        onRosterChanged();
      }
    }
  }

  /// Call with own fresh position each update: claims uncollected items we
  /// are within [pickupRadiusM] of. One itemHit per item per round per player;
  /// host validates against its location stream and broadcasts the result.
  void checkItemPickups(double lat, double lng) {
    for (final it in _roundItems.values) {
      if (_itemCollectors.containsKey(it.id) || _hitsSent.contains(it.id)) {
        continue;
      }
      if (distanceMeters(lat, lng, it.lat, it.lng) <= pickupRadiusM) {
        _hitsSent.add(it.id);
        _publish(
          RoomKinds.itemHit,
          playerKeys.private,
          jsonEncode({'itemId': it.id, 'code': _roomCode, 'roundId': _roundId}),
        );
      }
    }
  }

  void _handleItemHit(RoomEvent e) {
    // kinds 20004 is relay-global — only accept traffic for our code.
    if (e.data['code']?.toString() != _roomCode) return;
    final itemId = e.data['itemId']?.toString();
    if (itemId == null) return;
    final item = _roundItems[itemId];
    if (item == null || _itemCollectors.containsKey(itemId)) return;
    final loc = _lastLocations[e.pubkey];
    if (loc == null) return;
    // Stream lag slack: claim radius 2x our pickup radius.
    if (distanceMeters(loc.lat, loc.lng, item.lat, item.lng) >
        pickupRadiusM * 2) {
      return; // too far from our last-known position of this player
    }
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.itemCollected,
        'code': _roomCode,
        'roundId': _roundId,
        'itemId': itemId,
        'by': e.pubkey,
      }),
    );
  }

  void _handleLocation(RoomEvent e) {
    if (!_roster.containsKey(e.pubkey)) return; // not in our roster — ignore
    final loc = LocationData.from(e);
    if (loc == null) return;
    final prev = _lastLocations[e.pubkey];
    if (prev != null && prev.ts >= loc.ts) return; // out-of-order
    _lastLocations[e.pubkey] = loc;
    final trailData = e.data['trail'];
    if (trailData is List) {
      _lastTrails[e.pubkey] =
          trailData
              .whereType<List>()
              .where((p2) => p2.length >= 2)
              .map<List<double>>(
                (p2) => <double>[p2[0].toDouble(), p2[1].toDouble()],
              )
              .toList();
    }
    if (_roster[e.pubkey]!.lastSeen < loc.ts) {
      _roster[e.pubkey] = PlayerEntry(
        e.pubkey,
        _roster[e.pubkey]!.name,
        loc.ts,
      );
    }
    onLocation?.call(e.pubkey, loc);
  }
}
