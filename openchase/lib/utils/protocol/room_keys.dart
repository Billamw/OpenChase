import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:nostr/nostr.dart';

/// Deterministic room identity from the 4-letter share code: everyone who
/// knows the code derives the same room keypair, so joining needs only the
/// code (no key exchange). This matches the trust model of the share-out code:
/// anyone with the code is considered room-trusted.
class RoomKeys {
  final String code; // 4 uppercase letters
  final Keychain roomKeychain;

  RoomKeys._(this.code, this.roomKeychain);

  factory RoomKeys.fromCode(String code) {
    final normalized = code.trim().toUpperCase();
    final digest = sha256.convert(utf8.encode('openchase-room-v0:$normalized'));
    return RoomKeys._(normalized, Keychain(digest.toString()));
  }

  String get roomPubkey => roomKeychain.public;
  String get roomPrivkey => roomKeychain.private;

  static final Random _rnd = Random.secure();

  /// Per-session player keypair. A client that stays in one room keeps this
  /// stable across reconnects (identity = pubkey).
  static Keychain generatePlayerKeychain() => Keychain.generate();

  static String randomRoomCode() {
    // Ambiguous glyphs (O/0, I/1) excluded is cosmetic here: alphabet-only
    // keeps the existing 4-letter UX intact.
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return List.generate(4, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }
}
