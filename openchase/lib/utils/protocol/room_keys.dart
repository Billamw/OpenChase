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
    // 5 letters, ambiguous glyphs (I/O) excluded for verbal sharing
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    return List.generate(5, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }
}
