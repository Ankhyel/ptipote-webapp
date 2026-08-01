enum CampStage { camp, refuge, bourgade, village, petiteVille }

class CommunityProjectDefinition {
  const CommunityProjectDefinition(
      {required this.id,
      required this.label,
      required this.weatherType,
      required this.tier,
      required this.requiredCoreLevel,
      required this.prerequisiteId,
      required this.materialCosts,
      required this.requiredContributionPoints,
      required this.globalProtectionPercent,
      required this.description});
  final String id;
  final String label;
  final String weatherType;
  final int tier;
  final int requiredCoreLevel;
  final String? prerequisiteId;
  final Map<String, int> materialCosts;
  final int requiredContributionPoints;
  final int globalProtectionPercent;
  final String description;
}

class CommunityProjectsConfig {
  const CommunityProjectsConfig(
      {required this.choicesPerCoreLevel,
      required this.maximumActiveProjects,
      required this.playerDailyContribution,
      required this.residentHappinessThreshold,
      required this.residentDailyContribution,
      required this.residentContributionCapEnabled,
      required this.residentContributionCap,
      required this.projects,
      required this.protectedBatteryCapacity,
      required this.protectedBatteryCapacityPerUpgrade,
      required this.protectedBatteryUpgradeMaxLevel,
      required this.protectedBatteryUpgradeMineralCosts,
      required this.stockLossPercentByIntensity});
  final int choicesPerCoreLevel;
  final int maximumActiveProjects;
  final int playerDailyContribution;
  final int residentHappinessThreshold;
  final int residentDailyContribution;
  final bool residentContributionCapEnabled;
  final int residentContributionCap;
  final List<CommunityProjectDefinition> projects;
  final int protectedBatteryCapacity;
  final int protectedBatteryCapacityPerUpgrade;
  final int protectedBatteryUpgradeMaxLevel;
  final List<int> protectedBatteryUpgradeMineralCosts;
  final Map<String, int> stockLossPercentByIntensity;
}

class CampHeartConfig {
  const CampHeartConfig(
      {required this.stages, required this.communityProjects});

  final List<CampHeartStageConfig> stages;
  final CommunityProjectsConfig communityProjects;

  CampHeartStageConfig stageForLevel(int level) {
    final safeLevel = level.clamp(1, stages.length);
    return stages[safeLevel - 1];
  }

  CampHeartStageConfig? nextStageForLevel(int level) {
    if (level >= stages.length) return null;
    return stages[level];
  }
}

class CampHeartStageConfig {
  const CampHeartStageConfig({
    required this.level,
    required this.stage,
    required this.label,
    required this.organicRequiredForNextLevel,
    required this.populationLabel,
    required this.populationMin,
    required this.populationMax,
    required this.activePtipoteComfortLimit,
    required this.refugeHappinessBonus,
    required this.localActivityModifier,
    required this.unlocks,
    required this.effects,
  });

  final int level;
  final CampStage stage;
  final String label;
  final int? organicRequiredForNextLevel;
  final String populationLabel;
  final int? populationMin;
  final int? populationMax;
  final int activePtipoteComfortLimit;
  final int refugeHappinessBonus;
  final double localActivityModifier;
  final List<String> unlocks;
  final List<String> effects;
}

const CampHeartConfig defaultCampHeartConfig = CampHeartConfig(
  communityProjects: CommunityProjectsConfig(
    choicesPerCoreLevel: 1,
    maximumActiveProjects: 1,
    playerDailyContribution: 5,
    residentHappinessThreshold: 70,
    residentDailyContribution: 1,
    residentContributionCapEnabled: false,
    residentContributionCap: 0,
    protectedBatteryCapacity: 50,
    protectedBatteryCapacityPerUpgrade: 20,
    protectedBatteryUpgradeMaxLevel: 4,
    protectedBatteryUpgradeMineralCosts: <int>[30, 35, 40, 50],
    stockLossPercentByIntensity: <String, int>{
      'moderate': 5,
      'strong': 10,
      'severe': 20
    },
    projects: <CommunityProjectDefinition>[
      CommunityProjectDefinition(
          id: 'solarReflector',
          label: 'Réflecteur solaire',
          weatherType: 'heatWave',
          tier: 1,
          requiredCoreLevel: 1,
          prerequisiteId: null,
          materialCosts: <String, int>{'Organique': 20, 'Minéral': 10},
          requiredContributionPoints: 100,
          globalProtectionPercent: 10,
          description: 'Réduit les dégâts de Forte chaleur.'),
      CommunityProjectDefinition(
          id: 'highCanopyWood',
          label: 'Bois aux Hautes-Cimes',
          weatherType: 'heatWave',
          tier: 2,
          requiredCoreLevel: 2,
          prerequisiteId: 'solarReflector',
          materialCosts: <String, int>{'Organique': 40, 'Minéral': 20},
          requiredContributionPoints: 250,
          globalProtectionPercent: 10,
          description: 'Renforce la protection contre la Forte chaleur.'),
      CommunityProjectDefinition(
          id: 'canalisations',
          label: 'Canalisations',
          weatherType: 'heavyRain',
          tier: 1,
          requiredCoreLevel: 1,
          prerequisiteId: null,
          materialCosts: <String, int>{'Organique': 20, 'Minéral': 10},
          requiredContributionPoints: 100,
          globalProtectionPercent: 10,
          description: 'Réduit les dégâts de Pluie intense.'),
      CommunityProjectDefinition(
          id: 'myceliumMoss',
          label: 'Mousse-mycelium',
          weatherType: 'heavyRain',
          tier: 2,
          requiredCoreLevel: 2,
          prerequisiteId: 'canalisations',
          materialCosts: <String, int>{'Organique': 40, 'Minéral': 20},
          requiredContributionPoints: 250,
          globalProtectionPercent: 10,
          description: 'Renforce la protection contre la Pluie intense.'),
      CommunityProjectDefinition(
          id: 'stabilizingWood',
          label: 'Bois stabilisateur',
          weatherType: 'heavyRain',
          tier: 3,
          requiredCoreLevel: 3,
          prerequisiteId: 'myceliumMoss',
          materialCosts: <String, int>{'Organique': 60, 'Minéral': 30},
          requiredContributionPoints: 500,
          globalProtectionPercent: 10,
          description: 'Stabilise le camp sous la Pluie intense.'),
      CommunityProjectDefinition(
          id: 'giantFiltration',
          label: 'Filtration géante',
          weatherType: 'toxicCloud',
          tier: 1,
          requiredCoreLevel: 1,
          prerequisiteId: null,
          materialCosts: <String, int>{'Organique': 20, 'Minéral': 10},
          requiredContributionPoints: 100,
          globalProtectionPercent: 10,
          description: 'Réduit les dégâts de Nuage toxique.'),
      CommunityProjectDefinition(
          id: 'giantMushroom',
          label: 'Champignon géant',
          weatherType: 'toxicCloud',
          tier: 2,
          requiredCoreLevel: 2,
          prerequisiteId: 'giantFiltration',
          materialCosts: <String, int>{'Organique': 40, 'Minéral': 20},
          requiredContributionPoints: 250,
          globalProtectionPercent: 10,
          description: 'Renforce la filtration contre le Nuage toxique.'),
    ],
  ),
  stages: <CampHeartStageConfig>[
    CampHeartStageConfig(
      level: 1,
      stage: CampStage.camp,
      label: 'Camp',
      organicRequiredForNextLevel: 100,
      populationLabel: 'environ 5 personnes + visiteurs',
      populationMin: 5,
      populationMax: null,
      activePtipoteComfortLimit: 1,
      refugeHappinessBonus: 0,
      localActivityModifier: 1,
      unlocks: <String>[
        'Maison',
        'Kernel',
        'Cuisine simple',
        'Lisière proche de base',
        '1 P’TIPOTE actif confortable',
        'Visiteurs ponctuels',
        'Hauts-Refuges',
        'Savane tropicale',
      ],
      effects: <String>[
        'Début de végétalisation',
        'Bonheur de base faible mais stable',
      ],
    ),
    CampHeartStageConfig(
      level: 2,
      stage: CampStage.refuge,
      label: 'Refuge',
      organicRequiredForNextLevel: 250,
      populationLabel: '7 à 12 habitants',
      populationMin: 7,
      populationMax: 12,
      activePtipoteComfortLimit: 2,
      refugeHappinessBonus: 5,
      localActivityModifier: 1.05,
      unlocks: <String>[
        'Atelier simple',
        'Tour',
        'Semi-désert / Garrigue tropicale',
        'Forêt humide relictuelle',
        'Refuge PTIBUG',
        '2 P’TIPOTES actifs confortables',
        'Premiers habitants permanents',
      ],
      effects: <String>[
        'Bonheur plus stable',
        'Récupération des zones proches légèrement meilleure',
        'Activité locale un peu meilleure',
      ],
    ),
    CampHeartStageConfig(
      level: 3,
      stage: CampStage.bourgade,
      label: 'Bourgade',
      organicRequiredForNextLevel: 500,
      populationLabel: '15 à 21 habitants',
      populationMin: 15,
      populationMax: 21,
      activePtipoteComfortLimit: 3,
      refugeHappinessBonus: 10,
      localActivityModifier: 1.12,
      unlocks: <String>[
        'Serre',
        'Schémas PTIBUG via Atelier',
        'Premières évolutions PTIBUG',
        'Première Lisière lointaine simple',
        '3 P’TIPOTES actifs confortables',
        'Habitants plus visibles',
      ],
      effects: <String>[
        'Végétation visible plus riche',
        'Activité locale améliorée',
        'Meilleures ventes locales',
        'Bio-batterie légèrement améliorée',
      ],
    ),
    CampHeartStageConfig(
      level: 4,
      stage: CampStage.village,
      label: 'Village',
      organicRequiredForNextLevel: 900,
      populationLabel: 'communauté stable',
      populationMin: null,
      populationMax: null,
      activePtipoteComfortLimit: 4,
      refugeHappinessBonus: 15,
      localActivityModifier: 1.2,
      unlocks: <String>[
        'Systèmes sociaux avancés plus tard',
        'Relais commun plus tard',
        'Lisière lointaine plus complète',
        'Routes commerciales plus tard',
        '4 P’TIPOTES actifs confortables',
      ],
      effects: <String>[
        'Meilleure stabilité du refuge',
        'Événements positifs plus fréquents',
        'Marché plus vivant',
      ],
    ),
    CampHeartStageConfig(
      level: 5,
      stage: CampStage.petiteVille,
      label: 'Petite ville',
      organicRequiredForNextLevel: null,
      populationLabel: 'à définir plus tard',
      populationMin: null,
      populationMax: null,
      activePtipoteComfortLimit: 5,
      refugeHappinessBonus: 20,
      localActivityModifier: 1.3,
      unlocks: <String>[
        'Placeholder futur',
        'Mairie plus tard',
        'Organisation avancée',
        'Systèmes de groupe plus tard',
        'Zone 1 avancée plus tard',
      ],
      effects: <String>['Placeholder futur'],
    ),
  ],
);

CampHeartConfig campHeartConfig = defaultCampHeartConfig;
