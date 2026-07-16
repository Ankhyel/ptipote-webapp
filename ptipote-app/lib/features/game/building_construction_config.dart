/// Central V1 settings for communal construction projects.
class BuildingConstructionConfig {
  const BuildingConstructionConfig({
    required this.mineralCostMultiplier,
    required this.defaultDurationMinutes,
    required this.projects,
  });

  final double mineralCostMultiplier;
  final int defaultDurationMinutes;
  final Map<String, BuildingProjectDefinition> projects;

  BuildingProjectDefinition project(String id) => projects[id]!;
}

class BuildingProjectDefinition {
  const BuildingProjectDefinition({
    required this.id,
    required this.label,
    required this.baseRequirements,
    required this.durationMinutes,
  });

  final String id;
  final String label;
  final Map<String, int> baseRequirements;
  final int durationMinutes;

  Map<String, int> requirements(double mineralMultiplier) =>
      baseRequirements.map((resource, amount) => MapEntry(
            resource,
            resource == 'Minéral'
                ? (amount * mineralMultiplier).ceil()
                : amount,
          ));
}

const buildingConstructionConfig = BuildingConstructionConfig(
  mineralCostMultiplier: 1.30,
  defaultDurationMinutes: 1,
  projects: <String, BuildingProjectDefinition>{
    'fablab': BuildingProjectDefinition(
      id: 'fablab',
      label: 'Fablab',
      baseRequirements: <String, int>{'Organique': 8, 'Minéral': 4},
      durationMinutes: 1,
    ),
    'securityTower': BuildingProjectDefinition(
      id: 'securityTower',
      label: 'Tour de sécurité',
      baseRequirements: <String, int>{'Organique': 6, 'Minéral': 8},
      durationMinutes: 1,
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
    'plaineNursery': BuildingProjectDefinition(
      id: 'plaineNursery',
      label: 'Nurserie P’TIBUG',
      baseRequirements: <String, int>{'Organique': 20, 'Minéral': 35},
      durationMinutes: 1,
    ),
  },
);
