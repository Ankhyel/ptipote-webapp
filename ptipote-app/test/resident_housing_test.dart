import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/housing_config.dart';
import 'package:ptipote_app/features/game/community_roles_config.dart';
import 'package:ptipote_app/features/game/lisiere_forage_config.dart';
import 'package:ptipote_app/features/game/market_config.dart';
import 'package:ptipote_app/features/game/resident_economy_config.dart';
import 'package:ptipote_app/features/game/zone0_game_state.dart';
import 'package:ptipote_app/features/game/waste_recycler_config.dart';

void main() {
  test('les réglages Habitants V1 séparent les emplacements de maison', () {
    expect(defaultHousingConfig.houseProtectionSlots, 3);
    expect(defaultHousingConfig.residentFurnitureSlots, 4);
    expect(defaultHousingConfig.additionalGeneratorSlots, 1);
    expect(defaultHousingConfig.domesticGeneratorPilesPerHour, 5);
    expect(defaultHousingConfig.domesticGeneratorRunsWhenEmpty, isFalse);
  });

  test('un habitant conserve son identité, son compte et son statut', () {
    final resident = Zone0Resident(
      id: 'resident-1',
      displayName: 'Nima',
      createdAt: DateTime(2026, 8, 2),
      internalPileBalance: 142,
      status: ResidentStatus.awaitingHousing,
      happinessModifiers: <String, int>{'house': -30},
    );

    expect(resident.displayName, 'Nima');
    expect(resident.internalPileBalance, 142);
    expect(resident.status, ResidentStatus.awaitingHousing);
    expect(resident.happinessModifiers['house'], -30);
  });

  test('une maison fonctionnelle n’a pas de niveau et garde ses slots dédiés',
      () {
    final house = ResidentHouse(
      id: 'house-1',
      displayName: 'Maison 1',
      biome: ForageBiome.plaineRiche,
      capacity: 3,
    );

    expect(house.capacity, 3);
    expect(house.weatherProtectionSlots, 3);
    expect(house.furnitureSlots, 4);
    expect(house.additionalGeneratorSlots, 1);
    expect(house.baseGeneratorInstalled, isTrue);
  });

  test('les besoins V2 demandent deux repas et restent explicables', () {
    final needs = ResidentNeedsState(
      currentDayKey: '2026-08-02',
      mealsRequired: defaultHousingConfig.mealsRequiredPerDay,
      mealsConsumed: 1,
      nutritionStatus: ResidentNutritionStatus.partiellementNourri,
      interiorProfileId: ResidentInteriorProfile.technique.name,
    );

    expect(needs.mealsRequired, 2);
    expect(needs.mealsMissing, 1);
    expect(needs.nutritionStatus, ResidentNutritionStatus.partiellementNourri);
    expect(needs.toFirebase()['mealsMissing'], 1);
  });

  test('un objet personnel usé ne reste pas utilisable', () {
    final item = ResidentOwnedItem(
      id: 'shade-1',
      itemDefinitionId: 'Tenue ombragée',
      category: 'clothing',
      quantity: 1,
      acquiredAt: DateTime(2026, 8, 2),
      currentDurability: 0,
      maxDurability: 4,
      status: ResidentOwnedItemStatus.broken,
    );

    expect(item.isUsable, isFalse);
  });

  test('le service de bonheur centralise les modificateurs', () {
    final resident = Zone0Resident(
      id: 'resident-happiness',
      displayName: 'Sol',
      createdAt: DateTime(2026, 8, 2),
      baseHappiness: 70,
      houseId: 'house-damaged',
      happinessModifiers: <String, int>{'nutrition': -10, 'interior': 10},
    );
    final house = ResidentHouse(
      id: 'house-damaged',
      displayName: 'Maison endommagée',
      biome: ForageBiome.plaineRiche,
      capacity: 3,
      currentViability: 40,
    );

    expect(
      ResidentHappinessService.calculate(resident: resident, house: house),
      40,
    );
  });

  test('les réglages des rôles communautaires restent lents et plafonnés', () {
    expect(defaultCommunityRolesConfig.communityEfficiencyPercent, 50);
    expect(defaultCommunityRolesConfig.roleIntervalMinutes, 180);
    expect(defaultCommunityRolesConfig.watchingSecurityPerInterval, 1);
    expect(defaultCommunityRolesConfig.residentPtibugMaximum, 3);
    expect(defaultCommunityRolesConfig.ptibugRequestChancePercent, 10);
  });

  test('une affectation communautaire garde son rôle et son slot', () {
    final assignment = CommunityRoleAssignment(
      id: 'role-1',
      residentId: 'resident-1',
      passion: ResidentPassion.watching,
      roleType: CommunityRoleType.securityWatch,
      buildingId: 'securityTower',
      slotId: 'resident-0',
      startedAt: DateTime(2026, 8, 2),
    );

    expect(assignment.isActive, isTrue);
    expect(assignment.toFirebase()['slotId'], 'resident-0');
    expect(assignment.toFirebase()['passionId'], 'watching');
  });

  test('l’économie conserve piles, réserve et répartition 50/25/25', () {
    expect(defaultResidentEconomyConfig.pilesPerBattery, 100);
    expect(defaultResidentEconomyConfig.batteriesPerEnergyCore, 200);
    expect(defaultResidentEconomyConfig.priceFor('Repas simple'), 15);
    expect(defaultResidentEconomyConfig.producerSharePercent, 50);
    expect(defaultResidentEconomyConfig.supplierSharePercent, 25);
    expect(defaultResidentEconomyConfig.merchantSharePercent, 25);
    expect(defaultResidentEconomyConfig.secondGeneratorBonusPercent, 50);
    expect(defaultResidentEconomyConfig.secondGeneratorInstallationCostPiles,
        1000);
  });

  test('un lot communautaire conserve sa provenance sans créer de revenu', () {
    final batch = CommunityProductionBatch(
      id: 'batch-1',
      itemDefinitionId: 'Repas simple',
      outputQuantity: 2,
      producerResidentId: 'cook-1',
      buildingId: 'cuisine',
      supplierContributions: <SupplierContribution>[
        SupplierContribution(
          id: 'supplier-1',
          sourceType: 'playerStock',
          itemDefinitionId: 'Organique',
          quantity: 3,
          contributionWeight: 3,
          createdAt: DateTime(2026, 8, 2),
        ),
      ],
      producedAt: DateTime(2026, 8, 2),
    );

    expect(batch.isAvailable, isTrue);
    expect(batch.remainingQuantity, 2);
    expect(batch.producerResidentId, 'cook-1');
    expect(batch.supplierContributions.single.sourceType, 'playerStock');
  });

  test('une transaction économique reste idempotente par clé', () {
    final transaction = ResidentEconomicTransaction(
      id: 'purchase-1',
      type: ResidentEconomicTransactionType.residentPurchase,
      buyerResidentId: 'resident-1',
      itemDefinitionId: 'Repas simple',
      grossAmountPiles: 15,
      producerSharePiles: 7,
      supplierSharePiles: 3,
      merchantSharePiles: 5,
      status: ResidentEconomicTransactionStatus.completed,
      createdAt: DateTime(2026, 8, 2),
      completedAt: DateTime(2026, 8, 2),
      idempotencyKey: 'purchase:resident-1:meal:day-1',
    );

    expect(
        transaction.grossAmountPiles,
        transaction.producerSharePiles +
            transaction.supplierSharePiles +
            transaction.merchantSharePiles);
    expect(transaction.toFirebase()['idempotencyKey'],
        'purchase:resident-1:meal:day-1');
  });

  test('la progression V5 du Marché limite les emplacements', () {
    expect(defaultMarketConfig.shopSlotsForMarketLevel(1), 1);
    expect(defaultMarketConfig.shopSlotsForMarketLevel(2), 2);
    expect(defaultMarketConfig.shopSlotsForMarketLevel(3), 4);
    expect(defaultMarketConfig.residentClaimVacancyDays, 1);
    expect(defaultMarketConfig.residentClaimWarningHours, 24);
    expect(defaultMarketConfig.constructionMinutesForLevel(1), 6);
    expect(defaultMarketConfig.constructionMinutesForLevel(2), 30);
    expect(defaultMarketConfig.constructionMinutesForLevel(3), 60);
    expect(defaultMarketConfig.constructionMinutesForLevel(4), 120);
    expect(defaultMarketConfig.requestMinimumMarketLevelFor('Repas simple'), 1);
    expect(
        defaultMarketConfig.requestMinimumMarketLevelFor('Tenue ombragée'), 2);
    expect(
        defaultMarketConfig.requestMinimumMarketLevelFor('Meuble simple'), 3);
    expect(defaultMarketConfig.distributorMarketLevelFor(1), 2);
    expect(defaultMarketConfig.distributorMarketLevelFor(2), 3);
    expect(defaultMarketConfig.distributorMarketLevelFor(3), 4);
  });

  test('un emplacement et une consigne de Marché restent persistants', () {
    final slot = MarketShopSlot(
      slotId: 'market-shop-slot-2',
      slotIndex: 1,
      marketLevelRequired: 2,
      status: MarketShopSlotStatus.pendingResidentClaim,
      vacantSince: DateTime(2026, 8, 2),
      claimCandidateResidentId: 'resident-trader',
    );
    final rule = MarketRestockRule(
      ruleId: 'rule-1',
      shopId: Zone0GameState.primaryMarketShopId,
      itemDefinitionId: 'Repas simple',
      enabled: true,
      reserveMinimum: 8,
      targetStock: 10,
      maximumTransfer: 4,
    );

    expect(slot.toFirebase()['status'], 'pendingResidentClaim');
    expect(rule.toFirebase()['reserveMinimum'], 8);
    expect(rule.toFirebase()['targetStock'], 10);
  });

  test('une candidature narrative conserve son récit et ses accompagnants', () {
    final candidate = ResidentArrivalCandidate(
      id: 'arrival-1',
      displayName: 'Nelo',
      originText: 'les lisières du sud',
      departureReasonText: 'Le poste a été détruit.',
      arrivalReasonText: 'La Tour est active.',
      shortStoryText: 'Nelo cherche un refuge où veiller.',
      promisedContributionText: 'Soutenir la Sécurité.',
      promisedContributionType: ResidentPassion.watching.name,
      primaryPassionId: ResidentPassion.watching.name,
      primaryDesireId: ResidentDesireType.tools.name,
      interiorProfileId: ResidentInteriorProfile.technique.name,
      accompanyingResidentCount: 1,
      accompanyingCandidates: <ResidentArrivalCompanion>[
        ResidentArrivalCompanion(
          id: 'arrival-1-companion',
          displayName: 'Ayo',
          primaryPassionId: ResidentPassion.cooking.name,
          primaryDesireId: ResidentDesireType.comfort.name,
          interiorProfileId: ResidentInteriorProfile.simple.name,
        ),
      ],
      requiredHousingCapacity: 2,
      createdAt: DateTime(2026, 8, 2),
      status: ResidentArrivalStatus.acceptedPendingConditions,
    );

    expect(candidate.toFirebase()['shortStoryText'], contains('Nelo'));
    expect(candidate.requiredHousingCapacity, 2);
    expect(candidate.accompanyingCandidates.single.displayName, 'Ayo');
    expect(candidate.status, ResidentArrivalStatus.acceptedPendingConditions);
  });

  test('une vision et une réparation domestique restent persistantes', () {
    final vision = ResidentVision(
      id: 'vision-1',
      residentId: 'resident-1',
      projectId: 'canalisations',
      projectTier: 1,
      branchId: 'heavyRain',
      selectedAt: DateTime(2026, 8, 2),
    );
    final repair = HouseholdRepairJob(
      id: 'repair-1',
      houseId: 'house-1',
      startedAt: DateTime(2026, 8, 2),
      endsAt: DateTime(2026, 8, 5),
      viabilityGain: defaultHousingConfig.autonomousRepairGain,
      isPlayerRepair: false,
      reservedKitItemId: 'Kit de réparation domestique',
    );

    expect(vision.toFirebase()['projectId'], 'canalisations');
    expect(repair.toFirebase()['viabilityGain'], 15);
    expect(repair.reservedKitItemId, 'Kit de réparation domestique');
  });

  test('les réglages V6 gardent les limites lentes et récupérables', () {
    expect(defaultHousingConfig.arrivalActiveCandidateLimit, 3);
    expect(defaultHousingConfig.arrivalTravelHours, 12);
    expect(defaultHousingConfig.visionSameBranchPercent, 70);
    expect(defaultHousingConfig.visionBonusCap, 10);
    expect(defaultHousingConfig.autonomousRepairGain, 15);
    expect(defaultHousingConfig.autonomousRepairHours, 72);
  });

  test('le Biofermenteur et la Lithoculture restent configurables', () {
    final bio = defaultLisiereForageConfig.territoryBuildings.biofermenter;
    expect(defaultLisiereForageConfig.territoryBuildings.slotsPerZone, 1);
    expect(bio.passiveOrganicPerDayByLevel,
        <int, double>{1: 12, 2: 18, 3: 24, 4: 30});
    expect(bio.normalMineralPerOrganic, 3);
    expect(bio.mineralBasinMineralPerOrganic, 2);
    expect(bio.futureScarabeHookEnabled, isFalse);
    expect(bio.constructionMinutesByLevel,
        <int, int>{1: 60, 2: 120, 3: 180, 4: 240});
    expect(bio.edibleForestConstructionMinutes, 60);
  });

  test('le Recycleur conserve ses deux répartitions et son module', () {
    expect(
        defaultWasteRecyclerConfig.standardOrganicRatio +
            defaultWasteRecyclerConfig.standardMineralRatio +
            defaultWasteRecyclerConfig.standardOtherRatio,
        100);
    expect(
        defaultWasteRecyclerConfig.biologicalOrganicRatio +
            defaultWasteRecyclerConfig.biologicalMineralRatio +
            defaultWasteRecyclerConfig.biologicalOtherRatio,
        100);
    expect(defaultWasteRecyclerConfig.otherOutputResource, 'Mycélium');
    expect(
        defaultWasteRecyclerConfig.biologicalOrientationModuleCost['Mycélium'],
        5);
  });
}
