import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'package:openchase/utils/protocol/room_models.dart';

/// Minimal multi-relay nostr transport: connects to N relays, routes parsed
/// room events to one handler, dedupes across relays by event id, and
/// re-sends subscriptions when a relay (re)connects.
class RoomTransport {
  final List<String> relays;
  final void Function(RoomEvent event) onEvent;
  final void Function(int ready, int total)? onRelayReady;

  final Map<String, WebSocketChannel> _sockets = {};
  final Map<String, String> _filters =
      {}; // logical key -> REQ json (id slot empty)
  final Set<String> _seenEventIds = {};
  final List<Timer> _retryTimers = [];
  final Map<String, int> _retryAttempt = {};
  static final Random _rnd = Random();
  int _readyCount = 0;
  bool _closed = false;

  RoomTransport({
    required this.relays,
    required this.onEvent,
    this.onRelayReady,
  });

  int get readyRelays => _readyCount;

  void connect() {
    for (final relay in relays) {
      unawaited(_connectRelay(relay));
    }
  }

  Future<void> _connectRelay(String relay) async {
    if (_closed) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(relay));
      await channel.ready;
      _sockets[relay] = channel;
      _retryAttempt[relay] = 0;
      channel.stream.listen(
        (raw) => _handleFrame(raw),
        onDone: () => _scheduleRetry(relay),
        onError: (_) => _scheduleRetry(relay),
        cancelOnError: true,
      );
      // Re-send all live subscriptions with a unique sub id on this connection.
      for (final entry in _filters.entries) {
        channel.sink.add(_withSubId(entry.value, _newSubId()));
      }
      _readyCount++;
      onRelayReady?.call(_readyCount, relays.length);
    } catch (_) {
      _scheduleRetry(relay);
    }
  }

  void _scheduleRetry(String relay) {
    if (_closed) return;
    _sockets.remove(relay);
    _readyCount = _sockets.length;
    final attempt = (_retryAttempt[relay] ?? 0) + 1;
    _retryAttempt[relay] = attempt;
    final delay = Duration(
      milliseconds: min(5000, 250 * (1 << min(attempt, 4))),
    );
    final timer = Timer(delay, () => _connectRelay(relay));
    _retryTimers.add(timer);
  }

  static String _newSubId() =>
      'oc${_rnd.nextInt(0x7fffffff).toRadixString(16)}';

  String _withSubId(String reqJson, String subId) {
    final decoded = jsonDecode(reqJson) as List;
    decoded[1] = subId;
    return jsonEncode(decoded);
  }

  void _handleFrame(dynamic raw) {
    if (raw is! String) return;
    final event = RoomEvent.tryParse(raw);
    if (event == null) return;
    if (!_seenEventIds.add(event.id)) return; // cross-relay / replay dedupe
    if (_seenEventIds.length > 8000) {
      _seenEventIds.removeWhere(
        (_) => true,
      ); // coarse reset; dedupe is best-effort
    }
    onEvent(event);
  }

  /// Subscribe with filter maps (plain nostr filter JSON). Same key replaces.
  void subscribe(String key, List<Map<String, dynamic>> filters) {
    _filters[key] = jsonEncode(['REQ', '', ...filters]);
    for (final channel in _sockets.values) {
      channel.sink.add(_withSubId(_filters[key]!, _newSubId()));
    }
  }

  void publish(String serializedEvent) {
    for (final channel in _sockets.values) {
      channel.sink.add(serializedEvent);
    }
  }

  void close() {
    _closed = true;
    for (final t in _retryTimers) {
      t.cancel();
    }
    _retryTimers.clear();
    final sockets = Map.of(_sockets);
    _sockets.clear();
    _readyCount = 0;
    for (final channel in sockets.values) {
      channel.sink.close(ws_status.normalClosure);
    }
  }
}
