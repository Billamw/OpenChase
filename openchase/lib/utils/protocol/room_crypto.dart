// ignore_for_file: implementation_imports

import 'package:nostr/src/crypto/nip_004.dart' show nip4cipher;

/// Targeted-publish encryption (hunt visibility policy): the host rebroadcasts
/// a hider's position to a single seeker as a normal relay event whose content
/// is ECDH-encrypted under the *seeker's session pubkey* (NIP-04 style:
/// secp256k1 shared secret -> AES-256-CBC, content `b64?iv=b64`). Only the
/// seeker's session key can open it; other players see an opaque blob.
class RoomCrypto {
  /// Encrypt [jsonPayload] so only [receiverPubkey] (a session pubkey) can
  /// decrypt it. [senderPrivkey] is the authoring session key (host player).
  static String encryptFor(String senderPrivkey, String receiverPubkey, String jsonPayload) =>
      nip4cipher(senderPrivkey, '02$receiverPubkey', jsonPayload, true);

  /// Decrypt an event authored by [senderPubkey] using our [ourPrivkey].
  /// Returns null for anything not decryptable with this key.
  static String? decrypt(String ourPrivkey, String senderPubkey, String content) {
    final parts = content.split('?iv=');
    if (parts.length != 2) return null;
    try {
      return nip4cipher(ourPrivkey, '02$senderPubkey', parts[0], false, nonce: parts[1]);
    } catch (_) {
      return null;
    }
  }
}
