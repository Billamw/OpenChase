import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:openchase/map.dart';
import 'package:openchase/theme.dart';
import 'package:openchase/utils/game_manager.dart';

/// Host picks round settings after the play area is set:
/// duration + hiders. Placement of items comes next.
class HostSettingsScreen extends StatefulWidget {
  final LatLng playAreaCenter;
  final int playareaRadius;

  const HostSettingsScreen({
    super.key,
    required this.playAreaCenter,
    required this.playareaRadius,
  });

  /// Hiders must stay a minority: at most (n-1)/2 of the roster.
  static int maxHiders(int n) => max(1, (n - 1) ~/ 2);

  @override
  State<HostSettingsScreen> createState() => _HostSettingsScreenState();
}

enum HiderPickMode { random, manual }

class _HostSettingsScreenState extends State<HostSettingsScreen> {
  HiderPickMode _mode = HiderPickMode.random;

  int get _maxHiders => HostSettingsScreen.maxHiders(
    GameManager.roomClient?.playerPubkeys.length ?? 0,
  );

  /// Random mode always fills up to the cap.
  void _assignRandomRoster() {
    final pks = (GameManager.roomClient?.playerPubkeys.keys ?? const <String>[]).toList()..shuffle();
    GameManager.roundHiders = pks
        .take(HostSettingsScreen.maxHiders(pks.length))
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final client = GameManager.roomClient;
    final roster = client?.playerPubkeys ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Round settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Round duration'),
              trailing: DropdownButton<int>(
                value: GameManager.roundDurationMin,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                  DropdownMenuItem(value: 45, child: Text('45 min')),
                  DropdownMenuItem(value: 60, child: Text('60 min')),
                  DropdownMenuItem(value: 90, child: Text('90 min')),
                ],
                onChanged: (v) =>
                    setState(() => GameManager.roundDurationMin = v ?? 30),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt),
                      const SizedBox(width: 8),
                      Text(
                        'Items',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Density', style: TextStyle(color: OcColors.mutedFg)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'less', label: Text('Less')),
                      ButtonSegment(value: 'normal', label: Text('Normal')),
                      ButtonSegment(value: 'more', label: Text('More')),
                    ],
                    selected: {GameManager.roundDensity},
                    onSelectionChanged: (s) => setState(
                      () => GameManager.roundDensity = s.first,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Item bank cap — ${GameManager.roundBankCap}',
                    style: TextStyle(color: OcColors.mutedFg),
                  ),
                  Slider(
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${GameManager.roundBankCap}',
                    value: GameManager.roundBankCap.toDouble(),
                    onChanged: (v) => setState(
                      () => GameManager.roundBankCap = v.round(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_3_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Head start (hiders flee first)',
                          style: TextStyle(color: OcColors.mutedFg),
                        ),
                      ),
                      DropdownButton<int>(
                        value: GameManager.roundHeadStartMin,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('None')),
                          DropdownMenuItem(value: 3, child: Text('3 min')),
                          DropdownMenuItem(value: 5, child: Text('5 min')),
                          DropdownMenuItem(value: 10, child: Text('10 min')),
                        ],
                        onChanged: (v) => setState(
                          () => GameManager.roundHeadStartMin = v ?? 5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.visibility_off_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Hiders',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      if (_mode == HiderPickMode.manual)
                        Chip(
                          label: Text(
                            '${GameManager.roundHiders.length} / $_maxHiders',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<HiderPickMode>(
                    segments: const [
                      ButtonSegment(
                        value: HiderPickMode.random,
                        label: Text('Random'),
                        icon: Icon(Icons.shuffle, size: 18),
                      ),
                      ButtonSegment(
                        value: HiderPickMode.manual,
                        label: Text('Manual'),
                        icon: Icon(Icons.touch_app, size: 18),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _mode == HiderPickMode.random
                        ? 'Hiders are picked at random each round, then '
                              'revealed at round end. Fewer hiders than chasers.'
                        : 'Tap players to hide them. '
                              'Max $_maxHiders — fewer than chasers.',
                    style: const TextStyle(color: OcColors.mutedFg),
                  ),
                  if (_mode == HiderPickMode.manual) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in roster.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: GameManager.roundHiders.contains(
                              entry.key,
                            ),
                            onSelected: (selected) {
                              if (selected &&
                                  GameManager.roundHiders.length >=
                                      _maxHiders) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Hiders must stay fewer than chasers',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                if (selected) {
                                  GameManager.roundHiders.add(entry.key);
                                } else {
                                  GameManager.roundHiders.remove(entry.key);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (_mode == HiderPickMode.random) {
                _assignRandomRoster();
              } else if (GameManager.roundHiders.isEmpty ||
                  GameManager.roundHiders.length > _maxHiders) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Pick 1-$_maxHiders hiders (or switch to Random)',
                    ),
                  ),
                );
                return;
              }
              // Host publishes the round: area + hiders go out over the
              // room channel; players auto-navigate.
              final client = GameManager.roomClient;
              GameManager.roundCenter = widget.playAreaCenter;
              GameManager.roundRadius = widget.playareaRadius;
              client?.publishRoundStart(
                center: [
                  widget.playAreaCenter.latitude,
                  widget.playAreaCenter.longitude,
                ],
                radiusM: widget.playareaRadius,
                durationSec: GameManager.roundDurationMin * 60,
                hiders: GameManager.roundHiders.toList(),
                items: const [],
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MapScreen(
                    players: const [],
                    playAreaCenter: widget.playAreaCenter,
                    playareaRadius: widget.playareaRadius,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start game'),
          ),
        ],
      ),
    );
  }
}
