/// Central V1 settings for the House and aggregated resident housing.
class HousingConfig {
  const HousingConfig({
    required this.houseMaxLevel,
    required this.alcovesByHouseLevel,
    required this.residentsPerHousingUnit,
    required this.initialHousingOrganicCost,
    required this.initialHousingMineralCost,
    required this.housingDurationMinutes,
    required this.wellbeingPenaltyPerUnhousedResident,
    required this.maximumHousingWellbeingPenalty,
    required this.thanksBioBatteryCost,
    required this.thanksWellbeingBonus,
    required this.thanksDurationHours,
  });

  final int houseMaxLevel;
  final Map<int, int> alcovesByHouseLevel;
  final int residentsPerHousingUnit;
  final int initialHousingOrganicCost;
  final int initialHousingMineralCost;
  final int housingDurationMinutes;
  final int wellbeingPenaltyPerUnhousedResident;
  final int maximumHousingWellbeingPenalty;
  final int thanksBioBatteryCost;
  final int thanksWellbeingBonus;
  final int thanksDurationHours;

  int alcovesForHouseLevel(int level) =>
      alcovesByHouseLevel[level.clamp(1, houseMaxLevel)] ?? 2;

  Map<String, int> housingRequirementsForUnit(int unitNumber) {
    final offset = (unitNumber - 1).clamp(0, 99);
    return <String, int>{
      'Organique': initialHousingOrganicCost + offset * 2,
      'Minéral': initialHousingMineralCost + offset * 4,
    };
  }
}

const HousingConfig defaultHousingConfig = HousingConfig(
  houseMaxLevel: 5,
  alcovesByHouseLevel: <int, int>{1: 2, 2: 3, 3: 4, 4: 6, 5: 8},
  residentsPerHousingUnit: 3,
  initialHousingOrganicCost: 10,
  initialHousingMineralCost: 20,
  housingDurationMinutes: 60,
  wellbeingPenaltyPerUnhousedResident: 3,
  maximumHousingWellbeingPenalty: 30,
  thanksBioBatteryCost: 2,
  thanksWellbeingBonus: 3,
  thanksDurationHours: 48,
);

HousingConfig housingConfig = defaultHousingConfig;
