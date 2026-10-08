/// Rank shown for the current streak (architecture doc 4.4). It follows the
/// current streak, so it drops when the streak breaks.
enum KnightRank {
  page(0),
  squire(3),
  knight(7),
  paladin(30);

  KnightRank(this.minDays);

  /// Qualifying days in a row needed to hold this rank.
  final int minDays;

  /// The highest rank whose [minDays] is at most [streakDays].
  static KnightRank forStreak(int streakDays) => values.lastWhere((r) => streakDays >= r.minDays);

  /// The rank after this one, or null at the top.
  KnightRank? get next => index + 1 < values.length ? values[index + 1] : null;

  /// Days still needed from [streakDays] to reach [next], or null at the top.
  int? daysToNext(int streakDays) {
    final n = next;
    return n == null ? null : n.minDays - streakDays;
  }
}
