enum KernelMissionType { main, refugeRequest, weather }

enum KernelMissionStatus { locked, active, completed }

enum KernelMissionConditionType {
  fablabBuilt,
  securityTowerBuilt,
  mealsPrepared,
  plaineMissionsCompleted,
  requirementsMet,
}

class KernelConfig {
  const KernelConfig({
    required this.startingPopulation,
    required this.startingWellbeing,
    required this.startingBioBatteries,
    required this.maxRefugeRequests,
    required this.populationCapacityByCampHeartLevel,
    required this.wellbeingRedThreshold,
    required this.wellbeingOrangeThreshold,
    required this.missions,
    required this.plans,
  });

  final int startingPopulation;
  final int startingWellbeing;
  final int startingBioBatteries;
  final int maxRefugeRequests;
  final Map<int, int> populationCapacityByCampHeartLevel;
  final int wellbeingRedThreshold;
  final int wellbeingOrangeThreshold;
  final List<KernelMissionConfig> missions;
  final List<KernelPlanConfig> plans;

  int populationCapacityForCampHeartLevel(int level) {
    final safeLevel = level.clamp(1, 5);
    return populationCapacityByCampHeartLevel[safeLevel] ??
        populationCapacityByCampHeartLevel.values.last;
  }
}

class KernelMissionConfig {
  const KernelMissionConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.conditionType,
    required this.requiredAmount,
    required this.populationReward,
    required this.bioBatteryReward,
    required this.xpReward,
    required this.mailMessage,
    this.requiredBuildingLevels = const <String, int>{},
    this.requiredKernelTrustLevel = 1,
    this.requiredBreederLevel = 1,
    this.requiredBuilderLevel = 1,
    this.requiredRestorerLevel = 1,
    this.requestedItem,
    this.requestedAmount = 0,
    this.resourceRewards = const <String, int>{},
    this.rewardPatternId,
    this.weatherType,
    this.weatherDemandOptions = const <String>[],
  });

  final String id;
  final KernelMissionType type;
  final String title;
  final String description;
  final KernelMissionConditionType conditionType;
  final int requiredAmount;
  final int populationReward;
  final int bioBatteryReward;
  final int xpReward;
  final String mailMessage;
  final Map<String, int> requiredBuildingLevels;
  final int requiredKernelTrustLevel;
  final int requiredBreederLevel;
  final int requiredBuilderLevel;
  final int requiredRestorerLevel;
  final String? requestedItem;
  final int requestedAmount;
  final Map<String, int> resourceRewards;
  final String? rewardPatternId;
  final String? weatherType;
  final List<String> weatherDemandOptions;
}

class KernelMissionProgress {
  const KernelMissionProgress({
    required this.config,
    required this.progress,
    required this.status,
  });

  final KernelMissionConfig config;
  final int progress;
  final KernelMissionStatus status;

  bool get isCompleted => status == KernelMissionStatus.completed;
}

class KernelPlanConfig {
  const KernelPlanConfig({
    required this.id,
    required this.title,
    required this.description,
    required this.requiredCampHeartLevel,
  });

  final String id;
  final String title;
  final String description;
  final int requiredCampHeartLevel;
}

const KernelConfig defaultKernelConfig = KernelConfig(
  startingPopulation: 4,
  startingWellbeing: 70,
  startingBioBatteries: 0,
  maxRefugeRequests: 3,
  populationCapacityByCampHeartLevel: <int, int>{
    1: 5,
    2: 10,
    3: 18,
    4: 30,
    5: 50,
  },
  wellbeingRedThreshold: 40,
  wellbeingOrangeThreshold: 70,
  missions: <KernelMissionConfig>[
    KernelMissionConfig(
      id: 'build-fablab',
      type: KernelMissionType.main,
      title: 'Construire le Fablab',
      description:
          'Le refuge a besoin d’un espace pour cuisiner et préparer ses ressources.',
      conditionType: KernelMissionConditionType.fablabBuilt,
      requiredAmount: 1,
      populationReward: 1,
      bioBatteryReward: 0,
      xpReward: 0,
      mailMessage:
          'Un nouvel habitant s’installe près du refuge après la construction du Fablab.',
    ),
    KernelMissionConfig(
      id: 'build-security-tower',
      type: KernelMissionType.refugeRequest,
      title: 'Construire la Tour',
      description:
          'La communauté veut sécuriser les abords avant d’envoyer plus de sorties.',
      conditionType: KernelMissionConditionType.securityTowerBuilt,
      requiredAmount: 1,
      populationReward: 1,
      bioBatteryReward: 0,
      xpReward: 0,
      mailMessage:
          'Un nouvel habitant rejoint le refuge grâce à la Tour de sécurité.',
    ),
    KernelMissionConfig(
      id: 'prepare-five-meals',
      type: KernelMissionType.refugeRequest,
      title: 'Préparer 5 repas',
      description:
          'La Cuisine doit prouver que le refuge peut nourrir plus de monde.',
      conditionType: KernelMissionConditionType.mealsPrepared,
      requiredAmount: 5,
      populationReward: 2,
      bioBatteryReward: 0,
      xpReward: 0,
      mailMessage:
          'Deux nouveaux habitants se sont installés près du refuge après les premiers repas.',
    ),
    KernelMissionConfig(
      id: 'plaine-forage-runs',
      type: KernelMissionType.refugeRequest,
      title: 'Explorer plusieurs fois la Plaine',
      description:
          'La Plaine doit être reconnue avant d’accueillir plus de passages.',
      conditionType: KernelMissionConditionType.plaineMissionsCompleted,
      requiredAmount: 3,
      populationReward: 1,
      bioBatteryReward: 0,
      xpReward: 0,
      mailMessage:
          'Un habitant rejoint le refuge après les reconnaissances en Plaine.',
    ),
    KernelMissionConfig(
      id: 'weather-toxic-cloud',
      type: KernelMissionType.weather,
      title: 'Filtrer le nuage',
      description: 'La Tour demande un Filtre pour atténuer le nuage toxique.',
      conditionType: KernelMissionConditionType.requirementsMet,
      requiredAmount: 1,
      populationReward: 0,
      bioBatteryReward: 1,
      xpReward: 2,
      requestedItem: 'Filtre',
      requestedAmount: 1,
      weatherType: 'toxicCloud',
      mailMessage: 'Le nuage toxique a été filtré avant son arrivée.',
    ),
    KernelMissionConfig(
      id: 'weather-heat-wave',
      type: KernelMissionType.weather,
      title: 'Protéger du soleil',
      description: 'La Tour demande une Tenue ombragée avant la forte chaleur.',
      conditionType: KernelMissionConditionType.requirementsMet,
      requiredAmount: 1,
      populationReward: 0,
      bioBatteryReward: 1,
      xpReward: 2,
      requestedItem: 'Tenue ombragée',
      requestedAmount: 1,
      weatherType: 'heatWave',
      mailMessage: 'La Maison a été protégée de la forte chaleur.',
    ),
    KernelMissionConfig(
      id: 'weather-heavy-rain',
      type: KernelMissionType.weather,
      title: 'Assécher les passages',
      description:
          'La Tour demande une Ventilation Termite avant la pluie intense.',
      conditionType: KernelMissionConditionType.requirementsMet,
      requiredAmount: 1,
      populationReward: 0,
      bioBatteryReward: 1,
      xpReward: 2,
      requestedItem: 'Ventilation Termite',
      requestedAmount: 1,
      weatherType: 'heavyRain',
      mailMessage: 'Les passages ont été préparés avant la pluie intense.',
    ),
  ],
  plans: <KernelPlanConfig>[
    KernelPlanConfig(
      id: 'cuisine',
      title: 'Cuisine',
      description: 'Préparer repas et boissons pour les P’TIPOTES.',
      requiredCampHeartLevel: 1,
    ),
    KernelPlanConfig(
      id: 'atelier',
      title: 'Atelier',
      description: 'Fabrication simple. Gameplay à venir.',
      requiredCampHeartLevel: 2,
    ),
    KernelPlanConfig(
      id: 'security-tower',
      title: 'Tour',
      description: 'Réduit les risques en Lisière.',
      requiredCampHeartLevel: 2,
    ),
    KernelPlanConfig(
      id: 'recycler',
      title: 'Recycleur',
      description: 'Transformer les surplus. Gameplay à venir.',
      requiredCampHeartLevel: 3,
    ),
    KernelPlanConfig(
      id: 'ptibug-refuge',
      title: 'Refuge PTIBUG',
      description: 'Abri et schémas PTIBUG. À venir.',
      requiredCampHeartLevel: 2,
    ),
  ],
);

KernelConfig kernelConfig = defaultKernelConfig;
