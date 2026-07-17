enum KernelAxis { breeder, builder, restorer }

enum KernelProgressEventType {
  buildingConstructed,
  buildingUpgraded,
  craftCompleted,
  ptipoteCraftCompleted,
  missionCompleted,
  towerMissionCompleted,
  ptipoteFed,
  ptipoteHappy,
  ptipoteWellRested,
  pollutionObserved,
  ecosystemLevelUp,
  ptibugCreated,
  ptibugTraitEquipped,
  traitDataFused,
  ptibugModuleEquipped,
  ptibugProductionCollected,
  firstMyceliumProduced,
}

enum KernelPlanCategory { buildings, workshop, cuisine, ptibug, installations }

enum KernelPlanState { unknown, discovered, ready, active }

class KernelProgressReward {
  const KernelProgressReward({
    this.trustXp = 0,
    this.breederXp = 0,
    this.builderXp = 0,
    this.restorerXp = 0,
  });

  final int trustXp;
  final int breederXp;
  final int builderXp;
  final int restorerXp;

  int xpFor(KernelAxis axis) => switch (axis) {
        KernelAxis.breeder => breederXp,
        KernelAxis.builder => builderXp,
        KernelAxis.restorer => restorerXp,
      };
}

class KernelTechnologyPlanConfig {
  const KernelTechnologyPlanConfig({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.iconName,
    required this.origin,
    required this.kernelText,
    required this.discoveryEvent,
    required this.discoveryThreshold,
    required this.requiredTrustLevel,
    required this.requiredAxis,
    required this.requiredAxisLevel,
    required this.workshopRecipeId,
    this.requiredBreederLevel = 0,
    this.requiredBuilderLevel = 0,
    this.requiredRestorerLevel = 0,
    this.requiredBuildingLevels = const <String, int>{},
    this.initialState = KernelPlanState.unknown,
  });

  final String id;
  final String title;
  final String description;
  final KernelPlanCategory category;
  final String iconName;
  final String origin;
  final String kernelText;
  final KernelProgressEventType? discoveryEvent;
  final int discoveryThreshold;
  final int requiredTrustLevel;
  final KernelAxis? requiredAxis;
  final int requiredAxisLevel;
  final String? workshopRecipeId;
  final int requiredBreederLevel;
  final int requiredBuilderLevel;
  final int requiredRestorerLevel;
  final Map<String, int> requiredBuildingLevels;
  final KernelPlanState initialState;
}

class KernelProgressConfig {
  const KernelProgressConfig({
    required this.trustXpRequiredBase,
    required this.axisXpRequiredBase,
    required this.xpRequiredMultiplier,
    required this.eventRewards,
    required this.plans,
  });

  final int trustXpRequiredBase;
  final int axisXpRequiredBase;
  final double xpRequiredMultiplier;
  final Map<KernelProgressEventType, KernelProgressReward> eventRewards;
  final List<KernelTechnologyPlanConfig> plans;

  int xpRequired({required int level, required bool isTrust}) {
    final base = isTrust ? trustXpRequiredBase : axisXpRequiredBase;
    var multiplier = 1.0;
    for (var index = 0; index < level - 1; index += 1) {
      multiplier *= xpRequiredMultiplier;
    }
    return (base * multiplier).round();
  }
}

const KernelProgressConfig defaultKernelProgressConfig = KernelProgressConfig(
  trustXpRequiredBase: 100,
  axisXpRequiredBase: 80,
  xpRequiredMultiplier: 1.25,
  eventRewards: <KernelProgressEventType, KernelProgressReward>{
    KernelProgressEventType.buildingConstructed:
        KernelProgressReward(trustXp: 25, builderXp: 25),
    KernelProgressEventType.buildingUpgraded:
        KernelProgressReward(trustXp: 20, builderXp: 20),
    KernelProgressEventType.craftCompleted:
        KernelProgressReward(trustXp: 8, builderXp: 4, restorerXp: 4),
    KernelProgressEventType.ptipoteCraftCompleted:
        KernelProgressReward(trustXp: 1, breederXp: 5),
    KernelProgressEventType.missionCompleted:
        KernelProgressReward(trustXp: 2, breederXp: 10),
    KernelProgressEventType.towerMissionCompleted:
        KernelProgressReward(trustXp: 2, breederXp: 10),
    KernelProgressEventType.ptipoteFed: KernelProgressReward(breederXp: 1),
    KernelProgressEventType.ptipoteHappy:
        KernelProgressReward(trustXp: 1, breederXp: 5),
    KernelProgressEventType.ptipoteWellRested:
        KernelProgressReward(breederXp: 1),
    KernelProgressEventType.pollutionObserved:
        KernelProgressReward(trustXp: 5, restorerXp: 12),
    KernelProgressEventType.ecosystemLevelUp:
        KernelProgressReward(trustXp: 30, restorerXp: 25),
    KernelProgressEventType.ptibugCreated:
        KernelProgressReward(trustXp: 15, breederXp: 25),
    KernelProgressEventType.ptibugTraitEquipped:
        KernelProgressReward(trustXp: 5, breederXp: 10),
    KernelProgressEventType.traitDataFused:
        KernelProgressReward(trustXp: 10, breederXp: 18),
    KernelProgressEventType.ptibugModuleEquipped:
        KernelProgressReward(trustXp: 6, breederXp: 10),
    KernelProgressEventType.ptibugProductionCollected:
        KernelProgressReward(trustXp: 2, breederXp: 3),
    KernelProgressEventType.firstMyceliumProduced:
        KernelProgressReward(trustXp: 12, breederXp: 16),
  },
  plans: <KernelTechnologyPlanConfig>[
    KernelTechnologyPlanConfig(
      id: 'ptibug-pattern-scarabe',
      title: 'Pattern Scarabé',
      description: 'Un pattern de base pour créer un P’TIBUG Scarabé.',
      category: KernelPlanCategory.ptibug,
      iconName: 'scarabe',
      origin: 'Le Kernel le transmet à l’ouverture de la Nurserie.',
      kernelText: 'Un collecteur robuste constitue une première fondation.',
      discoveryEvent: null,
      discoveryThreshold: 0,
      requiredTrustLevel: 1,
      requiredAxis: null,
      requiredAxisLevel: 1,
      workshopRecipeId: null,
      requiredBuildingLevels: <String, int>{
        'plaineNursery': 1,
        'house': 0,
        'fablab': 0,
        'cuisine': 0,
        'atelier': 0,
        'recycler': 0,
        'securityTower': 0,
        'market': 0,
      },
      initialState: KernelPlanState.discovered,
    ),
    KernelTechnologyPlanConfig(
      id: 'ptibug-pattern-hyme',
      title: 'Pattern Hymé',
      description: 'Un pattern de P’TIBUG spécialisé dans l’Organique.',
      category: KernelPlanCategory.ptibug,
      iconName: 'hyme',
      origin: 'Observé après la création du premier P’TIBUG.',
      kernelText:
          'Le comportement des premiers collecteurs révèle une forme plus vive.',
      discoveryEvent: KernelProgressEventType.ptibugCreated,
      discoveryThreshold: 1,
      requiredTrustLevel: 1,
      requiredAxis: KernelAxis.breeder,
      requiredAxisLevel: 1,
      workshopRecipeId: null,
      requiredBreederLevel: 1,
      requiredBuildingLevels: <String, int>{
        'plaineNursery': 1,
        'house': 0,
        'fablab': 0,
        'cuisine': 0,
        'atelier': 0,
        'recycler': 0,
        'securityTower': 0,
        'market': 0,
      },
    ),
    KernelTechnologyPlanConfig(
      id: 'ptibug-pattern-arac',
      title: 'Pattern Arac',
      description: 'Un pattern de P’TIBUG agile à la collecte adaptable.',
      category: KernelPlanCategory.ptibug,
      iconName: 'arac',
      origin: 'Affiné grâce aux premières collectes de P’TIBUG.',
      kernelText:
          'Les cycles de collecte stabilisent une forme plus adaptable.',
      discoveryEvent: KernelProgressEventType.ptibugProductionCollected,
      discoveryThreshold: 3,
      requiredTrustLevel: 2,
      requiredAxis: KernelAxis.breeder,
      requiredAxisLevel: 2,
      workshopRecipeId: null,
      requiredBreederLevel: 2,
      requiredBuildingLevels: <String, int>{
        'plaineNursery': 1,
        'house': 0,
        'fablab': 0,
        'cuisine': 0,
        'atelier': 0,
        'recycler': 0,
        'securityTower': 0,
        'market': 0,
      },
    ),
    KernelTechnologyPlanConfig(
      id: 'simple-furniture',
      title: 'Meuble simple',
      description: 'Un premier équipement utile pour organiser le refuge.',
      category: KernelPlanCategory.workshop,
      iconName: 'chair',
      origin: 'Disponible après les premiers travaux de l’Atelier.',
      kernelText: 'Les formes de base sont déjà suffisamment comprises.',
      discoveryEvent: null,
      discoveryThreshold: 0,
      requiredTrustLevel: 1,
      requiredAxis: null,
      requiredAxisLevel: 1,
      workshopRecipeId: 'simpleFurniture',
      initialState: KernelPlanState.active,
    ),
    KernelTechnologyPlanConfig(
      id: 'filter',
      title: 'Filtre',
      description: 'Un filtre artisanal contre les particules en suspension.',
      category: KernelPlanCategory.workshop,
      iconName: 'filter',
      origin: 'Découvert après plusieurs observations de pollution.',
      kernelText:
          'Les équipes semblent ralenties par les particules en suspension.',
      discoveryEvent: KernelProgressEventType.pollutionObserved,
      discoveryThreshold: 3,
      requiredTrustLevel: 2,
      requiredAxis: KernelAxis.restorer,
      requiredAxisLevel: 1,
      workshopRecipeId: 'filter',
    ),
    KernelTechnologyPlanConfig(
      id: 'filter-cartridge',
      title: 'Cartouche de filtration',
      description: 'Une cartouche remplaçable qui prolonge la filtration.',
      category: KernelPlanCategory.workshop,
      iconName: 'cartridge',
      origin: 'Découvert après la fabrication de plusieurs filtres.',
      kernelText:
          'La répétition des filtres révèle une pièce à rendre remplaçable.',
      discoveryEvent: KernelProgressEventType.craftCompleted,
      discoveryThreshold: 3,
      requiredTrustLevel: 2,
      requiredAxis: KernelAxis.restorer,
      requiredAxisLevel: 2,
      workshopRecipeId: 'filterCartridge',
    ),
    KernelTechnologyPlanConfig(
      id: 'shade-suit',
      title: 'Tenue ombragée',
      description:
          'Une tenue légère pour les sorties sous un climat difficile.',
      category: KernelPlanCategory.workshop,
      iconName: 'suit',
      origin: 'Inspirée des sorties répétées dans les biomes chauds.',
      kernelText: 'La chaleur impose une enveloppe plus protectrice.',
      discoveryEvent: KernelProgressEventType.missionCompleted,
      discoveryThreshold: 3,
      requiredTrustLevel: 2,
      requiredAxis: KernelAxis.builder,
      requiredAxisLevel: 2,
      workshopRecipeId: 'shadeSuit',
    ),
    KernelTechnologyPlanConfig(
      id: 'termite-ventilation',
      title: 'Ventilation Termite',
      description: 'Une installation inspirée des termitières voisines.',
      category: KernelPlanCategory.installations,
      iconName: 'air',
      origin:
          'Inspirée des termitières voisines et de la croissance du refuge.',
      kernelText: 'La communauté a besoin de mieux faire circuler l’air.',
      discoveryEvent: KernelProgressEventType.buildingConstructed,
      discoveryThreshold: 3,
      requiredTrustLevel: 3,
      requiredAxis: KernelAxis.builder,
      requiredAxisLevel: 2,
      workshopRecipeId: 'termiteVentilation',
    ),
    KernelTechnologyPlanConfig(
      id: 'solar-light',
      title: 'Lumière solaire',
      description: 'Un éclairage autonome pour les espaces du refuge.',
      category: KernelPlanCategory.installations,
      iconName: 'light',
      origin: 'Développée après les premiers travaux de végétalisation.',
      kernelText:
          'Les zones aménagées nécessitent une lumière douce et durable.',
      discoveryEvent: KernelProgressEventType.ecosystemLevelUp,
      discoveryThreshold: 1,
      requiredTrustLevel: 3,
      requiredAxis: KernelAxis.builder,
      requiredAxisLevel: 2,
      workshopRecipeId: 'solarLight',
    ),
  ],
);

KernelProgressConfig kernelProgressConfig = defaultKernelProgressConfig;
