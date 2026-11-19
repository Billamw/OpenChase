import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/utils/player.dart';
import 'package:openchase/utils/circle_generator.dart';
import 'package:openchase/utils/location_service.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/protocol/room_client.dart';
import 'package:openchase/utils/protocol/room_models.dart';
import 'package:openchase/utils/sim_location.dart';
import 'package:openchase/host_settings_screen.dart';
import 'package:openchase/main_screen.dart';
import 'package:openchase/item_catalog.dart';
import 'package:openchase/theme.dart';

class MapScreen extends StatefulWidget {
  final List<Player> players;
  final LatLng playAreaCenter;
  final int playareaRadius;

  MapScreen({
    required this.players,
    required this.playAreaCenter,
    required this.playareaRadius,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  static const _palette = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.amber,
  ];

  late final MapController _mapController;
  final Map<String, Player> _playersByPubkey = {};
  Player? _user;
  LatLng _currentPosition = LatLng(0, 0);
  bool _loading = true;
  bool _followUser = true;
  late Timer _locationUpdateTimer;
  late Timer _renderTimer;
  late Timer _rosterTickTimer;
  final GeolocatorService geolocatorService = GeolocatorService();

  final Set<String> _trailHidden = {}; // pubkeys whose trail filter is off

  // Items v1 UI state. Effect state here is a LOCAL PLACEHOLDER: real
  // effect truth must arrive as host-published events (backend); the UI
  // renders that once it exists. Never trust this for gameplay decisions.
  final List<ActiveEffect> _effects = [];
  String? _talkItemId; // walky_talky channel open -> chip pulses red
  String? _talkPeerName;
  LatLng? _dronePlacement; // non-null = drone zone aiming on the map
  late Timer _effectTickTimer;
  late final AnimationController _talkPulse;
  static final Distance _dist = Distance();

  List<ItemData> get _bank {
    final client = GameManager.roomClient;
    if (client == null) return const [];
    return client.roundItems
        .where((it) => client.collectorOf(it.id) == client.selfPubkey)
        .take(GameManager.roundBankCap)
        .toList(growable: false);
  }

  bool _effectActive(String id) =>
      _effects.any((e) => e.def.id == id && e.endsAt.isAfter(DateTime.now()));

  /// Seekers see the JAMMED overlay while a disturber effect runs
  /// (host-published jam events will replace this local placeholder).
  bool get _jammed =>
      _effectActive('disturber') &&
      _client != null &&
      !_client!.isHider(_client!.selfPubkey);

  DateTime get _jamEnd => _effects
      .where((e) => e.def.id == 'disturber')
      .map((e) => e.endsAt)
      .fold(DateTime.now(), (a, b) => b.isAfter(a) ? b : a);

  RoomClient? get _client => GameManager.roomClient;

  /// Round is live: host says playing AND the local clock has not expired
  /// (grace +20 s) — so clients freeze even if a suspended host missed
  /// publishing round_end on time.
  bool get _roundActive {
    final c = _client;
    if (c == null) return true; // debug path without a room client
    if (!c.phasePlaying) return false;
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (c.endsAt > 0 && nowS > c.endsAt + 20) return false;
    return true;
  }

  String _countdownLabel() {
    final c = _client;
    if (c == null || c.endsAt == 0) return 'OpenChase';
    final rem = c.endsAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (rem <= 0) return '0:00';
    final m = rem ~/ 60, s = rem % 60;
    return 'Round over in $m:${s.toString().padLeft(2, '0')}';
  }

  String _roundOverLabel() {
    final c = _client;
    final tally =
        '${c!.caughtHiders.length}/${c.hiderPubkeys.length} hiders caught';
    switch (c.winner) {
      case 'chasers':
        return 'Chasers win! $tally';
      case 'hiders':
        return 'Hiders win! $tally';
      default:
        return 'Time is up — round over. $tally';
    }
  }

  // ---- Items v1 UI (flows are UI-only; effect truth is host-published) ----

  static const double _eyesRadiusM = 50;

  String _mmss(DateTime end) {
    final rem = (end.difference(DateTime.now()).inSeconds).clamp(0, 1 << 30);
    return '${rem ~/ 60}:${(rem % 60).toString().padLeft(2, '0')}';
  }

  bool _withinEyes(LatLng p) =>
      _dist.distance(p, _currentPosition) <= _eyesRadiusM;

  void _startEffect(ItemDef def, {String? targetName}) {
    if (def.bannerSec > 0) {
      setState(() => _effects.add(
        ActiveEffect(
          def: def,
          label: targetName == null ? def.name : '${def.name} → $targetName',
          endsAt: DateTime.now().add(Duration(seconds: def.bannerSec)),
        ),
      ));
    } else {
      // Instant/info items have nothing to render until the host publishes
      // their result (backend). Make that visible instead of silently no-op.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${def.name} queued — result needs host publish (backend)',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _useItem(ItemData item) async {
    if (_jammed) return;
    final def = itemDefOf(item.type);
    if (def.bannerSec > 0 && _effectActive(def.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${def.name} already active')),
      );
      return;
    }
    switch (def.target) {
      case ItemTargetMode.player:
        await _pickPlayer(item, def, hidersOnly: false);
      case ItemTargetMode.hider:
        await _pickPlayer(item, def, hidersOnly: true);
      case ItemTargetMode.zone:
        setState(() => _dronePlacement = _currentPosition);
      case ItemTargetMode.position:
        final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Arm ${def.name}?'),
            content: const Text(
              'Arms at your current position and stays live all round.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Arm here'),
              ),
            ],
          ),
        );
        if (go == true) _startEffect(def);
      case ItemTargetMode.none:
        final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Use ${def.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Use'),
              ),
            ],
          ),
        );
        if (go == true) _startEffect(def);
    }
  }

  Future<void> _pickPlayer(
    ItemData item,
    ItemDef def, {
    required bool hidersOnly,
  }) async {
    final client = _client;
    if (client == null) return;
    final entries =
        client.playerPubkeys.entries
            .where((e) => !hidersOnly || (client.isHider(e.key) && !client.isCaught(e.key)))
            .toList();
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No target players')),
      );
      return;
    }
    final pk = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OcColors.card,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '${def.name} — pick player',
                style: const TextStyle(
                  color: OcColors.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final e in entries)
              ListTile(
                leading: Icon(def.icon, color: OcColors.gold),
                title: Text(
                  e.value,
                  style: const TextStyle(color: OcColors.fg),
                ),
                onTap: () => Navigator.pop(sheetContext, e.key),
              ),
          ],
        ),
      ),
    );
    if (pk == null || !mounted) return;
    final name = client.playerPubkeys[pk] ?? '?';
    if (def.id == 'walky_talky') {
      // Transport is a placeholder: pairing UI works, voice server is
      // backend and deferred. The chip itself becomes the on-air dot.
      setState(() {
        _talkItemId = item.id;
        _talkPeerName = name;
      });
      _talkPulse.repeat(reverse: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Channel to $name open — voice transport pending (backend)',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      _startEffect(def, targetName: name);
    }
  }

  void _endTalk() {
    _talkPulse.stop();
    setState(() {
      _talkItemId = null;
      _talkPeerName = null;
    });
  }

  void _resetRoundUi() {
    for (final p in _playersByPubkey.values) {
      p.positionHistory.clear();
      p.shownPositionHistory = [];
      p.trailVisible = true;
    }
    _trailHidden.clear();
    _effects.clear();
    _talkPulse.stop();
    _talkItemId = null;
    _talkPeerName = null;
    _dronePlacement = null;
    _followUser = true;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _talkPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final client = GameManager.roomClient;
    _currentPosition = widget.playAreaCenter;

    if (client != null) {
      // Build players from the live roster (identity = pubkey, not name).
      var i = 0;
      for (final entry in client.playerPubkeys.entries) {
        _playersByPubkey[entry.key] = Player(
          name: entry.value,
          color: _palette[i++ % _palette.length],
          positionHistory: [],
          currentPosition: widget.playAreaCenter,
        );
      }
      _user = _playersByPubkey[client.selfPubkey];

      for (final entry in client.lastLocations.entries) {
        final p = _playersByPubkey[entry.key];
        if (p == null) continue;
        p.updatePosition(LatLng(entry.value.lat, entry.value.lng));
        p.revealPosition();
        p.revealPositionHistory();
      }

      client.onLocation = (pubkey, loc) {
        final p = _playersByPubkey[pubkey];
        if (p == null) return;
        p.updatePosition(LatLng(loc.lat, loc.lng));
        p.revealPosition();
        p.revealPositionHistory();
      };
      client.onRosterChanged = () {
        _syncRoster();
        if (mounted) setState(() {});
      };
      // Players already on the map follow new rounds automatically.
      client.onRoundStart = (_) => _resetRoundUi();
      // Auto-grab feedback: proximity pickup happens in checkItemPickups
      // (host-validated); here we only toast what the host confirmed.
      client.onItemCollected = (itemId, by) {
        if (by != client.selfPubkey) return;
        final item = client.roundItems.firstWhere(
          (it) => it.id == itemId,
          orElse: () => ItemData(id: itemId, type: 'item', lat: 0, lng: 0),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Picked up ${itemDefOf(item.type).name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      };
    } else {
      // Debug/Setup-Test path without a room client.
      for (final p in widget.players) {
        _playersByPubkey[p.name] = p;
      }
      _user = widget.players.isNotEmpty ? widget.players.first : null;
    }

    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _updateLocation();
    });
    // Drive item-effect countdown banners (1 s ticks only while effects
    // are on screen).
    _effectTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final before = _effects.length;
      _effects.removeWhere((e) => e.endsAt.isBefore(DateTime.now()));
      if (_effects.isNotEmpty || _effects.length != before) setState(() {});
    });
    // Batch-render incoming locations instead of setState per packet.
    _renderTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
    // Host prunes stale players and rebroadcasts roster; players prune locally.
    _rosterTickTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      GameManager.roomClient?.tick();
    });
  }

  void _syncRoster() {
    final client = GameManager.roomClient;
    if (client == null) return;
    final current = client.playerPubkeys;
    // Removed players
    _playersByPubkey.removeWhere(
      (pk, _) => !current.containsKey(pk) && pk != client.selfPubkey,
    );
    // New players
    var i = _playersByPubkey.length;
    for (final entry in current.entries) {
      if (!_playersByPubkey.containsKey(entry.key)) {
        _playersByPubkey[entry.key] = Player(
          name: entry.value,
          color: _palette[i++ % _palette.length],
          positionHistory: [],
          currentPosition: widget.playAreaCenter,
        );
      }
    }
    _user = _playersByPubkey[client.selfPubkey] ?? _user;
  }

  Future<void> _updateLocation() async {
    try {
      final client = GameManager.roomClient;
      final position = await geolocatorService.getCurrentLocation();
      client?.sendLocation(position.latitude, position.longitude);
      client?.checkItemPickups(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _user?.updatePosition(position);
          _user?.revealPosition();
          _user?.revealPositionHistory();
          _loading = false;
        });

        if (_followUser) {
          _animatedMapMove(_currentPosition, null);
        }
      }
    } catch (e) {
      debugPrint("Fehler beim Abrufen des Standorts: $e");
    }
  }

  void _animatedMapMove(LatLng destLocation, double? destZoom) {
    // ... (rest of the _animatedMapMove method remains the same)
  }

  @override
  void dispose() {
    _locationUpdateTimer.cancel();
    _renderTimer.cancel();
    _rosterTickTimer.cancel();
    _effectTickTimer.cancel();
    _talkPulse.dispose();
    GameManager.roomClient?.onItemCollected = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // After the round: draw every player's walked route from the trails
    // their location events carried (works for late joiners too).
    if (_client != null && !_roundActive) {
      for (final entry in _playersByPubkey.entries) {
        entry.value.shownPositionHistory =
            _client!.trailOf(entry.key).map((p) => LatLng(p[0], p[1])).toList();
      }
    }
    // Markers: own always; other players hidden during the round —
    // revealed when it ends.
    // Dark-hunt visibility: while the round runs the map shows NO hider
    // data outside the 50 m eyes-radius; a jam hides everything but self.
    final players =
        _playersByPubkey.entries
            .where((e) {
              if (_client == null) return true; // debug path
              if (e.key == _client!.selfPubkey) return true;
              if (!_roundActive) return true;
              if (_jammed) return false;
              return _client!.isHider(e.key) && _withinEyes(e.value.shownPosition);
            })
            .map((e) => e.value)
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_roundActive ? _countdownLabel() : 'Round over'),
        actions: [
          if (_client != null && _client!.host && _roundActive)
            IconButton(
              tooltip: 'End round now',
              icon: Icon(Icons.stop_circle_outlined),
              onPressed:
                  () => _client!.publishRoundEnd(
                    _client!.caughtHiders.length >=
                                _client!.hiderPubkeys.length &&
                            _client!.hiderPubkeys.isNotEmpty
                        ? 'chasers'
                        : 'hiders',
                  ),
            ),
          if (_client != null && _client!.host && !_roundActive)
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => HostSettingsScreen(
                          playAreaCenter: widget.playAreaCenter,
                          playareaRadius: widget.playareaRadius,
                        ),
                  ),
                );
              },
              child: Text(
                'Next round',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          if (_client != null && !_client!.host)
            IconButton(
              tooltip: 'Leave game',
              icon: Icon(Icons.logout),
              onPressed: () async {
                final leave = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Leave game?'),
                    content: const Text(
                      'You will drop out of the room and this round.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Stay'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                );
                if (leave != true) return;
                if (!context.mounted) return;
                _client!.sendLeave();
                GameManager.removeAllData();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => MainScreen()),
                  (route) => false,
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
              setState(() {
                _followUser = false;
              });
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 16,
                maxZoom: 19.6,
                minZoom: 4.0,
                onTap: (_, point) {
                  if (_dronePlacement != null) {
                    setState(() => _dronePlacement = point);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: CircleGenerator.generateCircle(
                        widget.playAreaCenter,
                        widget.playareaRadius.toDouble(),
                      ),
                      strokeWidth: 8.0,
                      color: Colors.red,
                    ),
                  ],
                ),
                // Drone zone preview while aiming (75 m per items_v1).
                if (_dronePlacement != null) ...[
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: CircleGenerator.generateCircle(
                          _dronePlacement!,
                          75.0,
                        ),
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderColor: Colors.amber,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                ],
                // Trails — recorded live, but only drawn once the round is
                // over (live trails would expose the hiders). Filter chips
                // in the bottom bar toggle each player's trail.
                ..._playersByPubkey.entries
                    .where(
                      (e) => !_roundActive && !_trailHidden.contains(e.key),
                    )
                    .map((entry) {
                      final player = entry.value;
                      return PolylineLayer(
                        polylines: [
                          if (player.shownPositionHistory.length > 1 &&
                              player.trailVisible)
                            Polyline(
                              points: player.shownPositionHistory,
                              strokeWidth: 5.0,
                              color: player.color,
                            ),
                        ],
                      );
                    })
                    .toList(),
                // Player markers
                MarkerLayer(
                  markers:
                      players.map((player) {
                        return Marker(
                          point: player.shownPosition,
                          width: 200,
                          height: 114,
                          alignment: Alignment(0, -0.75),
                          rotate: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: player == _user
                                      ? OcColors.primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 3,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  player == _user ? 'You' : player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: player == _user
                                        ? OcColors.onPrimary
                                        : Colors.black,
                                  ),
                                ),
                              ),
                              SizedBox(height: 5),
                              GestureDetector(
                                onTap: () {
                                  _animatedMapMove(player.shownPosition, 17.0);
                                },
                                child:
                                    player.isMrX
                                        ? Image.asset(
                                          'images/mrx.png',
                                          width: 75,
                                          height: 68,
                                        )
                                        : Icon(
                                          Icons.location_on_rounded,
                                          color: player.color,
                                          size: 75,
                                        ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                ),
                // Item markers for the live round; collected items vanish
                // (who grabbed it is kept in client state for future
                // item-effect wiring, not shown).
                MarkerLayer(
                  markers:
                      (GameManager.roomClient?.roundItems ?? const <ItemData>[])
                          .where(
                            (it) =>
                                GameManager.roomClient?.collectorOf(it.id) ==
                                null,
                          )
                          .map(
                            (it) => Marker(
                              point: LatLng(it.lat, it.lng),
                              width: 50,
                              height: 50,
                              child: Image.asset(
                                'images/test-item.png',
                                width: 44,
                                height: 44,
                              ),
                            ),
                          )
                          .toList(),
                ),
                // Meeting point once the round is over: the play-area center.
                if (_client != null && !_roundActive)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: widget.playAreaCenter,
                        width: 90,
                        height: 90,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'MEET HERE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[900],
                              ),
                            ),
                            Icon(Icons.flag, size: 40, color: Colors.indigo),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_loading) Center(child: CircularProgressIndicator()),
          if (SimLocation.enabled)
            Positioned(
              left: 8,
              bottom: 78,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade700.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SIM GPS - WASD moves, Shift fast',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          // Round-over banner: winner + catch tally.
          if (_client != null && !_roundActive)
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _roundOverLabel(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          // Google Maps-style floating roster (top right): who is playing;
          // hiders get a gold eye-off tag.
          if (_client != null)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 190,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: OcColors.card.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(OcColors.radius),
                  border: Border.all(color: OcColors.border),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 8),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Playing — ${_playersByPubkey.length}',
                      style: const TextStyle(
                        color: OcColors.fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final entry in _playersByPubkey.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: entry.value.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                entry.value.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: OcColors.fg,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (_client!.isHider(entry.key)) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.visibility_off,
                                size: 14,
                                color: OcColors.gold,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Effect countdown banners: stacked top-center under the AppBar
          // (round timer stays in the AppBar title, both fit).
          if (_effects.isNotEmpty)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in _effects)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: rarityColor(e.def.rarity)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(e.def.icon, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              '${e.label}  ${_mmss(e.endsAt)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Drone zone aiming controls (circle preview follows map taps).
          if (_dronePlacement != null)
            Positioned(
              bottom: 96,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Tap map to place the 75 m zone',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(80, 34),
                        ),
                        onPressed: () {
                          final def = itemDefOf('drone');
                          setState(() => _dronePlacement = null);
                          _startEffect(def);
                        },
                        child: const Text('Confirm'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        onPressed: () =>
                            setState(() => _dronePlacement = null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Item bank row (bottom center): one chip per held item, rarity
          // badge per chip. Jam greys the row and blocks taps.
          if (_client != null && (_bank.isNotEmpty || _talkItemId != null))
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(
                child: IgnorePointer(
                  ignoring: _jammed,
                  child: AnimatedOpacity(
                    opacity: _jammed ? 0.35 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_talkItemId != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onLongPressStart: (_) =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Hold-to-talk placeholder — voice '
                                          'transport pending (backend)',
                                        ),
                                      ),
                                    ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius: BorderRadius.circular(
                                      OcColors.radius,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.mic,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Hold to talk — $_talkPeerName',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                ),
                                onPressed: _endTalk,
                                child: const Text('End'),
                              ),
                            ],
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: OcColors.card.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(OcColors.radius),
                            border: Border.all(color: OcColors.border),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 8),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final it in _bank)
                                Builder(
                                  builder: (context) {
                                    final def = itemDefOf(it.type);
                                    final onAir = _talkItemId == it.id;
                                    return GestureDetector(
                                      onTap: () => _useItem(it),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: OcColors.field,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: onAir
                                                ? Colors.red
                                                : rarityColor(def.rarity),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (onAir)
                                              AnimatedBuilder(
                                                animation: _talkPulse,
                                                builder: (context, _) =>
                                                    Container(
                                                      width: 22,
                                                      height: 22,
                                                      margin: const EdgeInsets
                                                          .symmetric(vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red
                                                            .withValues(
                                                              alpha: 0.4 +
                                                                  0.6 *
                                                                      _talkPulse
                                                                          .value,
                                                            ),
                                                        shape: BoxShape.circle,
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color: Colors
                                                                .redAccent,
                                                            blurRadius: 8,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                              )
                                            else
                                              Icon(
                                                def.icon,
                                                color: rarityColor(def.rarity),
                                                size: 22,
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    color: rarityColor(
                                                      def.rarity,
                                                    ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  def.name,
                                                  style: const TextStyle(
                                                    color: OcColors.fg,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // JAMMED overlay for jammed seekers — a loud "you see nothing",
          // not a silently broken map.
          if (_jammed)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'JAMMED',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Map and items offline  ${_mmss(_jamEnd)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton:
          (_client != null &&
                  _roundActive &&
                  _client!.isHider(_client!.selfPubkey) &&
                  !_client!.isCaught(_client!.selfPubkey))
              ? FloatingActionButton.extended(
                backgroundColor: Colors.red,
                onPressed: () => _client!.sendCaught(),
                icon: Icon(Icons.flag),
                label: Text("I'm caught!"),
              )
              : FloatingActionButton(
                onPressed: () {
                  setState(() {
                    _followUser = true;
                  });
                  _animatedMapMove(_currentPosition, null);
                  _rotateMapBackToNorth();
                },
                child: Icon(Icons.my_location),
              ),
      bottomNavigationBar: (_client != null && !_roundActive)
          ? BottomAppBar(
              color: Colors.blueGrey[900],
              shape: CircularNotchedRectangle(),
              child: Container(
                height: 60,
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Trail filter chips — every player's route shows in
                    // their color, toggleable here.
                    for (final entry in _playersByPubkey.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, top: 8),
                        child: ChoiceChip(
                          label: Text(
                            entry.value.name,
                            style: TextStyle(color: entry.value.color),
                          ),
                          selected: !_trailHidden.contains(entry.key),
                          onSelected: (_) {
                            setState(() {
                              if (_trailHidden.contains(entry.key)) {
                                _trailHidden.remove(entry.key);
                              } else {
                                _trailHidden.add(entry.key);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // Map rotation animation to North
  void _rotateMapBackToNorth() {
    _mapController.rotate(0);
  }
}
