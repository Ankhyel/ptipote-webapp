/// Tunable rules for the internal, pile-based resident economy.
///
/// Balances are always stored as whole piles. Energy Cores remain physical
/// player-inventory items and are deliberately absent from this configuration.
class ResidentEconomyConfig {
  const ResidentEconomyConfig({
    required this.enabled,
    required this.pilesPerBattery,
    required this.batteriesPerEnergyCore,
    required this.householdDistributionMinutes,
    required this.secondGeneratorBonusPercent,
    required this.secondGeneratorInstallationCostPiles,
    required this.residentInitialPileBalance,
    required this.householdInitialPileBalance,
    required this.personalEmergencyReservePiles,
    required this.essentialPurchaseMayUseReserve,
    required this.desirePurchaseMayUseReserve,
    required this.personalAccountCapPiles,
    required this.householdAccountCapPiles,
    required this.residentInventoryItemCap,
    required this.basePricesPiles,
    required this.producerSharePercent,
    required this.supplierSharePercent,
    required this.merchantSharePercent,
    required this.absentMerchantShareRecipient,
    required this.financialStrainWindowDays,
    required this.financialStrainCriticalThreshold,
    required this.maxSettlementHistory,
  });

  final bool enabled;
  final int pilesPerBattery;
  final int batteriesPerEnergyCore;
  final int householdDistributionMinutes;
  final int secondGeneratorBonusPercent;
  final int secondGeneratorInstallationCostPiles;
  final int residentInitialPileBalance;
  final int householdInitialPileBalance;
  final int personalEmergencyReservePiles;
  final bool essentialPurchaseMayUseReserve;
  final bool desirePurchaseMayUseReserve;
  final int personalAccountCapPiles;
  final int householdAccountCapPiles;
  final int residentInventoryItemCap;
  final Map<String, int> basePricesPiles;
  final int producerSharePercent;
  final int supplierSharePercent;
  final int merchantSharePercent;
  final String absentMerchantShareRecipient;
  final int financialStrainWindowDays;
  final int financialStrainCriticalThreshold;
  final int maxSettlementHistory;

  int priceFor(String item) =>
      (basePricesPiles[item] ?? basePricesPiles['default'] ?? 1)
          .clamp(1, 999999);
}

const ResidentEconomyConfig defaultResidentEconomyConfig =
    ResidentEconomyConfig(
  enabled: true,
  pilesPerBattery: 100,
  batteriesPerEnergyCore: 200,
  householdDistributionMinutes: 60,
  secondGeneratorBonusPercent: 50,
  secondGeneratorInstallationCostPiles: 1000,
  residentInitialPileBalance: 0,
  householdInitialPileBalance: 0,
  personalEmergencyReservePiles: 10,
  essentialPurchaseMayUseReserve: true,
  desirePurchaseMayUseReserve: false,
  personalAccountCapPiles: 999999,
  householdAccountCapPiles: 999999,
  residentInventoryItemCap: 20,
  basePricesPiles: <String, int>{
    'default': 10,
    'Repas simple': 15,
    'Boisson tonique': 8,
    'Tenue ombragée': 200,
    'Cartouche de filtration': 130,
    'Filtre': 70,
    'Meuble simple': 500,
    'Ventilation Termite': 500,
    'Chloro-canaux': 500,
    'Installation filtrante': 500,
  },
  producerSharePercent: 50,
  supplierSharePercent: 25,
  merchantSharePercent: 25,
  absentMerchantShareRecipient: 'producer',
  financialStrainWindowDays: 3,
  financialStrainCriticalThreshold: 3,
  maxSettlementHistory: 60,
);

ResidentEconomyConfig residentEconomyConfig = defaultResidentEconomyConfig;
