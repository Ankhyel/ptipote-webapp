import 'dart:math' as math;

import 'ptipote_v2.dart';
import 'ptipote_daily_life.dart';

enum PtipoteElementType { vegetal, mineral, fungal }

enum PtipoteEnvelopeType {
  standard,
  exploration,
  production,
  analyste,
  defense,
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
    required this.statRecoveryTimeMultiplier,
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
    required this.v2,
  });

  final int maxVitality;
  final int vitalityRecoveryPerMinute;

  /// 1 = timing normal; 2 = les remontées de statistiques sont deux fois plus lentes.
  final double statRecoveryTimeMultiplier;
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
  final PtipoteV2Config v2;

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

  /// Only the scalar values edited by the Dashboard are persisted remotely.
  /// Type and envelope modifiers remain versioned with the application for V1.
  Map<String, dynamic> toDashboardMap() => <String, dynamic>{
        'maxVitality': maxVitality,
        'vitalityRecoveryPerMinute': vitalityRecoveryPerMinute,
        'statRecoveryTimeMultiplier': statRecoveryTimeMultiplier,
        'alcoveVitalityRecoveryPerMinute': alcoveVitalityRecoveryPerMinute,
        'naturalVitalityRecoveryMinutes': naturalVitalityRecoveryMinutes,
        'happyVitalityRecoveryPerMinute': happyVitalityRecoveryPerMinute,
        'minVitalityBeforeAutoRest': minVitalityBeforeAutoRest,
        'minimumMissionVitality': minimumMissionVitality,
        'maxRest': maxRest,
        'sleepRestRecoveryPerMinute': sleepRestRecoveryPerMinute,
        'awakeRestLossMinutes': awakeRestLossMinutes,
        'missionRestLossRatio': missionRestLossRatio,
        'wellRestedThreshold': wellRestedThreshold,
        'restedThreshold': restedThreshold,
        'tiredThreshold': tiredThreshold,
        'exhaustedThreshold': exhaustedThreshold,
        'wellRestedXpBonus': wellRestedXpBonus,
        'wellRestedRewardBonus': wellRestedRewardBonus,
        'tiredXpPenalty': tiredXpPenalty,
        'tiredRewardPenalty': tiredRewardPenalty,
        'indigestionXpPenalty': indigestionXpPenalty,
        'maxHunger': maxHunger,
        'maxOverfedHunger': maxOverfedHunger,
        'baseHunger': baseHunger,
        'hungerDecayMinutes': hungerDecayMinutes,
        'missionHungerCostRatio': missionHungerCostRatio,
        'wellFedHungerThreshold': wellFedHungerThreshold,
        'wellFedVitalityRecoveryBonus': wellFedVitalityRecoveryBonus,
        'indigestionHungerThreshold': indigestionHungerThreshold,
        'indigestionVitalityRecoveryPenalty':
            indigestionVitalityRecoveryPenalty,
        'happyVitalityThreshold': happyVitalityThreshold,
        'happyHungerThreshold': happyHungerThreshold,
        'cuddleCooldownMinutes': cuddleCooldownMinutes,
        'cuddleCareDurationMinutes': cuddleCareDurationMinutes,
        'vitalityBubbleThreshold': vitalityBubbleThreshold,
        'hungerBubbleThreshold': hungerBubbleThreshold,
        'cuddleBubbleWarningMinutes': cuddleBubbleWarningMinutes,
        'needBubbleMinIntervalMinutes': needBubbleMinIntervalMinutes,
        'needBubbleMaxIntervalMinutes': needBubbleMaxIntervalMinutes,
        'needBubbleDisplayDurationSeconds': needBubbleDisplayDurationSeconds,
        'happyNeedsRequired': happyNeedsRequired,
        'okayNeedsRequired': okayNeedsRequired,
        'baseHappiness': baseHappiness,
        'maxHappiness': maxHappiness,
        'happinessDecayPerHour': happinessDecayPerHour,
        'xpRequiredBase': xpRequiredBase,
        'xpRequiredMultiplier': xpRequiredMultiplier,
        'baseEVG': baseEVG,
        'baseForageEfficiency': baseForageEfficiency,
        'baseSafetyContribution': baseSafetyContribution,
        'baseMarketContribution': baseMarketContribution,
        ...v2.toDashboardMap(),
      };

  factory PtipoteStatsConfig.fromDashboardMap(Map<String, dynamic> values) {
    const fallback = defaultPtipoteStatsConfig;
    int integer(String key, int value) =>
        (values[key] as num?)?.round() ?? value;
    double decimal(String key, double value) =>
        (values[key] as num?)?.toDouble() ?? value;

    return PtipoteStatsConfig(
      maxVitality: integer('maxVitality', fallback.maxVitality),
      vitalityRecoveryPerMinute: integer(
          'vitalityRecoveryPerMinute', fallback.vitalityRecoveryPerMinute),
      statRecoveryTimeMultiplier: decimal(
        'statRecoveryTimeMultiplier',
        fallback.statRecoveryTimeMultiplier,
      ).clamp(0.1, 10).toDouble(),
      alcoveVitalityRecoveryPerMinute: integer(
          'alcoveVitalityRecoveryPerMinute',
          fallback.alcoveVitalityRecoveryPerMinute),
      naturalVitalityRecoveryMinutes: integer('naturalVitalityRecoveryMinutes',
          fallback.naturalVitalityRecoveryMinutes),
      happyVitalityRecoveryPerMinute: integer('happyVitalityRecoveryPerMinute',
          fallback.happyVitalityRecoveryPerMinute),
      minVitalityBeforeAutoRest: integer(
          'minVitalityBeforeAutoRest', fallback.minVitalityBeforeAutoRest),
      minimumMissionVitality:
          integer('minimumMissionVitality', fallback.minimumMissionVitality),
      maxRest: integer('maxRest', fallback.maxRest),
      sleepRestRecoveryPerMinute: integer(
          'sleepRestRecoveryPerMinute', fallback.sleepRestRecoveryPerMinute),
      awakeRestLossMinutes:
          integer('awakeRestLossMinutes', fallback.awakeRestLossMinutes),
      missionRestLossRatio:
          decimal('missionRestLossRatio', fallback.missionRestLossRatio),
      wellRestedThreshold:
          integer('wellRestedThreshold', fallback.wellRestedThreshold),
      restedThreshold: integer('restedThreshold', fallback.restedThreshold),
      tiredThreshold: integer('tiredThreshold', fallback.tiredThreshold),
      exhaustedThreshold:
          integer('exhaustedThreshold', fallback.exhaustedThreshold),
      wellRestedXpBonus:
          decimal('wellRestedXpBonus', fallback.wellRestedXpBonus),
      wellRestedRewardBonus:
          decimal('wellRestedRewardBonus', fallback.wellRestedRewardBonus),
      tiredXpPenalty: decimal('tiredXpPenalty', fallback.tiredXpPenalty),
      tiredRewardPenalty:
          decimal('tiredRewardPenalty', fallback.tiredRewardPenalty),
      indigestionXpPenalty:
          decimal('indigestionXpPenalty', fallback.indigestionXpPenalty),
      maxHunger: integer('maxHunger', fallback.maxHunger),
      maxOverfedHunger: integer('maxOverfedHunger', fallback.maxOverfedHunger),
      baseHunger: integer('baseHunger', fallback.baseHunger),
      hungerDecayMinutes:
          integer('hungerDecayMinutes', fallback.hungerDecayMinutes),
      missionHungerCostRatio:
          decimal('missionHungerCostRatio', fallback.missionHungerCostRatio),
      wellFedHungerThreshold:
          integer('wellFedHungerThreshold', fallback.wellFedHungerThreshold),
      wellFedVitalityRecoveryBonus: decimal('wellFedVitalityRecoveryBonus',
          fallback.wellFedVitalityRecoveryBonus),
      indigestionHungerThreshold: integer(
          'indigestionHungerThreshold', fallback.indigestionHungerThreshold),
      indigestionVitalityRecoveryPenalty: decimal(
          'indigestionVitalityRecoveryPenalty',
          fallback.indigestionVitalityRecoveryPenalty),
      happyVitalityThreshold:
          integer('happyVitalityThreshold', fallback.happyVitalityThreshold),
      happyHungerThreshold:
          integer('happyHungerThreshold', fallback.happyHungerThreshold),
      cuddleCooldownMinutes:
          integer('cuddleCooldownMinutes', fallback.cuddleCooldownMinutes),
      cuddleCareDurationMinutes: integer(
          'cuddleCareDurationMinutes', fallback.cuddleCareDurationMinutes),
      vitalityBubbleThreshold:
          integer('vitalityBubbleThreshold', fallback.vitalityBubbleThreshold),
      hungerBubbleThreshold:
          integer('hungerBubbleThreshold', fallback.hungerBubbleThreshold),
      cuddleBubbleWarningMinutes: integer(
          'cuddleBubbleWarningMinutes', fallback.cuddleBubbleWarningMinutes),
      needBubbleMinIntervalMinutes: integer('needBubbleMinIntervalMinutes',
          fallback.needBubbleMinIntervalMinutes),
      needBubbleMaxIntervalMinutes: integer('needBubbleMaxIntervalMinutes',
          fallback.needBubbleMaxIntervalMinutes),
      needBubbleDisplayDurationSeconds: integer(
          'needBubbleDisplayDurationSeconds',
          fallback.needBubbleDisplayDurationSeconds),
      happyNeedsRequired:
          integer('happyNeedsRequired', fallback.happyNeedsRequired),
      okayNeedsRequired:
          integer('okayNeedsRequired', fallback.okayNeedsRequired),
      baseHappiness: integer('baseHappiness', fallback.baseHappiness),
      maxHappiness: integer('maxHappiness', fallback.maxHappiness),
      happinessDecayPerHour:
          integer('happinessDecayPerHour', fallback.happinessDecayPerHour),
      xpRequiredBase: integer('xpRequiredBase', fallback.xpRequiredBase),
      xpRequiredMultiplier:
          decimal('xpRequiredMultiplier', fallback.xpRequiredMultiplier),
      baseEVG: integer('baseEVG', fallback.baseEVG),
      baseForageEfficiency:
          decimal('baseForageEfficiency', fallback.baseForageEfficiency),
      baseSafetyContribution:
          decimal('baseSafetyContribution', fallback.baseSafetyContribution),
      baseMarketContribution:
          decimal('baseMarketContribution', fallback.baseMarketContribution),
      typeModifiers: fallback.typeModifiers,
      envelopeModifiers: fallback.envelopeModifiers,
      v2: _ptipoteV2Config(values, fallback.v2),
    );
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

const defaultPtipoteStatsConfig = PtipoteStatsConfig(
  maxVitality: 100,
  vitalityRecoveryPerMinute: 1,
  statRecoveryTimeMultiplier: 1,
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
    PtipoteEnvelopeType.exploration: PtipoteStatModifier(
      forageEfficiencyBonus: 0.05,
    ),
    PtipoteEnvelopeType.production: PtipoteStatModifier(
      marketContributionBonus: 0.05,
    ),
    PtipoteEnvelopeType.analyste: PtipoteStatModifier(
      pollutionResistanceBonus: 0.10,
      xpGainBonus: 0.05,
    ),
    PtipoteEnvelopeType.defense: PtipoteStatModifier(
      safetyContributionBonus: 0.10,
    ),
  },
  v2: defaultPtipoteV2Config,
);

PtipoteV2Config _ptipoteV2Config(
  Map<String, dynamic> values,
  PtipoteV2Config fallback,
) {
  int integer(String key, int value) => (values[key] as num?)?.round() ?? value;
  double decimal(String key, double value) =>
      (values[key] as num?)?.toDouble() ?? value;
  bool boolean(String key, bool value) {
    final raw = values[key];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return value;
  }

  String text(String key, String value) {
    final raw = '${values[key] ?? ''}'.trim();
    return raw.isEmpty ? value : raw;
  }

  return PtipoteV2Config(
    defaultBaseCarryCapacity: integer(
      'v2DefaultBaseCarryCapacity',
      fallback.defaultBaseCarryCapacity,
    ).clamp(1, 9999),
    coreOnlyEfficiency:
        decimal('v2CoreOnlyEfficiency', fallback.coreOnlyEfficiency)
            .clamp(0, 10)
            .toDouble(),
    newEnvelopeEfficiency:
        decimal('v2NewEnvelopeEfficiency', fallback.newEnvelopeEfficiency)
            .clamp(0, 10)
            .toDouble(),
    habituatedEnvelopeEfficiency: decimal(
      'v2HabituatedEnvelopeEfficiency',
      fallback.habituatedEnvelopeEfficiency,
    ).clamp(0, 10).toDouble(),
    adoptedEnvelopeEfficiency: decimal(
            'v2AdoptedEnvelopeEfficiency', fallback.adoptedEnvelopeEfficiency)
        .clamp(0, 10)
        .toDouble(),
    mineralTowerDefenseBonus: decimal(
      'v2MineralTowerDefenseBonus',
      fallback.mineralTowerDefenseBonus,
    ),
    mineralMissionSecurityBonus: decimal(
      'v2MineralMissionSecurityBonus',
      fallback.mineralMissionSecurityBonus,
    ),
    mineralGatherBonus:
        decimal('v2MineralGatherBonus', fallback.mineralGatherBonus),
    vegetalCraftBonus:
        decimal('v2VegetalCraftBonus', fallback.vegetalCraftBonus),
    vegetalHeatMitigation:
        decimal('v2VegetalHeatMitigation', fallback.vegetalHeatMitigation),
    vegetalOrganicGatherBonus: decimal(
      'v2VegetalOrganicGatherBonus',
      fallback.vegetalOrganicGatherBonus,
    ),
    mycelialCraftBonus:
        decimal('v2MycelialCraftBonus', fallback.mycelialCraftBonus),
    mycelialCommerceBonus:
        decimal('v2MycelialCommerceBonus', fallback.mycelialCommerceBonus),
    mycelialToxicMitigation: decimal(
      'v2MycelialToxicMitigation',
      fallback.mycelialToxicMitigation,
    ),
    mycelialOrganicGatherBonus: decimal(
      'v2MycelialOrganicGatherBonus',
      fallback.mycelialOrganicGatherBonus,
    ),
    mycelialWasteGatherBonus: decimal(
      'v2MycelialWasteGatherBonus',
      fallback.mycelialWasteGatherBonus,
    ),
    defenseSecurityBonus:
        decimal('v2DefenseSecurityBonus', fallback.defenseSecurityBonus),
    defenseDroneDefenseBonus: decimal(
      'v2DefenseDroneDefenseBonus',
      fallback.defenseDroneDefenseBonus,
    ),
    defenseCarryCapacityBonus: decimal(
      'v2DefenseCarryCapacityBonus',
      fallback.defenseCarryCapacityBonus,
    ),
    explorationGatherBonus: decimal(
      'v2ExplorationGatherBonus',
      fallback.explorationGatherBonus,
    ),
    explorationSecurityBonus: decimal(
      'v2ExplorationSecurityBonus',
      fallback.explorationSecurityBonus,
    ),
    explorationAllWeatherMitigation: decimal(
      'v2ExplorationAllWeatherMitigation',
      fallback.explorationAllWeatherMitigation,
    ),
    productionGatherBonus:
        decimal('v2ProductionGatherBonus', fallback.productionGatherBonus),
    productionCraftBonus:
        decimal('v2ProductionCraftBonus', fallback.productionCraftBonus),
    analystCraftBonus:
        decimal('v2AnalystCraftBonus', fallback.analystCraftBonus),
    analystSaleBonus: decimal('v2AnalystSaleBonus', fallback.analystSaleBonus),
    analystOwnCoreExplorationBonus: decimal(
      'v2AnalystOwnCoreExplorationBonus',
      fallback.analystOwnCoreExplorationBonus,
    ),
    analystGroupCountCap:
        integer('v2AnalystGroupCountCap', fallback.analystGroupCountCap)
            .clamp(1, 999),
    enableIncubator: boolean('v2EnableIncubator', fallback.enableIncubator),
    enableRhythmHatching:
        boolean('v2EnableRhythmHatching', fallback.enableRhythmHatching),
    eggVegetalColor: text('v2EggVegetalColor', fallback.eggVegetalColor),
    eggMineralColor: text('v2EggMineralColor', fallback.eggMineralColor),
    eggMycelialColor: text('v2EggMycelialColor', fallback.eggMycelialColor),
    arrivalInitialLevel:
        integer('v2ArrivalInitialLevel', fallback.arrivalInitialLevel)
            .clamp(1, 999),
    arrivalInitialXp: integer('v2ArrivalInitialXp', fallback.arrivalInitialXp)
        .clamp(0, 1 << 30),
    rhythmSequenceLength:
        integer('v2RhythmSequenceLength', fallback.rhythmSequenceLength)
            .clamp(3, 5),
    rhythmTimingToleranceMs: integer(
      'v2RhythmTimingToleranceMs',
      fallback.rhythmTimingToleranceMs,
    ).clamp(100, 5000),
    rhythmMinIntervalMs:
        integer('v2RhythmMinIntervalMs', fallback.rhythmMinIntervalMs)
            .clamp(100, 5000),
    rhythmMaxIntervalMs:
        integer('v2RhythmMaxIntervalMs', fallback.rhythmMaxIntervalMs)
            .clamp(100, 5000),
    rhythmRetryPolicy: text('v2RhythmRetryPolicy', fallback.rhythmRetryPolicy),
    rhythmVisualCueEnabled: boolean(
      'v2RhythmVisualCueEnabled',
      fallback.rhythmVisualCueEnabled,
    ),
    rhythmHapticEnabled:
        boolean('v2RhythmHapticEnabled', fallback.rhythmHapticEnabled),
    rhythmSoundEnabled:
        boolean('v2RhythmSoundEnabled', fallback.rhythmSoundEnabled),
    coBreedingEnabled:
        boolean('v2CoBreedingEnabled', fallback.coBreedingEnabled),
    coBreedingKernelUnlockLevel: integer(
      'v2CoBreedingKernelUnlockLevel',
      fallback.coBreedingKernelUnlockLevel,
    ).clamp(1, 99),
    coBreedingMaxDurationHours: integer(
      'v2CoBreedingMaxDurationHours',
      fallback.coBreedingMaxDurationHours,
    ).clamp(1, 24 * 31),
    coBreedingFinalProtectionWindowHours: integer(
      'v2CoBreedingFinalProtectionWindowHours',
      fallback.coBreedingFinalProtectionWindowHours,
    ).clamp(0, 24 * 31),
    coBreedingOfflineGuaranteedRemainingHours: integer(
      'v2CoBreedingOfflineGuaranteedRemainingHours',
      fallback.coBreedingOfflineGuaranteedRemainingHours,
    ).clamp(0, 24 * 31),
    coBreedingCapacityPerBreederLevel: integer(
      'v2CoBreedingCapacityPerBreederLevel',
      fallback.coBreedingCapacityPerBreederLevel,
    ).clamp(1, 99),
    coBreedingLevelEarlyDeparture: integer(
      'v2CoBreedingLevelEarlyDeparture',
      fallback.coBreedingLevelEarlyDeparture,
    ).clamp(1, 999),
    coBreedingOfferRotationHours: integer(
      'v2CoBreedingOfferRotationHours',
      fallback.coBreedingOfferRotationHours,
    ).clamp(1, 24 * 31),
    coBreedingChooseTypeCost: integer(
      'v2CoBreedingChooseTypeCost',
      fallback.coBreedingChooseTypeCost,
    ).clamp(0, 9999),
    coBreedingChooseExactPtipoteCost: integer(
      'v2CoBreedingChooseExactPtipoteCost',
      fallback.coBreedingChooseExactPtipoteCost,
    ).clamp(0, 9999),
    coBreedingChooseExactEnvelopeCost: integer(
      'v2CoBreedingChooseExactEnvelopeCost',
      fallback.coBreedingChooseExactEnvelopeCost,
    ).clamp(0, 9999),
    coBreedingInitialFreeEnabled: boolean(
      'v2CoBreedingInitialFreeEnabled',
      fallback.coBreedingInitialFreeEnabled,
    ),
    envelopeUnlockPtipoteLevel: integer(
      'v2EnvelopeUnlockPtipoteLevel',
      fallback.envelopeUnlockPtipoteLevel,
    ).clamp(1, 999),
    symbiosisPercentPerHour: decimal(
      'v2SymbiosisPercentPerHour',
      fallback.symbiosisPercentPerHour,
    ).clamp(0, 100).toDouble(),
    symbiosisPercentPerActivity: decimal(
      'v2SymbiosisPercentPerActivity',
      fallback.symbiosisPercentPerActivity,
    ).clamp(0, 100).toDouble(),
    symbiosisMaxLevel: integer(
      'v2SymbiosisMaxLevel',
      fallback.symbiosisMaxLevel,
    ).clamp(0, 10),
    symbiosisProgressRequiredPerLevel: decimal(
      'v2SymbiosisProgressRequiredPerLevel',
      fallback.symbiosisProgressRequiredPerLevel,
    ).clamp(1, 1000).toDouble(),
    coBreedingCompletionRequireHouse: boolean(
      'v2CoBreedingCompletionRequireHouse',
      fallback.coBreedingCompletionRequireHouse,
    ),
    coBreedingCompletionBlockNewActivity: boolean(
      'v2CoBreedingCompletionBlockNewActivity',
      fallback.coBreedingCompletionBlockNewActivity,
    ),
    coBreedingCompletionArchive: boolean(
      'v2CoBreedingCompletionArchive',
      fallback.coBreedingCompletionArchive,
    ),
    protocolsPublicEnabled: boolean(
      'v2ProtocolsPublicEnabled',
      fallback.protocolsPublicEnabled,
    ),
    protocolsDevEnabled: boolean(
      'v2ProtocolsDevEnabled',
      fallback.protocolsDevEnabled,
    ),
    protocolEnvelopePublicEnabled: boolean(
      'v2ProtocolEnvelopesPublicEnabled',
      fallback.protocolEnvelopePublicEnabled,
    ),
    protocolEnvelopeDevEnabled: boolean(
      'v2ProtocolEnvelopesDevEnabled',
      fallback.protocolEnvelopeDevEnabled,
    ),
    coBreedingXpRewardBase: integer(
      'v2CoBreedingXpRewardBase',
      fallback.coBreedingXpRewardBase,
    ).clamp(0, 999999),
    coBreedingXpRewardPerFinalLevel: integer(
      'v2CoBreedingXpRewardPerFinalLevel',
      fallback.coBreedingXpRewardPerFinalLevel,
    ).clamp(0, 999999),
    coBreedingBreederXpRewardBase: integer(
      'v2CoBreedingBreederXpRewardBase',
      fallback.coBreedingBreederXpRewardBase,
    ).clamp(0, 999999),
    coBreedingBreederXpRewardPerFinalLevel: integer(
      'v2CoBreedingBreederXpRewardPerFinalLevel',
      fallback.coBreedingBreederXpRewardPerFinalLevel,
    ).clamp(0, 999999),
    coBreedingKernelTrustRewardBase: integer(
      'v2CoBreedingKernelTrustRewardBase',
      fallback.coBreedingKernelTrustRewardBase,
    ).clamp(0, 999999),
    coBreedingKernelTrustRewardPerFinalLevel: integer(
      'v2CoBreedingKernelTrustRewardPerFinalLevel',
      fallback.coBreedingKernelTrustRewardPerFinalLevel,
    ).clamp(0, 999999),
  );
}

PtipoteStatsConfig _activePtipoteStatsConfig = defaultPtipoteStatsConfig;

/// Current configuration used by gameplay. It starts with the app defaults and
/// can be replaced by the signed-in Dashboard configuration at runtime.
PtipoteStatsConfig get ptipoteStatsConfig => _activePtipoteStatsConfig;

void applyRemotePtipoteStatsConfig(Map<String, dynamic>? values) {
  _activePtipoteStatsConfig = values == null
      ? defaultPtipoteStatsConfig
      : PtipoteStatsConfig.fromDashboardMap(values);
  applyRemotePtipoteDailyLifeConfig(values);
}
