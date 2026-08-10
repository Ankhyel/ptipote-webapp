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

  test('la Biomasse V1 couvre rendement, récupération et Revigorer', () {
    final biomass = defaultLisiereForageConfig.biomass;

    expect(biomass.maximumPercent, 100);
    expect(biomass.missionConsumptionByIntensity[ForageIntensity.doux], 2);
    expect(biomass.missionConsumptionByIntensity[ForageIntensity.normal], 4);
    expect(
      biomass.missionConsumptionByIntensity[ForageIntensity.intensif],
      8,
    );
    expect(
      biomass.resourceYieldTiers
          .firstWhere((tier) => tier.contains(25))
          .multiplier,
      .75,
    );
    expect(
      biomass.recoveryTiers.firstWhere((tier) => tier.contains(5)).multiplier,
      16,
    );
    expect(
      biomass.visualStates.firstWhere((state) => state.contains(85)).icon,
      '🌿',
    );
  });

  test('le Mycélium suit la richesse des biomes sans changer leurs IDs', () {
    final config = defaultLisiereForageConfig;
    expect(config.biomes[ForageBiome.sousBois]!.label, 'Forêt humide');
    expect(config.biomes[ForageBiome.colline]!.label, 'Forêt sèche');
    expect(config.biomes[ForageBiome.plaineRiche]!.label, 'Savane tropicale');
    expect(
      config.biomes[ForageBiome.sousBois]!.myceliumRichness,
      MyceliumRichness.rich,
    );
    expect(
      config.biomes[ForageBiome.plaineRiche]!.myceliumRichness,
      MyceliumRichness.medium,
    );
    expect(
      config.biomes[ForageBiome.bassinMineral]!.myceliumRichness,
      MyceliumRichness.none,
    );
    expect(
        config.myceliumExploration.yieldByRichness[MyceliumRichness.rich], 3);
    expect(config.myceliumExploration.mycelialTypeGatherBonus, .5);
  });

  test('le Réseau mycélien reste une spécialisation configurable', () {
    final bio = defaultLisiereForageConfig.territoryBuildings.biofermenter;
    expect(bio.mycelialNetworkEnabled, isTrue);
    expect(bio.baseMyceliumPerDay, 8);
    expect(bio.myceliumBiomeMultipliers[MyceliumRichness.none], 1);
    expect(bio.myceliumBiomeMultipliers[MyceliumRichness.medium], 1.25);
    expect(bio.myceliumBiomeMultipliers[MyceliumRichness.rich], 1.5);
    expect(bio.mycelialTraitId, 'decomposeur');
    expect(bio.mycelialTraitBonusPerPTibug, .1);
    expect(bio.maxMycelialPTibugsCounted, 3);
  });
}
