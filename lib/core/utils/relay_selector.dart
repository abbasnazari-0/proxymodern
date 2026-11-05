import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/ad_config.dart';

/// Result of probing one relay.
class RelayProbe {
  const RelayProbe(this.relay, this.latency);

  final RelayConfig relay;

  /// `null` = the relay did not complete the CONNECT tunnel.
  final Duration? latency;

  bool get isReachable => latency != null;
}

/// Measures relays by opening a real CONNECT tunnel to Google's ad host.
///
/// A plain TCP connect is not enough: a relay can accept the socket quickly and
/// still fail to tunnel traffic. The probe therefore performs the same CONNECT
/// handshake the ad SDK will use and requires an HTTP 200 status line.
class RelaySelector {
  RelaySelector({
    this.connectTimeout = const Duration(milliseconds: 2500),
    this.readTimeout = const Duration(milliseconds: 6000),
  });

  static const String targetHost = 'googleads.g.doubleclick.net';
  static const int targetPort = 443;

  final Duration connectTimeout;
  final Duration readTimeout;

  /// Probes every relay in parallel and returns the ranking (fastest first).
  Future<List<RelayProbe>> rank(List<RelayConfig> relays) async {
    final candidates = relays.where((relay) => relay.isValid).toList();
    if (candidates.isEmpty) return const <RelayProbe>[];

    final probes = await Future.wait(
      candidates.map((relay) async => RelayProbe(relay, await measure(relay))),
    );
    final reachable = probes.where((probe) => probe.isReachable).toList()
      ..sort((a, b) => a.latency!.compareTo(b.latency!));
    return List<RelayProbe>.unmodifiable(reachable);
  }

  /// Fastest reachable relay, or `null` when every tunnel failed.
  Future<RelayConfig?> pickFastest(List<RelayConfig> relays) async {
    final ranked = await rank(relays);
    return ranked.isEmpty ? null : ranked.first.relay;
  }

  /// Probes [relay] and returns its latency only when the relay can carry a
  /// real HTTPS request to Google.
  ///
  /// For plain `http` relays this performs the full path the ad SDK uses:
  /// `CONNECT googleads.g.doubleclick.net:443` → TLS handshake → HTTPS
  /// response. This matters because some relays accept CONNECT with `200` and
  /// then immediately close the TLS handshake (`ERR_CONNECTION_CLOSED`); a
  /// status-only probe would pick them and every ad load would fail.
  ///
  /// `https` relays keep the lightweight CONNECT check because Dart's
  /// `HttpClient` proxy support is HTTP-only.
  Future<Duration?> measure(RelayConfig relay) async {
    final uri = relay.uri;
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);

    if (scheme == 'http') {
      final tlsLatency = await _measureHttpProxyTls(relay, uri, port);
      if (tlsLatency != null) return tlsLatency;
      // A sticky relay can reject the plain username used by this probe but
      // still work with the verified `-sid-...` session fetched at start time.
      // Keep it in the ranking instead of declaring every sticky relay dead;
      // the load path will switch away if its TLS really is broken.
      if (relay.isSticky) {
        return _measureConnectStatus(relay, uri, port);
      }
      return null;
    }
    return _measureConnectStatus(relay, uri, port);
  }

  /// Full proxy → CONNECT → TLS → HTTP probe for plain HTTP relays.
  Future<Duration?> _measureHttpProxyTls(
    RelayConfig relay,
    Uri proxy,
    int proxyPort,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = readTimeout
      ..findProxy = ((_) => 'PROXY ${proxy.host}:$proxyPort');
    if (relay.hasCredentials) {
      client.addProxyCredentials(
        proxy.host,
        proxyPort,
        'Basic',
        HttpClientBasicCredentials(relay.proxyUsername, relay.proxyPassword),
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.parse('https://$targetHost/generate_204'))
          .timeout(readTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(readTimeout);
      stopwatch.stop();
      // The 204 body is empty; forcing the client closed in `finally` is
      // enough and avoids waiting on a slow body.
      return response.statusCode > 0 ? stopwatch.elapsed : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// CONNECT-only probe used for `https` relays (TLS to the proxy itself).
  Future<Duration?> _measureConnectStatus(
    RelayConfig relay,
    Uri uri,
    int port,
  ) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      socket = uri.scheme.toLowerCase() == 'https'
          ? await SecureSocket.connect(
              uri.host,
              port,
              timeout: connectTimeout,
            )
          : await Socket.connect(uri.host, port, timeout: connectTimeout);

      final authorization = relay.hasCredentials
          ? base64Encode(
              utf8.encode('${relay.proxyUsername}:${relay.proxyPassword}'),
            )
          : null;
      final request = StringBuffer()
        ..write('CONNECT $targetHost:$targetPort HTTP/1.1\r\n')
        ..write('Host: $targetHost:$targetPort\r\n')
        ..write('User-Agent: proxymodern\r\n')
        ..write('Proxy-Connection: keep-alive\r\n');
      if (authorization != null) {
        request.write('Proxy-Authorization: Basic $authorization\r\n');
      }
      request.write('Connection: close\r\n\r\n');

      socket.write(request.toString());
      await socket.flush();

      final statusLine = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(readTimeout);
      stopwatch.stop();

      final match = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(
        statusLine.trim(),
      );
      if (match == null) return null;
      return int.parse(match.group(1)!) == 200 ? stopwatch.elapsed : null;
    } catch (_) {
      return null;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {
        // Best effort.
      }
    }
  }
}

/// Picks the URL with the lowest latency; exposed for unit tests.
String? pickFastestRelayUrl(List<(String, int?)> probes) {
  String? best;
  int? bestMs;
  for (final (url, ms) in probes) {
    if (ms == null) continue;
    if (bestMs == null || ms < bestMs) {
      best = url;
      bestMs = ms;
    }
  }
  return best;
}
