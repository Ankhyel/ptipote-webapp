import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/notification_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'building_construction_config.dart';
import 'camp_generator_config.dart';
import 'housing_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'remote_game_config_service.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'waste_recycler_config.dart';
import 'workshop_config.dart';

/// Keeps player-facing messages in the building that owns the activity.
/// Older saved reports fall back to the P'TIPOTE/PTIBUG mailbox.
enum Zone0MessageMailbox { companions, kernel, fablab }

class Zone0GameState extends ChangeNotifier {
  Zone0GameState._() {
    RemoteGameConfigService.instance.addListener(_onRemoteConfigChanged);
  }

  static final Zone0GameState instance = Zone0GameState._();
  final math.Random _random = math.Random();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _onRemoteConfigChanged() {
    _consumeManualWeatherTrigger();
    notifyListeners();
  }

  final Map<String, int> vitalityOverrides = <String, int>{};
  final Map<String, int> hungerOverrides = <String, int>{};
  final Map<String, int> restOverrides = <String, int>{};
  // A P'TIPOTE earns the rest reward once per recovery cycle.
  final Set<String> wellRestedRewardedIds = <String>{};
  final Map<String, int> xpOverrides = <String, int>{};
  final Map<String, int> levelOverrides = <String, int>{};
  final Map<String, DateTime> lastCuddleAt = <String, DateTime>{};
  final Set<String> manualRestingIds = <String>{};
  // A P'TIPOTE can need rest even when every alcove is occupied. Keeping this
  // separately prevents an unavailable bed from granting alcove recovery.
  final Set<String> waitingForBedIds = <String>{};
  // P'TIPOTES admitted into the Maison. New scans remain eggs in the
  // Couveuse when the active alcove capacity is full.
  final Set<String> hatchedPtipoteIds = <String>{};
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<TowerMission> towerMissions = <TowerMission>[];
  final List<WorkshopCraftOrder> workshopOrders = <WorkshopCraftOrder>[];
  final List<PTibug> pTibugs = <PTibug>[];
  final List<PTibugTraitData> pTibugTraitData = <PTibugTraitData>[];
  final Set<PTibugModuleType> unlockedPTibugModules = <PTibugModuleType>{};
  final Set<PTibugSpecies> activePTibugPatterns = <PTibugSpecies>{};
  // The legacy P'TIBUG fields above remain loaded for existing accounts. The
  // collections below are the V1 scientific progression data.
  final Map<PTibugDataFamily, int> pTibugDataReserve = <PTibugDataFamily, int>{
    for (final family in PTibugDataFamily.values) family: 0,
  };
  final List<PTibugDataCell> pTibugDataCells = <PTibugDataCell>[];
  final Map<String, PTibugPatternProgress> pTibugPatternProgress =
      <String, PTibugPatternProgress>{};
  final List<PTibugModuleInstance> pTibugModuleInstances =
      <PTibugModuleInstance>[];
  final List<PTibugModuleCraftOrder> pTibugModuleCraftOrders =
      <PTibugModuleCraftOrder>[];
  final List<PTibugCapsule> pTibugCapsules = <PTibugCapsule>[];
  bool starterPTibugChoiceMade = false;
  final Map<String, ConstructionProject> constructionProjects =
      <String, ConstructionProject>{};
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
  String weatherScheduleDayKey = '';
  int weatherEventsToday = 0;
  DateTime? nextWeatherEligibleAt;
  final Set<String> processedManualWeatherTriggerIds = <String>{};
  final List<MerchantOffer> merchantOffers = <MerchantOffer>[];
  final Set<String> completedKernelMissionIds = <String>{};
  final Set<String> dismissedKernelMissionIds = <String>{};
  // A Kernel mission can remain active after its notification was consulted.
  // Keeping this separate prevents the building badge from staying permanent.
  final Set<String> viewedKernelMissionIds = <String>{};
  // Prevents the same available mission from creating several remote
  // notifications across application restarts.
  final Set<String> notifiedKernelMissionIds = <String>{};
  final Set<String> _kernelNotificationInFlightIds = <String>{};
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
  // Compatibility level. New code should read atelierLevel for stock and slots.
  int atelierLevel = 0;
  int cuisineLevel = 0;
  int houseLevel = 1;
  // Existing saves started with three drawn alcoves. Keep that capacity during
  // migration even though new House level 1 starts with two.
  int alcoveCapacity = 3;
  int housingUnits = 0;
  // Housing remains separate from the Camp Heart population capacity.
  int housingCapacity = 0;
  CommunityConstructionThanks? communityConstructionThanks;
  int plaineNurseryLevel = 0;
  PTibugCreationOrder? pTibugCreationOrder;
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
  DateTime? merchantNextArrivalAt;
  String merchantVisitsDayKey = '';
  int merchantVisitsToday = 0;
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

  bool get isFablabBuilt => atelierLevel >= fablabConfig.cuisineUnlockLevel;
  bool get isSecurityTowerBuilt => securityTowerLevel >= 1;
  bool get isMarketBuilt => marketLevel >= 1;
  bool get isPlaineNurseryBuilt => plaineNurseryLevel >= 1;

  bool get hasPendingStarterPTibugChoice =>
      isPlaineNurseryBuilt && !starterPTibugChoiceMade;
  bool isRecyclerUnlocked(int campHeartLevel) =>
      isFablabBuilt &&
      campHeartLevel >= wasteRecyclerConfig.recyclerUnlockCampHeartLevel;
  int get recyclerWasteRequired =>
      wasteRecyclerConfig.wasteRequired(recyclerLevel);
  int get recyclerTankCapacity =>
      wasteRecyclerConfig.tankCapacity(recyclerLevel);
  int get recyclerOutputAmount => recyclerOutputOrganic + recyclerOutputMineral;
  int get recyclerOutputCapacity =>
      wasteRecyclerConfig.outputCapacity(recyclerLevel);
  int get securityTowerSlots =>
      securityTowerConfig.slotsForLevel(securityTowerLevel);
  bool get hasActiveTowerMission => towerMissions.any(
        (mission) => mission.status == TowerMissionStatus.active,
      );

  int get securityWellbeingModifier =>
      towerOperationsConfig.wellbeingBandFor(refugeSafety).wellbeingModifier;

  int get unhousedPopulation =>
      math.max(0, currentPopulation - housingCapacity);

  int get housingWellbeingPenalty => math.min(
        housingConfig.maximumHousingWellbeingPenalty,
        unhousedPopulation * housingConfig.wellbeingPenaltyPerUnhousedResident,
      );

  int get communityThanksWellbeingBonus {
    final thanks = communityConstructionThanks;
    if (thanks == null || !thanks.isActive) return 0;
    return thanks.bonusValue;
  }

  int get displayedCampWellbeing => (campWellbeing +
          securityWellbeingModifier -
          housingWellbeingPenalty +
          communityThanksWellbeingBonus)
      .clamp(0, 100);

  bool get isMerchantAvailable =>
      merchantAvailableUntil != null &&
      DateTime.now().isBefore(merchantAvailableUntil!);

  int get merchantVisitsRemaining => math.max(
        0,
        towerOperationsConfig.merchantMaxVisitsPerDay - merchantVisitsToday,
      );

  Duration? get merchantNextArrivalIn => merchantNextArrivalAt == null
      ? null
      : merchantNextArrivalAt!.difference(DateTime.now());

  bool isBiomeUnlocked(ForageBiome biome) =>
      biomeSecurity[biome]?.status == BiomeDiscoveryStatus.unlocked;

  bool isBiomeExploring(ForageBiome biome) => explorationMissions.any(
        (mission) => mission.biome == biome && mission.isActive,
      );

  /// The exploration map expands from already discovered neighbouring biomes.
  /// Locked biomes never dilute the average before the player can reach them.
  List<ForageBiome> adjacentBiomesFor(ForageBiome biome) => switch (biome) {
        ForageBiome.plaineRiche => <ForageBiome>[
            ForageBiome.colline,
            ForageBiome.sousBois,
          ],
        ForageBiome.colline => <ForageBiome>[
            ForageBiome.plaineRiche,
            ForageBiome.bassinMineral,
          ],
        ForageBiome.sousBois => <ForageBiome>[
            ForageBiome.plaineRiche,
            ForageBiome.bassinMineral,
          ],
        ForageBiome.bassinMineral => <ForageBiome>[
            ForageBiome.colline,
            ForageBiome.sousBois,
          ],
      };

  int adjacentBiomeSecurityFor(ForageBiome biome) {
    final neighbours = adjacentBiomesFor(biome)
        .where(isBiomeUnlocked)
        .map((item) => biomeSecurity[item]?.localSecurity ?? 0)
        .toList();
    if (neighbours.isEmpty) return 0;
    return (neighbours.reduce((left, right) => left + right) /
            neighbours.length)
        .round();
  }

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
      .where(
        (order) =>
            order.area == WorkshopOrderArea.workshop &&
            order.assignedPtipoteId == null,
      )
      .length;

  int get activePtipoteWorkshopOrders => activeWorkshopOrders
      .where(
        (order) =>
            order.area == WorkshopOrderArea.workshop &&
            order.assignedPtipoteId != null,
      )
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

  int get workshopSlots => workshopConfig.slotsForLevel(atelierLevel);

  int get kitchenSlots => workshopConfig.slotsForLevel(cuisineLevel);

  bool isAssignedToWorkshop(String figurineId) => activeWorkshopOrders.any(
        (order) => order.assignedPtipoteId == figurineId,
      );

  CraftRecipe _orderRecipe(WorkshopCraftOrder order) =>
      craftConfig.recipes.firstWhere(
        (recipe) => recipe.id == order.recipeId,
        orElse: () => defaultCraftConfig.simpleMealRecipe,
      );

  Map<String, int> _orderIngredients(WorkshopCraftOrder order) =>
      _orderRecipe(order).ingredients;

  String _orderDisplayName(WorkshopCraftOrder order) =>
      _orderRecipe(order).displayName;

  String _orderResultItem(WorkshopCraftOrder order) =>
      _orderRecipe(order).resultItem;

  int _orderResultAmount(WorkshopCraftOrder order) =>
      _orderRecipe(order).resultAmount;

  bool isAssignedToMarket(String figurineId) =>
      marketAssignedPtipoteId == figurineId;

  int get marketSlotLimit => marketConfig.slotsForLevel(marketLevel);

  bool isEquipmentResource(String resource) {
    return craftConfig.recipes.any(
      (recipe) => recipe.resultItem == resource && recipe.isEquipment,
    );
  }

  int marketStackLimitFor(String resource) => isEquipmentResource(resource)
      ? 1
      : lisiereForageConfig.inventoryStackLimit;

  int get globalStockCapacity {
    return fablabConfig.baseGlobalStockCapacity +
        atelierLevel * fablabConfig.stockCapacityBonusPerFablabLevel;
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
        success: false,
        message: 'Ressource incompatible.',
      );
    }
    final current = isOrganic ? generatorOrganic : generatorMineral;
    final capacity = isOrganic
        ? generatorOrganicCapacity(heartLevel)
        : generatorMineralCapacity(heartLevel);
    final moved = math.min(
      math.min(amount, resourceAmount(resource)),
      capacity - current,
    );
    if (moved <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune ressource transférée.',
      );
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
      success: true,
      message: '$removed $resource ajouté au Générateur.',
    );
  }

  bool resolveGenerator({required int heartLevel, DateTime? now}) {
    final current = now ?? DateTime.now();
    if (!_generatorCanRun) {
      generatorCycleStartedAt = null;
      return false;
    }
    generatorCycleStartedAt ??= current;
    final cycle = Duration(
      minutes: campGeneratorConfig.cycleMinutes(heartLevel),
    );
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
        ? generatorCycleStartedAt!.add(
            Duration(seconds: cycle.inSeconds * possibleCycles),
          )
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
    final persistentMissions = kernelConfig.missions
        .where((mission) => mission.type != KernelMissionType.weather)
        .where((mission) => !dismissedKernelMissionIds.contains(mission.id))
        .map(
          (mission) => KernelMissionProgress(
            config: mission,
            progress: _kernelMissionProgress(mission),
            status: completedKernelMissionIds.contains(mission.id)
                ? KernelMissionStatus.completed
                : _kernelMissionPrerequisiteMessage(mission) == null
                    ? KernelMissionStatus.active
                    : KernelMissionStatus.locked,
          ),
        );
    final weatherMissions = weatherAlerts
        .where((alert) => alert.endsAt.isAfter(DateTime.now()))
        .map(_weatherMissionForAlert)
        .whereType<KernelMissionConfig>()
        .where((mission) => !dismissedKernelMissionIds.contains(mission.id))
        .map(
          (mission) => KernelMissionProgress(
            config: mission,
            progress: _kernelMissionProgress(mission),
            status: completedKernelMissionIds.contains(mission.id)
                ? KernelMissionStatus.completed
                : _kernelMissionPrerequisiteMessage(mission) == null
                    ? KernelMissionStatus.active
                    : KernelMissionStatus.locked,
          ),
        );
    return <KernelMissionProgress>[...persistentMissions, ...weatherMissions];
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
          (mission) => mission.config.type == KernelMissionType.refugeRequest,
        )
        .take(kernelConfig.maxRefugeRequests)
        .toList();
  }

  void dismissCompletedKernelMission(String missionId) {
    if (!completedKernelMissionIds.contains(missionId)) return;
    dismissedKernelMissionIds.add(missionId);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  List<KernelMissionProgress> weatherKernelMissions(int campHeartLevel) {
    return kernelMissionsForCampHeartLevel(campHeartLevel)
        .where((mission) => mission.config.type == KernelMissionType.weather)
        .toList();
  }

  KernelMissionConfig? _weatherMissionForAlert(WeatherAlert alert) {
    final template = kernelConfig.missions
        .where(
          (mission) =>
              mission.type == KernelMissionType.weather &&
              mission.weatherType == alert.type.name,
        )
        .firstOrNull;
    if (template == null) return null;
    return KernelMissionConfig(
      id: '${template.id}-${alert.id}',
      type: template.type,
      title: template.title,
      description: template.description,
      conditionType: template.conditionType,
      requiredAmount: template.requiredAmount,
      populationReward: template.populationReward,
      bioBatteryReward: template.bioBatteryReward,
      xpReward: template.xpReward,
      mailMessage: template.mailMessage,
      requiredBuildingLevels: template.requiredBuildingLevels,
      requiredKernelTrustLevel: template.requiredKernelTrustLevel,
      requiredBreederLevel: template.requiredBreederLevel,
      requiredBuilderLevel: template.requiredBuilderLevel,
      requiredRestorerLevel: template.requiredRestorerLevel,
      requestedItem: alert.requestedItem ?? template.requestedItem,
      requestedAmount: alert.requestedAmount > 0
          ? alert.requestedAmount
          : template.requestedAmount,
      resourceRewards: template.resourceRewards,
      rewardPatternId: template.rewardPatternId,
      weatherType: template.weatherType,
      weatherDemandOptions: template.weatherDemandOptions,
    );
  }

  KernelMissionConfig? _kernelMissionById(String missionId) {
    final staticMission = kernelConfig.missions
        .where((mission) => mission.id == missionId)
        .firstOrNull;
    if (staticMission != null) return staticMission;
    return weatherAlerts
        .where((alert) => alert.endsAt.isAfter(DateTime.now()))
        .map(_weatherMissionForAlert)
        .whereType<KernelMissionConfig>()
        .where((mission) => mission.id == missionId)
        .firstOrNull;
  }

  int activeKernelMissionCount(int campHeartLevel) =>
      kernelMissionsForCampHeartLevel(
        campHeartLevel,
      ).where((mission) => mission.status == KernelMissionStatus.active).length;

  int unreadKernelMissionNotificationCount(int campHeartLevel) =>
      kernelMissionsForCampHeartLevel(campHeartLevel)
          .where(
            (mission) =>
                mission.status == KernelMissionStatus.active &&
                !viewedKernelMissionIds.contains(mission.config.id),
          )
          .length;

  void markKernelMissionsViewed(int campHeartLevel) {
    final activeIds = kernelMissionsForCampHeartLevel(campHeartLevel)
        .where((mission) => mission.status == KernelMissionStatus.active)
        .map((mission) => mission.config.id);
    final before = viewedKernelMissionIds.length;
    viewedKernelMissionIds.addAll(activeIds);
    if (viewedKernelMissionIds.length != before) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  int kernelAxisLevel(KernelAxis axis) => kernelAxisLevels[axis] ?? 1;

  int kernelAxisCurrentXp(KernelAxis axis) => kernelAxisXp[axis] ?? 0;

  /// Returns the current level for a building referenced by a Kernel Pattern.
  /// Pattern prerequisites stay data-driven while unknown future buildings
  /// simply remain unavailable instead of making an activation crash.
  int kernelPlanBuildingLevel(String buildingId) => switch (buildingId) {
        'fablab' => atelierLevel,
        'cuisine' => cuisineLevel,
        'atelier' => atelierLevel,
        'recycler' => recyclerLevel,
        'securityTower' => securityTowerLevel,
        'market' => marketLevel,
        'house' => houseLevel,
        'plaineNursery' => plaineNurseryLevel,
        _ => 0,
      };

  bool kernelPlanRequirementsMet(KernelTechnologyPlanConfig plan) {
    if (kernelTrustLevel < plan.requiredTrustLevel) return false;
    if (plan.requiredAxis != null &&
        kernelAxisLevel(plan.requiredAxis!) < plan.requiredAxisLevel) {
      return false;
    }
    if (kernelAxisLevel(KernelAxis.breeder) < plan.requiredBreederLevel ||
        kernelAxisLevel(KernelAxis.builder) < plan.requiredBuilderLevel ||
        kernelAxisLevel(KernelAxis.restorer) < plan.requiredRestorerLevel) {
      return false;
    }
    return plan.requiredBuildingLevels.entries.every(
      (entry) => kernelPlanBuildingLevel(entry.key) >= entry.value,
    );
  }

  String kernelPlanRequirementsLabel(KernelTechnologyPlanConfig plan) {
    final requirements = <String>[
      'Confiance niv. ${plan.requiredTrustLevel}',
      if (plan.requiredAxis != null)
        '${_kernelAxisLabel(plan.requiredAxis!)} niv. ${plan.requiredAxisLevel}',
      if (plan.requiredBreederLevel > 0)
        'Éleveur niv. ${plan.requiredBreederLevel}',
      if (plan.requiredBuilderLevel > 0)
        'Bâtisseur niv. ${plan.requiredBuilderLevel}',
      if (plan.requiredRestorerLevel > 0)
        'Régénérateur niv. ${plan.requiredRestorerLevel}',
      ...plan.requiredBuildingLevels.entries.map(
        (entry) => '${_kernelBuildingLabel(entry.key)} niv. ${entry.value}',
      ),
    ];
    return requirements.join(' · ');
  }

  String _kernelAxisLabel(KernelAxis axis) => switch (axis) {
        KernelAxis.breeder => 'Éleveur',
        KernelAxis.builder => 'Bâtisseur',
        KernelAxis.restorer => 'Régénérateur',
      };

  String _kernelBuildingLabel(String buildingId) => switch (buildingId) {
        'fablab' => 'Fablab',
        'cuisine' => 'Cuisine',
        'atelier' => 'Atelier',
        'recycler' => 'Recycleur',
        'securityTower' => 'Tour',
        'market' => 'Marché',
        'house' => 'Maison',
        'plaineNursery' => 'Nurserie',
        _ => buildingId,
      };

  int get kernelTrustXpRequired =>
      kernelProgressConfig.xpRequired(level: kernelTrustLevel, isTrust: true);

  int kernelAxisXpRequired(KernelAxis axis) => kernelProgressConfig.xpRequired(
        level: kernelAxisLevel(axis),
        isTrust: false,
      );

  KernelPlanState kernelPlanState(KernelTechnologyPlanConfig plan) {
    final pTibugPattern = pTibugConfig.patternForKernelPlanId(plan.id);
    if (activeKernelPlanIds.contains(plan.id) ||
        (pTibugPattern != null &&
            activePTibugPatterns.contains(pTibugPattern.species)) ||
        (plan.initialState == KernelPlanState.active && isFablabBuilt)) {
      return KernelPlanState.active;
    }
    if (readyKernelPlanIds.contains(plan.id)) return KernelPlanState.ready;
    if (discoveredKernelPlanIds.contains(plan.id)) {
      return KernelPlanState.discovered;
    }
    if (plan.initialState == KernelPlanState.discovered) {
      return KernelPlanState.discovered;
    }
    return KernelPlanState.unknown;
  }

  KernelPlanState pTibugPatternState(PTibugSpecies species) {
    final planId = pTibugConfig.patterns[species]!.kernelPlanId;
    final plan = kernelProgressConfig.plans
        .where((item) => item.id == planId)
        .firstOrNull;
    return plan == null ? KernelPlanState.unknown : kernelPlanState(plan);
  }

  Zone0ActionResult chooseStarterPTibugPattern(PTibugSpecies species) {
    if (!isPlaineNurseryBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis d’abord la Nurserie P’TIBUG.',
      );
    }
    if (starterPTibugChoiceMade) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le premier Pattern a déjà été choisi.',
      );
    }
    starterPTibugChoiceMade = true;
    activePTibugPatterns.add(species);
    final researchPattern = pTibugConfig.researchPatterns.values
        .where((item) => item.linkedSpecies == species)
        .firstOrNull;
    if (researchPattern != null) {
      final progress = _patternProgressFor(researchPattern.id);
      progress
        ..state = PTibugPatternState.active
        ..masteryLevel = math.max(progress.masteryLevel, 1)
        ..discoveredAt ??= DateTime.now()
        ..activatedAt ??= DateTime.now();
    }
    final planId = pTibugConfig.patterns[species]!.kernelPlanId;
    discoveredKernelPlanIds.remove(planId);
    readyKernelPlanIds.remove(planId);
    activeKernelPlanIds.add(planId);
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Le Kernel transmet le Pattern ${pTibugConfig.species[species]!.displayName}. La Nurserie peut lancer sa première création.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Plan Kernel',
        concerned: 'Joueur',
        summary:
            'Pattern ${pTibugConfig.species[species]!.displayName} sélectionné.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Pattern ${pTibugConfig.species[species]!.displayName} choisi.',
    );
  }

  PTibugPatternProgress _patternProgressFor(String patternId) =>
      pTibugPatternProgress.putIfAbsent(
        patternId,
        () => PTibugPatternProgress(patternId: patternId),
      );

  PTibugResearchPatternConfig? pTibugResearchPattern(String patternId) =>
      pTibugConfig.researchPatterns[patternId];

  bool isPTibugPatternActive(String patternId) {
    final progress = pTibugPatternProgress[patternId];
    return progress != null &&
        (progress.state == PTibugPatternState.active ||
            progress.state == PTibugPatternState.masteredCurrentLevel) &&
        progress.masteryLevel > 0;
  }

  Zone0ActionResult discoverPTibugPattern(String patternId) {
    final pattern = pTibugResearchPattern(patternId);
    if (pattern == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern inconnu.',
      );
    }
    final progress = _patternProgressFor(patternId);
    if (progress.state != PTibugPatternState.unknown) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern déjà identifié.',
      );
    }
    progress
      ..state = PTibugPatternState.discovered
      ..discoveredAt = DateTime.now();
    reports.add(
      PtipoteMissionReport.system(
        message: 'Le Kernel a identifié ${pattern.displayName}.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Recherche Kernel',
        concerned: 'Joueur',
        summary: 'Nouveau Pattern disponible.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${pattern.displayName} identifié.',
    );
  }

  Zone0ActionResult openPTibugDataCell(String cellId) {
    final cell = pTibugDataCells.where((item) => item.id == cellId).firstOrNull;
    if (cell == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cellule introuvable.',
      );
    }
    if (cell.isOpened) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cellule déjà analysée.',
      );
    }
    for (final entry in cell.entries) {
      pTibugDataReserve[entry.family] =
          (pTibugDataReserve[entry.family] ?? 0) + entry.value(pTibugConfig);
    }
    cell.openedAt = DateTime.now();
    reports.add(
      PtipoteMissionReport.system(
        message:
            '${cell.displayName} analysée : les données rejoignent le Kernel.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Analyse de cellule',
        concerned: 'Joueur',
        summary: '5 données révélées.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Données ajoutées au Kernel.',
    );
  }

  Map<PTibugDataFamily, int> pTibugPatternMissingData(String patternId) {
    final pattern = pTibugResearchPattern(patternId);
    final progress = pTibugPatternProgress[patternId];
    if (pattern == null || progress == null) {
      return const <PTibugDataFamily, int>{};
    }
    final nextLevel = progress.masteryLevel + 1;
    final requirements = pattern.masteryCosts[nextLevel];
    if (requirements == null) return const <PTibugDataFamily, int>{};
    return <PTibugDataFamily, int>{
      for (final entry in requirements.entries)
        entry.key: math.max(
          0,
          entry.value - (progress.investedDataByFamily[entry.key] ?? 0),
        ),
    };
  }

  Zone0ActionResult investPTibugPatternData({
    required String patternId,
    required PTibugDataFamily family,
    required int amount,
  }) {
    final pattern = pTibugResearchPattern(patternId);
    if (pattern == null || amount <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Investissement invalide.',
      );
    }
    final progress = _patternProgressFor(patternId);
    if (progress.state == PTibugPatternState.unknown) {
      return const Zone0ActionResult(
        success: false,
        message: 'Découvre ce Pattern avant de le rechercher.',
      );
    }
    final missing = pTibugPatternMissingData(patternId)[family] ?? 0;
    final available = pTibugDataReserve[family] ?? 0;
    final invested = math.min(amount, math.min(missing, available));
    if (invested <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune donnée compatible disponible.',
      );
    }
    pTibugDataReserve[family] = available - invested;
    progress.investedDataByFamily[family] =
        (progress.investedDataByFamily[family] ?? 0) + invested;
    progress.state = PTibugPatternState.researching;
    _completePTibugPatternLevelIfReady(pattern, progress);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$invested donnée(s) investie(s).',
    );
  }

  Zone0ActionResult completePTibugPatternAutomatically(String patternId) {
    final pattern = pTibugResearchPattern(patternId);
    if (pattern == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern introuvable.',
      );
    }
    final progress = _patternProgressFor(patternId);
    if (progress.state == PTibugPatternState.unknown) {
      return const Zone0ActionResult(
        success: false,
        message: 'Découvre ce Pattern avant de le rechercher.',
      );
    }
    final missing = pTibugPatternMissingData(patternId);
    var investedAny = false;
    for (final entry in missing.entries) {
      final available = pTibugDataReserve[entry.key] ?? 0;
      final invested = math.min(entry.value, available);
      if (invested == 0) continue;
      pTibugDataReserve[entry.key] = available - invested;
      progress.investedDataByFamily[entry.key] =
          (progress.investedDataByFamily[entry.key] ?? 0) + invested;
      investedAny = true;
    }
    if (!investedAny) {
      return const Zone0ActionResult(
        success: false,
        message: 'Réserve de données insuffisante.',
      );
    }
    progress.state = PTibugPatternState.researching;
    _completePTibugPatternLevelIfReady(pattern, progress);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Données disponibles investies.',
    );
  }

  void _completePTibugPatternLevelIfReady(
    PTibugResearchPatternConfig pattern,
    PTibugPatternProgress progress,
  ) {
    final nextLevel = progress.masteryLevel + 1;
    final requirements = pattern.masteryCosts[nextLevel];
    if (requirements == null ||
        requirements.entries.any(
          (entry) =>
              (progress.investedDataByFamily[entry.key] ?? 0) < entry.value,
        )) {
      return;
    }
    progress
      ..masteryLevel = nextLevel
      ..investedDataByFamily.clear()
      ..activatedAt = DateTime.now()
      ..state = pattern.masteryCosts.containsKey(nextLevel + 1)
          ? PTibugPatternState.masteredCurrentLevel
          : PTibugPatternState.active;
    if (pattern.linkedSpecies != null) {
      activePTibugPatterns.add(pattern.linkedSpecies!);
    }
    reports.add(
      PtipoteMissionReport.system(
        message: '${pattern.displayName} atteint la maîtrise $nextLevel.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Maîtrise de Pattern',
        concerned: 'Joueur',
        summary: 'Nouveau niveau de recherche.',
      ),
    );
  }

  bool isWorkshopRecipeActive(CraftRecipe recipe) {
    final matchingPlan = kernelProgressConfig.plans.where(
      (plan) => plan.workshopRecipeId == recipe.id,
    );
    if (matchingPlan.isEmpty) return true;
    return matchingPlan.any(
      (plan) => kernelPlanState(plan) == KernelPlanState.active,
    );
  }

  String? _recipeRequirementsMessage(CraftRecipe recipe) {
    final matchingPlans = kernelProgressConfig.plans
        .where((plan) => plan.workshopRecipeId == recipe.id)
        .toList();
    final plan = matchingPlans.isEmpty ? null : matchingPlans.first;
    final requiredTrustLevel =
        plan?.requiredTrustLevel ?? recipe.kernelTrustLevel;
    final requiredBreederLevel =
        plan?.requiredBreederLevel ?? recipe.breederLevel;
    final requiredBuilderLevel =
        plan?.requiredBuilderLevel ?? recipe.builderLevel;
    final requiredRestorerLevel =
        plan?.requiredRestorerLevel ?? recipe.restorerLevel;
    if (kernelTrustLevel < requiredTrustLevel) {
      return 'Confiance du Kernel niveau $requiredTrustLevel requise.';
    }
    if (kernelAxisLevel(KernelAxis.breeder) < requiredBreederLevel) {
      return 'Éleveur niveau $requiredBreederLevel requis.';
    }
    if (kernelAxisLevel(KernelAxis.builder) < requiredBuilderLevel) {
      return 'Bâtisseur niveau $requiredBuilderLevel requis.';
    }
    if (kernelAxisLevel(KernelAxis.restorer) < requiredRestorerLevel) {
      return 'Régénérateur niveau $requiredRestorerLevel requis.';
    }
    if (recipe.craftSection == CraftSection.cuisine &&
        cuisineLevel < recipe.cuisineLevel) {
      return 'Cuisine niveau ${recipe.cuisineLevel} requise.';
    }
    if (recipe.craftSection == CraftSection.atelier &&
        atelierLevel < recipe.atelierLevel) {
      return 'Atelier niveau ${recipe.atelierLevel} requis.';
    }
    return null;
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
    final pTibugPattern = pTibugConfig.patternForKernelPlanId(planId);
    if (pTibugPattern != null) {
      activePTibugPatterns.add(pTibugPattern.species);
    }
    reports.add(
      PtipoteMissionReport.system(
        message: 'Plan activé : ${plan.title}. ${plan.kernelText}',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Plan Kernel',
        concerned: 'Joueur',
        summary: '${plan.title} est maintenant actif.',
      ),
    );
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
        reports.add(
          PtipoteMissionReport.system(
            message: 'Observation Kernel : ${plan.kernelText}',
            sourceBuildingId: 'kernel',
            mailbox: Zone0MessageMailbox.kernel,
            subject: 'Message Kernel',
            concerned: 'Joueur',
            summary: plan.kernelText,
          ),
        );
      }
      if (kernelPlanState(plan) != KernelPlanState.discovered) continue;
      if (kernelPlanRequirementsMet(plan)) {
        readyKernelPlanIds.add(plan.id);
        reports.add(
          PtipoteMissionReport.system(
            message: 'Plan prêt : ${plan.title}. Le Kernel peut le partager.',
            sourceBuildingId: 'kernel',
            mailbox: Zone0MessageMailbox.kernel,
            subject: 'Plan Kernel',
            concerned: 'Joueur',
            summary: '${plan.title} est prêt à être activé.',
          ),
        );
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

  int unreadReportCountForMailbox(Zone0MessageMailbox mailbox) {
    return reports
        .where((report) => !report.read && report.mailbox == mailbox)
        .length;
  }

  int unreadBuildingNotificationCount(String buildingName) {
    // A parent badge includes notifications emitted by its child units.
    final targets = switch (buildingName) {
      'FabLab' => const <String>{'fablab', 'cuisine', 'atelier', 'recycler'},
      'Tour' => const <String>{'securityTower'},
      'Market' => const <String>{'market'},
      'Maison' => const <String>{'house', 'housing'},
      'Cœur du Camp' => const <String>{'plaineNursery'},
      'Kernel' => const <String>{'kernel'},
      _ => const <String>{},
    };
    return reports
        .where(
          (report) => !report.read && targets.contains(report.sourceBuildingId),
        )
        .length;
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
        manualRestingIds.contains(figurine.id) &&
        !waitingForBedIds.contains(figurine.id);
  }

  bool isWaitingForBed(PtipoteFigurine figurine) =>
      !isOnMission(figurine.id) && waitingForBedIds.contains(figurine.id);

  void ensureNurseryAdmissions(List<PtipoteFigurine> figurines) {
    var changed = false;
    for (final figurine in figurines) {
      if (hatchedPtipoteIds.length >= alcoveCapacity) break;
      if (hatchedPtipoteIds.add(figurine.id)) changed = true;
    }
    if (changed) {
      unawaited(saveRuntimeToFirebase());
    }
  }

  bool isInNursery(PtipoteFigurine figurine) =>
      !hatchedPtipoteIds.contains(figurine.id);

  bool canHatchFromNursery(PtipoteFigurine figurine) =>
      isInNursery(figurine) && hatchedPtipoteIds.length < alcoveCapacity;

  void hatchFromNursery(PtipoteFigurine figurine) {
    if (!canHatchFromNursery(figurine)) return;
    hatchedPtipoteIds.add(figurine.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  bool isBusy(PtipoteFigurine figurine) {
    return isOnMission(figurine.id) ||
        isResting(figurine) ||
        isWaitingForBed(figurine) ||
        isAssignedToTower(figurine.id) ||
        isAssignedToWorkshop(figurine.id) ||
        isAssignedToMarket(figurine.id);
  }

  double calculateWorkshopEfficiency(
    PtipoteFigurine figurine, {
    required int buildingLevel,
  }) {
    final figurineBonus =
        levelFor(figurine) * workshopConfig.levelSpeedBonusPercent;
    return (figurineBonus.clamp(0, workshopConfig.maxLevelSpeedBonusPercent) +
            workshopConfig.buildingSpeedBonusForLevel(buildingLevel))
        .clamp(0, 0.50);
  }

  double craftSpeedBonus(PtipoteFigurine? figurine, int buildingLevel) =>
      figurine == null
          ? workshopConfig.buildingSpeedBonusForLevel(buildingLevel)
          : calculateWorkshopEfficiency(figurine, buildingLevel: buildingLevel);

  Zone0ActionResult startWorkshopOrder({
    required CraftRecipe recipe,
    required int quantity,
    PtipoteFigurine? figurine,
  }) {
    resolveWorkshopOrder();
    if (recipe.craftSection != CraftSection.atelier) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette recette se prépare dans la Cuisine.',
      );
    }
    final requirements = _recipeRequirementsMessage(recipe);
    if (requirements != null) {
      return Zone0ActionResult(success: false, message: requirements);
    }
    if (!isWorkshopRecipeActive(recipe)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Kernel n’a pas encore activé ce Plan.',
      );
    }
    if (figurine == null && activeManualWorkshopOrders >= 1) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le créneau manuel de l’Atelier est occupé.',
      );
    }
    if (figurine == null && energyUnits < 1) {
      return const Zone0ActionResult(
        success: false,
        message: 'Il faut 1 unité d’énergie pour lancer un craft manuel.',
      );
    }
    if (figurine != null && activePtipoteWorkshopOrders >= workshopSlots) {
      return const Zone0ActionResult(
        success: false,
        message: 'Tous les emplacements P’TIPOTE sont occupés.',
      );
    }
    if (quantity <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Quantité invalide.',
      );
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE occupé.',
      );
    }
    final totalCosts = recipe.ingredients.map(
      (key, value) => MapEntry(key, value * quantity),
    );
    if (!hasResources(totalCosts)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(totalCosts),
      );
    }
    if (!hasInventoryCapacityFor(<String, int>{
      recipe.resultItem: recipe.resultAmount * quantity,
    })) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire insuffisant pour la commande.',
      );
    }
    if (!removeResources(totalCosts)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources indisponibles.',
      );
    }
    if (figurine == null) {
      energyUnits -= 1;
    }
    final speedBonus = craftSpeedBonus(figurine, atelierLevel);
    final unitSeconds = math.max(
      1,
      (Duration(minutes: recipe.durationMinutes).inSeconds * (1 - speedBonus))
          .round(),
    );
    final now = DateTime.now();
    workshopOrders.add(
      WorkshopCraftOrder(
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
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${recipe.displayName} lancé${figurine == null ? '' : ' avec ${figurine.displayName}'}.',
    );
  }

  Zone0ActionResult startKitchenOrder({
    required CraftRecipe recipe,
    required int quantity,
    PtipoteFigurine? figurine,
  }) {
    resolveWorkshopOrder();
    if (recipe.craftSection != CraftSection.cuisine) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette recette se fabrique dans l’Atelier.',
      );
    }
    if (!isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis le Fablab pour utiliser la Cuisine.',
      );
    }
    final requirements = _recipeRequirementsMessage(recipe);
    if (requirements != null) {
      return Zone0ActionResult(success: false, message: requirements);
    }
    if (figurine == null && activeManualKitchenOrders >= 1) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le créneau manuel de la Cuisine est occupé.',
      );
    }
    if (figurine == null && energyUnits < 1) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Il faut 1 unité d’énergie pour lancer une préparation manuelle.',
      );
    }
    if (figurine != null && activePtipoteKitchenOrders >= kitchenSlots) {
      return const Zone0ActionResult(
        success: false,
        message: 'Tous les emplacements P’TIPOTE sont occupés.',
      );
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE occupé.',
      );
    }
    if (quantity <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Quantité invalide.',
      );
    }
    final totalCosts = recipe.ingredients.map(
      (key, value) => MapEntry(key, value * quantity),
    );
    final output = <String, int>{
      recipe.resultItem: recipe.resultAmount * quantity,
    };
    if (!hasResources(totalCosts)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(totalCosts),
      );
    }
    if (!hasInventoryCapacityFor(output)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire insuffisant pour la commande.',
      );
    }
    if (!removeResources(totalCosts)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources indisponibles.',
      );
    }
    if (figurine == null) {
      energyUnits -= 1;
    }
    final speedBonus = craftSpeedBonus(figurine, cuisineLevel);
    final unitSeconds = math.max(
      1,
      (Duration(minutes: recipe.durationMinutes).inSeconds * (1 - speedBonus))
          .round(),
    );
    final now = DateTime.now();
    workshopOrders.add(
      WorkshopCraftOrder(
        id: 'kitchen-${now.microsecondsSinceEpoch}',
        area: WorkshopOrderArea.kitchen,
        recipeId: recipe.id,
        requestedQuantity: quantity,
        completedQuantity: 0,
        assignedPtipoteId: figurine?.id,
        assignedPtipoteName: figurine?.displayName,
        startTime: now,
        nextCompletionTime: now.add(Duration(seconds: unitSeconds)),
        unitDurationSeconds: unitSeconds,
        reservedResources: totalCosts,
      ),
    );
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
      elapsedUnits,
      order.requestedQuantity - order.completedQuantity,
    );
    if (order.assignedPtipoteId != null) {
      final vitality = vitalityOverrides[order.assignedPtipoteId!] ??
          ptipoteStatsConfig.maxVitality;
      final possible = math.max(
        0,
        (vitality - ptipoteStatsConfig.minVitalityBeforeAutoRest) ~/
            workshopConfig.vitalityCostPerUnit,
      );
      units = math.min(units, possible);
    }
    if (units > 0) {
      addResources(<String, int>{resultItem: resultAmount * units});
      order.completedQuantity += units;
      order.nextCompletionTime = order.nextCompletionTime.add(
        Duration(seconds: order.unitDurationSeconds * units),
      );
      if (order.assignedPtipoteId != null) {
        final id = order.assignedPtipoteId!;
        vitalityOverrides[id] = math.max(
          0,
          (vitalityOverrides[id] ?? ptipoteStatsConfig.maxVitality) -
              units * workshopConfig.vitalityCostPerUnit,
        );
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
          addResources(
            ingredients.map((key, value) => MapEntry(key, value * remaining)),
          );
        }
      }
      reports.add(
        PtipoteMissionReport.system(
          message: tired
              ? '${order.assignedPtipoteName} rentre fatigué de ${order.area == WorkshopOrderArea.kitchen ? 'la Cuisine' : 'l’Atelier'}.'
              : 'Commande ${order.area == WorkshopOrderArea.kitchen ? 'Cuisine' : 'Atelier'} terminée : $displayName.',
          sourceBuildingId:
              order.area == WorkshopOrderArea.kitchen ? 'cuisine' : 'atelier',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: order.assignedPtipoteName ?? 'Joueur',
          summary: tired
              ? '$displayName arrêté : P’TIPOTE fatigué.'
              : '$displayName × ${order.completedQuantity} terminé.',
        ),
      );
      if (order.area == WorkshopOrderArea.kitchen &&
          resultItem == craftConfig.simpleMealRecipe.resultItem) {
        mealsPrepared += resultAmount * order.completedQuantity;
        refreshKernelMissions();
      }
      emitKernelProgressEvent(KernelProgressEventType.craftCompleted);
      if (order.assignedPtipoteId != null) {
        emitKernelProgressEvent(KernelProgressEventType.ptipoteCraftCompleted);
      }
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
        success: false,
        message: 'Aucune commande active.',
      );
    }
    resolveWorkshopOrder();
    final remaining = order.requestedQuantity - order.completedQuantity;
    final ingredients = _orderIngredients(order);
    if (remaining > 0) {
      addResources(
        ingredients.map((key, value) => MapEntry(key, value * remaining)),
      );
    }
    order.status = WorkshopOrderStatus.cancelled;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Commande annulée, ressources restantes rendues.',
    );
  }

  Zone0ActionResult constructMarket(int heartLevel) {
    if (isMarketBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Marché est déjà construit.',
      );
    }
    if (heartLevel < marketConfig.requiredCampHeartLevel) {
      return const Zone0ActionResult(
        success: false,
        message: 'Niveau du Cœur insuffisant.',
      );
    }
    if (currentPopulation < marketConfig.requiredPopulation) {
      return Zone0ActionResult(
        success: false,
        message: 'Population requise : ${marketConfig.requiredPopulation}.',
      );
    }
    if (!hasResources(marketConfig.constructionCost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(marketConfig.constructionCost),
      );
    }
    if (!removeResources(marketConfig.constructionCost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources indisponibles.',
      );
    }
    marketLevel = 1;
    emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
    reports.add(PtipoteMissionReport.system(message: 'Le Marché est ouvert.'));
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Le Marché est prêt.',
    );
  }

  Zone0ActionResult transferToMarket(String resource, int amount) {
    if (!isMarketBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Marché non construit.',
      );
    }
    if (!marketConfig.saleValues.containsKey(resource)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Objet non vendable.',
      );
    }
    final existing =
        marketStock.where((item) => item.resource == resource).firstOrNull;
    if (existing == null && marketStock.length >= marketSlotLimit) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les trois emplacements sont occupés.',
      );
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
        success: false,
        message: 'Stock insuffisant.',
      );
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
      success: true,
      message: '$moved $resource placé au Marché.',
    );
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
      message: '$returned $resource rendu à la Maison.',
    );
  }

  Zone0ActionResult assignToMarket(PtipoteFigurine figurine) {
    if (!isMarketBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Marché non construit.',
      );
    }
    if (marketAssignedPtipoteId != null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Un P’TIPOTE travaille déjà au Marché.',
      );
    }
    if (isBusy(figurine)) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE occupé.',
      );
    }
    if (vitalityFor(figurine) <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE trop fatigué.',
      );
    }
    marketAssignedPtipoteId = figurine.id;
    marketAssignedPtipoteName = figurine.displayName;
    marketLastWorkTickAt = DateTime.now();
    vitalityOverrides.putIfAbsent(figurine.id, () => vitalityFor(figurine));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${figurine.displayName} aide au Marché.',
    );
  }

  Zone0ActionResult removeFromMarket({bool tired = false}) {
    final id = marketAssignedPtipoteId;
    if (id == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun P’TIPOTE affecté.',
      );
    }
    if (tired) manualRestingIds.add(id);
    final name = marketAssignedPtipoteName ?? 'Le P’TIPOTE';
    marketAssignedPtipoteId = null;
    marketAssignedPtipoteName = null;
    marketLastWorkTickAt = null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$name rentre à la Maison.',
    );
  }

  Duration _marketSaleInterval() {
    final populationModifier =
        (10 / math.max(5, currentPopulation)).clamp(0.5, 2.0) *
            (marketConfig.saleIntervalPopulationImpactPercent / 100).clamp(
              0.0,
              2.0,
            );
    final wellbeingModifier = (1.3 - campWellbeing / 250).clamp(0.8, 1.3);
    final ptipoteModifier = marketAssignedPtipoteId == null
        ? 1.0
        : marketConfig.ptipoteIntervalMultiplier;
    return Duration(
      seconds: math.max(
        1,
        (marketConfig.baseSaleIntervalMinutes *
                60 *
                marketConfig.saleIntervalMultiplierForLevel(marketLevel) *
                populationModifier *
                wellbeingModifier *
                ptipoteModifier)
            .round(),
      ),
    );
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
    var changed = _resolveMerchantSchedule(current);
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
              marketConfig.maxRequestsForLevel(marketLevel)) {
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
    for (final request in marketRequests.where(
      (item) =>
          item.status != MarketRequestStatus.completed &&
          !current.isBefore(item.customerReturnTime),
    )) {
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
        reports.add(
          PtipoteMissionReport.system(
            message:
                'Demande livrée : ${request.requestedQuantity} ${request.requestedItemId}.',
          ),
        );
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
    marketRequests.add(
      MarketCustomerRequest(
        id: 'request-${now.microsecondsSinceEpoch}-${marketRequests.length}',
        requestedItemId: item,
        requestedQuantity:
            isResource ? lisiereForageConfig.inventoryStackLimit : 1,
        rewardBioBattery: math.max(
          1,
          (marketConfig.saleValues[item] ?? 1) ~/
              marketConfig.valuePerBioBattery,
        ),
        rewardWellbeing: 1,
        createdAt: now,
        customerReturnTime: now.add(_randomMarketReturnDelay()),
        status: MarketRequestStatus.noted,
      ),
    );
    reports.add(
      PtipoteMissionReport.system(
        message: 'Demande du Marché : $item recherché.',
      ),
    );
  }

  Duration _randomMarketReturnDelay() => Duration(
        minutes: marketConfig.requestMinReturnMinutes +
            _random.nextInt(
              math.max(
                1,
                marketConfig.requestMaxReturnMinutes -
                    marketConfig.requestMinReturnMinutes +
                    1,
              ),
            ),
      );

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
    final cooldown = Duration(
      minutes: ptipoteStatsConfig.cuddleCooldownMinutes,
    );
    final elapsed = DateTime.now().difference(cuddleAt);
    return (elapsed.inSeconds / cooldown.inSeconds).clamp(0.0, 1.0);
  }

  Duration vitalityRecoveryRemaining(PtipoteFigurine figurine) {
    final missing = math.max(
      0,
      ptipoteStatsConfig.maxVitality - vitalityFor(figurine),
    );
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
    if (manualRestingIds.length > alcoveCapacity) {
      waitingForBedIds.add(figurine.id);
    }
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
    waitingForBedIds.remove(figurine.id);
    final wakeVitality = math.min(
      ptipoteStatsConfig.maxVitality,
      ptipoteStatsConfig.minVitalityBeforeAutoRest + 1,
    );
    vitalityOverrides[figurine.id] = math.max(
      vitalityFor(figurine),
      wakeVitality,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void recoverFigurineNeeds({
    required List<PtipoteFigurine> figurines,
    required int tick,
  }) {
    var changed = false;
    if (_syncBedAssignments(figurines)) {
      changed = true;
    }
    if (resolveDueTowerMissions()) {
      changed = true;
    }
    if (resolveWeatherCycle()) {
      changed = true;
    }
    if (_applyElapsedSimulation(figurines)) {
      changed = true;
    }
    final hungerDecayTick = math.max(
      1,
      ptipoteStatsConfig.hungerDecayMinutes * 2,
    );
    final restLossTick = math.max(
      1,
      ptipoteStatsConfig.awakeRestLossMinutes * 2,
    );
    final naturalVitalityTick = math.max(
      1,
      ptipoteStatsConfig.naturalVitalityRecoveryMinutes * 2,
    );
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
            refugeSafety +
                securityTowerConfig.securityGainForLevel(securityTowerLevel),
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
        final restGain = math.max(
          1,
          ptipoteStatsConfig.sleepRestRecoveryPerMinute ~/ 2,
        );
        final nextRest = math.min(
          ptipoteStatsConfig.maxRest,
          currentRest + restGain,
        );
        if (nextRest != currentRest) {
          restOverrides[figurine.id] = nextRest;
          _trackWellRestedTransition(
            figurineId: figurine.id,
            previousRest: currentRest,
            nextRest: nextRest,
          );
          changed = true;
        }
        // A full rest frees the alcove so another tired P'TIPOTE can use it.
        if (nextRest >= ptipoteStatsConfig.maxRest) {
          manualRestingIds.remove(figurine.id);
          waitingForBedIds.remove(figurine.id);
          changed = true;
        }
      } else if (tick % restLossTick == 0 && currentRest > 0) {
        final nextRest = math.max(0, currentRest - 1);
        restOverrides[figurine.id] = nextRest;
        _trackWellRestedTransition(
          figurineId: figurine.id,
          previousRest: currentRest,
          nextRest: nextRest,
        );
        changed = true;
      }
    }
    if (_syncBedAssignments(figurines)) {
      changed = true;
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
    if (_syncBedAssignments(figurines)) {
      changed = true;
    }
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
          final previousRest = currentRest;
          currentRest = math.min(
            ptipoteStatsConfig.maxRest,
            currentRest + restGain,
          );
          restOverrides[figurine.id] = currentRest;
          _trackWellRestedTransition(
            figurineId: figurine.id,
            previousRest: previousRest,
            nextRest: currentRest,
          );
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
          final previousRest = currentRest;
          currentRest = math.max(0, currentRest - restLoss);
          restOverrides[figurine.id] = currentRest;
          _trackWellRestedTransition(
            figurineId: figurine.id,
            previousRest: previousRest,
            nextRest: currentRest,
          );
          changed = true;
        }

        final recoveryInterval = isHappy(figurine)
            ? math.max(
                1,
                (1 / ptipoteStatsConfig.happyVitalityRecoveryPerMinute).ceil(),
              )
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
            refugeSafety +
                towerTicks *
                    securityTowerConfig.securityGainForLevel(
                      securityTowerLevel,
                    ),
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

  void _trackWellRestedTransition({
    required String figurineId,
    required int previousRest,
    required int nextRest,
  }) {
    final wasWellRested =
        previousRest >= ptipoteStatsConfig.wellRestedThreshold;
    final isWellRested = nextRest >= ptipoteStatsConfig.wellRestedThreshold;
    if (!isWellRested) {
      wellRestedRewardedIds.remove(figurineId);
      return;
    }
    if (!wasWellRested && wellRestedRewardedIds.add(figurineId)) {
      emitKernelProgressEvent(KernelProgressEventType.ptipoteWellRested);
    }
  }

  bool _syncBedAssignments(List<PtipoteFigurine> figurines) {
    final candidates = <String>[];
    for (final figurine in figurines) {
      if (isOnMission(figurine.id) ||
          isAssignedToTower(figurine.id) ||
          isAssignedToWorkshop(figurine.id) ||
          isAssignedToMarket(figurine.id)) {
        continue;
      }
      if (manualRestingIds.contains(figurine.id) ||
          vitalityFor(figurine) <=
              ptipoteStatsConfig.minVitalityBeforeAutoRest) {
        manualRestingIds.add(figurine.id);
        candidates.add(figurine.id);
      }
    }

    final alreadyInBed = manualRestingIds
        .where(
          (id) => candidates.contains(id) && !waitingForBedIds.contains(id),
        )
        .toList();
    final preferred = <String>[
      ...alreadyInBed,
      ...candidates.where((id) => !alreadyInBed.contains(id)),
    ];
    final nextWaiting = preferred.skip(alcoveCapacity).toSet();
    if (setEquals(waitingForBedIds, nextWaiting)) return false;
    waitingForBedIds
      ..clear()
      ..addAll(nextWaiting);
    return true;
  }

  int resourceAmount(String resource) {
    return inventory
        .where((stack) => stack.resource == resource)
        .fold(0, (total, stack) => total + stack.amount);
  }

  Zone0ActionResult openBioBattery() {
    if (bioBatteries <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune Bio-batterie disponible.',
      );
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
            'Débloqué au Cœur du Camp niveau ${wasteRecyclerConfig.recyclerUnlockCampHeartLevel}.',
      );
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
        success: false,
        message: 'Aucun Déchet transféré.',
      );
    }
    removeResource('Déchets', moved);
    recyclerWasteTank += moved;
    resolveWasteAndRecycler(campHeartLevel: campHeartLevel);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$moved Déchet(s) vers la cuve.',
    );
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
          isMarketBuilt,
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
      lastWasteGenerationAt = lastWaste.add(
        Duration(
          minutes:
              wasteCycles * wasteRecyclerConfig.wasteGenerationCycleMinutes,
        ),
      );
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
        Duration(minutes: wasteRecyclerConfig.cycleMinutes(recyclerLevel)),
      );
      if (finishedAt.isAfter(current)) break;
      final split = wasteRecyclerConfig.outputSplits[_random.nextInt(
        wasteRecyclerConfig.outputSplits.length,
      )];
      recyclerOutputOrganic += split.organic;
      recyclerOutputMineral += split.mineral;
      completedCycles += 1;
      producedOrganic += split.organic;
      producedMineral += split.mineral;
      recyclerCycleStartedAt = finishedAt;
      changed = true;
      if (recyclerOutputAmount + wasteRecyclerConfig.outputResourcesPerCycle >
          recyclerOutputCapacity) {
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
            recyclerOutputCapacity &&
        recyclerWasteTank >= recyclerWasteRequired &&
        energyUnits >= wasteRecyclerConfig.energyCostPerCycle) {
      recyclerWasteTank -= recyclerWasteRequired;
      energyUnits -= wasteRecyclerConfig.energyCostPerCycle;
      recyclerCycleStartedAt = current;
      changed = true;
    }
    if (completedCycles > 0) {
      reports.add(
        PtipoteMissionReport.system(
          message: 'Recycleur : $completedCycles cycle(s) terminé(s). '
              'Déchets traités : ${completedCycles * recyclerWasteRequired}. '
              'Énergie consommée : ${completedCycles * wasteRecyclerConfig.energyCostPerCycle}. '
              '+$producedOrganic Organique, +$producedMineral Minéral.',
          sourceBuildingId: 'recycler',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: 'Joueur',
          summary:
              'Recycleur : +$producedOrganic Organique, +$producedMineral Minéral.',
        ),
      );
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
      for (final stack in simulated.where(
        (stack) => stack.resource == entry.key,
      )) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        capacity += add;
      }

      while (remaining > 0 && freeSlots > 0) {
        final add = math.min(
          remaining,
          lisiereForageConfig.inventoryStackLimit,
        );
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

  ConstructionProject projectFor(String targetId) {
    final existing = constructionProjects[targetId];
    final currentLevel = _buildingLevel(targetId);
    final maxLevel = _projectMaxLevel(targetId);
    if (existing == null && currentLevel >= maxLevel) {
      return constructionProjects.putIfAbsent(
        targetId,
        () => ConstructionProject(
          projectId: 'project-$targetId',
          targetId: targetId,
          targetType: targetId,
          currentLevel: currentLevel,
          targetLevel: currentLevel,
          requirements: const <String, int>{},
          constructionDuration: Duration.zero,
          state: ConstructionProjectState.maxLevel,
        ),
      );
    }
    if (existing != null) {
      if (!existing.isInProgress && currentLevel >= maxLevel) {
        existing.currentLevel = currentLevel;
        existing.targetLevel = currentLevel;
        existing.state = ConstructionProjectState.maxLevel;
        return existing;
      }
      if (!existing.isInProgress &&
          existing.state == ConstructionProjectState.built &&
          existing.currentLevel == currentLevel) {
        final targetLevel = currentLevel + 1;
        existing.prepareNextLevel(
          targetLevel: targetLevel,
          requirements: _projectRequirements(targetId, targetLevel),
          constructionDuration: _projectDuration(targetId),
        );
      }
      return existing;
    }
    return constructionProjects.putIfAbsent(targetId, () {
      final targetLevel = currentLevel + 1;
      return ConstructionProject(
        projectId: 'project-$targetId',
        targetId: targetId,
        targetType: targetId,
        currentLevel: currentLevel,
        targetLevel: targetLevel,
        requirements: _projectRequirements(targetId, targetLevel),
        constructionDuration: _projectDuration(targetId),
      );
    });
  }

  Map<String, int> _projectRequirements(String targetId, int targetLevel) {
    if (targetId == 'housing') {
      return housingConfig.housingRequirementsForUnit(targetLevel).map(
            (resource, amount) => MapEntry(
              resource,
              resource == 'Minéral'
                  ? (amount * buildingConstructionConfig.mineralCostMultiplier)
                      .ceil()
                  : amount,
            ),
          );
    }
    return buildingConstructionConfig
        .project(targetId)
        .requirements(buildingConstructionConfig.mineralCostMultiplier);
  }

  Duration _projectDuration(String targetId) => Duration(
        minutes: targetId == 'housing'
            ? housingConfig.housingDurationMinutes
            : buildingConstructionConfig.project(targetId).durationMinutes,
      );

  int _buildingLevel(String targetId) => switch (targetId) {
        'fablab' => atelierLevel,
        'cuisine' => cuisineLevel,
        'atelier' => atelierLevel,
        'recycler' => recyclerLevel,
        'securityTower' => securityTowerLevel,
        'market' => marketLevel,
        'house' => houseLevel,
        'housing' => housingUnits,
        'plaineNursery' => plaineNurseryLevel,
        _ => 0,
      };

  int _projectMaxLevel(String targetId) => switch (targetId) {
        'fablab' => 1,
        'cuisine' => fablabConfig.cuisineMaxLevel,
        'atelier' => fablabConfig.atelierMaxLevel,
        'recycler' => wasteRecyclerConfig.recyclerMaxLevel,
        'securityTower' => 3,
        'market' => 5,
        'house' => housingConfig.houseMaxLevel,
        'housing' => 99,
        'plaineNursery' => 3,
        _ => 1,
      };

  Zone0ActionResult depositProjectMaterial(
    String targetId,
    String resource,
    int amount,
  ) {
    final project = projectFor(targetId);
    if (!project.canEditMaterials) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les matériaux ne sont plus modifiables.',
      );
    }
    final missing = project.missingFor(resource);
    final deposit = math.min(
      amount,
      math.min(missing, resourceAmount(resource)),
    );
    if (deposit <= 0) {
      return Zone0ActionResult(
        success: false,
        message: 'Aucun $resource à déposer.',
      );
    }
    removeResource(resource, deposit);
    project.depositedMaterials[resource] =
        (project.depositedMaterials[resource] ?? 0) + deposit;
    project.refreshState();
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$deposit $resource déposé.',
    );
  }

  Zone0ActionResult withdrawProjectMaterial(String targetId, String resource) {
    final project = projectFor(targetId);
    if (!project.canEditMaterials) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les travaux ont déjà commencé.',
      );
    }
    final amount = project.depositedMaterials[resource] ?? 0;
    if (amount <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun matériau à récupérer.',
      );
    }
    if (!hasInventoryCapacityFor(<String, int>{resource: amount})) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire insuffisant.',
      );
    }
    addResources(<String, int>{resource: amount});
    project.depositedMaterials.remove(resource);
    project.refreshState();
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$amount $resource rendu à la Maison.',
    );
  }

  Zone0ActionResult startConstructionProject(
    String targetId, {
    int? campHeartLevel,
  }) {
    if (targetId == 'securityTower' &&
        (campHeartLevel ?? 0) < securityTowerConfig.requiredCampHeartLevel) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Cœur du Camp doit atteindre le niveau ${securityTowerConfig.requiredCampHeartLevel}.',
      );
    }
    if (targetId == 'market') {
      if ((campHeartLevel ?? 0) < marketConfig.requiredCampHeartLevel) {
        return Zone0ActionResult(
          success: false,
          message:
              'Le Cœur du Camp doit atteindre le niveau ${marketConfig.requiredCampHeartLevel}.',
        );
      }
      if (currentPopulation < marketConfig.requiredPopulation) {
        return Zone0ActionResult(
          success: false,
          message: 'Population requise : ${marketConfig.requiredPopulation}.',
        );
      }
    }
    final project = projectFor(targetId);
    if (project.state == ConstructionProjectState.maxLevel) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce batiment est deja au niveau maximum.',
      );
    }
    if (!project.isReady) {
      return const Zone0ActionResult(
        success: false,
        message: 'Tous les matériaux sont requis.',
      );
    }
    final now = DateTime.now();
    project.startedAt = now;
    project.endsAt = now.add(project.constructionDuration);
    project.state = project.currentLevel == 0
        ? ConstructionProjectState.underConstruction
        : ConstructionProjectState.upgrading;
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Travaux lancés. Fin dans ${project.constructionDuration.inMinutes} min.',
    );
  }

  bool resolveConstructionProjects({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    if (communityConstructionThanks != null &&
        !communityConstructionThanks!.isActiveAt(current)) {
      communityConstructionThanks = null;
      changed = true;
    }
    for (final project in constructionProjects.values) {
      if (!project.isReadyToCompleteAt(current)) continue;
      _completeConstructionProject(project, current);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveBuildingsToFirebase());
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _completeConstructionProject(ConstructionProject project, DateTime now) {
    if (!project.completeAt(now)) return;
    switch (project.targetId) {
      case 'fablab':
        atelierLevel = project.currentLevel;
        fablabLevel = atelierLevel;
        cuisineLevel = math.max(cuisineLevel, 1);
        emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
        refreshKernelMissions();
      case 'cuisine':
        cuisineLevel = project.currentLevel;
      case 'atelier':
        atelierLevel = project.currentLevel;
        fablabLevel = atelierLevel;
      case 'recycler':
        recyclerLevel = project.currentLevel;
      case 'securityTower':
        securityTowerLevel = project.currentLevel;
        refugeSafety = math.max(
          refugeSafety,
          securityTowerConfig.initialSecurity,
        );
        ensureWeatherForecast();
      case 'market':
        marketLevel = project.currentLevel;
        emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
      case 'house':
        houseLevel = project.currentLevel;
        alcoveCapacity = math.max(
          alcoveCapacity,
          housingConfig.alcovesForHouseLevel(houseLevel),
        );
      case 'housing':
        housingUnits = project.currentLevel;
        housingCapacity = housingUnits * housingConfig.residentsPerHousingUnit;
      case 'plaineNursery':
        plaineNurseryLevel = project.currentLevel;
        emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
    }
    if (!project.notificationCreated) {
      final isFablabUnit = const <String>{
        'cuisine',
        'atelier',
        'recycler',
      }.contains(project.targetId);
      reports.add(
        PtipoteMissionReport.system(
          message:
              'Les travaux de ${buildingConstructionConfig.project(project.targetId).label} sont terminés. Niveau ${project.currentLevel}.',
          sourceBuildingId: project.targetId,
          mailbox: isFablabUnit
              ? Zone0MessageMailbox.fablab
              : Zone0MessageMailbox.companions,
          subject: 'Fin de chantier',
          concerned: 'Joueur',
          summary:
              '${buildingConstructionConfig.project(project.targetId).label} niveau ${project.currentLevel} est prêt.',
        ),
      );
      project.notificationCreated = true;
    }
  }

  Zone0ActionResult thankResidentsForHousing(String projectId) {
    final project = constructionProjects[projectId];
    if (project == null ||
        project.targetId != 'housing' ||
        project.completedAt == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun logement termine a remercier.',
      );
    }
    if (communityConstructionThanks?.sourceProjectId == projectId) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les habitants ont deja ete remercies.',
      );
    }
    if (bioBatteries < housingConfig.thanksBioBatteryCost) {
      return Zone0ActionResult(
        success: false,
        message:
            '${housingConfig.thanksBioBatteryCost} Bio-batteries requises.',
      );
    }
    bioBatteries -= housingConfig.thanksBioBatteryCost;
    final now = DateTime.now();
    communityConstructionThanks = CommunityConstructionThanks(
      bonusValue: housingConfig.thanksWellbeingBonus,
      startedAt: now,
      endsAt: now.add(Duration(hours: housingConfig.thanksDurationHours)),
      sourceProjectId: projectId,
    );
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Les habitants remercient le refuge : +${housingConfig.thanksWellbeingBonus} Bien-etre temporaire.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    unawaited(saveBuildingsToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Remerciement offert.',
    );
  }

  Zone0ActionResult startPTibugCreation(PTibugSpecies species) {
    if (!isPlaineNurseryBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis la Nurserie P’TIBUG.',
      );
    }
    final researchPatternId = 'ptibug-species-${species.name}';
    if (!activePTibugPatterns.contains(species) &&
        !isPTibugPatternActive(researchPatternId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern P’TIBUG non actif.',
      );
    }
    if (pTibugCreationOrder?.isActive == true) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Nurserie crée déjà un P’TIBUG.',
      );
    }
    final config = pTibugConfig.species[species]!;
    if (!hasResources(config.creationCost) ||
        energyUnits < config.creationEnergyCost ||
        bioBatteries < config.creationBioBatteryCost) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources, bio-batteries ou énergie insuffisantes.',
      );
    }
    removeResources(config.creationCost);
    energyUnits -= config.creationEnergyCost;
    bioBatteries -= config.creationBioBatteryCost;
    final now = DateTime.now();
    pTibugCreationOrder = PTibugCreationOrder(
      species: species,
      startedAt: now,
      endsAt: now.add(Duration(minutes: config.creationMinutes)),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Création ${config.displayName} lancée.',
    );
  }

  bool _hasPTibugData(Map<PTibugDataFamily, int> costs) {
    return costs.entries.every(
      (entry) =>
          (pTibugDataReserve[entry.key] ?? 0) >= math.max(0, entry.value),
    );
  }

  void _consumePTibugData(Map<PTibugDataFamily, int> costs) {
    for (final entry in costs.entries) {
      pTibugDataReserve[entry.key] =
          math.max(0, (pTibugDataReserve[entry.key] ?? 0) - entry.value);
    }
  }

  bool _resolvePTibugModuleCrafts(DateTime current) {
    var changed = false;
    for (final order
        in pTibugModuleCraftOrders.where((item) => item.isActive)) {
      if (order.endsAt.isAfter(current)) continue;
      order.completedAt = current;
      final instance = PTibugModuleInstance(
        id: 'ptibug-module-${order.id}',
        type: order.moduleType,
        createdAt: current,
      );
      pTibugModuleInstances.add(instance);
      reports.add(
        PtipoteMissionReport.system(
          message: 'Le module ${order.moduleType.displayName} est prêt.',
          sourceBuildingId: 'fablab',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: 'Le joueur',
          summary: 'Module P’TIBUG ${order.moduleType.displayName} créé.',
        ),
      );
      changed = true;
    }
    return changed;
  }

  Zone0ActionResult startPTibugModuleCraft(PTibugModuleType type) {
    if (atelierLevel < 1) {
      return const Zone0ActionResult(
        success: false,
        message: 'Atelier niveau 1 requis.',
      );
    }
    if (!isPTibugPatternActive('ptibug-module-${type.name}')) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern de Module non actif.',
      );
    }
    if (activePTibugModuleCraftOrder != null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Un Module P’TIBUG est déjà en fabrication.',
      );
    }
    final cost = pTibugConfig.moduleCraftCostFor(type);
    final energyCost = pTibugConfig.moduleCraftEnergyFor(type);
    if (!hasResources(cost) || energyUnits < energyCost) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources ou énergie insuffisantes.',
      );
    }
    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }
    energyUnits -= energyCost;
    final current = DateTime.now();
    pTibugModuleCraftOrders.add(
      PTibugModuleCraftOrder(
        id: current.microsecondsSinceEpoch.toString(),
        moduleType: type,
        startedAt: current,
        endsAt: current.add(
          Duration(minutes: pTibugConfig.moduleCraftMinutesFor(type)),
        ),
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Fabrication de ${type.displayName} lancée.',
    );
  }

  Zone0ActionResult applyPTibugPermanentTrait({
    required PTibug bug,
    required String traitId,
  }) {
    if (!pTibugs.contains(bug) || !isPlaineNurseryBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIBUG ou Nurserie indisponible.',
      );
    }
    if (bug.biologicalTraitId != null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce P’TIBUG possède déjà un Trait permanent.',
      );
    }
    final definition = pTibugConfig.traitDefinitionFor(traitId);
    final patternId = 'ptibug-trait-$traitId';
    final progress = pTibugPatternProgress[patternId];
    if (definition == null ||
        progress == null ||
        !definition.isActive ||
        !isPTibugPatternActive(patternId) ||
        progress.masteryLevel <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Pattern de Trait non maîtrisé.',
      );
    }
    final level = progress.masteryLevel.clamp(1, definition.maxLevel);
    final dataCost = definition.dataCostForLevel(level);
    final materialCost = definition.materialCostForLevel(level);
    final energyCost = definition.energyCostForLevel(level);
    if (dataCost.isEmpty || materialCost.isEmpty) {
      return const Zone0ActionResult(
        success: false,
        message: 'Coût de Trait à configurer dans le Dashboard.',
      );
    }
    if (!_hasPTibugData(dataCost) ||
        !hasResources(materialCost) ||
        energyUnits < energyCost) {
      return const Zone0ActionResult(
        success: false,
        message: 'Données, matériaux ou énergie insuffisants.',
      );
    }
    if (!removeResources(materialCost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Matériaux insuffisants.',
      );
    }
    _consumePTibugData(dataCost);
    energyUnits -= energyCost;
    bug.biologicalTraitId = traitId;
    bug.biologicalTraitLevel = level;
    emitKernelProgressEvent(KernelProgressEventType.ptibugTraitEquipped);
    reports.add(
      PtipoteMissionReport.system(
        message: '${_pTibugBiologicalName(bug)} reçoit un Trait permanent.',
        sourceBuildingId: 'plaineNursery',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Trait P’TIBUG',
        concerned: bug.displayName,
        summary: 'Trait ${definition.displayName} niveau $level appliqué.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Trait ${definition.displayName} appliqué.',
    );
  }

  Zone0ActionResult equipPTibugModuleInstance({
    required PTibug bug,
    required String moduleInstanceId,
  }) {
    final instance = pTibugModuleInstances
        .where((item) => item.id == moduleInstanceId)
        .firstOrNull;
    final equippedModules = pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id)
        .toList();
    if (instance == null ||
        instance.isEquipped ||
        !pTibugs.contains(bug) ||
        equippedModules.any((item) => item.type == instance.type) ||
        equippedModules.length >=
            pTibugConfig.moduleSlotsForLevel(plaineNurseryLevel)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Module indisponible ou aucun slot libre.',
      );
    }
    instance.equippedPTibugId = bug.id;
    if (!bug.equippedModuleInstanceIds.contains(instance.id)) {
      bug.equippedModuleInstanceIds.add(instance.id);
    }
    emitKernelProgressEvent(KernelProgressEventType.ptibugModuleEquipped);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'Module équipé.');
  }

  Zone0ActionResult unequipPTibugModuleInstance({
    required PTibug bug,
    required String moduleInstanceId,
  }) {
    final instance = pTibugModuleInstances
        .where((item) => item.id == moduleInstanceId)
        .firstOrNull;
    if (instance == null || instance.equippedPTibugId != bug.id) {
      return const Zone0ActionResult(
        success: false,
        message: 'Module non équipé sur ce P’TIBUG.',
      );
    }
    instance.equippedPTibugId = null;
    bug.equippedModuleInstanceIds.remove(instance.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'Module retiré.');
  }

  Zone0ActionResult fusePTibugModuleInstances({
    required String firstId,
    required String secondId,
  }) {
    final first =
        pTibugModuleInstances.where((item) => item.id == firstId).firstOrNull;
    final second =
        pTibugModuleInstances.where((item) => item.id == secondId).firstOrNull;
    if (first == null ||
        second == null ||
        first.id == second.id ||
        first.isEquipped ||
        second.isEquipped ||
        first.type != second.type ||
        first.qualityLevel != second.qualityLevel ||
        first.qualityLevel >= pTibugConfig.moduleMaxLevel) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ces Modules ne peuvent pas être fusionnés.',
      );
    }
    if (energyUnits < pTibugConfig.moduleFusionEnergyCost) {
      return const Zone0ActionResult(
        success: false,
        message: 'Énergie insuffisante pour la fusion.',
      );
    }
    energyUnits -= pTibugConfig.moduleFusionEnergyCost;
    pTibugModuleInstances.removeWhere(
      (item) => item.id == first.id || item.id == second.id,
    );
    final nextLevel = first.qualityLevel + 1;
    pTibugModuleInstances.add(
      PTibugModuleInstance(
        id: 'ptibug-module-${DateTime.now().microsecondsSinceEpoch}',
        type: first.type,
        qualityLevel: nextLevel,
        createdAt: DateTime.now(),
        source: 'fusion',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${first.type.displayName} niveau $nextLevel créé.',
    );
  }

  Zone0ActionResult encapsulatePTibug(PTibug bug) {
    final hasEquippedModuleInstances =
        pTibugModuleInstances.any((item) => item.equippedPTibugId == bug.id);
    if (!pTibugs.contains(bug) ||
        bug.assignedSlotIndex != null ||
        bug.storedResources.isNotEmpty ||
        bug.equippedModules.isNotEmpty ||
        bug.equippedModuleInstanceIds.isNotEmpty ||
        hasEquippedModuleInstances) {
      return const Zone0ActionResult(
        success: false,
        message: 'Récolte le stock et retire les Modules avant encapsulation.',
      );
    }
    if (energyUnits < pTibugConfig.capsuleEnergyCost) {
      return const Zone0ActionResult(
        success: false,
        message: 'Énergie insuffisante pour encapsuler ce P’TIBUG.',
      );
    }
    energyUnits -= pTibugConfig.capsuleEnergyCost;
    pTibugs.remove(bug);
    pTibugCapsules.add(
      PTibugCapsule(
        id: 'ptibug-capsule-${DateTime.now().microsecondsSinceEpoch}',
        species: bug.species,
        styleVariant: bug.styleVariant,
        displayName: _pTibugBiologicalName(bug),
        biologicalTraitId: bug.biologicalTraitId,
        biologicalTraitLevel: bug.biologicalTraitLevel,
        level: bug.level,
        xp: bug.xp,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Capsule P’TIBUG créée.',
    );
  }

  Zone0ActionResult decapsulatePTibug(String capsuleId) {
    final capsule =
        pTibugCapsules.where((item) => item.id == capsuleId).firstOrNull;
    if (capsule == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Capsule introuvable.',
      );
    }
    pTibugCapsules.remove(capsule);
    pTibugs.add(
      PTibug(
        id: 'ptibug-${DateTime.now().microsecondsSinceEpoch}',
        displayName: capsule.displayName,
        species: capsule.species,
        styleVariant: capsule.styleVariant,
        createdAt: DateTime.now(),
        level: capsule.level,
        xp: capsule.xp,
        biologicalTraitId: capsule.biologicalTraitId,
        biologicalTraitLevel: capsule.biologicalTraitLevel,
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'P’TIBUG décapsulé.');
  }

  bool resolvePTibugProduction({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    if (_resolvePTibugModuleCrafts(current)) {
      changed = true;
    }
    final creation = pTibugCreationOrder;
    if (creation != null &&
        creation.isActive &&
        !creation.endsAt.isAfter(current)) {
      final config = pTibugConfig.species[creation.species]!;
      pTibugs.add(
        PTibug(
          id: 'ptibug-${current.microsecondsSinceEpoch}',
          displayName: config.displayName,
          species: creation.species,
          styleVariant: config.styles[_random.nextInt(config.styles.length)],
          createdAt: current,
        ),
      );
      pTibugCreationOrder!.completedAt = current;
      reports.add(
        PtipoteMissionReport.system(
          message: '${config.displayName} est né dans la Nurserie.',
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Création P’TIBUG',
          concerned: config.displayName,
          summary: 'Création terminée.',
        ),
      );
      emitKernelProgressEvent(KernelProgressEventType.ptibugCreated);
      changed = true;
    }
    for (final bug in pTibugs.where((item) => item.assignedSlotIndex != null)) {
      final next = bug.nextProductionAt;
      if (next == null || next.isAfter(current)) {
        continue;
      }
      var cycleAt = next;
      var producedCycles = 0;
      while (!cycleAt.isAfter(current) &&
          bug.storedAmount < _pTibugCapacity(bug)) {
        final production = _pTibugProduction(bug);
        if (bug.storedAmount +
                production.values.fold(0, (total, value) => total + value) >
            _pTibugCapacity(bug)) {
          break;
        }
        production.forEach((resource, amount) {
          bug.storedResources[resource] =
              (bug.storedResources[resource] ?? 0) + amount;
        });
        bug.xp += pTibugConfig.xpPerCycle;
        producedCycles += 1;
        cycleAt = cycleAt.add(_pTibugCycleDuration(bug));
      }
      bug.nextProductionAt = cycleAt;
      if (bug.storedAmount >= _pTibugCapacity(bug) && !bug.stockFullNotified) {
        bug.stockFullNotified = true;
        reports.add(
          PtipoteMissionReport.system(
            message: '${bug.displayName} a atteint sa capacité de stockage.',
            sourceBuildingId: 'plaineNursery',
            mailbox: Zone0MessageMailbox.companions,
            subject: 'Stock P’TIBUG plein',
            concerned: bug.displayName,
            summary: 'Production prête à être récoltée.',
          ),
        );
        changed = true;
      }
      if (producedCycles > 0) changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  int get pTibugActiveSlots => pTibugConfig.slotsForLevel(plaineNurseryLevel);

  PTibugModuleCraftOrder? get activePTibugModuleCraftOrder =>
      pTibugModuleCraftOrders.where((item) => item.isActive).firstOrNull;

  String pTibugBiologicalNameFor(PTibug bug) => _pTibugBiologicalName(bug);

  int pTibugCapacityFor(PTibug bug) => _pTibugCapacity(bug);

  Duration pTibugCycleDurationFor(PTibug bug) => _pTibugCycleDuration(bug);

  Map<String, int> pTibugProductionFor(PTibug bug) =>
      Map<String, int>.unmodifiable(_pTibugProduction(bug));

  Duration _pTibugCycleDuration(PTibug bug) => Duration(
        minutes: math.max(
          1,
          (pTibugConfig.productionCycleMinutes *
                  (1 -
                      _pTibugModuleEffect(
                        bug,
                        PTibugModuleType.ailes,
                        pTibugConfig.wingsCycleReductionByLevel,
                      )))
              .round(),
        ),
      );

  int _pTibugCapacity(PTibug bug) =>
      pTibugConfig.carryingCapacity +
      _pTibugModuleEffect(
        bug,
        PTibugModuleType.reservoir,
        pTibugConfig.reservoirCapacityBonusByLevel,
      ).round();

  int _pTibugModuleLevel(PTibug bug, PTibugModuleType type) {
    final levels = pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id && item.type == type)
        .map((item) => item.qualityLevel);
    if (levels.isNotEmpty) return levels.reduce(math.max);
    return bug.hasModule(type) ? 1 : 0;
  }

  double _pTibugModuleEffect(
    PTibug bug,
    PTibugModuleType type,
    Map<int, num> effects,
  ) {
    final level = _pTibugModuleLevel(bug, type);
    return (effects[level] ?? 0).toDouble();
  }

  String _pTibugBiologicalName(PTibug bug) {
    final species = pTibugConfig.species[bug.species]!.displayName;
    final trait = bug.biologicalTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!);
    return trait == null || bug.biologicalTraitLevel <= 0
        ? species
        : '$species ${trait.displayName} ${bug.biologicalTraitLevel}';
  }

  Map<String, int> _pTibugProduction(PTibug bug) {
    final output = <String, int>{};
    void add(String resource, int amount) =>
        output[resource] = (output[resource] ?? 0) + amount;
    switch (bug.species) {
      case PTibugSpecies.scarabe:
        add('Minéral', 3);
      case PTibugSpecies.hyme:
        add('Organique', 3);
      case PTibugSpecies.arac:
        final variants = <Map<String, int>>[
          <String, int>{'Organique': 3},
          <String, int>{'Minéral': 3},
          <String, int>{'Déchets': 3},
          <String, int>{'Organique': 2, 'Minéral': 1},
          <String, int>{'Organique': 2, 'Déchets': 1},
          <String, int>{'Minéral': 2, 'Déchets': 1},
        ];
        variants[_random.nextInt(variants.length)].forEach(
          (resource, amount) => add(resource, amount),
        );
    }
    final trait = bug.traitDataId == null
        ? null
        : pTibugTraitData
            .where((item) => item.id == bug.traitDataId)
            .firstOrNull;
    if (trait != null) {
      final definition = pTibugConfig.traitDefinitionFor(trait.definitionId);
      final effects =
          definition?.productionFor(trait.grade) ?? const <String, int>{};
      effects.forEach(add);
    }
    final permanentTrait = bug.biologicalTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!);
    if (permanentTrait != null) {
      permanentTrait.productionForLevel(bug.biologicalTraitLevel).forEach(add);
    }
    final claws = _pTibugModuleEffect(
      bug,
      PTibugModuleType.pinces,
      pTibugConfig.clawProductionBonusByLevel,
    ).round();
    if (claws > 0) {
      switch (bug.species) {
        case PTibugSpecies.scarabe:
          add('Minéral', claws);
        case PTibugSpecies.hyme:
          add('Organique', claws);
        case PTibugSpecies.arac:
          add(
            <String>['Organique', 'Minéral', 'Déchets'][_random.nextInt(3)],
            claws,
          );
      }
    }
    final biome = pTibugConfig.biomes[bug.biome];
    biome?.localProductionBonus[bug.species]?.forEach(add);
    return output;
  }

  Zone0ActionResult assignPTibugSlot(PTibug bug, int slot) {
    if (slot < 0 ||
        slot >= pTibugActiveSlots ||
        pTibugs.any(
          (item) => item.id != bug.id && item.assignedSlotIndex == slot,
        )) {
      return const Zone0ActionResult(
        success: false,
        message: 'Slot indisponible.',
      );
    }
    bug.assignedSlotIndex = slot;
    bug.nextProductionAt ??= DateTime.now().add(_pTibugCycleDuration(bug));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'P’TIBUG installé.');
  }

  Zone0ActionResult removePTibugSlot(PTibug bug) {
    bug.assignedSlotIndex = null;
    bug.nextProductionAt = null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'P’TIBUG rangé dans la Nurserie.',
    );
  }

  Zone0ActionResult collectPTibugProduction() {
    final output = <String, int>{};
    for (final bug in pTibugs) {
      bug.storedResources.forEach(
        (key, value) => output[key] = (output[key] ?? 0) + value,
      );
    }
    if (output.isEmpty || !hasInventoryCapacityFor(output)) {
      return Zone0ActionResult(
        success: false,
        message: output.isEmpty
            ? 'Aucune production prête.'
            : 'Inventaire insuffisant.',
      );
    }
    addResources(output);
    for (final bug in pTibugs) {
      bug.storedResources.clear();
      bug.stockFullNotified = false;
    }
    emitKernelProgressEvent(KernelProgressEventType.ptibugProductionCollected);
    if (output.containsKey('Mycélium') &&
        (kernelEventCounts[KernelProgressEventType.firstMyceliumProduced] ??
                0) ==
            0) {
      emitKernelProgressEvent(KernelProgressEventType.firstMyceliumProduced);
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Production récupérée.',
    );
  }

  Zone0ActionResult collectPTibugProductionFor(PTibug bug) {
    if (bug.storedResources.isEmpty) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune production prête.',
      );
    }
    final output = Map<String, int>.from(bug.storedResources);
    if (!hasInventoryCapacityFor(output)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire insuffisant.',
      );
    }
    addResources(output);
    bug.storedResources.clear();
    bug.stockFullNotified = false;
    bug.nextProductionAt ??= DateTime.now().add(_pTibugCycleDuration(bug));
    emitKernelProgressEvent(KernelProgressEventType.ptibugProductionCollected);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Production de ${bug.displayName} récupérée.',
    );
  }

  Zone0ActionResult equipPTibugTrait(PTibug bug, PTibugTraitData data) {
    bug.traitDataId = data.id;
    emitKernelProgressEvent(KernelProgressEventType.ptibugTraitEquipped);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Donnée de trait attribuée.',
    );
  }

  Zone0ActionResult fusePTibugTraitData(
    PTibugTraitData first,
    PTibugTraitData second,
  ) {
    if (first.id == second.id ||
        first.definitionId != second.definitionId ||
        first.grade != second.grade ||
        first.grade == PTibugTraitGrade.avance ||
        pTibugs.any(
          (bug) => bug.traitDataId == first.id || bug.traitDataId == second.id,
        )) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ces Données ne peuvent pas être fusionnées.',
      );
    }
    pTibugTraitData.removeWhere(
      (item) => item.id == first.id || item.id == second.id,
    );
    pTibugTraitData.add(
      PTibugTraitData(
        id: 'trait-${DateTime.now().microsecondsSinceEpoch}',
        definitionId: first.definitionId,
        grade: PTibugTraitGrade.values[first.grade.index + 1],
      ),
    );
    emitKernelProgressEvent(KernelProgressEventType.traitDataFused);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'Fusion réussie.');
  }

  Zone0ActionResult equipPTibugModule(PTibug bug, PTibugModuleType module) {
    if (!unlockedPTibugModules.contains(module) ||
        bug.hasModule(module) ||
        bug.equippedModules.length >=
            pTibugConfig.moduleSlotsForLevel(plaineNurseryLevel)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Module indisponible ou aucun slot libre.',
      );
    }
    bug.equippedModules.add(module);
    emitKernelProgressEvent(KernelProgressEventType.ptibugModuleEquipped);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'Module équipé.');
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
        .add(
          Duration(minutes: securityTowerConfig.manualRechargeCooldownMinutes),
        )
        .difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Zone0ActionResult manuallyRechargeTower() {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Tour non construite.',
      );
    }
    final remaining = towerManualRechargeRemaining();
    if (remaining > Duration.zero) {
      return Zone0ActionResult(
        success: false,
        message: 'Balises disponibles dans ${remaining.inMinutes + 1} min.',
      );
    }
    refugeSafety = math.min(
      securityTowerConfig.maxSecurity,
      refugeSafety +
          securityTowerConfig.manualRechargeGainForLevel(securityTowerLevel),
    );
    lastManualTowerRechargeAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '+${securityTowerConfig.manualRechargeGainForLevel(securityTowerLevel)} Sécurité.',
    );
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
        success: false,
        message: 'Tour non construite.',
      );
    }
    resolveDueTowerMissions();
    // Each secured biome, plus the camp, owns its own surveillance slot.
    final activeCount = towerMissions
        .where(
          (mission) =>
              mission.status == TowerMissionStatus.active &&
              mission.patrolBiome == patrolBiome,
        )
        .length;
    if (activeCount >= securityTowerSlots) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun slot libre.',
      );
    }
    if (isUnavailableForTower(figurine)) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE occupé.',
      );
    }
    if (vitalityFor(figurine) < ptipoteStatsConfig.minimumMissionVitality) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE trop fatigué.',
      );
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
        securityGain: ticks *
            securityTowerConfig.securityGainForLevel(securityTowerLevel),
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
    if (recipe.craftSection != CraftSection.cuisine) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette recette se fabrique dans l’Atelier.',
      );
    }
    if (!isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis le Fablab pour utiliser la Cuisine.',
      );
    }

    final requirements = _recipeRequirementsMessage(recipe);
    if (requirements != null) {
      return Zone0ActionResult(success: false, message: requirements);
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
    reports.add(
      PtipoteMissionReport.system(
        message: '${recipe.displayName} préparé.',
        sourceBuildingId: 'cuisine',
        mailbox: Zone0MessageMailbox.fablab,
        subject: 'Fin de craft',
        concerned: 'Joueur',
        summary: '${recipe.resultAmount} ${recipe.resultItem} préparé.',
      ),
    );
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

  List<CraftRecipe> get availableConsumableRecipes => craftConfig.recipes
      .where(
        (recipe) =>
            recipe.isConsumable && resourceAmount(recipe.resultItem) > 0,
      )
      .toList();

  CraftRecipe? consumableRecipeForItem(String item) {
    for (final recipe in craftConfig.recipes) {
      if (recipe.isConsumable && recipe.resultItem == item) return recipe;
    }
    return null;
  }

  Zone0ActionResult consumeConsumable(
    PtipoteFigurine figurine,
    CraftRecipe recipe,
  ) {
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
      return Zone0ActionResult(
        success: false,
        message: '${recipe.resultItem} indisponible.',
      );
    }
    final previousMood = _moodLabelForValues(
      hunger: hungerFor(figurine),
      rest: restOverrides[figurine.id] ?? ptipoteStatsConfig.maxRest,
      figurineId: figurine.id,
    );
    hungerOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxOverfedHunger,
      hungerFor(figurine) + recipe.hungerRestore,
    );
    vitalityOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxVitality,
      vitalityFor(figurine) + recipe.vitalityRestore,
    );
    emitKernelProgressEvent(KernelProgressEventType.ptipoteFed);
    final nextMood = _moodLabelForValues(
      hunger: hungerFor(figurine),
      rest: restOverrides[figurine.id] ?? ptipoteStatsConfig.maxRest,
      figurineId: figurine.id,
    );
    if (previousMood != 'Heureux' && nextMood == 'Heureux') {
      emitKernelProgressEvent(KernelProgressEventType.ptipoteHappy);
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${figurine.displayName} reçoit ${recipe.resultItem} (+${recipe.hungerRestore} faim, +${recipe.vitalityRestore} vitalité).',
    );
  }

  Zone0ActionResult consumeSimpleMeal(PtipoteFigurine figurine) =>
      consumeConsumable(figurine, craftConfig.simpleMealRecipe);

  String missingResourcesLabel(Map<String, int> costs) {
    final missing = costs.entries
        .map(
          (entry) => MapEntry(
            entry.key,
            math.max(0, entry.value - resourceAmount(entry.key)),
          ),
        )
        .where((entry) => entry.value > 0)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(', ');
    return missing.isEmpty ? 'Ressources disponibles.' : 'Il manque $missing.';
  }

  Future<void> loadFromFirebase() async {
    if (_loadedFromFirebase) return;
    final user = await _currentUser();
    if (user == null) return;
    await RemoteGameConfigService.instance.start();
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
                  (stack) => stack.resource.isNotEmpty && stack.amount > 0,
                ),
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
      final wellRestedData = data['wellRestedRewardedIds'];
      if (wellRestedData is List) {
        wellRestedRewardedIds
          ..clear()
          ..addAll(wellRestedData.map((id) => '$id'));
      }

      final restingData = data['manualRestingIds'];
      if (restingData is List) {
        manualRestingIds
          ..clear()
          ..addAll(restingData.map((id) => '$id'));
      }
      final waitingForBedData = data['waitingForBedIds'];
      if (waitingForBedData is List) {
        waitingForBedIds
          ..clear()
          ..addAll(waitingForBedData.map((id) => '$id'));
      }
      final hatchedData = data['hatchedPtipoteIds'];
      if (hatchedData is List) {
        hatchedPtipoteIds
          ..clear()
          ..addAll(hatchedData.map((id) => '$id'));
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
          workshopOrdersData.whereType<Map>().map(
                WorkshopCraftOrder.fromFirebase,
              ),
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
          ..addAll(
            (marketData['stock'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (item) => Zone0InventoryStack(
                    resource: '${item['resource'] ?? ''}',
                    amount: _readInt(item['amount']),
                  ),
                )
                .where((item) => item.resource.isNotEmpty && item.amount > 0),
          );
        marketRequests
          ..clear()
          ..addAll(
            (marketData['requests'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(MarketCustomerRequest.fromFirebase),
          );
        marketNextSaleAt = _readDate(marketData['nextSaleAt']);
        marketLastWorkTickAt = _readDate(marketData['lastWorkTickAt']);
        marketAssignedPtipoteId = marketData['assignedPtipoteId'] as String?;
        marketAssignedPtipoteName =
            marketData['assignedPtipoteName'] as String?;
        marketValueRemainder = _readInt(marketData['valueRemainder']);
        marketBioBatteriesEarned = _readInt(marketData['bioBatteriesEarned']);
        merchantAvailableUntil = _readDate(
          marketData['merchantAvailableUntil'],
        );
        merchantNextArrivalAt = _readDate(marketData['merchantNextArrivalAt']);
        merchantVisitsDayKey = '${marketData['merchantVisitsDayKey'] ?? ''}';
        merchantVisitsToday = _readInt(marketData['merchantVisitsToday']);
        merchantOffers
          ..clear()
          ..addAll(
            (marketData['merchantOffers'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (item) => MerchantOffer(
                    planName: '${item['planName'] ?? ''}',
                    price: _readInt(item['price']),
                    purchased: item['purchased'] == true,
                    pTibugSpecies: item['ptibugSpecies'] == null
                        ? null
                        : ForageMission._enumByName(
                            PTibugSpecies.values,
                            '${item['ptibugSpecies']}',
                            PTibugSpecies.scarabe,
                          ),
                  ),
                )
                .where((item) => item.planName.isNotEmpty),
          );
      }

      final localSecurityData = data['biomeSecurity'];
      if (localSecurityData is Map) {
        for (final biome in ForageBiome.values) {
          final value = localSecurityData[biome.name];
          if (value is Map) {
            biomeSecurity[biome] = BiomeSecurityState.fromFirebase(
              biome,
              value,
            );
          }
        }
      }
      final explorationData = data['explorationMissions'];
      if (explorationData is List) {
        explorationMissions
          ..clear()
          ..addAll(
            explorationData.whereType<Map>().map(
                  BiomeExplorationMission.fromFirebase,
                ),
          );
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

      final weatherData = data['weather'];
      if (weatherData is Map) {
        weatherScheduleDayKey = '${weatherData['dayKey'] ?? ''}';
        weatherEventsToday = _readInt(weatherData['eventsToday']);
        nextWeatherEligibleAt = _readDate(weatherData['nextEligibleAt']);
        processedManualWeatherTriggerIds
          ..clear()
          ..addAll(
            (weatherData['processedManualTriggerIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        weatherAlerts
          ..clear()
          ..addAll(
            (weatherData['alerts'] as List? ?? const []).whereType<Map>().map(
                  WeatherAlert.fromFirebase,
                ),
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
        plaineMissionsCompleted = _readInt(
          kernelData['plaineMissionsCompleted'],
        );
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
          ..addAll(
            (kernelData['discoveredPlanIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        readyKernelPlanIds
          ..clear()
          ..addAll(
            (kernelData['readyPlanIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        activeKernelPlanIds
          ..clear()
          ..addAll(
            (kernelData['activePlanIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        kernelProgressHistory
          ..clear()
          ..addAll(
            (kernelData['progressHistory'] as List? ?? const [])
                .whereType<Map>()
                .map(KernelProgressHistoryEntry.fromFirebase),
          );
        final completedData = kernelData['completedMissionIds'];
        if (completedData is List) {
          completedKernelMissionIds
            ..clear()
            ..addAll(completedData.map((id) => '$id'));
        }
        dismissedKernelMissionIds
          ..clear()
          ..addAll(
            (kernelData['dismissedMissionIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        viewedKernelMissionIds
          ..clear()
          ..addAll(
            (kernelData['viewedMissionIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
        notifiedKernelMissionIds
          ..clear()
          ..addAll(
            (kernelData['notifiedMissionIds'] as List? ?? const []).map(
              (id) => '$id',
            ),
          );
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
        lastWasteGenerationAt = _readDate(
          recyclerData['lastWasteGenerationAt'],
        );
      }
      final ptibugData = data['ptibug'];
      if (ptibugData is Map) {
        plaineNurseryLevel = _readInt(ptibugData['nurseryLevel']).clamp(0, 3);
        activePTibugPatterns
          ..clear()
          ..addAll(
            (ptibugData['activePatterns'] as List? ?? const <dynamic>[]).map(
              (name) => ForageMission._enumByName(
                PTibugSpecies.values,
                '$name',
                PTibugSpecies.scarabe,
              ),
            ),
          );
        starterPTibugChoiceMade = ptibugData['starterChoiceMade'] == true ||
            activePTibugPatterns.isNotEmpty;
        pTibugs
          ..clear()
          ..addAll(
            (ptibugData['items'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibug.fromFirebase),
          );
        pTibugTraitData
          ..clear()
          ..addAll(
            (ptibugData['traitData'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugTraitData.fromFirebase),
          );
        unlockedPTibugModules
          ..clear()
          ..addAll(
            (ptibugData['unlockedModules'] as List? ?? const <dynamic>[]).map(
              (value) => ForageMission._enumByName(
                PTibugModuleType.values,
                '$value',
                PTibugModuleType.reservoir,
              ),
            ),
          );
        final dataReserve =
            ptibugData['dataReserve'] as Map? ?? const <dynamic, dynamic>{};
        for (final family in PTibugDataFamily.values) {
          pTibugDataReserve[family] = _readInt(dataReserve[family.name]);
        }
        pTibugDataCells
          ..clear()
          ..addAll(
            (ptibugData['dataCells'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugDataCell.fromFirebase),
          );
        pTibugPatternProgress
          ..clear()
          ..addEntries(
            (ptibugData['patternProgress'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugPatternProgress.fromFirebase)
                .where((item) => item.patternId.isNotEmpty)
                .map((item) => MapEntry(item.patternId, item)),
          );
        pTibugModuleInstances
          ..clear()
          ..addAll(
            (ptibugData['moduleInstances'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugModuleInstance.fromFirebase),
          );
        pTibugModuleCraftOrders
          ..clear()
          ..addAll(
            (ptibugData['moduleCraftOrders'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugModuleCraftOrder.fromFirebase),
          );
        pTibugCapsules
          ..clear()
          ..addAll(
            (ptibugData['capsules'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugCapsule.fromFirebase),
          );
        final creationData = ptibugData['creation'];
        pTibugCreationOrder = creationData is Map
            ? PTibugCreationOrder.fromFirebase(creationData)
            : null;
      }

      final buildingsData = data['buildings'];
      if (buildingsData is Map) {
        final fablabData = buildingsData['fablab'];
        if (fablabData is Map) {
          fablabLevel = _readInt(
            fablabData['currentLevel'],
          ).clamp(0, fablabConfig.fablabMaxLevel);
          atelierLevel = _readInt(
            fablabData['atelierLevel'],
            fallback: fablabLevel,
          ).clamp(0, fablabConfig.fablabMaxLevel);
          cuisineLevel = _readInt(
            fablabData['cuisineLevel'],
            fallback: fablabLevel > 0 ? 1 : 0,
          ).clamp(0, fablabConfig.fablabMaxLevel);
        }
        final towerData = buildingsData['securityTower'];
        if (towerData is Map) {
          securityTowerLevel = _readInt(towerData['currentLevel']).clamp(0, 3);
        }
        final marketBuildingData = buildingsData['market'];
        if (marketBuildingData is Map) {
          marketLevel = _readInt(
            marketBuildingData['currentLevel'],
          ).clamp(0, 5);
        }
        final houseData = buildingsData['house'];
        if (houseData is Map) {
          houseLevel = _readInt(
            houseData['currentLevel'],
            fallback: 1,
          ).clamp(1, housingConfig.houseMaxLevel);
          alcoveCapacity = _readInt(
            houseData['alcoveCapacity'],
            fallback: alcoveCapacity,
          ).clamp(1, 8);
        }
        final housingData = buildingsData['housing'];
        if (housingData is Map) {
          housingUnits = _readInt(housingData['units']);
          // Capacity is derived from real, aggregated housing units. Older
          // builds saved a temporary population-sized fallback here.
          housingCapacity =
              housingUnits * housingConfig.residentsPerHousingUnit;
          communityConstructionThanks =
              CommunityConstructionThanks.fromFirebase(housingData['thanks']);
        }
        final projectData = buildingsData['projects'];
        if (projectData is Map) {
          constructionProjects
            ..clear()
            ..addEntries(
              projectData.entries.whereType<MapEntry>().map(
                    (entry) => MapEntry(
                      '${entry.key}',
                      ConstructionProject.fromFirebase(entry.value as Map),
                    ),
                  ),
            );
        }
      }
      // Migration for saves created before the Fablab units were independent.
      if (atelierLevel == 0 && fablabLevel > 0) atelierLevel = fablabLevel;
      if (cuisineLevel == 0 && atelierLevel > 0) cuisineLevel = 1;
      // Old saves predate independent Fablab units and construction projects.
      // Keep every acquired level, then let a future project target the next
      // level. No material is retroactively charged or discarded.
      recyclerLevel = recyclerLevel.clamp(
        0,
        wasteRecyclerConfig.recyclerMaxLevel,
      );
      securityTowerLevel = securityTowerLevel.clamp(0, 3);
      marketLevel = marketLevel.clamp(0, 5);
      // New saves always expose the real number of places built. Do not keep
      // the former migration fallback equal to the current population.
      housingCapacity = housingUnits * housingConfig.residentsPerHousingUnit;
      alcoveCapacity = math.max(
        alcoveCapacity,
        housingConfig.alcovesForHouseLevel(houseLevel),
      );
      refugeSafety = _readInt(
        data['campSecurity'],
      ).clamp(0, securityTowerConfig.maxSecurity);
      final towerAssignedData = data['towerAssignedIds'];
      if (towerAssignedData is List) {
        towerAssignedIds
          ..clear()
          ..addAll(towerAssignedData.map((id) => '$id'));
      }
      lastSimulationAt =
          _readDate(data['lastSimulationAt']) ?? _readDate(data['updatedAt']);
      lastManualTowerRechargeAt = _readDate(data['lastManualTowerRechargeAt']);

      final migratedPTibugState = _migratePTibugScientificState();
      _loadedFromFirebase = true;
      resolveConstructionProjects();
      if (migratedPTibugState) {
        unawaited(saveRuntimeToFirebase());
      }
    });
  }

  /// Keeps saves made before data cells, permanent traits and module instances.
  /// The migration only adds compatibility data; it never removes player items.
  bool _migratePTibugScientificState() {
    var changed = false;
    final now = DateTime.now();
    for (final pattern in pTibugConfig.researchPatterns.values) {
      final legacySpeciesIsActive = pattern.linkedSpecies != null &&
          activePTibugPatterns.contains(pattern.linkedSpecies);
      final progress = pTibugPatternProgress.putIfAbsent(pattern.id, () {
        changed = true;
        return PTibugPatternProgress(
          patternId: pattern.id,
          state: legacySpeciesIsActive
              ? PTibugPatternState.active
              : PTibugPatternState.unknown,
          masteryLevel: legacySpeciesIsActive ? 1 : 0,
          discoveredAt: legacySpeciesIsActive ? now : null,
          activatedAt: legacySpeciesIsActive ? now : null,
        );
      });
      if (legacySpeciesIsActive && progress.masteryLevel == 0) {
        progress
          ..masteryLevel = 1
          ..state = PTibugPatternState.active
          ..discoveredAt ??= now
          ..activatedAt ??= now;
        changed = true;
      }
    }

    for (final bug in pTibugs) {
      if (bug.biologicalTraitId == null && bug.traitDataId != null) {
        final legacyTrait = pTibugTraitData
            .where((item) => item.id == bug.traitDataId)
            .firstOrNull;
        if (legacyTrait != null) {
          final definition = pTibugConfig.traitDefinitionFor(
            legacyTrait.definitionId,
          );
          bug
            ..biologicalTraitId = legacyTrait.definitionId
            ..biologicalTraitLevel = legacyTrait.grade.index + 1;
          if (definition != null) {
            bug.displayName = _pTibugBiologicalName(bug);
          }
          changed = true;
        }
      }
      for (final type in bug.equippedModules) {
        final existing = pTibugModuleInstances.where(
          (item) => item.equippedPTibugId == bug.id && item.type == type,
        );
        if (existing.isNotEmpty) continue;
        final instance = PTibugModuleInstance(
          id: 'legacy-module-${bug.id}-${type.name}',
          type: type,
          equippedPTibugId: bug.id,
          createdAt: now,
          source: 'migration',
        );
        pTibugModuleInstances.add(instance);
        bug.equippedModuleInstanceIds.add(instance.id);
        changed = true;
      }
    }
    return changed;
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
    final totalVitalityCost = vitalityCostByMember.values.fold(
      0,
      (total, cost) => total + cost,
    );
    final totalXpGain = xpGainByMember.values.fold(
      0,
      (total, xp) => total + xp,
    );
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
        success: false,
        message: 'La Tour est nécessaire pour explorer.',
      );
    }
    final adjacentSecurity = adjacentBiomeSecurityFor(biome);
    if (adjacentSecurity < towerOperationsConfig.biomeRevealSecurityThreshold) {
      return Zone0ActionResult(
        success: false,
        message:
            'La sécurité moyenne des biomes adjacents doit atteindre ${towerOperationsConfig.biomeRevealSecurityThreshold}%.',
      );
    }
    final state = biomeSecurity[biome]!;
    if (state.status == BiomeDiscoveryStatus.unlocked) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce biome est déjà disponible en Lisière.',
      );
    }
    if (isBiomeExploring(biome) || figurines.isEmpty) {
      return const Zone0ActionResult(
        success: false,
        message: 'Exploration indisponible.',
      );
    }
    if (figurines.any(isUnavailableForTower)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Un P’TIPOTE choisi est occupé.',
      );
    }
    final now = DateTime.now();
    explorationMissions.add(
      BiomeExplorationMission(
        id: 'exploration-${now.microsecondsSinceEpoch}',
        biome: biome,
        memberIds: figurines.map((item) => item.id).toList(),
        memberNames: figurines.map((item) => item.displayName).toList(),
        endTime: now.add(
          Duration(
            minutes: math.max(
              1,
              (durationHours * 60 / lisiereForageConfig.forageTimeScale)
                  .round(),
            ),
          ),
        ),
        explorationProgressGain: durationHours * 10,
      ),
    );
    state.status = BiomeDiscoveryStatus.exploring;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Exploration de ${lisiereForageConfig.biomes[biome]!.label} lancée.',
    );
  }

  Zone0ActionResult startBiomePatrol({
    required ForageBiome biome,
    required PtipoteFigurine figurine,
    required TowerMissionPlan plan,
  }) {
    if (!isBiomeUnlocked(biome)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Termine d’abord l’exploration.',
      );
    }
    final result = startTowerMission(
      figurine: figurine,
      plan: plan,
      patrolBiome: biome,
    );
    if (!result.success) return result;
    reports.add(
      PtipoteMissionReport.system(
        message:
            '${figurine.displayName} sécurise les abords de ${lisiereForageConfig.biomes[biome]!.label}.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${figurine.displayName} est en ronde locale. Le gain sera appliqué au retour.',
    );
  }

  void resolveTowerOperations({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    for (final mission in explorationMissions.where(
      (item) => item.isActive && !item.endTime.isAfter(current),
    )) {
      mission.completedAt = current;
      final state = biomeSecurity[mission.biome]!;
      state.explorationProgress = math.min(
        100,
        state.explorationProgress + mission.explorationProgressGain,
      );
      state.status = state.explorationProgress >= 100
          ? BiomeDiscoveryStatus.unlocked
          : BiomeDiscoveryStatus.discovered;
      state.lastMissionAt = current;
      reports.add(
        PtipoteMissionReport.system(
          message: state.status == BiomeDiscoveryStatus.unlocked
              ? '${mission.memberNames.join(', ')} a découvert ${lisiereForageConfig.biomes[mission.biome]!.label}. Le biome est disponible en Lisière.'
              : '${mission.memberNames.join(', ')} progresse dans l’exploration de ${lisiereForageConfig.biomes[mission.biome]!.label} : ${state.explorationProgress}%.',
        ),
      );
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
                elapsedHours * towerOperationsConfig.localSecurityDecayPerHour,
          );
          state.lastDecayAt = current;
          changed = true;
        }
      }
    }
    changed = _resolveMerchantSchedule(current) || changed;
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  String _merchantDayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  void _resetMerchantVisitDay(DateTime current) {
    final key = _merchantDayKey(current);
    if (merchantVisitsDayKey == key) return;
    merchantVisitsDayKey = key;
    merchantVisitsToday = 0;
  }

  bool _resolveMerchantSchedule(DateTime current) {
    var changed = false;
    final previousDayKey = merchantVisitsDayKey;
    _resetMerchantVisitDay(current);
    if (merchantVisitsDayKey != previousDayKey) changed = true;

    final activeUntil = merchantAvailableUntil;
    if (activeUntil != null) {
      final maximumVisitEnd = current.add(
        Duration(hours: towerOperationsConfig.merchantPresenceHours),
      );
      if (activeUntil.isAfter(maximumVisitEnd)) {
        merchantAvailableUntil = maximumVisitEnd;
        changed = true;
      }
    }

    if (merchantAvailableUntil != null &&
        !current.isBefore(merchantAvailableUntil!)) {
      _finishMerchantVisit(
        current,
        message: 'Le Sourcier est reparti. Il reviendra plus tard.',
      );
      return true;
    }

    if (merchantAvailableUntil == null && merchantNextArrivalAt == null) {
      merchantNextArrivalAt = _nextMerchantArrivalAfter(current);
      changed = true;
    }
    if (merchantAvailableUntil == null &&
        merchantNextArrivalAt != null &&
        !current.isBefore(merchantNextArrivalAt!)) {
      _startMerchantVisit(current);
      changed = true;
    }
    return changed;
  }

  DateTime _nextMerchantArrivalAfter(DateTime current) {
    _resetMerchantVisitDay(current);
    if (merchantVisitsToday >= towerOperationsConfig.merchantMaxVisitsPerDay) {
      final tomorrow = DateTime(current.year, current.month, current.day + 1);
      return tomorrow.add(
        Duration(hours: towerOperationsConfig.merchantMinimumGapHours),
      );
    }
    final spread = towerOperationsConfig.merchantRandomGapAdditionalHours;
    final extraHours = spread <= 0
        ? 0
        : math.Random(current.microsecondsSinceEpoch).nextInt(spread + 1);
    return current.add(
      Duration(
        hours: towerOperationsConfig.merchantMinimumGapHours + extraHours,
      ),
    );
  }

  void _startMerchantVisit(DateTime current) {
    _resetMerchantVisitDay(current);
    if (merchantVisitsToday >= towerOperationsConfig.merchantMaxVisitsPerDay) {
      merchantNextArrivalAt = _nextMerchantArrivalAfter(current);
      return;
    }
    merchantVisitsToday += 1;
    merchantNextArrivalAt = null;
    merchantAvailableUntil = current.add(
      Duration(hours: towerOperationsConfig.merchantPresenceHours),
    );
    merchantOffers
      ..clear()
      ..addAll(
        towerOperationsConfig.merchantOfferPrices.entries.map(
          (entry) => MerchantOffer(planName: entry.key, price: entry.value),
        ),
      );
    merchantOffers.addAll(
      pTibugConfig.sourcierPatternPrices.entries
          .where((entry) => !activePTibugPatterns.contains(entry.key))
          .map(
            (entry) => MerchantOffer(
              planName:
                  'Pattern ${pTibugConfig.species[entry.key]!.displayName}',
              price: entry.value,
              pTibugSpecies: entry.key,
            ),
          ),
    );
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Le Sourcier est arrivé au Marché avec des Plans et Patterns rares.',
        sourceBuildingId: 'market',
        subject: 'Sourcier arrivé',
        concerned: 'Joueur',
        summary: 'Nouvelles offres disponibles pendant deux heures.',
      ),
    );
  }

  /// Kept public for existing debug controls. Normal gameplay starts visits
  /// from the persistent arrival scheduler in [resolveTowerOperations] and
  /// [resolveMarket].
  void openMerchant() {
    if (isMerchantAvailable) return;
    _startMerchantVisit(DateTime.now());
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void _finishMerchantVisit(DateTime current, {required String message}) {
    merchantAvailableUntil = null;
    merchantOffers.clear();
    merchantNextArrivalAt = _nextMerchantArrivalAfter(current);
    reports.add(
      PtipoteMissionReport.system(
        message: message,
        sourceBuildingId: 'market',
        subject: 'Sourcier',
        concerned: 'Joueur',
        summary: 'Transaction terminée.',
      ),
    );
  }

  Zone0ActionResult finishMerchantTransaction() {
    if (!isMerchantAvailable) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Sourcier n’est pas présent.',
      );
    }
    _finishMerchantVisit(
      DateTime.now(),
      message: 'La transaction avec le Sourcier est terminée.',
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Le Sourcier est reparti.',
    );
  }

  Zone0ActionResult buyMerchantOffer(MerchantOffer offer) {
    if (!isMerchantAvailable || offer.purchased) {
      return const Zone0ActionResult(
        success: false,
        message: 'Offre indisponible.',
      );
    }
    if (bioBatteries < offer.price) {
      return const Zone0ActionResult(
        success: false,
        message: 'Bio-batteries insuffisantes.',
      );
    }
    bioBatteries -= offer.price;
    offer.purchased = true;
    if (offer.pTibugSpecies != null) {
      final species = offer.pTibugSpecies!;
      activePTibugPatterns.add(species);
      final planId = pTibugConfig.patterns[species]!.kernelPlanId;
      discoveredKernelPlanIds.remove(planId);
      readyKernelPlanIds.remove(planId);
      activeKernelPlanIds.add(planId);
      reports.add(
        PtipoteMissionReport.system(
          message:
              'Le Sourcier partage le Pattern ${pTibugConfig.species[species]!.displayName}. La Nurserie peut maintenant l’utiliser.',
          sourceBuildingId: 'market',
        ),
      );
    } else {
      reports.add(
        PtipoteMissionReport.system(
          message: '${offer.planName} a été acquis auprès du Sourcier.',
        ),
      );
    }
    if (merchantOffers.isNotEmpty &&
        merchantOffers.every((item) => item.purchased)) {
      _finishMerchantVisit(
        DateTime.now(),
        message: 'Toutes les offres du Sourcier ont été acquises.',
      );
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${offer.planName} acheté.',
    );
  }

  void ensureWeatherForecast() {
    resolveWeatherCycle(forceFirstAlert: true);
  }

  bool resolveWeatherCycle({DateTime? now, bool forceFirstAlert = false}) {
    final current = now ?? DateTime.now();
    var changed = _closeFinishedWeatherAlerts(current);
    if (!isSecurityTowerBuilt) return changed;

    final dayKey = _weatherDayKey(current);
    if (weatherScheduleDayKey != dayKey) {
      weatherScheduleDayKey = dayKey;
      weatherEventsToday = 0;
      changed = true;
    }
    if (weatherAlerts.any((alert) => alert.endsAt.isAfter(current))) {
      return changed;
    }
    if (weatherEventsToday >= towerOperationsConfig.maxWeatherEventsPerDay) {
      return changed;
    }
    if (!forceFirstAlert &&
        nextWeatherEligibleAt != null &&
        nextWeatherEligibleAt!.isAfter(current)) {
      return changed;
    }
    _createWeatherAlert(_weightedWeatherConfig(), current, manual: false);
    return true;
  }

  Zone0ActionResult triggerManualWeatherAlert(TowerWeatherType type) {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Tour de sécurité doit être construite.',
      );
    }
    if (weatherAlerts.any((alert) => alert.endsAt.isAfter(DateTime.now()))) {
      return const Zone0ActionResult(
        success: false,
        message: 'Une alerte météo est déjà active.',
      );
    }
    final config = towerOperationsConfig.weatherEvents
        .where((item) => item.type == type)
        .firstOrNull;
    if (config == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette intempérie n’est pas configurée.',
      );
    }
    _createWeatherAlert(config, DateTime.now(), manual: true);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${config.label} déclenchée pour le test.',
    );
  }

  void _consumeManualWeatherTrigger() {
    final triggerId = towerOperationsConfig.manualWeatherTriggerId;
    final type = towerOperationsConfig.manualWeatherTriggerType;
    if (triggerId.isEmpty ||
        type == null ||
        !processedManualWeatherTriggerIds.add(triggerId)) {
      return;
    }
    triggerManualWeatherAlert(type);
  }

  TowerWeatherConfig _weightedWeatherConfig() {
    final events = towerOperationsConfig.weatherEvents;
    final total = events.fold<int>(
      0,
      (accumulated, event) => accumulated + math.max(0, event.occurrenceWeight),
    );
    if (total <= 0) return events[_random.nextInt(events.length)];
    var roll = _random.nextInt(total);
    for (final event in events) {
      roll -= math.max(0, event.occurrenceWeight);
      if (roll < 0) return event;
    }
    return events.last;
  }

  void _createWeatherAlert(
    TowerWeatherConfig config,
    DateTime now, {
    required bool manual,
  }) {
    final template = kernelConfig.missions
        .where(
          (mission) =>
              mission.type == KernelMissionType.weather &&
              mission.weatherType == config.type.name,
        )
        .firstOrNull;
    final demandOptions = <String>{
      if (template?.requestedItem?.isNotEmpty == true) template!.requestedItem!,
      ...?template?.weatherDemandOptions,
    }.toList();
    final requestedItem = demandOptions.isEmpty
        ? null
        : demandOptions[_random.nextInt(demandOptions.length)];
    final populationBonus = currentPopulation ~/ 8;
    final heartBonus = math.max(0, _lastKnownCampHeartLevel - 1);
    final requestedAmount = template == null || requestedItem == null
        ? 0
        : math.max(
            1,
            template.requestedAmount +
                populationBonus +
                heartBonus +
                _random.nextInt(2),
          );
    final alert = WeatherAlert(
      id: 'weather-${now.microsecondsSinceEpoch}',
      type: config.type,
      startsAt: now.add(Duration(minutes: config.warningMinutes)),
      endsAt: now.add(
        Duration(minutes: config.warningMinutes + config.durationMinutes),
      ),
      manual: manual,
      requestedItem: requestedItem,
      requestedAmount: requestedAmount,
    );
    weatherAlerts.add(alert);
    weatherEventsToday += 1;
    nextWeatherEligibleAt = alert.endsAt.add(
      Duration(minutes: towerOperationsConfig.minimumWeatherIntervalMinutes),
    );
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Alerte Tour : ${config.label} approche. Consulte le Kernel pour voir la demande de préparation.',
        sourceBuildingId: 'securityTower',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Alerte météo',
        concerned: 'Maison',
        summary: config.announcement,
      ),
    );
  }

  bool _closeFinishedWeatherAlerts(DateTime now) {
    var changed = false;
    for (final alert in weatherAlerts.where(
      (item) => !item.reportSent && !item.endsAt.isAfter(now),
    )) {
      final config = towerOperationsConfig.weatherEvents
          .where((item) => item.type == alert.type)
          .firstOrNull;
      final label = config?.label ?? alert.type.name;
      reports.add(
        PtipoteMissionReport.system(
          message: alert.preparationCompleted
              ? '$label terminé : la préparation de la Maison a atténué l’intempérie.'
              : '$label terminé : aucune préparation validée avant la fin de l’alerte.',
          sourceBuildingId: 'house',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Rapport météo terminé',
          concerned: 'Maison',
          summary: alert.preparationCompleted
              ? '$label atténué.'
              : '$label non préparé.',
        ),
      );
      alert.reportSent = true;
      changed = true;
    }
    if (changed) weatherAlerts.removeWhere((item) => item.reportSent);
    return changed;
  }

  String _weatherDayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Zone0ActionResult fulfillWeatherPreparation(
    WeatherAlert alert, {
    WeatherPreparationType type = WeatherPreparationType.provide,
  }) {
    final config = towerOperationsConfig.weatherEvents.firstWhere(
      (item) => item.type == alert.type,
    );
    if (alert.preparationCompleted) {
      return const Zone0ActionResult(
        success: false,
        message: 'Préparation déjà terminée.',
      );
    }
    if (resourceAmount(config.preparationItem) < config.preparationAmount) {
      return Zone0ActionResult(
        success: false,
        message:
            'Il faut ${config.preparationAmount} ${config.preparationItem}.',
      );
    }
    if (type == WeatherPreparationType.provide) {
      removeResource(config.preparationItem, config.preparationAmount);
    }
    alert.preparationCompleted = true;
    reports.add(
      PtipoteMissionReport.system(
        message: 'Préparation météo validée : ${config.label} sera atténué.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Préparation validée.',
    );
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
    final elapsedSeconds =
        now.difference(mission.startTime).inSeconds.clamp(0, totalSeconds);
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
      for (final stack in inventory.where(
        (stack) => stack.resource == entry.key,
      )) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        addedAny = true;
      }

      while (remaining > 0 && inventory.length < inventorySlotLimit) {
        final add = math.min(
          remaining,
          lisiereForageConfig.inventoryStackLimit,
        );
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

  void markReportsRead({Zone0MessageMailbox? mailbox}) {
    var changed = false;
    for (final report in reports) {
      if (mailbox != null && report.mailbox != mailbox) continue;
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
      KernelMissionConditionType.requirementsMet => 1,
    };
  }

  int _kernelBuildingLevel(String buildingId) => switch (buildingId) {
        'campHeart' => _lastKnownCampHeartLevel,
        'fablab' => fablabLevel,
        'cuisine' => cuisineLevel,
        'atelier' => atelierLevel,
        'securityTower' => securityTowerLevel,
        'market' => marketLevel,
        'house' => houseLevel,
        _ => 0,
      };

  String? _kernelMissionPrerequisiteMessage(KernelMissionConfig mission) {
    for (final requirement in mission.requiredBuildingLevels.entries) {
      if (_kernelBuildingLevel(requirement.key) < requirement.value) {
        return '${requirement.key} niveau ${requirement.value} requis.';
      }
    }
    if (kernelTrustLevel < mission.requiredKernelTrustLevel) {
      return 'Confiance du Kernel niveau ${mission.requiredKernelTrustLevel} requise.';
    }
    if (kernelAxisLevel(KernelAxis.breeder) < mission.requiredBreederLevel) {
      return 'Éleveur niveau ${mission.requiredBreederLevel} requis.';
    }
    if (kernelAxisLevel(KernelAxis.builder) < mission.requiredBuilderLevel) {
      return 'Bâtisseur niveau ${mission.requiredBuilderLevel} requis.';
    }
    if (kernelAxisLevel(KernelAxis.restorer) < mission.requiredRestorerLevel) {
      return 'Restaurateur niveau ${mission.requiredRestorerLevel} requis.';
    }
    if (mission.type == KernelMissionType.weather &&
        !weatherAlerts.any(
          (alert) =>
              alert.type.name == mission.weatherType &&
              alert.endsAt.isAfter(DateTime.now()),
        )) {
      return 'En attente de l’intempérie annoncée par la Tour.';
    }
    return null;
  }

  Zone0ActionResult fulfillKernelMission(String missionId) {
    final mission = _kernelMissionById(missionId);
    if (mission == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Mission inconnue.',
      );
    }
    if (completedKernelMissionIds.contains(mission.id)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Mission déjà terminée.',
      );
    }
    final prerequisite = _kernelMissionPrerequisiteMessage(mission);
    if (prerequisite != null) {
      return Zone0ActionResult(success: false, message: prerequisite);
    }
    if (mission.requestedItem == null || mission.requestedAmount <= 0) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Cette mission se valide automatiquement quand ses prérequis sont remplis.',
      );
    }
    if (resourceAmount(mission.requestedItem!) < mission.requestedAmount) {
      return Zone0ActionResult(
        success: false,
        message: 'Il faut ${mission.requestedAmount} ${mission.requestedItem}.',
      );
    }
    removeResource(mission.requestedItem!, mission.requestedAmount);
    if (mission.type == KernelMissionType.weather) {
      final alert = weatherAlerts
          .where(
            (item) =>
                item.type.name == mission.weatherType &&
                _weatherMissionForAlert(item)?.id == mission.id &&
                item.endsAt.isAfter(DateTime.now()),
          )
          .firstOrNull;
      if (alert != null) alert.preparationCompleted = true;
    }
    _completeKernelMission(mission);
    refreshKernelMissions();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${mission.title} terminée.',
    );
  }

  void _completeKernelMission(KernelMissionConfig mission) {
    if (!completedKernelMissionIds.add(mission.id)) return;
    bioBatteries += mission.bioBatteryReward;
    if (mission.resourceRewards.isNotEmpty) {
      addResources(mission.resourceRewards);
    }
    if (mission.rewardPatternId case final patternId?) {
      activeKernelPlanIds.add(patternId);
    }
    if (mission.xpReward > 0) _addKernelTrustXp(mission.xpReward);
    reports.add(
      PtipoteMissionReport.system(
        message: mission.mailMessage,
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Mission Kernel terminée',
        concerned: 'Joueur',
        summary: mission.mailMessage,
      ),
    );
  }

  bool refreshKernelMissions({int? campHeartLevel}) {
    var changed = false;
    if (campHeartLevel != null) {
      _lastKnownCampHeartLevel = campHeartLevel.clamp(1, 5);
    }
    final populationCapacity = populationCapacityForCampHeartLevel(
      _lastKnownCampHeartLevel,
    );

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
        if (mission.requestedItem != null ||
            _kernelMissionPrerequisiteMessage(mission) != null) {
          continue;
        }
        if (_kernelMissionProgress(mission) < mission.requiredAmount) continue;
        _completeKernelMission(mission);
        changed = true;
      }

      final alreadyGranted = (kernelPopulationRewardsGranted[mission.id] ?? 0)
          .clamp(0, mission.populationReward);
      final remainingReward = mission.populationReward - alreadyGranted;
      final availableCapacity = math.max(
        0,
        populationCapacity - currentPopulation,
      );
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
    _notifyAvailableKernelMissions();
    return changed;
  }

  void _notifyAvailableKernelMissions() {
    final user = _auth.currentUser;
    if (user == null) return;

    for (final progress in kernelMissionsForCampHeartLevel(
      _lastKnownCampHeartLevel,
    )) {
      final mission = progress.config;
      if (progress.status != KernelMissionStatus.active ||
          notifiedKernelMissionIds.contains(mission.id) ||
          !_kernelNotificationInFlightIds.add(mission.id)) {
        continue;
      }
      unawaited(_sendKernelMissionNotification(user.uid, mission));
    }
  }

  Future<void> _sendKernelMissionNotification(
    String userId,
    KernelMissionConfig mission,
  ) async {
    try {
      await NotificationService(auth: _auth, firestore: _firestore).sendToUser(
        recipientUid: userId,
        type: 'kernel_mission',
        title: 'Kernel : nouvelle mission',
        body: mission.title,
        data: <String, dynamic>{
          'missionId': mission.id,
          'missionType': mission.type.name,
        },
      );
      notifiedKernelMissionIds.add(mission.id);
      unawaited(saveRuntimeToFirebase());
    } catch (_) {
      // The mission stays eligible so a later online refresh can notify it.
    } finally {
      _kernelNotificationInFlightIds.remove(mission.id);
    }
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
          rewards = rewards.map(
            (key, value) => MapEntry(key, (value * 0.75).round()),
          );
          incident = 'drone errant, -25 % gains totaux';
        case ForageHazard.climatDifficile:
          rewards = rewards.map(
            (key, value) => MapEntry(key, (value * 0.85).round()),
          );
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
          _random.nextInt(
            wasteRecyclerConfig.wasteRewardMaximumPercent -
                wasteRecyclerConfig.wasteRewardMinimumPercent +
                1,
          );
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
      unawaited(
        persistFigurineProgress(
          figurineId: memberId,
          xp: xpResult.xp,
          level: xpResult.level,
        ),
      );
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
          final ticks = _towerTicksForPlan(TowerMissionPlan.oneHour, vitality);
          towerMissions.add(
            TowerMission(
              id: 'tower-${DateTime.now().microsecondsSinceEpoch}-$memberId',
              figurineId: memberId,
              figurineName: memberName,
              plan: TowerMissionPlan.oneHour,
              startTime: completedAt,
              endTime: completedAt.add(_towerDurationForTicks(ticks)),
              vitalityCost: ticks * securityTowerConfig.vitalityCostPerTick,
              securityGain: ticks *
                  securityTowerConfig.securityGainForLevel(securityTowerLevel),
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
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Retour de mission Lisière',
        concerned: mission.figurineName,
        summary: incident == 'aucun'
            ? 'Mission terminée.'
            : 'Événement : $incident.',
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
      1,
      (theoreticalMinutes / lisiereForageConfig.forageTimeScale).round(),
    );
    return Duration(minutes: realMinutes);
  }

  void _resolveTowerMission(TowerMission mission, {bool early = false}) {
    final elapsedRatio = early
        ? (DateTime.now().difference(mission.startTime).inSeconds /
            math.max(
              1,
              mission.endTime.difference(mission.startTime).inSeconds,
            ))
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
    emitKernelProgressEvent(KernelProgressEventType.towerMissionCompleted);
    reports.add(
      PtipoteMissionReport.system(
        message: early
            ? '${mission.figurineName} revient de la Tour plus tôt : -$vitalityCost Vitalité.'
            : mission.patrolBiome == null
                ? '${mission.figurineName} termine sa surveillance : +$securityGain sécurité camp, -$vitalityCost Vitalité.'
                : '${mission.figurineName} termine sa ronde : +$localGain sécurité locale, -$vitalityCost Vitalité.',
        sourceBuildingId: 'securityTower',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Retour de ronde',
        concerned: mission.figurineName,
        summary: mission.patrolBiome == null
            ? '+$securityGain sécurité camp, -$vitalityCost vitalité.'
            : '+$localGain sécurité locale, -$vitalityCost vitalité.',
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
      notes.add(
        '$figurineName est revenu très fatigué et est allé se reposer.',
      );
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
    return PtipoteXpGainResult(xp: xp, level: level, leveledUp: leveledUp);
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
      return _zone0Doc(user.uid).set(<String, dynamic>{
        'campHeart': campHeart,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> saveInventoryToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde inventaire', () {
      return _zone0Doc(user.uid).set(<String, dynamic>{
        'inventory': inventory
            .map(
              (stack) => <String, dynamic>{
                'resource': stack.resource,
                'amount': stack.amount,
              },
            )
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> saveRuntimeToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde missions/vitalité', () {
      return _zone0Doc(user.uid).set(<String, dynamic>{
        'vitalityOverrides': vitalityOverrides,
        'hungerOverrides': hungerOverrides,
        'restOverrides': restOverrides,
        'wellRestedRewardedIds': wellRestedRewardedIds.toList(),
        'manualRestingIds': manualRestingIds.toList(),
        'waitingForBedIds': waitingForBedIds.toList(),
        'hatchedPtipoteIds': hatchedPtipoteIds.toList(),
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
              .map(
                (item) => <String, dynamic>{
                  'resource': item.resource,
                  'amount': item.amount,
                },
              )
              .toList(),
          'requests': marketRequests.map((item) => item.toFirebase()).toList(),
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
          'merchantNextArrivalAt': merchantNextArrivalAt == null
              ? null
              : Timestamp.fromDate(merchantNextArrivalAt!),
          'merchantVisitsDayKey': merchantVisitsDayKey,
          'merchantVisitsToday': merchantVisitsToday,
          'merchantOffers': merchantOffers
              .map(
                (item) => <String, dynamic>{
                  'planName': item.planName,
                  'price': item.price,
                  'purchased': item.purchased,
                  'ptibugSpecies': item.pTibugSpecies?.name,
                },
              )
              .toList(),
        },
        'biomeSecurity': biomeSecurity.map(
          (key, value) => MapEntry(key.name, value.toFirebase()),
        ),
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
          'axisXp': kernelAxisXp.map((key, value) => MapEntry(key.name, value)),
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
          'dismissedMissionIds': dismissedKernelMissionIds.toList(),
          'viewedMissionIds': viewedKernelMissionIds.toList(),
          'notifiedMissionIds': notifiedKernelMissionIds.toList(),
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
        'ptibug': <String, dynamic>{
          'nurseryLevel': plaineNurseryLevel,
          'activePatterns':
              activePTibugPatterns.map((item) => item.name).toList(),
          'starterChoiceMade': starterPTibugChoiceMade,
          'creation': pTibugCreationOrder?.toFirebase(),
          'items': pTibugs.map((item) => item.toFirebase()).toList(),
          'traitData':
              pTibugTraitData.map((item) => item.toFirebase()).toList(),
          'unlockedModules':
              unlockedPTibugModules.map((item) => item.name).toList(),
          'dataReserve': <String, int>{
            for (final entry in pTibugDataReserve.entries)
              entry.key.name: entry.value,
          },
          'dataCells':
              pTibugDataCells.map((item) => item.toFirebase()).toList(),
          'patternProgress': pTibugPatternProgress.values
              .map((item) => item.toFirebase())
              .toList(),
          'moduleInstances':
              pTibugModuleInstances.map((item) => item.toFirebase()).toList(),
          'moduleCraftOrders':
              pTibugModuleCraftOrders.map((item) => item.toFirebase()).toList(),
          'capsules': pTibugCapsules.map((item) => item.toFirebase()).toList(),
        },
        'lastSimulationAt': lastSimulationAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(lastSimulationAt!),
        'lastCuddleAt': lastCuddleAt.map(
          (key, value) => MapEntry(key, Timestamp.fromDate(value)),
        ),
        'weather': <String, dynamic>{
          'dayKey': weatherScheduleDayKey,
          'eventsToday': weatherEventsToday,
          'nextEligibleAt': nextWeatherEligibleAt == null
              ? null
              : Timestamp.fromDate(nextWeatherEligibleAt!),
          'processedManualTriggerIds':
              processedManualWeatherTriggerIds.toList(),
          'alerts': weatherAlerts.map((alert) => alert.toFirebase()).toList(),
        },
        'missions': missions.map((mission) => mission.toFirebase()).toList(),
        'reports': reports.map((report) => report.toFirebase()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> saveBuildingsToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde bâtiments', () {
      return _zone0Doc(user.uid).set(<String, dynamic>{
        'buildings': <String, dynamic>{
          'fablab': <String, dynamic>{
            'buildingId': 'fablab',
            'buildingType': 'production',
            'displayName': 'Fablab',
            'state': isFablabBuilt ? 'built' : 'constructible',
            'currentLevel': fablabLevel,
            'atelierLevel': atelierLevel,
            'cuisineLevel': cuisineLevel,
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
          'house': <String, dynamic>{
            'buildingId': 'house',
            'buildingType': 'home',
            'displayName': 'Maison',
            'state': 'built',
            'currentLevel': houseLevel,
            'maxLevel': housingConfig.houseMaxLevel,
            'alcoveCapacity': alcoveCapacity,
            'isVisible': true,
          },
          'housing': <String, dynamic>{
            'units': housingUnits,
            'capacity': housingCapacity,
            'thanks': communityConstructionThanks?.toFirebase(),
          },
          'projects': constructionProjects.map(
            (key, value) => MapEntry(key, value.toFirebase()),
          ),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      return ref.set(<String, dynamic>{
        'fields': fields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
  MarketCustomerRequest({
    required this.id,
    required this.requestedItemId,
    required this.requestedQuantity,
    required this.rewardBioBattery,
    required this.rewardWellbeing,
    required this.createdAt,
    required this.customerReturnTime,
    required this.status,
  });

  factory MarketCustomerRequest.fromFirebase(
    Map<dynamic, dynamic> data,
  ) =>
      MarketCustomerRequest(
        id: '${data['id'] ?? ''}',
        requestedItemId: '${data['requestedItemId'] ?? ''}',
        requestedQuantity: Zone0GameState.instance._readInt(
          data['requestedQuantity'],
        ),
        rewardBioBattery: Zone0GameState.instance._readInt(
          data['rewardBioBattery'],
        ),
        rewardWellbeing:
            Zone0GameState.instance._readInt(data['rewardWellbeing']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        customerReturnTime:
            Zone0GameState.instance._readDate(data['customerReturnTime']) ??
                DateTime.now(),
        status: ForageMission._enumByName(
          MarketRequestStatus.values,
          '${data['status'] ?? ''}',
          MarketRequestStatus.noted,
        ),
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
      requestedQuantity: Zone0GameState.instance._readInt(
        data['requestedQuantity'],
      ),
      completedQuantity: Zone0GameState.instance._readInt(
        data['completedQuantity'],
      ),
      assignedPtipoteId: data['assignedPtipoteId'] as String?,
      assignedPtipoteName: data['assignedPtipoteName'] as String?,
      startTime: Zone0GameState.instance._readDate(data['startTime']) ??
          DateTime.now(),
      nextCompletionTime:
          Zone0GameState.instance._readDate(data['nextCompletionTime']) ??
              DateTime.now(),
      unitDurationSeconds: math.max(
        1,
        Zone0GameState.instance._readInt(
          data['unitDurationSeconds'],
          fallback: 60,
        ),
      ),
      reservedResources: Map<String, int>.fromEntries(
        (data['reservedResources'] as Map? ?? const <String, dynamic>{})
            .entries
            .map(
              (entry) => MapEntry(
                '${entry.key}',
                Zone0GameState.instance._readInt(entry.value),
              ),
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

enum ConstructionProjectState {
  locked,
  available,
  collectingMaterials,
  readyToBuild,
  underConstruction,
  built,
  upgradeAvailable,
  upgrading,
  maxLevel,
}

class CommunityConstructionThanks {
  const CommunityConstructionThanks({
    required this.bonusValue,
    required this.startedAt,
    required this.endsAt,
    required this.sourceProjectId,
  });

  factory CommunityConstructionThanks.fromFirebase(Object? value) {
    if (value is! Map) {
      return CommunityConstructionThanks(
        bonusValue: 0,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        endsAt: DateTime.fromMillisecondsSinceEpoch(0),
        sourceProjectId: '',
      );
    }
    return CommunityConstructionThanks(
      bonusValue: Zone0GameState.instance._readInt(value['bonusValue']),
      startedAt: Zone0GameState.instance._readDate(value['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: Zone0GameState.instance._readDate(value['endsAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceProjectId: '${value['sourceProjectId'] ?? ''}',
    );
  }

  final int bonusValue;
  final DateTime startedAt;
  final DateTime endsAt;
  final String sourceProjectId;

  bool get isActive => isActiveAt(DateTime.now());
  bool isActiveAt(DateTime now) => now.isBefore(endsAt);

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'bonusValue': bonusValue,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'sourceProjectId': sourceProjectId,
      };
}

class ConstructionProject {
  ConstructionProject({
    required this.projectId,
    required this.targetId,
    required this.targetType,
    required this.currentLevel,
    required this.targetLevel,
    required this.requirements,
    required this.constructionDuration,
    Map<String, int>? depositedMaterials,
    this.state = ConstructionProjectState.available,
    this.startedAt,
    this.endsAt,
    this.completedAt,
    this.notificationCreated = false,
  }) : depositedMaterials = depositedMaterials ?? <String, int>{};

  factory ConstructionProject.fromFirebase(Map<dynamic, dynamic> data) {
    final durationSeconds = Zone0GameState.instance._readInt(
      data['constructionDurationSeconds'],
      fallback: 60,
    );
    Map<String, int> mapValue(Object? value) => Map<String, int>.fromEntries(
          (value as Map? ?? const <dynamic, dynamic>{}).entries.map(
                (entry) => MapEntry(
                  '${entry.key}',
                  Zone0GameState.instance._readInt(entry.value),
                ),
              ),
        );
    return ConstructionProject(
      projectId: '${data['projectId'] ?? ''}',
      targetId: '${data['targetId'] ?? ''}',
      targetType: '${data['targetType'] ?? ''}',
      currentLevel: Zone0GameState.instance._readInt(data['currentLevel']),
      targetLevel: Zone0GameState.instance._readInt(data['targetLevel']),
      requirements: mapValue(data['requirements']),
      depositedMaterials: mapValue(data['depositedMaterials']),
      constructionDuration: Duration(seconds: math.max(1, durationSeconds)),
      state: ForageMission._enumByName(
        ConstructionProjectState.values,
        '${data['state'] ?? ''}',
        ConstructionProjectState.available,
      ),
      startedAt: Zone0GameState.instance._readDate(data['startedAt']),
      endsAt: Zone0GameState.instance._readDate(data['endsAt']),
      completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      notificationCreated: data['notificationCreated'] == true,
    );
  }

  final String projectId;
  final String targetId;
  final String targetType;
  int currentLevel;
  int targetLevel;
  Map<String, int> requirements;
  final Map<String, int> depositedMaterials;
  Duration constructionDuration;
  ConstructionProjectState state;
  DateTime? startedAt;
  DateTime? endsAt;
  DateTime? completedAt;
  bool notificationCreated;

  bool get isInProgress =>
      state == ConstructionProjectState.underConstruction ||
      state == ConstructionProjectState.upgrading;
  bool isReadyToCompleteAt(DateTime now) =>
      isInProgress && endsAt != null && !endsAt!.isAfter(now);
  bool get canEditMaterials =>
      !isInProgress &&
      state != ConstructionProjectState.built &&
      state != ConstructionProjectState.maxLevel;
  bool get isReady => requirements.entries.every(
        (entry) => (depositedMaterials[entry.key] ?? 0) >= entry.value,
      );
  int missingFor(String resource) => math.max(
        0,
        (requirements[resource] ?? 0) - (depositedMaterials[resource] ?? 0),
      );

  void prepareNextLevel({
    required int targetLevel,
    required Map<String, int> requirements,
    required Duration constructionDuration,
  }) {
    this.targetLevel = targetLevel;
    this.requirements = requirements;
    this.constructionDuration = constructionDuration;
    depositedMaterials.clear();
    startedAt = null;
    endsAt = null;
    completedAt = null;
    state = ConstructionProjectState.available;
  }

  void refreshState() {
    if (isInProgress || state == ConstructionProjectState.built) return;
    if (depositedMaterials.isEmpty) {
      state = ConstructionProjectState.available;
    } else if (isReady) {
      state = ConstructionProjectState.readyToBuild;
    } else {
      state = ConstructionProjectState.collectingMaterials;
    }
  }

  /// Completes the time-only part of a project. The game state applies the
  /// building-specific effect immediately afterwards.
  bool completeAt(DateTime now) {
    if (!isReadyToCompleteAt(now)) return false;
    currentLevel = targetLevel;
    completedAt = now;
    depositedMaterials.clear();
    state = ConstructionProjectState.built;
    return true;
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'projectId': projectId,
        'targetId': targetId,
        'targetType': targetType,
        'currentLevel': currentLevel,
        'targetLevel': targetLevel,
        'requirements': requirements,
        'depositedMaterials': depositedMaterials,
        'constructionDurationSeconds': constructionDuration.inSeconds,
        'state': state.name,
        'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
        'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'notificationCreated': notificationCreated,
      };
}

class PTibug {
  PTibug({
    required this.id,
    required this.displayName,
    required this.species,
    required this.styleVariant,
    required this.createdAt,
    this.assignedSlotIndex,
    Map<String, int>? storedResources,
    this.level = 1,
    this.xp = 0,
    this.traitDataId,
    this.biologicalTraitId,
    this.biologicalTraitLevel = 0,
    List<PTibugModuleType>? equippedModules,
    List<String>? equippedModuleInstanceIds,
    this.biome = PTibugBiome.savaneTropicale,
    this.stockFullNotified = false,
    this.nextProductionAt,
  })  : storedResources = storedResources ?? <String, int>{},
        equippedModules = equippedModules ?? <PTibugModuleType>[],
        equippedModuleInstanceIds = equippedModuleInstanceIds ?? <String>[];
  final String id;
  String displayName;
  final PTibugSpecies species;
  final String styleVariant;
  final DateTime createdAt;
  int? assignedSlotIndex;
  final Map<String, int> storedResources;
  int level;
  int xp;
  String? traitDataId;
  String? biologicalTraitId;
  int biologicalTraitLevel;
  final List<PTibugModuleType> equippedModules;
  final List<String> equippedModuleInstanceIds;
  PTibugBiome biome;
  bool stockFullNotified;
  DateTime? nextProductionAt;
  int get storedAmount =>
      storedResources.values.fold(0, (total, value) => total + value);
  bool hasModule(PTibugModuleType type) => equippedModules.contains(type);

  factory PTibug.fromFirebase(Map<dynamic, dynamic> data) => PTibug(
        id: '${data['id'] ?? ''}',
        displayName: '${data['displayName'] ?? 'P’TIBUG'}',
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        styleVariant: '${data['styleVariant'] ?? 'compact'}',
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        assignedSlotIndex: data['assignedSlotIndex'] as int?,
        level: Zone0GameState.instance._readInt(data['level'], fallback: 1),
        xp: Zone0GameState.instance._readInt(data['xp']),
        traitDataId: data['traitDataId'] as String?,
        biologicalTraitId: data['biologicalTraitId'] as String?,
        biologicalTraitLevel: Zone0GameState.instance._readInt(
          data['biologicalTraitLevel'],
        ),
        equippedModules: (data['equippedModules'] as List? ?? const <dynamic>[])
            .map(
              (value) => ForageMission._enumByName(
                PTibugModuleType.values,
                '$value',
                PTibugModuleType.ailes,
              ),
            )
            .toList(),
        equippedModuleInstanceIds:
            (data['equippedModuleInstanceIds'] as List? ?? const <dynamic>[])
                .map((value) => '$value')
                .toList(),
        biome: ForageMission._enumByName(
          PTibugBiome.values,
          '${data['biome'] ?? ''}',
          PTibugBiome.savaneTropicale,
        ),
        stockFullNotified: data['stockFullNotified'] == true,
        nextProductionAt: Zone0GameState.instance._readDate(
          data['nextProductionAt'],
        ),
        storedResources: Map<String, int>.fromEntries(
          (data['storedResources'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map(
                (entry) => MapEntry(
                  '${entry.key}',
                  Zone0GameState.instance._readInt(entry.value),
                ),
              ),
        ),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'species': species.name,
        'styleVariant': styleVariant,
        'createdAt': Timestamp.fromDate(createdAt),
        'assignedSlotIndex': assignedSlotIndex,
        'storedResources': storedResources,
        'level': level,
        'xp': xp,
        'traitDataId': traitDataId,
        'biologicalTraitId': biologicalTraitId,
        'biologicalTraitLevel': biologicalTraitLevel,
        'equippedModules': equippedModules.map((item) => item.name).toList(),
        'equippedModuleInstanceIds': equippedModuleInstanceIds,
        'biome': biome.name,
        'stockFullNotified': stockFullNotified,
        'nextProductionAt': nextProductionAt == null
            ? null
            : Timestamp.fromDate(nextProductionAt!),
      };
}

class PTibugDataCellEntry {
  const PTibugDataCellEntry({
    required this.family,
    required this.quality,
    required this.slotIndex,
  });

  final PTibugDataFamily family;
  final PTibugDataQuality quality;
  final int slotIndex;

  int value(PTibugConfig config) => config.dataValue(quality);

  factory PTibugDataCellEntry.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugDataCellEntry(
        family: ForageMission._enumByName(
          PTibugDataFamily.values,
          '${data['family'] ?? ''}',
          PTibugDataFamily.organique,
        ),
        quality: ForageMission._enumByName(
          PTibugDataQuality.values,
          '${data['quality'] ?? ''}',
          PTibugDataQuality.common,
        ),
        slotIndex: Zone0GameState.instance._readInt(data['slotIndex']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'family': family.name,
        'quality': quality.name,
        'slotIndex': slotIndex,
      };
}

class PTibugDataCell {
  PTibugDataCell({
    required this.id,
    required this.displayName,
    required this.sourceBiomeId,
    required this.entries,
    required this.createdAt,
    this.sourceMissionId,
    this.dominantFamily,
    this.isNeutralCell = false,
    this.openedAt,
  });

  final String id;
  final String displayName;
  final String sourceBiomeId;
  final String? sourceMissionId;
  final PTibugDataFamily? dominantFamily;
  final bool isNeutralCell;
  final List<PTibugDataCellEntry> entries;
  final DateTime createdAt;
  DateTime? openedAt;
  bool get isOpened => openedAt != null;

  factory PTibugDataCell.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugDataCell(
        id: '${data['id'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Cellule de données'}',
        sourceBiomeId: '${data['sourceBiomeId'] ?? 'unknown'}',
        sourceMissionId: data['sourceMissionId'] as String?,
        dominantFamily: data['dominantFamily'] == null
            ? null
            : ForageMission._enumByName(
                PTibugDataFamily.values,
                '${data['dominantFamily']}',
                PTibugDataFamily.organique,
              ),
        isNeutralCell: data['isNeutralCell'] == true,
        entries: (data['entries'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(PTibugDataCellEntry.fromFirebase)
            .take(5)
            .toList(),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        openedAt: Zone0GameState.instance._readDate(data['openedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'sourceBiomeId': sourceBiomeId,
        'sourceMissionId': sourceMissionId,
        'dominantFamily': dominantFamily?.name,
        'isNeutralCell': isNeutralCell,
        'entries': entries.map((entry) => entry.toFirebase()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'openedAt': openedAt == null ? null : Timestamp.fromDate(openedAt!),
      };
}

class PTibugPatternProgress {
  PTibugPatternProgress({
    required this.patternId,
    this.state = PTibugPatternState.unknown,
    this.masteryLevel = 0,
    Map<PTibugDataFamily, int>? investedDataByFamily,
    this.discoveredAt,
    this.activatedAt,
  }) : investedDataByFamily = investedDataByFamily ?? <PTibugDataFamily, int>{};

  final String patternId;
  PTibugPatternState state;
  int masteryLevel;
  final Map<PTibugDataFamily, int> investedDataByFamily;
  DateTime? discoveredAt;
  DateTime? activatedAt;

  factory PTibugPatternProgress.fromFirebase(Map<dynamic, dynamic> data) {
    final rawInvested =
        data['investedDataByFamily'] as Map? ?? const <dynamic, dynamic>{};
    return PTibugPatternProgress(
      patternId: '${data['patternId'] ?? ''}',
      state: ForageMission._enumByName(
        PTibugPatternState.values,
        '${data['state'] ?? ''}',
        PTibugPatternState.unknown,
      ),
      masteryLevel: Zone0GameState.instance._readInt(data['masteryLevel']),
      investedDataByFamily: <PTibugDataFamily, int>{
        for (final family in PTibugDataFamily.values)
          family: Zone0GameState.instance._readInt(rawInvested[family.name]),
      },
      discoveredAt: Zone0GameState.instance._readDate(data['discoveredAt']),
      activatedAt: Zone0GameState.instance._readDate(data['activatedAt']),
    );
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'patternId': patternId,
        'state': state.name,
        'masteryLevel': masteryLevel,
        'investedDataByFamily': <String, int>{
          for (final entry in investedDataByFamily.entries)
            entry.key.name: entry.value,
        },
        'discoveredAt':
            discoveredAt == null ? null : Timestamp.fromDate(discoveredAt!),
        'activatedAt':
            activatedAt == null ? null : Timestamp.fromDate(activatedAt!),
      };
}

class PTibugModuleInstance {
  PTibugModuleInstance({
    required this.id,
    required this.type,
    this.qualityLevel = 1,
    this.equippedPTibugId,
    required this.createdAt,
    this.source = 'atelier',
  });

  final String id;
  final PTibugModuleType type;
  int qualityLevel;
  String? equippedPTibugId;
  final DateTime createdAt;
  final String source;
  bool get isEquipped => equippedPTibugId != null;

  factory PTibugModuleInstance.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugModuleInstance(
        id: '${data['id'] ?? ''}',
        type: ForageMission._enumByName(
          PTibugModuleType.values,
          '${data['type'] ?? ''}',
          PTibugModuleType.ailes,
        ),
        qualityLevel: Zone0GameState.instance
            ._readInt(data['qualityLevel'], fallback: 1)
            .clamp(1, 99),
        equippedPTibugId: data['equippedPTibugId'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        source: '${data['source'] ?? 'atelier'}',
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'qualityLevel': qualityLevel,
        'equippedPTibugId': equippedPTibugId,
        'createdAt': Timestamp.fromDate(createdAt),
        'source': source,
      };
}

class PTibugModuleCraftOrder {
  PTibugModuleCraftOrder({
    required this.id,
    required this.moduleType,
    required this.startedAt,
    required this.endsAt,
    this.completedAt,
  });

  final String id;
  final PTibugModuleType moduleType;
  final DateTime startedAt;
  final DateTime endsAt;
  DateTime? completedAt;

  bool get isActive => completedAt == null;

  factory PTibugModuleCraftOrder.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugModuleCraftOrder(
        id: '${data['id'] ?? ''}',
        moduleType: ForageMission._enumByName(
          PTibugModuleType.values,
          '${data['moduleType'] ?? ''}',
          PTibugModuleType.ailes,
        ),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'moduleType': moduleType.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

class PTibugCapsule {
  const PTibugCapsule({
    required this.id,
    required this.species,
    required this.styleVariant,
    required this.displayName,
    required this.createdAt,
    this.biologicalTraitId,
    this.biologicalTraitLevel = 0,
    this.level = 1,
    this.xp = 0,
    this.originRefugeId,
    this.creatorPlayerId,
  });

  final String id;
  final PTibugSpecies species;
  final String styleVariant;
  final String displayName;
  final String? biologicalTraitId;
  final int biologicalTraitLevel;
  final int level;
  final int xp;
  final String? originRefugeId;
  final String? creatorPlayerId;
  final DateTime createdAt;

  factory PTibugCapsule.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugCapsule(
        id: '${data['id'] ?? ''}',
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        styleVariant: '${data['styleVariant'] ?? 'compact'}',
        displayName: '${data['displayName'] ?? 'Capsule P’TIBUG'}',
        biologicalTraitId: data['biologicalTraitId'] as String?,
        biologicalTraitLevel: Zone0GameState.instance._readInt(
          data['biologicalTraitLevel'],
        ),
        level: Zone0GameState.instance._readInt(data['level'], fallback: 1),
        xp: Zone0GameState.instance._readInt(data['xp']),
        originRefugeId: data['originRefugeId'] as String?,
        creatorPlayerId: data['creatorPlayerId'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'species': species.name,
        'styleVariant': styleVariant,
        'displayName': displayName,
        'biologicalTraitId': biologicalTraitId,
        'biologicalTraitLevel': biologicalTraitLevel,
        'level': level,
        'xp': xp,
        'originRefugeId': originRefugeId,
        'creatorPlayerId': creatorPlayerId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

class PTibugTraitData {
  const PTibugTraitData({
    required this.id,
    required this.definitionId,
    required this.grade,
  });

  final String id;
  final String definitionId;
  final PTibugTraitGrade grade;

  factory PTibugTraitData.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugTraitData(
        id: '${data['id'] ?? ''}',
        definitionId:
            '${data['definitionId'] ?? data['type'] ?? 'pollinisateur'}',
        grade: ForageMission._enumByName(
          PTibugTraitGrade.values,
          '${data['grade'] ?? ''}',
          PTibugTraitGrade.commun,
        ),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        // Kept for application versions that still read the historical field.
        'type': definitionId,
        'grade': grade.name,
        'definitionId': definitionId,
      };
}

class PTibugCreationOrder {
  PTibugCreationOrder({
    required this.species,
    required this.startedAt,
    required this.endsAt,
    this.completedAt,
  });

  final PTibugSpecies species;
  final DateTime startedAt;
  final DateTime endsAt;
  DateTime? completedAt;
  bool get isActive => completedAt == null;

  factory PTibugCreationOrder.fromFirebase(
    Map<dynamic, dynamic> data,
  ) =>
      PTibugCreationOrder(
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'species': species.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

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
    ForageBiome biome,
    Map<dynamic, dynamic> data,
  ) =>
      BiomeSecurityState(
        biome: biome,
        status: ForageMission._enumByName(
          BiomeDiscoveryStatus.values,
          '${data['status'] ?? ''}',
          BiomeDiscoveryStatus.discovered,
        ),
        // V1 stored local security for exploration and forage missions too.
        // Those values were not actual completed patrols, so reset them once.
        localSecurity: ForageMission._readStaticInt(data['securitySchema']) >= 2
            ? ForageMission._readStaticInt(data['localSecurity'])
            : 0,
        explorationProgress: ForageMission._readStaticInt(
          data['explorationProgress'],
        ),
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
  BiomeExplorationMission({
    required this.id,
    required this.biome,
    required this.memberIds,
    required this.memberNames,
    required this.endTime,
    required this.explorationProgressGain,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  factory BiomeExplorationMission.fromFirebase(Map<dynamic, dynamic> data) =>
      BiomeExplorationMission(
        id: '${data['id'] ?? ''}',
        biome: ForageMission._enumByName(
          ForageBiome.values,
          '${data['biome'] ?? ''}',
          ForageBiome.plaineRiche,
        ),
        memberIds: ForageMission._readStringList(data['memberIds']),
        memberNames: ForageMission._readStringList(data['memberNames']),
        startTime: ForageMission._readDate(data['startTime']) ?? DateTime.now(),
        endTime: ForageMission._readDate(data['endTime']) ?? DateTime.now(),
        explorationProgressGain: ForageMission._readStaticInt(
          data['explorationProgressGain'],
        ),
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
  WeatherAlert({
    required this.id,
    required this.type,
    required this.startsAt,
    required this.endsAt,
    this.preparationCompleted = false,
    this.reportSent = false,
    this.manual = false,
    this.requestedItem,
    this.requestedAmount = 0,
  });
  final String id;
  final TowerWeatherType type;
  final DateTime startsAt;
  final DateTime endsAt;
  bool preparationCompleted;
  bool reportSent;
  final bool manual;
  final String? requestedItem;
  final int requestedAmount;

  factory WeatherAlert.fromFirebase(Map<dynamic, dynamic> data) => WeatherAlert(
        id: '${data['id'] ?? 'weather-${DateTime.now().microsecondsSinceEpoch}'}',
        type: ForageMission._enumByName(
          TowerWeatherType.values,
          '${data['type'] ?? ''}',
          TowerWeatherType.toxicCloud,
        ),
        startsAt: Zone0GameState.instance._readDate(data['startsAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        preparationCompleted: data['preparationCompleted'] == true,
        reportSent: data['reportSent'] == true,
        manual: data['manual'] == true,
        requestedItem: data['requestedItem'] as String?,
        requestedAmount: (data['requestedAmount'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'startsAt': Timestamp.fromDate(startsAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'preparationCompleted': preparationCompleted,
        'reportSent': reportSent,
        'manual': manual,
        'requestedItem': requestedItem,
        'requestedAmount': requestedAmount,
      };
}

class MerchantOffer {
  MerchantOffer({
    required this.planName,
    required this.price,
    this.purchased = false,
    this.pTibugSpecies,
  });
  final String planName;
  final int price;
  bool purchased;
  final PTibugSpecies? pTibugSpecies;
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
          : ForageMission._enumByName(
              ForageBiome.values,
              '${data['patrolBiome']}',
              ForageBiome.plaineRiche,
            ),
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
      autoPreferenceByMember: _readAutoPreferenceMap(
        data['autoPreferenceByMember'],
      ),
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
    return value.map((key, amount) => MapEntry('$key', _readStaticInt(amount)))
      ..removeWhere((_, amount) => amount <= 0);
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
    this.sourceBuildingId,
    this.mailbox = Zone0MessageMailbox.companions,
    this.subject,
    this.concerned,
    this.summary,
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
      vitalityRemaining: ForageMission._readStaticInt(
        data['vitalityRemaining'],
      ),
      hungerRemaining: ForageMission._readStaticInt(data['hungerRemaining']),
      moodLabel: '${data['moodLabel'] ?? 'Bien'}',
      finalStateLabel: '${data['finalStateLabel'] ?? ''}',
      baseRiskPercent: ForageMission._readStaticInt(data['baseRiskPercent']),
      securityAtLaunch: ForageMission._readStaticInt(data['securityAtLaunch']),
      securityReduction: ForageMission._readStaticInt(
        data['securityReduction'],
      ),
      realRiskPercent: ForageMission._readStaticInt(data['realRiskPercent']),
      completedAt:
          ForageMission._readDate(data['completedAt']) ?? DateTime.now(),
      inventoryFull: data['inventoryFull'] == true,
      sourceBuildingId: data['sourceBuildingId']?.toString(),
      mailbox: _mailboxFromValue(
        data['mailbox']?.toString(),
        data['sourceBuildingId']?.toString(),
      ),
      subject: data['subject']?.toString(),
      concerned: data['concerned']?.toString(),
      summary: data['summary']?.toString(),
      read: data['read'] == true,
    );
  }

  factory PtipoteMissionReport.system({
    required String message,
    String? sourceBuildingId,
    Zone0MessageMailbox mailbox = Zone0MessageMailbox.companions,
    String? subject,
    String? concerned,
    String? summary,
  }) {
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
      sourceBuildingId: sourceBuildingId,
      mailbox: mailbox,
      subject: subject,
      concerned: concerned,
      summary: summary ?? message,
    );
  }

  static Zone0MessageMailbox _mailboxFromValue(
    String? value,
    String? sourceBuildingId,
  ) {
    final stored = Zone0MessageMailbox.values.where(
      (mailbox) => mailbox.name == value,
    );
    if (stored.isNotEmpty) return stored.first;
    if (sourceBuildingId == 'kernel') return Zone0MessageMailbox.kernel;
    if (const <String>{
      'fablab',
      'cuisine',
      'atelier',
      'recycler',
    }.contains(sourceBuildingId)) {
      return Zone0MessageMailbox.fablab;
    }
    return Zone0MessageMailbox.companions;
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
  final String? sourceBuildingId;
  final Zone0MessageMailbox mailbox;
  final String? subject;
  final String? concerned;
  final String? summary;
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
      'sourceBuildingId': sourceBuildingId,
      'mailbox': mailbox.name,
      'subject': subject,
      'concerned': concerned,
      'summary': summary,
      'read': read,
    };
  }
}
