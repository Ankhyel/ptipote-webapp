class CommunityRolesConfig {
  const CommunityRolesConfig({
    required this.enabled,
    required this.passionWeights,
    required this.passionHappinessBonus,
    required this.communityEfficiencyPercent,
    required this.roleIntervalMinutes,
    required this.cookingCoveragePerCycle,
    required this.cookingMaximumMealsPerDay,
    required this.craftingMaximumOutputPerDay,
    required this.observationOrganicPerCycle,
    required this.observationMineralPerCycle,
    required this.observationRequiresSecurity,
    required this.watchingSecurityPerInterval,
    required this.ptibugRequestChancePercent,
    required this.residentPtibugMaximum,
    required this.allowNonPassionWork,
  });

  final bool enabled;
  final Map<String, int> passionWeights;
  final int passionHappinessBonus;
  final int communityEfficiencyPercent;
  final int roleIntervalMinutes;
  final int cookingCoveragePerCycle;
  final int cookingMaximumMealsPerDay;
  final int craftingMaximumOutputPerDay;
  final int observationOrganicPerCycle;
  final int observationMineralPerCycle;
  final int observationRequiresSecurity;
  final int watchingSecurityPerInterval;
  final int ptibugRequestChancePercent;
  final int residentPtibugMaximum;
  final bool allowNonPassionWork;
}

const CommunityRolesConfig defaultCommunityRolesConfig = CommunityRolesConfig(
  enabled: true,
  passionWeights: <String, int>{
    'cooking': 20,
    'crafting': 20,
    'trading': 20,
    'livingObservation': 20,
    'watching': 20,
  },
  passionHappinessBonus: 5,
  communityEfficiencyPercent: 50,
  roleIntervalMinutes: 180,
  cookingCoveragePerCycle: 2,
  cookingMaximumMealsPerDay: 6,
  craftingMaximumOutputPerDay: 2,
  observationOrganicPerCycle: 1,
  observationMineralPerCycle: 0,
  observationRequiresSecurity: 15,
  watchingSecurityPerInterval: 1,
  ptibugRequestChancePercent: 10,
  residentPtibugMaximum: 3,
  allowNonPassionWork: false,
);

CommunityRolesConfig communityRolesConfig = defaultCommunityRolesConfig;
