/// Central V1 settings for the House and aggregated resident housing.
class HousingConfig {
  const HousingConfig({
    required this.houseMaxLevel,
    required this.alcovesByHouseLevel,
    required this.residentsPerHousingUnit,
    required this.initialHousingOrganicCost,
    required this.initialHousingMineralCost,
    required this.housingOrganicCostIncreasePerUnit,
    required this.housingMineralCostIncreasePerUnit,
    required this.housingDurationMinutes,
    required this.wellbeingPenaltyPerUnhousedResident,
    required this.maximumHousingWellbeingPenalty,
    required this.thanksBioBatteryCost,
    required this.thanksWellbeingBonus,
    required this.thanksDurationHours,
    required this.houseViabilityDamageHappinessPercent,
    required this.houseRepairGain,
    required this.houseRepairOrganicCost,
    required this.houseRepairMineralCost,
    required this.houseProtectionSlots,
    required this.neutralHappinessWithoutResidents,
    required this.residentFurnitureSlots,
    required this.additionalGeneratorSlots,
    required this.domesticGeneratorPilesPerHour,
    required this.domesticGeneratorRunsWhenEmpty,
    required this.residentInitialPileBalance,
    required this.mealsRequiredPerDay,
    required this.partialNutritionHappinessPenalty,
    required this.noNutritionHappinessPenalty,
    required this.interiorSatisfiedHappinessBonus,
    required this.interiorUnsatisfiedHappinessPenalty,
    required this.desireSatisfiedHappinessBonus,
    required this.weatherProtectionModeratePenalty,
    required this.weatherProtectionStrongPenalty,
    required this.weatherProtectionSeverePenalty,
    required this.migrationGraceHours,
    required this.clothingRequiredForFashionDesire,
    required this.defaultProtectionDurabilityEvents,
    required this.arrivalActiveCandidateLimit,
    required this.arrivalCandidateIntervalHours,
    required this.arrivalExpiryDays,
    required this.arrivalPostponeDays,
    required this.arrivalTravelHours,
    required this.arrivalInitialHappiness,
    required this.arrivalInitialPileBalance,
    required this.visionDisappointmentPenalty,
    required this.visionDisappointmentHours,
    required this.visionFulfilledBonus,
    required this.visionBonusCap,
    required this.visionSameBranchPercent,
    required this.householdAutonomyGraceHours,
    required this.householdEmergencyReservePiles,
    required this.autonomousRepairGain,
    required this.autonomousRepairHours,
    required this.autonomousRepairCostPiles,
    required this.householdContributionMaxPercent,
  });

  final int houseMaxLevel;
  final Map<int, int> alcovesByHouseLevel;
  final int residentsPerHousingUnit;
  final int initialHousingOrganicCost;
  final int initialHousingMineralCost;
  final int housingOrganicCostIncreasePerUnit;
  final int housingMineralCostIncreasePerUnit;
  final int housingDurationMinutes;
  final int wellbeingPenaltyPerUnhousedResident;
  final int maximumHousingWellbeingPenalty;
  final int thanksBioBatteryCost;
  final int thanksWellbeingBonus;
  final int thanksDurationHours;
  final int houseViabilityDamageHappinessPercent;
  final int houseRepairGain;
  final int houseRepairOrganicCost;
  final int houseRepairMineralCost;
  final int houseProtectionSlots;
  final int neutralHappinessWithoutResidents;
  final int residentFurnitureSlots;
  final int additionalGeneratorSlots;
  final int domesticGeneratorPilesPerHour;
  final bool domesticGeneratorRunsWhenEmpty;
  final int residentInitialPileBalance;
  final int mealsRequiredPerDay;
  final int partialNutritionHappinessPenalty;
  final int noNutritionHappinessPenalty;
  final int interiorSatisfiedHappinessBonus;
  final int interiorUnsatisfiedHappinessPenalty;
  final int desireSatisfiedHappinessBonus;
  final int weatherProtectionModeratePenalty;
  final int weatherProtectionStrongPenalty;
  final int weatherProtectionSeverePenalty;
  final int migrationGraceHours;
  final int clothingRequiredForFashionDesire;
  final int defaultProtectionDurabilityEvents;
  final int arrivalActiveCandidateLimit;
  final int arrivalCandidateIntervalHours;
  final int arrivalExpiryDays;
  final int arrivalPostponeDays;
  final int arrivalTravelHours;
  final int arrivalInitialHappiness;
  final int arrivalInitialPileBalance;
  final int visionDisappointmentPenalty;
  final int visionDisappointmentHours;
  final int visionFulfilledBonus;
  final int visionBonusCap;
  final int visionSameBranchPercent;
  final int householdAutonomyGraceHours;
  final int householdEmergencyReservePiles;
  final int autonomousRepairGain;
  final int autonomousRepairHours;
  final int autonomousRepairCostPiles;
  final int householdContributionMaxPercent;

  int alcovesForHouseLevel(int level) =>
      alcovesByHouseLevel[level.clamp(1, houseMaxLevel)] ?? 2;

  Map<String, int> housingRequirementsForUnit(int unitNumber) {
    final offset = (unitNumber - 1).clamp(0, 99);
    return <String, int>{
      'Organique': initialHousingOrganicCost +
          offset * housingOrganicCostIncreasePerUnit,
      'Minéral': initialHousingMineralCost +
          offset * housingMineralCostIncreasePerUnit,
    };
  }
}

const HousingConfig defaultHousingConfig = HousingConfig(
  houseMaxLevel: 5,
  alcovesByHouseLevel: <int, int>{1: 2, 2: 3, 3: 4, 4: 6, 5: 8},
  residentsPerHousingUnit: 3,
  initialHousingOrganicCost: 10,
  initialHousingMineralCost: 20,
  housingOrganicCostIncreasePerUnit: 2,
  housingMineralCostIncreasePerUnit: 4,
  housingDurationMinutes: 60,
  wellbeingPenaltyPerUnhousedResident: 3,
  maximumHousingWellbeingPenalty: 30,
  thanksBioBatteryCost: 2,
  thanksWellbeingBonus: 3,
  thanksDurationHours: 48,
  houseViabilityDamageHappinessPercent: 30,
  houseRepairGain: 10,
  houseRepairOrganicCost: 3,
  houseRepairMineralCost: 10,
  houseProtectionSlots: 3,
  neutralHappinessWithoutResidents: 50,
  residentFurnitureSlots: 4,
  additionalGeneratorSlots: 1,
  domesticGeneratorPilesPerHour: 5,
  domesticGeneratorRunsWhenEmpty: false,
  residentInitialPileBalance: 0,
  mealsRequiredPerDay: 2,
  partialNutritionHappinessPenalty: 10,
  noNutritionHappinessPenalty: 30,
  interiorSatisfiedHappinessBonus: 10,
  interiorUnsatisfiedHappinessPenalty: 15,
  desireSatisfiedHappinessBonus: 5,
  weatherProtectionModeratePenalty: 5,
  weatherProtectionStrongPenalty: 10,
  weatherProtectionSeverePenalty: 20,
  migrationGraceHours: 24,
  clothingRequiredForFashionDesire: 2,
  defaultProtectionDurabilityEvents: 10,
  arrivalActiveCandidateLimit: 3,
  arrivalCandidateIntervalHours: 72,
  arrivalExpiryDays: 7,
  arrivalPostponeDays: 3,
  arrivalTravelHours: 12,
  arrivalInitialHappiness: 70,
  arrivalInitialPileBalance: 0,
  visionDisappointmentPenalty: 5,
  visionDisappointmentHours: 24,
  visionFulfilledBonus: 3,
  visionBonusCap: 10,
  visionSameBranchPercent: 70,
  householdAutonomyGraceHours: 24,
  householdEmergencyReservePiles: 25,
  autonomousRepairGain: 15,
  autonomousRepairHours: 72,
  autonomousRepairCostPiles: 25,
  householdContributionMaxPercent: 50,
);

HousingConfig housingConfig = defaultHousingConfig;
