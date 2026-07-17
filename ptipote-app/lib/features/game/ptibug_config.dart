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

/// A Pattern is the Kernel knowledge required before the Nurserie can create
/// a species. The creation recipe itself stays on [PTibugSpeciesConfig].
class PTibugPatternConfig {
  const PTibugPatternConfig({
    required this.species,
    required this.kernelPlanId,
    required this.description,
  });

  final PTibugSpecies species;
  final String kernelPlanId;
  final String description;
}

class PTibugTraitDefinition {
  const PTibugTraitDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.effects,
    required this.gradeMultipliers,
  });

  final String id;
  final String displayName;
  final String description;
  final Map<String, int> effects;
  final Map<PTibugTraitGrade, int> gradeMultipliers;

  Map<String, int> productionFor(PTibugTraitGrade grade) => effects.map(
        (resource, amount) => MapEntry(
          resource,
          amount * (gradeMultipliers[grade] ?? 1),
        ),
      );
}

class PTibugConfig {
  const PTibugConfig({
    required this.nurseryRequirements,
    required this.nurseryDurationMinutes,
    required this.slotsByLevel,
    required this.moduleSlotsByLevel,
    required this.productionCycleMinutes,
    required this.carryingCapacity,
    required this.xpPerCycle,
    required this.wingsCycleReduction,
    required this.clawProductionBonus,
    required this.reservoirCapacityBonus,
    required this.species,
    required this.patterns,
    required this.sourcierPatternPrices,
    required this.traitDefinitions,
  });

  final Map<String, int> nurseryRequirements;
  final int nurseryDurationMinutes;
  final Map<int, int> slotsByLevel;
  final Map<int, int> moduleSlotsByLevel;
  final int productionCycleMinutes;
  final int carryingCapacity;
  final int xpPerCycle;
  final double wingsCycleReduction;
  final int clawProductionBonus;
  final int reservoirCapacityBonus;
  final Map<PTibugSpecies, PTibugSpeciesConfig> species;
  final Map<PTibugSpecies, PTibugPatternConfig> patterns;
  final Map<PTibugSpecies, int> sourcierPatternPrices;
  final Map<String, PTibugTraitDefinition> traitDefinitions;

  int slotsForLevel(int level) => slotsByLevel[level.clamp(1, 3)] ?? 1;
  int moduleSlotsForLevel(int level) =>
      moduleSlotsByLevel[level.clamp(1, 3)] ?? 1;

  int traitMultiplier(PTibugTraitGrade grade) => grade.index + 1;

  PTibugTraitDefinition? traitDefinitionFor(String id) => traitDefinitions[id];

  PTibugPatternConfig? patternForKernelPlanId(String planId) {
    for (final pattern in patterns.values) {
      if (pattern.kernelPlanId == planId) return pattern;
    }
    return null;
  }
}

const PTibugConfig defaultPTibugConfig = PTibugConfig(
  nurseryRequirements: <String, int>{'Organique': 20, 'Minéral': 35},
  nurseryDurationMinutes: 1,
  slotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  moduleSlotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  productionCycleMinutes: 60,
  carryingCapacity: 6,
  xpPerCycle: 1,
  wingsCycleReduction: 0.15,
  clawProductionBonus: 1,
  reservoirCapacityBonus: 4,
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
  patterns: <PTibugSpecies, PTibugPatternConfig>{
    PTibugSpecies.scarabe: PTibugPatternConfig(
      species: PTibugSpecies.scarabe,
      kernelPlanId: 'ptibug-pattern-scarabe',
      description: 'Un premier collecteur robuste pour les sols du refuge.',
    ),
    PTibugSpecies.hyme: PTibugPatternConfig(
      species: PTibugSpecies.hyme,
      kernelPlanId: 'ptibug-pattern-hyme',
      description: 'Un P’TIBUG rapide, adapté aux ressources organiques.',
    ),
    PTibugSpecies.arac: PTibugPatternConfig(
      species: PTibugSpecies.arac,
      kernelPlanId: 'ptibug-pattern-arac',
      description: 'Un collecteur agile capable de s’adapter à sa collecte.',
    ),
  },
  sourcierPatternPrices: <PTibugSpecies, int>{
    PTibugSpecies.hyme: 6,
    PTibugSpecies.arac: 8,
  },
  traitDefinitions: <String, PTibugTraitDefinition>{
    'pollinisateur': PTibugTraitDefinition(
      id: 'pollinisateur',
      displayName: 'Pollinisateur',
      description: 'Améliore la collecte organique.',
      effects: <String, int>{'Organique': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
    ),
    'mineur': PTibugTraitDefinition(
      id: 'mineur',
      displayName: 'Mineur',
      description: 'Améliore la collecte minérale.',
      effects: <String, int>{'Minéral': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
    ),
    'decomposeur': PTibugTraitDefinition(
      id: 'decomposeur',
      displayName: 'Décomposeur',
      description: 'Transforme les matières en organique et mycélium.',
      effects: <String, int>{'Organique': 1, 'Mycélium': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
    ),
  },
);

/// Active tuning published by the internal Dashboard. Player-owned P'TIBUG
/// progress is intentionally kept out of this configuration.
PTibugConfig pTibugConfig = defaultPTibugConfig;
