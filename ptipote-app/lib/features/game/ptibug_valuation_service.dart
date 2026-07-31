import 'ptibug_config.dart';

/// Immutable input makes valuation independent from widgets and persistence.
class PTibugValuationInput {
  const PTibugValuationInput({
    required this.species,
    required this.level,
    required this.traitRanks,
    required this.modules,
  });

  final PTibugSpecies species;
  final int level;
  final List<int> traitRanks;
  final List<PTibugModuleType> modules;
}

class PTibugValuationBreakdown {
  const PTibugValuationBreakdown({
    required this.baseValue,
    required this.levelValue,
    required this.traitValue,
    required this.moduleValue,
    required this.configVersion,
  });

  final int baseValue;
  final int levelValue;
  final int traitValue;
  final int moduleValue;
  final int configVersion;

  int get total => baseValue + levelValue + traitValue + moduleValue;
}

/// Single source of truth for estimated value and real commercial payment.
class PTibugValuationService {
  const PTibugValuationService(this.config);

  final PTibugValuationConfig config;

  PTibugValuationBreakdown evaluate(PTibugValuationInput input) {
    final traits = input.traitRanks.fold<int>(
      0,
      (total, rank) => total + config.traitValueFor(rank),
    );
    final modules = input.modules.fold<int>(
      0,
      (total, module) => total + config.moduleValueFor(module),
    );
    return PTibugValuationBreakdown(
      baseValue: config.baseValueFor(input.species),
      levelValue: config.levelValueFor(input.level),
      traitValue: traits,
      moduleValue: modules,
      configVersion: config.configVersion,
    );
  }

  int paymentFor(
    PTibugValuationBreakdown value, {
    required bool sourcierContract,
    double bonusMultiplier = 1,
  }) {
    final coefficient = sourcierContract
        ? config.sourcierContractCoefficient
        : config.customerRequestCoefficient;
    return (value.total * coefficient * bonusMultiplier)
        .round()
        .clamp(config.minimumPayment, 1 << 30);
  }
}
