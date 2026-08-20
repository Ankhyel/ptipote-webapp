import 'dart:math' as math;

/// Central V1 settings for communal construction projects.
class BuildingConstructionConfig {
  const BuildingConstructionConfig({
    required this.mineralCostMultiplier,
    required this.defaultDurationMinutes,
    required this.globalBaseDurationMultiplier,
    required this.ptipoteMaterialReduction,
    required this.ptipoteLevelTimeReductionPerLevel,
    required this.constructorReductionByLevel,
    required this.projects,
  });

  final double mineralCostMultiplier;
  final int defaultDurationMinutes;

  /// Applied to new construction/upgrade projects only. Existing project
  /// snapshots retain their original completion timestamp during migration.
  final double globalBaseDurationMultiplier;
  final double ptipoteMaterialReduction;
  final double ptipoteLevelTimeReductionPerLevel;
  final Map<int, double> constructorReductionByLevel;
  final Map<String, BuildingProjectDefinition> projects;

  double constructorReduction(int jobLevel, int ptipoteLevel) =>
      ((constructorReductionByLevel[jobLevel.clamp(0, 4).toInt()] ?? 0) +
              ptipoteLevel.clamp(0, 99) * ptipoteLevelTimeReductionPerLevel)
          .clamp(0, .95)
          .toDouble();

  BuildingProjectDefinition project(String id) => projects[id]!;
}

class BuildingProjectDefinition {
  const BuildingProjectDefinition({
    required this.id,
    required this.label,
    required this.baseRequirements,
    required this.durationMinutes,
    this.requiredData = const <String, int>{},
    this.requiredDataByLevel = const <int, Map<String, int>>{},
    this.bypassBiomimicryRequirement = false,
    this.requiredJobLevel = const <String, int>{},
    this.unattendedEnergyCost = 1,
    this.unattendedEnergyCostByLevel = const <int, int>{},
  });

  final String id;
  final String label;
  final Map<String, int> baseRequirements;
  final int durationMinutes;

  /// Scientific data is a direct, configurable construction cost. Keys are
  /// the stable PTibugDataFamily names (biomimetisme, organique, ...).
  final Map<String, int> requiredData;

  /// Optional per-target-level overrides. Without one, [requiredData]
  /// remains the shared cost for all levels of this project.
  final Map<int, Map<String, int>> requiredDataByLevel;

  /// Only onboarding may bypass Biomimétisme: the initial research tower
  /// cannot require data before the player has a way to earn any.
  final bool bypassBiomimicryRequirement;

  /// Hook for future construction unlocks, e.g. {'artisan': 2}.
  final Map<String, int> requiredJobLevel;

  /// Energy consumed by automated construction when no P'TIPOTE is assigned.
  final int unattendedEnergyCost;
  final Map<int, int> unattendedEnergyCostByLevel;

  Map<String, int> requirements(double mineralMultiplier) =>
      baseRequirements.map((resource, amount) => MapEntry(
            resource,
            resource == 'Minéral'
                ? (amount * mineralMultiplier).ceil()
                : amount,
          ));

  Map<String, int> dataRequirementsForLevel(int level) =>
      requiredDataByLevel[level] ?? requiredData;

  int unattendedEnergyCostForLevel(int level) =>
      math.max(0, unattendedEnergyCostByLevel[level] ?? unattendedEnergyCost);
}

const BuildingConstructionConfig defaultBuildingConstructionConfig =
    BuildingConstructionConfig(
  mineralCostMultiplier: 1.30,
  defaultDurationMinutes: 1,
  globalBaseDurationMultiplier: 2,
  ptipoteMaterialReduction: .20,
  ptipoteLevelTimeReductionPerLevel: .01,
  constructorReductionByLevel: <int, double>{
    0: 0,
    1: .15,
    2: .20,
    3: .25,
    4: .30,
  },
  projects: <String, BuildingProjectDefinition>{
    'fablab': BuildingProjectDefinition(
      id: 'fablab',
      label: 'Fablab',
      baseRequirements: <String, int>{'Organique': 8, 'Minéral': 4},
      durationMinutes: 1,
      requiredData: <String, int>{'biomimetisme': 1},
    ),
    'cuisine': BuildingProjectDefinition(
      id: 'cuisine',
      label: 'Cuisine',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 12},
      durationMinutes: 1,
      requiredData: <String, int>{'biomimetisme': 1, 'organique': 1},
    ),
    'atelier': BuildingProjectDefinition(
      id: 'atelier',
      label: 'Atelier',
      baseRequirements: <String, int>{'Organique': 8, 'Minéral': 16},
      durationMinutes: 1,
      requiredData: <String, int>{
        'biomimetisme': 1,
        'organique': 1,
        'minerale': 1,
        'energie': 1,
      },
    ),
    'recycler': BuildingProjectDefinition(
      id: 'recycler',
      label: 'Recycleur',
      baseRequirements: <String, int>{'Organique': 10, 'Minéral': 18},
      durationMinutes: 1,
      requiredData: <String, int>{
        'biomimetisme': 1,
        'organique': 1,
        'minerale': 1,
        'energie': 1,
      },
    ),
    'securityTower': BuildingProjectDefinition(
      id: 'securityTower',
      label: 'Tour de sécurité',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 8},
      durationMinutes: 1,
    ),
    // Les deux équipements sont des améliorations de la Tour : ils gardent
    // volontairement le même coût que sa construction initiale.
    'towerWeatherModule': BuildingProjectDefinition(
      id: 'towerWeatherModule',
      label: 'Tour météo',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 8},
      durationMinutes: 1,
      requiredData: <String, int>{'biomimetisme': 1, 'energie': 1},
    ),
    'towerResearchModule': BuildingProjectDefinition(
      id: 'towerResearchModule',
      label: 'Tour de recherche',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 8},
      durationMinutes: 1,
      bypassBiomimicryRequirement: true,
    ),
    'market': BuildingProjectDefinition(
      id: 'market',
      label: 'Marché',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 6},
      durationMinutes: 1,
    ),
    'house': BuildingProjectDefinition(
      id: 'house',
      label: 'Maison',
      baseRequirements: <String, int>{'Organique': 5, 'Minéral': 9},
      durationMinutes: 1,
    ),
    'housing': BuildingProjectDefinition(
      id: 'housing',
      label: 'Logement',
      baseRequirements: <String, int>{'Organique': 30, 'Minéral': 60},
      durationMinutes: 60,
    ),
    'logistics': BuildingProjectDefinition(
      id: 'logistics',
      label: 'Bâtiment Logistique',
      baseRequirements: <String, int>{'Organique': 20, 'Minéral': 20},
      durationMinutes: 60,
      requiredData: <String, int>{'biomimetisme': 2, 'energie': 1},
      unattendedEnergyCost: 2,
    ),
    'plaineNursery': BuildingProjectDefinition(
      id: 'plaineNursery',
      label: 'Nurserie P’TIBUG',
      baseRequirements: <String, int>{'Organique': 20, 'Minéral': 35},
      durationMinutes: 1,
    ),
  },
);

/// Runtime-tunable through the developer Dashboard. Player progress is never
/// stored here; only the shared construction prices and durations are.
BuildingConstructionConfig buildingConstructionConfig =
    defaultBuildingConstructionConfig;
