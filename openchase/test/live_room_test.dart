@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:openchase/utils/protocol/room_client.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/protocol/room_models.dart';
import 'stub_relay.dart';

/// End-to-end protocol exercise. Deterministic by default (stub relay);
/// against the real network with --dart-define=RELAYS=wss://relay.damus.io
const _relaysEnv = String.fromEnvironment('RELAYS');

void main() {
  test(
    'host+player: join, roster, roundStart, location exchange over relays',
    () async {
      StubRelay? stub;
      List<String> relays;
      if (_relaysEnv.isEmpty) {
        stub = await StubRelay.start();
        addTearDown(stub.stop);
        relays = [stub.url];
      } else {
        relays = _relaysEnv.split(',');
      }
      // ignore: avoid_print
      print('using relays: $relays');
      final code = RoomKeys.randomRoomCode();
      // ignore: avoid_print
      print('live room code: $code');

      final host = RoomClient(
        host: true,
        roomKeys: RoomKeys.fromCode(code),
        playerName: 'Hostus',
        relays: relays,
        onRosterChanged: () {},
      );
      await _wait(() => host.readyRelays >= 1, 15, 'host relay connect');
      host.publishRoomInit();

      final player = RoomClient(
        host: false,
        roomKeys: RoomKeys.fromCode(code),
        playerName: 'Peer',
        relays: relays,
        onRosterChanged: () {},
      );
      await _wait(() => player.readyRelays >= 1, 15, 'player relay connect');

      final hostName = await player.findRoom(const Duration(seconds: 8));
      expect(hostName, 'Hostus', reason: 'room_init not resolved by player');

      player.sendJoin('Peer');

      await _wait(
        () => host.playerNames.contains('Peer'),
        20,
        'host roster contains Peer (got: ${host.playerNames})',
      );
      await _wait(
        () =>
            player.playerNames.contains('Peer') &&
            player.playerNames.contains('Hostus'),
        20,
        'player got roster snapshot (got: ${player.playerNames})',
      );

      RoundStartData? seenRound;
      player.onRoundStart = (r) => seenRound = r;
      host.publishRoundStart(center: [50.94, 6.96], radiusM: 750, items: [
        [50.941, 6.961],
      ]);
      await _wait(() => seenRound != null, 20, 'player saw round_start');
      expect(seenRound!.radiusM, 750);

      final hostGotLoc = <String, LocationData>{};
      final playerGotLoc = <String, LocationData>{};
      host.onLocation = (pk, loc) => hostGotLoc[pk] = loc;
      player.onLocation = (pk, loc) => playerGotLoc[pk] = loc;

      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline) &&
          (hostGotLoc.isEmpty || playerGotLoc.isEmpty)) {
        final jitter =
            (DateTime.now().millisecondsSinceEpoch % 10000) / 100000.0;
        player.sendLocation(50.93 + jitter, 6.95);
        host.sendLocation(50.92, 6.97 + jitter);
        await Future.delayed(const Duration(seconds: 3));
      }
      expect(
        hostGotLoc.containsKey(player.selfPubkey),
        isTrue,
        reason: 'host never got player location (got: ${hostGotLoc.keys})',
      );
      expect(
        playerGotLoc.containsKey(host.selfPubkey),
        isTrue,
        reason: 'player never got host location (got: ${playerGotLoc.keys})',
      );

      // Item pickup loop: player walks onto i0, claims it automatically,
      // host validates against its stream, both sides converge on collected.
      final item = seenRound!.items.first;
      expect(item.id, 'i0');
      expect(item.type, 'item');
      await Future.delayed(const Duration(milliseconds: 1100)); // fresh ts
      player.sendLocation(item.lat, item.lng);
      await _wait(
        () => host.lastLocations[player.selfPubkey]?.lat == item.lat,
        15,
        'host sees player standing on the item',
      );
      player.checkItemPickups(item.lat, item.lng);
      await _wait(
        () => player.collectorOf('i0') != null,
        15,
        'player sees i0 collected',
      );
      expect(player.collectorOf('i0'), player.selfPubkey);
      expect(host.collectorOf('i0'), player.selfPubkey);
      // Collected item is not claimable again.
      player.checkItemPickups(item.lat, item.lng);
      host.checkItemPickups(item.lat, item.lng);
      await Future.delayed(const Duration(seconds: 1));
      expect(host.collectorOf('i0'), player.selfPubkey);

      host.close();
      player.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _wait(bool Function() cond, int seconds, String what) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('timeout waiting for: $what');
}
