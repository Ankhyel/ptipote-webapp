enum TowerWeatherType { toxicCloud, heatWave, heavyRain }

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
    required this.merchantOfferPrices,
    required this.wellbeingBands,
    required this.weatherEvents,
    required this.maxWeatherEventsPerDay,
    required this.minimumWeatherIntervalMinutes,
    required this.manualWeatherTriggerId,
    required this.manualWeatherTriggerType,
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
  final Map<String, int> merchantOfferPrices;
  final List<SecurityWellbeingBand> wellbeingBands;
  final List<TowerWeatherConfig> weatherEvents;
  final int maxWeatherEventsPerDay;
  final int minimumWeatherIntervalMinutes;
  final String manualWeatherTriggerId;
  final TowerWeatherType? manualWeatherTriggerType;

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
  merchantOfferPrices: <String, int>{
    'Plan Filtre': 4,
    'Plan Ventilation Termite': 6,
    'Plan Lumière solaire': 6,
  },
  maxWeatherEventsPerDay: 3,
  minimumWeatherIntervalMinutes: 240,
  manualWeatherTriggerId: '',
  manualWeatherTriggerType: null,
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
