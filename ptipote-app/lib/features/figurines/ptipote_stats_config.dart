import 'dart:math' as math;

enum PtipoteElementType { vegetal, mineral, fungal }

enum PtipoteEnvelopeType {
  standard,
  explorateur,
  producteur,
  scientifique,
  protecteur,
}

enum PtipoteBehaviorState {
  idle,
  wanderingHome,
  resting,
  onMission,
  helpingTower,
  helpingMarket,
  exhausted,
}

enum PtipoteAutoAssignmentPreference { home, tower, market }

class PtipoteStatsConfig {
  const PtipoteStatsConfig({
    required this.maxVitality,
    required this.vitalityRecoveryPerMinute,
    required this.alcoveVitalityRecoveryPerMinute,
    required this.minVitalityBeforeAutoRest,
    required this.baseHappiness,
    required this.maxHappiness,
    required this.happinessDecayPerHour,
    required this.xpRequiredBase,
    required this.xpRequiredMultiplier,
    required this.baseEVG,
    required this.baseForageEfficiency,
    required this.baseSafetyContribution,
    required this.baseMarketContribution,
    required this.typeModifiers,
    required this.envelopeModifiers,
  });

  final int maxVitality;
  final int vitalityRecoveryPerMinute;
  final int alcoveVitalityRecoveryPerMinute;
  final int minVitalityBeforeAutoRest;
  final int baseHappiness;
  final int maxHappiness;
  final int happinessDecayPerHour;
  final int xpRequiredBase;
  final double xpRequiredMultiplier;
  final int baseEVG;
  final double baseForageEfficiency;
  final double baseSafetyContribution;
  final double baseMarketContribution;
  final Map<PtipoteElementType, PtipoteStatModifier> typeModifiers;
  final Map<PtipoteEnvelopeType, PtipoteStatModifier> envelopeModifiers;

  int xpRequiredForNextLevel(int currentLevel) {
    final safeLevel = math.max(1, currentLevel);
    final required =
        xpRequiredBase * math.pow(xpRequiredMultiplier, safeLevel - 1);
    return required.round();
  }
}

class PtipoteStatModifier {
  const PtipoteStatModifier({
    this.organicForageBonus = 0,
    this.mineralForageBonus = 0,
    this.forageEfficiencyBonus = 0,
    this.safetyContributionBonus = 0,
    this.marketContributionBonus = 0,
    this.pollutionResistanceBonus = 0,
    this.xpGainBonus = 0,
  });

  final double organicForageBonus;
  final double mineralForageBonus;
  final double forageEfficiencyBonus;
  final double safetyContributionBonus;
  final double marketContributionBonus;
  final double pollutionResistanceBonus;
  final double xpGainBonus;
}

const ptipoteStatsConfig = PtipoteStatsConfig(
  maxVitality: 100,
  vitalityRecoveryPerMinute: 1,
  alcoveVitalityRecoveryPerMinute: 2,
  minVitalityBeforeAutoRest: 20,
  baseHappiness: 70,
  maxHappiness: 100,
  happinessDecayPerHour: 1,
  xpRequiredBase: 100,
  xpRequiredMultiplier: 1.25,
  baseEVG: 50,
  baseForageEfficiency: 1,
  baseSafetyContribution: 1,
  baseMarketContribution: 1,
  typeModifiers: <PtipoteElementType, PtipoteStatModifier>{
    PtipoteElementType.vegetal: PtipoteStatModifier(
      organicForageBonus: 0.10,
      marketContributionBonus: 0.05,
    ),
    PtipoteElementType.mineral: PtipoteStatModifier(
      mineralForageBonus: 0.10,
      safetyContributionBonus: 0.10,
    ),
    PtipoteElementType.fungal: PtipoteStatModifier(
      safetyContributionBonus: 0.05,
      marketContributionBonus: 0.05,
    ),
  },
  envelopeModifiers: <PtipoteEnvelopeType, PtipoteStatModifier>{
    PtipoteEnvelopeType.standard: PtipoteStatModifier(),
    PtipoteEnvelopeType.explorateur: PtipoteStatModifier(
      forageEfficiencyBonus: 0.05,
    ),
    PtipoteEnvelopeType.producteur: PtipoteStatModifier(
      marketContributionBonus: 0.05,
    ),
    PtipoteEnvelopeType.scientifique: PtipoteStatModifier(
      pollutionResistanceBonus: 0.10,
      xpGainBonus: 0.05,
    ),
    PtipoteEnvelopeType.protecteur: PtipoteStatModifier(
      safetyContributionBonus: 0.10,
    ),
  },
);
