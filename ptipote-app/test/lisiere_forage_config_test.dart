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

  test('les synergies territoriales partagent la même table configurable', () {
    final bio = defaultLisiereForageConfig.territoryBuildings.biofermenter;
    expect(bio.mycelialNetworkEnabled, isTrue);
    expect(bio.baseMyceliumPerDay, 8);
    expect(bio.mycelialTraitId, 'decomposeur');
    expect(bio.biomeSynergy.ptibugBonusPerDay, 3);
    expect(bio.biomeSynergy.maxEligiblePtibugs, 3);
    expect(bio.biomeSynergy.mainModuleMultipliers, <int, double>{
      1: 1,
      2: 2,
      3: 3,
    });
    expect(bio.biomeSynergy.securityFloors, <int, int>{1: 20, 2: 35, 3: 50});
    expect(bio.biomeSynergy.researchFloors, <int, int>{1: 20, 2: 35, 3: 50});
    expect(bio.biomeSynergy.weatherDamageReductions, <int, double>{
      1: .15,
      2: .30,
      3: .50,
    });
    expect(
      bio.biomeSynergy.standardModuleBuild.resourceCostsByLevel[1],
      <String, int>{'Minéral': 10, 'Organique': 30},
    );
    expect(
      bio.biomeSynergy.weatherModuleBuild.dataCostsByLevel[3],
      <String, int>{'mycelienne': 5, 'toxine': 5},
    );
  });

  test('le Bassin minéral garde ses réserves locales configurables', () {
    final bio = defaultLisiereForageConfig.territoryBuildings.biofermenter;
    expect(bio.mineralBasinProductionPerDay, <int, double>{
      1: 12,
      2: 15,
      3: 18,
    });
    expect(bio.mineralBasinWaterCapacity, <int, int>{1: 24, 2: 36, 3: 48});
    expect(bio.mineralBasinWaterConsumptionPerDay,
        <int, double>{1: 24, 2: 18, 3: 12});
    expect(bio.mineralBasinOrganicConsumptionPerDay,
        <int, double>{1: 18, 2: 12, 3: 6});
    expect(bio.mineralBasinOrganicCapacity, <int, int>{1: 12, 2: 18, 3: 24});
    expect(bio.rainRefillsMineralBasinWater, isTrue);
  });
}
