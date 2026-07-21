import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/ptibug_config.dart';

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
}
