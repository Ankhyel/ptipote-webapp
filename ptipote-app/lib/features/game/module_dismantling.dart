/// Shared policy for dismantling an installed module.
///
/// A module keeps the physical materials that were really paid when it was
/// built.  Data is deliberately absent from this model: knowledge is never
/// refunded.  The game state owns the inventory transaction and persistence;
/// this small service makes the floor rounding rule reusable by Recycler,
/// biome modules and P'TIBUG modules.
class ModuleDismantlingService {
  const ModuleDismantlingService._();

  /// Returns the recoverable physical materials only.
  ///
  /// Values at zero are omitted so an installation with a tiny legacy cost
  /// can still be removed without pretending a resource was refunded.
  static Map<String, int> refundFor(
    Map<String, int> paidPhysicalMaterials, {
    required int percent,
  }) {
    final safePercent = percent.clamp(0, 100).toInt();
    return <String, int>{
      for (final entry in paidPhysicalMaterials.entries)
        if (entry.value > 0 && entry.value * safePercent ~/ 100 > 0)
          entry.key: entry.value * safePercent ~/ 100,
    };
  }

  /// Adds a newly paid level cost to an existing module snapshot.  This is
  /// important for upgrades: dismantling a level-3 module refunds from all
  /// physical materials that were paid for levels 1, 2 and 3, not a current
  /// Dashboard recipe that may have changed afterwards.
  static Map<String, int> accumulate(
    Map<String, int>? existing,
    Map<String, int> paidPhysicalMaterials,
  ) {
    final result = <String, int>{
      for (final entry in (existing ?? const <String, int>{}).entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    for (final entry in paidPhysicalMaterials.entries) {
      if (entry.value <= 0) continue;
      result.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    return result;
  }
}
