import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/ptibug_config.dart';
import 'package:ptipote_app/features/game/kernel_progress_config.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';
import 'package:ptipote_app/features/game/lisiere_forage_config.dart';
import 'package:ptipote_app/features/game/craft_config.dart';
import 'package:ptipote_app/features/game/ptibug_valuation_service.dart';

void main() {
  test('un trait separe les bonus de production des effets systemiques', () {
    const trait = PTibugTraitDefinition(
      id: 'test',
      displayName: 'Test',
      description: '',
      effects: const <String, int>{
        'Organique': 2,
        'Chance Cellule': 5,
      },
      gradeMultipliers: const <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
      },
      colorHex: '#000000',
      isActive: true,
      maxLevel: 1,
    );

    expect(trait.productionForLevel(1), <String, int>{'Organique': 2});
    expect(trait.effectForLevel('Chance Cellule', 1), 5);
  });

  test('Arac utilise une table de production configuree par biome', () {
    final biome = defaultPTibugConfig.biomes[PTibugBiome.mangroves]!;

    expect(biome.aracProductionWeights['Déchets'], greaterThan(0));
    expect(biome.aracProductionWeights['Organique'], greaterThan(0));
  });

  test('les traits V1 complets ont des couts sur leurs trois niveaux', () {
    for (final traitId in <String>[
      'pollinisateur',
      'mineur',
      'decomposeur',
      'recuperateur',
      'capteurIntelligent',
      'filtreur',
      'econome',
      'stabilisateur',
    ]) {
      final trait = defaultPTibugConfig.traitDefinitionFor(traitId)!;
      expect(trait.dataCostByLevel.keys, containsAll(<int>[1, 2, 3]));
      expect(trait.energyCostByLevel[1], greaterThan(0));
    }
  });

  test('le Sourcier valorise les Cellules et les lots Atelier', () {
    expect(defaultPTibugConfig.sourcierCellPricePerDataValue, 3);
    expect(defaultTowerOperationsConfig.merchantWorkshopOfferCount, 1);
    expect(defaultTowerOperationsConfig.merchantWorkshopMinimumQuantity, 5);
    expect(defaultTowerOperationsConfig.merchantWorkshopMaximumQuantity, 10);
  });

  test('les crafts Kernel ont des coûts de données pertinents', () {
    final plans = <String, KernelTechnologyPlanConfig>{
      for (final plan in defaultKernelProgressConfig.plans) plan.id: plan,
    };

    expect(plans['filter']!.dataRequirements, <String, int>{
      'toxine': 6,
      'minerale': 3,
    });
    expect(plans['solar-light']!.dataRequirements['energie'], 8);
    expect(plans['energy-core']!.dataRequirements, <String, int>{
      'energie': 20,
      'organique': 20,
      'minerale': 10,
      'mycelienne': 15,
      'biomimetisme': 15,
    });
  });

  test('le cœur d’énergie est un craft Atelier non empilable', () {
    final recipe = defaultCraftConfig.recipes
        .firstWhere((recipe) => recipe.id == 'energyCore');

    expect(recipe.craftSection, CraftSection.atelier);
    expect(recipe.bioBatteryCost, 300);
    expect(recipe.ingredients, <String, int>{'Organique': 10, 'Minéral': 10});
    expect(recipe.stackLimit, 1);
  });

  test('la gestion territoriale applique une capacité par niveau configurable',
      () {
    final territory = defaultPTibugConfig.territory;

    expect(territory.nurseryCapacityForLevel(1), 1);
    expect(territory.nurseryCapacityForLevel(6), 6);
    expect(territory.refugeCapacityForLevel(4), 4);
    expect(territory.dataCellStorageCapacity, 3);
  });

  test('la progression V1 applique rendement et énergie par niveau', () {
    final progression = defaultPTibugConfig.progression;

    expect(progression.maximumLevel, 6);
    expect(progression.yieldMultiplierForLevel(1), 1);
    expect(progression.yieldMultiplierForLevel(3), 1.2);
    expect(progression.yieldMultiplierForLevel(6), 1.5);
    expect(progression.baseEnergyPerDayForLevel(1), 3);
    expect(progression.baseEnergyPerDayForLevel(2), 2);
    expect(progression.baseEnergyPerDayForLevel(3), 1);
    expect(progression.baseEnergyPerDayForLevel(6), 1);
  });

  test('les améliorations globales de Modules ont les coûts V1', () {
    final modules = defaultPTibugConfig.moduleCapacity;

    expect(modules.capacityForLevel(0), 1);
    expect(modules.capacityForLevel(1), 2);
    expect(modules.capacityForLevel(2), 3);
    expect(modules.materialCostsByLevel[1], <String, int>{
      'Organique': 60,
      'Minéral': 30,
    });
    expect(modules.bioBatteryCostsByLevel[2], 20);
    expect(modules.dataCostsByLevel[2]![PTibugDataFamily.biomimetisme], 20);
    expect(
        modules.dataCostsByLevel[2]![PTibugDataFamily.comportementInsectoide],
        20);
  });

  test('Capteur intelligent et météo V1 ont leurs réglages pilotables', () {
    final config = defaultPTibugConfig;
    final sensor = config.traitDefinitionFor('capteurIntelligent')!;

    expect(config.traitDefinitionFor('eclaireur'), isNull);
    expect(sensor.displayName, 'Capteur intelligent');
    expect(config.weather.sensorChanceByLevel, <int, int>{1: 5, 2: 10, 3: 15});
    expect(config.weather.sensorMaterialPenaltyPercent, 50);
    expect(config.weather.productionMalusPercent, 30);
    expect(PTibugModuleType.values, contains(PTibugModuleType.reflecteur));
    expect(PTibugModuleType.values, contains(PTibugModuleType.etancheite));
    expect(config.moduleCraftCostFor(PTibugModuleType.reflecteur)['Organique'],
        10);
    expect(
        config.moduleCraftCostFor(PTibugModuleType.etancheite)['Minéral'], 10);
  });

  test('les missions distinguent Récolte et Recherche dans la configuration',
      () {
    final harvest =
        defaultLisiereForageConfig.missionTypes[ForageMissionType.harvest]!;
    final research =
        defaultLisiereForageConfig.missionTypes[ForageMissionType.research]!;

    expect(harvest.vigorMultiplier, 1);
    expect(
        harvest.cellChanceMultiplier, lessThan(research.cellChanceMultiplier));
    expect(research.vigorMultiplier, lessThan(harvest.vigorMultiplier));
    expect(research.wastePerHour, greaterThan(0));
    expect(defaultLisiereForageConfig.intensities[ForageIntensity.normal],
        isNotNull);
    expect(defaultLisiereForageConfig.intensities[ForageIntensity.intensif],
        isNotNull);
  });

  test('les Refuges ont leur chantier et leur capacité V1 configurables', () {
    final territory = defaultPTibugConfig.territory;

    expect(territory.refugeMaximumLevel, 4);
    expect(territory.refugeCapacityForLevel(1), 1);
    expect(territory.refugeCapacityForLevel(4), 4);
    expect(territory.refugeRequirementsForLevel(1), <String, int>{
      'Organique': 20,
      'Minéral': 10,
    });
    expect(territory.refugeBioBatteriesForLevel(1), 1);
    expect(territory.refugeRequirementsForLevel(2)['Organique'], 30);
    expect(territory.refugeUpgradeBioBatteriesByLevel[4], 8);
  });

  test('la Cultivation possède une autonomie et des ratios par espèce', () {
    final cultivation = defaultPTibugConfig.cultivation;

    expect(cultivation.armatureMinutes, 180);
    expect(cultivation.activeHours, 24);
    expect(cultivation.activeSecondsRequired, 24 * 60 * 60);
    expect(cultivation.tankSlotsPerNurseryLevel, 1);
    expect(cultivation.targetAutonomyHours, 8);
    expect(cultivation.organicPerActiveHour[PTibugSpecies.hyme],
        greaterThan(cultivation.mineralPerActiveHour[PTibugSpecies.hyme]!));
    expect(cultivation.mineralPerActiveHour[PTibugSpecies.scarabe],
        greaterThan(cultivation.organicPerActiveHour[PTibugSpecies.scarabe]!));
    expect(cultivation.organicPerActiveHour[PTibugSpecies.arac],
        cultivation.mineralPerActiveHour[PTibugSpecies.arac]);
    expect(cultivation.tapBonusMinutes, 60);
    expect(cultivation.tapMaximumPerDay, 3);
    expect(cultivation.tapMinimumDelayHours, 4);
  });

  test('Infusion et Évolution utilisent les réglages de cuve V2', () {
    final cultivation = defaultPTibugConfig.cultivation;

    expect(cultivation.traitInfusionHours, 6);
    expect(cultivation.evolutionHours, 12);
    expect(cultivation.traitMaterialCostCoefficient, .30);
    expect(cultivation.evolutionMaterialCostCoefficient, .50);
    expect(
      cultivation.activeSecondsFor(
        PTibugCultivationOperationType.traitInfusion,
      ),
      const Duration(hours: 6).inSeconds,
    );
    expect(
      cultivation.tapBonusFor(PTibugCultivationOperationType.evolution),
      30,
    );
    expect(cultivation.evolutionDataCost[PTibugDataFamily.organique], 3);
  });

  test('l’Extracteur de matrice respecte les paliers et coûts configurés', () {
    final extractor = defaultPTibugConfig.aspectMatrixExtractor;

    expect(extractor.moduleCountFor(1), 1);
    expect(extractor.matricesFor(1), <int>[1]);
    expect(extractor.durationFor(1), 10);
    expect(extractor.matricesFor(2), <int>[2]);
    expect(extractor.moduleCountFor(3), 2);
    expect(extractor.matricesFor(3), <int>[2, 1]);
    expect(extractor.matricesFor(4), <int>[2, 2]);
    expect(extractor.durationFor(4), 4);
    expect(extractor.mineralCostPerModule, 1);
    expect(extractor.organicCostPerModule, 10);
    expect(extractor.nurseryEnergyCostPerModule, 3);
  });

  test('la valeur P’TIBUG additionne espèces, niveaux, Traits et Modules', () {
    final service = PTibugValuationService(defaultPTibugConfig.valuation);
    final value = service.evaluate(const PTibugValuationInput(
      species: PTibugSpecies.hyme,
      level: 3,
      traitRanks: <int>[3, 1],
      modules: <PTibugModuleType>[
        PTibugModuleType.ailes,
        PTibugModuleType.ailes,
      ],
    ));

    expect(value.baseValue, 22);
    expect(value.levelValue, 12);
    expect(value.traitValue, 33);
    expect(value.moduleValue, 10);
    expect(value.total, 77);
    expect(service.paymentFor(value, sourcierContract: false), 77);
    expect(service.paymentFor(value, sourcierContract: true), 92);
  });
}
