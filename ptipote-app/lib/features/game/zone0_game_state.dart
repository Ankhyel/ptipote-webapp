import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'camp_generator_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'waste_recycler_config.dart';
import 'workshop_config.dart';

class Zone0GameState extends ChangeNotifier {
  Zone0GameState._();

  static final Zone0GameState instance = Zone0GameState._();
  final math.Random _random = math.Random();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, int> vitalityOverrides = <String, int>{};
  final Map<String, int> hungerOverrides = <String, int>{};
  final Map<String, int> restOverrides = <String, int>{};
  final Map<String, int> xpOverrides = <String, int>{};
  final Map<String, int> levelOverrides = <String, int>{};
  final Map<String, DateTime> lastCuddleAt = <String, DateTime>{};
  final Set<String> manualRestingIds = <String>{};
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<TowerMission> towerMissions = <TowerMission>[];
  final List<WorkshopCraftOrder> workshopOrders = <WorkshopCraftOrder>[];
  final List<PtipoteMissionReport> reports = <PtipoteMissionReport>[];
  final List<Zone0InventoryStack> marketStock = <Zone0InventoryStack>[];
  final List<MarketCustomerRequest> marketRequests = <MarketCustomerRequest>[];
  final Map<ForageBiome, BiomeSecurityState> biomeSecurity =
      <ForageBiome, BiomeSecurityState>{
    for (final biome in ForageBiome.values)
      biome: BiomeSecurityState.initial(biome),
  };
  final List<BiomeExplorationMission> explorationMissions =
      <BiomeExplorationMission>[];
  final List<WeatherAlert> weatherAlerts = <WeatherAlert>[];
  final List<MerchantOffer> merchantOffers = <MerchantOffer>[];
  final Set<String> completedKernelMissionIds = <String>{};
  // Kept separately from completion: a completed mission can wait for room
  // in the refuge before all of its population reward is credited.
  final Map<String, int> kernelPopulationRewardsGranted = <String, int>{};
  final Map<KernelAxis, int> kernelAxisLevels = <KernelAxis, int>{
    for (final axis in KernelAxis.values) axis: 1,
  };
  final Map<KernelAxis, int> kernelAxisXp = <KernelAxis, int>{
    for (final axis in KernelAxis.values) axis: 0,
  };
  final Map<KernelProgressEventType, int> kernelEventCounts =
      <KernelProgressEventType, int>{};
  final Set<String> discoveredKernelPlanIds = <String>{};
  final Set<String> readyKernelPlanIds = <String>{};
  final Set<String> activeKernelPlanIds = <String>{};
  final List<KernelProgressHistoryEntry> kernelProgressHistory =
      <KernelProgressHistoryEntry>[];
  bool _needsKernelPopulationRewardMigration = false;
  int _lastKnownCampHeartLevel = 1;

  int refugeSafety = lisiereForageConfig.refugeSafetyFallback;
  int fablabLevel = 0;
  int securityTowerLevel = 0;
  int marketLevel = 0;
  int currentPopulation = kernelConfig.startingPopulation;
  int kernelTrustLevel = 1;
  int kernelTrustXp = 0;
  int bioBatteries = kernelConfig.startingBioBatteries;
  int energyUnits = 0;
  int recyclerLevel = 0;
  int recyclerWasteTank = 0;
  int recyclerOutputOrganic = 0;
  int recyclerOutputMineral = 0;
  int pendingWaste = 0;
  DateTime? recyclerCycleStartedAt;
  DateTime? lastWasteGenerationAt;
  int campWellbeing = kernelConfig.startingWellbeing;
  int mealsPrepared = 0;
  int plaineMissionsCompleted = 0;
  int generatorOrganic = 0;
  int generatorMineral = 0;
  int generatorTotalProduced = 0;
  DateTime? generatorCycleStartedAt;
  DateTime? marketNextSaleAt;
  DateTime? marketLastWorkTickAt;
  DateTime? lastManualTowerRechargeAt;
  DateTime? merchantAvailableUntil;
  String? marketAssignedPtipoteId;
  String? marketAssignedPtipoteName;
  int marketValueRemainder = 0;
  int marketBioBatteriesEarned = 0;
  final Set<String> towerAssignedIds = <String>{};
  DateTime? lastFirebaseSyncAt;
  DateTime? lastSimulationAt;
  String? lastFirebaseError;
  String firebaseSyncLabel = 'Non synchronisé';
  bool isFirebaseSyncing = false;
  bool _loadedFromFirebase = false;

  bool get isFablabBuilt => fablabLevel >= fablabConfig.cuisineUnlockLevel;
  bool get isSecurityTowerBuilt => securityTowerLevel >= 1;
  bool get isMarketBuilt => marketLevel >= 1;
  bool isRecyclerUnlocked(int campHeartLevel) =>
      isFablabBuilt &&
      campHeartLevel >= wasteRecyclerConfig.recyclerUnlockCampHeartLevel;
  int get recyclerWasteRequired =>
      wasteRecyclerConfig.wasteRequired(recyclerLevel);
  int get recyclerTankCapacity =>
      wasteRecyclerConfig.tankCapacity(recyclerLevel);
  int get recyclerOutputAmount => recyclerOutputOrganic + recyclerOutputMineral;
  int get securityTowerSlots =>
      securityTowerConfig.slotsForLevel(securityTowerLevel);
  bool get hasActiveTowerMission => towerMissions.any(
        (mission) => mission.status == TowerMissionStatus.active,
      );

  int get securityWellbeingModifier =>
      towerOperationsConfig.wellbeingBandFor(refugeSafety).wellbeingModifier;

  int get displayedCampWellbeing =>
      (campWellbeing + securityWellbeingModifier).clamp(0, 100);

  bool get isMerchantAvailable =>
      merchantAvailableUntil != null &&
      DateTime.now().isBefore(merchantAvailableUntil!);

  bool isBiomeUnlocked(ForageBiome biome) =>
      biomeSecurity[biome]?.status == BiomeDiscoveryStatus.unlocked;

  bool isBiomeExploring(ForageBiome biome) => explorationMissions
      .any((mission) => mission.biome == biome && mission.isActive);

  bool isAssignedToTower(String figurineId) {
    return towerAssignedIds.contains(figurineId) ||
        towerMissions.any(
          (mission) =>
              mission.figurineId == figurineId &&
              mission.status == TowerMissionStatus.active,
        );
  }

  List<WorkshopCraftOrder> get activeWorkshopOrders => workshopOrders
      .where((order) => order.status == WorkshopOrderStatus.active)
      .toList();

  int get activeManualWorkshopOrders => activeWorkshopOrders
      .where((order) =>
          order.area == WorkshopOrderArea.workshop &&
          order.assignedPtipoteId == null)
      .length;

  int get activePtipoteWorkshopOrders => activeWorkshopOrders
      .where((order) =>
          order.area == WorkshopOrderArea.workshop &&
          order.assignedPtipoteId != null)
      .length;

  List<WorkshopCraftOrder> get activeKitchenOrders => activeWorkshopOrders
      .where((order) => order.area == WorkshopOrderArea.kitchen)
      .toList();

  int get activeManualKitchenOrders => activeKitchenOrders
      .where((order) => order.assignedPtipoteId == null)
      .length;

  int get activePtipoteKitchenOrders => activeKitchenOrders
      .where((order) => order.assignedPtipoteId != null)
      .length;

  int get workshopSlots => workshopConfig.slotsForLevel(fablabLevel);

  bool isAssignedToWorkshop(String figurineId) => activeWorkshopOrders.any(
        (order) => order.assignedPtipoteId == figurineId,
      );

  Map<String, int> _orderIngredients(WorkshopCraftOrder order) =>
      order.area == WorkshopOrderArea.kitchen
          ? craftConfig.recipes
              .firstWhere((recipe) => recipe.id == order.recipeId)
              .ingredients
          : workshopConfig.recipe(order.recipeId).ingredients;

  String _orderDisplayName(WorkshopCraftOrder order) =>
      order.area == WorkshopOrderArea.kitchen
          ? craftConfig.recipes
              .firstWhere((recipe) => recipe.id == order.recipeId)
              .displayName
          : workshopConfig.recipe(order.recipeId).displayName;

  String _orderResultItem(WorkshopCraftOrder order) =>
      order.area == WorkshopOrderArea.kitchen
          ? craftConfig.recipes
              .firstWhere((recipe) => recipe.id == order.recipeId)
              .resultItem
          : workshopConfig.recipe(order.recipeId).resultItem;

  int _orderResultAmount(WorkshopCraftOrder order) =>
      order.area == WorkshopOrderArea.kitchen
          ? craftConfig.recipes
              .firstWhere((recipe) => recipe.id == order.recipeId)
              .resultAmount
          : workshopConfig.recipe(order.recipeId).resultAmount;

  bool isAssignedToMarket(String figurineId) =>
      marketAssignedPtipoteId == figurineId;

  int get marketSlotLimit => marketConfig.slotsForLevel(marketLevel);

  bool isEquipmentResource(String resource) {
    return workshopConfig.recipes.any(
      (recipe) => recipe.resultItem == resource && recipe.isEquipment,
    );
  }

  int marketStackLimitFor(String resource) => isEquipmentResource(resource)
      ? 1
      : lisiereForageConfig.inventoryStackLimit;

  int get globalStockCapacity {
    return fablabConfig.baseGlobalStockCapacity +
        fablabLevel * fablabConfig.stockCapacityBonusPerFablabLevel;
  }

  int get inventorySlotLimit {
    return (globalStockCapacity / lisiereForageConfig.inventoryStackLimit)
        .floor();
  }

  int get inventoryUsedAmount {
    return inventory.fold(0, (total, stack) => total + stack.amount);
  }

  int generatorOrganicCapacity(int heartLevel) =>
      campGeneratorConfig.organicCapacity(heartLevel);

  int generatorMineralCapacity(int heartLevel) =>
      campGeneratorConfig.mineralCapacity(heartLevel);

  Duration? generatorRemaining(int heartLevel, {DateTime? now}) {
    final started = generatorCycleStartedAt;
    if (started == null || !_generatorCanRun) return null;
    final end = started.add(
      Duration(minutes: campGeneratorConfig.cycleMinutes(heartLevel)),
    );
    final remaining = end.difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _generatorCanRun =>
      generatorOrganic >= campGeneratorConfig.organicCostPerCycle &&
      generatorMineral >= campGeneratorConfig.mineralCostPerCycle;

  Zone0ActionResult transferToGenerator({
    required String resource,
    required int amount,
    required int heartLevel,
  }) {
    final isOrganic = resource == 'Organique';
    if (!isOrganic && resource != 'Minéral') {
      return const Zone0ActionResult(
          success: false, message: 'Ressource incompatible.');
    }
    final current = isOrganic ? generatorOrganic : generatorMineral;
    final capacity = isOrganic
        ? generatorOrganicCapacity(heartLevel)
        : generatorMineralCapacity(heartLevel);
    final moved = math.min(
        math.min(amount, resourceAmount(resource)), capacity - current);
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune ressource transférée.');
    }
    final removed = removeResource(resource, moved);
    if (isOrganic) {
      generatorOrganic += removed;
    } else {
      generatorMineral += removed;
    }
    generatorCycleStartedAt ??= _generatorCanRun ? DateTime.now() : null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$removed $resource ajouté au Générateur.');
  }

  bool resolveGenerator({required int heartLevel, DateTime? now}) {
    final current = now ?? DateTime.now();
    if (!_generatorCanRun) {
      generatorCycleStartedAt = null;
      return false;
    }
    generatorCycleStartedAt ??= current;
    final cycle =
        Duration(minutes: campGeneratorConfig.cycleMinutes(heartLevel));
    final elapsed = current.difference(generatorCycleStartedAt!);
    final elapsedCycles = elapsed.inSeconds ~/ math.max(1, cycle.inSeconds);
    if (elapsedCycles <= 0) return false;
    final possibleCycles = math.min(
      elapsedCycles,
      math.min(
        generatorOrganic ~/ campGeneratorConfig.organicCostPerCycle,
        generatorMineral ~/ campGeneratorConfig.mineralCostPerCycle,
      ),
    );
    if (possibleCycles <= 0) return false;
    generatorOrganic -=
        possibleCycles * campGeneratorConfig.organicCostPerCycle;
    generatorMineral -=
        possibleCycles * campGeneratorConfig.mineralCostPerCycle;
    final produced = possibleCycles * campGeneratorConfig.bioBatteriesPerCycle;
    bioBatteries += produced;
    generatorTotalProduced += produced;
    generatorCycleStartedAt = _generatorCanRun
        ? generatorCycleStartedAt!
            .add(Duration(seconds: cycle.inSeconds * possibleCycles))
        : null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return true;
  }

  int populationCapacityForCampHeartLevel(int campHeartLevel) {
    return kernelConfig.populationCapacityForCampHeartLevel(campHeartLevel);
  }

  String wellbeingColorLabel() {
    if (campWellbeing < kernelConfig.wellbeingRedThreshold) return 'Rouge';
    if (campWellbeing < kernelConfig.wellbeingOrangeThreshold) return 'Orange';
    return 'Vert';
  }

  List<KernelMissionProgress> kernelMissionsForCampHeartLevel(
    int campHeartLevel,
  ) {
    return kernelConfig.missions
        .map(
          (mission) => KernelMissionProgress(
            config: mission,
            progress: _kernelMissionProgress(mission),
            status: completedKernelMissionIds.contains(mission.id)
                ? KernelMissionStatus.completed
                : KernelMissionStatus.active,
          ),
        )
        .toList();
  }

  KernelMissionProgress? mainKernelMission(int campHeartLevel) {
    final missions = kernelMissionsForCampHeartLevel(campHeartLevel)
        .where((mission) => mission.config.type == KernelMissionType.main)
        .toList();
    for (final mission in missions) {
      if (mission.status != KernelMissionStatus.completed) return mission;
    }
    return missions.isEmpty ? null : missions.last;
  }

  List<KernelMissionProgress> refugeRequests(int campHeartLevel) {
    return kernelMissionsForCampHeartLevel(campHeartLevel)
        .where(
            (mission) => mission.config.type == KernelMissionType.refugeRequest)
        .take(kernelConfig.maxRefugeRequests)
        .toList();
  }

  int kernelAxisLevel(KernelAxis axis) => kernelAxisLevels[axis] ?? 1;

  int kernelAxisCurrentXp(KernelAxis axis) => kernelAxisXp[axis] ?? 0;

  int get kernelTrustXpRequired => kernelProgressConfig.xpRequired(
        level: kernelTrustLevel,
        isTrust: true,
      );

  int kernelAxisXpRequired(KernelAxis axis) => kernelProgressConfig.xpRequired(
        level: kernelAxisLevel(axis),
        isTrust: false,
      );

  KernelPlanState kernelPlanState(KernelTechnologyPlanConfig plan) {
    if (activeKernelPlanIds.contains(plan.id) ||
        (plan.initialState == KernelPlanState.active && isFablabBuilt)) {
      return KernelPlanState.active;
    }
    if (readyKernelPlanIds.contains(plan.id)) return KernelPlanState.ready;
    if (discoveredKernelPlanIds.contains(plan.id)) {
      return KernelPlanState.discovered;
    }
    return KernelPlanState.unknown;
  }

  bool isWorkshopRecipeActive(WorkshopRecipe recipe) {
    final matchingPlan = kernelProgressConfig.plans.where(
      (plan) => plan.workshopRecipeId == recipe.id,
    );
    if (matchingPlan.isEmpty) return true;
    return matchingPlan.any(
      (plan) => kernelPlanState(plan) == KernelPlanState.active,
    );
  }

  void emitKernelProgressEvent(KernelProgressEventType type) {
    final reward = kernelProgressConfig.eventRewards[type];
    if (reward == null) return;
    kernelEventCounts[type] = (kernelEventCounts[type] ?? 0) + 1;
    _addKernelTrustXp(reward.trustXp);
    for (final axis in KernelAxis.values) {
      _addKernelAxisXp(axis, reward.xpFor(axis));
    }
    kernelProgressHistory.add(
      KernelProgressHistoryEntry(
        occurredAt: DateTime.now(),
        eventType: type,
        trustXp: reward.trustXp,
        breederXp: reward.breederXp,
        builderXp: reward.builderXp,
        restorerXp: reward.restorerXp,
      ),
    );
    _refreshKernelPlanReadiness();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  Zone0ActionResult activateKernelPlan(String planId) {
    final plan = kernelProgressConfig.plans
        .where((item) => item.id == planId)
        .firstOrNull;
    if (plan == null || kernelPlanState(plan) != KernelPlanState.ready) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce Plan n’est pas encore prêt.',
      );
    }
    readyKernelPlanIds.remove(planId);
    activeKernelPlanIds.add(planId);
    reports.add(PtipoteMissionReport.system(
      message: 'Plan activé : ${plan.title}. ${plan.kernelText}',
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${plan.title} est maintenant disponible.',
    );
  }

  void _addKernelTrustXp(int amount) {
    kernelTrustXp += amount;
    while (kernelTrustXp >= kernelTrustXpRequired) {
      kernelTrustXp -= kernelTrustXpRequired;
      kernelTrustLevel += 1;
    }
  }

  void _addKernelAxisXp(KernelAxis axis, int amount) {
    if (amount <= 0) return;
    var xp = kernelAxisCurrentXp(axis) + amount;
    var level = kernelAxisLevel(axis);
    while (
        xp >= kernelProgressConfig.xpRequired(level: level, isTrust: false)) {
      xp -= kernelProgressConfig.xpRequired(level: level, isTrust: false);
      level += 1;
    }
    kernelAxisXp[axis] = xp;
    kernelAxisLevels[axis] = level;
  }

  void _refreshKernelPlanReadiness() {
    for (final plan in kernelProgressConfig.plans) {
      if (kernelPlanState(plan) == KernelPlanState.unknown &&
          plan.discoveryEvent != null &&
          (kernelEventCounts[plan.discoveryEvent] ?? 0) >=
              plan.discoveryThreshold) {
        discoveredKernelPlanIds.add(plan.id);
        reports.add(PtipoteMissionReport.system(
          message: 'Observation Kernel : ${plan.kernelText}',
        ));
      }
      if (kernelPlanState(plan) != KernelPlanState.discovered) continue;
      final axisReady = plan.requiredAxis == null ||
          kernelAxisLevel(plan.requiredAxis!) >= plan.requiredAxisLevel;
      if (kernelTrustLevel >= plan.requiredTrustLevel && axisReady) {
        readyKernelPlanIds.add(plan.id);
        reports.add(PtipoteMissionReport.system(
          message: 'Plan prêt : ${plan.title}. Le Kernel peut le partager.',
        ));
      }
    }
  }

  int vitalityFor(PtipoteFigurine figurine) {
    return vitalityOverrides[figurine.id] ?? figurine.vitality;
  }

  int hungerFor(PtipoteFigurine figurine) {
    return hungerOverrides[figurine.id] ?? ptipoteStatsConfig.baseHunger;
  }

  int restFor(PtipoteFigurine figurine) {
    return restOverrides[figurine.id] ?? ptipoteStatsConfig.maxRest;
  }

  int xpFor(PtipoteFigurine figurine) {
    return xpOverrides[figurine.id] ?? figurine.xpValue;
  }

  int levelFor(PtipoteFigurine figurine) {
    return levelOverrides[figurine.id] ?? figurine.levelValue;
  }

  PtipoteAutoAssignmentPreference autoPreferenceFor(PtipoteFigurine figurine) {
    return autoPreferenceOverrides[figurine.id] ??
        figurine.autoAssignmentPreference;
  }

  void setAutoPreference(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) {
    autoPreferenceOverrides[figurine.id] = preference;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  bool get hasUnreadReports => unreadReportCount > 0;

  int get unreadReportCount {
    return reports.where((report) => !report.read).length;
  }

  bool isOnMission(String figurineId) {
    return missions.any(
          (mission) =>
              mission.memberIds.contains(figurineId) &&
              mission.status == ForageMissionStatus.active,
        ) ||
        explorationMissions.any(
          (mission) =>
              mission.isActive && mission.memberIds.contains(figurineId),
        );
  }

  bool isResting(PtipoteFigurine figurine) {
    return !isOnMission(figurine.id) &&
        (manualRestingIds.contains(figurine.id) ||
            vitalityFor(figurine) <=
                ptipoteStatsConfig.minVitalityBeforeAutoRest);
  }

  bool isBusy(PtipoteFigurine figurine) {
    return isOnMission(figurine.id) ||
        isResting(figurine) ||
        isAssignedToTower(figurine.id) ||
        isAssignedToWorkshop(figurine.id) ||
        isAssignedToMarket(figurine.id);
  }

  double calculateWorkshopEfficiency(PtipoteFigurine figurine) {
    final levelBonus =
        levelFor(figurine) * workshopConfig.levelSpeedBonusPercent;
    return levelBonus.clamp(0, workshopConfig.maxLevelSpeedBonusPercent);
  }

  Zone0ActionResult startWorkshopOrder({
    required WorkshopRecipe recipe,
    required int quantity,
    PtipoteFigurine? figurine,
  }) {
    resolveWorkshopOrder();
    if (!isWorkshopRecipeActive(recipe)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Kernel n’a pas encore activé ce Plan.',
      );
    }
    if (figurine == null && activeManualWorkshopOrders >= 1) {
      return const Zone0ActionResult(
          success: false,
          message: 'Le créneau manuel de l’Atelier est occupé.');
    }
    if (figurine != null && activePtipoteWorkshopOrders >= workshopSlots) {
      return const Zone0ActionResult(
          success: false,
          message: 'Tous les emplacements P’TIPOTE sont occupés.');
    }
    if (quantity <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Quantité invalide.');
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
    }
    final totalCosts =
        recipe.ingredients.map((key, value) => MapEntry(key, value * quantity));
    if (!hasResources(totalCosts)) {
      return Zone0ActionResult(
          success: false, message: missingResourcesLabel(totalCosts));
    }
    if (!hasInventoryCapacityFor(
        <String, int>{recipe.resultItem: recipe.resultAmount * quantity})) {
      return const Zone0ActionResult(
          success: false, message: 'Inventaire insuffisant pour la commande.');
    }
    if (!removeResources(totalCosts)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources indisponibles.');
    }
    final speedBonus =
        figurine == null ? 0.0 : calculateWorkshopEfficiency(figurine);
    final unitSeconds = math.max(
        1,
        (Duration(minutes: recipe.durationMinutes).inSeconds * (1 - speedBonus))
            .round());
    final now = DateTime.now();
    workshopOrders.add(WorkshopCraftOrder(
      id: 'workshop-${now.microsecondsSinceEpoch}',
      recipeId: recipe.id,
      requestedQuantity: quantity,
      completedQuantity: 0,
      assignedPtipoteId: figurine?.id,
      assignedPtipoteName: figurine?.displayName,
      startTime: now,
      nextCompletionTime: now.add(Duration(seconds: unitSeconds)),
      unitDurationSeconds: unitSeconds,
      reservedResources: totalCosts,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '${recipe.displayName} lancé${figurine == null ? '' : ' avec ${figurine.displayName}'}.');
  }

  Zone0ActionResult startKitchenOrder({
    required CraftRecipe recipe,
    PtipoteFigurine? figurine,
  }) {
    resolveWorkshopOrder();
    if (!isFablabBuilt) {
      return const Zone0ActionResult(
          success: false,
          message: 'Construis le Fablab pour utiliser la Cuisine.');
    }
    if (fablabLevel < recipe.cuisineLevel) {
      return Zone0ActionResult(
          success: false,
          message: 'Cuisine niveau ${recipe.cuisineLevel} requise.');
    }
    if (figurine == null && activeManualKitchenOrders >= 1) {
      return const Zone0ActionResult(
          success: false,
          message: 'Le créneau manuel de la Cuisine est occupé.');
    }
    if (figurine != null && activePtipoteKitchenOrders >= workshopSlots) {
      return const Zone0ActionResult(
          success: false,
          message: 'Tous les emplacements P’TIPOTE sont occupés.');
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
    }
    final output = <String, int>{recipe.resultItem: recipe.resultAmount};
    if (!hasResources(recipe.ingredients)) {
      return Zone0ActionResult(
          success: false, message: missingResourcesLabel(recipe.ingredients));
    }
    if (!hasInventoryCapacityFor(output)) {
      return const Zone0ActionResult(
          success: false, message: 'Inventaire insuffisant pour la commande.');
    }
    if (!removeResources(recipe.ingredients)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources indisponibles.');
    }
    final speedBonus =
        figurine == null ? 0.0 : calculateWorkshopEfficiency(figurine);
    final unitSeconds = math.max(
      1,
      (Duration(minutes: recipe.durationMinutes).inSeconds * (1 - speedBonus))
          .round(),
    );
    final now = DateTime.now();
    workshopOrders.add(WorkshopCraftOrder(
      id: 'kitchen-${now.microsecondsSinceEpoch}',
      area: WorkshopOrderArea.kitchen,
      recipeId: recipe.id,
      requestedQuantity: 1,
      completedQuantity: 0,
      assignedPtipoteId: figurine?.id,
      assignedPtipoteName: figurine?.displayName,
      startTime: now,
      nextCompletionTime: now.add(Duration(seconds: unitSeconds)),
      unitDurationSeconds: unitSeconds,
      reservedResources: recipe.ingredients,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${recipe.displayName} lancé${figurine == null ? '' : ' avec ${figurine.displayName}'}.',
    );
  }

  bool resolveWorkshopOrder({DateTime? now}) {
    var changed = false;
    for (final order in List<WorkshopCraftOrder>.from(workshopOrders)) {
      changed = _resolveWorkshopOrder(order, now: now) || changed;
    }
    return changed;
  }

  bool _resolveWorkshopOrder(WorkshopCraftOrder order, {DateTime? now}) {
    if (order.status != WorkshopOrderStatus.active) return false;
    final current = now ?? DateTime.now();
    if (current.isBefore(order.nextCompletionTime)) return false;
    final ingredients = _orderIngredients(order);
    final resultItem = _orderResultItem(order);
    final resultAmount = _orderResultAmount(order);
    final displayName = _orderDisplayName(order);
    final elapsedUnits = 1 +
        current.difference(order.nextCompletionTime).inSeconds ~/
            order.unitDurationSeconds;
    var units = math.min(
        elapsedUnits, order.requestedQuantity - order.completedQuantity);
    if (order.assignedPtipoteId != null) {
      final vitality = vitalityOverrides[order.assignedPtipoteId!] ??
          ptipoteStatsConfig.maxVitality;
      final possible = math.max(
          0,
          (vitality - ptipoteStatsConfig.minVitalityBeforeAutoRest) ~/
              workshopConfig.vitalityCostPerUnit);
      units = math.min(units, possible);
    }
    if (units > 0) {
      addResources(<String, int>{resultItem: resultAmount * units});
      order.completedQuantity += units;
      order.nextCompletionTime = order.nextCompletionTime
          .add(Duration(seconds: order.unitDurationSeconds * units));
      if (order.assignedPtipoteId != null) {
        final id = order.assignedPtipoteId!;
        vitalityOverrides[id] = math.max(
            0,
            (vitalityOverrides[id] ?? ptipoteStatsConfig.maxVitality) -
                units * workshopConfig.vitalityCostPerUnit);
      }
    }
    final assignedVitality = order.assignedPtipoteId == null
        ? ptipoteStatsConfig.maxVitality
        : vitalityOverrides[order.assignedPtipoteId!] ??
            ptipoteStatsConfig.maxVitality;
    final tired = order.assignedPtipoteId != null &&
        assignedVitality <
            ptipoteStatsConfig.minVitalityBeforeAutoRest +
                workshopConfig.vitalityCostPerUnit;
    if (order.completedQuantity >= order.requestedQuantity || tired) {
      order.status = WorkshopOrderStatus.completed;
      if (tired) {
        manualRestingIds.add(order.assignedPtipoteId!);
        final remaining = order.requestedQuantity - order.completedQuantity;
        if (remaining > 0) {
          addResources(ingredients
              .map((key, value) => MapEntry(key, value * remaining)));
        }
      }
      reports.add(PtipoteMissionReport.system(
          message: tired
              ? '${order.assignedPtipoteName} rentre fatigué de ${order.area == WorkshopOrderArea.kitchen ? 'la Cuisine' : 'l’Atelier'}.'
              : 'Commande ${order.area == WorkshopOrderArea.kitchen ? 'Cuisine' : 'Atelier'} terminée : $displayName.'));
      if (order.area == WorkshopOrderArea.kitchen &&
          resultItem == craftConfig.simpleMealRecipe.resultItem) {
        mealsPrepared += resultAmount * order.completedQuantity;
        refreshKernelMissions();
      }
      emitKernelProgressEvent(KernelProgressEventType.craftCompleted);
    }
    notifyListeners();
    unawaited(saveInventoryToFirebase());
    unawaited(saveRuntimeToFirebase());
    return true;
  }

  Zone0ActionResult cancelWorkshopOrder(String orderId) {
    final order =
        workshopOrders.where((item) => item.id == orderId).firstOrNull;
    if (order == null || order.status != WorkshopOrderStatus.active) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune commande active.');
    }
    resolveWorkshopOrder();
    final remaining = order.requestedQuantity - order.completedQuantity;
    final ingredients = _orderIngredients(order);
    if (remaining > 0) {
      addResources(
          ingredients.map((key, value) => MapEntry(key, value * remaining)));
    }
    order.status = WorkshopOrderStatus.cancelled;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true,
        message: 'Commande annulée, ressources restantes rendues.');
  }

  Zone0ActionResult constructMarket(int heartLevel) {
    if (isMarketBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Le Marché est déjà construit.');
    }
    if (heartLevel < marketConfig.requiredCampHeartLevel) {
      return const Zone0ActionResult(
          success: false, message: 'Niveau du Cœur insuffisant.');
    }
    if (currentPopulation < marketConfig.requiredPopulation) {
      return Zone0ActionResult(
          success: false,
          message: 'Population requise : ${marketConfig.requiredPopulation}.');
    }
    if (!hasResources(marketConfig.constructionCost)) {
      return Zone0ActionResult(
          success: false,
          message: missingResourcesLabel(marketConfig.constructionCost));
    }
    if (!removeResources(marketConfig.constructionCost)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources indisponibles.');
    }
    marketLevel = 1;
    emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
    reports.add(PtipoteMissionReport.system(message: 'Le Marché est ouvert.'));
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Le Marché est prêt.');
  }

  Zone0ActionResult transferToMarket(String resource, int amount) {
    if (!isMarketBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Marché non construit.');
    }
    if (!marketConfig.saleValues.containsKey(resource)) {
      return const Zone0ActionResult(
          success: false, message: 'Objet non vendable.');
    }
    final existing =
        marketStock.where((item) => item.resource == resource).firstOrNull;
    if (existing == null && marketStock.length >= marketSlotLimit) {
      return const Zone0ActionResult(
          success: false, message: 'Les trois emplacements sont occupés.');
    }
    final freeInStack = marketStackLimitFor(resource) - (existing?.amount ?? 0);
    if (freeInStack <= 0) {
      return Zone0ActionResult(
        success: false,
        message:
            'Cet emplacement accepte ${marketStackLimitFor(resource)} $resource maximum.',
      );
    }
    final moved = removeResource(
      resource,
      math.min(amount, math.min(resourceAmount(resource), freeInStack)),
    );
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Stock insuffisant.');
    }
    if (existing == null) {
      marketStock.add(Zone0InventoryStack(resource: resource, amount: moved));
    } else {
      existing.amount += moved;
    }
    marketNextSaleAt ??= DateTime.now().add(_marketSaleInterval());
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved $resource placé au Marché.');
  }

  Zone0ActionResult returnMarketStock(String resource) {
    final stack =
        marketStock.where((item) => item.resource == resource).firstOrNull;
    if (stack == null) {
      return const Zone0ActionResult(success: false, message: 'Stock absent.');
    }
    final result = addResources(<String, int>{resource: stack.amount});
    final returned = stack.amount - (result.pending[resource] ?? 0);
    stack.amount -= returned;
    if (stack.amount <= 0) marketStock.remove(stack);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: returned > 0,
        message: '$returned $resource rendu à la Maison.');
  }

  Zone0ActionResult assignToMarket(PtipoteFigurine figurine) {
    if (!isMarketBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Marché non construit.');
    }
    if (marketAssignedPtipoteId != null) {
      return const Zone0ActionResult(
          success: false, message: 'Un P’TIPOTE travaille déjà au Marché.');
    }
    if (isBusy(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
    }
    if (vitalityFor(figurine) <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE trop fatigué.');
    }
    marketAssignedPtipoteId = figurine.id;
    marketAssignedPtipoteName = figurine.displayName;
    marketLastWorkTickAt = DateTime.now();
    vitalityOverrides.putIfAbsent(figurine.id, () => vitalityFor(figurine));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '${figurine.displayName} aide au Marché.');
  }

  Zone0ActionResult removeFromMarket({bool tired = false}) {
    final id = marketAssignedPtipoteId;
    if (id == null) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun P’TIPOTE affecté.');
    }
    if (tired) manualRestingIds.add(id);
    final name = marketAssignedPtipoteName ?? 'Le P’TIPOTE';
    marketAssignedPtipoteId = null;
    marketAssignedPtipoteName = null;
    marketLastWorkTickAt = null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$name rentre à la Maison.');
  }

  Duration _marketSaleInterval() {
    final populationModifier =
        (10 / math.max(5, currentPopulation)).clamp(0.5, 2.0);
    final wellbeingModifier = (1.3 - campWellbeing / 250).clamp(0.8, 1.3);
    final ptipoteModifier = marketAssignedPtipoteId == null
        ? 1.0
        : marketConfig.ptipoteIntervalMultiplier;
    return Duration(
        seconds: math.max(
            1,
            (marketConfig.baseSaleIntervalMinutes *
                    60 *
                    populationModifier *
                    wellbeingModifier *
                    ptipoteModifier)
                .round()));
  }

  Duration? marketSaleRemaining({DateTime? now}) {
    final next = marketNextSaleAt;
    if (next == null || marketStock.isEmpty) return null;
    final remaining = next.difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool resolveMarket({DateTime? now}) {
    if (!isMarketBuilt) return false;
    final current = now ?? DateTime.now();
    var changed = false;
    if (marketAssignedPtipoteId != null) {
      marketLastWorkTickAt ??= current;
      final ticks = current.difference(marketLastWorkTickAt!).inMinutes ~/
          math.max(1, marketConfig.vitalityTickMinutes);
      if (ticks > 0) {
        final id = marketAssignedPtipoteId!;
        vitalityOverrides[id] = math.max(
          0,
          (vitalityOverrides[id] ?? ptipoteStatsConfig.maxVitality) -
              ticks * marketConfig.vitalityCostPerTick,
        );
        marketLastWorkTickAt = marketLastWorkTickAt!.add(
          Duration(minutes: ticks * marketConfig.vitalityTickMinutes),
        );
        if (vitalityOverrides[id]! <=
            ptipoteStatsConfig.minVitalityBeforeAutoRest) {
          removeFromMarket(tired: true);
        }
        changed = true;
      }
    }
    if (marketStock.isNotEmpty) {
      marketNextSaleAt ??= current.add(_marketSaleInterval());
    }
    var guard = 0;
    while (marketStock.isNotEmpty &&
        marketNextSaleAt != null &&
        !current.isBefore(marketNextSaleAt!) &&
        guard++ < 500) {
      final stack = marketStock.first;
      stack.amount -= 1;
      marketValueRemainder += marketConfig.saleValues[stack.resource] ?? 0;
      if (stack.amount <= 0) marketStock.removeAt(0);
      final earned = marketValueRemainder ~/ marketConfig.valuePerBioBattery;
      if (earned > 0) {
        bioBatteries += earned;
        marketBioBatteriesEarned += earned;
        marketValueRemainder %= marketConfig.valuePerBioBattery;
      }
      if (marketAssignedPtipoteId != null &&
          _random.nextDouble() < marketConfig.requestChance &&
          marketRequests
                  .where((item) => item.status != MarketRequestStatus.completed)
                  .length <
              marketConfig.maxActiveRequests) {
        _createMarketRequest(current);
      }
      marketNextSaleAt = marketStock.isEmpty
          ? null
          : marketNextSaleAt!.add(_marketSaleInterval());
      changed = true;
    }
    if (marketStock.isEmpty && marketAssignedPtipoteId != null) {
      removeFromMarket();
      changed = true;
    }
    for (final request in marketRequests.where((item) =>
        item.status != MarketRequestStatus.completed &&
        !current.isBefore(item.customerReturnTime))) {
      final stock = marketStock
          .where((item) => item.resource == request.requestedItemId)
          .firstOrNull;
      if (marketAssignedPtipoteId != null &&
          stock != null &&
          stock.amount >= request.requestedQuantity) {
        stock.amount -= request.requestedQuantity;
        if (stock.amount <= 0) marketStock.remove(stock);
        bioBatteries += request.rewardBioBattery;
        campWellbeing = math.min(100, campWellbeing + request.rewardWellbeing);
        request.status = MarketRequestStatus.completed;
        reports.add(PtipoteMissionReport.system(
            message:
                'Demande livrée : ${request.requestedQuantity} ${request.requestedItemId}.'));
      } else {
        request.status = MarketRequestStatus.waitingCustomer;
        request.customerReturnTime = current.add(_randomMarketReturnDelay());
      }
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _createMarketRequest(DateTime now) {
    final entries = marketConfig.saleValues.keys.toList();
    final item = entries[_random.nextInt(entries.length)];
    final isResource = item == 'Organique' || item == 'Minéral';
    marketRequests.add(MarketCustomerRequest(
        id: 'request-${now.microsecondsSinceEpoch}-${marketRequests.length}',
        requestedItemId: item,
        requestedQuantity:
            isResource ? lisiereForageConfig.inventoryStackLimit : 1,
        rewardBioBattery: math.max(
            1,
            (marketConfig.saleValues[item] ?? 1) ~/
                marketConfig.valuePerBioBattery),
        rewardWellbeing: 1,
        createdAt: now,
        customerReturnTime: now.add(_randomMarketReturnDelay()),
        status: MarketRequestStatus.noted));
    reports.add(PtipoteMissionReport.system(
        message: 'Demande du Marché : $item recherché.'));
  }

  Duration _randomMarketReturnDelay() => Duration(
      minutes: marketConfig.requestMinReturnMinutes +
          _random.nextInt(math.max(
              1,
              marketConfig.requestMaxReturnMinutes -
                  marketConfig.requestMinReturnMinutes +
                  1)));

  bool isUnavailableForTower(PtipoteFigurine figurine) {
    return isOnMission(figurine.id) ||
        isAssignedToTower(figurine.id) ||
        isAssignedToWorkshop(figurine.id) ||
        isAssignedToMarket(figurine.id);
  }

  bool isHappy(PtipoteFigurine figurine) {
    return moodFor(figurine) == PtipoteMood.happy;
  }

  bool isFed(PtipoteFigurine figurine) {
    return hungerFor(figurine) > ptipoteStatsConfig.happyHungerThreshold;
  }

  bool isRested(PtipoteFigurine figurine) {
    final state = restStateFor(figurine);
    return state == PtipoteRestState.wellRested ||
        state == PtipoteRestState.rested;
  }

  bool hasIndigestion(PtipoteFigurine figurine) {
    return hungerFor(figurine) > ptipoteStatsConfig.indigestionHungerThreshold;
  }

  PtipoteRestState restStateFor(PtipoteFigurine figurine) {
    return ptipoteStatsConfig.restStateFor(restFor(figurine));
  }

  String restStateLabelFor(PtipoteFigurine figurine) {
    return switch (restStateFor(figurine)) {
      PtipoteRestState.wellRested => 'Bien reposé',
      PtipoteRestState.rested => 'Reposé',
      PtipoteRestState.tired => 'Fatigué',
      PtipoteRestState.exhausted => 'Exténué',
    };
  }

  bool isCuddleCareActive(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return false;
    return DateTime.now().difference(cuddleAt) <=
        Duration(minutes: ptipoteStatsConfig.cuddleCareDurationMinutes);
  }

  int satisfiedNeedCount(PtipoteFigurine figurine) {
    return <bool>[
      isFed(figurine),
      isRested(figurine),
      isCuddleCareActive(figurine),
    ].where((satisfied) => satisfied).length;
  }

  PtipoteMood moodFor(PtipoteFigurine figurine) {
    final count = satisfiedNeedCount(figurine);
    if (count >= ptipoteStatsConfig.happyNeedsRequired) {
      return PtipoteMood.happy;
    }
    if (count >= ptipoteStatsConfig.okayNeedsRequired) {
      return PtipoteMood.okay;
    }
    return PtipoteMood.unwell;
  }

  String moodLabelFor(PtipoteFigurine figurine) {
    return switch (moodFor(figurine)) {
      PtipoteMood.happy => 'Heureux',
      PtipoteMood.okay => 'Bien',
      PtipoteMood.unwell => 'Mal',
    };
  }

  bool canCuddle(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return true;
    return DateTime.now().difference(cuddleAt) >=
        Duration(minutes: ptipoteStatsConfig.cuddleCooldownMinutes);
  }

  double cuddleCooldownProgress(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return 1;
    final cooldown =
        Duration(minutes: ptipoteStatsConfig.cuddleCooldownMinutes);
    final elapsed = DateTime.now().difference(cuddleAt);
    return (elapsed.inSeconds / cooldown.inSeconds).clamp(0.0, 1.0);
  }

  Duration vitalityRecoveryRemaining(PtipoteFigurine figurine) {
    final missing =
        math.max(0, ptipoteStatsConfig.maxVitality - vitalityFor(figurine));
    if (missing == 0) return Duration.zero;
    if (isResting(figurine)) {
      return Duration(
        minutes: (missing / ptipoteStatsConfig.alcoveVitalityRecoveryPerMinute)
            .ceil(),
      );
    }
    if (isHappy(figurine)) {
      return Duration(
        minutes: (missing / ptipoteStatsConfig.happyVitalityRecoveryPerMinute)
            .ceil(),
      );
    }
    return Duration(
      minutes: missing * ptipoteStatsConfig.naturalVitalityRecoveryMinutes,
    );
  }

  Duration restRecoveryRemaining(PtipoteFigurine figurine) {
    final missing = math.max(0, ptipoteStatsConfig.maxRest - restFor(figurine));
    if (missing == 0) return Duration.zero;
    return Duration(
      minutes: (missing / ptipoteStatsConfig.sleepRestRecoveryPerMinute).ceil(),
    );
  }

  void sendToSleep(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    manualRestingIds.add(figurine.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void cuddle(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    if (!canCuddle(figurine)) return;
    lastCuddleAt[figurine.id] = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void wakeFromRest(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    manualRestingIds.remove(figurine.id);
    final wakeVitality = math.min(
      ptipoteStatsConfig.maxVitality,
      ptipoteStatsConfig.minVitalityBeforeAutoRest + 1,
    );
    vitalityOverrides[figurine.id] =
        math.max(vitalityFor(figurine), wakeVitality);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void recoverFigurineNeeds({
    required List<PtipoteFigurine> figurines,
    required int tick,
  }) {
    var changed = false;
    if (resolveDueTowerMissions()) {
      changed = true;
    }
    if (_applyElapsedSimulation(figurines)) {
      changed = true;
    }
    final hungerDecayTick =
        math.max(1, ptipoteStatsConfig.hungerDecayMinutes * 2);
    final restLossTick =
        math.max(1, ptipoteStatsConfig.awakeRestLossMinutes * 2);
    final naturalVitalityTick =
        math.max(1, ptipoteStatsConfig.naturalVitalityRecoveryMinutes * 2);
    for (final figurine in figurines) {
      if (isOnMission(figurine.id)) continue;
      if (towerAssignedIds.contains(figurine.id)) {
        if (tick % math.max(1, securityTowerConfig.tickMinutes * 2) == 0) {
          final currentVitality = vitalityFor(figurine);
          final nextVitality = math.max(
            0,
            currentVitality - securityTowerConfig.vitalityCostPerTick,
          );
          vitalityOverrides[figurine.id] = nextVitality;
          refugeSafety = math.min(
            securityTowerConfig.maxSecurity,
            refugeSafety + securityTowerConfig.securityGainPerTick,
          );
          if (nextVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
            towerAssignedIds.remove(figurine.id);
            manualRestingIds.add(figurine.id);
          }
          changed = true;
        }
        continue;
      }
      if (isAssignedToTower(figurine.id) ||
          isAssignedToWorkshop(figurine.id) ||
          isAssignedToMarket(figurine.id)) {
        continue;
      }
      final currentVitality = vitalityFor(figurine);
      final resting = isResting(figurine);
      final happy = isHappy(figurine);
      final hunger = hungerFor(figurine);
      var vitalityGain = 0;
      if (resting && tick.isEven) {
        vitalityGain = ptipoteStatsConfig.vitalityRecoveryPerMinute;
      } else if (happy && tick.isEven) {
        vitalityGain = ptipoteStatsConfig.happyVitalityRecoveryPerMinute;
      } else if (!resting &&
          hunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
          hunger <= ptipoteStatsConfig.indigestionHungerThreshold &&
          tick % math.max(1, (naturalVitalityTick * 0.75).round()) == 0) {
        vitalityGain = 1;
      } else if (tick % naturalVitalityTick == 0) {
        vitalityGain = 1;
      }

      if (vitalityGain > 0) {
        if (hunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
            hunger <= ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = math.max(
            1,
            (vitalityGain *
                    (1 + ptipoteStatsConfig.wellFedVitalityRecoveryBonus))
                .round(),
          );
        } else if (hunger > ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = math.max(
            0,
            (vitalityGain *
                    (1 - ptipoteStatsConfig.indigestionVitalityRecoveryPenalty))
                .floor(),
          );
        }
      }

      if (vitalityGain > 0 &&
          currentVitality < ptipoteStatsConfig.maxVitality) {
        final nextVitality = math.min(
          ptipoteStatsConfig.maxVitality,
          currentVitality + vitalityGain,
        );
        if (nextVitality >= ptipoteStatsConfig.maxVitality &&
            restFor(figurine) >= ptipoteStatsConfig.maxRest) {
          vitalityOverrides.remove(figurine.id);
          manualRestingIds.remove(figurine.id);
        } else {
          vitalityOverrides[figurine.id] = nextVitality;
        }
        changed = true;
      }

      if (tick % hungerDecayTick == 0) {
        final currentHunger = hungerFor(figurine);
        if (currentHunger > 0) {
          hungerOverrides[figurine.id] = math.max(0, currentHunger - 1);
          changed = true;
        }
      }

      final currentRest = restFor(figurine);
      if (resting) {
        final restGain =
            math.max(1, ptipoteStatsConfig.sleepRestRecoveryPerMinute ~/ 2);
        final nextRest =
            math.min(ptipoteStatsConfig.maxRest, currentRest + restGain);
        if (nextRest != currentRest) {
          restOverrides[figurine.id] = nextRest;
          changed = true;
        }
      } else if (tick % restLossTick == 0 && currentRest > 0) {
        restOverrides[figurine.id] = math.max(0, currentRest - 1);
        changed = true;
      }
    }
    if (isSecurityTowerBuilt &&
        towerAssignedIds.isEmpty &&
        !hasActiveTowerMission &&
        tick % math.max(1, securityTowerConfig.tickMinutes * 2) == 0 &&
        refugeSafety > 0) {
      refugeSafety = math.max(
        0,
        refugeSafety - securityTowerConfig.securityDecayPerTick,
      );
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  bool _applyElapsedSimulation(List<PtipoteFigurine> figurines) {
    final now = DateTime.now();
    final previous = lastSimulationAt;
    if (previous == null) {
      lastSimulationAt = now;
      return true;
    }
    final elapsedMinutes = now.difference(previous).inMinutes;
    if (elapsedMinutes <= 0) return false;

    var changed = false;
    final figurinesById = <String, PtipoteFigurine>{
      for (final figurine in figurines) figurine.id: figurine,
    };

    for (final figurine in figurines) {
      if (isOnMission(figurine.id)) continue;
      if (towerAssignedIds.contains(figurine.id)) continue;
      if (isAssignedToTower(figurine.id) ||
          isAssignedToWorkshop(figurine.id) ||
          isAssignedToMarket(figurine.id)) {
        continue;
      }

      final resting = isResting(figurine);
      var currentHunger = hungerFor(figurine);
      var currentRest = restFor(figurine);
      var currentVitality = vitalityFor(figurine);

      final hungerLoss =
          elapsedMinutes ~/ math.max(1, ptipoteStatsConfig.hungerDecayMinutes);
      if (hungerLoss > 0 && currentHunger > 0) {
        currentHunger = math.max(0, currentHunger - hungerLoss);
        hungerOverrides[figurine.id] = currentHunger;
        changed = true;
      }

      if (resting) {
        final restGain =
            elapsedMinutes * ptipoteStatsConfig.sleepRestRecoveryPerMinute;
        if (restGain > 0 && currentRest < ptipoteStatsConfig.maxRest) {
          currentRest =
              math.min(ptipoteStatsConfig.maxRest, currentRest + restGain);
          restOverrides[figurine.id] = currentRest;
          changed = true;
        }
        if (currentVitality < ptipoteStatsConfig.maxVitality) {
          currentVitality = math.min(
            ptipoteStatsConfig.maxVitality,
            currentVitality +
                elapsedMinutes * ptipoteStatsConfig.vitalityRecoveryPerMinute,
          );
          vitalityOverrides[figurine.id] = currentVitality;
          changed = true;
        }
      } else {
        final restLoss = elapsedMinutes ~/
            math.max(1, ptipoteStatsConfig.awakeRestLossMinutes);
        if (restLoss > 0 && currentRest > 0) {
          currentRest = math.max(0, currentRest - restLoss);
          restOverrides[figurine.id] = currentRest;
          changed = true;
        }

        final recoveryInterval = isHappy(figurine)
            ? math.max(1,
                (1 / ptipoteStatsConfig.happyVitalityRecoveryPerMinute).ceil())
            : ptipoteStatsConfig.naturalVitalityRecoveryMinutes;
        var vitalityGain = elapsedMinutes ~/ math.max(1, recoveryInterval);
        if (currentHunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
            currentHunger <= ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = (vitalityGain *
                  (1 + ptipoteStatsConfig.wellFedVitalityRecoveryBonus))
              .round();
        } else if (currentHunger >
            ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = (vitalityGain *
                  (1 - ptipoteStatsConfig.indigestionVitalityRecoveryPenalty))
              .floor();
        }
        if (vitalityGain > 0 &&
            currentVitality < ptipoteStatsConfig.maxVitality) {
          currentVitality = math.min(
            ptipoteStatsConfig.maxVitality,
            currentVitality + vitalityGain,
          );
          vitalityOverrides[figurine.id] = currentVitality;
          changed = true;
        }
      }
    }

    final towerTicks =
        elapsedMinutes ~/ math.max(1, securityTowerConfig.tickMinutes);
    if (towerTicks > 0) {
      if (towerAssignedIds.isNotEmpty) {
        for (final figurineId in towerAssignedIds.toList()) {
          final figurine = figurinesById[figurineId];
          if (figurine == null) continue;
          final nextVitality = math.max(
            0,
            vitalityFor(figurine) -
                towerTicks * securityTowerConfig.vitalityCostPerTick,
          );
          vitalityOverrides[figurine.id] = nextVitality;
          refugeSafety = math.min(
            securityTowerConfig.maxSecurity,
            refugeSafety + towerTicks * securityTowerConfig.securityGainPerTick,
          );
          if (nextVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
            towerAssignedIds.remove(figurine.id);
            manualRestingIds.add(figurine.id);
          }
          changed = true;
        }
      } else if (isSecurityTowerBuilt &&
          !hasActiveTowerMission &&
          refugeSafety > 0) {
        refugeSafety = math.max(
          0,
          refugeSafety - towerTicks * securityTowerConfig.securityDecayPerTick,
        );
        changed = true;
      }
    }

    lastSimulationAt = now;
    return changed;
  }

  int resourceAmount(String resource) {
    return inventory
        .where((stack) => stack.resource == resource)
        .fold(0, (total, stack) => total + stack.amount);
  }

  Zone0ActionResult openBioBattery() {
    if (bioBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune Bio-batterie disponible.');
    }
    bioBatteries -= 1;
    energyUnits += wasteRecyclerConfig.energyUnitsPerBioBattery;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '+${wasteRecyclerConfig.energyUnitsPerBioBattery} Énergie.',
    );
  }

  Zone0ActionResult transferWasteToRecycler(int amount, int campHeartLevel) {
    if (!isRecyclerUnlocked(campHeartLevel)) {
      return Zone0ActionResult(
          success: false,
          message:
              'Débloqué au Cœur du Camp niveau ${wasteRecyclerConfig.recyclerUnlockCampHeartLevel}.');
    }
    if (recyclerLevel == 0) {
      recyclerLevel = wasteRecyclerConfig.initialRecyclerLevel;
    }
    final moved = math.min(
      math.min(amount, resourceAmount('Déchets')),
      recyclerTankCapacity - recyclerWasteTank,
    );
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun Déchet transféré.');
    }
    removeResource('Déchets', moved);
    recyclerWasteTank += moved;
    resolveWasteAndRecycler(campHeartLevel: campHeartLevel);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved Déchet(s) vers la cuve.');
  }

  Zone0ActionResult retrieveRecyclerOutput() {
    final rewards = <String, int>{
      'Organique': recyclerOutputOrganic,
      'Minéral': recyclerOutputMineral,
    };
    final result = addResources(rewards);
    final organicLeft = result.pending['Organique'] ?? 0;
    final mineralLeft = result.pending['Minéral'] ?? 0;
    recyclerOutputOrganic = organicLeft;
    recyclerOutputMineral = mineralLeft;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: result.addedAny,
      message: result.hasPending
          ? 'Inventaire plein : production conservée dans le Recycleur.'
          : 'Production récupérée.',
    );
  }

  bool resolveWasteAndRecycler({required int campHeartLevel, DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    if (pendingWaste > 0) {
      final result = addResources(<String, int>{'Déchets': pendingWaste});
      pendingWaste = result.pending['Déchets'] ?? 0;
      changed = result.addedAny;
    }
    final builtBuildings = <bool>[
          isFablabBuilt,
          isSecurityTowerBuilt,
          isMarketBuilt
        ].where((item) => item).length +
        1;
    final lastWaste = lastWasteGenerationAt ?? current;
    final wasteCycles = current.difference(lastWaste).inMinutes ~/
        wasteRecyclerConfig.wasteGenerationCycleMinutes;
    if (wasteCycles > 0) {
      final perCycle = wasteRecyclerConfig.baseWastePerCycle +
          currentPopulation ~/ wasteRecyclerConfig.populationPerWasteUnit +
          builtBuildings ~/ wasteRecyclerConfig.buildingsPerWasteUnit;
      if (perCycle > 0) {
        final generated = perCycle * wasteCycles;
        final result = addResources(<String, int>{'Déchets': generated});
        pendingWaste = math.min(
          wasteRecyclerConfig.pendingWasteCapacity,
          pendingWaste + (result.pending['Déchets'] ?? 0),
        );
      }
      lastWasteGenerationAt = lastWaste.add(Duration(
          minutes:
              wasteCycles * wasteRecyclerConfig.wasteGenerationCycleMinutes));
      changed = true;
    }
    if (!isRecyclerUnlocked(campHeartLevel)) return changed;
    if (recyclerLevel == 0) {
      recyclerLevel = wasteRecyclerConfig.initialRecyclerLevel;
      changed = true;
    }
    var completedCycles = 0;
    var producedOrganic = 0;
    var producedMineral = 0;
    while (recyclerCycleStartedAt != null) {
      final finishedAt = recyclerCycleStartedAt!.add(
          Duration(minutes: wasteRecyclerConfig.cycleMinutes(recyclerLevel)));
      if (finishedAt.isAfter(current)) break;
      final split = wasteRecyclerConfig.outputSplits[
          _random.nextInt(wasteRecyclerConfig.outputSplits.length)];
      recyclerOutputOrganic += split.organic;
      recyclerOutputMineral += split.mineral;
      completedCycles += 1;
      producedOrganic += split.organic;
      producedMineral += split.mineral;
      recyclerCycleStartedAt = finishedAt;
      changed = true;
      if (recyclerOutputAmount + wasteRecyclerConfig.outputResourcesPerCycle >
          wasteRecyclerConfig.outputStorageCapacity) {
        recyclerCycleStartedAt = null;
      } else if (recyclerWasteTank < recyclerWasteRequired ||
          energyUnits < wasteRecyclerConfig.energyCostPerCycle) {
        recyclerCycleStartedAt = null;
      } else {
        recyclerWasteTank -= recyclerWasteRequired;
        energyUnits -= wasteRecyclerConfig.energyCostPerCycle;
      }
    }
    if (recyclerCycleStartedAt == null &&
        recyclerOutputAmount + wasteRecyclerConfig.outputResourcesPerCycle <=
            wasteRecyclerConfig.outputStorageCapacity &&
        recyclerWasteTank >= recyclerWasteRequired &&
        energyUnits >= wasteRecyclerConfig.energyCostPerCycle) {
      recyclerWasteTank -= recyclerWasteRequired;
      energyUnits -= wasteRecyclerConfig.energyCostPerCycle;
      recyclerCycleStartedAt = current;
      changed = true;
    }
    if (completedCycles > 0) {
      reports.add(PtipoteMissionReport.system(
        message: 'Recycleur : $completedCycles cycle(s) terminé(s). '
            'Déchets traités : ${completedCycles * recyclerWasteRequired}. '
            'Énergie consommée : ${completedCycles * wasteRecyclerConfig.energyCostPerCycle}. '
            '+$producedOrganic Organique, +$producedMineral Minéral.',
      ));
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  int inventoryFreeCapacityFor(Map<String, int> rewards) {
    final simulated = inventory
        .map(
          (stack) => Zone0InventoryStack(
            resource: stack.resource,
            amount: stack.amount,
          ),
        )
        .toList();
    var freeSlots = inventorySlotLimit - simulated.length;
    var capacity = 0;

    for (final entry in rewards.entries) {
      var remaining = math.max(0, entry.value);
      for (final stack
          in simulated.where((stack) => stack.resource == entry.key)) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        capacity += add;
      }

      while (remaining > 0 && freeSlots > 0) {
        final add =
            math.min(remaining, lisiereForageConfig.inventoryStackLimit);
        simulated.add(Zone0InventoryStack(resource: entry.key, amount: add));
        freeSlots -= 1;
        remaining -= add;
        capacity += add;
      }
    }

    return capacity;
  }

  int removeResource(String resource, int requestedAmount) {
    var remaining = math.max(0, requestedAmount);
    var removed = 0;
    for (final stack in inventory.toList()) {
      if (remaining <= 0) break;
      if (stack.resource != resource) continue;
      final take = math.min(stack.amount, remaining);
      stack.amount -= take;
      remaining -= take;
      removed += take;
      if (stack.amount <= 0) {
        inventory.remove(stack);
      }
    }
    if (removed > 0) {
      notifyListeners();
      unawaited(saveInventoryToFirebase());
    }
    return removed;
  }

  bool hasResources(Map<String, int> costs) {
    return costs.entries.every(
      (entry) => resourceAmount(entry.key) >= math.max(0, entry.value),
    );
  }

  bool hasInventoryCapacityFor(Map<String, int> rewards) {
    return inventoryFreeCapacityFor(rewards) >=
        rewards.values.fold(0, (total, amount) => total + math.max(0, amount));
  }

  bool removeResources(Map<String, int> costs) {
    final cleanCosts = Map<String, int>.from(costs)
      ..removeWhere((_, amount) => amount <= 0);
    if (!hasResources(cleanCosts)) return false;

    for (final entry in cleanCosts.entries) {
      removeResource(entry.key, entry.value);
    }
    unawaited(saveInventoryToFirebase());
    return true;
  }

  Zone0ActionResult constructFablabLevel1() {
    if (isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Fablab est déjà construit.',
      );
    }

    final cost = fablabConfig.constructionCostLevel1;
    if (!hasResources(cost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(cost),
      );
    }

    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }

    fablabLevel = 1;
    emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
    reports.add(
      PtipoteMissionReport.system(
        message: 'Le Fablab est prêt. La Cuisine est maintenant disponible.',
      ),
    );
    refreshKernelMissions();
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Le Fablab est prêt. La Cuisine peut maintenant être utilisée.',
    );
  }

  Zone0ActionResult constructSecurityTower(int campHeartLevel) {
    if (isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Tour est déjà construite.',
      );
    }
    if (campHeartLevel < securityTowerConfig.requiredCampHeartLevel) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Cœur du Camp doit atteindre le niveau 1.',
      );
    }
    final cost = securityTowerConfig.constructionCost;
    if (!hasResources(cost)) {
      return Zone0ActionResult(
          success: false, message: missingResourcesLabel(cost));
    }
    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }
    securityTowerLevel = 1;
    emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
    refugeSafety = math.max(refugeSafety, securityTowerConfig.initialSecurity);
    reports.add(
      PtipoteMissionReport.system(
        message: 'La Tour de sécurité est construite.',
      ),
    );
    ensureWeatherForecast();
    refreshKernelMissions(campHeartLevel: campHeartLevel);
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'La Tour surveille maintenant les abords du refuge.',
    );
  }

  Duration towerManualRechargeRemaining({DateTime? now}) {
    final last = lastManualTowerRechargeAt;
    if (last == null) return Duration.zero;
    final remaining = last
        .add(Duration(
            minutes: securityTowerConfig.manualRechargeCooldownMinutes))
        .difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Zone0ActionResult manuallyRechargeTower() {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Tour non construite.');
    }
    final remaining = towerManualRechargeRemaining();
    if (remaining > Duration.zero) {
      return Zone0ActionResult(
          success: false,
          message: 'Balises disponibles dans ${remaining.inMinutes + 1} min.');
    }
    refugeSafety = math.min(securityTowerConfig.maxSecurity,
        refugeSafety + securityTowerConfig.manualRechargeSecurityGain);
    lastManualTowerRechargeAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '+${securityTowerConfig.manualRechargeSecurityGain} Sécurité.');
  }

  Zone0ActionResult assignToTower(PtipoteFigurine figurine) {
    return startTowerMission(
      figurine: figurine,
      plan: TowerMissionPlan.oneHour,
    );
  }

  Zone0ActionResult startTowerMission({
    required PtipoteFigurine figurine,
    required TowerMissionPlan plan,
    ForageBiome? patrolBiome,
  }) {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Tour non construite.');
    }
    resolveDueTowerMissions();
    final activeCount = towerMissions
        .where((mission) => mission.status == TowerMissionStatus.active)
        .length;
    if (activeCount >= securityTowerSlots) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun slot libre.');
    }
    if (isUnavailableForTower(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
    }
    if (vitalityFor(figurine) < ptipoteStatsConfig.minimumMissionVitality) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE trop fatigué.');
    }
    final vitality = vitalityFor(figurine);
    final ticks = _towerTicksForPlan(plan, vitality);
    if (ticks <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Vitalité insuffisante pour surveiller la Tour.',
      );
    }
    vitalityOverrides.putIfAbsent(figurine.id, () => vitality);
    final start = DateTime.now();
    towerMissions.add(
      TowerMission(
        id: 'tower-${start.microsecondsSinceEpoch}',
        figurineId: figurine.id,
        figurineName: figurine.displayName,
        plan: plan,
        startTime: start,
        endTime: start.add(_towerDurationForTicks(ticks)),
        vitalityCost: ticks * securityTowerConfig.vitalityCostPerTick,
        securityGain: ticks * securityTowerConfig.securityGainPerTick,
        sleepAfter: plan == TowerMissionPlan.until25Vitality,
        patrolBiome: patrolBiome,
      ),
    );
    manualRestingIds.remove(figurine.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${figurine.displayName} surveille la Tour.',
    );
  }

  void removeFromTower(String figurineId) {
    var changed = towerAssignedIds.remove(figurineId);
    for (final mission in towerMissions) {
      if (mission.figurineId == figurineId &&
          mission.status == TowerMissionStatus.active) {
        _resolveTowerMission(mission, early: true);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  Zone0ActionResult prepareSimpleMeal() {
    return prepareRecipe(craftConfig.simpleMealRecipe);
  }

  Zone0ActionResult prepareRecipe(CraftRecipe recipe) {
    if (!isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis le Fablab pour utiliser la Cuisine.',
      );
    }

    final cost = recipe.ingredients;
    final output = <String, int>{recipe.resultItem: recipe.resultAmount};
    if (!hasResources(cost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(cost),
      );
    }
    if (!hasInventoryCapacityFor(output)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire plein : libère un slot avant de cuisiner.',
      );
    }
    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }
    addResources(output);
    emitKernelProgressEvent(KernelProgressEventType.craftCompleted);
    if (recipe.resultItem == craftConfig.simpleMealRecipe.resultItem) {
      mealsPrepared += recipe.resultAmount;
    }
    refreshKernelMissions();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${recipe.displayName} préparé.',
    );
  }

  Zone0ActionResult consumeSimpleMeal(PtipoteFigurine figurine) {
    final recipe = craftConfig.simpleMealRecipe;
    if (!recipe.isConsumable) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cet objet n’est pas consommable.',
      );
    }
    if (resourceAmount(recipe.resultItem) <= 0) {
      return Zone0ActionResult(
        success: false,
        message: 'Aucun ${recipe.resultItem} disponible.',
      );
    }
    final removed = removeResource(recipe.resultItem, 1);
    if (removed <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Repas indisponible.',
      );
    }
    hungerOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxOverfedHunger,
      hungerFor(figurine) + recipe.hungerRestore,
    );
    vitalityOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxVitality,
      vitalityFor(figurine) + recipe.vitalityRestore,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${figurine.displayName} mange ${recipe.resultItem} (+${recipe.hungerRestore} faim, +${recipe.vitalityRestore} vitalité).',
    );
  }

  String missingResourcesLabel(Map<String, int> costs) {
    final missing = costs.entries
        .map((entry) => MapEntry(
              entry.key,
              math.max(0, entry.value - resourceAmount(entry.key)),
            ))
        .where((entry) => entry.value > 0)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(', ');
    return missing.isEmpty ? 'Ressources disponibles.' : 'Il manque $missing.';
  }

  Future<void> loadFromFirebase() async {
    if (_loadedFromFirebase) return;
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Chargement Zone 0', () async {
      final snapshot = await _zone0Doc(user.uid).get();
      final data = snapshot.data();
      if (data == null) {
        _loadedFromFirebase = true;
        return;
      }

      final inventoryData = data['inventory'];
      if (inventoryData is List) {
        inventory
          ..clear()
          ..addAll(
            inventoryData
                .whereType<Map>()
                .map(
                  (item) => Zone0InventoryStack(
                    resource: '${item['resource'] ?? ''}',
                    amount: _readInt(item['amount']),
                  ),
                )
                .where(
                    (stack) => stack.resource.isNotEmpty && stack.amount > 0),
          );
      }

      final vitalityData = data['vitalityOverrides'];
      if (vitalityData is Map) {
        vitalityOverrides
          ..clear()
          ..addEntries(
            vitalityData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final hungerData = data['hungerOverrides'];
      if (hungerData is Map) {
        hungerOverrides
          ..clear()
          ..addEntries(
            hungerData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final restData = data['restOverrides'];
      if (restData is Map) {
        restOverrides
          ..clear()
          ..addEntries(
            restData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final restingData = data['manualRestingIds'];
      if (restingData is List) {
        manualRestingIds
          ..clear()
          ..addAll(restingData.map((id) => '$id'));
      }

      final autoPreferenceData = data['autoPreferenceOverrides'];
      if (autoPreferenceData is Map) {
        autoPreferenceOverrides
          ..clear()
          ..addEntries(
            autoPreferenceData.entries.map((entry) {
              return MapEntry(
                '${entry.key}',
                ForageMission._enumByName(
                  PtipoteAutoAssignmentPreference.values,
                  '${entry.value}',
                  PtipoteAutoAssignmentPreference.home,
                ),
              );
            }),
          );
      }

      final cuddleData = data['lastCuddleAt'];
      if (cuddleData is Map) {
        lastCuddleAt
          ..clear()
          ..addEntries(
            cuddleData.entries.map((entry) {
              final date = _readDate(entry.value);
              if (date == null) return null;
              return MapEntry('${entry.key}', date);
            }).whereType<MapEntry<String, DateTime>>(),
          );
      }

      final missionData = data['missions'];
      if (missionData is List) {
        missions
          ..clear()
          ..addAll(
            missionData
                .whereType<Map>()
                .map(ForageMission.fromFirebase)
                .whereType<ForageMission>(),
          );
      }

      final towerMissionData = data['towerMissions'];
      if (towerMissionData is List) {
        towerMissions
          ..clear()
          ..addAll(
            towerMissionData
                .whereType<Map>()
                .map(TowerMission.fromFirebase)
                .whereType<TowerMission>(),
          );
      }
      workshopOrders.clear();
      final workshopOrdersData = data['workshopOrders'];
      if (workshopOrdersData is List) {
        workshopOrders.addAll(
          workshopOrdersData
              .whereType<Map>()
              .map(WorkshopCraftOrder.fromFirebase),
        );
      } else {
        // V1 stored one order only. Keep it when upgrading the save format.
        final workshopData = data['workshopOrder'];
        if (workshopData is Map) {
          workshopOrders.add(WorkshopCraftOrder.fromFirebase(workshopData));
        }
      }
      final marketData = data['market'];
      if (marketData is Map) {
        marketStock
          ..clear()
          ..addAll((marketData['stock'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => Zone0InventoryStack(
                  resource: '${item['resource'] ?? ''}',
                  amount: _readInt(item['amount'])))
              .where((item) => item.resource.isNotEmpty && item.amount > 0));
        marketRequests
          ..clear()
          ..addAll((marketData['requests'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketCustomerRequest.fromFirebase));
        marketNextSaleAt = _readDate(marketData['nextSaleAt']);
        marketLastWorkTickAt = _readDate(marketData['lastWorkTickAt']);
        marketAssignedPtipoteId = marketData['assignedPtipoteId'] as String?;
        marketAssignedPtipoteName =
            marketData['assignedPtipoteName'] as String?;
        marketValueRemainder = _readInt(marketData['valueRemainder']);
        marketBioBatteriesEarned = _readInt(marketData['bioBatteriesEarned']);
        merchantAvailableUntil =
            _readDate(marketData['merchantAvailableUntil']);
        merchantOffers
          ..clear()
          ..addAll((marketData['merchantOffers'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => MerchantOffer(
                    planName: '${item['planName'] ?? ''}',
                    price: _readInt(item['price']),
                    purchased: item['purchased'] == true,
                  ))
              .where((item) => item.planName.isNotEmpty));
      }

      final localSecurityData = data['biomeSecurity'];
      if (localSecurityData is Map) {
        for (final biome in ForageBiome.values) {
          final value = localSecurityData[biome.name];
          if (value is Map) {
            biomeSecurity[biome] =
                BiomeSecurityState.fromFirebase(biome, value);
          }
        }
      }
      final explorationData = data['explorationMissions'];
      if (explorationData is List) {
        explorationMissions
          ..clear()
          ..addAll(explorationData
              .whereType<Map>()
              .map(BiomeExplorationMission.fromFirebase));
      }

      final reportData = data['reports'];
      if (reportData is List) {
        reports
          ..clear()
          ..addAll(
            reportData
                .whereType<Map>()
                .map(PtipoteMissionReport.fromFirebase)
                .whereType<PtipoteMissionReport>(),
          );
      }

      final kernelData = data['kernel'];
      if (kernelData is Map) {
        currentPopulation = _readInt(
          kernelData['currentPopulation'],
          fallback: kernelConfig.startingPopulation,
        );
        bioBatteries = _readInt(
          kernelData['bioBatteries'],
          fallback: kernelConfig.startingBioBatteries,
        );
        energyUnits = _readInt(kernelData['energyUnits']);
        campWellbeing = _readInt(
          kernelData['campWellbeing'],
          fallback: kernelConfig.startingWellbeing,
        ).clamp(0, 100);
        mealsPrepared = _readInt(kernelData['mealsPrepared']);
        plaineMissionsCompleted =
            _readInt(kernelData['plaineMissionsCompleted']);
        kernelTrustLevel = _readInt(kernelData['trustLevel'], fallback: 1);
        kernelTrustXp = _readInt(kernelData['trustXp']);
        for (final axis in KernelAxis.values) {
          kernelAxisLevels[axis] = _readInt(
            (kernelData['axisLevels'] as Map?)?[axis.name],
            fallback: 1,
          );
          kernelAxisXp[axis] = _readInt(
            (kernelData['axisXp'] as Map?)?[axis.name],
          );
        }
        kernelEventCounts.clear();
        final eventCounts = kernelData['eventCounts'] as Map?;
        for (final type in KernelProgressEventType.values) {
          kernelEventCounts[type] = _readInt(eventCounts?[type.name]);
        }
        discoveredKernelPlanIds
          ..clear()
          ..addAll((kernelData['discoveredPlanIds'] as List? ?? const [])
              .map((id) => '$id'));
        readyKernelPlanIds
          ..clear()
          ..addAll((kernelData['readyPlanIds'] as List? ?? const [])
              .map((id) => '$id'));
        activeKernelPlanIds
          ..clear()
          ..addAll((kernelData['activePlanIds'] as List? ?? const [])
              .map((id) => '$id'));
        kernelProgressHistory
          ..clear()
          ..addAll((kernelData['progressHistory'] as List? ?? const [])
              .whereType<Map>()
              .map(KernelProgressHistoryEntry.fromFirebase));
        final completedData = kernelData['completedMissionIds'];
        if (completedData is List) {
          completedKernelMissionIds
            ..clear()
            ..addAll(completedData.map((id) => '$id'));
        }
        kernelPopulationRewardsGranted.clear();
        final grantedData = kernelData['populationRewardsGranted'];
        if (grantedData is Map) {
          for (final entry in grantedData.entries) {
            final amount = _readInt(entry.value);
            if (amount > 0) {
              kernelPopulationRewardsGranted['${entry.key}'] = amount;
            }
          }
          _needsKernelPopulationRewardMigration = false;
        } else {
          // Older saves only stored completed ids. Reconstruct the rewards
          // already received from the current population once on next refresh.
          _needsKernelPopulationRewardMigration =
              completedKernelMissionIds.isNotEmpty;
        }
      }
      final generatorData = data['campGenerator'];
      if (generatorData is Map) {
        generatorOrganic = _readInt(generatorData['organic']);
        generatorMineral = _readInt(generatorData['mineral']);
        generatorTotalProduced = _readInt(generatorData['totalProduced']);
        generatorCycleStartedAt = _readDate(generatorData['cycleStartedAt']);
      }
      final recyclerData = data['recycler'];
      if (recyclerData is Map) {
        recyclerLevel = _readInt(recyclerData['level']).clamp(0, 5);
        recyclerWasteTank = _readInt(recyclerData['wasteTank']);
        recyclerOutputOrganic = _readInt(recyclerData['outputOrganic']);
        recyclerOutputMineral = _readInt(recyclerData['outputMineral']);
        pendingWaste = _readInt(recyclerData['pendingWaste']);
        recyclerCycleStartedAt = _readDate(recyclerData['cycleStartedAt']);
        lastWasteGenerationAt =
            _readDate(recyclerData['lastWasteGenerationAt']);
      }

      final buildingsData = data['buildings'];
      if (buildingsData is Map) {
        final fablabData = buildingsData['fablab'];
        if (fablabData is Map) {
          fablabLevel = _readInt(fablabData['currentLevel']).clamp(
            0,
            fablabConfig.fablabMaxLevel,
          );
        }
        final towerData = buildingsData['securityTower'];
        if (towerData is Map) {
          securityTowerLevel = _readInt(towerData['currentLevel']).clamp(0, 3);
        }
        final marketBuildingData = buildingsData['market'];
        if (marketBuildingData is Map) {
          marketLevel =
              _readInt(marketBuildingData['currentLevel']).clamp(0, 5);
        }
      }
      refugeSafety = _readInt(data['campSecurity']).clamp(
        0,
        securityTowerConfig.maxSecurity,
      );
      final towerAssignedData = data['towerAssignedIds'];
      if (towerAssignedData is List) {
        towerAssignedIds
          ..clear()
          ..addAll(towerAssignedData.map((id) => '$id'));
      }
      lastSimulationAt =
          _readDate(data['lastSimulationAt']) ?? _readDate(data['updatedAt']);
      lastManualTowerRechargeAt = _readDate(data['lastManualTowerRechargeAt']);

      _loadedFromFirebase = true;
    });
  }

  ForageMission startForageMission({
    required List<PtipoteFigurine> figurines,
    required ForageBiome biome,
    required ForageDuration duration,
    required ForageIntensity intensity,
    required Map<String, int> expectedRewards,
    required Map<String, int> vitalityCostByMember,
    required int riskPercent,
    required String riskLabel,
    required int baseRiskPercent,
    required int securityAtLaunch,
    required int securityReduction,
    required Map<String, int> xpGainByMember,
  }) {
    final start = DateTime.now();
    final durationConfig = lisiereForageConfig.durations[duration]!;
    for (final figurine in figurines) {
      levelOverrides.putIfAbsent(figurine.id, () => figurine.levelValue);
      xpOverrides.putIfAbsent(figurine.id, () => figurine.xpValue);
    }
    final memberIds = figurines.map((figurine) => figurine.id).toList();
    final memberNames =
        figurines.map((figurine) => figurine.displayName).toList();
    final totalVitalityCost =
        vitalityCostByMember.values.fold(0, (total, cost) => total + cost);
    final totalXpGain =
        xpGainByMember.values.fold(0, (total, xp) => total + xp);
    final mission = ForageMission(
      id: 'mission-${start.microsecondsSinceEpoch}',
      figurineId: memberIds.first,
      figurineName: memberNames.join(', '),
      memberIds: memberIds,
      memberNames: memberNames,
      biome: biome,
      duration: duration,
      intensity: intensity,
      startTime: start,
      endTime: start.add(
        durationConfig.realDuration(lisiereForageConfig.forageTimeScale),
      ),
      expectedRewards: expectedRewards,
      vitalityCost: totalVitalityCost,
      vitalityCostByMember: vitalityCostByMember,
      riskPercent: riskPercent,
      riskLabel: riskLabel,
      baseRiskPercent: baseRiskPercent,
      securityAtLaunch: securityAtLaunch,
      securityReduction: securityReduction,
      xpGain: totalXpGain,
      xpGainByMember: xpGainByMember,
      autoPreferenceByMember: <String, PtipoteAutoAssignmentPreference>{
        for (final figurine in figurines)
          figurine.id: autoPreferenceFor(figurine),
      },
    );
    missions.add(mission);
    for (final figurine in figurines) {
      final vitalityCost = vitalityCostByMember[figurine.id] ?? 0;
      vitalityOverrides[figurine.id] = math.max(
        0,
        vitalityFor(figurine) - vitalityCost,
      );
      hungerOverrides[figurine.id] = math.max(
        0,
        hungerFor(figurine) -
            (vitalityCost * ptipoteStatsConfig.missionHungerCostRatio).round(),
      );
      restOverrides[figurine.id] = math.max(
        0,
        restFor(figurine) -
            (vitalityCost * ptipoteStatsConfig.missionRestLossRatio).round(),
      );
      manualRestingIds.remove(figurine.id);
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return mission;
  }

  Zone0ActionResult startBiomeExploration({
    required ForageBiome biome,
    required List<PtipoteFigurine> figurines,
    int durationHours = 2,
  }) {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'La Tour est nécessaire pour explorer.');
    }
    if (refugeSafety < towerOperationsConfig.biomeRevealSecurityThreshold) {
      return Zone0ActionResult(
          success: false,
          message:
              'La Sécurité doit atteindre ${towerOperationsConfig.biomeRevealSecurityThreshold}% pour révéler les environs.');
    }
    final state = biomeSecurity[biome]!;
    if (state.status == BiomeDiscoveryStatus.unlocked) {
      return const Zone0ActionResult(
          success: false, message: 'Ce biome est déjà disponible en Lisière.');
    }
    if (isBiomeExploring(biome) || figurines.isEmpty) {
      return const Zone0ActionResult(
          success: false, message: 'Exploration indisponible.');
    }
    if (figurines.any(isUnavailableForTower)) {
      return const Zone0ActionResult(
          success: false, message: 'Un P’TIPOTE choisi est occupé.');
    }
    final now = DateTime.now();
    explorationMissions.add(BiomeExplorationMission(
      id: 'exploration-${now.microsecondsSinceEpoch}',
      biome: biome,
      memberIds: figurines.map((item) => item.id).toList(),
      memberNames: figurines.map((item) => item.displayName).toList(),
      endTime: now.add(Duration(
        minutes: math.max(
          1,
          (durationHours * 60 / lisiereForageConfig.forageTimeScale).round(),
        ),
      )),
      explorationProgressGain: durationHours * 10,
    ));
    state.status = BiomeDiscoveryStatus.exploring;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Exploration de ${lisiereForageConfig.biomes[biome]!.label} lancée.');
  }

  Zone0ActionResult startBiomePatrol({
    required ForageBiome biome,
    required PtipoteFigurine figurine,
    required TowerMissionPlan plan,
  }) {
    if (!isBiomeUnlocked(biome)) {
      return const Zone0ActionResult(
          success: false, message: 'Termine d’abord l’exploration.');
    }
    final result = startTowerMission(
      figurine: figurine,
      plan: plan,
      patrolBiome: biome,
    );
    if (!result.success) return result;
    reports.add(PtipoteMissionReport.system(
        message:
            '${figurine.displayName} sécurise les abords de ${lisiereForageConfig.biomes[biome]!.label}.'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '${figurine.displayName} est en ronde locale. Le gain sera appliqué au retour.');
  }

  void resolveTowerOperations({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    for (final mission in explorationMissions
        .where((item) => item.isActive && !item.endTime.isAfter(current))) {
      mission.completedAt = current;
      final state = biomeSecurity[mission.biome]!;
      state.explorationProgress = math.min(
          100, state.explorationProgress + mission.explorationProgressGain);
      state.status = state.explorationProgress >= 100
          ? BiomeDiscoveryStatus.unlocked
          : BiomeDiscoveryStatus.discovered;
      state.lastMissionAt = current;
      reports.add(PtipoteMissionReport.system(
          message: state.status == BiomeDiscoveryStatus.unlocked
              ? '${mission.memberNames.join(', ')} a découvert ${lisiereForageConfig.biomes[mission.biome]!.label}. Le biome est disponible en Lisière.'
              : '${mission.memberNames.join(', ')} progresse dans l’exploration de ${lisiereForageConfig.biomes[mission.biome]!.label} : ${state.explorationProgress}%.'));
      changed = true;
    }
    for (final state in biomeSecurity.values) {
      final lastActivity = state.lastMissionAt ?? state.lastPatrolAt;
      if (lastActivity == null ||
          current.difference(lastActivity).inHours >=
              towerOperationsConfig.localSecurityRecentMissionHours) {
        final elapsedHours = state.lastDecayAt == null
            ? 0
            : current.difference(state.lastDecayAt!).inHours;
        if (elapsedHours > 0 && state.localSecurity > 0) {
          state.localSecurity = math.max(
              0,
              state.localSecurity -
                  elapsedHours *
                      towerOperationsConfig.localSecurityDecayPerHour);
          state.lastDecayAt = current;
          changed = true;
        }
      }
    }
    if (merchantAvailableUntil != null &&
        !current.isBefore(merchantAvailableUntil!)) {
      merchantAvailableUntil = null;
      merchantOffers.clear();
      reports.add(PtipoteMissionReport.system(
          message: 'Le Marchand est reparti sans attente.'));
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  void openMerchant() {
    if (isMerchantAvailable) return;
    merchantAvailableUntil = DateTime.now()
        .add(Duration(hours: towerOperationsConfig.merchantPresenceHours));
    merchantOffers
      ..clear()
      ..addAll(towerOperationsConfig.merchantOfferPrices.entries.map(
          (entry) => MerchantOffer(planName: entry.key, price: entry.value)));
    reports.add(PtipoteMissionReport.system(
        message: 'Un Marchand est arrivé au Marché avec des Plans rares.'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  Zone0ActionResult buyMerchantOffer(MerchantOffer offer) {
    if (!isMerchantAvailable || offer.purchased) {
      return const Zone0ActionResult(
          success: false, message: 'Offre indisponible.');
    }
    if (bioBatteries < offer.price) {
      return const Zone0ActionResult(
          success: false, message: 'Bio-batteries insuffisantes.');
    }
    bioBatteries -= offer.price;
    offer.purchased = true;
    reports.add(PtipoteMissionReport.system(
        message: '${offer.planName} a été acquis auprès du Marchand.'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '${offer.planName} acheté.');
  }

  void ensureWeatherForecast() {
    if (!isSecurityTowerBuilt ||
        weatherAlerts.any((item) => item.endsAt.isAfter(DateTime.now()))) {
      return;
    }
    final now = DateTime.now();
    final config = towerOperationsConfig.weatherEvents[
        _random.nextInt(towerOperationsConfig.weatherEvents.length)];
    weatherAlerts.add(WeatherAlert(
        type: config.type,
        startsAt: now.add(Duration(minutes: config.warningMinutes)),
        endsAt: now.add(Duration(
            minutes: config.warningMinutes + config.durationMinutes))));
    reports.add(PtipoteMissionReport.system(
        message:
            'Alerte Tour : ${config.label} approche. Le Kernel demande ${config.preparationAmount} ${config.preparationItem}.'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  Zone0ActionResult fulfillWeatherPreparation(WeatherAlert alert,
      {WeatherPreparationType type = WeatherPreparationType.provide}) {
    final config = towerOperationsConfig.weatherEvents
        .firstWhere((item) => item.type == alert.type);
    if (alert.preparationCompleted) {
      return const Zone0ActionResult(
          success: false, message: 'Préparation déjà terminée.');
    }
    if (resourceAmount(config.preparationItem) < config.preparationAmount) {
      return Zone0ActionResult(
          success: false,
          message:
              'Il faut ${config.preparationAmount} ${config.preparationItem}.');
    }
    if (type == WeatherPreparationType.provide) {
      removeResource(config.preparationItem, config.preparationAmount);
    }
    alert.preparationCompleted = true;
    reports.add(PtipoteMissionReport.system(
        message: 'Préparation météo validée : ${config.label} sera atténué.'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Préparation validée.');
  }

  bool resolveDueForageMissions({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    resolveTowerOperations(now: currentTime);
    var resolvedAny = false;
    for (final mission in missions) {
      if (mission.status != ForageMissionStatus.active) continue;
      if (mission.endTime.isAfter(currentTime)) continue;
      _resolveMission(mission, completedAt: currentTime);
      resolvedAny = true;
    }
    if (resolvedAny) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return resolvedAny;
  }

  bool resolveDueTowerMissions({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    var resolvedAny = false;
    for (final mission in towerMissions) {
      if (mission.status != TowerMissionStatus.active) continue;
      if (mission.endTime.isAfter(currentTime)) continue;
      _resolveTowerMission(mission);
      resolvedAny = true;
    }
    if (resolvedAny) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return resolvedAny;
  }

  Zone0ActionResult emergencyReturnForageMission(String missionId) {
    ForageMission? mission;
    for (final item in missions) {
      if (item.id == missionId) {
        mission = item;
        break;
      }
    }
    if (mission == null || mission.status != ForageMissionStatus.active) {
      return const Zone0ActionResult(
        success: false,
        message: 'Mission indisponible.',
      );
    }
    final now = DateTime.now();
    final totalSeconds = math.max(
      1,
      mission.endTime.difference(mission.startTime).inSeconds,
    );
    final elapsedSeconds = now.difference(mission.startTime).inSeconds.clamp(
          0,
          totalSeconds,
        );
    final ratio = (elapsedSeconds / totalSeconds).clamp(0.05, 1.0);
    _resolveMission(
      mission,
      completedAt: now,
      rewardRatio: ratio,
      riskBonus: 5,
      emergencyReturn: true,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Retour d’urgence lancé. Butin récupéré à ${(ratio * 100).round()}%.',
    );
  }

  int freeInventorySlots() {
    return inventorySlotLimit - inventory.length;
  }

  InventoryAddResult addResources(Map<String, int> rewards) {
    final pending = Map<String, int>.from(rewards)
      ..removeWhere((_, amount) => amount <= 0);
    var addedAny = false;

    for (final entry in pending.entries.toList()) {
      var remaining = entry.value;
      for (final stack
          in inventory.where((stack) => stack.resource == entry.key)) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        addedAny = true;
      }

      while (remaining > 0 && inventory.length < inventorySlotLimit) {
        final add =
            math.min(remaining, lisiereForageConfig.inventoryStackLimit);
        inventory.add(Zone0InventoryStack(resource: entry.key, amount: add));
        remaining -= add;
        addedAny = true;
      }

      if (remaining <= 0) {
        pending.remove(entry.key);
      } else {
        pending[entry.key] = remaining;
      }
    }

    if (addedAny) unawaited(saveInventoryToFirebase());
    return InventoryAddResult(addedAny: addedAny, pending: pending);
  }

  void markReportsRead() {
    var changed = false;
    for (final report in reports) {
      if (!report.read) changed = true;
      report.read = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  void deleteReport(String reportId) {
    final before = reports.length;
    reports.removeWhere((report) => report.id == reportId);
    if (reports.length != before) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  int _kernelMissionProgress(KernelMissionConfig mission) {
    return switch (mission.conditionType) {
      KernelMissionConditionType.fablabBuilt => isFablabBuilt ? 1 : 0,
      KernelMissionConditionType.securityTowerBuilt =>
        isSecurityTowerBuilt ? 1 : 0,
      KernelMissionConditionType.mealsPrepared => mealsPrepared,
      KernelMissionConditionType.plaineMissionsCompleted =>
        plaineMissionsCompleted,
    };
  }

  bool refreshKernelMissions({int? campHeartLevel}) {
    var changed = false;
    if (campHeartLevel != null) {
      _lastKnownCampHeartLevel = campHeartLevel.clamp(1, 5);
    }
    final populationCapacity =
        populationCapacityForCampHeartLevel(_lastKnownCampHeartLevel);

    if (_needsKernelPopulationRewardMigration) {
      var alreadyCredited = math.max(
        0,
        currentPopulation - kernelConfig.startingPopulation,
      );
      for (final mission in kernelConfig.missions) {
        if (!completedKernelMissionIds.contains(mission.id)) continue;
        final granted = math.min(mission.populationReward, alreadyCredited);
        if (granted > 0) {
          kernelPopulationRewardsGranted[mission.id] = granted;
          alreadyCredited -= granted;
        }
      }
      _needsKernelPopulationRewardMigration = false;
      changed = true;
    }

    var restoredPopulation = 0;
    for (final mission in kernelConfig.missions) {
      final wasCompleted = completedKernelMissionIds.contains(mission.id);
      if (!wasCompleted) {
        if (_kernelMissionProgress(mission) < mission.requiredAmount) continue;
        completedKernelMissionIds.add(mission.id);
        bioBatteries += mission.bioBatteryReward;
        reports.add(PtipoteMissionReport.system(message: mission.mailMessage));
        changed = true;
      }

      final alreadyGranted = (kernelPopulationRewardsGranted[mission.id] ?? 0)
          .clamp(0, mission.populationReward);
      final remainingReward = mission.populationReward - alreadyGranted;
      final availableCapacity =
          math.max(0, populationCapacity - currentPopulation);
      final populationGrantedNow = math.min(remainingReward, availableCapacity);
      if (populationGrantedNow <= 0) continue;

      currentPopulation += populationGrantedNow;
      kernelPopulationRewardsGranted[mission.id] =
          alreadyGranted + populationGrantedNow;
      if (wasCompleted) restoredPopulation += populationGrantedNow;
      changed = true;
    }

    if (restoredPopulation > 0) {
      reports.add(
        PtipoteMissionReport.system(
          message:
              '$restoredPopulation habitant(s) rejoignent le refuge : récompenses Kernel restaurées.',
        ),
      );
    }
    if (changed) {
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _resolveMission(
    ForageMission mission, {
    required DateTime completedAt,
    double rewardRatio = 1,
    int riskBonus = 0,
    bool emergencyReturn = false,
  }) {
    final biome = lisiereForageConfig.biomes[mission.biome]!;
    final duration = lisiereForageConfig.durations[mission.duration]!;
    final intensity = lisiereForageConfig.intensities[mission.intensity]!;
    var rewards = Map<String, int>.from(mission.expectedRewards);
    var incident = 'aucun';

    rewards = rewards.map(
      (key, value) => MapEntry(key, math.max(0, (value * rewardRatio).floor())),
    );
    final realRisk = math.min(100, mission.riskPercent + riskBonus);

    if (_random.nextInt(100) < realRisk) {
      final hazards = biome.hazards.isEmpty
          ? ForageHazard.values.where((h) => h != ForageHazard.none).toList()
          : biome.hazards;
      final hazard = hazards[_random.nextInt(hazards.length)];
      switch (hazard) {
        case ForageHazard.pollution:
          rewards['Organique'] = ((rewards['Organique'] ?? 0) * 0.8).round();
          incident = 'pollution légère, -20 % Organique';
        case ForageHazard.droneErrant:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.75).round()));
          incident = 'drone errant, -25 % gains totaux';
        case ForageHazard.climatDifficile:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.85).round()));
          incident = 'climat difficile, -15 % gains totaux';
        case ForageHazard.terrainInstable:
          rewards['Minéral'] = ((rewards['Minéral'] ?? 0) * 0.8).round();
          incident = 'terrain instable, -20 % Minéral';
        case ForageHazard.none:
          break;
      }
    }

    final mainRewards = (rewards['Organique'] ?? 0) + (rewards['Minéral'] ?? 0);
    if (mainRewards > 0) {
      final percent = wasteRecyclerConfig.wasteRewardMinimumPercent +
          _random.nextInt(wasteRecyclerConfig.wasteRewardMaximumPercent -
              wasteRecyclerConfig.wasteRewardMinimumPercent +
              1);
      final waste = (mainRewards * percent / 100).floor();
      if (waste > 0) rewards['Déchets'] = waste;
    }
    final inventoryResult = addResources(rewards);
    final xpResults = <String, PtipoteXpGainResult>{};
    for (final memberId in mission.memberIds) {
      final xpGain = mission.xpGainByMember[memberId] ??
          (mission.memberIds.isEmpty
              ? mission.xpGain
              : (mission.xpGain / mission.memberIds.length).round());
      final xpResult = addMissionXp(memberId, xpGain);
      xpResults[memberId] = xpResult;
      unawaited(persistFigurineProgress(
        figurineId: memberId,
        xp: xpResult.xp,
        level: xpResult.level,
      ));
    }
    if (mission.biome == ForageBiome.plaineRiche) {
      plaineMissionsCompleted += 1;
    }
    final localState = biomeSecurity[mission.biome];
    if (localState != null) {
      localState.lastMissionAt = completedAt;
      localState.lastDecayAt = completedAt;
    }
    emitKernelProgressEvent(KernelProgressEventType.missionCompleted);
    if (incident.startsWith('pollution')) {
      emitKernelProgressEvent(KernelProgressEventType.pollutionObserved);
    }
    refreshKernelMissions();
    final memberStateLabels = <String>[];
    var lowestVitality = ptipoteStatsConfig.maxVitality;
    var lowestHunger = ptipoteStatsConfig.baseHunger;
    var leveledUp = false;
    var highestLevel = 0;
    for (var index = 0; index < mission.memberIds.length; index += 1) {
      final memberId = mission.memberIds[index];
      final memberName = index < mission.memberNames.length
          ? mission.memberNames[index]
          : mission.figurineName;
      final vitality = vitalityOverrides[memberId] ?? 0;
      final hunger = hungerOverrides[memberId] ?? ptipoteStatsConfig.baseHunger;
      final rest = restOverrides[memberId] ?? ptipoteStatsConfig.maxRest;
      lowestVitality = math.min(lowestVitality, vitality);
      lowestHunger = math.min(lowestHunger, hunger);
      final moodLabel = _moodLabelForValues(
        hunger: hunger,
        rest: rest,
        figurineId: memberId,
      );
      if (vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
        manualRestingIds.add(memberId);
        towerAssignedIds.remove(memberId);
      } else {
        manualRestingIds.remove(memberId);
        final preference = mission.autoPreferenceByMember[memberId] ??
            autoPreferenceOverrides[memberId] ??
            PtipoteAutoAssignmentPreference.home;
        if (preference == PtipoteAutoAssignmentPreference.tower &&
            isSecurityTowerBuilt &&
            towerMissions
                    .where(
                      (mission) => mission.status == TowerMissionStatus.active,
                    )
                    .length <
                securityTowerSlots) {
          final ticks = _towerTicksForPlan(
            TowerMissionPlan.oneHour,
            vitality,
          );
          towerMissions.add(
            TowerMission(
              id: 'tower-${DateTime.now().microsecondsSinceEpoch}-$memberId',
              figurineId: memberId,
              figurineName: memberName,
              plan: TowerMissionPlan.oneHour,
              startTime: completedAt,
              endTime: completedAt.add(_towerDurationForTicks(ticks)),
              vitalityCost: ticks * securityTowerConfig.vitalityCostPerTick,
              securityGain: ticks * securityTowerConfig.securityGainPerTick,
              sleepAfter: false,
            ),
          );
        }
      }
      memberStateLabels.add(
        _finalMissionStateLabel(
          figurineName: memberName,
          vitality: vitality,
          hunger: hunger,
          moodLabel: moodLabel,
        ),
      );
      final xpResult = xpResults[memberId];
      if (xpResult != null) {
        leveledUp = leveledUp || xpResult.leveledUp;
        highestLevel = math.max(highestLevel, xpResult.level);
      }
    }
    final finalState = <String>[
      if (emergencyReturn)
        'Retour d’urgence : le butin est calculé au temps écoulé, avec +5% de risque événement.',
      ...memberStateLabels,
    ].join(' ');
    reports.add(
      PtipoteMissionReport(
        id: 'report-${completedAt.microsecondsSinceEpoch}',
        figurineName: mission.figurineName,
        biomeLabel: biome.label,
        durationLabel: duration.label,
        intensityLabel: intensity.label,
        rewards: rewards,
        incidentLabel: incident,
        xpGain: mission.xpGain,
        leveledUp: leveledUp,
        levelAfter: highestLevel,
        vitalityRemaining: lowestVitality,
        hungerRemaining: lowestHunger,
        moodLabel: 'Équipe',
        finalStateLabel: finalState,
        baseRiskPercent: mission.baseRiskPercent,
        securityAtLaunch: mission.securityAtLaunch,
        securityReduction: mission.securityReduction,
        realRiskPercent: realRisk,
        completedAt: completedAt,
        inventoryFull: inventoryResult.hasPending,
      ),
    );
    mission.status = ForageMissionStatus.completed;
  }

  int _towerTicksForPlan(TowerMissionPlan plan, int vitality) {
    if (plan == TowerMissionPlan.until25Vitality) {
      final spendable = math.max(0, vitality - 25);
      return spendable ~/ math.max(1, securityTowerConfig.vitalityCostPerTick);
    }
    final hours = switch (plan) {
      TowerMissionPlan.oneHour => 1,
      TowerMissionPlan.twoHours => 2,
      TowerMissionPlan.fourHours => 4,
      TowerMissionPlan.eightHours => 8,
      TowerMissionPlan.threeHours => 3,
      TowerMissionPlan.sixHours => 6,
      TowerMissionPlan.tenHours => 10,
      TowerMissionPlan.until25Vitality => 0,
    };
    final minutes = hours * 60;
    return math.max(1, minutes ~/ math.max(1, securityTowerConfig.tickMinutes));
  }

  Duration _towerDurationForTicks(int ticks) {
    final theoreticalMinutes = ticks * securityTowerConfig.tickMinutes;
    final realMinutes = math.max(
        1, (theoreticalMinutes / lisiereForageConfig.forageTimeScale).round());
    return Duration(minutes: realMinutes);
  }

  void _resolveTowerMission(TowerMission mission, {bool early = false}) {
    final elapsedRatio = early
        ? (DateTime.now().difference(mission.startTime).inSeconds /
            math.max(
                1, mission.endTime.difference(mission.startTime).inSeconds))
        : 1.0;
    final ratio = elapsedRatio.clamp(0.05, 1.0);
    final vitalityCost = math.max(1, (mission.vitalityCost * ratio).round());
    final securityGain = math.max(1, (mission.securityGain * ratio).round());
    final currentVitality =
        vitalityOverrides[mission.figurineId] ?? ptipoteStatsConfig.maxVitality;
    final nextVitality = math.max(0, currentVitality - vitalityCost);
    var localGain = 0;
    vitalityOverrides[mission.figurineId] = nextVitality;
    if (mission.patrolBiome == null) {
      refugeSafety = math.min(
        securityTowerConfig.maxSecurity,
        refugeSafety + securityGain,
      );
    } else {
      final state = biomeSecurity[mission.patrolBiome]!;
      localGain = math.max(
        1,
        (towerOperationsConfig.localSecurityMaximum *
                _towerHoursForPlan(mission.plan) /
                towerOperationsConfig.localSecurityHoursForFullPatrol *
                ratio)
            .round(),
      );
      state.localSecurity = math.min(
        towerOperationsConfig.localSecurityMaximum,
        state.localSecurity + localGain,
      );
      state.lastPatrolAt = DateTime.now();
      state.lastDecayAt = state.lastPatrolAt;
    }
    if (mission.sleepAfter ||
        nextVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      manualRestingIds.add(mission.figurineId);
    }
    mission.status = TowerMissionStatus.completed;
    reports.add(
      PtipoteMissionReport.system(
        message: early
            ? '${mission.figurineName} revient de la Tour plus tôt : -$vitalityCost Vitalité.'
            : mission.patrolBiome == null
                ? '${mission.figurineName} termine sa surveillance : +$securityGain sécurité camp, -$vitalityCost Vitalité.'
                : '${mission.figurineName} termine sa ronde : +$localGain sécurité locale, -$vitalityCost Vitalité.',
      ),
    );
  }

  int _towerHoursForPlan(TowerMissionPlan plan) => switch (plan) {
        TowerMissionPlan.oneHour => 1,
        TowerMissionPlan.twoHours => 2,
        TowerMissionPlan.fourHours => 4,
        TowerMissionPlan.eightHours => 8,
        TowerMissionPlan.threeHours => 3,
        TowerMissionPlan.sixHours => 6,
        TowerMissionPlan.tenHours => 10,
        TowerMissionPlan.until25Vitality => 1,
      };

  String _moodLabelForValues({
    required int hunger,
    required int rest,
    required String figurineId,
  }) {
    var needs = 0;
    if (hunger > ptipoteStatsConfig.happyHungerThreshold) needs += 1;
    final restState = ptipoteStatsConfig.restStateFor(rest);
    if (restState == PtipoteRestState.wellRested ||
        restState == PtipoteRestState.rested) {
      needs += 1;
    }
    final cuddleAt = lastCuddleAt[figurineId];
    if (cuddleAt != null &&
        DateTime.now().difference(cuddleAt) <=
            Duration(minutes: ptipoteStatsConfig.cuddleCareDurationMinutes)) {
      needs += 1;
    }
    if (needs >= ptipoteStatsConfig.happyNeedsRequired) return 'Heureux';
    if (needs >= ptipoteStatsConfig.okayNeedsRequired) return 'Bien';
    return 'Mal';
  }

  String _finalMissionStateLabel({
    required String figurineName,
    required int vitality,
    required int hunger,
    required String moodLabel,
  }) {
    final notes = <String>[];
    if (vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      notes
          .add('$figurineName est revenu très fatigué et est allé se reposer.');
    } else if (vitality <= ptipoteStatsConfig.happyVitalityThreshold) {
      notes.add('$figurineName est revenu fatigué.');
    } else {
      notes.add('$figurineName est revenu en forme.');
    }
    if (hunger <= ptipoteStatsConfig.happyHungerThreshold) {
      notes.add('$figurineName aimerait manger.');
    }
    notes.add('État de bonheur : $moodLabel.');
    return notes.join(' ');
  }

  PtipoteXpGainResult addMissionXp(String figurineId, int xpGain) {
    var level = levelOverrides[figurineId] ?? 1;
    var xp = xpOverrides[figurineId] ?? 0;
    xp += math.max(0, xpGain);
    var leveledUp = false;

    while (xp >= ptipoteStatsConfig.xpRequiredForNextLevel(level)) {
      xp -= ptipoteStatsConfig.xpRequiredForNextLevel(level);
      level += 1;
      leveledUp = true;
    }

    levelOverrides[figurineId] = level;
    xpOverrides[figurineId] = xp;
    unawaited(saveRuntimeToFirebase());
    return PtipoteXpGainResult(
      xp: xp,
      level: level,
      leveledUp: leveledUp,
    );
  }

  Future<Map<String, dynamic>?> loadCampHeartFromFirebase() async {
    final user = await _currentUser();
    if (user == null) return null;
    Map<String, dynamic>? campHeart;
    await _runFirebaseSync('Chargement Cœur du Camp', () async {
      final snapshot = await _zone0Doc(user.uid).get();
      campHeart = snapshot.data()?['campHeart'] as Map<String, dynamic>?;
    });
    return campHeart;
  }

  Future<void> saveCampHeartToFirebase(Map<String, dynamic> campHeart) async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde Cœur du Camp', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'campHeart': campHeart,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveInventoryToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde inventaire', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'inventory': inventory
              .map(
                (stack) => <String, dynamic>{
                  'resource': stack.resource,
                  'amount': stack.amount,
                },
              )
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveRuntimeToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde missions/vitalité', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'vitalityOverrides': vitalityOverrides,
          'hungerOverrides': hungerOverrides,
          'restOverrides': restOverrides,
          'manualRestingIds': manualRestingIds.toList(),
          'autoPreferenceOverrides': autoPreferenceOverrides.map(
            (key, value) => MapEntry(key, value.name),
          ),
          'towerAssignedIds': towerAssignedIds.toList(),
          'towerMissions':
              towerMissions.map((mission) => mission.toFirebase()).toList(),
          'workshopOrder': null,
          'workshopOrders':
              workshopOrders.map((order) => order.toFirebase()).toList(),
          'market': <String, dynamic>{
            'stock': marketStock
                .map((item) => <String, dynamic>{
                      'resource': item.resource,
                      'amount': item.amount
                    })
                .toList(),
            'requests':
                marketRequests.map((item) => item.toFirebase()).toList(),
            'nextSaleAt': marketNextSaleAt == null
                ? null
                : Timestamp.fromDate(marketNextSaleAt!),
            'lastWorkTickAt': marketLastWorkTickAt == null
                ? null
                : Timestamp.fromDate(marketLastWorkTickAt!),
            'assignedPtipoteId': marketAssignedPtipoteId,
            'assignedPtipoteName': marketAssignedPtipoteName,
            'valueRemainder': marketValueRemainder,
            'bioBatteriesEarned': marketBioBatteriesEarned,
            'merchantAvailableUntil': merchantAvailableUntil == null
                ? null
                : Timestamp.fromDate(merchantAvailableUntil!),
            'merchantOffers': merchantOffers
                .map((item) => <String, dynamic>{
                      'planName': item.planName,
                      'price': item.price,
                      'purchased': item.purchased
                    })
                .toList(),
          },
          'biomeSecurity': biomeSecurity
              .map((key, value) => MapEntry(key.name, value.toFirebase())),
          'explorationMissions':
              explorationMissions.map((item) => item.toFirebase()).toList(),
          'campSecurity': refugeSafety,
          'lastManualTowerRechargeAt': lastManualTowerRechargeAt == null
              ? null
              : Timestamp.fromDate(lastManualTowerRechargeAt!),
          'kernel': <String, dynamic>{
            'currentPopulation': currentPopulation,
            'bioBatteries': bioBatteries,
            'energyUnits': energyUnits,
            'campWellbeing': campWellbeing,
            'mealsPrepared': mealsPrepared,
            'plaineMissionsCompleted': plaineMissionsCompleted,
            'trustLevel': kernelTrustLevel,
            'trustXp': kernelTrustXp,
            'axisLevels': kernelAxisLevels.map(
              (key, value) => MapEntry(key.name, value),
            ),
            'axisXp': kernelAxisXp.map(
              (key, value) => MapEntry(key.name, value),
            ),
            'eventCounts': kernelEventCounts.map(
              (key, value) => MapEntry(key.name, value),
            ),
            'discoveredPlanIds': discoveredKernelPlanIds.toList(),
            'readyPlanIds': readyKernelPlanIds.toList(),
            'activePlanIds': activeKernelPlanIds.toList(),
            'progressHistory': kernelProgressHistory
                .take(50)
                .map((entry) => entry.toFirebase())
                .toList(),
            'completedMissionIds': completedKernelMissionIds.toList(),
            'populationRewardsGranted': kernelPopulationRewardsGranted,
          },
          'campGenerator': <String, dynamic>{
            'organic': generatorOrganic,
            'mineral': generatorMineral,
            'totalProduced': generatorTotalProduced,
            'cycleStartedAt': generatorCycleStartedAt == null
                ? null
                : Timestamp.fromDate(generatorCycleStartedAt!),
          },
          'recycler': <String, dynamic>{
            'level': recyclerLevel,
            'wasteTank': recyclerWasteTank,
            'outputOrganic': recyclerOutputOrganic,
            'outputMineral': recyclerOutputMineral,
            'pendingWaste': pendingWaste,
            'cycleStartedAt': recyclerCycleStartedAt == null
                ? null
                : Timestamp.fromDate(recyclerCycleStartedAt!),
            'lastWasteGenerationAt': lastWasteGenerationAt == null
                ? null
                : Timestamp.fromDate(lastWasteGenerationAt!),
          },
          'lastSimulationAt': lastSimulationAt == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(lastSimulationAt!),
          'lastCuddleAt': lastCuddleAt.map(
            (key, value) => MapEntry(key, Timestamp.fromDate(value)),
          ),
          'missions': missions.map((mission) => mission.toFirebase()).toList(),
          'reports': reports.map((report) => report.toFirebase()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveBuildingsToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde bâtiments', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'buildings': <String, dynamic>{
            'fablab': <String, dynamic>{
              'buildingId': 'fablab',
              'buildingType': 'production',
              'displayName': 'Fablab',
              'state': isFablabBuilt ? 'built' : 'constructible',
              'currentLevel': fablabLevel,
              'maxLevel': fablabConfig.fablabMaxLevel,
              'requiredCampHeartLevel': 0,
              'stockCapacityBonusPerLevel':
                  fablabConfig.stockCapacityBonusPerFablabLevel,
              'isVisible': true,
            },
            'securityTower': <String, dynamic>{
              'buildingId': 'securityTower',
              'buildingType': 'security',
              'displayName': 'Tour de sécurité',
              'state': isSecurityTowerBuilt ? 'built' : 'constructible',
              'currentLevel': securityTowerLevel,
              'maxLevel': 3,
              'requiredCampHeartLevel':
                  securityTowerConfig.requiredCampHeartLevel,
              'isVisible': true,
            },
            'market': <String, dynamic>{
              'buildingId': 'market',
              'buildingType': 'commerce',
              'displayName': 'Marché',
              'state': isMarketBuilt ? 'built' : 'constructible',
              'currentLevel': marketLevel,
              'maxLevel': 5,
              'requiredCampHeartLevel': marketConfig.requiredCampHeartLevel,
              'isVisible': true,
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> persistFigurineProgress({
    required String figurineId,
    required int xp,
    required int level,
  }) async {
    final user = await _currentUser();
    if (user == null) return;
    final ref = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('figurines')
        .doc(figurineId);
    final snapshot = await ref.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final fields = Map<String, dynamic>.from(
      data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    fields['x'] = '$xp';
    fields['xp'] = '$xp';
    fields['l'] = '$level';
    fields['level'] = '$level';

    await _runFirebaseSync('Sauvegarde XP P’TIPOTE', () {
      return ref.set(
        <String, dynamic>{
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  DocumentReference<Map<String, dynamic>> _zone0Doc(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('game')
        .doc('zone0');
  }

  int _readInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<User?> _currentUser() async {
    final current = _auth.currentUser;
    if (current != null) return current;
    try {
      return _auth
          .authStateChanges()
          .where((user) => user != null)
          .cast<User>()
          .first
          .timeout(const Duration(seconds: 4));
    } on Object {
      lastFirebaseError = 'Utilisateur Firebase non prêt.';
      firebaseSyncLabel = 'Synchro impossible';
      notifyListeners();
      return null;
    }
  }

  Future<void> _runFirebaseSync(
    String label,
    Future<void> Function() action,
  ) async {
    isFirebaseSyncing = true;
    firebaseSyncLabel = label;
    lastFirebaseError = null;
    notifyListeners();
    try {
      await action();
      lastFirebaseSyncAt = DateTime.now();
      firebaseSyncLabel = 'Synchronisé';
    } on FirebaseException catch (error) {
      lastFirebaseError = '${error.code}: ${error.message ?? error.plugin}';
      firebaseSyncLabel = 'Erreur Firebase';
      debugPrint('Zone0 Firebase sync failed: $label: $lastFirebaseError');
    } on Object catch (error) {
      lastFirebaseError = '$error';
      firebaseSyncLabel = 'Erreur Firebase';
      debugPrint('Zone0 Firebase sync failed: $label: $error');
    } finally {
      isFirebaseSyncing = false;
      notifyListeners();
    }
  }
}

class PtipoteXpGainResult {
  const PtipoteXpGainResult({
    required this.xp,
    required this.level,
    required this.leveledUp,
  });

  final int xp;
  final int level;
  final bool leveledUp;
}

class Zone0InventoryStack {
  Zone0InventoryStack({required this.resource, required this.amount});

  final String resource;
  int amount;
}

class InventoryAddResult {
  const InventoryAddResult({required this.addedAny, required this.pending});

  final bool addedAny;
  final Map<String, int> pending;

  bool get hasPending => pending.isNotEmpty;
}

class Zone0ActionResult {
  const Zone0ActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class KernelProgressHistoryEntry {
  const KernelProgressHistoryEntry({
    required this.occurredAt,
    required this.eventType,
    required this.trustXp,
    required this.breederXp,
    required this.builderXp,
    required this.restorerXp,
  });

  factory KernelProgressHistoryEntry.fromFirebase(Map<dynamic, dynamic> data) {
    return KernelProgressHistoryEntry(
      occurredAt: Zone0GameState.instance._readDate(data['occurredAt']) ??
          DateTime.now(),
      eventType: ForageMission._enumByName(
        KernelProgressEventType.values,
        '${data['eventType'] ?? ''}',
        KernelProgressEventType.craftCompleted,
      ),
      trustXp: Zone0GameState.instance._readInt(data['trustXp']),
      breederXp: Zone0GameState.instance._readInt(data['breederXp']),
      builderXp: Zone0GameState.instance._readInt(data['builderXp']),
      restorerXp: Zone0GameState.instance._readInt(data['restorerXp']),
    );
  }

  final DateTime occurredAt;
  final KernelProgressEventType eventType;
  final int trustXp;
  final int breederXp;
  final int builderXp;
  final int restorerXp;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'occurredAt': Timestamp.fromDate(occurredAt),
        'eventType': eventType.name,
        'trustXp': trustXp,
        'breederXp': breederXp,
        'builderXp': builderXp,
        'restorerXp': restorerXp,
      };
}

enum ForageMissionStatus { active, completed }

enum TowerMissionStatus { active, completed }

enum WorkshopOrderStatus { active, completed, cancelled }

enum MarketRequestStatus { noted, ready, waitingCustomer, completed, cancelled }

class MarketCustomerRequest {
  MarketCustomerRequest(
      {required this.id,
      required this.requestedItemId,
      required this.requestedQuantity,
      required this.rewardBioBattery,
      required this.rewardWellbeing,
      required this.createdAt,
      required this.customerReturnTime,
      required this.status});

  factory MarketCustomerRequest.fromFirebase(Map<dynamic, dynamic> data) =>
      MarketCustomerRequest(
        id: '${data['id'] ?? ''}',
        requestedItemId: '${data['requestedItemId'] ?? ''}',
        requestedQuantity:
            Zone0GameState.instance._readInt(data['requestedQuantity']),
        rewardBioBattery:
            Zone0GameState.instance._readInt(data['rewardBioBattery']),
        rewardWellbeing:
            Zone0GameState.instance._readInt(data['rewardWellbeing']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        customerReturnTime:
            Zone0GameState.instance._readDate(data['customerReturnTime']) ??
                DateTime.now(),
        status: ForageMission._enumByName(MarketRequestStatus.values,
            '${data['status'] ?? ''}', MarketRequestStatus.noted),
      );

  final String id;
  final String requestedItemId;
  final int requestedQuantity;
  final int rewardBioBattery;
  final int rewardWellbeing;
  final DateTime createdAt;
  DateTime customerReturnTime;
  MarketRequestStatus status;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'requestedItemId': requestedItemId,
        'requestedQuantity': requestedQuantity,
        'rewardBioBattery': rewardBioBattery,
        'rewardWellbeing': rewardWellbeing,
        'createdAt': Timestamp.fromDate(createdAt),
        'customerReturnTime': Timestamp.fromDate(customerReturnTime),
        'status': status.name,
      };
}

class WorkshopCraftOrder {
  WorkshopCraftOrder({
    required this.id,
    required this.recipeId,
    this.area = WorkshopOrderArea.workshop,
    required this.requestedQuantity,
    required this.completedQuantity,
    required this.assignedPtipoteId,
    required this.assignedPtipoteName,
    required this.startTime,
    required this.nextCompletionTime,
    required this.unitDurationSeconds,
    required this.reservedResources,
    this.status = WorkshopOrderStatus.active,
  });

  factory WorkshopCraftOrder.fromFirebase(Map<dynamic, dynamic> data) {
    return WorkshopCraftOrder(
      id: '${data['id'] ?? ''}',
      recipeId: '${data['recipeId'] ?? ''}',
      area: ForageMission._enumByName(
        WorkshopOrderArea.values,
        '${data['area'] ?? ''}',
        WorkshopOrderArea.workshop,
      ),
      requestedQuantity:
          Zone0GameState.instance._readInt(data['requestedQuantity']),
      completedQuantity:
          Zone0GameState.instance._readInt(data['completedQuantity']),
      assignedPtipoteId: data['assignedPtipoteId'] as String?,
      assignedPtipoteName: data['assignedPtipoteName'] as String?,
      startTime: Zone0GameState.instance._readDate(data['startTime']) ??
          DateTime.now(),
      nextCompletionTime:
          Zone0GameState.instance._readDate(data['nextCompletionTime']) ??
              DateTime.now(),
      unitDurationSeconds: math.max(
          1,
          Zone0GameState.instance
              ._readInt(data['unitDurationSeconds'], fallback: 60)),
      reservedResources: Map<String, int>.fromEntries(
        (data['reservedResources'] as Map? ?? const <String, dynamic>{})
            .entries
            .map(
              (entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value)),
            ),
      ),
      status: ForageMission._enumByName(
        WorkshopOrderStatus.values,
        '${data['status'] ?? ''}',
        WorkshopOrderStatus.active,
      ),
    );
  }

  final String id;
  final String recipeId;
  final WorkshopOrderArea area;
  final int requestedQuantity;
  int completedQuantity;
  final String? assignedPtipoteId;
  final String? assignedPtipoteName;
  final DateTime startTime;
  DateTime nextCompletionTime;
  final int unitDurationSeconds;
  final Map<String, int> reservedResources;
  WorkshopOrderStatus status;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'recipeId': recipeId,
        'area': area.name,
        'requestedQuantity': requestedQuantity,
        'completedQuantity': completedQuantity,
        'assignedPtipoteId': assignedPtipoteId,
        'assignedPtipoteName': assignedPtipoteName,
        'startTime': Timestamp.fromDate(startTime),
        'nextCompletionTime': Timestamp.fromDate(nextCompletionTime),
        'unitDurationSeconds': unitDurationSeconds,
        'reservedResources': reservedResources,
        'status': status.name,
      };
}

enum WorkshopOrderArea { workshop, kitchen }

enum TowerMissionPlan {
  oneHour,
  twoHours,
  fourHours,
  eightHours,
  threeHours,
  sixHours,
  tenHours,
  until25Vitality,
}

enum BiomeDiscoveryStatus { discovered, exploring, unlocked }

class BiomeSecurityState {
  BiomeSecurityState({
    required this.biome,
    required this.status,
    this.localSecurity = 0,
    this.explorationProgress = 0,
    this.lastPatrolAt,
    this.lastMissionAt,
    this.lastDecayAt,
  });

  factory BiomeSecurityState.initial(ForageBiome biome) => BiomeSecurityState(
        biome: biome,
        status: biome == ForageBiome.plaineRiche
            ? BiomeDiscoveryStatus.unlocked
            : BiomeDiscoveryStatus.discovered,
      );

  factory BiomeSecurityState.fromFirebase(
          ForageBiome biome, Map<dynamic, dynamic> data) =>
      BiomeSecurityState(
        biome: biome,
        status: ForageMission._enumByName(BiomeDiscoveryStatus.values,
            '${data['status'] ?? ''}', BiomeDiscoveryStatus.discovered),
        // V1 stored local security for exploration and forage missions too.
        // Those values were not actual completed patrols, so reset them once.
        localSecurity: ForageMission._readStaticInt(data['securitySchema']) >= 2
            ? ForageMission._readStaticInt(data['localSecurity'])
            : 0,
        explorationProgress:
            ForageMission._readStaticInt(data['explorationProgress']),
        lastPatrolAt: ForageMission._readDate(data['lastPatrolAt']),
        lastMissionAt: ForageMission._readDate(data['lastMissionAt']),
        lastDecayAt: ForageMission._readDate(data['lastDecayAt']),
      );

  final ForageBiome biome;
  BiomeDiscoveryStatus status;
  int localSecurity;
  int explorationProgress;
  DateTime? lastPatrolAt;
  DateTime? lastMissionAt;
  DateTime? lastDecayAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'securitySchema': 2,
        'status': status.name,
        'localSecurity': localSecurity,
        'explorationProgress': explorationProgress,
        'lastPatrolAt':
            lastPatrolAt == null ? null : Timestamp.fromDate(lastPatrolAt!),
        'lastMissionAt':
            lastMissionAt == null ? null : Timestamp.fromDate(lastMissionAt!),
        'lastDecayAt':
            lastDecayAt == null ? null : Timestamp.fromDate(lastDecayAt!),
      };
}

class BiomeExplorationMission {
  BiomeExplorationMission(
      {required this.id,
      required this.biome,
      required this.memberIds,
      required this.memberNames,
      required this.endTime,
      required this.explorationProgressGain,
      DateTime? startTime})
      : startTime = startTime ?? DateTime.now();

  factory BiomeExplorationMission.fromFirebase(Map<dynamic, dynamic> data) =>
      BiomeExplorationMission(
        id: '${data['id'] ?? ''}',
        biome: ForageMission._enumByName(ForageBiome.values,
            '${data['biome'] ?? ''}', ForageBiome.plaineRiche),
        memberIds: ForageMission._readStringList(data['memberIds']),
        memberNames: ForageMission._readStringList(data['memberNames']),
        startTime: ForageMission._readDate(data['startTime']) ?? DateTime.now(),
        endTime: ForageMission._readDate(data['endTime']) ?? DateTime.now(),
        explorationProgressGain:
            ForageMission._readStaticInt(data['explorationProgressGain']),
      )..completedAt = ForageMission._readDate(data['completedAt']);

  final String id;
  final ForageBiome biome;
  final List<String> memberIds;
  final List<String> memberNames;
  final DateTime startTime;
  final DateTime endTime;
  final int explorationProgressGain;
  DateTime? completedAt;
  bool get isActive => completedAt == null;
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'biome': biome.name,
        'memberIds': memberIds,
        'memberNames': memberNames,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'explorationProgressGain': explorationProgressGain,
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

enum WeatherPreparationType { craft, own, provide }

class WeatherAlert {
  WeatherAlert(
      {required this.type,
      required this.startsAt,
      required this.endsAt,
      this.preparationCompleted = false});
  final TowerWeatherType type;
  final DateTime startsAt;
  final DateTime endsAt;
  bool preparationCompleted;
}

class MerchantOffer {
  MerchantOffer(
      {required this.planName, required this.price, this.purchased = false});
  final String planName;
  final int price;
  bool purchased;
}

class TowerMission {
  TowerMission({
    required this.id,
    required this.figurineId,
    required this.figurineName,
    required this.plan,
    required this.startTime,
    required this.endTime,
    required this.vitalityCost,
    required this.securityGain,
    required this.sleepAfter,
    this.patrolBiome,
  });

  factory TowerMission.fromFirebase(Map<dynamic, dynamic> data) {
    final mission = TowerMission(
      id: '${data['id'] ?? 'tower-${DateTime.now().microsecondsSinceEpoch}'}',
      figurineId: '${data['figurineId'] ?? ''}',
      figurineName: '${data['figurineName'] ?? 'P’TIPOTE'}',
      plan: ForageMission._enumByName(
        TowerMissionPlan.values,
        '${data['plan'] ?? ''}',
        TowerMissionPlan.oneHour,
      ),
      startTime: ForageMission._readDate(data['startTime']) ?? DateTime.now(),
      endTime: ForageMission._readDate(data['endTime']) ?? DateTime.now(),
      vitalityCost: ForageMission._readStaticInt(data['vitalityCost']),
      securityGain: ForageMission._readStaticInt(data['securityGain']),
      sleepAfter: data['sleepAfter'] == true,
      patrolBiome: data['patrolBiome'] == null
          ? null
          : ForageMission._enumByName(ForageBiome.values,
              '${data['patrolBiome']}', ForageBiome.plaineRiche),
    );
    mission.status = ForageMission._enumByName(
      TowerMissionStatus.values,
      '${data['status'] ?? ''}',
      TowerMissionStatus.active,
    );
    return mission;
  }

  final String id;
  final String figurineId;
  final String figurineName;
  final TowerMissionPlan plan;
  final DateTime startTime;
  final DateTime endTime;
  final int vitalityCost;
  final int securityGain;
  final bool sleepAfter;
  final ForageBiome? patrolBiome;
  TowerMissionStatus status = TowerMissionStatus.active;

  Map<String, dynamic> toFirebase() {
    return <String, dynamic>{
      'id': id,
      'figurineId': figurineId,
      'figurineName': figurineName,
      'plan': plan.name,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'vitalityCost': vitalityCost,
      'securityGain': securityGain,
      'sleepAfter': sleepAfter,
      'patrolBiome': patrolBiome?.name,
      'status': status.name,
    };
  }
}

class ForageMission {
  ForageMission({
    required this.id,
    required this.figurineId,
    required this.figurineName,
    required this.memberIds,
    required this.memberNames,
    required this.biome,
    required this.duration,
    required this.intensity,
    required this.startTime,
    required this.endTime,
    required this.expectedRewards,
    required this.vitalityCost,
    required this.vitalityCostByMember,
    required this.riskPercent,
    required this.riskLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.xpGain,
    required this.xpGainByMember,
    required this.autoPreferenceByMember,
  });

  factory ForageMission.fromFirebase(Map<dynamic, dynamic> data) {
    final biome = _enumByName(
      ForageBiome.values,
      '${data['biome'] ?? ''}',
      ForageBiome.colline,
    );
    final duration = _enumByName(
      ForageDuration.values,
      '${data['duration'] ?? ''}',
      ForageDuration.oneHour,
    );
    final intensity = _enumByName(
      ForageIntensity.values,
      '${data['intensity'] ?? ''}',
      ForageIntensity.normal,
    );
    final mission = ForageMission(
      id: '${data['id'] ?? 'mission-${DateTime.now().microsecondsSinceEpoch}'}',
      figurineId: '${data['figurineId'] ?? ''}',
      figurineName: '${data['figurineName'] ?? 'P’TIPOTE'}',
      memberIds: _readStringList(data['memberIds']).isEmpty
          ? <String>['${data['figurineId'] ?? ''}']
          : _readStringList(data['memberIds']),
      memberNames: _readStringList(data['memberNames']).isEmpty
          ? <String>['${data['figurineName'] ?? 'P’TIPOTE'}']
          : _readStringList(data['memberNames']),
      biome: biome,
      duration: duration,
      intensity: intensity,
      startTime: _readDate(data['startTime']) ?? DateTime.now(),
      endTime: _readDate(data['endTime']) ?? DateTime.now(),
      expectedRewards: _readIntMap(data['expectedRewards']),
      vitalityCost: _readStaticInt(data['vitalityCost']),
      vitalityCostByMember: _readIntMap(data['vitalityCostByMember']),
      riskPercent: _readStaticInt(data['riskPercent']),
      riskLabel: '${data['riskLabel'] ?? 'normal'}',
      baseRiskPercent: _readStaticInt(data['baseRiskPercent']),
      securityAtLaunch: _readStaticInt(data['securityAtLaunch']),
      securityReduction: _readStaticInt(data['securityReduction']),
      xpGain: _readStaticInt(data['xpGain']),
      xpGainByMember: _readIntMap(data['xpGainByMember']),
      autoPreferenceByMember:
          _readAutoPreferenceMap(data['autoPreferenceByMember']),
    );
    mission.status = _enumByName(
      ForageMissionStatus.values,
      '${data['status'] ?? ''}',
      ForageMissionStatus.active,
    );
    return mission;
  }

  final String id;
  final String figurineId;
  final String figurineName;
  final List<String> memberIds;
  final List<String> memberNames;
  final ForageBiome biome;
  final ForageDuration duration;
  final ForageIntensity intensity;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, int> expectedRewards;
  final int vitalityCost;
  final Map<String, int> vitalityCostByMember;
  final int riskPercent;
  final String riskLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final int xpGain;
  final Map<String, int> xpGainByMember;
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceByMember;
  ForageMissionStatus status = ForageMissionStatus.active;

  Map<String, dynamic> toFirebase() {
    return <String, dynamic>{
      'id': id,
      'figurineId': figurineId,
      'figurineName': figurineName,
      'memberIds': memberIds,
      'memberNames': memberNames,
      'biome': biome.name,
      'duration': duration.name,
      'intensity': intensity.name,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'expectedRewards': expectedRewards,
      'vitalityCost': vitalityCost,
      'vitalityCostByMember': vitalityCostByMember,
      'riskPercent': riskPercent,
      'riskLabel': riskLabel,
      'baseRiskPercent': baseRiskPercent,
      'securityAtLaunch': securityAtLaunch,
      'securityReduction': securityReduction,
      'xpGain': xpGain,
      'xpGainByMember': xpGainByMember,
      'autoPreferenceByMember': autoPreferenceByMember.map(
        (key, value) => MapEntry(key, value.name),
      ),
      'status': status.name,
    };
  }

  static Map<String, PtipoteAutoAssignmentPreference> _readAutoPreferenceMap(
    Object? data,
  ) {
    if (data is! Map) return <String, PtipoteAutoAssignmentPreference>{};
    return data.map((key, value) {
      return MapEntry(
        '$key',
        _enumByName(
          PtipoteAutoAssignmentPreference.values,
          '$value',
          PtipoteAutoAssignmentPreference.home,
        ),
      );
    });
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, int> _readIntMap(Object? value) {
    if (value is! Map) return const <String, int>{};
    return value.map(
      (key, amount) => MapEntry('$key', _readStaticInt(amount)),
    )..removeWhere((_, amount) => amount <= 0);
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static int _readStaticInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class PtipoteMissionReport {
  PtipoteMissionReport({
    required this.id,
    required this.figurineName,
    required this.biomeLabel,
    required this.durationLabel,
    required this.intensityLabel,
    required this.rewards,
    required this.incidentLabel,
    required this.xpGain,
    required this.leveledUp,
    required this.levelAfter,
    required this.vitalityRemaining,
    required this.hungerRemaining,
    required this.moodLabel,
    required this.finalStateLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.realRiskPercent,
    required this.completedAt,
    required this.inventoryFull,
    this.read = false,
  });

  factory PtipoteMissionReport.fromFirebase(Map<dynamic, dynamic> data) {
    return PtipoteMissionReport(
      id: '${data['id'] ?? 'report-${DateTime.now().microsecondsSinceEpoch}'}',
      figurineName: '${data['figurineName'] ?? 'P’TIPOTE'}',
      biomeLabel: '${data['biomeLabel'] ?? 'Zone 0'}',
      durationLabel: '${data['durationLabel'] ?? '-'}',
      intensityLabel: '${data['intensityLabel'] ?? '-'}',
      rewards: ForageMission._readIntMap(data['rewards']),
      incidentLabel: '${data['incidentLabel'] ?? 'aucun'}',
      xpGain: ForageMission._readStaticInt(data['xpGain']),
      leveledUp: data['leveledUp'] == true,
      levelAfter: ForageMission._readStaticInt(data['levelAfter']),
      vitalityRemaining:
          ForageMission._readStaticInt(data['vitalityRemaining']),
      hungerRemaining: ForageMission._readStaticInt(data['hungerRemaining']),
      moodLabel: '${data['moodLabel'] ?? 'Bien'}',
      finalStateLabel: '${data['finalStateLabel'] ?? ''}',
      baseRiskPercent: ForageMission._readStaticInt(data['baseRiskPercent']),
      securityAtLaunch: ForageMission._readStaticInt(data['securityAtLaunch']),
      securityReduction:
          ForageMission._readStaticInt(data['securityReduction']),
      realRiskPercent: ForageMission._readStaticInt(data['realRiskPercent']),
      completedAt:
          ForageMission._readDate(data['completedAt']) ?? DateTime.now(),
      inventoryFull: data['inventoryFull'] == true,
      read: data['read'] == true,
    );
  }

  factory PtipoteMissionReport.system({required String message}) {
    final now = DateTime.now();
    return PtipoteMissionReport(
      id: 'system-${now.microsecondsSinceEpoch}',
      figurineName: 'Refuge',
      biomeLabel: 'Zone 0',
      durationLabel: 'instantané',
      intensityLabel: 'système',
      rewards: const <String, int>{},
      incidentLabel: message,
      xpGain: 0,
      leveledUp: false,
      levelAfter: 0,
      vitalityRemaining: 0,
      hungerRemaining: 0,
      moodLabel: 'Bien',
      finalStateLabel: message,
      baseRiskPercent: 0,
      securityAtLaunch: 0,
      securityReduction: 0,
      realRiskPercent: 0,
      completedAt: now,
      inventoryFull: false,
    );
  }

  final String id;
  final String figurineName;
  final String biomeLabel;
  final String durationLabel;
  final String intensityLabel;
  final Map<String, int> rewards;
  final String incidentLabel;
  final int xpGain;
  final bool leveledUp;
  final int levelAfter;
  final int vitalityRemaining;
  final int hungerRemaining;
  final String moodLabel;
  final String finalStateLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final int realRiskPercent;
  final DateTime completedAt;
  final bool inventoryFull;
  bool read;

  Map<String, dynamic> toFirebase() {
    return <String, dynamic>{
      'id': id,
      'figurineName': figurineName,
      'biomeLabel': biomeLabel,
      'durationLabel': durationLabel,
      'intensityLabel': intensityLabel,
      'rewards': rewards,
      'incidentLabel': incidentLabel,
      'xpGain': xpGain,
      'leveledUp': leveledUp,
      'levelAfter': levelAfter,
      'vitalityRemaining': vitalityRemaining,
      'hungerRemaining': hungerRemaining,
      'moodLabel': moodLabel,
      'finalStateLabel': finalStateLabel,
      'baseRiskPercent': baseRiskPercent,
      'securityAtLaunch': securityAtLaunch,
      'securityReduction': securityReduction,
      'realRiskPercent': realRiskPercent,
      'completedAt': Timestamp.fromDate(completedAt),
      'inventoryFull': inventoryFull,
      'read': read,
    };
  }
}
