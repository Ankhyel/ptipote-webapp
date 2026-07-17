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
    required this.durationMinutes,
    required this.warningMinutes,
    required this.preparationItem,
    required this.preparationAmount,
  });

  final TowerWeatherType type;
  final String label;
  final String description;
  final int durationMinutes;
  final int warningMinutes;
  final String preparationItem;
  final int preparationAmount;
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
    required this.merchantOfferPrices,
    required this.wellbeingBands,
    required this.weatherEvents,
  });

  final int biomeRevealSecurityThreshold;
  final int explorationDurationMinutes;
  final int localSecurityMaximum;
  final int localSecurityHoursForFullPatrol;
  final int maximumLocalRiskReductionPercent;
  final int localSecurityDecayPerHour;
  final int localSecurityRecentMissionHours;
  final int merchantPresenceHours;
  final Map<String, int> merchantOfferPrices;
  final List<SecurityWellbeingBand> wellbeingBands;
  final List<TowerWeatherConfig> weatherEvents;

  SecurityWellbeingBand wellbeingBandFor(int security) => wellbeingBands
      .where((band) => security >= band.minimumSecurity)
      .reduce((best, band) =>
          band.minimumSecurity > best.minimumSecurity ? band : best);
}

const TowerOperationsConfig defaultTowerOperationsConfig =
    TowerOperationsConfig(
  biomeRevealSecurityThreshold: 60,
  explorationDurationMinutes: 20,
  localSecurityMaximum: 100,
  localSecurityHoursForFullPatrol: 8,
  maximumLocalRiskReductionPercent: 30,
  localSecurityDecayPerHour: 2,
  localSecurityRecentMissionHours: 6,
  merchantPresenceHours: 24,
  merchantOfferPrices: <String, int>{
    'Plan Filtre': 4,
    'Plan Ventilation Termite': 6,
    'Plan Lumière solaire': 6,
  },
  wellbeingBands: <SecurityWellbeingBand>[
    SecurityWellbeingBand(
        minimumSecurity: 0, wellbeingModifier: -12, label: 'Vulnérable'),
    SecurityWellbeingBand(
        minimumSecurity: 20, wellbeingModifier: -5, label: 'Fragile'),
    SecurityWellbeingBand(
        minimumSecurity: 40, wellbeingModifier: 0, label: 'Stable'),
    SecurityWellbeingBand(
        minimumSecurity: 60, wellbeingModifier: 5, label: 'Protégé'),
    SecurityWellbeingBand(
        minimumSecurity: 80, wellbeingModifier: 10, label: 'Serein'),
  ],
  weatherEvents: <TowerWeatherConfig>[
    TowerWeatherConfig(
        type: TowerWeatherType.toxicCloud,
        label: 'Nuage toxique',
        description: 'La pollution réduit les récoltes proches.',
        durationMinutes: 90,
        warningMinutes: 30,
        preparationItem: 'Filtre',
        preparationAmount: 1),
    TowerWeatherConfig(
        type: TowerWeatherType.heatWave,
        label: 'Forte chaleur',
        description: 'La chaleur fatigue les équipes dehors.',
        durationMinutes: 90,
        warningMinutes: 30,
        preparationItem: 'Tenue ombragée',
        preparationAmount: 1),
    TowerWeatherConfig(
        type: TowerWeatherType.heavyRain,
        label: 'Pluie intense',
        description: 'Les chemins deviennent difficiles.',
        durationMinutes: 60,
        warningMinutes: 20,
        preparationItem: 'Ventilation Termite',
        preparationAmount: 1),
  ],
);

TowerOperationsConfig towerOperationsConfig = defaultTowerOperationsConfig;
