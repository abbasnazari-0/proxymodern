/// Immutable view of the capping rules coming from the backend.
///
/// Contract:
/// - `ad_min_interval_seconds == 0` means no interval limit.
/// - `ad_max_per_session == 0` means unlimited impressions per app run.
/// - Negative values are treated like zero (no limit).
///
/// The service keeps the mutable counters; this object only answers questions
/// about the current moment, which makes the rules trivially unit-testable.
class AdCapPolicy {
  const AdCapPolicy({
    required this.minIntervalSeconds,
    required this.maxPerSession,
    required this.shownCount,
    this.lastShownAt,
    this.now,
  });

  final int minIntervalSeconds;
  final int maxPerSession;
  final int shownCount;
  final DateTime? lastShownAt;

  /// Injected clock for deterministic tests; `null` uses [DateTime.now].
  final DateTime? now;

  bool get hasSessionCapacity =>
      maxPerSession <= 0 || shownCount < maxPerSession;

  bool get isIntervalElapsed {
    final last = lastShownAt;
    if (last == null || minIntervalSeconds <= 0) return true;
    final elapsed = (now ?? DateTime.now()).difference(last).inSeconds;
    // A backwards device clock must not lock ads forever.
    return elapsed.isNegative || elapsed >= minIntervalSeconds;
  }

  /// True when a load/show may start right now.
  bool get canRequest => hasSessionCapacity && isIntervalElapsed;

  /// Remaining impressions in this run; `-1` means unlimited.
  int get remainingSessionShows {
    if (maxPerSession <= 0) return -1;
    final remaining = maxPerSession - shownCount;
    return remaining < 0 ? 0 : remaining;
  }

  /// Time left until the next impression is allowed.
  Duration get remainingInterval {
    final last = lastShownAt;
    if (last == null || minIntervalSeconds <= 0) return Duration.zero;
    final elapsed = (now ?? DateTime.now()).difference(last);
    if (elapsed.isNegative) return Duration.zero;
    final remaining = Duration(seconds: minIntervalSeconds) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
