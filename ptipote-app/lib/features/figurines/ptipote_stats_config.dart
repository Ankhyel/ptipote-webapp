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

enum PtipoteMood { happy, okay, unwell }

enum PtipoteRestState { wellRested, rested, tired, exhausted }

class PtipoteStatsConfig {
  const PtipoteStatsConfig({
    required this.maxVitality,
    required this.vitalityRecoveryPerMinute,
    required this.alcoveVitalityRecoveryPerMinute,
    required this.naturalVitalityRecoveryMinutes,
    required this.happyVitalityRecoveryPerMinute,
    required this.minVitalityBeforeAutoRest,
    required this.minimumMissionVitality,
    required this.maxRest,
    required this.sleepRestRecoveryPerMinute,
    required this.awakeRestLossMinutes,
    required this.missionRestLossRatio,
    required this.wellRestedThreshold,
    required this.restedThreshold,
    required this.tiredThreshold,
    required this.exhaustedThreshold,
    required this.wellRestedXpBonus,
    required this.wellRestedRewardBonus,
    required this.tiredXpPenalty,
    required this.tiredRewardPenalty,
    required this.indigestionXpPenalty,
    required this.maxHunger,
    required this.maxOverfedHunger,
    required this.baseHunger,
    required this.hungerDecayMinutes,
    required this.missionHungerCostRatio,
    required this.wellFedHungerThreshold,
    required this.wellFedVitalityRecoveryBonus,
    required this.indigestionHungerThreshold,
    required this.indigestionVitalityRecoveryPenalty,
    required this.happyVitalityThreshold,
    required this.happyHungerThreshold,
    required this.cuddleCooldownMinutes,
    required this.cuddleCareDurationMinutes,
    required this.vitalityBubbleThreshold,
    required this.hungerBubbleThreshold,
    required this.cuddleBubbleWarningMinutes,
    required this.needBubbleMinIntervalMinutes,
    required this.needBubbleMaxIntervalMinutes,
    required this.needBubbleDisplayDurationSeconds,
    required this.happyNeedsRequired,
    required this.okayNeedsRequired,
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
  final int naturalVitalityRecoveryMinutes;
  final int happyVitalityRecoveryPerMinute;
  final int minVitalityBeforeAutoRest;
  final int minimumMissionVitality;
  final int maxRest;
  final int sleepRestRecoveryPerMinute;
  final int awakeRestLossMinutes;
  final double missionRestLossRatio;
  final int wellRestedThreshold;
  final int restedThreshold;
  final int tiredThreshold;
  final int exhaustedThreshold;
  final double wellRestedXpBonus;
  final double wellRestedRewardBonus;
  final double tiredXpPenalty;
  final double tiredRewardPenalty;
  final double indigestionXpPenalty;
  final int maxHunger;
  final int maxOverfedHunger;
  final int baseHunger;
  final int hungerDecayMinutes;
  final double missionHungerCostRatio;
  final int wellFedHungerThreshold;
  final double wellFedVitalityRecoveryBonus;
  final int indigestionHungerThreshold;
  final double indigestionVitalityRecoveryPenalty;
  final int happyVitalityThreshold;
  final int happyHungerThreshold;
  final int cuddleCooldownMinutes;
  final int cuddleCareDurationMinutes;
  final int vitalityBubbleThreshold;
  final int hungerBubbleThreshold;
  final int cuddleBubbleWarningMinutes;
  final int needBubbleMinIntervalMinutes;
  final int needBubbleMaxIntervalMinutes;
  final int needBubbleDisplayDurationSeconds;
  final int happyNeedsRequired;
  final int okayNeedsRequired;
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

  PtipoteRestState restStateFor(int rest) {
    if (rest >= wellRestedThreshold) return PtipoteRestState.wellRested;
    if (rest >= restedThreshold) return PtipoteRestState.rested;
    if (rest >= tiredThreshold) return PtipoteRestState.tired;
    return PtipoteRestState.exhausted;
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
  naturalVitalityRecoveryMinutes: 2,
  happyVitalityRecoveryPerMinute: 1,
  minVitalityBeforeAutoRest: 20,
  minimumMissionVitality: 10,
  maxRest: 100,
  sleepRestRecoveryPerMinute: 2,
  awakeRestLossMinutes: 30,
  missionRestLossRatio: 0.25,
  wellRestedThreshold: 80,
  restedThreshold: 50,
  tiredThreshold: 20,
  exhaustedThreshold: 0,
  wellRestedXpBonus: 0.10,
  wellRestedRewardBonus: 0.10,
  tiredXpPenalty: 0.10,
  tiredRewardPenalty: 0.05,
  indigestionXpPenalty: 0.10,
  maxHunger: 100,
  maxOverfedHunger: 120,
  baseHunger: 100,
  hungerDecayMinutes: 30,
  missionHungerCostRatio: 0.5,
  wellFedHungerThreshold: 80,
  wellFedVitalityRecoveryBonus: 0.25,
  indigestionHungerThreshold: 100,
  indigestionVitalityRecoveryPenalty: 0.25,
  happyVitalityThreshold: 30,
  happyHungerThreshold: 30,
  cuddleCooldownMinutes: 180,
  cuddleCareDurationMinutes: 240,
  vitalityBubbleThreshold: 40,
  hungerBubbleThreshold: 40,
  cuddleBubbleWarningMinutes: 30,
  needBubbleMinIntervalMinutes: 2,
  needBubbleMaxIntervalMinutes: 5,
  needBubbleDisplayDurationSeconds: 6,
  happyNeedsRequired: 3,
  okayNeedsRequired: 2,
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
