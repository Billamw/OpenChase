import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:nostr/nostr.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/protocol/room_models.dart';
import 'package:openchase/utils/protocol/room_transport.dart';

const defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
];

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
  void Function(String pubkey, LocationData loc)? onLocation;

  late final RoomTransport _transport;
  final Map<String, PlayerEntry> _roster = {};
  final Map<String, LocationData> _lastLocations = {};
  final Set<String> _seenJoins = {};
  int _rosterSeq = 0;
  String _hostName = '';
  String _roomCode = '';
  bool _phasePlaying = false;
  String _roundId = '';
  RoundStartData? _lastRoundStart;

  // Lobby bookkeeping for joiners
  final List<Map<String, dynamic>> _roomInits = [];

  RoomClient({
    required this.host,
    required this.roomKeys,
    required String playerName,
    required this.onRosterChanged,
    this.onRoundStart,
    this.onLocation,
    this.relays = defaultRelays,
  }) : playerKeys = RoomKeys.generatePlayerKeychain() {
    _hostName = playerName;
    _roomCode = roomKeys.code;
    _transport = RoomTransport(relays: relays, onEvent: _handle);
    _transport.subscribe('room', [
      {'authors': [roomKeys.roomPubkey], 'since': _sinceWindow(600)},
    ]);
    if (host) {
      _transport.subscribe('join', [
        {'kinds': [RoomKinds.join, RoomKinds.leave], 'since': _sinceWindow(600)},
      ]);
      _transport.subscribe('loc', [
        {'kinds': [RoomKinds.location], 'since': _sinceWindow(300)},
      ]);
    } else {
      _transport.subscribe('loc', [
        {'kinds': [RoomKinds.location], 'since': _sinceWindow(120)},
      ]);
    }
    _transport.connect();
  }

  int _sinceWindow(int seconds) =>
      currentUnixTimestampSeconds() - seconds;

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
    _publish(
      RoomKinds.location,
      playerKeys.private,
      jsonEncode({
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'acc': accuracy.round(),
        'roundId': _roundId,
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
  }) {
    final roundId = _newRoundId();
    _rosterHeartbeat();
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.roundStart,
        'roundId': roundId,
        'center': center,
        'radius': radiusM,
        'items': items,
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
        items: items,
      ),
    );
  }

  /// Periodic tick (every ~20 s): host rebroadcasts roster; everyone prunes
  /// stale entries. Stale = no join/location proof within [ttlSeconds].
  void tick({int ttlSeconds = 60}) {
    final now = currentUnixTimestampSeconds();
    final stale = _roster.entries
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

  void close() => _transport.close();

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
        _phasePlaying = false;
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
    onRoundStart?.call(round);
  }

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

  void _handleLocation(RoomEvent e) {
    if (!_roster.containsKey(e.pubkey)) return; // not in our roster — ignore
    final loc = LocationData.from(e);
    if (loc == null) return;
    final prev = _lastLocations[e.pubkey];
    if (prev != null && prev.ts >= loc.ts) return; // out-of-order
    _lastLocations[e.pubkey] = loc;
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
