import 'dart:async';
import 'dart:io';

/// A single proxy endpoint to measure.
class PingTarget {
  const PingTarget(this.index, this.host, this.port);

  /// Position of this endpoint in the source list.
  final int index;
  final String host;
  final int port;
}

/// A statistically robust latency measurement for one endpoint.
///
/// Instead of trusting a single connect attempt, [PingService] probes every
/// endpoint several times and reduces the samples into a median latency plus
/// jitter and loss, which is far more accurate and stable.
class PingResult {
  const PingResult({
    this.latency = -1,
    this.min = -1,
    this.max = -1,
    this.avg = -1,
    this.jitter = -1,
    this.loss = 0,
    this.samples = 0,
    this.attempts = 0,
    this.measuredAt,
  });

  /// Representative latency in milliseconds — the median of the samples.
  final int latency;

  /// Best (minimum) successful sample in ms.
  final int min;

  /// Worst (maximum) successful sample in ms.
  final int max;

  /// Mean of the successful samples in ms.
  final int avg;

  /// Jitter (mean absolute deviation) of the successful samples in ms.
  final int jitter;

  /// Failure rate as a percentage in `0..100`.
  final double loss;

  final int samples;
  final int attempts;
  final DateTime? measuredAt;

  static const failed = PingResult();

  bool get isAlive => latency > 0 && samples > 0;
}
/// A high-precision, concurrent TCP ping engine.
///
/// Each host is probed [samplesPerHost] times (DNS resolution is performed
/// once, up-front, so it never pollutes the connect-time measurement) and the
/// results are reduced to a median latency, jitter and packet loss. Batch runs
/// use a bounded worker pool so many proxies can be measured concurrently
/// without flooding the network.
class PingService {
  PingService({
    Duration? timeout,
    int? samplesPerHost,
    int? concurrency,
  })  : timeout = timeout ?? const Duration(milliseconds: 1200),
        samplesPerHost = samplesPerHost ?? 3,
        concurrency = concurrency ?? _adaptiveConcurrency();

  /// Maximum time to wait for a single TCP connect.
  final Duration timeout;

  /// Number of connect attempts used to build the statistics.
  final int samplesPerHost;

  /// How many hosts are probed in parallel during batch operations.
  ///
  /// Defaults to a value derived from the device's CPU core count: weak phones
  /// use fewer concurrent probes, while stronger devices push more.
  final int concurrency;

  /// Chooses a sensible number of parallel probes based on the device's CPU:
  /// 2 cores → 2, 3–4 → 4, 5–6 → 6, 7–8 → 8, 9+ → 10.
  static int _adaptiveConcurrency() {
    final cores = _processorCount();
    if (cores <= 2) return 2;
    if (cores <= 4) return 4;
    if (cores <= 6) return 6;
    if (cores <= 8) return 8;
    return 10;
  }

  static int _processorCount() {
    try {
      return Platform.numberOfProcessors;
    } catch (_) {
      return 4;
    }
  }

  /// Measures a single `host:port` endpoint.
  Future<PingResult> pingHost(String host, int port) async {
    final attempts = samplesPerHost.clamp(1, 20).toInt();
    final resolved = await _resolve(host);

    final latencies = <double>[];
    var failures = 0;

    for (var i = 0; i < attempts; i++) {
      final ms = await _connectOnce(host, port, resolved);
      if (ms == null) {
        failures++;
      } else {
        latencies.add(ms);
      }
    }

    if (latencies.isEmpty) {
      return PingResult(
        loss: 100,
        attempts: attempts,
        measuredAt: DateTime.now(),
      );
    }

    latencies.sort();
    final sum = latencies.reduce((a, b) => a + b);
    final mean = sum / latencies.length;
    final deviationSum =
        latencies.map((v) => (v - mean).abs()).reduce((a, b) => a + b);

    return PingResult(
      latency: _median(latencies).round(),
      min: latencies.first.round(),
      max: latencies.last.round(),
      avg: mean.round(),
      jitter: (deviationSum / latencies.length).round(),
      loss: (failures / attempts) * 100,
      samples: latencies.length,
      attempts: attempts,
      measuredAt: DateTime.now(),
    );
  }

  /// Pings a batch of endpoints concurrently using a bounded worker pool.
  ///
  /// [onResult] fires for every completed target, [onProgress] reports
  /// `(completed, total)`, and [isCancelled] lets the caller abort the run.
  Future<void> pingBatch(
    List<PingTarget> targets, {
    required void Function(PingTarget target, PingResult result) onResult,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (targets.isEmpty) return;

    final total = targets.length;
    var next = 0;
    var completed = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        final index = next;
        next++;
        if (index >= total) return;

        final target = targets[index];
        final result = await pingHost(target.host, target.port);
        if (isCancelled?.call() == true) return;

        onResult(target, result);
        completed++;
        onProgress?.call(completed, total);
      }
    }

    final workerCount = concurrency < total ? concurrency : total;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  Future<double?> _connectOnce(
    String host,
    int port,
    List<InternetAddress> resolved,
  ) async {
    // Try resolved IPs first (DNS is excluded from the timing), then fall back
    // to the raw hostname in case a resolved family is unreachable.
    final candidates = <String>[
      for (final address in resolved) address.address,
      host,
    ];

    Socket? socket;
    for (final candidate in candidates) {
      final stopwatch = Stopwatch()..start();
      try {
        socket = await Socket.connect(candidate, port, timeout: timeout);
        stopwatch.stop();
        return stopwatch.elapsedMicroseconds / 1000.0;
      } catch (_) {
        stopwatch.stop();
        socket?.destroy();
        socket = null;
      }
    }
    return null;
  }

  Future<List<InternetAddress>> _resolve(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      final ipv4 =
          addresses.where((a) => a.type == InternetAddressType.IPv4).toList();
      final ipv6 =
          addresses.where((a) => a.type == InternetAddressType.IPv6).toList();
      // Prefer IPv4: most MTProto endpoints listen on both families, and this
      // avoids burning a full timeout on a broken IPv6 path.
      return [...ipv4, ...ipv6];
    } catch (_) {
      return const [];
    }
  }

  double _median(List<double> sorted) {
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}
