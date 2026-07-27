import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/lisiere_forage_config.dart';

void main() {
  test('chaque biome actif a son rythme de régénération des déchets', () {
    final biomes = defaultLisiereForageConfig.biomes;

    expect(
      biomes[ForageBiome.plaineRiche]!.wasteHoursPerLevelRegeneration,
      1,
    );
    expect(
      biomes[ForageBiome.bassinMineral]!.wasteHoursPerLevelRegeneration,
      2,
    );
    expect(
      biomes[ForageBiome.sousBois]!.wasteHoursPerLevelRegeneration,
      2,
    );
    expect(
      biomes[ForageBiome.colline]!.wasteHoursPerLevelRegeneration,
      3,
    );
  });
}
