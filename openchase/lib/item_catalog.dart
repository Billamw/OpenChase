import 'package:flutter/material.dart';

/// Items v1 UI catalog (docs/items_v1.json mirror). UI-only: names, icons,
/// rarity badge colors, and which targeting flow an item opens. Actual
/// effect state must come from host-published events (backend); nothing
/// here enforces gameplay.
enum ItemTargetMode { none, player, hider, zone, position }

class ItemDef {
  final String id;
  final String name;
  final String rarity; // common | uncommon | rare
  final ItemTargetMode target;
  final IconData icon;

  /// Seconds of timed banner after use (0 = instant, no banner).
  final int bannerSec;
  const ItemDef({
    required this.id,
    required this.name,
    required this.rarity,
    required this.target,
    required this.icon,
    this.bannerSec = 0,
  });
}

const Map<String, ItemDef> itemCatalog = {
  'reveal': ItemDef(
    id: 'reveal',
    name: 'Reveal',
    rarity: 'rare',
    target: ItemTargetMode.hider,
    icon: Icons.visibility,
    bannerSec: 30,
  ),
  'found_clue': ItemDef(
    id: 'found_clue',
    name: 'Found Clue',
    rarity: 'common',
    target: ItemTargetMode.hider,
    icon: Icons.history,
    bannerSec: 0,
  ),
  'radar_pulse': ItemDef(
    id: 'radar_pulse',
    name: 'Radar Pulse',
    rarity: 'common',
    target: ItemTargetMode.none,
    icon: Icons.radar,
    bannerSec: 0,
  ),
  'proof_of_life': ItemDef(
    id: 'proof_of_life',
    name: 'Proof of Life',
    rarity: 'common',
    target: ItemTargetMode.none,
    icon: Icons.network_check,
    bannerSec: 0,
  ),
  'drone': ItemDef(
    id: 'drone',
    name: 'Drone',
    rarity: 'rare',
    target: ItemTargetMode.zone,
    icon: Icons.flight,
    bannerSec: 60,
  ),
  'trapwire': ItemDef(
    id: 'trapwire',
    name: 'Trapwire',
    rarity: 'rare',
    target: ItemTargetMode.position,
    icon: Icons.sensors,
    bannerSec: 0,
  ),
  'decoy': ItemDef(
    id: 'decoy',
    name: 'Decoy',
    rarity: 'uncommon',
    target: ItemTargetMode.none,
    icon: Icons.content_copy,
    bannerSec: 120,
  ),
  'disturber': ItemDef(
    id: 'disturber',
    name: 'Disturber',
    rarity: 'rare',
    target: ItemTargetMode.none,
    icon: Icons.campaign,
    bannerSec: 30,
  ),
  'clock_plus': ItemDef(
    id: 'clock_plus',
    name: 'Clock +',
    rarity: 'uncommon',
    target: ItemTargetMode.none,
    icon: Icons.more_time,
    bannerSec: 0,
  ),
  'clock_minus': ItemDef(
    id: 'clock_minus',
    name: 'Clock -',
    rarity: 'uncommon',
    target: ItemTargetMode.none,
    icon: Icons.timer_off,
    bannerSec: 0,
  ),
  'walky_talky': ItemDef(
    id: 'walky_talky',
    name: 'Walky Talky',
    rarity: 'uncommon',
    target: ItemTargetMode.player,
    icon: Icons.wifi_tethering,
    bannerSec: 0,
  ),
};

/// Fallback for item types the host publishes that the catalog doesn't know.
ItemDef itemDefOf(String type) =>
    itemCatalog[type] ??
    ItemDef(
      id: type,
      name: type,
      rarity: 'common',
      target: ItemTargetMode.none,
      icon: Icons.redeem,
    );

/// Rarity badge colors per spec: common grey / uncommon blue / rare purple.
Color rarityColor(String rarity) => switch (rarity) {
  'uncommon' => const Color(0xFF3B82F6),
  'rare' => const Color(0xFFA855F7),
  _ => const Color(0xFF9CA3AF),
};

/// A running timed effect shown as a countdown banner. Placeholder
/// carrier: real instances must be built from host-published events.
class ActiveEffect {
  final ItemDef def;
  final String label;
  final DateTime endsAt;
  const ActiveEffect({
    required this.def,
    required this.label,
    required this.endsAt,
  });
}
