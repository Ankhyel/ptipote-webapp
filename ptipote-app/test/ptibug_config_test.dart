import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/ptibug_config.dart';
import 'package:ptipote_app/features/game/kernel_progress_config.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';

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
      'eclaireur',
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
}
