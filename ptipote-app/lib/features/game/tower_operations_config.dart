enum TowerWeatherType { calm, toxicCloud, heatWave, heavyRain }

enum GlobalWeatherIntensity { calm, moderate, strong, severe }

enum GlobalWeatherEventStatus { planned, announced, active, completed }

class GlobalWeatherIntensityConfig {
  const GlobalWeatherIntensityConfig({
    required this.weight,
    required this.ptibugMalusPercent,
    required this.minimumAffectedBiomes,
    required this.maximumAffectedBiomes,
  });

  final int weight;
  final int ptibugMalusPercent;
  final int minimumAffectedBiomes;
  final int maximumAffectedBiomes;
}

class GlobalWeatherBiomeSensitivity {
  const GlobalWeatherBiomeSensitivity({
    required this.chancePercent,
    required this.impactMultiplier,
    this.immune = false,
    this.reason = '',
  });

  final int chancePercent;
  final double impactMultiplier;
  final bool immune;
  final String reason;
}

class GlobalWeatherConfig {
  const GlobalWeatherConfig({
    required this.cycleMinutes,
    required this.forecastMinutes,
    required this.maximumConsecutiveAdverseEvents,
    required this.allowConsecutiveSevereEvents,
    required this.forcedCalmChancePercent,
    required this.maximumPTibugMalusPercent,
    required this.localImpactMultipliers,
    required this.intensities,
    required this.biomeSensitivities,
  });

  final int cycleMinutes;
  final int forecastMinutes;
  final int maximumConsecutiveAdverseEvents;
  final int allowConsecutiveSevereEvents;
  final int forcedCalmChancePercent;
  final int maximumPTibugMalusPercent;
  final Map<String, double> localImpactMultipliers;
  final Map<GlobalWeatherIntensity, GlobalWeatherIntensityConfig> intensities;
  final Map<String, Map<TowerWeatherType, GlobalWeatherBiomeSensitivity>>
      biomeSensitivities;
}

/// Réglages communs de durabilité des bâtiments. Les bâtiments ne portent que
/// leur état courant : les règles de dégâts, réparation et protection restent
/// pilotables à distance depuis cette configuration versionnée.
class BuildingViabilityConfig {
  const BuildingViabilityConfig({
    required this.maximumViability,
    required this.initialViability,
    required this.degradedThreshold,
    required this.restartViability,
    required this.degradedCraftTimePercent,
    required this.degradedCraftCostPercent,
    required this.degradedProductionPercent,
    required this.repairGain,
    required this.repairOrganicCost,
    required this.repairMineralCost,
    required this.restartOrganicCost,
    required this.restartMineralCost,
    required this.restartBioBatteryCost,
    required this.slotsPerLevel,
    required this.protectionCapPercent,
    required this.protectionReductionPercents,
    required this.damageByWeatherAndIntensity,
  });

  final int maximumViability;
  final int initialViability;
  final int degradedThreshold;
  final int restartViability;
  final int degradedCraftTimePercent;
  final int degradedCraftCostPercent;
  final int degradedProductionPercent;
  final int repairGain;
  final int repairOrganicCost;
  final int repairMineralCost;
  final int restartOrganicCost;
  final int restartMineralCost;
  final int restartBioBatteryCost;
  final int slotsPerLevel;
  final int protectionCapPercent;
  final List<int> protectionReductionPercents;
  final Map<TowerWeatherType, Map<GlobalWeatherIntensity, int>>
      damageByWeatherAndIntensity;

  int damageFor(TowerWeatherType type, GlobalWeatherIntensity intensity) =>
      damageByWeatherAndIntensity[type]?[intensity] ?? 0;
}

class SecurityWellbeingBand {
  const SecurityWellbeingBand({
    required this.minimumSecurity,
    required this.wellbeingModifier,
    required this.label,
  });

  final int minimumSecurity;
  final int wellbeingModifier;
  final String label;
}

class TowerWeatherConfig {
  const TowerWeatherConfig({
    required this.type,
    required this.label,
    required this.description,
    required this.announcement,
    required this.durationMinutes,
    required this.warningMinutes,
    required this.preparationItem,
    required this.preparationAmount,
    required this.occurrenceWeight,
  });

  final TowerWeatherType type;
  final String label;
  final String description;
  final String announcement;
  final int durationMinutes;
  final int warningMinutes;
  final String preparationItem;
  final int preparationAmount;
  final int occurrenceWeight;
}

class TowerOperationsConfig {
  const TowerOperationsConfig({
    required this.biomeRevealSecurityThreshold,
    required this.explorationDurationMinutes,
    required this.localSecurityMaximum,
    required this.localSecurityHoursForFullPatrol,
    required this.maximumLocalRiskReductionPercent,
    required this.localSecurityDecayPerHour,
    required this.localSecurityRecentMissionHours,
    required this.merchantPresenceHours,
    required this.merchantMaxVisitsPerDay,
    required this.merchantMinimumGapHours,
    required this.merchantRandomGapAdditionalHours,
    required this.merchantCallBatteryCost,
    required this.merchantCallMinimumWaitMinutes,
    required this.merchantCallRandomWaitAdditionalMinutes,
    required this.merchantOfferPrices,
    required this.merchantWorkshopOfferCount,
    required this.merchantWorkshopMinimumQuantity,
    required this.merchantWorkshopMaximumQuantity,
    required this.wellbeingBands,
    required this.weatherEvents,
    required this.maxWeatherEventsPerDay,
    required this.minimumWeatherIntervalMinutes,
    required this.manualWeatherTriggerId,
    required this.manualWeatherTriggerType,
    required this.globalWeather,
    required this.buildingViability,
  });

  final int biomeRevealSecurityThreshold;
  final int explorationDurationMinutes;
  final int localSecurityMaximum;
  final int localSecurityHoursForFullPatrol;
  final int maximumLocalRiskReductionPercent;
  final int localSecurityDecayPerHour;
  final int localSecurityRecentMissionHours;
  final int merchantPresenceHours;
  final int merchantMaxVisitsPerDay;
  final int merchantMinimumGapHours;
  final int merchantRandomGapAdditionalHours;
  final int merchantCallBatteryCost;
  final int merchantCallMinimumWaitMinutes;
  final int merchantCallRandomWaitAdditionalMinutes;

  /// Finished Atelier product prices, per unit.
  final Map<String, int> merchantOfferPrices;
  final int merchantWorkshopOfferCount;
  final int merchantWorkshopMinimumQuantity;
  final int merchantWorkshopMaximumQuantity;
  final List<SecurityWellbeingBand> wellbeingBands;
  final List<TowerWeatherConfig> weatherEvents;
  final int maxWeatherEventsPerDay;
  final int minimumWeatherIntervalMinutes;
  final String manualWeatherTriggerId;
  final TowerWeatherType? manualWeatherTriggerType;
  final GlobalWeatherConfig globalWeather;
  final BuildingViabilityConfig buildingViability;

  SecurityWellbeingBand wellbeingBandFor(int security) =>
      wellbeingBands.where((band) => security >= band.minimumSecurity).reduce(
            (best, band) =>
                band.minimumSecurity > best.minimumSecurity ? band : best,
          );
}

const TowerOperationsConfig defaultTowerOperationsConfig =
    TowerOperationsConfig(
  biomeRevealSecurityThreshold: 40,
  explorationDurationMinutes: 20,
  localSecurityMaximum: 100,
  localSecurityHoursForFullPatrol: 8,
  maximumLocalRiskReductionPercent: 30,
  localSecurityDecayPerHour: 2,
  localSecurityRecentMissionHours: 6,
  merchantPresenceHours: 2,
  merchantMaxVisitsPerDay: 3,
  merchantMinimumGapHours: 4,
  merchantRandomGapAdditionalHours: 4,
  merchantCallBatteryCost: 1,
  merchantCallMinimumWaitMinutes: 5,
  merchantCallRandomWaitAdditionalMinutes: 10,
  merchantOfferPrices: <String, int>{
    'Filtre': 4,
    'Tenue ombragée': 6,
    'Ventilation Termite': 6,
  },
  merchantWorkshopOfferCount: 1,
  merchantWorkshopMinimumQuantity: 5,
  merchantWorkshopMaximumQuantity: 10,
  maxWeatherEventsPerDay: 3,
  minimumWeatherIntervalMinutes: 240,
  manualWeatherTriggerId: '',
  manualWeatherTriggerType: null,
  globalWeather: GlobalWeatherConfig(
    cycleMinutes: 360,
    forecastMinutes: 120,
    maximumConsecutiveAdverseEvents: 3,
    allowConsecutiveSevereEvents: 0,
    forcedCalmChancePercent: 100,
    maximumPTibugMalusPercent: 60,
    localImpactMultipliers: const <String, double>{
      'low': 0.5,
      'medium': 1.0,
      'high': 1.5,
    },
    intensities: const <GlobalWeatherIntensity, GlobalWeatherIntensityConfig>{
      GlobalWeatherIntensity.calm: GlobalWeatherIntensityConfig(
          weight: 40,
          ptibugMalusPercent: 0,
          minimumAffectedBiomes: 0,
          maximumAffectedBiomes: 0),
      GlobalWeatherIntensity.moderate: GlobalWeatherIntensityConfig(
          weight: 35,
          ptibugMalusPercent: 10,
          minimumAffectedBiomes: 1,
          maximumAffectedBiomes: 3),
      GlobalWeatherIntensity.strong: GlobalWeatherIntensityConfig(
          weight: 20,
          ptibugMalusPercent: 20,
          minimumAffectedBiomes: 3,
          maximumAffectedBiomes: 4),
      GlobalWeatherIntensity.severe: GlobalWeatherIntensityConfig(
          weight: 5,
          ptibugMalusPercent: 30,
          minimumAffectedBiomes: 4,
          maximumAffectedBiomes: 4),
    },
    biomeSensitivities: <String,
        Map<TowerWeatherType, GlobalWeatherBiomeSensitivity>>{
      'plaineRiche': <TowerWeatherType, GlobalWeatherBiomeSensitivity>{
        TowerWeatherType.heatWave: GlobalWeatherBiomeSensitivity(
            chancePercent: 90,
            impactMultiplier: 1.0,
            reason: 'Plaine exposée à la chaleur.'),
        TowerWeatherType.heavyRain: GlobalWeatherBiomeSensitivity(
            chancePercent: 80,
            impactMultiplier: 1.0,
            reason: 'Plaine sensible au ruissellement.'),
        TowerWeatherType.toxicCloud: GlobalWeatherBiomeSensitivity(
            chancePercent: 45, impactMultiplier: 1.0),
      },
      'colline': <TowerWeatherType, GlobalWeatherBiomeSensitivity>{
        TowerWeatherType.heatWave: GlobalWeatherBiomeSensitivity(
            chancePercent: 65, impactMultiplier: 0.8),
        TowerWeatherType.heavyRain: GlobalWeatherBiomeSensitivity(
            chancePercent: 80,
            impactMultiplier: 1.2,
            reason: 'Ruissellement des hauteurs.'),
        TowerWeatherType.toxicCloud: GlobalWeatherBiomeSensitivity(
            chancePercent: 20, impactMultiplier: 0.5, reason: 'Zone ventilée.'),
      },
      'bassinMineral': <TowerWeatherType, GlobalWeatherBiomeSensitivity>{
        TowerWeatherType.heatWave: GlobalWeatherBiomeSensitivity(
            chancePercent: 85, impactMultiplier: 1.3),
        TowerWeatherType.heavyRain: GlobalWeatherBiomeSensitivity(
            chancePercent: 35, impactMultiplier: 0.5),
        TowerWeatherType.toxicCloud: GlobalWeatherBiomeSensitivity(
            chancePercent: 70,
            impactMultiplier: 1.3,
            reason: 'Bassin confiné.'),
      },
      'sousBois': <TowerWeatherType, GlobalWeatherBiomeSensitivity>{
        TowerWeatherType.heatWave: GlobalWeatherBiomeSensitivity(
            chancePercent: 45, impactMultiplier: 0.5),
        TowerWeatherType.heavyRain: GlobalWeatherBiomeSensitivity(
            chancePercent: 90, impactMultiplier: 1.3),
        TowerWeatherType.toxicCloud: GlobalWeatherBiomeSensitivity(
            chancePercent: 65, impactMultiplier: 1.0),
      },
    },
  ),
  buildingViability: BuildingViabilityConfig(
    maximumViability: 100,
    initialViability: 100,
    degradedThreshold: 50,
    restartViability: 25,
    degradedCraftTimePercent: 25,
    degradedCraftCostPercent: 25,
    degradedProductionPercent: 25,
    repairGain: 15,
    repairOrganicCost: 5,
    repairMineralCost: 3,
    restartOrganicCost: 8,
    restartMineralCost: 4,
    restartBioBatteryCost: 1,
    slotsPerLevel: 1,
    protectionCapPercent: 70,
    protectionReductionPercents: const <int>[25, 15, 10],
    damageByWeatherAndIntensity: const <TowerWeatherType,
        Map<GlobalWeatherIntensity, int>>{
      TowerWeatherType.calm: <GlobalWeatherIntensity, int>{
        GlobalWeatherIntensity.calm: 0,
        GlobalWeatherIntensity.moderate: 0,
        GlobalWeatherIntensity.strong: 0,
        GlobalWeatherIntensity.severe: 0,
      },
      TowerWeatherType.heatWave: <GlobalWeatherIntensity, int>{
        GlobalWeatherIntensity.calm: 0,
        GlobalWeatherIntensity.moderate: 5,
        GlobalWeatherIntensity.strong: 12,
        GlobalWeatherIntensity.severe: 25,
      },
      TowerWeatherType.heavyRain: <GlobalWeatherIntensity, int>{
        GlobalWeatherIntensity.calm: 0,
        GlobalWeatherIntensity.moderate: 5,
        GlobalWeatherIntensity.strong: 12,
        GlobalWeatherIntensity.severe: 25,
      },
      TowerWeatherType.toxicCloud: <GlobalWeatherIntensity, int>{
        GlobalWeatherIntensity.calm: 0,
        GlobalWeatherIntensity.moderate: 5,
        GlobalWeatherIntensity.strong: 12,
        GlobalWeatherIntensity.severe: 25,
      },
    },
  ),
  wellbeingBands: <SecurityWellbeingBand>[
    SecurityWellbeingBand(
      minimumSecurity: 0,
      wellbeingModifier: -12,
      label: 'Vulnérable',
    ),
    SecurityWellbeingBand(
      minimumSecurity: 20,
      wellbeingModifier: -5,
      label: 'Fragile',
    ),
    SecurityWellbeingBand(
      minimumSecurity: 40,
      wellbeingModifier: 0,
      label: 'Stable',
    ),
    SecurityWellbeingBand(
      minimumSecurity: 60,
      wellbeingModifier: 5,
      label: 'Protégé',
    ),
    SecurityWellbeingBand(
      minimumSecurity: 80,
      wellbeingModifier: 10,
      label: 'Serein',
    ),
  ],
  weatherEvents: <TowerWeatherConfig>[
    TowerWeatherConfig(
      type: TowerWeatherType.toxicCloud,
      label: 'Nuage toxique',
      description: 'La pollution réduit les récoltes proches.',
      announcement:
          'La tour météo repère une pollution inhabituelle. Un nuage toxique arrive bientôt : consulte le Kernel pour voir la demande.',
      durationMinutes: 90,
      warningMinutes: 30,
      preparationItem: 'Filtre',
      preparationAmount: 1,
      occurrenceWeight: 2,
    ),
    TowerWeatherConfig(
      type: TowerWeatherType.heatWave,
      label: 'Forte chaleur',
      description: 'La chaleur fatigue les équipes dehors.',
      announcement:
          'La tour météo repère une augmentation de la chaleur. Une vague de chaleur arrive bientôt : consulte le Kernel pour voir la demande.',
      durationMinutes: 90,
      warningMinutes: 30,
      preparationItem: 'Tenue ombragée',
      preparationAmount: 1,
      occurrenceWeight: 3,
    ),
    TowerWeatherConfig(
      type: TowerWeatherType.heavyRain,
      label: 'Pluie intense',
      description: 'Les chemins deviennent difficiles.',
      announcement:
          'La tour météo repère une forte perturbation. Une pluie intense arrive bientôt : consulte le Kernel pour voir la demande.',
      durationMinutes: 60,
      warningMinutes: 20,
      preparationItem: 'Ventilation Termite',
      preparationAmount: 1,
      occurrenceWeight: 1,
    ),
  ],
);

TowerOperationsConfig towerOperationsConfig = defaultTowerOperationsConfig;
