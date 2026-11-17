@Tags(['live'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Policy probe: for each candidate relay, check custom-kind (20005)
/// acceptance/echo and OK responses.
void main() {
  test('relay policy matrix', () async {
    for (final relay in [
      'wss://relay.mutinywallet.com',
      'wss://relay.0xchat.com',
      
      
      
      'wss://relay.damus.io',
    ]) {
      // ignore: avoid_print
      print('===== $relay =====');
      try {
        final ws = WebSocketChannel.connect(Uri.parse(relay));
        await ws.ready.timeout(const Duration(seconds: 8));
        final keys = Keychain.generate();
        final seen = <String>{};

        ws.stream.listen(
          (raw) {
            final s = raw.toString();
            try {
              final d = jsonDecode(s);
              if (d is! List) return;
              if (d[0] == 'OK') {
                // ignore: avoid_print
                print('OK accepted=${d[3]} msg=${d.length > 4 ? d[4] : ''}');
              } else if (d[0] == 'EVENT') {
                final id = (d[2] as Map)['id'] as String;
                // ignore: avoid_print
                print('EVENT kind=${(d[2] as Map)['kind']}');
                seen.add(id);
              }
            } catch (_) {}
          },
          onError: (_) {},
          cancelOnError: false,
        );

        final since = currentUnixTimestampSeconds() - 30;
        ws.sink.add('["REQ","a",{"kinds":[20005],"since":$since}]');
        await Future.delayed(const Duration(seconds: 1));

        final ev = Event.from(
          kind: 20005,
          content: '{"msg":"probe"}',
          privkey: keys.private,
        );
        ws.sink.add(ev.serialize());
        await Future.delayed(const Duration(seconds: 5));
        try {
          ws.sink.close();
        } catch (_) {}
        // ignore: avoid_print
        print('echo=${seen.contains(ev.id)}');
      } catch (e) {
        // ignore: avoid_print
        print('CONNECT FAIL: $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
