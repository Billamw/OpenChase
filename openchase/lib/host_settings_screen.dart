import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:openchase/setup_items_map.dart';
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

class _HostSettingsScreenState extends State<HostSettingsScreen> {
  int get _maxHiders => HostSettingsScreen.maxHiders(
    GameManager.roomClient?.playerPubkeys.length ?? 0,
  );

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
                      const Icon(Icons.visibility_off_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Hiders — pick 0-$_maxHiders',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      ActionChip(
                        label: const Text('Random'),
                        avatar: const Icon(Icons.shuffle, size: 16),
                        onPressed: () => setState(() {
                          final pks = roster.keys.toList()..shuffle();
                          GameManager.roundHiders = pks
                              .take(HostSettingsScreen.maxHiders(pks.length))
                              .toSet();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hidden players are revealed at round end. '
                    'Fewer hiders than chasers.',
                    style: const TextStyle(color: OcColors.mutedFg),
                  ),
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
                                GameManager.roundHiders.length >= _maxHiders) {
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
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (GameManager.roundHiders.isEmpty ||
                  GameManager.roundHiders.length > _maxHiders) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Pick 1-$_maxHiders hiders (or press Random)',
                    ),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ItemsTest(
                    playAreaCenter: widget.playAreaCenter,
                    playareaRadius: widget.playareaRadius,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.place_outlined),
            label: const Text('Place items'),
          ),
        ],
      ),
    );
  }
}
