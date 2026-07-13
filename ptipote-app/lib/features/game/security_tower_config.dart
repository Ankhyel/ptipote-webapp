class SecurityTowerConfig {
  const SecurityTowerConfig({
    required this.requiredCampHeartLevel,
    required this.constructionCostOrganic,
    required this.constructionCostMineral,
    required this.maxSecurity,
    required this.initialSecurity,
    required this.securityGainPerTick,
    required this.tickMinutes,
    required this.vitalityCostPerTick,
    required this.securityDecayPerTick,
    required this.level1Slots,
    required this.level2Slots,
    required this.level3Slots,
  });

  final int requiredCampHeartLevel;
  final int constructionCostOrganic;
  final int constructionCostMineral;
  final int maxSecurity;
  final int initialSecurity;
  final int securityGainPerTick;
  final int tickMinutes;
  final int vitalityCostPerTick;
  final int securityDecayPerTick;
  final int level1Slots;
  final int level2Slots;
  final int level3Slots;

  Map<String, int> get constructionCost {
    return <String, int>{
      'Organique': constructionCostOrganic,
      'Minéral': constructionCostMineral,
    };
  }

  int slotsForLevel(int level) {
    if (level >= 3) return level3Slots;
    if (level >= 2) return level2Slots;
    if (level >= 1) return level1Slots;
    return 0;
  }
}

const securityTowerConfig = SecurityTowerConfig(
  requiredCampHeartLevel: 1,
  constructionCostOrganic: 6,
  constructionCostMineral: 8,
  maxSecurity: 100,
  initialSecurity: 0,
  securityGainPerTick: 5,
  tickMinutes: 10,
  vitalityCostPerTick: 5,
  securityDecayPerTick: 1,
  level1Slots: 1,
  level2Slots: 2,
  level3Slots: 3,
);
