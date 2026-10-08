import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';

abstract interface class ShieldRepository {
  /// Sessions whose [ShieldSession.effectiveEnd] is after [since], oldest first.
  Stream<List<ShieldSession>> watchSince(DateTime since);

  Future<List<ShieldSession>> getSince(DateTime since);

  /// Inserts [session] (its `id` is ignored) and returns the new id.
  Future<int> add(ShieldSession session);

  /// Replaces the stored session with the same `id`.
  Future<void> update(ShieldSession session);

  /// The session covering [now], if any (the latest started when several do).
  Future<ShieldSession?> active(DateTime now);
}
