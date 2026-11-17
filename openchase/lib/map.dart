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
import 'package:openchase/setup_items_map.dart';
import 'package:openchase/main_screen.dart';

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

  void _resetRoundUi() {
    for (final p in _playersByPubkey.values) {
      p.positionHistory.clear();
      p.shownPositionHistory = [];
      p.trailVisible = true;
    }
    _trailHidden.clear();
    _followUser = true;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
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
    final players =
        _playersByPubkey.entries
            .where((e) {
              if (_client == null) return true; // debug path
              if (e.key == _client!.selfPubkey) return true;
              return !_roundActive;
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
                        (context) => ItemsTest(
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
              onPressed: () {
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
                                  color: Colors.white,
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
                                  player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
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
      bottomNavigationBar: BottomAppBar(
        color: Colors.blueGrey[900],
        shape: CircularNotchedRectangle(),
        child: Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Trail filter chips — live round hides trails; once over,
              // every player's route shows in their color, toggleable here.
              if (_client != null && !_roundActive)
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
                  )
              else if (_client != null)
                Center(
                  child: Text(
                    'Routes appear when the round ends',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Map rotation animation to North
  void _rotateMapBackToNorth() {
    _mapController.rotate(0);
  }
}
