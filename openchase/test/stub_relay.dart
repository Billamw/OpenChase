import 'dart:convert';
import 'dart:io';

/// Minimal nostr relay for tests: speaks REQ/EVENT/EOSE with authors/kinds/
/// since filters, stores events for replay on new subscriptions, and
/// broadcasts accepted events to matching subs of *other* sockets (relays
/// never echo to the publishing connection, per NIP-01).
class StubRelay {
  late HttpServer _server;
  final List<_Sub> _allSubs = [];
  final List<Map<String, dynamic>> _stored = [];

  static Future<StubRelay> start() async {
    final r = StubRelay();
    r._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    r._serve();
    return r;
  }

  String get url => 'ws://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

  void _serve() {
    _server.transform(WebSocketTransformer()).listen((ws) {
      ws.listen(
        (raw) {
          dynamic msg;
          try {
            msg = jsonDecode(raw.toString());
          } catch (_) {
            return;
          }
          if (msg is! List || msg.isEmpty) return;
          switch (msg[0]) {
            case 'REQ':
              final subId = msg[1] as String;
              for (final f in msg.skip(2)) {
                final filter = Map<String, dynamic>.from(f as Map);
                _allSubs.add(_Sub(ws, subId, filter));
                // replay stored events like real relays do
                for (final ev in _stored) {
                  if (_matches(filter, ev)) {
                    ws.add(jsonEncode(['EVENT', subId, ev]));
                  }
                }
              }
              ws.add(jsonEncode(['EOSE', subId]));
            case 'EVENT':
              final ev = msg[1];
              if (ev is! Map) return;
              _stored.add(Map<String, dynamic>.from(ev));
              _allSubs.removeWhere(
                (s) => s.socket.readyState != WebSocket.open,
              );
              for (final s in _allSubs.toList()) {
                if (s.socket != ws && _matches(s.filter, ev)) {
                  s.socket.add(jsonEncode(['EVENT', s.subId, ev]));
                }
              }
              ws.add(jsonEncode(['OK', ev['id'], '', true, '']));
          }
        },
        onDone: () {
          _allSubs.removeWhere((s) => s.socket == ws);
        },
      );
    });
  }

  bool _matches(Map<String, dynamic> f, dynamic ev) {
    if (ev is! Map) return false;
    final since = f['since'];
    if (since is int && (ev['created_at'] as int) < since) return false;
    final kinds = f['kinds'];
    if (kinds is List && !kinds.contains(ev['kind'])) return false;
    final authors = f['authors'];
    if (authors is List && !authors.contains(ev['pubkey'])) return false;
    return true;
  }
}

class _Sub {
  final WebSocket socket;
  final String subId;
  final Map<String, dynamic> filter;
  _Sub(this.socket, this.subId, this.filter);
}
