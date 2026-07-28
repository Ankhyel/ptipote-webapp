import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/ptibug_config.dart';
import 'package:ptipote_app/features/game/kernel_progress_config.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';
import 'package:ptipote_app/features/game/lisiere_forage_config.dart';

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
}
