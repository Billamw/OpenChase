import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:nostr/nostr.dart';
import 'package:openchase/utils/protocol/room_crypto.dart';
import 'package:openchase/utils/protocol/room_host.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/protocol/room_models.dart';
import 'package:openchase/utils/protocol/room_transport.dart';

const _relaysOverride = String.fromEnvironment('RELAYS');
List<String> get defaultRelays => _relaysOverride.isNotEmpty
    ? _relaysOverride.split(',').map((e) => e.trim()).toList()
    : const [
        'wss://nos.lol', 'wss://relay.nostr.net',
        'wss://relay.primal.net', 'wss://nostr.wine',
      ];

/// One websocket client per device: lobby + game channel share the connection.
/// Host mode maintains the authoritative roster, the items-v1 round state
/// machine (RoomHost) and the hunt visibility fan-out. Player mode renders
/// the host's publishes and talks to the host only.
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

  // Items v1 (host-published state deltas; docs/room-protocol-spec.md).
  void Function(String phase)? onPhaseChanged;
  void Function(Map<String, List<double>> positions)? onAnchorReveal;
  void Function(String itemId, EffectView effect)? onEffectStarted;
  void Function(String itemId, String reason)? onEffectCancelled;
  void Function(String itemId, String reason)? onEffectRejected;
  void Function(String itemId, String reason)? onItemRejected;
  void Function(String by)? onBankCleared;
  void Function(String by, String target)? onRevealNotice;
  void Function(String seekerPk, Map<String, dynamic> payload)? onZoneSoftlock;

  /// Host-side round settings source (density / bank cap / head start),
  /// wired by the app layer from the round-settings UI (GameManager).
  static ({String density, int bankCap, int headStartMin}) Function()?
  settingsProvider;

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
  final Set<String> _usedOrDropped = {}; // consumed or vanished item ids
  static const pickupRadiusM = 15; // auto-grab (decisions.pickup)
  static const trailSampleEveryMs = 2000;
  static const trailMaxSamples = 30;

  // Round/role state for the live round.
  final Set<String> _hiders = {};
  final Set<String> _caught = {};
  int _endsAt = 0;
  String? _winner;
  Timer? _hostEndTimer;
  Timer? _huntTimer;
  Timer? _trailTimer;
  List<List<double>> _trail = const [];

  // Items v1 client view state (from host events + local clock).
  String _phase = RoundPhase.lobby;
  int _roundBankCap = 3;
  int _headStartEndsAt = 0;
  int _jamEndsAt = 0;
  final Map<String, int> _frozenUntil = {}; // seeker pk -> freeze endsAt
  final Set<String> _softlocked = {};
  final Map<String, EffectView> _effectsView = {};

  // Host authority for the live round (null outside rounds / on players).
  RoomHost? _host;

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
    List<String>? relays,
  }) : relays = relays ?? defaultRelays,
       playerKeys = RoomKeys.generatePlayerKeychain() {
    _hostName = playerName;
    _roomCode = roomKeys.code;
    _transport = RoomTransport(relays: this.relays, onEvent: _handle);
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

  // ── public surface ────────────────────────────────────────────────────

  bool get phasePlaying => _phasePlaying;
  String get roundId => _roundId;
  String get phase => _phase;
  int get roundBankCap => _roundBankCap;
  List<String> get playerNames =>
      _roster.values.map((e) => e.name).toList(growable: false);
  Map<String, String> get playerPubkeys => {
    for (final e in _roster.values) e.pubkey: e.name,
  };
  Map<String, LocationData> get lastLocations =>
      Map.unmodifiable(_lastLocations);
  RoundStartData? get lastRoundStart => _lastRoundStart;

  /// Items of the live round that are still grabbable or banked-but-unused
  /// (consumed / vanished items drop out of the view).
  List<ItemData> get roundItems => _roundItems.values
      .where((it) => !_usedOrDropped.contains(it.id))
      .toList(growable: false);
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

  /// Session pubkey of the host player (author of targeted publishes),
  /// resolved from the roster by host name. Null on the host itself.
  String? get hostPlayerPubkey {
    if (host) return null;
    final byName = _playerPubkeyForHostName(_hostName);
    if (byName != null) return byName;
    final others = _roster.keys
        .where((pk) => pk != playerKeys.public)
        .toList();
    return others.length == 1 ? others.first : null;
  }

  String? _playerPubkeyForHostName(String name) {
    for (final e in _roster.entries) {
      if (e.value.name == name && e.key != playerKeys.public) return e.key;
    }
    return null;
  }

  /// Banked, still-usable items of a player (client view from host events).
  List<ItemData> bankOf(String pk) => _roundItems.values
      .where(
        (it) =>
            _itemCollectors[it.id] == pk && !_usedOrDropped.contains(it.id),
      )
      .toList(growable: false);

  bool get jamActive => currentUnixSeconds() < _jamEndsAt;
  int get jamEndsAt => _jamEndsAt;
  int get headStartEndsAt => _headStartEndsAt;
  bool isSeekerFrozen(String pk) =>
      pk != selfPubkey && currentUnixSeconds() < (_frozenUntil[pk] ?? 0);
  bool isSeekerSoftlocked(String pk) =>
      pk != selfPubkey && _softlocked.contains(pk);

  /// Set once events from a *different* room keypair are observed on our room
  /// identity — means the room code is already live elsewhere.
  bool sawForeignRoomTraffic = false;

  static int currentUnixSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── lobby / roster ────────────────────────────────────────────────────

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

  // ── location ──────────────────────────────────────────────────────────

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
    _touchRoster(playerKeys.public, currentUnixTimestampSeconds());
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
        _publishItemHit(it.id);
      }
    }
  }

  void _publishItemHit(String itemId) {
    _publish(
      RoomKinds.itemHit,
      playerKeys.private,
      jsonEncode({'itemId': itemId, 'code': _roomCode, 'roundId': _roundId}),
    );
  }

  /// Test seam: publish an itemHit bypassing the per-player dedupe (models a
  /// second claimant whose intent races ahead under relay latency).
  void publishItemHitForTest(String itemId) {
    _hitsSent.remove(itemId);
    _publishItemHit(itemId);
  }

  /// Any: ask the host to resolve a banked-item use (hunt phase only).
  /// Observe the outcome via [onEffectStarted] / [onEffectRejected].
  void useItem(String itemId, {String? target, List<double>? center}) {
    _publish(
      RoomKinds.itemHit,
      playerKeys.private,
      jsonEncode({
        'msg': RoomMsg.itemUse,
        'itemId': itemId,
        'code': _roomCode,
        'roundId': _roundId,
        if (target != null) 'target': target,
        if (center != null) 'center': center,
      }),
    );
  }

  // ── round lifecycle ───────────────────────────────────────────────────

  /// Host: start the round (area/items = existing setup screens' output).
  /// Items v1: when a density is configured (settings provider or explicit
  /// arg), the host rolls a fresh pool per docs/items_v1.json (density count,
  /// rarity weights 60/30/10) over the placed positions. Without density
  /// (pre-v1 flow) placements pass through untouched.
  void publishRoundStart({
    required List<double> center,
    required int radiusM,
    List<dynamic> items = const [],
    int durationSec = 1800,
    List<String> hiders = const [],
    String? density,
    int? bankCap,
    int? headStartMin,
    int? headStartSec, // test seam: override head-start in seconds
  }) {
    final settings = settingsProvider?.call();
    final d = density ?? settings?.density ?? '';
    final cap = (bankCap ?? settings?.bankCap ?? 3).clamp(1, 5);
    final hsMin = headStartMin ?? settings?.headStartMin ?? 0;
    final hsSec = headStartSec ?? hsMin * 60;

    final roundId = _newRoundId();
    final now = currentUnixTimestampSeconds();
    final headStartEndsAt = hsSec > 0 ? now + hsSec : 0;
    final endsAt = now + durationSec;

    _host = RoomHost(
      now: currentUnixSeconds,
      publishRoom: (p) =>
          _publish(RoomKinds.room, roomKeys.roomPrivkey, jsonEncode(p)),
      publishTargeted: _publishTargeted,
    )..hostPlayerPk = playerKeys.public;
    final normItems = _host!.prepareItems(
      placed: ItemData.parseList(items),
      density: d,
      centerLat: center[0],
      centerLng: center[1],
      radiusM: radiusM,
    );

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
        if (d.isNotEmpty) ...{
          'density': d,
          'bankCap': cap,
          'headStartMin': hsMin,
          'headStartEndsAt': headStartEndsAt,
        },
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
        density: d,
        bankCap: cap,
        headStartMin: hsMin,
        headStartEndsAt: headStartEndsAt,
      ),
    );
    _scheduleHostTimers();
  }

  void _scheduleHostTimers() {
    if (!host || _lastRoundStart == null) return;
    final r = _lastRoundStart!;
    _huntTimer?.cancel();
    if (r.headStartEndsAt > 0) {
      final hs = (r.headStartEndsAt - currentUnixSeconds()).clamp(1, 86400);
      _huntTimer = Timer(Duration(seconds: hs), () {
        if (_phasePlaying && host) _host?.enterHunt();
      });
    }
    // Host closes the round when the clock runs out. If the host app is
    // suspended the clients still freeze locally at endsAt (grace +20 s).
    _scheduleHostEndTimer(r.endsAt);
  }

  void _scheduleHostEndTimer(int endsAt) {
    if (!host) return;
    _hostEndTimer?.cancel();
    final secs = (endsAt - currentUnixSeconds()).clamp(1, 86400);
    final rid = _roundId;
    _hostEndTimer = Timer(Duration(seconds: secs), () {
      if (_phasePlaying && _roundId == rid && host) {
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
    final allCaught = _host?.handleCaught(pk) ?? false;
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
    // Caught hider's bank vanishes (decisions.catch_loot: no looting).
    _publish(
      RoomKinds.room,
      roomKeys.roomPrivkey,
      jsonEncode({
        'msg': RoomMsg.itemBankCleared,
        'roundId': _roundId,
        'by': pk,
        'at': currentUnixSeconds(),
      }),
    );
    if (allCaught && _hiders.isNotEmpty) {
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
    _huntTimer?.cancel();
    _trailTimer?.cancel();
    _transport.close();
  }

  // ── internals ─────────────────────────────────────────────────────────

  final Random _rnd = Random.secure();
  String _newRoundId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${_rnd.nextInt(0xffffff).toRadixString(16)}';

  void _publish(
    int kind,
    String privkey,
    String content, {
    List<List<String>> tags = const [],
  }) {
    final event = Event.from(
      kind: kind,
      content: content,
      privkey: privkey,
      tags: tags,
    );
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
        tags: tags,
      )..content = content,
    );
  }

  /// Host: rebroadcast one hider's position to a single seeker, encrypted
  /// under the seeker's session key (hunt visibility policy).
  void _publishTargeted(String seekerPk, Map<String, dynamic> payload) {
    final cipher = RoomCrypto.encryptFor(
      playerKeys.private,
      seekerPk,
      jsonEncode(payload),
    );
    _publish(
      RoomKinds.location,
      playerKeys.private,
      cipher,
      tags: [
        ['to', seekerPk],
      ],
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

  void _touchRoster(String pk, int ts) {
    final entry = _roster[pk];
    if (entry != null && entry.lastSeen < ts) {
      _roster[pk] = PlayerEntry(pk, entry.name, ts);
    }
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
        if (host) _handleItemEvent(e);
      case RoomKinds.caught:
        if (host) _handleCaught(e);
      case RoomKinds.location:
        _handleLocation(e);
    }
  }

  void _handleRoomEvent(RoomEvent e) {
    final rid = e.data['roundId']?.toString();
    final mine = rid == null || rid == _roundId;
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
        _phase = RoundPhase.roundOver;
        _huntTimer?.cancel();
        _host = null;
        _clearRoundEffectState(clearCollectors: false);
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
      case RoomMsg.phaseChanged:
        if (!mine) return;
        final p = e.data['phase']?.toString();
        if (p != null) {
          _phase = p;
          onPhaseChanged?.call(p);
        }
      case RoomMsg.zoneSoftlock:
        if (!mine) return;
        final seeker = e.data['seeker']?.toString();
        if (seeker == null) return;
        if (e.data['released'] == true) {
          _softlocked.remove(seeker);
        } else {
          _softlocked.add(seeker);
        }
        onZoneSoftlock?.call(seeker, e.data);
      case RoomMsg.anchorReveal:
        if (!mine) return;
        final positions = <String, List<double>>{};
        for (final p in (e.data['positions'] as List? ?? const [])) {
          if (p is List && p.length >= 3 && p[0] is String) {
            positions[p[0] as String] = [
              (p[1] as num).toDouble(),
              (p[2] as num).toDouble(),
            ];
          }
        }
        onAnchorReveal?.call(positions);
      case RoomMsg.itemRejected:
        if (!mine) return;
        if (e.data['to']?.toString() != playerKeys.public) return;
        final itemId = e.data['itemId']?.toString() ?? '';
        final reason = e.data['reason']?.toString() ?? '';
        if (itemId.isNotEmpty) _hitsSent.remove(itemId); // retryable later
        onItemRejected?.call(itemId, reason);
      case RoomMsg.itemBankCleared:
        if (!mine) return;
        final by = e.data['by']?.toString();
        if (by == null) return;
        for (final it in _roundItems.values) {
          if (_itemCollectors[it.id] == by) _usedOrDropped.add(it.id);
        }
        onBankCleared?.call(by);
      case RoomMsg.effectStarted:
        if (!mine) return;
        final itemId = e.data['itemId']?.toString();
        final type = e.data['type']?.toString();
        if (itemId == null || type == null) return;
        final to = e.data['to']?.toString();
        if (to != null && to != playerKeys.public) return; // seeker-only effect
        _usedOrDropped.add(itemId); // consumed, no refund
        final view = EffectView(
          itemId: itemId,
          type: type,
          target: e.data['target']?.toString(),
          center: _parseCenter(e.data['center']),
          endsAt:
              e.data['endsAt'] is num ? (e.data['endsAt'] as num).toInt() : 0,
          at: e.data['at'] is num ? (e.data['at'] as num).toInt() : 0,
          payload: e.data,
        );
        _effectsView[itemId] = view;
        onEffectStarted?.call(itemId, view);
      case RoomMsg.effectCancelled:
        if (!mine) return;
        final itemId = e.data['itemId']?.toString() ?? '';
        final reason = e.data['reason']?.toString() ?? '';
        final ef = _effectsView.remove(itemId);
        if (ef != null) {
          onEffectCancelled?.call(itemId, reason);
        }
      case RoomMsg.effectRejected:
        if (!mine) return;
        if (e.data['to']?.toString() != playerKeys.public) return;
        onEffectRejected?.call(
          e.data['itemId']?.toString() ?? '',
          e.data['reason']?.toString() ?? '',
        );
      case RoomMsg.jam:
        if (!mine) return;
        final ends =
            e.data['endsAt'] is num ? (e.data['endsAt'] as num).toInt() : 0;
        if (ends > _jamEndsAt) _jamEndsAt = ends;
      case RoomMsg.freeze:
        if (!mine) return;
        final seeker = e.data['seeker']?.toString();
        final ends =
            e.data['endsAt'] is num ? (e.data['endsAt'] as num).toInt() : 0;
        if (seeker != null && ends > (_frozenUntil[seeker] ?? 0)) {
          _frozenUntil[seeker] = ends;
        }
      case RoomMsg.roundTimer:
        if (!mine) return;
        final ends =
            e.data['endsAt'] is num ? (e.data['endsAt'] as num).toInt() : 0;
        if (ends > 0) {
          _endsAt = ends;
          if (host) _scheduleHostEndTimer(ends);
        }
      case RoomMsg.revealNotice:
        if (!mine) return;
        onRevealNotice?.call(
          e.data['by']?.toString() ?? '',
          e.data['target']?.toString() ?? '',
        );
    }
  }

  static List<double>? _parseCenter(dynamic v) {
    if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
      return [(v[0] as num).toDouble(), (v[1] as num).toDouble()];
    }
    return null;
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
    _roundBankCap = round.bankCap;
    _headStartEndsAt = round.headStartEndsAt;
    _itemCollectors.clear();
    _hitsSent.clear();
    _endsAt = round.endsAt;
    _hiders
      ..clear()
      ..addAll(round.hiders);
    _caught.clear();
    _winner = null;
    _trail = const [];
    _clearRoundEffectState(clearCollectors: true);
    _phase = round.headStartEndsAt > currentUnixSeconds()
        ? RoundPhase.headStart
        : RoundPhase.hunt;
    if (host) {
      for (final pk in _roster.keys) {
        _host?.addParticipant(pk);
      }
      _host?.onRoundStart(round);
    }
    _startTrailSampler();
    onRoundStart?.call(round);
  }

  /// round_end / next round_start wipe all effect state, jams, freezes,
  /// soft-locks, bank view and trail buffers — nothing survives into the
  /// next round.
  void _clearRoundEffectState({required bool clearCollectors}) {
    _effectsView.clear();
    _usedOrDropped.clear();
    if (clearCollectors) _itemCollectors.clear();
    _frozenUntil.clear();
    _softlocked.clear();
    _jamEndsAt = 0;
    _lastTrails.clear();
    _hitsSent.clear();
  }

  // ---- trails -------------------------------------------------------------

  void _startTrailSampler() {
    _trailTimer?.cancel();
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

  /// Downsampled trail for a player: ours; others' only where the hunt
  /// visibility policy allows (targeted publishes) — frozen / soft-locked
  /// seekers flatline (honor stand-still).
  List<List<double>> trailOf(String pubkey) {
    if (pubkey == selfPubkey) return _trail;
    if (isSeekerFrozen(pubkey) || isSeekerSoftlocked(pubkey)) {
      final p = _lastLocations[pubkey];
      return p == null
          ? const []
          : [
              [p.lat, p.lng],
              [p.lat, p.lng],
            ];
    }
    return _lastTrails[pubkey] ?? const [];
  }

  void _handleJoinLeave(RoomEvent e) {
    // kinds 20002/20003 are relay-global — only accept traffic for our code.
    if (e.data['code']?.toString() != _roomCode) return;
    if (e.kind == RoomKinds.join) {
      if (!_seenJoins.add(e.id)) return; // relay replay dedupe
      final name = e.data['name']?.toString();
      if (name == null || name.isEmpty) return;
      _roster[e.pubkey] = PlayerEntry(e.pubkey, name, e.createdAt);
      _host?.addParticipant(e.pubkey);
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

  void _handleItemEvent(RoomEvent e) {
    // kind 20004 is relay-global — only accept traffic for our code.
    if (e.data['code']?.toString() != _roomCode) return;
    final itemId = e.data['itemId']?.toString();
    if (itemId == null) return;
    if (e.msg == RoomMsg.itemUse) {
      _host?.handleItemUse(
        e.pubkey,
        itemId,
        target: e.data['target']?.toString(),
        center: _parseCenter(e.data['center']),
      );
      return;
    }
    _host?.handleItemHit(e.pubkey, itemId);
  }

  void _handleLocation(RoomEvent e) {
    if (e.tag('to') == playerKeys.public &&
        e.pubkey != playerKeys.public &&
        e.pubkey != roomKeys.roomPubkey) {
      // Targeted hider-position publish from the host, encrypted to us.
      final plain = RoomCrypto.decrypt(
        playerKeys.private,
        e.pubkey,
        e.content,
      );
      _applyTargeted(plain, e);
      return;
    }
    if (!_roster.containsKey(e.pubkey)) return; // not in our roster — ignore
    final loc = LocationData.from(e);
    if (loc == null) return;
    if (!_locationVisibleToMe(e.pubkey)) return; // hunt visibility policy
    _mergeLocation(e.pubkey, loc);
    final trailData = e.data['trail'];
    if (trailData is List && _trailVisibleToMe(e.pubkey)) {
      _lastTrails[e.pubkey] =
          trailData
              .whereType<List>()
              .where((p2) => p2.length >= 2)
              .map<List<double>>(
                (p2) => <double>[p2[0].toDouble(), p2[1].toDouble()],
              )
              .toList();
    }
    onLocation?.call(e.pubkey, loc);
    if (host) _host?.ingestLocation(e.pubkey, loc);
  }

  void _applyTargeted(String? plain, RoomEvent e) {
    if (plain == null) return; // not decryptable with our key — ignore
    dynamic payload;
    try {
      payload = jsonDecode(plain);
    } catch (_) {
      return;
    }
    if (payload is! Map) return;
    final hider = payload['hider']?.toString();
    final lat = payload['lat'];
    final lng = payload['lng'];
    if (hider == null || lat is! num || lng is! num) return;
    final rid = payload['roundId']?.toString();
    if (rid != null && rid != _roundId) return;
    final ts =
        payload['ts'] is num ? (payload['ts'] as num).toInt() : e.createdAt;
    final prev = _lastLocations[hider];
    if (prev != null && prev.ts >= ts) return; // out-of-order
    final loc = LocationData(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      accuracy:
          payload['acc'] is num ? (payload['acc'] as num).toDouble() : null,
      ts: ts,
    );
    _lastLocations[hider] = loc;
    final trailData = payload['trail'];
    if (trailData is List) {
      _lastTrails[hider] =
          trailData
              .whereType<List>()
              .where((p2) => p2.length >= 2)
              .map<List<double>>(
                (p2) => <double>[p2[0].toDouble(), p2[1].toDouble()],
              )
              .toList();
    }
    onLocation?.call(hider, loc);
  }

  void _mergeLocation(String pk, LocationData loc) {
    _lastLocations[pk] = loc;
    _touchRoster(pk, loc.ts);
  }

  /// Hunt-phase gate (decisions.hunt_visibility): raw hider LocationData is
  /// not visible to other players once hunt is on — it arrives via targeted
  /// publishes (eyes radius / effects / anchor reveal) instead. Outside hunt
  /// (lobby, head_start, round over) the room behaves like pre-v1 rounds.
  bool _locationVisibleToMe(String pk) {
    if (pk == selfPubkey) return true;
    if (host) return true; // authority consumes the raw stream
    if (_phase != RoundPhase.hunt || !_phasePlaying) return true;
    if (_hiders.contains(pk) && !_caught.contains(pk)) return false;
    // Jammed seekers see no other players at all (JAMMED banner instead).
    if (jamActive && !isHider(selfPubkey)) return false;
    return true;
  }

  /// decisions.own_trail: during hunt only our own trail is trusted; other
  /// players' trails arrive only inside targeted publishes.
  bool _trailVisibleToMe(String pk) {
    if (pk == selfPubkey) return true;
    if (_phase != RoundPhase.hunt || !_phasePlaying) return true;
    return false;
  }
}

/// Client-side view of a host-published effect (envelope + payload).
class EffectView {
  final String itemId;
  final String type;
  final String? target;
  final List<double>? center;
  final int endsAt;
  final int at;
  final Map<String, dynamic> payload;
  EffectView({
    required this.itemId,
    required this.type,
    this.target,
    this.center,
    required this.endsAt,
    required this.at,
    required this.payload,
  });
}
