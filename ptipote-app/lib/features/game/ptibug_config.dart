enum PTibugSpecies { scarabe, hyme, arac }

enum PTibugTraitType { pollinisateur, mineur, decomposeur }

enum PTibugTraitGrade { commun, rare, avance }

enum PTibugModuleType { ailes, pinces, reservoir }

class PTibugSpeciesConfig {
  const PTibugSpeciesConfig({
    required this.displayName,
    required this.styles,
    required this.creationCost,
    required this.creationEnergyCost,
    required this.creationMinutes,
  });

  final String displayName;
  final List<String> styles;
  final Map<String, int> creationCost;
  final int creationEnergyCost;
  final int creationMinutes;
}

class PTibugConfig {
  const PTibugConfig({
    required this.nurseryRequirements,
    required this.nurseryDurationMinutes,
    required this.slotsByLevel,
    required this.moduleSlotsByLevel,
    required this.productionCycleMinutes,
    required this.carryingCapacity,
    required this.species,
  });

  final Map<String, int> nurseryRequirements;
  final int nurseryDurationMinutes;
  final Map<int, int> slotsByLevel;
  final Map<int, int> moduleSlotsByLevel;
  final int productionCycleMinutes;
  final int carryingCapacity;
  final Map<PTibugSpecies, PTibugSpeciesConfig> species;

  int slotsForLevel(int level) => slotsByLevel[level.clamp(1, 3)] ?? 1;
  int moduleSlotsForLevel(int level) =>
      moduleSlotsByLevel[level.clamp(1, 3)] ?? 1;
}

const pTibugConfig = PTibugConfig(
  nurseryRequirements: <String, int>{'Organique': 20, 'Minéral': 35},
  nurseryDurationMinutes: 1,
  slotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  moduleSlotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  productionCycleMinutes: 60,
  carryingCapacity: 6,
  species: <PTibugSpecies, PTibugSpeciesConfig>{
    PTibugSpecies.scarabe: PTibugSpeciesConfig(
      displayName: 'Scarabé',
      styles: <String>['compact', 'cornu', 'cuirassé'],
      creationCost: <String, int>{'Organique': 2, 'Minéral': 4},
      creationEnergyCost: 5,
      creationMinutes: 20,
    ),
    PTibugSpecies.hyme: PTibugSpeciesConfig(
      displayName: 'Hyme',
      styles: <String>['fourmi', 'abeille', 'guêpe'],
      creationCost: <String, int>{'Organique': 4, 'Minéral': 2},
      creationEnergyCost: 5,
      creationMinutes: 20,
    ),
    PTibugSpecies.arac: PTibugSpeciesConfig(
      displayName: 'Arac',
      styles: <String>['toile', 'chasseuse', 'sauteuse'],
      creationCost: <String, int>{'Organique': 3, 'Minéral': 3},
      creationEnergyCost: 5,
      creationMinutes: 25,
    ),
  },
);
