enum CampStage { camp, refuge, bourgade, village, petiteVille }

class CampHeartConfig {
  const CampHeartConfig({required this.stages});

  final List<CampHeartStageConfig> stages;

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
    required this.xpRequiredForNextLevel,
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
  final int? xpRequiredForNextLevel;
  final String populationLabel;
  final int? populationMin;
  final int? populationMax;
  final int activePtipoteComfortLimit;
  final int refugeHappinessBonus;
  final double localActivityModifier;
  final List<String> unlocks;
  final List<String> effects;
}

const campHeartConfig = CampHeartConfig(
  stages: <CampHeartStageConfig>[
    CampHeartStageConfig(
      level: 1,
      stage: CampStage.camp,
      label: 'Camp',
      xpRequiredForNextLevel: 100,
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
        'Colline',
        'Plaine riche',
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
      xpRequiredForNextLevel: 250,
      populationLabel: '7 à 12 habitants',
      populationMin: 7,
      populationMax: 12,
      activePtipoteComfortLimit: 2,
      refugeHappinessBonus: 5,
      localActivityModifier: 1.05,
      unlocks: <String>[
        'Atelier simple',
        'Tour',
        'Bassin minéral',
        'Sous-bois',
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
      xpRequiredForNextLevel: 500,
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
      xpRequiredForNextLevel: 900,
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
      xpRequiredForNextLevel: null,
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
