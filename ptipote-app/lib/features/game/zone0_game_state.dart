import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/notification_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/co_breeding.dart';
import '../figurines/ptipote_stats_config.dart';
import '../figurines/ptipote_v2.dart';
import 'building_construction_config.dart';
import 'camp_heart_config.dart';
import 'camp_generator_config.dart';
import 'community_roles_config.dart';
import 'housing_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'ptibug_valuation_service.dart';
import 'resident_economy_config.dart';
import 'remote_game_config_service.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'waste_recycler_config.dart';
import 'workshop_config.dart';

/// Keeps player-facing messages in the building that owns the activity.
/// Older saved reports fall back to the P'TIPOTE/PTIBUG mailbox.
enum Zone0MessageMailbox { companions, kernel, fablab }

enum RepairMiniGameType { colorMatch, pipes, waterSort }

/// Une tentative ne vit que le temps de l'écran : fermer totalement l'app
/// annule proprement la réparation, mais les rebuilds gardent le même jeu.
class RepairMiniGameAttempt {
  RepairMiniGameAttempt({
    required this.id,
    required this.buildingId,
    required this.repairGain,
    required this.buildingLevel,
    required this.gameType,
    required this.seed,
  });
  final String id;
  final String buildingId;
  final int repairGain;
  final int buildingLevel;
  final RepairMiniGameType gameType;
  final int seed;
  bool completed = false;
}

String _ptibugDataFamilyLabel(PTibugDataFamily family) => switch (family) {
      PTibugDataFamily.organique => 'Organique',
      PTibugDataFamily.minerale => 'Minérale',
      PTibugDataFamily.mycelienne => 'Mycélienne',
      PTibugDataFamily.toxine => 'Toxine',
      PTibugDataFamily.biomimetisme => 'Biomimétisme',
      PTibugDataFamily.energie => 'Énergie',
      PTibugDataFamily.comportementInsectoide => 'Comportement insectoïde',
    };

String _ptipoteTypeLabel(PtipoteTypeId type) => switch (type) {
      PtipoteTypeId.vegetal => 'Végétal',
      PtipoteTypeId.mineral => 'Minéral',
      PtipoteTypeId.mycelial => 'Mycélien',
    };

class Zone0GameState extends ChangeNotifier {
  static const String primaryMarketShopId = 'market-main';
  Zone0GameState._() {
    RemoteGameConfigService.instance.addListener(_onRemoteConfigChanged);
  }

  static final Zone0GameState instance = Zone0GameState._();
  final math.Random _random = math.Random();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, RepairMiniGameAttempt> _repairMiniGameAttempts =
      <String, RepairMiniGameAttempt>{};

  void _onRemoteConfigChanged() {
    _consumeManualWeatherTrigger();
    _refreshKernelPlanReadiness();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  final Map<String, int> vitalityOverrides = <String, int>{};
  final Map<String, int> hungerOverrides = <String, int>{};
  final Map<String, int> restOverrides = <String, int>{};
  // A P'TIPOTE earns the rest reward once per recovery cycle.
  final Set<String> wellRestedRewardedIds = <String>{};
  final Map<String, int> xpOverrides = <String, int>{};
  final Map<String, int> levelOverrides = <String, int>{};

  /// V2 game profiles are deliberately separate from the NFC figurine data.
  /// This gives physical scans and future co-bred companions one common game
  /// model without mutating an NFC source record.
  final Map<String, PtipoteV2Profile> ptipoteV2Profiles =
      <String, PtipoteV2Profile>{};
  final List<CoBreedingSession> coBreedingSessions = <CoBreedingSession>[];
  CoBreedingOffer? coBreedingOffer;
  final Map<String, CoBreedingEnvelopeOffer> coBreedingEnvelopeOffers =
      <String, CoBreedingEnvelopeOffer>{};
  final List<CoBreedingXpReward> coBreedingXpRewards = <CoBreedingXpReward>[];
  final List<CoBreedingArchive> coBreedingArchive = <CoBreedingArchive>[];
  int completedCoBreedingCount = 0;
  bool coBreedingUnlocked = false;
  bool coBreedingIntroMissionDismissed = false;
  bool coBreedingDevMode = false;
  DateTime? lastCoBreedingSelectionAt;
  CoBreedingConfig get coBreedingConfig {
    final v2 = ptipoteStatsConfig.v2;
    return CoBreedingConfig(
      enabled: v2.coBreedingEnabled,
      kernelUnlockLevel: v2.coBreedingKernelUnlockLevel,
      maxDurationHours: v2.coBreedingMaxDurationHours,
      finalProtectionWindowHours: v2.coBreedingFinalProtectionWindowHours,
      offlineGuaranteedRemainingHours:
          v2.coBreedingOfflineGuaranteedRemainingHours,
      capacityPerBreederLevel: v2.coBreedingCapacityPerBreederLevel,
      levelEarlyDeparture: v2.coBreedingLevelEarlyDeparture,
      offerRotationHours: v2.coBreedingOfferRotationHours,
      chooseTypeCost: v2.coBreedingChooseTypeCost,
      chooseExactPtipoteCost: v2.coBreedingChooseExactPtipoteCost,
      chooseExactEnvelopeCost: v2.coBreedingChooseExactEnvelopeCost,
      initialFreeCoBreedingEnabled: v2.coBreedingInitialFreeEnabled,
      devPoolMode: coBreedingDevMode
          ? CoBreedingPoolMode.publicAndDev
          : CoBreedingPoolMode.publicOnly,
    );
  }

  final Map<String, DateTime> lastCuddleAt = <String, DateTime>{};
  final Set<String> manualRestingIds = <String>{};
  // A P'TIPOTE can need rest even when every alcove is occupied. Keeping this
  // separately prevents an unavailable bed from granting alcove recovery.
  final Set<String> waitingForBedIds = <String>{};
  // Legacy active P'TIPOTES. V2 arrivalState is the source of truth for new
  // entries; this set is preserved solely for backward-compatible saves.
  final Set<String> hatchedPtipoteIds = <String>{};
  bool _legacyArrivalSnapshotPresent = false;
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<TowerMission> towerMissions = <TowerMission>[];
  final List<TowerBiomeResearch> towerBiomeResearch = <TowerBiomeResearch>[];
  final List<WorkshopCraftOrder> workshopOrders = <WorkshopCraftOrder>[];
  final List<PTibug> pTibugs = <PTibug>[];
  final List<PTibug> soldPTibugArchive = <PTibug>[];
  final List<PTibugTraitData> pTibugTraitData = <PTibugTraitData>[];
  final Set<PTibugModuleType> unlockedPTibugModules = <PTibugModuleType>{};
  final Set<PTibugSpecies> activePTibugPatterns = <PTibugSpecies>{};
  // The legacy P'TIBUG fields above remain loaded for existing accounts. The
  // collections below are the V1 scientific progression data.
  final Map<PTibugDataFamily, int> pTibugDataReserve = <PTibugDataFamily, int>{
    for (final family in PTibugDataFamily.values) family: 0,
  };
  final List<PTibugDataCell> pTibugDataCells = <PTibugDataCell>[];

  /// Patterns purchased from the Sourcier. They are Kernel stock, not active
  /// knowledge: Kernel prerequisites discover them, then Data Cells activate
  /// them through normal research.
  final Set<String> sourcierPatternIds = <String>{};
  final Map<String, PTibugPatternProgress> pTibugPatternProgress =
      <String, PTibugPatternProgress>{};
  final List<PTibugModuleInstance> pTibugModuleInstances =
      <PTibugModuleInstance>[];
  final List<PTibugModuleCraftOrder> pTibugModuleCraftOrders =
      <PTibugModuleCraftOrder>[];
  final List<PTibugCapsule> pTibugCapsules = <PTibugCapsule>[];
  int pTibugModuleCapacityLevel = 0;
  final Map<String, PTibugTerritoryBuilding> pTibugTerritoryBuildings =
      <String, PTibugTerritoryBuilding>{};
  bool starterPTibugChoiceMade = false;
  final Map<String, ConstructionProject> constructionProjects =
      <String, ConstructionProject>{};
  final List<PtipoteMissionReport> reports = <PtipoteMissionReport>[];
  final List<Zone0InventoryStack> marketStock = <Zone0InventoryStack>[];
  final List<MarketCustomerRequest> marketRequests = <MarketCustomerRequest>[];
  final List<MarketRequestLogEntry> marketRequestLog =
      <MarketRequestLogEntry>[];
  final List<MarketSourcierContract> marketContracts =
      <MarketSourcierContract>[];
  final List<MarketShop> marketShops = <MarketShop>[];
  final List<MarketShopSlot> marketShopSlots = <MarketShopSlot>[];
  final List<MarketRestockRule> marketRestockRules = <MarketRestockRule>[];
  bool marketShopSlotsMigrationCompleted = false;
  MarketShopConstructionOrder? marketShopConstructionOrder;

  /// Chantier communautaire distinct : il ne bloque jamais le chantier que le
  /// joueur prépare pour sa propre boutique.
  MarketShopConstructionOrder? residentCommunityShopConstructionOrder;
  DateTime? lastResidentCommunityShopConstructionAt;
  String primaryMarketShopSpecialization = 'general';
  bool primaryMarketShopChosen = false;
  int primaryMarketShopLevel = 1;
  final Set<String> activeMarketLicenses = <String>{};
  final MarketDistributorState marketDistributor = MarketDistributorState();
  int sourcierConfidence = 0;
  bool firstFreeShopClaimed = false;
  final Map<ForageBiome, BiomeSecurityState> biomeSecurity =
      <ForageBiome, BiomeSecurityState>{
    for (final biome in ForageBiome.values)
      biome: BiomeSecurityState.initial(biome),
  };

  /// Un emplacement territorial par biome, distinct des refuges P'TIBUG.
  final Map<ForageBiome, LisiereTerritoryZone> lisiereTerritoryZones =
      <ForageBiome, LisiereTerritoryZone>{
    for (final biome in ForageBiome.values)
      biome: LisiereTerritoryZone.initial(biome),
  };
  final List<BiomeExplorationMission> explorationMissions =
      <BiomeExplorationMission>[];
  final List<WeatherAlert> weatherAlerts = <WeatherAlert>[];
  GlobalWeatherEvent? activeGlobalWeatherEvent;
  GlobalWeatherEvent? nextGlobalWeatherEvent;
  int globalWeatherConsecutiveAdverseEvents = 0;
  int globalWeatherConsecutiveSevereEvents = 0;

  /// Etat persistant unique par bâtiment. Les clés sont les identifiants de
  /// bâtiment déjà employés par les projets et les écrans, jamais des widgets.
  final Map<String, BuildingViabilityState> buildingViabilities =
      <String, BuildingViabilityState>{};
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
  final Map<String, Map<PTibugDataFamily, int>> kernelPlanDataInvestments =
      <String, Map<PTibugDataFamily, int>>{};
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

  /// Couche sociale minimale : des identités stables, sans simulation de
  /// métier, famille ou besoins individuels.
  final List<Zone0Resident> residents = <Zone0Resident>[];
  final List<ResidentHouse> residentHouses = <ResidentHouse>[];
  final List<ResidentArrivalCandidate> residentArrivalCandidates =
      <ResidentArrivalCandidate>[];
  final List<ResidentVision> residentVisions = <ResidentVision>[];
  final List<HouseholdRepairJob> householdRepairJobs = <HouseholdRepairJob>[];
  DateTime? lastResidentArrivalResolutionAt;
  DateTime? residentAutonomyGraceUntil;
  final List<CommunityRoleAssignment> communityRoleAssignments =
      <CommunityRoleAssignment>[];
  final List<CommunityProductionBatch> communityProductionBatches =
      <CommunityProductionBatch>[];
  final List<ResidentEconomicTransaction> residentEconomicTransactions =
      <ResidentEconomicTransaction>[];
  final List<EconomicSettlementBatch> economicSettlementBatches =
      <EconomicSettlementBatch>[];
  final List<ResidentUncoveredNeed> residentUncoveredNeeds =
      <ResidentUncoveredNeed>[];
  bool residentPassionMigrationCompleted = false;
  DateTime? lastCommunityRoleResolutionAt;
  bool residentEconomyMigrationCompleted = false;
  DateTime? lastResidentEconomyResolvedAt;
  String lastEconomicSettlementDayKey = '';
  bool residentPopulationMigrationCompleted = false;

  /// V2 needs migration is kept separately from the V1 population bridge so
  /// opening an old save cannot repeatedly reset meals or duplicate items.
  bool residentNeedsMigrationCompleted = false;
  DateTime? residentNeedsGraceUntil;
  String lastResidentNeedsResolutionDayKey = '';
  final Set<String> resolvedResidentWeatherEventIds = <String>{};
  DateTime? lastDomesticEnergyDistributionAt;
  // The generator data itself remains in the established campGenerator save
  // block. This flag moves its ownership and UI to the player's House without
  // resetting its stock, timer, upgrades, or production history.
  bool bioGeneratorMovedToPlayerHouse = false;
  final Map<String, CommunityProjectProgress> communityProjects =
      <String, CommunityProjectProgress>{};
  final Set<String> resolvedWeatherStockLossEventIds = <String>{};
  WeatherStockIncident? lastWeatherStockIncident;
  int protectedBatteryChestLevel = 0;
  CommunityConstructionThanks? communityConstructionThanks;
  int plaineNurseryLevel = 0;

  /// Legacy direct craft. Existing orders complete once after migration; all
  /// new creations go through an Armature then a cultivation tank.
  PTibugCreationOrder? pTibugCreationOrder;
  final List<PTibugArmature> pTibugArmatures = <PTibugArmature>[];
  final List<PTibugCultivationTank> pTibugCultivationTanks =
      <PTibugCultivationTank>[];
  final List<PTibugCultivationOperation> pTibugCultivationOperations =
      <PTibugCultivationOperation>[];
  final List<PTibugAspectMatrix> pTibugAspectMatrices = <PTibugAspectMatrix>[];
  PTibugAspectExtractionOrder? pTibugAspectExtractionOrder;
  int pTibugAspectExtractorLevel = 1;
  bool firstCultivationTankGranted = false;
  int securityTowerLevel = 0;
  bool towerWeatherModuleInstalled = false;
  bool towerResearchModuleInstalled = false;
  int marketLevel = 0;
  int currentPopulation = kernelConfig.startingPopulation;
  int kernelTrustLevel = 1;
  int kernelTrustXp = 0;
  int bioBatteries = kernelConfig.startingBioBatteries;

  /// Monnaie fine du Marché. Cent bio-piles sont automatiquement compactées
  /// en une bio-batterie, sans modifier les coûts existants en batteries.
  int bioPiles = 0;
  bool energyCorePatternDiscovered = false;
  bool energyCoreWarning600Shown = false;
  bool energyCoreWarning699Shown = false;
  int storedEnergyCores = 0;
  int energyUnits = 0;
  int recyclerLevel = 0;
  int recyclerWasteTank = 0;
  int recyclerOutputOrganic = 0;
  int recyclerOutputMineral = 0;
  int recyclerOutputOther = 0;
  bool recyclerBiologicalOrientationInstalled = false;
  bool recyclerBiologicalOrientationActive = false;
  RecyclerBatchSnapshot? recyclerActiveBatch;
  int pendingWaste = 0;
  DateTime? recyclerCycleStartedAt;
  DateTime? lastWasteGenerationAt;
  DateTime? lastCampWasteCalculationAt;
  double campWasteRemainder = 0;
  final List<CampWasteDailyReport> campWasteDailyReports =
      <CampWasteDailyReport>[];
  int campWellbeing = kernelConfig.startingWellbeing;
  int mealsPrepared = 0;
  int plaineMissionsCompleted = 0;
  int generatorOrganic = 0;
  int generatorMineral = 0;
  int generatorTotalProduced = 0;
  DateTime? generatorCycleStartedAt;
  // Compatibilité de lecture uniquement : les anciennes sauvegardes pouvaient
  // contenir un cycle de vente autonome. Les ventes passent désormais
  // exclusivement par une demande habitant ou un contrat du Sourcier.
  DateTime? marketNextSaleAt;
  DateTime? marketNextRequestAt;
  DateTime? marketLastWorkTickAt;
  DateTime? marketLastXpTickAt;
  DateTime? marketAssignedAt;
  int marketXpEarnedThisAssignment = 0;
  int marketBioPilesEarnedThisAssignment = 0;
  int marketArticlesSoldThisAssignment = 0;
  int marketDistributorsRepairedThisAssignment = 0;
  DateTime? lastManualTowerRechargeAt;
  DateTime? merchantAvailableUntil;
  DateTime? merchantNextArrivalAt;
  DateTime? merchantCallRequestedAt;
  String merchantVisitsDayKey = '';
  int merchantVisitsToday = 0;
  String? marketAssignedPtipoteId;
  String? marketAssignedPtipoteName;
  final Set<String> marketRestockEnabledItems = <String>{};
  final Map<String, int> marketRestockMinimums = <String, int>{};
  int marketValueRemainder = 0;
  int marketBioBatteriesEarned = 0;
  final Set<String> towerAssignedIds = <String>{};
  DateTime? lastFirebaseSyncAt;
  DateTime? lastSimulationAt;
  String? lastFirebaseError;
  String firebaseSyncLabel = 'Non synchronisé';
  bool isFirebaseSyncing = false;
  bool _loadedFromFirebase = false;
  Future<void> _firebaseWriteQueue = Future<void>.value();
  int _firebaseSyncCount = 0;

  /// Empêche les actions de simulation d'écraser les données avant le chargement.
  bool get hasLoadedFromFirebase => _loadedFromFirebase;

  bool get isFablabBuilt => atelierLevel >= fablabConfig.cuisineUnlockLevel;
  bool get isSecurityTowerBuilt => securityTowerLevel >= 1;
  bool get isTowerWeatherUnlocked =>
      isSecurityTowerBuilt && towerWeatherModuleInstalled;
  bool get isTowerResearchUnlocked =>
      isSecurityTowerBuilt && towerResearchModuleInstalled;
  bool get isMarketBuilt => marketLevel >= 1;
  bool get isPlaineNurseryBuilt => plaineNurseryLevel >= 1;

  static const String plaineNurseryTerritoryId = 'nursery-plaine';

  PTibugTerritoryBuilding? territoryBuildingForId(String? id) =>
      id == null ? null : pTibugTerritoryBuildings[id];

  String refugeTerritoryId(ForageBiome biome) => 'refuge-${biome.name}';

  PTibugTerritoryBuilding? refugeForBiome(ForageBiome biome) =>
      territoryBuildingForId(refugeTerritoryId(biome));

  bool _isRefugeTarget(String targetId) => targetId.startsWith('refuge-');

  ForageBiome? _refugeBiomeForTarget(String targetId) {
    if (!_isRefugeTarget(targetId)) return null;
    final name = targetId.substring('refuge-'.length);
    return ForageBiome.values.where((biome) => biome.name == name).firstOrNull;
  }

  bool isTerritoryUnderConstruction(PTibugTerritoryBuilding building) =>
      constructionProjects[building.id]?.isInProgress ?? false;

  BuildingViabilityState viabilityForBuilding(String buildingId) =>
      buildingViabilities.putIfAbsent(
        buildingId,
        () => BuildingViabilityState.fresh(
          buildingId,
          maximum: towerOperationsConfig.buildingViability.maximumViability,
          initial: towerOperationsConfig.buildingViability.initialViability,
        ),
      );

  int buildingLevelForViability(String buildingId) {
    final biofermenterBiome = _biofermenterBiomeForTarget(buildingId);
    if (biofermenterBiome != null) {
      return territoryZone(biofermenterBiome).buildingLevel;
    }
    final territory = territoryBuildingForId(buildingId);
    if (territory != null) return territory.level;
    return switch (buildingId) {
      'fablab' || 'atelier' => atelierLevel,
      'cuisine' => cuisineLevel,
      'recycler' => recyclerLevel,
      'generator' || 'house' => houseLevel,
      'market' => marketLevel,
      'securityTower' => securityTowerLevel,
      'campHeart' => _lastKnownCampHeartLevel,
      _ => 1,
    };
  }

  ForageBiome buildingBiomeForViability(String buildingId) =>
      _biofermenterBiomeForTarget(buildingId) ??
      territoryBuildingForId(buildingId)?.biome ??
      ForageBiome.plaineRiche;

  int structuralProtectionSlotsFor(String buildingId) => math.max(
        0,
        buildingLevelForViability(buildingId) *
            towerOperationsConfig.buildingViability.slotsPerLevel,
      );

  bool isBuildingOperational(String buildingId) =>
      !viabilityForBuilding(buildingId).isDisabled;

  bool isBuildingDegraded(String buildingId) =>
      viabilityForBuilding(buildingId).isDegraded(
        towerOperationsConfig.buildingViability.degradedThreshold,
      );

  double buildingCraftDurationMultiplier(String buildingId) =>
      isBuildingDegraded(buildingId)
          ? 1 +
              towerOperationsConfig.buildingViability.degradedCraftTimePercent /
                  100
          : 1;

  Map<String, int> buildingCraftCosts(
      String buildingId, Map<String, int> costs) {
    if (!isBuildingDegraded(buildingId)) return Map<String, int>.from(costs);
    final factor = 1 +
        towerOperationsConfig.buildingViability.degradedCraftCostPercent / 100;
    return costs.map((key, value) => MapEntry(key, (value * factor).ceil()));
  }

  double buildingProductionMultiplier(String buildingId) =>
      isBuildingDegraded(buildingId)
          ? 1 -
              towerOperationsConfig
                      .buildingViability.degradedProductionPercent /
                  100
          : 1;

  Zone0ActionResult restartBuildingByPayment(String buildingId) {
    final viability = viabilityForBuilding(buildingId);
    if (!viability.isDisabled) {
      return const Zone0ActionResult(
          success: false, message: 'Ce bâtiment fonctionne déjà.');
    }
    final config = towerOperationsConfig.buildingViability;
    final costs = <String, int>{
      'Organique': config.restartOrganicCost,
      'Minéral': config.restartMineralCost
    };
    if (!hasResources(costs) || bioBatteries < config.restartBioBatteryCost) {
      return const Zone0ActionResult(
          success: false,
          message:
              'Ressources insuffisantes pour remettre ce bâtiment en marche.');
    }
    if (!removeResources(costs)) {
      return const Zone0ActionResult(
          success: false, message: 'Transaction indisponible.');
    }
    bioBatteries -= config.restartBioBatteryCost;
    viability.restoreToMinimum(config.restartViability);
    _reportBuildingViability(buildingId, 'fonctionne de nouveau.');
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: 'Bâtiment remis en marche.');
  }

  Zone0ActionResult restartBuildingByMiniGame(String buildingId) {
    final viability = viabilityForBuilding(buildingId);
    if (!viability.isDisabled) {
      return const Zone0ActionResult(
          success: false, message: 'Ce bâtiment fonctionne déjà.');
    }
    viability.restoreToMinimum(
        towerOperationsConfig.buildingViability.restartViability);
    _reportBuildingViability(
        buildingId, 'fonctionne de nouveau après diagnostic.');
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true,
        message: 'Diagnostic réussi : bâtiment remis en marche.');
  }

  int buildingRepairLevel(String buildingId) =>
      math.max(1, buildingLevelForViability(buildingId));

  Map<String, int> buildingRepairCosts(String buildingId, int requestedGain) {
    return buildingRepairCostsForLevel(
      buildingRepairLevel(buildingId),
      requestedGain,
    );
  }

  Map<String, int> buildingRepairCostsForLevel(
    int buildingLevel,
    int requestedGain,
  ) {
    final steps = (math.max(1, requestedGain) / 10).ceil();
    final perStep = towerOperationsConfig.buildingViability
        .repairCostsForLevel(buildingLevel);
    return <String, int>{
      for (final entry in perStep.entries) entry.key: entry.value * steps,
    };
  }

  int get bioBatteryBalanceInPiles => bioBatteries * 100 + bioPiles;

  bool canSpendBioBatteryPiles(int piles) =>
      piles >= 0 && bioBatteryBalanceInPiles >= piles;

  /// Bio-piles are cents, not a separate wallet. Every debit therefore uses
  /// the combined balance and normalizes it back to batteries + remainder.
  bool _spendBioBatteryPiles(int piles) {
    if (!canSpendBioBatteryPiles(piles)) return false;
    final remaining = bioBatteryBalanceInPiles - piles;
    bioBatteries = remaining ~/ 100;
    bioPiles = remaining % 100;
    return true;
  }

  int _repairCurrencyCostInPiles(Map<String, int> costs) =>
      (costs['Bio-batteries'] ?? 0) * 100 + (costs['Bio-piles'] ?? 0);

  String _formatBioBatteryPiles(int piles) {
    final batteries = piles ~/ 100;
    final remainder = piles % 100;
    if (remainder == 0)
      return '$batteries Bio-batterie${batteries == 1 ? '' : 's'}';
    return '$batteries,${remainder.toString().padLeft(2, '0')} Bio-batterie';
  }

  String _repairCostSummary(Map<String, int> costs) {
    final resourceCosts = costs.entries
        .where((entry) =>
            entry.value > 0 &&
            entry.key != 'Bio-batteries' &&
            entry.key != 'Bio-piles')
        .map((entry) => '${entry.value} ${entry.key}');
    final currency = _repairCurrencyCostInPiles(costs);
    return <String>[
      ...resourceCosts,
      if (currency > 0) _formatBioBatteryPiles(currency),
    ].join(' · ');
  }

  String buildingRepairCostLabel(Map<String, int> costs) =>
      _repairCostSummary(costs);

  void _awardPlayerBuildingRepairXp() {
    _addKernelAxisXp(KernelAxis.builder, 5);
    _refreshKernelPlanReadiness();
  }

  Zone0ActionResult repairBuilding(String buildingId, {int gain = 10}) {
    final viability = viabilityForBuilding(buildingId);
    if (viability.current >= viability.maximum) {
      return const Zone0ActionResult(
          success: false, message: 'La Viabilité est déjà maximale.');
    }
    final requestedGain = (gain / 10).ceil().clamp(1, 10) * 10;
    final actualGain =
        math.min(requestedGain, viability.maximum - viability.current).toInt();
    final costs = buildingRepairCosts(buildingId, actualGain);
    final materials = Map<String, int>.fromEntries(costs.entries.where(
      (entry) => entry.key != 'Bio-batteries' && entry.key != 'Bio-piles',
    ));
    final currencyPiles = _repairCurrencyCostInPiles(costs);
    if (!canSpendBioBatteryPiles(currencyPiles) ||
        !hasResources(materials) ||
        !removeResources(materials)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources insuffisantes pour réparer.');
    }
    _spendBioBatteryPiles(currencyPiles);
    viability.restore(actualGain);
    _awardPlayerBuildingRepairXp();
    if (viability.current >= viability.maximum) {
      _reportBuildingViability(buildingId, 'est entièrement réparé.');
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '+$actualGain% de Viabilité · ${_repairCostSummary(costs)}.');
  }

  RepairMiniGameAttempt? repairMiniGameAttemptFor(String attemptId) =>
      _repairMiniGameAttempts[attemptId];

  RepairMiniGameAttempt? beginInteractiveRepair(String buildingId,
      {required int gain, RepairMiniGameType? forcedGame}) {
    final houseId = buildingId.startsWith('resident-house:')
        ? buildingId.substring(15)
        : null;
    final house = houseId == null ? null : residentHouseForId(houseId);
    final viability = house == null ? viabilityForBuilding(buildingId) : null;
    final current = house?.currentViability ?? viability!.current;
    final maximum = house?.maximumViability ?? viability!.maximum;
    if (!towerOperationsConfig.buildingViability.repairMiniGames.enabled ||
        current >= maximum) return null;
    final actualGain = math
        .min(
          ((gain / 10).ceil().clamp(1, 10) * 10).toInt(),
          maximum - current,
        )
        .toInt();
    if (actualGain <= 0) return null;
    final cfg = towerOperationsConfig.buildingViability.repairMiniGames;
    final weighted = <RepairMiniGameType, int>{
      RepairMiniGameType.colorMatch: cfg.colorMatchWeight,
      RepairMiniGameType.pipes: cfg.pipesWeight,
      RepairMiniGameType.waterSort: cfg.waterSortWeight,
    };
    final total =
        weighted.values.fold<int>(0, (sum, value) => sum + math.max(0, value));
    var roll = total <= 0 ? 0 : _random.nextInt(total);
    RepairMiniGameType selected = RepairMiniGameType.colorMatch;
    if (forcedGame != null) {
      selected = forcedGame;
    } else {
      for (final entry in weighted.entries) {
        roll -= math.max(0, entry.value);
        if (roll < 0) {
          selected = entry.key;
          break;
        }
      }
    }
    final id =
        'repair-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';
    final attempt = RepairMiniGameAttempt(
      id: id,
      buildingId: buildingId,
      repairGain: actualGain,
      buildingLevel: house == null ? buildingRepairLevel(buildingId) : 1,
      gameType: selected,
      seed: _random.nextInt(1 << 31),
    );
    _repairMiniGameAttempts[id] = attempt;
    return attempt;
  }

  void cancelInteractiveRepair(String attemptId) =>
      _repairMiniGameAttempts.remove(attemptId);

  Zone0ActionResult completeInteractiveRepair(String attemptId) {
    final attempt = _repairMiniGameAttempts[attemptId];
    if (attempt == null || attempt.completed) {
      return const Zone0ActionResult(
          success: false, message: 'Cette réparation a déjà été traitée.');
    }
    final houseId = attempt.buildingId.startsWith('resident-house:')
        ? attempt.buildingId.substring(15)
        : null;
    final house = houseId == null ? null : residentHouseForId(houseId);
    final viability =
        house == null ? viabilityForBuilding(attempt.buildingId) : null;
    final current = house?.currentViability ?? viability!.current;
    final maximum = house?.maximumViability ?? viability!.maximum;
    if (current >= maximum) {
      return const Zone0ActionResult(
          success: false, message: 'La Viabilité est déjà maximale.');
    }
    attempt.completed = true;
    final gain = math.min(attempt.repairGain, maximum - current).toInt();
    if (house == null) {
      viability!.restore(gain);
    } else {
      house.currentViability += gain;
      house.updatedAt = DateTime.now();
    }
    // Le mini-jeu remplace uniquement le coût : aucune XP ni ressource bonus.
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: 'Réparation terminée : +$gain% de Viabilité.');
  }

  /// Compatibilité avec l'ancien prototype de tuyaux : les nouveaux écrans
  /// utilisent [completeInteractiveRepair] afin de respecter le gain choisi.
  Zone0ActionResult repairBuildingByMiniGame(String buildingId) {
    final viability = viabilityForBuilding(buildingId);
    if (viability.current >= viability.maximum) {
      return const Zone0ActionResult(
          success: false, message: 'La Viabilité est déjà maximale.');
    }
    final gain = math.min(10, viability.maximum - viability.current).toInt();
    viability.restore(gain);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Circuit réparé : +$gain% de Viabilité.',
    );
  }

  /// A finished repair kit is deliberately more effective than raw materials.
  /// It is consumed atomically so a persisted action can never reuse it.
  Zone0ActionResult repairBuildingWithKit(String buildingId) {
    final viability = viabilityForBuilding(buildingId);
    if (viability.current >= viability.maximum) {
      return const Zone0ActionResult(
          success: false, message: 'La Viabilité est déjà maximale.');
    }
    const kit = 'Kit de réparation domestique';
    if (resourceAmount(kit) < 1 || removeResource(kit, 1) <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Un Kit de réparation est requis.');
    }
    final gain = math.min(15, viability.maximum - viability.current).toInt();
    viability.restore(gain);
    _awardPlayerBuildingRepairXp();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Kit de réparation utilisé : +$gain% de Viabilité.',
    );
  }

  int structuralProtectionReductionPercent(
    String buildingId,
    TowerWeatherType weather,
  ) {
    final state = viabilityForBuilding(buildingId);
    final matching = state.installedStructuralProtections
        .where(
          (item) => switch (item) {
            StructuralProtectionType.ventilationTermite =>
              weather == TowerWeatherType.heatWave,
            StructuralProtectionType.chloroCanaux =>
              weather == TowerWeatherType.heavyRain,
            StructuralProtectionType.filtration =>
              weather == TowerWeatherType.toxicCloud,
          },
        )
        .length;
    final reductions =
        towerOperationsConfig.buildingViability.protectionReductionPercents;
    if (reductions.isEmpty) return 0;
    var total = 0;
    for (var index = 0; index < matching; index++) {
      total +=
          reductions[index < reductions.length ? index : reductions.length - 1];
    }
    return total.clamp(
        0, towerOperationsConfig.buildingViability.protectionCapPercent);
  }

  /// Cartouches are stored by the filtering installation itself.  They are
  /// consumed before the building has to absorb the toxic event.  A partial
  /// stock is consumed, but cannot claim the full filtration bonus.
  bool _consumeStructuralFilterCartridges(
    Map<String, int> inventory,
    List<StructuralProtectionType> installations,
    GlobalWeatherEvent event,
  ) {
    if (event.type != TowerWeatherType.toxicCloud ||
        !installations.contains(StructuralProtectionType.filtration)) {
      return true;
    }
    final needed = weatherProtectionUsesFor(event.intensity);
    final stored = inventory['Cartouche de filtration'] ?? 0;
    final ready = stored >= needed;
    final consumed = math.min(stored, needed);
    if (consumed > 0) {
      final remaining = stored - consumed;
      if (remaining <= 0) {
        inventory.remove('Cartouche de filtration');
      } else {
        inventory['Cartouche de filtration'] = remaining;
      }
    }
    return ready;
  }

  Zone0ActionResult addFilterCartridgesToBuilding(
    String buildingId, {
    int quantity = 1,
  }) =>
      addStructuralConsumableToBuilding(
        buildingId,
        requiredInstallation: StructuralProtectionType.filtration,
        itemName: 'Cartouche de filtration',
        quantity: quantity,
      );

  /// Generic reserve for installations that consume an item before their own
  /// durability can be affected. New structural systems only need to declare
  /// their installation/item pair in the UI; the transfer remains atomic.
  Zone0ActionResult addStructuralConsumableToBuilding(
    String buildingId, {
    required StructuralProtectionType requiredInstallation,
    required String itemName,
    int quantity = 1,
  }) {
    final state = viabilityForBuilding(buildingId);
    if (!state.installedStructuralProtections.contains(requiredInstallation)) {
      return const Zone0ActionResult(
          success: false, message: 'Installation requise.');
    }
    final safeQuantity = math.max(1, quantity);
    if (resourceAmount(itemName) < safeQuantity ||
        removeResource(itemName, safeQuantity) <= 0) {
      return Zone0ActionResult(
        success: false,
        message: '$itemName insuffisant${safeQuantity > 1 ? 's' : ''}.',
      );
    }
    state.structuralConsumables.update(
      itemName,
      (value) => value + safeQuantity,
      ifAbsent: () => safeQuantity,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '$safeQuantity $itemName ajouté${safeQuantity > 1 ? 's' : ''}.');
  }

  Zone0ActionResult addFilterCartridgesToHouse(
    String houseId, {
    int quantity = 1,
  }) {
    final house = residentHouseForId(houseId);
    if (house == null) {
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    }
    if (!house.installedStructuralProtections
        .contains(StructuralProtectionType.filtration)) {
      return const Zone0ActionResult(
          success: false, message: 'Installation filtrante requise.');
    }
    final safeQuantity = math.max(1, quantity);
    if (!_consumeHouseholdInventoryItem(
          house,
          'Cartouche de filtration',
          quantity: safeQuantity,
        ) &&
        (resourceAmount('Cartouche de filtration') < safeQuantity ||
            removeResource('Cartouche de filtration', safeQuantity) <= 0)) {
      return const Zone0ActionResult(
          success: false, message: 'Cartouches de filtration insuffisantes.');
    }
    house.structuralConsumables.update(
      'Cartouche de filtration',
      (value) => value + safeQuantity,
      ifAbsent: () => safeQuantity,
    );
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$safeQuantity cartouche(s) ajoutée(s) à la filtration.');
  }

  Zone0ActionResult installStructuralProtection(
    String buildingId,
    StructuralProtectionType type,
  ) {
    final state = viabilityForBuilding(buildingId);
    if (state.installedStructuralProtections.length >=
        structuralProtectionSlotsFor(buildingId)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Aucun emplacement d’installation disponible.');
    }
    final item = switch (type) {
      StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
      StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
      StructuralProtectionType.filtration => 'Installation filtrante',
    };
    if (resourceAmount(item) < 1 || removeResource(item, 1) <= 0) {
      return Zone0ActionResult(
          success: false, message: '$item requis dans l’inventaire.');
    }
    state.installedStructuralProtections.add(type);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(success: true, message: '$item installé.');
  }

  Zone0ActionResult removeStructuralProtection(
    String buildingId,
    StructuralProtectionType type,
  ) {
    final state = viabilityForBuilding(buildingId);
    if (!state.installedStructuralProtections.remove(type)) {
      return const Zone0ActionResult(
          success: false, message: 'Installation introuvable.');
    }
    final item = switch (type) {
      StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
      StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
      StructuralProtectionType.filtration => 'Installation filtrante',
    };
    final result = addResources(<String, int>{item: 1});
    if (result.pending.isNotEmpty) {
      state.installedStructuralProtections.add(type);
      return const Zone0ActionResult(
          success: false, message: 'Inventaire plein : retrait impossible.');
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$item retiré et replacé dans l’inventaire.');
  }

  void _applyWeatherViabilityDamage(GlobalWeatherEvent event) {
    if (event.type == TowerWeatherType.calm) return;
    final candidates = <String>{
      if (isFablabBuilt) 'fablab',
      if (atelierLevel > 0) 'atelier',
      if (cuisineLevel > 0) 'cuisine',
      if (recyclerLevel > 0) 'recycler',
      if (isMarketBuilt) 'market',
      if (isSecurityTowerBuilt) 'securityTower',
      'house',
      'campHeart',
      ...activePTibugTerritories.map((building) => building.id),
      ...lisiereTerritoryZones.values
          .where((zone) => zone.buildingId == 'biofermenter')
          .map((zone) => biofermenterTargetId(zone.biome)),
    };
    final config = towerOperationsConfig.buildingViability;
    final territoryIds =
        activePTibugTerritories.map((building) => building.id).toSet();
    var territoryDamage = 0;
    var damagedTerritories = 0;
    for (final buildingId in candidates) {
      if (constructionProjects[buildingId]?.isInProgress == true) continue;
      final state = viabilityForBuilding(buildingId);
      if (state.lastDamageEventId == event.id) continue;
      final impact = event.affectedBiomes
          .where((item) => item.biome == buildingBiomeForViability(buildingId))
          .firstOrNull;
      state.lastDamageEventId = event.id;
      if (impact == null || !impact.isAffected) continue;
      final filtrationReady = _consumeStructuralFilterCartridges(
        state.structuralConsumables,
        state.installedStructuralProtections,
        event,
      );
      final raw = config.damageFor(event.type, event.intensity) *
          impact.localImpactMultiplier;
      final protection = ((filtrationReady
                  ? structuralProtectionReductionPercent(buildingId, event.type)
                  : 0) +
              globalWeatherProtectionPercent(event.type))
          .clamp(0, config.protectionCapPercent);
      final reduced = raw * (1 - protection / 100);
      final damage = reduced.ceil();
      if (damage <= 0) continue;
      final previous = state.current;
      state.current = math.max(0, state.current - damage);
      final actualDamage = previous - state.current;
      if (territoryIds.contains(buildingId) && actualDamage > 0) {
        territoryDamage += actualDamage;
        damagedTerritories++;
      }
      state.lastViabilityUpdateAt = DateTime.now();
      if (state.current == 0) {
        state.restartRequired = true;
        _reportBuildingViability(buildingId,
            'est hors service après ${_weatherTypeLabel(event.type)}.');
      } else if (previous >= config.degradedThreshold &&
          state.current < config.degradedThreshold) {
        state.viabilityWarningShown = true;
        _reportBuildingViability(
            buildingId, 'est endommagé et fonctionne en mode dégradé.');
      }
    }
    if (damagedTerritories > 0) {
      final average = territoryDamage / damagedTerritories;
      reports.add(PtipoteMissionReport.system(
        message:
            'Refuges P’TIBUG : ${average.toStringAsFixed(1)}% de Viabilité perdue en moyenne ($territoryDamage% au total).',
        sourceBuildingId: 'campHeart',
        subject: 'Bilan météo',
        concerned: 'Refuges P’TIBUG',
        summary: '$damagedTerritories refuge(s) touché(s).',
      ));
    }
  }

  void _migrateResidentsAndHouses() {
    // Existing saves can already contain named residents. Only bridge the
    // former aggregate value once and never manufacture a second population.
    final targetResidents =
        math.max(0, math.max(currentPopulation, residents.length));
    while (residents.length < targetResidents) {
      final index = residents.length;
      residents.add(Zone0Resident(
        id: 'resident-migrated-${index + 1}',
        displayName: _residentNameFor(index),
        createdAt: DateTime.now(),
        internalPileBalance: housingConfig.residentInitialPileBalance,
        sourceMigrationId: 'abstract-population-v1',
      ));
    }
    // The old aggregate model did not necessarily persist actual homes. On
    // its single migration, materialize only the minimum functional houses
    // necessary to preserve the existing population. Later arrivals may be
    // awaiting housing; they never create free homes automatically.
    final requiredMigrationHouses = residentPopulationMigrationCompleted
        ? housingUnits
        : math.max(
            housingUnits,
            (targetResidents / housingConfig.residentsPerHousingUnit).ceil(),
          );
    housingUnits = math.max(housingUnits, requiredMigrationHouses);
    // Do not destroy identities when a temporary population value falls.
    while (residentHouses.length < requiredMigrationHouses) {
      final index = residentHouses.length;
      residentHouses.add(ResidentHouse(
        id: 'house-${index + 1}',
        displayName: 'Maison ${index + 1}',
        biome: ForageBiome.plaineRiche,
        capacity: housingConfig.residentsPerHousingUnit,
      ));
    }
    for (final house in residentHouses) {
      house.capacity = housingConfig.residentsPerHousingUnit;
      house.weatherProtectionSlots = housingConfig.houseProtectionSlots;
      house.furnitureSlots = housingConfig.residentFurnitureSlots;
      house.additionalGeneratorSlots = housingConfig.additionalGeneratorSlots;
      house.baseGeneratorInstalled = true;
      house.residentIds.removeWhere(
        (id) => !residents.any((resident) => resident.id == id),
      );
    }
    for (final resident in residents) {
      final assigned = residentHouseForId(resident.houseId);
      if (assigned == null || !assigned.residentIds.contains(resident.id)) {
        resident.houseId = null;
        final house = residentHouses
            .where((item) => item.residentIds.length < item.capacity)
            .firstOrNull;
        if (house != null) {
          house.residentIds.add(resident.id);
          resident.houseId = house.id;
        }
      }
      resident.status = resident.houseId == null
          ? ResidentStatus.awaitingHousing
          : ResidentStatus.active;
      resident.currentHappiness = residentHappinessFor(resident);
      resident.updatedAt = DateTime.now();
    }
    currentPopulation = math.max(currentPopulation, residents.length);
    housingCapacity = residentHouses.fold<int>(
      0,
      (total, house) => total + house.capacity,
    );
    residentPopulationMigrationCompleted = true;
    bioGeneratorMovedToPlayerHouse = true;
  }

  /// Resident and household accounting is kept in piles. It intentionally
  /// does not create physical Energy Cores or modify the player HUD.
  String formatInternalPileBalance(int piles) {
    final safe = math.max(0, piles);
    final batteries = safe ~/ 100;
    final remainingPiles = safe % 100;
    if (batteries == 0) return '$remainingPiles bio-pile(s)';
    if (remainingPiles == 0) return '$batteries bio-batterie(s)';
    return '$batteries bio-batterie(s) · $remainingPiles bio-pile(s)';
  }

  /// Resolves physical household energy first, then shares only whole piles
  /// between the active occupants. Per-house timestamps make a move safe: the
  /// old house is settled before the resident list changes and no period can
  /// be credited twice after an offline return.
  bool resolveResidentDomesticGeneration({DateTime? now}) {
    if (!residentEconomyConfig.enabled) return false;
    final current = now ?? DateTime.now();
    var changed = false;
    for (final house in residentHouses) {
      final previous = house.lastHouseholdEnergyResolvedAt ??
          house.lastEnergyDistributionAt ??
          lastDomesticEnergyDistributionAt;
      if (previous == null) {
        house.lastHouseholdEnergyResolvedAt = current;
        house.lastEnergyDistributionAt = current;
        continue;
      }
      final elapsedSeconds = current.difference(previous).inSeconds;
      if (elapsedSeconds <= 0) continue;
      final occupants = residents
          .where(
              (resident) => resident.isActive && resident.houseId == house.id)
          .toList(growable: false);
      if (house.baseGeneratorInstalled &&
          (occupants.isNotEmpty ||
              housingConfig.domesticGeneratorRunsWhenEmpty)) {
        final baseHundredths =
            housingConfig.domesticGeneratorPilesPerHour * 100;
        final rateHundredths = baseHundredths +
            (house.additionalGeneratorInstalled
                ? (baseHundredths *
                    residentEconomyConfig.secondGeneratorBonusPercent ~/
                    100)
                : 0);
        final accumulated = house.energyProductionRemainder +
            elapsedSeconds * math.max(0, rateHundredths);
        final onePile = Duration.secondsPerHour * 100;
        final generated = accumulated ~/ onePile;
        house.energyProductionRemainder = (accumulated % onePile).toInt();
        if (generated > 0) {
          final cap = residentEconomyConfig.householdAccountCapPiles;
          final accepted = math.max(
              0, math.min(generated, cap - house.householdPileBalance));
          house.householdPileBalance += accepted;
          house.recentEnergyProducedPiles += accepted;
          _recordResidentEconomicTransaction(ResidentEconomicTransaction(
            id: 'energy-${house.id}-${previous.microsecondsSinceEpoch}',
            type: ResidentEconomicTransactionType.householdEnergyProduction,
            householdId: house.id,
            grossAmountPiles: accepted,
            status: ResidentEconomicTransactionStatus.completed,
            createdAt: previous,
            completedAt: current,
            idempotencyKey:
                'energy:${house.id}:${previous.microsecondsSinceEpoch}:${current.microsecondsSinceEpoch}',
          ));
          changed = accepted > 0 || changed;
        }
      }
      house.lastHouseholdEnergyResolvedAt = current;
      final distributionPrevious = house.lastEnergyDistributionAt ?? previous;
      final interval = Duration(
          minutes:
              math.max(1, residentEconomyConfig.householdDistributionMinutes));
      if (!current.isBefore(distributionPrevious.add(interval)) &&
          occupants.isNotEmpty) {
        final share = house.householdPileBalance ~/ occupants.length;
        if (share > 0) {
          final paid = share * occupants.length;
          house.householdPileBalance -= paid;
          for (final resident in occupants) {
            resident.internalPileBalance = math.min(
              residentEconomyConfig.personalAccountCapPiles,
              resident.internalPileBalance + share,
            );
            resident.recentDomesticIncomePiles += share;
            resident.updatedAt = current;
          }
          _recordResidentEconomicTransaction(ResidentEconomicTransaction(
            id: 'distribution-${house.id}-${distributionPrevious.microsecondsSinceEpoch}',
            type: ResidentEconomicTransactionType.householdEnergyDistribution,
            householdId: house.id,
            quantity: occupants.length,
            grossAmountPiles: paid,
            otherSharePiles: house.householdPileBalance,
            participantResidentIds: occupants.map((item) => item.id).toList(),
            status: ResidentEconomicTransactionStatus.completed,
            createdAt: distributionPrevious,
            completedAt: current,
            idempotencyKey:
                'distribution:${house.id}:${distributionPrevious.microsecondsSinceEpoch}',
          ));
          changed = true;
        }
        house.lastEnergyDistributionAt = current;
      }
      house.updatedAt = current;
    }
    lastDomesticEnergyDistributionAt = current;
    return changed;
  }

  String _residentNameFor(int index) {
    const names = <String>[
      'Malo',
      'Sacha',
      'Noa',
      'Ari',
      'Lio',
      'Nima',
      'Cam',
      'Eden',
      'Sol',
      'Yaël',
      'Mika',
      'Iris',
      'Lou',
      'Ayo',
      'Nox',
      'Rin',
    ];
    final cycle = index ~/ names.length;
    return cycle == 0
        ? names[index % names.length]
        : '${names[index % names.length]} ${cycle + 1}';
  }

  List<ResidentArrivalCandidate> get activeResidentArrivalCandidates =>
      residentArrivalCandidates
          .where((candidate) => <ResidentArrivalStatus>{
                ResidentArrivalStatus.available,
                ResidentArrivalStatus.postponed,
                ResidentArrivalStatus.acceptedPendingConditions,
                ResidentArrivalStatus.acceptedReady,
                ResidentArrivalStatus.arrivalScheduled,
              }.contains(candidate.status))
          .toList(growable: false);

  int get availableResidentHousingPlaces => residentHouses.fold<int>(
      0,
      (total, house) =>
          total +
          math.max(
              0,
              house.capacity -
                  house.residentIds.length -
                  house.reservedArrivalCandidateIds.length));

  bool _arrivalConditionsMet(ResidentArrivalCandidate candidate) {
    if (availableResidentHousingPlaces < candidate.requiredHousingCapacity &&
        candidate.reservedHouseId == null) return false;
    for (final condition in candidate.requiredBuildingConditions) {
      final met = switch (condition) {
        'cuisine' => cuisineLevel > 0,
        'fablab' => fablabLevel > 0,
        'market' => marketLevel > 0,
        'tower' => securityTowerLevel > 0,
        'nursery' => plaineNurseryLevel > 0,
        'lisiere' => true,
        _ => true,
      };
      if (!met) return false;
    }
    for (final item in candidate.requiredItemConditions) {
      if (resourceAmount(item) <= 0) return false;
    }
    return candidate.requiredProjectConditions.every((projectId) =>
        communityProjects[projectId]?.status ==
        CommunityProjectStatus.completed);
  }

  ResidentArrivalCandidate _generateResidentArrivalCandidate(DateTime now) {
    final index = residents.length + residentArrivalCandidates.length;
    final passions = ResidentPassion.values;
    final missing = passions.where((passion) => !residents
        .any((resident) => resident.primaryPassionId == passion.name));
    final passion = missing.isNotEmpty
        ? missing.elementAt(index % missing.length)
        : passions[index % passions.length];
    final desire =
        ResidentDesireType.values[index % ResidentDesireType.values.length];
    final profile = ResidentInteriorProfile
        .values[index % ResidentInteriorProfile.values.length];
    final building = switch (passion) {
      ResidentPassion.cooking => 'cuisine',
      ResidentPassion.crafting => 'fablab',
      ResidentPassion.trading => 'market',
      ResidentPassion.livingObservation => 'nursery',
      ResidentPassion.watching => 'tower',
    };
    final name = _residentNameFor(index);
    final id = 'arrival-${now.microsecondsSinceEpoch}-$index';
    final contribution = switch (passion) {
      ResidentPassion.cooking => 'Préparer lentement des repas à la Cuisine.',
      ResidentPassion.crafting =>
        'Fabriquer des fournitures simples au Fablab.',
      ResidentPassion.trading => 'Tenir un rôle de distribution au Marché.',
      ResidentPassion.livingObservation =>
        'Observer la Lisière et soutenir le vivant.',
      ResidentPassion.watching =>
        'Participer à la veille météo et à la Sécurité.',
    };
    final candidate = ResidentArrivalCandidate(
      id: id,
      displayName: name,
      originText: 'un refuge voisin',
      departureReasonText:
          'Son ancien point d’appui ne permet plus de poursuivre son activité.',
      arrivalReasonText:
          'Le développement du Cœur rend votre refuge visible et accueillant.',
      shortStoryText:
          '$name cherche une place où mettre sa passion au service du refuge.',
      promisedContributionText: contribution,
      promisedContributionType: passion.name,
      primaryPassionId: passion.name,
      primaryDesireId: desire.name,
      interiorProfileId: profile.name,
      accompanyingResidentCount: 0,
      requiredHousingCapacity: 1,
      requiredBuildingConditions: <String>[building],
      requestedConditions: <String>[
        'Une place de logement',
        'Accès à $building'
      ],
      createdAt: now,
      expiresAt: now.add(Duration(days: housingConfig.arrivalExpiryDays)),
      idempotencyKey: 'arrival-candidate:$id',
    );
    residentArrivalCandidates.add(candidate);
    reports.add(PtipoteMissionReport.system(
      message: '$name souhaite rejoindre le refuge.',
      subject: 'Nouvelle candidature',
      concerned: 'Arrivées',
    ));
    return candidate;
  }

  Zone0ActionResult acceptResidentArrivalCandidate(String candidateId) {
    final candidate = residentArrivalCandidates
        .where((item) => item.id == candidateId)
        .firstOrNull;
    if (candidate == null ||
        !<ResidentArrivalStatus>{
          ResidentArrivalStatus.available,
          ResidentArrivalStatus.postponed
        }.contains(candidate.status)) {
      return const Zone0ActionResult(
          success: false, message: 'Candidature indisponible.');
    }
    final house = residentHouses
        .where((item) =>
            item.capacity -
                item.residentIds.length -
                item.reservedArrivalCandidateIds.length >=
            candidate.requiredHousingCapacity)
        .firstOrNull;
    if (house != null) {
      house.reservedArrivalCandidateIds.add(candidate.id);
      candidate.reservedHouseId = house.id;
    }
    candidate
      ..acceptedAt = DateTime.now()
      ..updatedAt = DateTime.now()
      ..status = _arrivalConditionsMet(candidate) && house != null
          ? ResidentArrivalStatus.arrivalScheduled
          : ResidentArrivalStatus.acceptedPendingConditions;
    if (candidate.status == ResidentArrivalStatus.arrivalScheduled) {
      candidate.arrivalScheduledAt =
          DateTime.now().add(Duration(hours: housingConfig.arrivalTravelHours));
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: candidate.status == ResidentArrivalStatus.arrivalScheduled
            ? 'Candidature acceptée : arrivée programmée.'
            : 'Candidature acceptée : conditions à préparer.');
  }

  Zone0ActionResult postponeResidentArrivalCandidate(String candidateId) {
    final candidate = residentArrivalCandidates
        .where((item) => item.id == candidateId)
        .firstOrNull;
    if (candidate == null ||
        candidate.status != ResidentArrivalStatus.available) {
      return const Zone0ActionResult(
          success: false, message: 'Report indisponible.');
    }
    candidate
      ..status = ResidentArrivalStatus.postponed
      ..postponedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Candidature reportée.');
  }

  Zone0ActionResult rejectResidentArrivalCandidate(String candidateId) {
    final candidate = residentArrivalCandidates
        .where((item) => item.id == candidateId)
        .firstOrNull;
    if (candidate == null ||
        candidate.status == ResidentArrivalStatus.arrived) {
      return const Zone0ActionResult(
          success: false, message: 'Refus indisponible.');
    }
    _releaseArrivalReservation(candidate);
    candidate
      ..status = ResidentArrivalStatus.rejected
      ..updatedAt = DateTime.now();
    reports.add(PtipoteMissionReport.system(
        message: '${candidate.displayName} poursuit sa route.',
        subject: 'Candidature refusée'));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Candidature refusée.');
  }

  void _releaseArrivalReservation(ResidentArrivalCandidate candidate) {
    for (final house in residentHouses) {
      house.reservedArrivalCandidateIds.remove(candidate.id);
    }
    candidate.reservedHouseId = null;
  }

  bool resolveResidentArrivals({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    for (final candidate in activeResidentArrivalCandidates) {
      if (candidate.expiresAt != null &&
          current.isAfter(candidate.expiresAt!) &&
          <ResidentArrivalStatus>{
            ResidentArrivalStatus.available,
            ResidentArrivalStatus.postponed
          }.contains(candidate.status)) {
        _releaseArrivalReservation(candidate);
        candidate.status = ResidentArrivalStatus.expired;
        changed = true;
        continue;
      }
      if (candidate.status == ResidentArrivalStatus.acceptedPendingConditions &&
          _arrivalConditionsMet(candidate)) {
        final house = residentHouseForId(candidate.reservedHouseId) ??
            residentHouses
                .where((item) =>
                    item.capacity -
                        item.residentIds.length -
                        item.reservedArrivalCandidateIds.length >=
                    candidate.requiredHousingCapacity)
                .firstOrNull;
        if (house != null) {
          if (!house.reservedArrivalCandidateIds.contains(candidate.id))
            house.reservedArrivalCandidateIds.add(candidate.id);
          candidate
            ..reservedHouseId = house.id
            ..status = ResidentArrivalStatus.arrivalScheduled
            ..arrivalScheduledAt =
                current.add(Duration(hours: housingConfig.arrivalTravelHours));
          changed = true;
        }
      }
      if (candidate.status == ResidentArrivalStatus.arrivalScheduled &&
          candidate.arrivalScheduledAt != null &&
          !current.isBefore(candidate.arrivalScheduledAt!)) {
        changed = _finalizeResidentArrival(candidate, current) || changed;
      }
    }
    final due = lastResidentArrivalResolutionAt == null ||
        current.difference(lastResidentArrivalResolutionAt!).inHours >=
            housingConfig.arrivalCandidateIntervalHours;
    if (due &&
        activeResidentArrivalCandidates.length <
            housingConfig.arrivalActiveCandidateLimit &&
        availableResidentHousingPlaces > 0 &&
        _lastKnownCampHeartLevel > 0) {
      _generateResidentArrivalCandidate(current);
      changed = true;
    }
    lastResidentArrivalResolutionAt = current;
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  bool _finalizeResidentArrival(
      ResidentArrivalCandidate candidate, DateTime now) {
    if (candidate.status == ResidentArrivalStatus.arrived ||
        !_arrivalConditionsMet(candidate)) return false;
    final house = residentHouseForId(candidate.reservedHouseId);
    final total = 1 + candidate.accompanyingCandidates.length;
    if (house == null || house.capacity - house.residentIds.length < total)
      return false;
    final arrivals = <ResidentArrivalCompanion>[
      ResidentArrivalCompanion(
          id: candidate.id,
          displayName: candidate.displayName,
          primaryPassionId: candidate.primaryPassionId,
          primaryDesireId: candidate.primaryDesireId,
          interiorProfileId: candidate.interiorProfileId),
      ...candidate.accompanyingCandidates,
    ];
    if (arrivals.length != candidate.requiredHousingCapacity) return false;
    for (final entry in arrivals) {
      final residentId = 'resident-arrival-${entry.id}';
      if (residents.any((resident) => resident.id == residentId)) continue;
      final resident = Zone0Resident(
        id: residentId,
        displayName: entry.displayName,
        houseId: house.id,
        baseHappiness: housingConfig.arrivalInitialHappiness,
        internalPileBalance: housingConfig.arrivalInitialPileBalance,
        createdAt: now,
        arrivedAt: now,
        sourceMigrationId: candidate.id,
        primaryPassionId: entry.primaryPassionId,
        primaryDesireId: entry.primaryDesireId,
        interiorProfileId: entry.interiorProfileId,
        contributionEligible: true,
      );
      residents.add(resident);
      house.residentIds.add(resident.id);
      _assignResidentVision(resident, now,
          preferredProjectId: candidate.initialVisionProjectId);
    }
    _releaseArrivalReservation(candidate);
    candidate
      ..status = ResidentArrivalStatus.arrived
      ..arrivedAt = now
      ..updatedAt = now;
    currentPopulation = residents.where((resident) => resident.isActive).length;
    reports.add(PtipoteMissionReport.system(
        message: '${candidate.displayName} s’installe à ${house.displayName}.',
        subject: 'Arrivée au refuge',
        concerned: 'Population'));
    return true;
  }

  ResidentVision? residentVisionFor(String residentId) => residentVisions
      .where((vision) =>
          vision.residentId == residentId &&
          <ResidentVisionStatus>{
            ResidentVisionStatus.active,
            ResidentVisionStatus.disappointed
          }.contains(vision.status))
      .firstOrNull;

  Map<String, int> get residentVisionSupportCounts {
    final result = <String, int>{};
    for (final vision in residentVisions.where((vision) =>
        <ResidentVisionStatus>{
          ResidentVisionStatus.active,
          ResidentVisionStatus.disappointed
        }.contains(vision.status))) {
      result.update(vision.projectId, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  List<CommunityProjectDefinition> _availableVisionProjects(
          {int minimumTier = 0}) =>
      campHeartConfig.communityProjects.projects
          .where((definition) =>
              definition.tier >= minimumTier &&
              definition.requiredCoreLevel <= _lastKnownCampHeartLevel &&
              communityProjects[definition.id]?.status !=
                  CommunityProjectStatus.completed &&
              (definition.prerequisiteId == null ||
                  communityProjects[definition.prerequisiteId]?.status ==
                      CommunityProjectStatus.completed))
          .toList();

  ResidentVision? _assignResidentVision(Zone0Resident resident, DateTime now,
      {String? preferredProjectId, int minimumTier = 0}) {
    if (residentVisionFor(resident.id) != null)
      return residentVisionFor(resident.id);
    final choices = _availableVisionProjects(minimumTier: minimumTier);
    if (choices.isEmpty) return null;
    final preferred = choices
        .where((project) => project.id == preferredProjectId)
        .firstOrNull;
    final passion = resident.primaryPassionId;
    final oriented = choices
        .where((project) =>
            (passion == ResidentPassion.watching.name &&
                project.weatherType.isNotEmpty) ||
            (passion == ResidentPassion.livingObservation.name &&
                project.weatherType == 'toxicCloud') ||
            (passion == ResidentPassion.trading.name &&
                project.weatherType == 'heavyRain'))
        .toList();
    final pool = preferred == null
        ? (oriented.isNotEmpty ? oriented : choices)
        : <CommunityProjectDefinition>[preferred];
    final project = pool[resident.id.hashCode.abs() % pool.length];
    final vision = ResidentVision(
      id: 'vision-${resident.id}-${project.id}',
      residentId: resident.id,
      projectId: project.id,
      projectTier: project.tier,
      branchId: project.weatherType,
      selectedAt: now,
    );
    residentVisions.add(vision);
    resident.currentVisionProjectId = project.id;
    return vision;
  }

  bool _resolveResidentVisions({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    for (final resident in residents.where((item) => item.isActive)) {
      if (residentVisionFor(resident.id) == null) {
        changed = _assignResidentVision(resident, current,
                    preferredProjectId: resident.currentVisionProjectId) !=
                null ||
            changed;
      }
    }
    for (final vision in residentVisions
        .where((item) => item.status == ResidentVisionStatus.disappointed)) {
      if (vision.disappointmentEndsAt != null &&
          !current.isBefore(vision.disappointmentEndsAt!)) {
        final resident =
            residents.where((item) => item.id == vision.residentId).firstOrNull;
        resident?.happinessModifiers
            .remove('vision-disappointment-${vision.id}');
        vision
          ..status = ResidentVisionStatus.active
          ..disappointedAt = null
          ..disappointmentEndsAt = null;
        changed = true;
      }
    }
    return changed;
  }

  void _resolveVisionsForProjectSelection(
      String selectedProjectId, DateTime now) {
    for (final vision in residentVisions.where((vision) =>
        vision.status == ResidentVisionStatus.active &&
        vision.projectId != selectedProjectId)) {
      final resident =
          residents.where((item) => item.id == vision.residentId).firstOrNull;
      if (resident == null || vision.disappointmentEndsAt != null) continue;
      vision
        ..status = ResidentVisionStatus.disappointed
        ..disappointedAt = now
        ..disappointmentEndsAt =
            now.add(Duration(hours: housingConfig.visionDisappointmentHours));
      resident.happinessModifiers['vision-disappointment-${vision.id}'] =
          -housingConfig.visionDisappointmentPenalty;
    }
  }

  void _resolveVisionsForCompletedProject(
      CommunityProjectProgress project, DateTime now) {
    for (final vision in residentVisions.where((vision) =>
        vision.projectId == project.definition.id &&
        <ResidentVisionStatus>{
          ResidentVisionStatus.active,
          ResidentVisionStatus.disappointed
        }.contains(vision.status))) {
      final resident =
          residents.where((item) => item.id == vision.residentId).firstOrNull;
      if (resident == null) continue;
      resident.happinessModifiers.remove('vision-disappointment-${vision.id}');
      final prior = residentVisions
          .where((item) =>
              item.residentId == resident.id &&
              item.status == ResidentVisionStatus.fulfilled)
          .fold<int>(0, (total, item) => total + item.persistentBonus);
      vision
        ..status = ResidentVisionStatus.fulfilled
        ..fulfilledAt = now
        ..persistentBonus = math.min(housingConfig.visionFulfilledBonus,
            math.max(0, housingConfig.visionBonusCap - prior));
      final total = prior + vision.persistentBonus;
      resident.happinessModifiers['vision-fulfilled'] = total;
      resident.currentVisionProjectId = null;
      final sameBranch = _availableVisionProjects(
              minimumTier: project.definition.tier + 1)
          .where((item) => item.weatherType == project.definition.weatherType)
          .toList();
      final useSame = sameBranch.isNotEmpty &&
          resident.id.hashCode.abs() % 100 <
              housingConfig.visionSameBranchPercent;
      _assignResidentVision(resident, now,
          preferredProjectId: useSame ? sameBranch.first.id : null,
          minimumTier: project.definition.tier + 1);
    }
  }

  HouseholdRepairJob? householdRepairFor(String houseId) => householdRepairJobs
      .where((job) =>
          job.houseId == houseId &&
          <HouseholdRepairStatus>{
            HouseholdRepairStatus.active,
            HouseholdRepairStatus.paused
          }.contains(job.status))
      .firstOrNull;

  bool _payHouseholdCost(ResidentHouse house, int cost, DateTime now,
      {required bool essential}) {
    final reserve =
        essential ? 0 : housingConfig.householdEmergencyReservePiles;
    if (house.householdPileBalance - cost >= reserve) {
      house.householdPileBalance -= cost;
      house.recentHouseholdSpendingPiles += cost;
      return true;
    }
    final fromHouse = math.max(0, house.householdPileBalance - reserve);
    final remaining = cost - fromHouse;
    final occupants = residents
        .where((resident) => resident.isActive && resident.houseId == house.id)
        .toList();
    if (occupants.isEmpty) return false;
    final share = (remaining / occupants.length).ceil();
    final maxPercent = housingConfig.householdContributionMaxPercent / 100;
    if (occupants.any((resident) =>
        resident.internalPileBalance < share ||
        share > resident.internalPileBalance * maxPercent)) return false;
    house.householdPileBalance -= fromHouse;
    for (final resident in occupants) {
      resident
        ..internalPileBalance -= share
        ..recentSpendingPiles += share
        ..updatedAt = now;
    }
    house.recentHouseholdSpendingPiles += cost;
    return true;
  }

  bool _buyHouseholdFinishedItem(ResidentHouse house, String item, DateTime now,
      {required bool essential}) {
    final shopId = _marketShopWithStock(item, 1);
    if (shopId == null) {
      house.lastAutonomyDecision = '$item indisponible dans les magasins.';
      return false;
    }
    final cost = residentEconomyConfig.priceFor(item);
    if (!_payHouseholdCost(house, cost, now, essential: essential)) {
      house.lastAutonomyDecision = 'Le foyer économise pour $item.';
      return false;
    }
    if (!_consumeMarketShopStock(shopId, item, 1)) {
      house.householdPileBalance += cost;
      house.recentHouseholdSpendingPiles =
          math.max(0, house.recentHouseholdSpendingPiles - cost);
      return false;
    }
    final shop = marketShops.where((entry) => entry.id == shopId).firstOrNull;
    final owner = residents
        .where((resident) => resident.id == shop?.ownerResidentId)
        .firstOrNull;
    if (owner != null) {
      owner.internalPileBalance += cost;
    } else {
      _creditMarketBioPiles(cost);
    }
    _recordResidentEconomicTransaction(ResidentEconomicTransaction(
      id: 'household-$item-${house.id}-${now.microsecondsSinceEpoch}',
      type: ResidentEconomicTransactionType.householdInstallationPurchase,
      householdId: house.id,
      buildingId: 'market',
      itemDefinitionId: item,
      quantity: 1,
      grossAmountPiles: cost,
      playerSharePiles: owner == null ? cost : 0,
      merchantSharePiles: owner == null ? 0 : cost,
      status: ResidentEconomicTransactionStatus.completed,
      createdAt: now,
      completedAt: now,
      idempotencyKey:
          'household-buy:${house.id}:$item:${now.microsecondsSinceEpoch}',
    ));
    _addHouseholdInventoryItem(house, item, 1);
    return true;
  }

  bool _startAutonomousHouseholdRepair(ResidentHouse house, DateTime now) {
    if (householdRepairFor(house.id) != null ||
        house.currentViability >= house.maximumViability) return false;
    const kit = 'Kit de réparation domestique';
    if (!_buyHouseholdFinishedItem(house, kit, now, essential: true))
      return false;
    if (!_consumeHouseholdInventoryItem(house, kit)) return false;
    final job = HouseholdRepairJob(
      id: 'repair-${house.id}-${now.microsecondsSinceEpoch}',
      houseId: house.id,
      startedAt: now,
      endsAt: now.add(Duration(hours: housingConfig.autonomousRepairHours)),
      viabilityGain: housingConfig.autonomousRepairGain,
      isPlayerRepair: false,
      reservedKitItemId: kit,
    );
    householdRepairJobs.add(job);
    house
      ..activeRepairJobId = job.id
      ..isUnderRepair = true
      ..lastAutonomyDecision = 'Réparation habitante en cours.';
    return true;
  }

  bool _resolveHouseholdRepairs(DateTime now) {
    var changed = false;
    for (final job in householdRepairJobs
        .where((job) => job.status == HouseholdRepairStatus.active)
        .toList()) {
      if (now.isBefore(job.endsAt)) continue;
      final house = residentHouseForId(job.houseId);
      if (house != null) {
        house
          ..currentViability = math.min(house.maximumViability,
              house.currentViability + job.viabilityGain)
          ..activeRepairJobId = null
          ..isUnderRepair = false
          ..lastAutonomyDecision =
              'Réparation terminée : +${job.viabilityGain}% de Viabilité.'
          ..updatedAt = now;
        for (final resident
            in residents.where((resident) => resident.houseId == house.id)) {
          resident.currentHappiness = residentHappinessFor(resident);
        }
      }
      job.status = HouseholdRepairStatus.completed;
      if (job.isPlayerRepair &&
          house != null &&
          house.currentViability < house.maximumViability) {
        final paused = householdRepairJobs
            .where((other) =>
                other.houseId == house.id &&
                other.status == HouseholdRepairStatus.paused)
            .firstOrNull;
        if (paused != null) {
          paused.status = HouseholdRepairStatus.active;
          house
            ..activeRepairJobId = paused.id
            ..isUnderRepair = true;
        }
      }
      changed = true;
    }
    return changed;
  }

  bool resolveHouseholdAutonomy({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = _resolveHouseholdRepairs(current);
    if (residentAutonomyGraceUntil != null &&
        current.isBefore(residentAutonomyGraceUntil!)) return changed;
    for (final house
        in residentHouses.where((house) => house.residentIds.isNotEmpty)) {
      if (house.autonomyLockedUntil != null &&
          current.isBefore(house.autonomyLockedUntil!)) continue;
      final action = HouseholdAutonomyService.nextAction(this, house);
      var completed = false;
      if (action == HouseholdAutonomyAction.repair) {
        completed = _startAutonomousHouseholdRepair(house, current);
      } else if (action == HouseholdAutonomyAction.furniture &&
          house.installedFurnitureItems.length < house.furnitureSlots) {
        completed = _buyHouseholdFinishedItem(house, 'Meuble simple', current,
            essential: true);
        if (completed &&
            _consumeHouseholdInventoryItem(house, 'Meuble simple')) {
          house.installedFurnitureItems.add('Meuble simple');
        }
      } else if (action == HouseholdAutonomyAction.generator &&
          !house.additionalGeneratorInstalled) {
        completed = _buyHouseholdFinishedItem(
            house, 'Second générateur domestique', current,
            essential: false);
        if (completed &&
            _consumeHouseholdInventoryItem(
                house, 'Second générateur domestique')) {
          house.additionalGeneratorInstalled = true;
        }
      } else if (action == HouseholdAutonomyAction.protection) {
        final type = HouseholdAutonomyService.requiredProtection(
            nextGlobalWeatherEvent?.type);
        final item = HouseholdAutonomyService.protectionItem(type);
        if (type != null &&
            item != null &&
            !house.installedStructuralProtections.contains(type) &&
            house.installedStructuralProtections.length <
                house.weatherProtectionSlots) {
          completed =
              _buyHouseholdFinishedItem(house, item, current, essential: true);
          if (completed && _consumeHouseholdInventoryItem(house, item)) {
            house.installedStructuralProtections.add(type);
          }
        }
      }
      if (completed) {
        house
          ..autonomyLockedUntil = current.add(const Duration(hours: 1))
          ..updatedAt = current;
        for (final resident
            in residents.where((resident) => resident.houseId == house.id)) {
          _resolveResidentInteriorAndDesire(resident, current);
        }
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  Zone0ActionResult moveResidentToHouse({
    required String residentId,
    String? targetHouseId,
  }) {
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    if (resident == null) {
      return const Zone0ActionResult(
          success: false, message: 'Habitant introuvable.');
    }
    final target = residentHouseForId(targetHouseId);
    if (targetHouseId != null && target == null) {
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    }
    if (target != null &&
        !target.residentIds.contains(resident.id) &&
        target.residentIds.length >= target.capacity) {
      return const Zone0ActionResult(
          success: false, message: 'Cette maison est complète.');
    }
    // Settle the old household before changing the membership so one hour of
    // household energy can never be received from both homes.
    resolveResidentDomesticGeneration();
    for (final house in residentHouses) {
      house.residentIds.remove(resident.id);
    }
    if (target != null) target.residentIds.add(resident.id);
    resident.houseId = target?.id;
    resident.status =
        target == null ? ResidentStatus.awaitingHousing : ResidentStatus.active;
    resident.currentHappiness = residentHappinessFor(resident);
    resident.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: target == null
          ? '${resident.displayName} attend un logement.'
          : '${resident.displayName} rejoint ${target.displayName}.',
    );
  }

  Zone0ActionResult repairResidentHouse(String houseId, {int gain = 10}) {
    final house = residentHouseForId(houseId);
    if (house == null)
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    if (house.currentViability >= house.maximumViability) {
      return const Zone0ActionResult(
          success: false, message: 'La maison est déjà en bon état.');
    }
    final activeRepair = householdRepairFor(houseId);
    if (activeRepair != null && !activeRepair.isPlayerRepair) {
      activeRepair.status = HouseholdRepairStatus.paused;
      house.isUnderRepair = false;
    }
    final requestedGain = (gain / 10).ceil().clamp(1, 10) * 10;
    final actualGain = math
        .min(requestedGain, house.maximumViability - house.currentViability)
        .toInt();
    // Les maisons habitantes ne disposent pas encore de niveaux. Elles
    // utilisent donc le palier 1, tout en passant par la même table centrale.
    final costs = buildingRepairCostsForLevel(1, actualGain);
    final materials = Map<String, int>.fromEntries(costs.entries.where(
      (entry) => entry.key != 'Bio-batteries' && entry.key != 'Bio-piles',
    ));
    final currencyPiles = _repairCurrencyCostInPiles(costs);
    if (!canSpendBioBatteryPiles(currencyPiles) ||
        !hasResources(materials) ||
        !removeResources(materials)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ressources insuffisantes pour réparer cette maison.');
    }
    _spendBioBatteryPiles(currencyPiles);
    house.currentViability = math
        .min(house.maximumViability, house.currentViability + requestedGain)
        .toInt();
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Maison réparée : +$actualGain% de Viabilité · ${_repairCostSummary(costs)}.');
  }

  Zone0ActionResult repairResidentHouseByMiniGame(String houseId) {
    final house = residentHouseForId(houseId);
    if (house == null || house.currentViability >= house.maximumViability) {
      return const Zone0ActionResult(
          success: false, message: 'Réparation indisponible.');
    }
    final gain = math.min(10, house.maximumViability - house.currentViability);
    house.currentViability += gain.toInt();
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: 'Circuit de la maison réparé : +$gain%.');
  }

  Zone0ActionResult repairResidentHouseWithKit(String houseId) {
    final house = residentHouseForId(houseId);
    if (house == null || house.currentViability >= house.maximumViability) {
      return const Zone0ActionResult(
          success: false, message: 'Réparation indisponible.');
    }
    const kit = 'Kit de réparation domestique';
    if (resourceAmount(kit) < 1 || removeResource(kit, 1) <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Un Kit de réparation est requis.');
    }
    final activeRepair = householdRepairFor(houseId);
    if (activeRepair != null && !activeRepair.isPlayerRepair) {
      activeRepair.status = HouseholdRepairStatus.paused;
      house.isUnderRepair = false;
    }
    final gain =
        math.min(15, house.maximumViability - house.currentViability).toInt();
    house
      ..currentViability += gain
      ..updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Kit de réparation utilisé : maison réparée de +$gain%.',
    );
  }

  /// Fast player intervention uses the established material cost path while
  /// pausing (never discarding) a slower household repair.
  Zone0ActionResult startPlayerHouseRepair(String houseId, {int gain = 10}) {
    final house = residentHouseForId(houseId);
    if (house == null || house.currentViability >= house.maximumViability) {
      return const Zone0ActionResult(
          success: false, message: 'Réparation indisponible.');
    }
    final active = householdRepairFor(houseId);
    if (active != null && !active.isPlayerRepair)
      active.status = HouseholdRepairStatus.paused;
    final costs = <String, int>{
      'Organique': housingConfig.houseRepairOrganicCost,
      'Minéral': housingConfig.houseRepairMineralCost,
    };
    if (!hasResources(costs) || !removeResources(costs)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources insuffisantes.');
    }
    final now = DateTime.now();
    final job = HouseholdRepairJob(
      id: 'player-repair-$houseId-${now.microsecondsSinceEpoch}',
      houseId: houseId,
      startedAt: now,
      endsAt: now.add(Duration(minutes: gain <= 10 ? 5 : 15)),
      viabilityGain: gain.clamp(1, 100),
      isPlayerRepair: true,
    );
    householdRepairJobs.add(job);
    house
      ..activeRepairJobId = job.id
      ..isUnderRepair = true
      ..lastAutonomyDecision = 'Intervention du joueur en cours.';
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: 'Réparation du joueur programmée (+${job.viabilityGain}%).');
  }

  Zone0ActionResult installResidentSecondGenerator(String houseId) {
    final house = residentHouseForId(houseId);
    if (house == null) {
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    }
    if (house.additionalGeneratorInstalled ||
        house.additionalGeneratorSlots <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun emplacement énergétique disponible.');
    }
    final cost = residentEconomyConfig.secondGeneratorInstallationCostPiles;
    if (house.householdPileBalance < cost) {
      return Zone0ActionResult(
        success: false,
        message: 'Le foyer doit réunir $cost bio-pile(s).',
      );
    }
    final now = DateTime.now();
    house
      ..householdPileBalance -= cost
      ..recentHouseholdSpendingPiles += cost
      ..additionalGeneratorInstalled = true
      ..updatedAt = now;
    _recordResidentEconomicTransaction(ResidentEconomicTransaction(
      id: 'house-generator-$houseId-${now.microsecondsSinceEpoch}',
      type: ResidentEconomicTransactionType.householdInstallationPurchase,
      householdId: house.id,
      itemDefinitionId: 'Second générateur domestique',
      grossAmountPiles: cost,
      playerSharePiles: cost,
      status: ResidentEconomicTransactionStatus.completed,
      createdAt: now,
      completedAt: now,
      idempotencyKey: 'house-generator:${house.id}',
    ));
    _creditMarketBioPiles(cost);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Second générateur domestique installé.',
    );
  }

  Zone0ActionResult installHouseProtection(
    String houseId,
    StructuralProtectionType type,
  ) {
    final house = residentHouseForId(houseId);
    if (house == null)
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    if (house.installedStructuralProtections.length >=
        house.weatherProtectionSlots) {
      return const Zone0ActionResult(
          success: false,
          message: 'Aucun emplacement de protection disponible.');
    }
    final item = switch (type) {
      StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
      StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
      StructuralProtectionType.filtration => 'Installation filtrante',
    };
    // Les achats habitants arrivent d'abord dans l'inventaire de la Maison.
    // Le prélèvement direct du joueur reste accepté ici pour ne pas bloquer
    // une installation manuelle existante.
    if (!_consumeHouseholdInventoryItem(house, item) &&
        (resourceAmount(item) < 1 || removeResource(item, 1) <= 0)) {
      return Zone0ActionResult(
          success: false,
          message: '$item requis dans l’inventaire de la maison.');
    }
    house.installedStructuralProtections.add(type);
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$item installé dans ${house.displayName}.');
  }

  void _applyWeatherHouseDamage(GlobalWeatherEvent event) {
    if (event.type == TowerWeatherType.calm) return;
    final config = towerOperationsConfig.buildingViability;
    var totalDamage = 0;
    var damagedHouses = 0;
    for (final house in residentHouses) {
      if (house.lastDamageEventId == event.id) continue;
      house.lastDamageEventId = event.id;
      final impact = event.affectedBiomes
          .where((item) => item.biome == house.biome)
          .firstOrNull;
      if (impact == null || !impact.isAffected) continue;
      final filtrationReady = _consumeStructuralFilterCartridges(
        house.structuralConsumables,
        house.installedStructuralProtections,
        event,
      );
      final protection = ((filtrationReady
                  ? house.protectionReductionPercent(event.type, config)
                  : 0) +
              globalWeatherProtectionPercent(event.type))
          .clamp(0, config.protectionCapPercent);
      final raw = config.damageFor(event.type, event.intensity) *
          impact.localImpactMultiplier;
      final previous = house.currentViability;
      house.currentViability = math
          .max(
            0,
            house.currentViability - (raw * (1 - protection / 100)).ceil(),
          )
          .toInt();
      final actualDamage = previous - house.currentViability;
      if (actualDamage > 0) {
        totalDamage += actualDamage;
        damagedHouses++;
      }
      house.updatedAt = DateTime.now();
    }
    if (damagedHouses > 0) {
      final average = totalDamage / damagedHouses;
      reports.add(PtipoteMissionReport.system(
        message:
            'Habitations : ${average.toStringAsFixed(1)}% de Viabilité perdue en moyenne ($totalDamage% au total).',
        sourceBuildingId: 'campHeart',
        subject: 'Bilan météo',
        concerned: 'Habitations',
        summary: '$damagedHouses maison(s) touchée(s).',
      ));
    }
  }

  CommunityProjectDefinition? communityProjectDefinition(String id) =>
      campHeartConfig.communityProjects.projects
          .where((project) => project.id == id)
          .firstOrNull;

  bool canSelectCommunityProject(CommunityProjectDefinition definition) {
    if (communityProjects.containsKey(definition.id) ||
        communityProjectChoicesUsed >= communityProjectChoiceLimit ||
        _lastKnownCampHeartLevel < definition.requiredCoreLevel) return false;
    if (definition.prerequisiteId != null &&
        communityProjects[definition.prerequisiteId]?.status !=
            CommunityProjectStatus.completed) return false;
    return activeCommunityProject == null ||
        campHeartConfig.communityProjects.maximumActiveProjects > 1;
  }

  Zone0ActionResult selectCommunityProject(String definitionId) {
    final definition = communityProjectDefinition(definitionId);
    if (definition == null || !canSelectCommunityProject(definition)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ce grand chantier n’est pas encore accessible.');
    }
    communityProjects[definition.id] =
        CommunityProjectProgress(definition: definition);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '${definition.label} choisi.');
  }

  Zone0ActionResult activateCommunityProject(String definitionId) {
    final project = communityProjects[definitionId];
    if (project == null ||
        project.status == CommunityProjectStatus.completed ||
        (activeCommunityProject != null && activeCommunityProject != project)) {
      return const Zone0ActionResult(
          success: false, message: 'Un seul grand chantier peut être actif.');
    }
    project.status = CommunityProjectStatus.active;
    project.startedAt ??= DateTime.now();
    _resolveVisionsForProjectSelection(definitionId, DateTime.now());
    _resolveCommunityDailyContribution(DateTime.now());
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '${project.definition.label} est actif.');
  }

  Zone0ActionResult depositCommunityProjectMaterial(
      String projectId, String resource, int amount) {
    final project = communityProjects[projectId];
    final required = project?.definition.materialCosts[resource] ?? 0;
    if (project == null || amount <= 0 || required <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Dépôt indisponible.');
    final missing = math
        .max(
          0,
          required - (project.depositedMaterials[resource] ?? 0),
        )
        .toInt();
    final moved =
        math.min(amount, math.min(missing, resourceAmount(resource))).toInt();
    if (moved <= 0 || removeResource(resource, moved) <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Ressource insuffisante.');
    project.depositedMaterials[resource] =
        (project.depositedMaterials[resource] ?? 0) + moved;
    project.updatedAt = DateTime.now();
    _completeCommunityProjectIfReady(project);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved $resource déposés.');
  }

  Zone0ActionResult contributeToCommunityProject() {
    final project = activeCommunityProject;
    if (project == null)
      return const Zone0ActionResult(
          success: false, message: 'Aucun grand chantier actif.');
    final day = _communityDayKey(DateTime.now());
    if (project.playerContributionDay == day)
      return const Zone0ActionResult(
          success: false, message: 'Contribution quotidienne déjà utilisée.');
    project
      ..playerContributionDay = day
      ..currentContributionPoints +=
          campHeartConfig.communityProjects.playerDailyContribution
      ..updatedAt = DateTime.now();
    _completeCommunityProjectIfReady(project);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '+${campHeartConfig.communityProjects.playerDailyContribution} points de contribution.');
  }

  void _resolveCommunityDailyContribution(DateTime now) {
    final project = activeCommunityProject;
    if (project == null) return;
    final day = _communityDayKey(now);
    if (project.residentContributionDay == day) return;
    var points = residents
            .where((resident) =>
                resident.isActive &&
                residentHappinessFor(resident) >=
                    campHeartConfig
                        .communityProjects.residentHappinessThreshold)
            .length *
        campHeartConfig.communityProjects.residentDailyContribution;
    final config = campHeartConfig.communityProjects;
    if (config.residentContributionCapEnabled)
      points = math.min(points, config.residentContributionCap).toInt();
    project
      ..residentContributionDay = day
      ..residentContributionToday = points
      ..currentContributionPoints += points
      ..updatedAt = now;
    _completeCommunityProjectIfReady(project);
  }

  String _communityDayKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';

  void _completeCommunityProjectIfReady(CommunityProjectProgress project) {
    if (project.status == CommunityProjectStatus.completed ||
        !project.materialsComplete ||
        project.currentContributionPoints <
            project.definition.requiredContributionPoints) return;
    project
      ..status = CommunityProjectStatus.completed
      ..completedAt = DateTime.now();
    _resolveVisionsForCompletedProject(project, project.completedAt!);
    reports.add(PtipoteMissionReport.system(
        message:
            '${project.definition.label} est terminé. Le camp résiste mieux aux intempéries.',
        sourceBuildingId: 'campHeart',
        subject: 'Grand chantier terminé',
        concerned: 'Camp',
        summary:
            '+${project.definition.globalProtectionPercent}% contre ${project.definition.weatherType}.'));
  }

  void _applyWeatherStockLosses(GlobalWeatherEvent event) {
    if (!resolvedWeatherStockLossEventIds.add(event.id) ||
        event.type == TowerWeatherType.calm) return;
    final impact = event.affectedBiomes
        .where((item) => item.biome == ForageBiome.plaineRiche)
        .firstOrNull;
    if (impact == null || !impact.isAffected) return;
    final rate = campHeartConfig.communityProjects
            .stockLossPercentByIntensity[event.intensity.name] ??
        0;
    final reduction = globalWeatherProtectionPercent(event.type)
        .clamp(0, towerOperationsConfig.buildingViability.protectionCapPercent);
    final effectiveRate =
        rate * impact.localImpactMultiplier * (1 - reduction / 100);
    final perishable = switch (event.type) {
      TowerWeatherType.heatWave => <String>['Organique', 'Repas simple'],
      TowerWeatherType.heavyRain => <String>['Organique', 'Repas simple'],
      TowerWeatherType.toxicCloud => <String>['Organique', 'Repas simple'],
      TowerWeatherType.calm => <String>[],
    };
    var waste = 0;
    var organicLost = 0;
    for (final item in perishable) {
      // Les intempéries restent dangereuses, mais seule la conversion de
      // l'Organique en Déchets est réduite de moitié.
      final itemRate = item == 'Organique' ? effectiveRate / 2 : effectiveRate;
      final loss = (resourceAmount(item) * itemRate / 100).floor();
      if (loss > 0) {
        removeResource(item, loss);
        waste += loss;
        if (item == 'Organique') organicLost += loss;
      }
    }
    if (waste > 0) addResources(<String, int>{'Déchets': waste});
    var batteriesLost = 0;
    if (event.type == TowerWeatherType.heavyRain) {
      batteriesLost = math
          .min(
            exposedBioBatteryCount,
            (exposedBioBatteryCount * effectiveRate / 100).floor(),
          )
          .toInt();
      bioBatteries -= batteriesLost;
    }
    lastWeatherStockIncident = WeatherStockIncident(
        eventId: event.id,
        wasteCreated: waste,
        organicLost: organicLost,
        batteriesLost: batteriesLost,
        protectionPercent: reduction,
        resolvedAt: DateTime.now());
    if (waste > 0 || batteriesLost > 0)
      reports.add(PtipoteMissionReport.system(
          message:
              'Intempérie : $organicLost Organique transformé(s) en Déchets, $batteriesLost Bio-batterie(s) exposée(s) perdue(s).',
          sourceBuildingId: 'campHeart',
          subject: 'Bilan météo',
          concerned: 'Stocks',
          summary: 'Protection globale : $reduction%.'));
  }

  void _reportBuildingViability(String buildingId, String message) {
    reports.add(PtipoteMissionReport.system(
      message: '${buildingViabilityLabel(buildingId)} $message',
      sourceBuildingId: buildingId,
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Viabilité du bâtiment',
      concerned: buildingViabilityLabel(buildingId),
      summary: message,
    ));
  }

  String buildingViabilityLabel(String buildingId) => switch (buildingId) {
        'fablab' => 'Fablab',
        'atelier' => 'Atelier',
        'cuisine' => 'Cuisine',
        'recycler' => 'Recycleur',
        'generator' => 'Bio-générateur (ancien rattachement)',
        'house' => 'Maison du joueur',
        'market' => 'Marché',
        'securityTower' => 'Tour',
        'campHeart' => 'Cœur du camp',
        _ => _biofermenterBiomeForTarget(buildingId) != null
            ? 'Biofermenteur mycélien'
            : territoryBuildingForId(buildingId)?.kind ==
                    PTibugTerritoryKind.nursery
                ? 'Nurserie'
                : territoryBuildingForId(buildingId) != null
                    ? 'Refuge P’TIBUG'
                    : 'Bâtiment',
      };

  void _migrateBuildingViability() {
    final legacyGenerator = buildingViabilities['generator'];
    if (buildingViabilities['house'] == null && legacyGenerator != null) {
      buildingViabilities['house'] = BuildingViabilityState(
        buildingId: 'house',
        current: legacyGenerator.current,
        maximum: legacyGenerator.maximum,
        lastViabilityUpdateAt: legacyGenerator.lastViabilityUpdateAt,
        lastDamageEventId: legacyGenerator.lastDamageEventId,
        viabilityWarningShown: legacyGenerator.viabilityWarningShown,
        restartRequired: legacyGenerator.restartRequired,
        installedStructuralProtections: List<StructuralProtectionType>.from(
          legacyGenerator.installedStructuralProtections,
        ),
      );
    }
    final ids = <String>{
      if (isFablabBuilt) 'fablab',
      if (atelierLevel > 0) 'atelier',
      if (cuisineLevel > 0) 'cuisine',
      if (recyclerLevel > 0) 'recycler',
      if (isMarketBuilt) 'market',
      if (isSecurityTowerBuilt) 'securityTower',
      'house',
      'campHeart',
      ...activePTibugTerritories.map((building) => building.id),
      ...lisiereTerritoryZones.values
          .where((zone) => zone.buildingId == 'biofermenter')
          .map((zone) => biofermenterTargetId(zone.biome)),
    };
    for (final id in ids) {
      viabilityForBuilding(id);
    }
  }

  PTibugTerritoryBuilding get plaineNurseryTerritory =>
      pTibugTerritoryBuildings.putIfAbsent(
        plaineNurseryTerritoryId,
        () => PTibugTerritoryBuilding.nurseryPlaine(
          level: plaineNurseryLevel,
        ),
      );

  List<PTibugTerritoryBuilding> get activePTibugTerritories =>
      pTibugTerritoryBuildings.values
          .where((building) => building.isBuilt)
          .toList(growable: false);

  List<PTibug> pTibugsForTerritory(String territoryId) => pTibugs
      .where((bug) => bug.assignedBuildingId == territoryId)
      .toList(growable: false);

  int pTibugTerritoryCapacity(PTibugTerritoryBuilding building) =>
      building.kind == PTibugTerritoryKind.nursery
          ? pTibugConfig.territory.nurseryCapacityForLevel(building.level)
          : pTibugConfig.territory.refugeCapacityForLevel(building.level);

  int get maxModulesPerPTibug =>
      pTibugConfig.moduleCapacity.capacityForLevel(pTibugModuleCapacityLevel);

  // Patterns are now discovered by the Kernel requirements. This legacy flag
  // stays persisted only to read existing saves; it must no longer open a
  // separate acquisition flow in the Nurserie.
  bool get hasPendingStarterPTibugChoice => false;
  bool isRecyclerUnlocked(int campHeartLevel) =>
      isFablabBuilt &&
      campHeartLevel >= wasteRecyclerConfig.recyclerUnlockCampHeartLevel;
  int get recyclerWasteRequired =>
      wasteRecyclerConfig.wasteRequired(recyclerLevel);
  int get recyclerTankCapacity =>
      wasteRecyclerConfig.tankCapacity(recyclerLevel);
  int get recyclerOutputAmount =>
      recyclerOutputOrganic + recyclerOutputMineral + recyclerOutputOther;
  int get recyclerOutputCapacity =>
      wasteRecyclerConfig.outputCapacity(recyclerLevel);
  int get securityTowerSlots =>
      securityTowerConfig.slotsForLevel(securityTowerLevel);
  bool get hasActiveTowerMission => towerMissions.any(
        (mission) => mission.status == TowerMissionStatus.active,
      );

  int get securityWellbeingModifier =>
      towerOperationsConfig.wellbeingBandFor(refugeSafety).wellbeingModifier;

  int get unhousedPopulation => residents.isEmpty
      ? math.max(0, currentPopulation - housingCapacity)
      : residents
          .where((resident) => resident.isActive && resident.houseId == null)
          .length;

  int get residentHappiness =>
      residents.where((resident) => resident.isActive).isEmpty
          ? housingConfig.neutralHappinessWithoutResidents
          : (residents
                      .where((resident) => resident.isActive)
                      .map(residentHappinessFor)
                      .reduce((sum, value) => sum + value) /
                  residents.where((resident) => resident.isActive).length)
              .round();

  String _residentDayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  ResidentDesireType _stableResidentDesire(Zone0Resident resident) =>
      ResidentDesireType.values[
          resident.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
              ResidentDesireType.values.length];

  ResidentInteriorProfile _stableResidentProfile(Zone0Resident resident) =>
      ResidentInteriorProfile.values[
          (resident.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) ~/ 3) %
              ResidentInteriorProfile.values.length];

  void _migrateResidentNeeds({DateTime? now}) {
    final current = now ?? DateTime.now();
    final dayKey = _residentDayKey(current);
    for (final resident in residents) {
      resident.primaryDesireId ??= _stableResidentDesire(resident).name;
      resident.interiorProfileId ??= _stableResidentProfile(resident).name;
      final needs = resident.needsState;
      if (needs.currentDayKey.isEmpty) {
        needs
          ..currentDayKey = dayKey
          ..mealsRequired = housingConfig.mealsRequiredPerDay
          ..mealsConsumed = housingConfig.mealsRequiredPerDay
          ..nutritionStatus = ResidentNutritionStatus.nourri
          ..activeDesireId = resident.primaryDesireId
          ..interiorProfileId = resident.interiorProfileId ?? 'simple'
          ..lastResolvedAt = current
          ..updatedAt = current;
      }
      // Migration douce des anciens équipements à 4 usages : on garde leur
      // usure déjà subie, mais la jauge de référence passe bien à 10.
      for (final item in resident.ownedItems) {
        final max = item.maxDurability;
        final currentDurability = item.currentDurability;
        if (max != null &&
            currentDurability != null &&
            max < housingConfig.defaultProtectionDurabilityEvents) {
          final spent = math.max(0, max - currentDurability);
          item
            ..maxDurability = housingConfig.defaultProtectionDurabilityEvents
            ..currentDurability = math.max(
              0,
              housingConfig.defaultProtectionDurabilityEvents - spent,
            );
        }
      }
    }
    if (!residentNeedsMigrationCompleted) {
      residentNeedsMigrationCompleted = true;
      residentNeedsGraceUntil = current.add(
        Duration(hours: housingConfig.migrationGraceHours),
      );
      lastResidentNeedsResolutionDayKey = dayKey;
    }
  }

  bool _isResidentFinishedItem(String item) =>
      _residentItemCategory(item) != null;

  /// Les produits qui servent au foyer ne transitent jamais par le sac
  /// personnel de l'habitant : ils rejoignent la réserve de sa Maison avant
  /// toute installation dans un emplacement.
  bool _isHouseholdFinishedItem(String item) => <String>{
        'Meuble simple',
        'Ventilation Termite',
        'Chloro-canaux',
        'Installation filtrante',
        'Lumière solaire',
        'Kit de réparation domestique',
        'Second générateur domestique',
      }.contains(item);

  bool _isResidentDurableEquipment(String item, String category) {
    if (category == 'clothing' ||
        category.endsWith('Protection') ||
        category == 'weatherConsumable') {
      return true;
    }
    final probe = ResidentOwnedItem(
      id: 'durability-probe',
      itemDefinitionId: item,
      category: category,
      quantity: 1,
      acquiredAt: DateTime.now(),
    );
    return TowerWeatherType.values
        .where((weather) => weather != TowerWeatherType.calm)
        .any((weather) => _itemProtectsWeather(probe, weather));
  }

  void _addHouseholdInventoryItem(
    ResidentHouse house,
    String item,
    int quantity,
  ) {
    if (quantity <= 0) return;
    house.householdInventory.update(
      item,
      (current) => current + quantity,
      ifAbsent: () => quantity,
    );
  }

  bool _consumeHouseholdInventoryItem(
    ResidentHouse house,
    String item, {
    int quantity = 1,
  }) {
    final stored = house.householdInventory[item] ?? 0;
    if (stored < quantity || quantity <= 0) return false;
    final remaining = stored - quantity;
    if (remaining == 0) {
      house.householdInventory.remove(item);
    } else {
      house.householdInventory[item] = remaining;
    }
    return true;
  }

  /// A repair kit bought for a household is not a piece of furniture to keep
  /// in reserve: it is consumed as soon as the Market sale is completed.
  /// Keeping this transition here makes both the resident-economy and the
  /// legacy Market request paths apply the exact same, capped repair.
  int _applyPurchasedHouseholdRepairKit(
    ResidentHouse house,
    DateTime now, {
    String? requesterName,
  }) {
    const kit = 'Kit de réparation domestique';
    if (house.currentViability >= house.maximumViability ||
        !_consumeHouseholdInventoryItem(house, kit)) {
      return 0;
    }
    final activeRepair = householdRepairFor(house.id);
    if (activeRepair != null && !activeRepair.isPlayerRepair) {
      activeRepair.status = HouseholdRepairStatus.paused;
      house.isUnderRepair = false;
    }
    final gain =
        math.min(15, house.maximumViability - house.currentViability).toInt();
    house
      ..currentViability += gain
      ..lastAutonomyDecision = requesterName == null
          ? 'Kit de réparation utilisé immédiatement : +$gain% de Viabilité.'
          : '$requesterName a fait utiliser un Kit : +$gain% de Viabilité.'
      ..updatedAt = now;
    for (final resident in residents.where(
        (resident) => resident.houseId == house.id && resident.isActive)) {
      _resolveResidentUncoveredNeed(resident.id, kit, now);
      resident.currentHappiness = residentHappinessFor(resident);
    }
    return gain;
  }

  bool _canResidentStoreOwnedItems(
    Zone0Resident resident,
    String item,
    String category,
    int quantity,
  ) {
    if (quantity <= 0) return true;
    final durable = _isResidentDurableEquipment(item, category);
    if (!durable &&
        resident.ownedItems.any((owned) =>
            owned.itemDefinitionId == item &&
            owned.category == category &&
            owned.isUsable)) {
      return true;
    }
    final requiredSlots = durable ? quantity : 1;
    return resident.ownedItems.length + requiredSlots <=
        residentInventorySlotsFor(resident);
  }

  bool _addResidentOwnedItems(
    Zone0Resident resident,
    String item,
    String category,
    int quantity,
    DateTime acquiredAt, {
    String? sourceTransactionId,
  }) {
    if (quantity <= 0) return true;
    if (!_canResidentStoreOwnedItems(resident, item, category, quantity)) {
      return false;
    }
    final durable = _isResidentDurableEquipment(item, category);
    if (!durable) {
      final existing = resident.ownedItems
          .where((owned) =>
              owned.itemDefinitionId == item &&
              owned.category == category &&
              owned.isUsable)
          .firstOrNull;
      if (existing != null) {
        existing.quantity += quantity;
        return true;
      }
    }
    // Une protection est stockée par exemplaire : chaque barre de durabilité
    // représente bien un seul équipement et non une pile entière.
    for (var index = 0; index < (durable ? quantity : 1); index++) {
      resident.ownedItems.add(ResidentOwnedItem(
        id: 'resident-item-${resident.id}-${item.hashCode}-${acquiredAt.microsecondsSinceEpoch}-$index',
        itemDefinitionId: item,
        category: category,
        quantity: durable ? 1 : quantity,
        acquiredAt: acquiredAt,
        currentDurability:
            durable ? housingConfig.defaultProtectionDurabilityEvents : null,
        maxDurability:
            durable ? housingConfig.defaultProtectionDurabilityEvents : null,
        sourceTransactionId: sourceTransactionId,
      ));
      if (!durable) break;
    }
    return true;
  }

  /// Neuf emplacements sont nécessaires dès l'arrivée : repas, tenue,
  /// consommables et outils personnels ne doivent pas se concurrencer.
  /// Le bonus existant reste conservé pour les anciennes sauvegardes qui ont
  /// déjà bénéficié de l'agrandissement gratuit.
  int residentInventorySlotsFor(Zone0Resident resident) =>
      9 + resident.inventorySlotBonus;

  Zone0ActionResult expandResidentInventory(String residentId) {
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    if (resident == null) {
      return const Zone0ActionResult(
          success: false, message: 'Habitant introuvable.');
    }
    if (resident.inventorySlotBonus >= 3) {
      return const Zone0ActionResult(
          success: false, message: 'Inventaire déjà agrandi au maximum.');
    }
    resident.inventorySlotBonus = 3;
    resident.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Inventaire de ${resident.displayName} agrandi à ${residentInventorySlotsFor(resident)} cases.',
    );
  }

  String? _residentItemCategory(String item) {
    switch (item.trim().toLowerCase()) {
      case 'repas simple':
        return 'meal';
      case 'boisson tonique':
        return 'drink';
      case 'tenue ombragée':
      case 'tenue anti-pluie':
      case 'tenue filtrante':
        return 'clothing';
      case 'couche imperméabilisante':
      case 'réflecteur thermique':
      case 'filtre personnel':
        return 'weatherConsumable';
      case 'peau amphibienne':
      case 'tenue étanche':
        return 'rainProtection';
      case 'meuble simple':
        return 'furniture';
      case 'ventilation termite':
      case 'chloro-canaux':
      case 'installation filtrante':
        return 'technicalEquipment';
      case 'lumière solaire':
        return 'furniture';
      case 'kit de réparation domestique':
      case 'second générateur domestique':
        return 'householdInstallation';
      default:
        return null;
    }
  }

  bool _itemProtectsWeather(ResidentOwnedItem item, TowerWeatherType type) {
    final name = item.itemDefinitionId.toLowerCase();
    return switch (type) {
      TowerWeatherType.heatWave => name == 'tenue ombragée',
      TowerWeatherType.heavyRain => name == 'tenue anti-pluie' ||
          name == 'peau amphibienne' ||
          name == 'tenue étanche',
      TowerWeatherType.toxicCloud =>
        name == 'tenue filtrante' || name == 'biofiltration personnelle',
      TowerWeatherType.calm => false,
    };
  }

  bool _itemIsWeatherConsumable(
    ResidentOwnedItem item,
    TowerWeatherType type,
  ) {
    final name = item.itemDefinitionId.toLowerCase();
    return switch (type) {
      TowerWeatherType.heatWave => name == 'réflecteur thermique',
      TowerWeatherType.heavyRain => name == 'couche imperméabilisante',
      TowerWeatherType.toxicCloud => name == 'filtre personnel',
      TowerWeatherType.calm => false,
    };
  }

  String _weatherConsumableFor(TowerWeatherType type) => switch (type) {
        TowerWeatherType.heatWave => 'Réflecteur thermique',
        TowerWeatherType.heavyRain => 'Couche imperméabilisante',
        TowerWeatherType.toxicCloud => 'Filtre personnel',
        TowerWeatherType.calm => '',
      };

  int weatherProtectionUsesFor(GlobalWeatherIntensity intensity) =>
      switch (intensity) {
        GlobalWeatherIntensity.moderate => 1,
        GlobalWeatherIntensity.strong => 2,
        GlobalWeatherIntensity.severe => 3,
        GlobalWeatherIntensity.calm => 0,
      };

  String _weatherProtectionLabel(TowerWeatherType type) => switch (type) {
        TowerWeatherType.heatWave => 'protection chaleur',
        TowerWeatherType.heavyRain => 'protection pluie',
        TowerWeatherType.toxicCloud => 'protection nuage toxique',
        TowerWeatherType.calm => 'aucune protection',
      };

  int _weatherProtectionPenalty(GlobalWeatherIntensity intensity) =>
      switch (intensity) {
        GlobalWeatherIntensity.moderate =>
          housingConfig.weatherProtectionModeratePenalty,
        GlobalWeatherIntensity.strong =>
          housingConfig.weatherProtectionStrongPenalty,
        GlobalWeatherIntensity.severe =>
          housingConfig.weatherProtectionSeverePenalty,
        GlobalWeatherIntensity.calm => 0,
      };

  /// Resolves a daily state only once per date. A migration grants the current
  /// day, then normal days consume meals from the personal finished-goods bag.
  bool resolveResidentNeeds({DateTime? now}) {
    final current = now ?? DateTime.now();
    _migrateResidentNeeds(now: current);
    final dayKey = _residentDayKey(current);
    var changed = false;
    for (final resident in residents.where((item) => item.isActive)) {
      final needs = resident.needsState;
      if (needs.currentDayKey != dayKey) {
        needs
          ..currentDayKey = dayKey
          ..mealsRequired = housingConfig.mealsRequiredPerDay
          ..mealsConsumed = 0
          ..activeDesireId = resident.primaryDesireId
          ..desireSatisfied = false
          ..requiredWeatherProtectionTypes.clear()
          ..missingWeatherProtectionTypes.clear();
        changed = true;
      }
      if (residentNeedsGraceUntil == null ||
          !current.isBefore(residentNeedsGraceUntil!)) {
        final meals = resident.ownedItems
            .where((item) => item.isUsable && item.category == 'meal')
            .toList()
          ..sort((a, b) => a.acquiredAt.compareTo(b.acquiredAt));
        for (final meal in meals) {
          while (
              needs.mealsConsumed < needs.mealsRequired && meal.quantity > 0) {
            meal.quantity -= 1;
            meal.lastUsedAt = current;
            needs.mealsConsumed += 1;
            changed = true;
          }
        }
      }
      final previousNutritionStatus = needs.nutritionStatus;
      final nutritionStatus = needs.mealsConsumed >= needs.mealsRequired
          ? ResidentNutritionStatus.nourri
          : needs.mealsConsumed == 1
              ? ResidentNutritionStatus.partiellementNourri
              : ResidentNutritionStatus.nonNourri;
      needs.nutritionStatus = nutritionStatus;
      final nutritionModifier = switch (needs.nutritionStatus) {
        ResidentNutritionStatus.nourri => 0,
        ResidentNutritionStatus.partiellementNourri =>
          -housingConfig.partialNutritionHappinessPenalty,
        ResidentNutritionStatus.nonNourri =>
          -housingConfig.noNutritionHappinessPenalty,
      };
      if (previousNutritionStatus != nutritionStatus ||
          resident.happinessModifiers['nutrition'] != nutritionModifier) {
        changed = true;
      }
      resident.happinessModifiers['nutrition'] = nutritionModifier;
      _resolveResidentInteriorAndDesire(resident, current);
      needs
        ..lastResolvedAt = current
        ..updatedAt = current;
      resident.updatedAt = current;
    }
    lastResidentNeedsResolutionDayKey = dayKey;
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _resolveResidentInteriorAndDesire(Zone0Resident resident, DateTime now) {
    final needs = resident.needsState;
    final house = residentHouseForId(resident.houseId);
    final installed = house?.installedFurnitureItems ?? const <String>[];
    final tags = <String>{};
    for (final item in installed) {
      switch (item.toLowerCase()) {
        case 'meuble simple':
          tags.addAll(<String>{'bed', 'functionalFurniture', 'decoration'});
        case 'lumière solaire':
          tags.addAll(<String>{'functionalFurniture', 'decoration'});
        case 'ventilation termite':
        case 'chloro-canaux':
        case 'installation filtrante':
          tags.addAll(<String>{'technicalEquipment', 'tools'});
      }
    }
    final profile = ResidentInteriorProfile.values.firstWhere(
      (value) => value.name == (resident.interiorProfileId ?? 'simple'),
      orElse: () => ResidentInteriorProfile.simple,
    );
    final satisfied = switch (profile) {
      ResidentInteriorProfile.simple =>
        tags.contains('bed') && tags.contains('functionalFurniture'),
      ResidentInteriorProfile.technique => tags.contains('bed') &&
          tags.contains('functionalFurniture') &&
          tags.contains('technicalEquipment') &&
          tags.contains('tools'),
      ResidentInteriorProfile.esthete => tags.contains('bed') &&
          installed.length >= 2 &&
          tags.contains('decoration'),
    };
    needs
      ..interiorProfileId = profile.name
      ..interiorSatisfied = satisfied
      ..houseViabilitySatisfied = house == null || house.currentViability >= 50;
    resident.happinessModifiers['interior'] = satisfied
        ? housingConfig.interiorSatisfiedHappinessBonus
        : -housingConfig.interiorUnsatisfiedHappinessPenalty;
    final desire = ResidentDesireType.values.firstWhere(
      (value) => value.name == resident.primaryDesireId,
      orElse: () => ResidentDesireType.sweetTooth,
    );
    final usable = resident.ownedItems.where((item) => item.isUsable).toList();
    final desireSatisfied = switch (desire) {
      ResidentDesireType.sweetTooth => usable.any((item) =>
          item.category == 'sweetFood' || item.category == 'highEnergyFood'),
      ResidentDesireType.fashion => usable
              .where((item) => item.category == 'clothing')
              .fold<int>(0, (sum, item) => sum + item.quantity) >=
          housingConfig.clothingRequiredForFashionDesire,
      ResidentDesireType.comfort => satisfied,
      ResidentDesireType.tools =>
        usable.any((item) => item.category == 'technicalEquipment') ||
            tags.contains('technicalEquipment'),
    };
    needs.desireSatisfied = desireSatisfied;
    resident.happinessModifiers['desire'] =
        desireSatisfied ? housingConfig.desireSatisfiedHappinessBonus : 0;
  }

  Zone0ActionResult giveResidentFinishedItem({
    required String residentId,
    required String itemName,
    int quantity = 1,
    bool consumeFromPlayerInventory = true,
  }) {
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    final category = _residentItemCategory(itemName);
    if (resident == null)
      return const Zone0ActionResult(
          success: false, message: 'Habitant introuvable.');
    if (category == null || !_isResidentFinishedItem(itemName)) {
      return const Zone0ActionResult(
          success: false,
          message:
              'Seuls les produits finis peuvent être attribués à un habitant.');
    }
    final safeQuantity = math.max(1, quantity);
    if (consumeFromPlayerInventory && resourceAmount(itemName) < safeQuantity) {
      return const Zone0ActionResult(
          success: false, message: 'Stock du refuge insuffisant.');
    }
    final house = residentHouseForId(resident.houseId);
    if ((house == null || !_isHouseholdFinishedItem(itemName)) &&
        !_canResidentStoreOwnedItems(
            resident, itemName, category, safeQuantity)) {
      return Zone0ActionResult(
        success: false,
        message:
            'Inventaire de ${resident.displayName} plein (${residentInventorySlotsFor(resident)} cases).',
      );
    }
    if (consumeFromPlayerInventory) removeResource(itemName, safeQuantity);
    if (house != null && _isHouseholdFinishedItem(itemName)) {
      _addHouseholdInventoryItem(house, itemName, safeQuantity);
    } else {
      _addResidentOwnedItems(
        resident,
        itemName,
        category,
        safeQuantity,
        DateTime.now(),
      );
    }
    resolveResidentNeeds();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$itemName attribué à ${resident.displayName}.');
  }

  Zone0ActionResult installResidentHouseFurniture({
    required String houseId,
    required String itemName,
  }) {
    final house = residentHouseForId(houseId);
    if (house == null)
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    if (house.installedFurnitureItems.length >= house.furnitureSlots) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun emplacement de mobilier disponible.');
    }
    if (_residentItemCategory(itemName) != 'furniture') {
      return const Zone0ActionResult(
          success: false,
          message: 'Meuble fini requis dans l’inventaire de la maison.');
    }
    if (!_consumeHouseholdInventoryItem(house, itemName) &&
        (resourceAmount(itemName) < 1 || removeResource(itemName, 1) <= 0)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Meuble fini requis dans l’inventaire de la maison.');
    }
    house.installedFurnitureItems.add(itemName);
    for (final resident
        in residents.where((item) => item.houseId == house.id)) {
      _resolveResidentInteriorAndDesire(resident, DateTime.now());
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$itemName installé dans ${house.displayName}.');
  }

  /// Household installations have their own four slots: three technical
  /// installations plus one stackable consumable reserve (e.g. cartridges).
  Zone0ActionResult installResidentHouseInstallation({
    required String houseId,
    required String itemName,
  }) {
    final house = residentHouseForId(houseId);
    if (house == null) {
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    }
    // The fourth household slot is permanently reserved for a stack of
    // filtration cartridges; only three physical installations may be fitted.
    if (house.installedInstallationItems.length >=
        math.max(0, house.installationSlots - 1)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Aucun emplacement d’installation disponible.');
    }
    final category = _residentItemCategory(itemName);
    if (category != 'technicalEquipment' &&
        category != 'householdInstallation') {
      return const Zone0ActionResult(
          success: false, message: 'Installation technique requise.');
    }
    if (!_consumeHouseholdInventoryItem(house, itemName) &&
        (resourceAmount(itemName) < 1 || removeResource(itemName, 1) <= 0)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Installation absente de l’inventaire du foyer.');
    }
    house.installedInstallationItems.add(itemName);
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$itemName installé dans ${house.displayName}.');
  }

  void _prepareResidentWeatherNeeds(GlobalWeatherEvent event) {
    if (event.type == TowerWeatherType.calm ||
        !event.isBiomeAffected(ForageBiome.plaineRiche)) return;
    final label = _weatherProtectionLabel(event.type);
    for (final resident in residents.where((item) => item.isActive)) {
      final needs = resident.needsState;
      if (!needs.requiredWeatherProtectionTypes.contains(label)) {
        needs.requiredWeatherProtectionTypes.add(label);
      }
      final protected = resident.ownedItems.any(
          (item) => item.isUsable && _itemProtectsWeather(item, event.type));
      if (protected) {
        needs.missingWeatherProtectionTypes.remove(label);
        // Une tenue reste utilisable sans consommable, mais le foyer est
        // averti avant la météo afin de préserver ses dix usages.
        final consumable = _weatherConsumableFor(event.type);
        final hasConsumable = resident.ownedItems.any((item) =>
            item.isUsable && _itemIsWeatherConsumable(item, event.type));
        if (consumable.isNotEmpty && !hasConsumable) {
          _upsertResidentUncoveredNeed(
            resident: resident,
            item: consumable,
            category: 'weatherConsumable',
            quantity: 1,
            reason: ResidentUncoveredNeedReason.noStock,
            urgency: 2,
            now: DateTime.now(),
          );
        }
      } else if (!needs.missingWeatherProtectionTypes.contains(label)) {
        needs.missingWeatherProtectionTypes.add(label);
      }
    }
  }

  void _resolveResidentWeatherImpact(GlobalWeatherEvent event) {
    if (!resolvedResidentWeatherEventIds.add(event.id)) return;
    if (event.type == TowerWeatherType.calm ||
        !event.isBiomeAffected(ForageBiome.plaineRiche)) return;
    final label = _weatherProtectionLabel(event.type);
    for (final resident in residents.where((item) => item.isActive)) {
      final supportCandidates = resident.ownedItems
          .where(
              (item) => item.isUsable && _itemProtectsWeather(item, event.type))
          .toList()
        ..sort((a, b) => (a.currentDurability ?? 999999)
            .compareTo(b.currentDurability ?? 999999));
      final support = supportCandidates.firstOrNull;
      if (support == null) {
        resident.needsState.missingWeatherProtectionTypes.add(label);
        resident.happinessModifiers['weather-${event.id}'] =
            -_weatherProtectionPenalty(event.intensity);
      } else {
        var remainingUses = weatherProtectionUsesFor(event.intensity);
        final consumables = resident.ownedItems
            .where((item) =>
                item.isUsable && _itemIsWeatherConsumable(item, event.type))
            .toList()
          ..sort((a, b) => (a.currentDurability ?? 999999)
              .compareTo(b.currentDurability ?? 999999));
        for (final consumable in consumables) {
          if (remainingUses <= 0) break;
          final available = consumable.currentDurability ?? 0;
          final consumed = math.min(available, remainingUses);
          if (consumed <= 0) continue;
          consumable
            ..currentDurability = available - consumed
            ..equippedOrActive = true
            ..lastUsedAt = DateTime.now();
          remainingUses -= consumed;
          if (consumable.currentDurability == 0) {
            resident.ownedItems.remove(consumable);
            _upsertResidentUncoveredNeed(
              resident: resident,
              item: consumable.itemDefinitionId,
              category: consumable.category,
              quantity: 1,
              reason: ResidentUncoveredNeedReason.noStock,
              urgency: 3,
              now: DateTime.now(),
            );
          }
        }
        if (remainingUses > 0 && support.currentDurability != null) {
          support.currentDurability = math.max(
            0,
            support.currentDurability! - remainingUses,
          );
          if (support.currentDurability == 0) {
            resident.ownedItems.remove(support);
            _upsertResidentUncoveredNeed(
              resident: resident,
              item: support.itemDefinitionId,
              category: support.category,
              quantity: 1,
              reason: ResidentUncoveredNeedReason.noStock,
              urgency: 3,
              now: DateTime.now(),
            );
          }
        }
        support
          ..equippedOrActive = true
          ..lastUsedAt = DateTime.now();
        resident.needsState.missingWeatherProtectionTypes.remove(label);
      }
      resident.needsState.updatedAt = DateTime.now();
    }
  }

  void _clearResidentWeatherImpact(GlobalWeatherEvent event) {
    for (final resident in residents) {
      resident.happinessModifiers.remove('weather-${event.id}');
      for (final item in resident.ownedItems) {
        item.equippedOrActive = false;
      }
    }
  }

  ResidentPassion _residentPassionFor(Zone0Resident resident) =>
      ResidentPassion.values.firstWhere(
        (value) => value.name == resident.primaryPassionId,
        orElse: () => ResidentPassion.cooking,
      );

  String residentPassionLabel(ResidentPassion passion) => switch (passion) {
        ResidentPassion.cooking => 'Cuisiner',
        ResidentPassion.crafting => 'Fabriquer',
        ResidentPassion.trading => 'Commercer',
        ResidentPassion.livingObservation => 'Observer le vivant',
        ResidentPassion.watching => 'Veiller',
      };

  String communityRoleLabel(CommunityRoleType role) => switch (role) {
        CommunityRoleType.kitchenCook => 'Cuisine communautaire',
        CommunityRoleType.fablabMaker => 'Fabrication communautaire',
        CommunityRoleType.marketCounter => 'Comptoir général',
        CommunityRoleType.lisiereObserver => 'Observation en Lisière',
        CommunityRoleType.securityWatch => 'Veille de sécurité',
        CommunityRoleType.weatherWatch => 'Veille météo',
      };

  ResidentPassion _rolePassion(CommunityRoleType role) => switch (role) {
        CommunityRoleType.kitchenCook => ResidentPassion.cooking,
        CommunityRoleType.fablabMaker => ResidentPassion.crafting,
        CommunityRoleType.marketCounter => ResidentPassion.trading,
        CommunityRoleType.lisiereObserver => ResidentPassion.livingObservation,
        CommunityRoleType.securityWatch ||
        CommunityRoleType.weatherWatch =>
          ResidentPassion.watching,
      };

  String _roleBuildingId(CommunityRoleType role) => switch (role) {
        CommunityRoleType.kitchenCook => 'cuisine',
        CommunityRoleType.fablabMaker => 'atelier',
        CommunityRoleType.marketCounter => 'market',
        CommunityRoleType.lisiereObserver => 'lisiere',
        CommunityRoleType.securityWatch ||
        CommunityRoleType.weatherWatch =>
          'securityTower',
      };

  int communityRoleSlotCount(CommunityRoleType role) => switch (role) {
        CommunityRoleType.kitchenCook => math.max(0, cuisineLevel),
        CommunityRoleType.fablabMaker => math.max(0, atelierLevel),
        // Un emplacement d'habitant par niveau, comme Cuisine et Atelier.
        CommunityRoleType.marketCounter => isMarketBuilt ? marketLevel : 0,
        // La Lisière n'a pas de niveau : elle offre donc ses huit postes
        // d'observation dès qu'elle est accessible.
        CommunityRoleType.lisiereObserver =>
          isBiomeUnlocked(ForageBiome.plaineRiche) ? 8 : 0,
        CommunityRoleType.securityWatch ||
        CommunityRoleType.weatherWatch =>
          securityTowerSlots,
      };

  /// The research tower reads the same weighted data-family tables as Lisière
  /// research. It only exposes information and a weather modifier; it does
  /// not create a second data-cell generator.
  double towerResearchWeatherMultiplierFor(ForageBiome biome) {
    if (!isTowerResearchUnlocked) return 1;
    final weather = activeGlobalWeatherEvent;
    if (weather == null || weather.type == TowerWeatherType.calm) return 1;
    final ptibugBiome = _ptibugBiomeForForageBiome(biome);
    final compatible = pTibugConfig.biomes[ptibugBiome]?.weatherTypes
            .contains(weather.type.name) ??
        false;
    return compatible ? 1.25 : .75;
  }

  int towerResearchCellChanceFor(ForageBiome biome, {int ordinal = 1}) {
    final base = towerOperationsConfig.research.cellChanceFor(
      ForageMissionType.research,
      ordinal,
    );
    return (base * towerResearchWeatherMultiplierFor(biome))
        .round()
        .clamp(0, 100)
        .toInt();
  }

  int biomeResearchProgressFor(ForageBiome biome) =>
      biomeSecurity[biome]?.researchProgress ?? 0;

  /// Les expéditions de recherche de la Lisière et la Tour contribuent au
  /// même savoir local. Sous 50 %, les données sont trop incertaines : les
  /// chances de trouver une Capsule sont donc divisées par deux.
  double capsuleDiscoveryMultiplierFor(ForageBiome biome) =>
      biomeResearchProgressFor(biome) < 50 ? .5 : 1;

  bool isBiomeResearching(ForageBiome biome) => towerBiomeResearch.any(
        (research) => research.biome == biome && research.isActive,
      );

  TowerBiomeResearch? activeBiomeResearchFor(ForageBiome biome) =>
      towerBiomeResearch
          .where((research) => research.biome == biome && research.isActive)
          .firstOrNull;

  Zone0ActionResult startTowerBiomeResearch({
    required ForageBiome biome,
    required int hours,
  }) {
    if (!isTowerResearchUnlocked) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Tour de recherche est verrouillée.',
      );
    }
    if (!isBiomeUnlocked(biome)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce biome doit être exploré avant son analyse.',
      );
    }
    if (hours <= 0 || !<int>[1, 2, 4, 8].contains(hours)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Durée de recherche invalide.',
      );
    }
    if (isBiomeResearching(biome)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Une recherche est déjà en cours dans ce biome.',
      );
    }
    final now = DateTime.now();
    final realMinutes =
        math.max(1, (hours * 60 / lisiereForageConfig.forageTimeScale).round());
    towerBiomeResearch.add(TowerBiomeResearch(
      id: 'tower-research-${biome.name}-${now.microsecondsSinceEpoch}',
      biome: biome,
      theoreticalHours: hours,
      startedAt: now,
      endsAt: now.add(Duration(minutes: realMinutes)),
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Recherche lancée dans ${lisiereForageConfig.biomes[biome]!.label}.',
    );
  }

  Map<PTibugDataFamily, int> towerResearchDataChancesFor(
    ForageBiome biome, {
    int ordinal = 1,
  }) {
    final weights = towerResearchFamilyWeightsFor(biome);
    final total = weights.values.fold<int>(0, (sum, value) => sum + value);
    final cellChance = towerResearchCellChanceFor(biome, ordinal: ordinal);
    if (total <= 0 || cellChance <= 0) return const <PTibugDataFamily, int>{};
    return <PTibugDataFamily, int>{
      for (final family in PTibugDataFamily.values)
        family: ((weights[family] ?? 0) * cellChance / total).round(),
    };
  }

  /// Stable family weights exposed once the Tower has fully analysed a biome.
  /// They deliberately remain independent from the number of Cells found.
  Map<PTibugDataFamily, int> towerResearchFamilyWeightsFor(
    ForageBiome biome,
  ) {
    final weights =
        pTibugConfig.biomes[_ptibugBiomeForForageBiome(biome)]!.dataWeights;
    return <PTibugDataFamily, int>{
      for (final family in PTibugDataFamily.values)
        family: weights[family] ?? 0,
    };
  }

  String get towerWeatherHudLabel {
    final weather = activeGlobalWeatherEvent;
    if (weather == null || weather.type == TowerWeatherType.calm) {
      return 'Météo calme';
    }
    return '${_weatherTypeLabel(weather.type)} · ${_weatherIntensityLabel(weather.intensity)}';
  }

  CommunityRoleStatus _roleAvailability(CommunityRoleType role) {
    final built = switch (role) {
      CommunityRoleType.kitchenCook ||
      CommunityRoleType.fablabMaker =>
        isFablabBuilt,
      CommunityRoleType.marketCounter => isMarketBuilt,
      CommunityRoleType.lisiereObserver =>
        isBiomeUnlocked(ForageBiome.plaineRiche),
      CommunityRoleType.securityWatch ||
      CommunityRoleType.weatherWatch =>
        isSecurityTowerBuilt,
    };
    if (!built || communityRoleSlotCount(role) <= 0) {
      return CommunityRoleStatus.awaitingBuilding;
    }
    final buildingId = _roleBuildingId(role);
    if (buildingId != 'lisiere' && !isBuildingOperational(buildingId)) {
      return CommunityRoleStatus.unavailable;
    }
    return CommunityRoleStatus.active;
  }

  CommunityRoleAssignment? communityRoleForResident(String residentId) =>
      communityRoleAssignments
          .where((assignment) =>
              assignment.residentId == residentId &&
              assignment.status != CommunityRoleStatus.archived)
          .lastOrNull;

  List<CommunityRoleType> compatibleCommunityRolesFor(Zone0Resident resident) {
    final passion = _residentPassionFor(resident);
    return CommunityRoleType.values
        .where((role) =>
            communityRolesConfig.allowNonPassionWork ||
            _rolePassion(role) == passion)
        .toList(growable: false);
  }

  Iterable<CommunityRoleAssignment> get activeCommunityRoles =>
      communityRoleAssignments.where((assignment) => assignment.isActive);

  /// Les habitants gardent automatiquement le poste correspondant à leur
  /// passion. Le joueur n'a pas à faire de micro-gestion ; l'absence de slot
  /// reste visible via `activeCommunityRoleId == null`.
  bool _autoAssignResidentsToCommunityRoles() {
    var assignedAny = false;
    for (final resident in residents.where((item) => item.isActive)) {
      if (communityRoleForResident(resident.id) != null) continue;
      final passion = _residentPassionFor(resident);
      final role = CommunityRoleType.values.firstWhere(
        (candidate) =>
            _rolePassion(candidate) == passion &&
            _roleAvailability(candidate) == CommunityRoleStatus.active &&
            communityRoleAssignments
                    .where((assignment) =>
                        assignment.roleType == candidate &&
                        assignment.status != CommunityRoleStatus.archived)
                    .length <
                communityRoleSlotCount(candidate),
        orElse: () => CommunityRoleType.kitchenCook,
      );
      if (_rolePassion(role) != passion ||
          _roleAvailability(role) != CommunityRoleStatus.active) {
        continue;
      }
      if (assignResidentCommunityRole(residentId: resident.id, roleType: role)
          .success) {
        assignedAny = true;
      }
    }
    return assignedAny;
  }

  void _migrateResidentPassionsAndRoles() {
    if (!residentPassionMigrationCompleted) {
      final missing = residents
          .where((resident) =>
              resident.primaryPassionId == null ||
              resident.primaryPassionId!.isEmpty)
          .toList();
      // First pass deliberately diversifies small existing populations; a
      // later weighted deterministic pass fills the rest without rerolls.
      for (var index = 0; index < missing.length; index++) {
        final resident = missing[index];
        final passion = index < ResidentPassion.values.length
            ? ResidentPassion.values[index]
            : _weightedStablePassion(resident);
        resident.primaryPassionId = passion.name;
      }
      for (final resident in residents) {
        if (resident.primaryPassionId == 'protect' ||
            resident.primaryPassionId == 'weatherStudy' ||
            resident.primaryPassionId == 'weather') {
          resident.primaryPassionId = ResidentPassion.watching.name;
        }
      }
      residentPassionMigrationCompleted = true;
    }
    // Reject only conflicting legacy assignments; all other assignments retain
    // their history and wait for their building if unavailable.
    final seenSlots = <String>{};
    for (final assignment in communityRoleAssignments
        .where((item) => item.status != CommunityRoleStatus.archived)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt))) {
      final slotKey = '${assignment.buildingId}:${assignment.slotId}';
      if (!seenSlots.add(slotKey) ||
          communityRoleForResident(assignment.residentId)?.id !=
              assignment.id) {
        assignment.status = CommunityRoleStatus.awaitingBuilding;
      }
      assignment.lastResolvedAt ??= DateTime.now();
      final resident = residents
          .where((item) => item.id == assignment.residentId)
          .firstOrNull;
      if (resident != null) {
        resident
          ..activeCommunityRoleId = assignment.id
          ..assignedBuildingId = assignment.buildingId;
      }
    }
  }

  ResidentPassion _weightedStablePassion(Zone0Resident resident) {
    final weights = communityRolesConfig.passionWeights;
    final total = ResidentPassion.values.fold<int>(
      0,
      (sum, passion) => sum + math.max(0, weights[passion.name] ?? 0),
    );
    if (total <= 0) return ResidentPassion.cooking;
    var roll =
        resident.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % total;
    for (final passion in ResidentPassion.values) {
      roll -= math.max(0, weights[passion.name] ?? 0);
      if (roll < 0) return passion;
    }
    return ResidentPassion.watching;
  }

  Zone0ActionResult assignResidentCommunityRole({
    required String residentId,
    required CommunityRoleType roleType,
    String? requestedSlotId,
  }) {
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    if (resident == null)
      return const Zone0ActionResult(
          success: false, message: 'Habitant introuvable.');
    final passion = _residentPassionFor(resident);
    final requiredPassion = _rolePassion(roleType);
    if (passion != requiredPassion &&
        !communityRolesConfig.allowNonPassionWork) {
      return Zone0ActionResult(
          success: false,
          message:
              '${resident.displayName} est passionné par ${residentPassionLabel(passion)}.');
    }
    final availability = _roleAvailability(roleType);
    final slots = communityRoleSlotCount(roleType);
    if (slots <= 0)
      return const Zone0ActionResult(
          success: false,
          message: 'Aucun slot habitant disponible dans ce bâtiment.');
    final buildingId = _roleBuildingId(roleType);
    final usedSlots = communityRoleAssignments
        .where((assignment) =>
            assignment.buildingId == buildingId &&
            assignment.status != CommunityRoleStatus.archived)
        .map((assignment) => assignment.slotId)
        .toSet();
    final slotId = requestedSlotId ??
        List<String>.generate(slots, (index) => 'resident-$index')
            .where((slot) => !usedSlots.contains(slot))
            .firstOrNull;
    if (slotId == null || usedSlots.contains(slotId)) {
      return const Zone0ActionResult(
          success: false, message: 'Tous les slots habitants sont occupés.');
    }
    final previous = communityRoleForResident(resident.id);
    if (previous != null) {
      previous
        ..status = CommunityRoleStatus.archived
        ..updatedAt = DateTime.now();
    }
    final now = DateTime.now();
    final assignment = CommunityRoleAssignment(
      id: 'community-role-${resident.id}-${now.microsecondsSinceEpoch}',
      residentId: resident.id,
      passion: requiredPassion,
      roleType: roleType,
      buildingId: buildingId,
      slotId: slotId,
      status: availability,
      startedAt: now,
      lastResolvedAt: now,
      coverageCapacity: roleType == CommunityRoleType.kitchenCook
          ? communityRolesConfig.cookingCoveragePerCycle
          : 0,
      previousAssignmentId: previous?.id,
    );
    communityRoleAssignments.add(assignment);
    resident
      ..assignedBuildingId = buildingId
      ..activeCommunityRoleId = assignment.id;
    if (roleType == CommunityRoleType.marketCounter) {
      resident
        ..eligibleForShopOwnership = true
        ..commercialAssignmentStatus = 'counterAssigned';
    }
    resident.happinessModifiers['passion-role'] =
        availability == CommunityRoleStatus.active
            ? communityRolesConfig.passionHappinessBonus
            : 0;
    resident.updatedAt = now;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            '${resident.displayName} est affecté à ${communityRoleLabel(roleType)}.');
  }

  Zone0ActionResult removeResidentCommunityRole(String residentId) {
    final assignment = communityRoleForResident(residentId);
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    if (assignment == null || resident == null) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun rôle actif à retirer.');
    }
    assignment
      ..status = CommunityRoleStatus.archived
      ..updatedAt = DateTime.now();
    resident
      ..assignedBuildingId = null
      ..activeCommunityRoleId = null
      ..happinessModifiers['passion-role'] = 0
      ..updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '${resident.displayName} quitte son rôle communautaire.');
  }

  int _effectiveResidentUnits(CommunityRoleAssignment assignment, int cycles) {
    final accumulated = assignment.efficiencyRemainder +
        cycles * communityRolesConfig.communityEfficiencyPercent;
    assignment.efficiencyRemainder = accumulated % 100;
    return accumulated ~/ 100;
  }

  void _giveCommunityMeal(Zone0Resident resident, DateTime now) {
    // The kitchen distributes a physical finished meal and the recipient eats
    // it immediately. A consumed history entry prevents it being consumed a
    // second time during the next daily needs pass.
    resident.ownedItems.add(ResidentOwnedItem(
      id: 'community-meal-${resident.id}-${now.microsecondsSinceEpoch}',
      itemDefinitionId: 'Repas simple',
      category: 'meal',
      quantity: 0,
      acquiredAt: now,
      sourceTransactionId: 'community-kitchen',
      lastUsedAt: now,
      status: ResidentOwnedItemStatus.consumed,
    ));
  }

  bool resolveCommunityRoles({DateTime? now}) {
    if (!communityRolesConfig.enabled) return false;
    final current = now ?? DateTime.now();
    _migrateResidentPassionsAndRoles();
    var changed = _autoAssignResidentsToCommunityRoles();
    final intervalSeconds =
        math.max(60, communityRolesConfig.roleIntervalMinutes * 60);
    for (final assignment in communityRoleAssignments
        .where((item) => item.status != CommunityRoleStatus.archived)) {
      final resident = residents
          .where((item) => item.id == assignment.residentId)
          .firstOrNull;
      if (resident == null || !resident.isActive) {
        if (assignment.status != CommunityRoleStatus.paused) {
          assignment.status = CommunityRoleStatus.paused;
          assignment.updatedAt = current;
          changed = true;
        }
        continue;
      }
      final availability = _roleAvailability(assignment.roleType);
      if (availability != CommunityRoleStatus.active) {
        if (assignment.status != availability ||
            resident.happinessModifiers['passion-role'] != 0) {
          changed = true;
        }
        assignment
          ..status = availability
          ..pausedAt = current
          ..updatedAt = current;
        resident.happinessModifiers['passion-role'] = 0;
        continue;
      }
      if (assignment.status != CommunityRoleStatus.active ||
          resident.happinessModifiers['passion-role'] !=
              communityRolesConfig.passionHappinessBonus) {
        changed = true;
      }
      assignment.status = CommunityRoleStatus.active;
      resident.happinessModifiers['passion-role'] =
          communityRolesConfig.passionHappinessBonus;
      final previous = assignment.lastResolvedAt ?? current;
      final elapsed = current.difference(previous).inSeconds;
      final cycles = math.min(48, math.max(0, elapsed ~/ intervalSeconds));
      if (cycles <= 0) continue;
      final units = _effectiveResidentUnits(assignment, cycles);
      assignment.lastResolvedAt =
          previous.add(Duration(seconds: cycles * intervalSeconds));
      changed = true;
      if (units > 0) {
        changed =
            _resolveCommunityRoleUnits(assignment, resident, units, current) ||
                changed;
      }
      assignment.updatedAt = current;
    }
    lastCommunityRoleResolutionAt = current;
    if (changed) {
      resolveResidentNeeds(now: current);
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  bool _resolveCommunityRoleUnits(
    CommunityRoleAssignment assignment,
    Zone0Resident resident,
    int units,
    DateTime now,
  ) {
    if (assignment.outputDayKey != _residentDayKey(now)) {
      assignment
        ..outputDayKey = _residentDayKey(now)
        ..dailyOutput = 0;
    }
    switch (assignment.roleType) {
      case CommunityRoleType.kitchenCook:
        final recipe = craftConfig.simpleMealRecipe;
        final inputs = <String, int>{
          ...recipe.ingredients,
          ...recipe.contextIngredients
        };
        var produced = 0;
        for (var index = 0;
            index < units &&
                assignment.dailyOutput <
                    communityRolesConfig.cookingMaximumMealsPerDay;
            index++) {
          if (!hasResources(inputs)) {
            assignment.status = CommunityRoleStatus.awaitingResources;
            break;
          }
          if (!hasInventoryCapacityFor(
              <String, int>{recipe.resultItem: recipe.resultAmount})) {
            assignment.status = CommunityRoleStatus.awaitingResources;
            break;
          }
          if (!removeResources(inputs)) break;
          addResources(<String, int>{recipe.resultItem: recipe.resultAmount});
          _createCommunityProductionBatch(
            itemDefinitionId: recipe.resultItem,
            quantity: recipe.resultAmount,
            producerResidentId: resident.id,
            buildingId: assignment.buildingId,
            inputs: inputs,
            now: now,
          );
          assignment.dailyOutput += 1;
          produced += 1;
        }
        return produced > 0;
      case CommunityRoleType.fablabMaker:
        final recipe = craftConfig.recipes.firstWhere(
          (item) => item.id == 'filter',
          orElse: () => craftConfig.simpleMealRecipe,
        );
        final inputs = <String, int>{
          ...recipe.ingredients,
          ...recipe.contextIngredients
        };
        var produced = 0;
        for (var index = 0;
            index < units &&
                assignment.dailyOutput <
                    communityRolesConfig.craftingMaximumOutputPerDay;
            index++) {
          if (!hasResources(inputs) ||
              !hasInventoryCapacityFor(
                  <String, int>{recipe.resultItem: recipe.resultAmount})) {
            assignment.status = CommunityRoleStatus.awaitingResources;
            break;
          }
          if (!removeResources(inputs)) break;
          addResources(<String, int>{recipe.resultItem: recipe.resultAmount});
          _createCommunityProductionBatch(
            itemDefinitionId: recipe.resultItem,
            quantity: recipe.resultAmount,
            producerResidentId: resident.id,
            buildingId: assignment.buildingId,
            inputs: inputs,
            now: now,
          );
          assignment.dailyOutput += recipe.resultAmount;
          produced += recipe.resultAmount;
        }
        return produced > 0;
      case CommunityRoleType.marketCounter:
        return false;
      case CommunityRoleType.lisiereObserver:
        if (refugeSafety < communityRolesConfig.observationRequiresSecurity ||
            (activeGlobalWeatherEvent
                        ?.isBiomeAffected(ForageBiome.plaineRiche) ??
                    false) &&
                activeGlobalWeatherEvent?.type != TowerWeatherType.calm) {
          assignment.status = CommunityRoleStatus.paused;
          return false;
        }
        final organic = units * communityRolesConfig.observationOrganicPerCycle;
        final mineral = units * communityRolesConfig.observationMineralPerCycle;
        if (!hasInventoryCapacityFor(<String, int>{
          if (organic > 0) 'Organique': organic,
          if (mineral > 0) 'Minéral': mineral,
        })) {
          assignment.status = CommunityRoleStatus.awaitingResources;
          return false;
        }
        addResources(<String, int>{
          if (organic > 0) 'Organique': organic,
          if (mineral > 0) 'Minéral': mineral,
        });
        assignment.dailyOutput += organic + mineral;
        return organic + mineral > 0;
      case CommunityRoleType.securityWatch:
        final gain = units * communityRolesConfig.watchingSecurityPerInterval;
        final before = refugeSafety;
        refugeSafety =
            math.min(securityTowerConfig.maxSecurity, refugeSafety + gain);
        assignment.dailyOutput += refugeSafety - before;
        return refugeSafety != before;
      case CommunityRoleType.weatherWatch:
        assignment.dailyOutput += units;
        return true;
    }
  }

  CommunityCoverage get communityCoverage =>
      CommunityCoverageService.calculate(this);

  Iterable<ResidentEconomicTransaction> economicHistoryForResident(
          String residentId) =>
      residentEconomicTransactions.where((transaction) =>
          transaction.buyerResidentId == residentId ||
          transaction.sellerResidentId == residentId ||
          transaction.participantResidentIds.contains(residentId));

  String residentEconomicStateLabel(Zone0Resident resident) {
    if (resident.financialStrainScore >=
        residentEconomyConfig.financialStrainCriticalThreshold) {
      return 'Critique';
    }
    if (resident.financialStrainScore > 0) return 'En manque';
    if (resident.internalPileBalance <
        residentEconomyConfig.personalEmergencyReservePiles) {
      return 'Limité';
    }
    return 'Stable';
  }

  void _recordResidentEconomicTransaction(
      ResidentEconomicTransaction transaction) {
    if (transaction.idempotencyKey.isNotEmpty &&
        residentEconomicTransactions.any((existing) =>
            existing.idempotencyKey == transaction.idempotencyKey)) {
      return;
    }
    residentEconomicTransactions.add(transaction);
    final historyLimit =
        math.max(20, residentEconomyConfig.maxSettlementHistory * 8);
    if (residentEconomicTransactions.length > historyLimit) {
      residentEconomicTransactions.removeRange(
          0, residentEconomicTransactions.length - historyLimit);
    }
  }

  void _createCommunityProductionBatch({
    required String itemDefinitionId,
    required int quantity,
    required String? producerResidentId,
    required String buildingId,
    required Map<String, int> inputs,
    required DateTime now,
  }) {
    if (quantity <= 0) return;
    communityProductionBatches.add(CommunityProductionBatch(
      id: 'community-batch-${now.microsecondsSinceEpoch}-${communityProductionBatches.length}',
      itemDefinitionId: itemDefinitionId,
      outputQuantity: quantity,
      producerResidentId: producerResidentId,
      buildingId: buildingId,
      inputSnapshot: Map<String, int>.from(inputs),
      supplierContributions: inputs.entries
          .where((entry) => entry.value > 0)
          .map((entry) => SupplierContribution(
                id: 'player-input-${now.microsecondsSinceEpoch}-${entry.key}',
                sourceType: 'playerStock',
                itemDefinitionId: entry.key,
                quantity: entry.value,
                contributionWeight: entry.value,
                createdAt: now,
              ))
          .toList(),
      producedAt: now,
    ));
  }

  void _migrateResidentEconomy() {
    if (residentEconomyMigrationCompleted) return;
    for (final resident in residents) {
      // A pre-economy save has no balance field. Existing numeric balances are
      // preserved; only the legacy zero default receives the configurable
      // neutral starting balance.
      if (resident.internalPileBalance == 0) {
        resident.internalPileBalance =
            residentEconomyConfig.residentInitialPileBalance;
      }
    }
    for (final house in residentHouses) {
      if (house.householdPileBalance == 0) {
        house.householdPileBalance =
            residentEconomyConfig.householdInitialPileBalance;
      }
      house.lastHouseholdEnergyResolvedAt ??= house.lastEnergyDistributionAt;
    }
    residentEconomyMigrationCompleted = true;
  }

  ResidentUncoveredNeed _upsertResidentUncoveredNeed({
    required Zone0Resident resident,
    required String item,
    required String category,
    required int quantity,
    required ResidentUncoveredNeedReason reason,
    required int urgency,
    required DateTime now,
  }) {
    final key = '${resident.id}:$item';
    final existing = residentUncoveredNeeds
        .where((need) => need.id == key && need.resolvedAt == null)
        .firstOrNull;
    if (existing != null) {
      existing.reason = reason;
      return existing;
    }
    final need = ResidentUncoveredNeed(
      id: key,
      residentId: resident.id,
      itemDefinitionId: item,
      category: category,
      quantity: quantity,
      budgetPiles: resident.internalPileBalance,
      reason: reason,
      urgency: urgency,
      createdAt: now,
    );
    residentUncoveredNeeds.add(need);
    return need;
  }

  void _resolveResidentUncoveredNeed(
      String residentId, String item, DateTime now) {
    for (final need in residentUncoveredNeeds.where((need) =>
        need.residentId == residentId && need.itemDefinitionId == item)) {
      need.resolvedAt ??= now;
    }
  }

  /// Below 85% Viability, one active occupant is selected deterministically
  /// for the house's repair-kit request. The choice stays stable while the
  /// request is open, so reopening the app cannot cycle through residents or
  /// create duplicate Market cards.
  bool _resolveHouseholdRepairKitDemands(DateTime now) {
    const kit = 'Kit de réparation domestique';
    var changed = false;
    for (final house in residentHouses) {
      final occupants = residents
          .where(
              (resident) => resident.isActive && resident.houseId == house.id)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (occupants.isEmpty) continue;

      final activeNeeds = residentUncoveredNeeds
          .where((need) =>
              need.resolvedAt == null &&
              need.itemDefinitionId == kit &&
              occupants.any((resident) => resident.id == need.residentId))
          .toList();
      if (house.currentViability >= 85 ||
          (house.householdInventory[kit] ?? 0) > 0) {
        for (final need in activeNeeds) {
          _resolveResidentUncoveredNeed(need.residentId, kit, now);
          changed = true;
        }
        continue;
      }

      if (activeNeeds.isNotEmpty) continue;
      final seed = house.id.hashCode ^ _residentDayKey(now).hashCode;
      final requester = occupants[seed.abs() % occupants.length];
      _upsertResidentUncoveredNeed(
        resident: requester,
        item: kit,
        category: 'householdInstallation',
        quantity: 1,
        reason: ResidentUncoveredNeedReason.noStock,
        urgency: 3,
        now: now,
      );
      house
        ..lastAutonomyDecision =
            '${requester.displayName} recherche un Kit de réparation.'
        ..updatedAt = now;
      changed = true;
    }
    return changed;
  }

  bool _isFinishedResidentProduct(String item) =>
      _residentItemCategory(item) != null;

  int _residentUsableItemAmount(Zone0Resident resident, String item) =>
      resident.ownedItems
          .where((owned) => owned.itemDefinitionId == item && owned.isUsable)
          .fold<int>(0, (total, owned) => total + owned.quantity);

  String? _marketShopWithStock(String item, int quantity) {
    final shops = marketShops.where((shop) => !shop.legacyExtraSlot).toList()
      ..sort((a, b) {
        final residentFirst =
            (a.ownershipType == MarketShopOwnershipType.residentCommunity
                    ? 0
                    : 1)
                .compareTo(
                    b.ownershipType == MarketShopOwnershipType.residentCommunity
                        ? 0
                        : 1);
        return residentFirst != 0 ? residentFirst : a.id.compareTo(b.id);
      });
    for (final shop in shops) {
      if (shop.accepts(item) &&
          marketShopStockAmount(shop.id, item) >= quantity) {
        return shop.id;
      }
    }
    if (primaryMarketShopChosen &&
        marketShopAccepts(primaryMarketShopId, item) &&
        marketShopStockAmount(primaryMarketShopId, item) >= quantity) {
      return primaryMarketShopId;
    }
    return null;
  }

  Zone0ActionResult purchaseResidentFinishedItem({
    required String residentId,
    required String itemDefinitionId,
    int quantity = 1,
    bool essential = false,
    String? sourceNeedId,
  }) {
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    final safeQuantity = math.max(1, quantity);
    final current = DateTime.now();
    if (resident == null || !resident.isActive) {
      return const Zone0ActionResult(
          success: false, message: 'Habitant indisponible.');
    }
    if (!_isFinishedResidentProduct(itemDefinitionId)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Les habitants achètent uniquement des produits finis.');
    }
    final house = residentHouseForId(resident.houseId);
    final isHouseholdItem =
        house != null && _isHouseholdFinishedItem(itemDefinitionId);
    final category = _residentItemCategory(itemDefinitionId) ?? 'finished';
    if (!isHouseholdItem &&
        !_canResidentStoreOwnedItems(
            resident, itemDefinitionId, category, safeQuantity)) {
      _upsertResidentUncoveredNeed(
        resident: resident,
        item: itemDefinitionId,
        category: category,
        quantity: safeQuantity,
        reason: ResidentUncoveredNeedReason.noStock,
        urgency: essential ? 3 : 1,
        now: current,
      );
      return Zone0ActionResult(
        success: false,
        message:
            'Inventaire de ${resident.displayName} plein (${residentInventorySlotsFor(resident)} cases).',
      );
    }
    if (itemDefinitionId != 'Repas simple' &&
        (isHouseholdItem
            ? (house.householdInventory[itemDefinitionId] ?? 0) >= safeQuantity
            : _residentUsableItemAmount(resident, itemDefinitionId) >=
                safeQuantity)) {
      return const Zone0ActionResult(
          success: false, message: 'Produit déjà disponible.');
    }
    final price =
        residentEconomyConfig.priceFor(itemDefinitionId) * safeQuantity;
    final reserve =
        essential && residentEconomyConfig.essentialPurchaseMayUseReserve
            ? 0
            : residentEconomyConfig.personalEmergencyReservePiles;
    if (resident.internalPileBalance - price < reserve) {
      _upsertResidentUncoveredNeed(
        resident: resident,
        item: itemDefinitionId,
        category: _residentItemCategory(itemDefinitionId) ?? 'finished',
        quantity: safeQuantity,
        reason: ResidentUncoveredNeedReason.insufficientFunds,
        urgency: essential ? 3 : 1,
        now: current,
      );
      resident.financialStrainScore += essential ? 1 : 0;
      return const Zone0ActionResult(
          success: false, message: 'Solde personnel insuffisant.');
    }
    final batch = communityProductionBatches
        .where((item) =>
            item.itemDefinitionId == itemDefinitionId &&
            item.remainingQuantity >= safeQuantity &&
            item.isAvailable)
        .firstOrNull;
    final shopId = batch == null
        ? _marketShopWithStock(itemDefinitionId, safeQuantity)
        : null;
    if (batch == null && shopId == null) {
      _upsertResidentUncoveredNeed(
        resident: resident,
        item: itemDefinitionId,
        category: _residentItemCategory(itemDefinitionId) ?? 'finished',
        quantity: safeQuantity,
        reason: ResidentUncoveredNeedReason.noStock,
        urgency: essential ? 3 : 1,
        now: current,
      );
      return const Zone0ActionResult(
          success: false, message: 'Aucun produit fini disponible.');
    }
    // All checks happen before the physical stock move. The remaining state
    // changes are in-memory integer transitions and are committed together.
    final consumed = batch != null
        ? (resourceAmount(itemDefinitionId) >= safeQuantity &&
            removeResource(itemDefinitionId, safeQuantity) == safeQuantity)
        : _consumeMarketShopStock(shopId!, itemDefinitionId, safeQuantity);
    if (!consumed) {
      return const Zone0ActionResult(
          success: false, message: 'Le stock a changé, achat annulé.');
    }
    resident.internalPileBalance -= price;
    resident.recentSpendingPiles += price;
    if (house != null && isHouseholdItem) {
      _addHouseholdInventoryItem(house, itemDefinitionId, safeQuantity);
      if (itemDefinitionId == 'Kit de réparation domestique') {
        _applyPurchasedHouseholdRepairKit(
          house,
          current,
          requesterName: resident.displayName,
        );
      }
    } else {
      _addResidentOwnedItems(
        resident,
        itemDefinitionId,
        category,
        safeQuantity,
        current,
      );
    }
    // Les repas passent eux aussi par le sac personnel. La résolution des
    // besoins peut ensuite les consommer réellement, sans objet fantôme.
    resolveResidentNeeds(now: current);
    var producer = 0;
    var supplier = 0;
    var merchant = 0;
    var player = 0;
    String? seller;
    if (batch == null) {
      final shop = marketShopById(shopId ?? '');
      if (shop?.ownershipType == MarketShopOwnershipType.residentCommunity) {
        merchant = price;
        shop!.shopPileBalance += price;
        _creditResidentPiles(shop.ownerResidentId, price);
        seller = shop.ownerResidentId;
      } else {
        player = price;
        _creditMarketBioPiles(player);
      }
    } else {
      final parts = _splitResidentEconomicPayment(price, batch);
      producer = parts.producer;
      supplier = parts.supplier;
      merchant = parts.merchant;
      player = parts.player;
      seller = batch.producerResidentId;
      batch.remainingQuantity -= safeQuantity;
      batch.updatedAt = current;
      if (batch.remainingQuantity <= 0) {
        batch.status = ResidentEconomicTransactionStatus.archived;
      }
      _creditResidentPiles(batch.producerResidentId, producer);
      _creditSupplierContributions(batch.supplierContributions, supplier);
      final merchantResident = _activeMerchantResident();
      _creditResidentPiles(merchantResident?.id, merchant);
      if (player > 0) _creditMarketBioPiles(player);
    }
    final transaction = ResidentEconomicTransaction(
      id: 'resident-purchase-${resident.id}-${current.microsecondsSinceEpoch}',
      type: batch == null && merchant > 0
          ? ResidentEconomicTransactionType.residentSale
          : batch == null
              ? ResidentEconomicTransactionType.playerSaleToResident
              : ResidentEconomicTransactionType.residentPurchase,
      buyerResidentId: resident.id,
      sellerResidentId: seller,
      shopId: shopId,
      itemDefinitionId: itemDefinitionId,
      quantity: safeQuantity,
      grossAmountPiles: price,
      merchantSharePiles: merchant,
      producerSharePiles: producer,
      supplierSharePiles: supplier,
      playerSharePiles: player,
      sourceNeedId: sourceNeedId,
      sourceProductionId: batch?.id,
      status: ResidentEconomicTransactionStatus.completed,
      createdAt: current,
      completedAt: current,
      idempotencyKey:
          'purchase:${resident.id}:${itemDefinitionId}:${sourceNeedId ?? current.microsecondsSinceEpoch}',
    );
    _recordResidentEconomicTransaction(transaction);
    _resolveResidentUncoveredNeed(resident.id, itemDefinitionId, current);
    resident.financialStrainScore =
        math.max(0, resident.financialStrainScore - 1);
    resident.updatedAt = current;
    resolveResidentNeeds(now: current);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '${resident.displayName} achète $itemDefinitionId.');
  }

  _ResidentPaymentParts _splitResidentEconomicPayment(
      int total, CommunityProductionBatch batch) {
    var producer = total * residentEconomyConfig.producerSharePercent ~/ 100;
    var supplier = total * residentEconomyConfig.supplierSharePercent ~/ 100;
    var merchant = total * residentEconomyConfig.merchantSharePercent ~/ 100;
    var player = 0;
    if (batch.producerResidentId == null) {
      player += producer;
      producer = 0;
    }
    if (batch.supplierContributions.isEmpty) {
      player += supplier;
      supplier = 0;
    }
    if (_activeMerchantResident() == null) {
      if (residentEconomyConfig.absentMerchantShareRecipient == 'player') {
        player += merchant;
      } else if (batch.producerResidentId != null) {
        producer += merchant;
      } else {
        player += merchant;
      }
      merchant = 0;
    }
    final assigned = producer + supplier + merchant + player;
    final remainder = math.max(0, total - assigned);
    if (merchant > 0) {
      merchant += remainder;
    } else if (batch.producerResidentId != null) {
      producer += remainder;
    } else {
      player += remainder;
    }
    return _ResidentPaymentParts(producer, supplier, merchant, player);
  }

  Zone0Resident? _activeMerchantResident() {
    final ownerId = marketShops
        .where((shop) =>
            shop.ownershipType == MarketShopOwnershipType.residentCommunity &&
            shop.ownerResidentId != null)
        .map((shop) => shop.ownerResidentId!)
        .toList()
      ..sort();
    if (ownerId.isNotEmpty) {
      return residents
          .where((resident) => resident.id == ownerId.first)
          .firstOrNull;
    }
    final role = activeCommunityRoles
        .where((assignment) =>
            assignment.roleType == CommunityRoleType.marketCounter)
        .firstOrNull;
    return role == null
        ? null
        : residents
            .where((resident) => resident.id == role.residentId)
            .firstOrNull;
  }

  void _creditResidentPiles(String? residentId, int amount) {
    if (residentId == null || amount <= 0) return;
    final resident =
        residents.where((item) => item.id == residentId).firstOrNull;
    if (resident == null) return;
    resident.internalPileBalance = math.min(
        residentEconomyConfig.personalAccountCapPiles,
        resident.internalPileBalance + amount);
  }

  void _creditSupplierContributions(
      List<SupplierContribution> contributions, int amount) {
    if (amount <= 0) return;
    final totalWeight = contributions.fold<int>(
        0,
        (total, contribution) =>
            total + math.max(0, contribution.contributionWeight));
    if (totalWeight <= 0) {
      _creditMarketBioPiles(amount);
      return;
    }
    var paid = 0;
    for (final contribution in contributions) {
      final share =
          amount * math.max(0, contribution.contributionWeight) ~/ totalWeight;
      paid += share;
      if (contribution.residentId == null) {
        _creditMarketBioPiles(share);
      } else {
        _creditResidentPiles(contribution.residentId, share);
      }
    }
    if (paid < amount) _creditMarketBioPiles(amount - paid);
  }

  bool resolveResidentEconomy({DateTime? now}) {
    if (!residentEconomyConfig.enabled) return false;
    final current = now ?? DateTime.now();
    _migrateResidentEconomy();
    var changed = resolveResidentDomesticGeneration(now: current);
    changed = _resolveHouseholdRepairKitDemands(current) || changed;
    residentUncoveredNeeds.removeWhere((need) =>
        need.resolvedAt != null &&
        current.difference(need.resolvedAt!).inDays > 2);
    for (final resident in residents.where((item) => item.isActive)) {
      if (resident.needsState.mealsMissing > 0) {
        final result = purchaseResidentFinishedItem(
          residentId: resident.id,
          itemDefinitionId: 'Repas simple',
          quantity: 1,
          essential: true,
          sourceNeedId: 'meal:${resident.id}:${_residentDayKey(current)}',
        );
        changed = result.success || changed;
        if (!result.success) {
          _upsertResidentUncoveredNeed(
            resident: resident,
            item: 'Repas simple',
            category: 'meal',
            quantity: resident.needsState.mealsMissing,
            reason: result.message.contains('Solde')
                ? ResidentUncoveredNeedReason.insufficientFunds
                : ResidentUncoveredNeedReason.noStock,
            urgency: 3,
            now: current,
          );
        }
      }
    }
    _createEconomicSettlementBatch(current);
    lastResidentEconomyResolvedAt = current;
    return changed;
  }

  void _createEconomicSettlementBatch(DateTime current) {
    final dayKey = _residentDayKey(current);
    if (lastEconomicSettlementDayKey == dayKey) return;
    final dayTransactions = residentEconomicTransactions
        .where((item) =>
            _residentDayKey(item.createdAt) == dayKey &&
            item.status == ResidentEconomicTransactionStatus.completed &&
            item.settlementBatchId == null)
        .toList();
    if (dayTransactions.isEmpty) return;
    final batch = EconomicSettlementBatch(
      id: 'settlement-$dayKey',
      periodStart: DateTime(current.year, current.month, current.day),
      periodEnd: current,
      transactionIds: dayTransactions.map((item) => item.id).toList(),
      totalGrossPiles:
          dayTransactions.fold(0, (sum, item) => sum + item.grossAmountPiles),
      totalMerchantPiles:
          dayTransactions.fold(0, (sum, item) => sum + item.merchantSharePiles),
      totalProducerPiles:
          dayTransactions.fold(0, (sum, item) => sum + item.producerSharePiles),
      totalSupplierPiles:
          dayTransactions.fold(0, (sum, item) => sum + item.supplierSharePiles),
      totalPlayerPiles:
          dayTransactions.fold(0, (sum, item) => sum + item.playerSharePiles),
      createdAt: current,
      completedAt: current,
      idempotencyKey: 'settlement:$dayKey',
    );
    if (economicSettlementBatches
        .any((item) => item.idempotencyKey == batch.idempotencyKey)) {
      return;
    }
    economicSettlementBatches.add(batch);
    for (final transaction in dayTransactions) {
      transaction.settlementBatchId = batch.id;
    }
    lastEconomicSettlementDayKey = dayKey;
    if (economicSettlementBatches.length >
        residentEconomyConfig.maxSettlementHistory) {
      economicSettlementBatches.removeRange(
          0,
          economicSettlementBatches.length -
              residentEconomyConfig.maxSettlementHistory);
    }
  }

  /// A small, displayable forecast-quality support from residents assigned to
  /// the Tower. It never changes the global two-hour weather announcement.
  int get communityWeatherForecastSupport => activeCommunityRoles
      .where(
          (assignment) => assignment.roleType == CommunityRoleType.weatherWatch)
      .fold<int>(0, (sum, assignment) => sum + assignment.dailyOutput);

  bool canResidentRequestCertifiedPtibug(Zone0Resident resident) {
    if (_residentPassionFor(resident) != ResidentPassion.livingObservation ||
        resident.ownedCertifiedPtibugIds.length >=
            communityRolesConfig.residentPtibugMaximum) {
      return false;
    }
    return resident.dailyNeedsState['activePtibugRequestId'] == null;
  }

  ResidentHouse? residentHouseForId(String? houseId) => houseId == null
      ? null
      : residentHouses.where((house) => house.id == houseId).firstOrNull;

  int residentHappinessFor(Zone0Resident resident) {
    final house = residentHouseForId(resident.houseId);
    final finalValue = ResidentHappinessService.calculate(
      resident: resident,
      house: house,
    );
    resident.currentHappiness = finalValue;
    return finalValue;
  }

  Map<String, int> residentHappinessBreakdown(Zone0Resident resident) =>
      ResidentHappinessService.breakdown(
        resident: resident,
        house: residentHouseForId(resident.houseId),
      );

  int get displayedCampWellbeing => (residentHappiness +
          securityWellbeingModifier +
          communityThanksWellbeingBonus)
      .clamp(0, 100);

  int get protectedBatteryChestCapacity =>
      campHeartConfig.communityProjects.protectedBatteryCapacity +
      protectedBatteryChestLevel *
          campHeartConfig.communityProjects.protectedBatteryCapacityPerUpgrade;

  int? get protectedBatteryChestNextUpgradeCost {
    final config = campHeartConfig.communityProjects;
    if (protectedBatteryChestLevel >= config.protectedBatteryUpgradeMaxLevel) {
      return null;
    }
    final costs = config.protectedBatteryUpgradeMineralCosts;
    return costs.isEmpty
        ? 30
        : costs[math.min(protectedBatteryChestLevel, costs.length - 1)];
  }

  Zone0ActionResult upgradeProtectedBatteryChest() {
    final cost = protectedBatteryChestNextUpgradeCost;
    if (cost == null) {
      return const Zone0ActionResult(
          success: false, message: 'Coffre au niveau maximal.');
    }
    if (resourceAmount('Minéral') < cost ||
        removeResource('Minéral', cost) <= 0) {
      return Zone0ActionResult(
          success: false, message: '$cost Minéral requis.');
    }
    protectedBatteryChestLevel += 1;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Coffre amélioré : $protectedBatteryChestCapacity Bio-batteries protégées.');
  }

  int get protectedBioBatteryCount => math
      .min(
        bioBatteries,
        protectedBatteryChestCapacity,
      )
      .toInt();
  int get exposedBioBatteryCount =>
      math.max(0, bioBatteries - protectedBioBatteryCount).toInt();

  static const int energyCoreCapacity = 300;
  static const int maximumBioBatteryStorage = 999;

  /// Every chest level from level 2 onward holds one sealed Energy Core.
  int get energyCoreStorageSlots => math.max(0, protectedBatteryChestLevel - 1);

  int get availableEnergyCoreStorageSlots =>
      math.max(0, energyCoreStorageSlots - storedEnergyCores);

  void _resolveEnergyCoreMilestones() {
    if (bioBatteries >= 600 && !energyCorePatternDiscovered) {
      energyCorePatternDiscovered = true;
      discoveredKernelPlanIds.add('energy-core');
      reports.add(PtipoteMissionReport.system(
        message:
            'La masse d’énergie accumulée révèle le Pattern Cœur d’énergie. Investis 20 Données Énergie, 20 Organiques, 10 Minérales, 15 Mycéliennes et 15 Biomimétisme.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Nouveau Pattern énergétique',
        concerned: 'Joueur',
        summary: 'Le Cœur d’énergie est disponible dans les Plans du Kernel.',
      ));
    }
    if (bioBatteries >= 600 && !energyCoreWarning600Shown) {
      energyCoreWarning600Shown = true;
    }
    if (bioBatteries >= 699 && !energyCoreWarning699Shown) {
      energyCoreWarning699Shown = true;
    }
  }

  /// Le Cœur d'énergie est la seule découverte pilotée par un stock : il ne
  /// doit pas être révélé par la progression générale du Kernel. Les parties
  /// ayant reçu le Plan trop tôt le perdent tant que le seuil de 600 n'est pas
  /// atteint ; les Données investies sont restituées une fois.
  bool _migratePrematureEnergyCorePattern() {
    if (bioBatteries >= 600) return false;
    final wasPresent = energyCorePatternDiscovered ||
        discoveredKernelPlanIds.contains('energy-core') ||
        readyKernelPlanIds.contains('energy-core') ||
        activeKernelPlanIds.contains('energy-core');
    if (!wasPresent) return false;
    final investments = kernelPlanDataInvestments.remove('energy-core');
    if (investments != null) {
      for (final entry in investments.entries) {
        pTibugDataReserve[entry.key] =
            (pTibugDataReserve[entry.key] ?? 0) + entry.value;
      }
    }
    energyCorePatternDiscovered = false;
    discoveredKernelPlanIds.remove('energy-core');
    readyKernelPlanIds.remove('energy-core');
    activeKernelPlanIds.remove('energy-core');
    return true;
  }

  Zone0ActionResult storeEnergyCore() {
    if (availableEnergyCoreStorageSlots <= 0 ||
        resourceAmount('Cœur d’énergie') <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun emplacement de coffre libre ou aucun Cœur disponible.',
      );
    }
    if (removeResource('Cœur d’énergie', 1) <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Cœur indisponible.');
    }
    storedEnergyCores += 1;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Cœur d’énergie rangé dans le coffre.');
  }

  Zone0ActionResult unsealStoredEnergyCore() {
    if (storedEnergyCores <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun Cœur scellé dans le coffre.');
    }
    if (bioBatteries + energyCoreCapacity > maximumBioBatteryStorage) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Stock insuffisant : ouvre ce Cœur à 699 Bio-batteries ou moins.',
      );
    }
    storedEnergyCores -= 1;
    bioBatteries += energyCoreCapacity;
    _resolveEnergyCoreMilestones();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Cœur descellé : +300 Bio-batteries.');
  }

  int get communityProjectChoiceLimit => (_lastKnownCampHeartLevel *
          campHeartConfig.communityProjects.choicesPerCoreLevel)
      .toInt();
  int get communityProjectChoicesUsed => communityProjects.length;
  CommunityProjectProgress? get activeCommunityProject =>
      communityProjects.values
          .where((project) => project.status == CommunityProjectStatus.active)
          .firstOrNull;

  int globalWeatherProtectionPercent(TowerWeatherType weather) =>
      communityProjects.values
          .where(
              (project) => project.status == CommunityProjectStatus.completed)
          .map((project) => project.definition.weatherType == weather.name
              ? project.definition.globalProtectionPercent
              : 0)
          .fold<int>(0, (total, value) => total + value);

  int get housingWellbeingPenalty => math.min(
        housingConfig.maximumHousingWellbeingPenalty,
        unhousedPopulation * housingConfig.wellbeingPenaltyPerUnhousedResident,
      );

  int get communityThanksWellbeingBonus {
    final thanks = communityConstructionThanks;
    if (thanks == null || !thanks.isActive) return 0;
    return thanks.bonusValue;
  }

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

  bool get hasPendingMerchantCall =>
      merchantCallRequestedAt != null &&
      merchantNextArrivalAt != null &&
      !isMerchantAvailable &&
      DateTime.now().isBefore(merchantNextArrivalAt!);

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

  int get activeManualWorkshopOrders =>
      activeWorkshopOrders
          .where(
            (order) =>
                order.area == WorkshopOrderArea.workshop &&
                order.assignedPtipoteId == null,
          )
          .length +
      activePTibugModuleCraftOrders
          .where((order) => order.assignedPtipoteId == null)
          .length +
      pTibugArmatures
          .where((order) => order.isCrafting && order.assignedPtipoteId == null)
          .length;

  int get activePtipoteWorkshopOrders =>
      activeWorkshopOrders
          .where(
            (order) =>
                order.area == WorkshopOrderArea.workshop &&
                order.assignedPtipoteId != null,
          )
          .length +
      activePTibugModuleCraftOrders
          .where((order) => order.assignedPtipoteId != null)
          .length +
      pTibugArmatures
          .where((order) => order.isCrafting && order.assignedPtipoteId != null)
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

  bool isAssignedToWorkshop(String figurineId) =>
      activeWorkshopOrders.any(
        (order) => order.assignedPtipoteId == figurineId,
      ) ||
      activePTibugModuleCraftOrders.any(
        (order) => order.assignedPtipoteId == figurineId,
      ) ||
      pTibugArmatures.any(
        (order) => order.isCrafting && order.assignedPtipoteId == figurineId,
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

  /// Le stock n'augmente plus avec le niveau global du Marché : la boutique
  /// principale commence avec trois piles et s'améliore séparément plus tard.
  int get marketSlotLimit => 3;

  /// La boutique principale est conservée sur les champs historiques afin de
  /// migrer les sauvegardes sans perdre son stock ni son Distributeur.
  int get marketShopLimit => marketConfig.shopSlotsForMarketLevel(marketLevel);
  int get marketShopCount =>
      (primaryMarketShopChosen ? 1 : 0) +
      marketShops
          .where((shop) => !shop.isPrimary && !shop.legacyExtraSlot)
          .length;

  bool get isMarketRequestBookUnlocked =>
      marketLevel >= marketConfig.requestBookLevel;
  bool get isMarketInformationPointUnlocked =>
      marketLevel >= marketConfig.informationPointLevel;

  List<MarketShopSlot> get unlockedMarketShopSlots => marketShopSlots
      .where((slot) => slot.marketLevelRequired <= marketLevel)
      .toList()
    ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

  MarketShopSlot? _vacantMarketShopSlot() => unlockedMarketShopSlots
      .where((slot) => slot.status == MarketShopSlotStatus.vacant)
      .firstOrNull;

  /// Pendant le préavis, une construction réelle du joueur est prioritaire :
  /// elle réserve le slot et annule proprement la revendication annoncée.
  MarketShopSlot? _playerBuildMarketShopSlot() => unlockedMarketShopSlots
      .where((slot) =>
          slot.status == MarketShopSlotStatus.vacant ||
          slot.status == MarketShopSlotStatus.pendingResidentClaim ||
          slot.status == MarketShopSlotStatus.reserved)
      .firstOrNull;

  int _marketSlotLevelRequirement(int index) {
    for (var level = 1; level <= marketConfig.maximumLevel; level++) {
      if (index < marketConfig.shopSlotsForMarketLevel(level)) return level;
    }
    return marketConfig.maximumLevel;
  }

  void _migrateMarketShopSlots(DateTime now) {
    final required = marketConfig.shopSlotsForMarketLevel(marketLevel);
    for (var index = 0; index < required; index++) {
      final id = 'market-shop-slot-${index + 1}';
      final existing =
          marketShopSlots.where((slot) => slot.slotId == id).firstOrNull;
      if (existing == null) {
        marketShopSlots.add(MarketShopSlot(
          slotId: id,
          slotIndex: index,
          marketLevelRequired: _marketSlotLevelRequirement(index),
          status: MarketShopSlotStatus.vacant,
          vacantSince: now,
        ));
      }
    }
    final orderedShops = <MarketShop>[
      if (primaryMarketShopChosen)
        MarketShop(
          id: primaryMarketShopId,
          specialization: primaryMarketShopSpecialization,
          level: primaryMarketShopLevel,
          isPrimary: true,
        ),
      ...marketShops.where((shop) => !shop.isPrimary),
    ];
    // Une ancienne migration recréait la boutique principale comme candidat
    // pour chaque slot vide. Elle pouvait donc réserver les quatre places
    // avec le même id `market-main`, alors que le compteur restait à 1/4.
    // La boutique principale ne conserve que son premier slot réel.
    final primarySlots = marketShopSlots
        .where((slot) => slot.shopId == primaryMarketShopId)
        .toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    if (primaryMarketShopChosen && primarySlots.isNotEmpty) {
      orderedShops.firstWhere((shop) => shop.id == primaryMarketShopId).slotId =
          primarySlots.first.slotId;
      for (final duplicate in primarySlots.skip(1)) {
        duplicate
          ..shopId = null
          ..status = MarketShopSlotStatus.vacant
          ..vacantSince = now;
      }
    }
    final hasPlayerConstructionReservation =
        marketShopConstructionOrder != null &&
            !marketShopConstructionOrder!.isPrimary &&
            marketShopConstructionOrder!.targetShopId == null;
    for (final slot in marketShopSlots) {
      if (slot.marketLevelRequired > marketLevel) {
        if (slot.status != MarketShopSlotStatus.playerOccupied &&
            slot.status != MarketShopSlotStatus.residentOccupied) {
          slot.status = MarketShopSlotStatus.locked;
        }
        continue;
      }
      final shop = orderedShops
          .where((entry) => entry.slotId == slot.slotId)
          .firstOrNull;
      if (slot.shopId == primaryMarketShopId && primaryMarketShopChosen) {
        orderedShops
            .firstWhere((shop) => shop.id == primaryMarketShopId)
            .slotId = slot.slotId;
        slot
          ..status = MarketShopSlotStatus.playerOccupied
          ..vacantSince = null;
        continue;
      }
      if (shop != null) {
        slot
          ..shopId = shop.id
          ..status =
              shop.ownershipType == MarketShopOwnershipType.residentCommunity
                  ? MarketShopSlotStatus.residentOccupied
                  : MarketShopSlotStatus.playerOccupied
          ..vacantSince = null;
        continue;
      }
      if (slot.shopId == null) {
        final candidate = orderedShops
            .where((entry) => entry.slotId == null && !entry.legacyExtraSlot)
            .firstOrNull;
        if (candidate != null) {
          candidate.slotId = slot.slotId;
          slot
            ..shopId = candidate.id
            ..status = candidate.ownershipType ==
                    MarketShopOwnershipType.residentCommunity
                ? MarketShopSlotStatus.residentOccupied
                : MarketShopSlotStatus.playerOccupied
            ..vacantSince = null;
          continue;
        }
      }
      // Les anciennes versions pouvaient laisser un slot « réservé » après
      // fermeture du panneau de construction. Sans chantier joueur actif,
      // cette réservation est un reliquat et doit redevenir disponible.
      if (slot.status == MarketShopSlotStatus.reserved &&
          !hasPlayerConstructionReservation) {
        slot
          ..status = MarketShopSlotStatus.vacant
          ..reservedByResidentId = null
          ..vacantSince = now;
        continue;
      }
      if (slot.status != MarketShopSlotStatus.pendingResidentClaim &&
          slot.status != MarketShopSlotStatus.reserved) {
        slot
          ..shopId = null
          ..status = MarketShopSlotStatus.vacant
          ..vacantSince ??= now;
      }
    }
    final slottedIds =
        marketShopSlots.map((slot) => slot.shopId).whereType<String>().toSet();
    for (final shop in marketShops) {
      if (!shop.isPrimary && !slottedIds.contains(shop.id))
        shop.legacyExtraSlot = true;
    }
    marketShopSlotsMigrationCompleted = true;
  }

  MarketShop? marketShopById(String id) =>
      marketShops.where((shop) => shop.id == id).firstOrNull;

  int marketShopStockLimit(String shopId) => shopId == primaryMarketShopId
      ? (primaryMarketShopLevel >= 2 ? 6 : 3)
      : marketShopById(shopId)?.stockSlots ?? 0;

  List<Zone0InventoryStack>? marketStockForShop(String shopId) =>
      shopId == primaryMarketShopId
          ? marketStock
          : marketShopById(shopId)?.stock;

  /// Le premier distributeur historique appartient désormais à la boutique
  /// principale. Les boutiques ajoutées enregistrent leur propre machine.
  MarketDistributorState? marketDistributorForShop(String shopId) =>
      shopId == primaryMarketShopId
          ? marketDistributor
          : marketShopById(shopId)?.distributor;

  MarketDistributorState _ensureMarketDistributorForShop(String shopId) {
    if (shopId == primaryMarketShopId) return marketDistributor;
    final shop = marketShopById(shopId);
    if (shop == null) throw StateError('Boutique introuvable.');
    return shop.distributor ??= MarketDistributorState()
      ..type = switch (shop.specialization) {
        'restaurant' => MarketDistributorType.food,
        'wholesale' => MarketDistributorType.resources,
        // Le type est un libellé historique ; l'acceptation utilise toujours
        // la spécialisation réelle de la boutique ci-dessous.
        _ => MarketDistributorType.general,
      };
  }

  /// Prépare l'état de construction sans fabriquer le distributeur. Cette
  /// étape permet d'afficher les dépôts progressifs de chaque magasin.
  MarketDistributorState prepareMarketDistributorForShop(String shopId) =>
      _ensureMarketDistributorForShop(shopId);

  bool marketShopAccepts(String shopId, String resource) =>
      shopId == primaryMarketShopId
          ? MarketShop(
                  id: primaryMarketShopId,
                  specialization: primaryMarketShopSpecialization,
                  level: primaryMarketShopLevel)
              .accepts(resource)
          : (marketShopById(shopId)?.accepts(resource) ?? false);

  PTibugSpecies? _marketPTibugSpecies(String resource) => switch (resource) {
        'P’TIBUG Scarabé' => PTibugSpecies.scarabe,
        'P’TIBUG Hyme' => PTibugSpecies.hyme,
        'P’TIBUG Arac' => PTibugSpecies.arac,
        'Capsule P’TIBUG Scarabé' => PTibugSpecies.scarabe,
        'Capsule P’TIBUG Hyme' => PTibugSpecies.hyme,
        'Capsule P’TIBUG Arac' => PTibugSpecies.arac,
        _ => null,
      };

  PTibugSpecies? _marketMatrixSpecies(String resource) => switch (resource) {
        'Matrice Scarabé' => PTibugSpecies.scarabe,
        'Matrice Hyme' => PTibugSpecies.hyme,
        // Une version accentuée a existé dans certaines sauvegardes/tests.
        // Elle doit continuer à pointer vers le Magasin P’TIBUG, sans créer
        // une seconde catégorie de Matrice.
        'Matrice Hymé' => PTibugSpecies.hyme,
        'Matrice Arac' => PTibugSpecies.arac,
        _ => null,
      };

  bool _isMarketMatrixResource(String resource) =>
      resource == 'Matrice P’TIBUG' || _marketMatrixSpecies(resource) != null;

  String marketMatrixItemForSpecies(PTibugSpecies species) =>
      'Matrice ${pTibugConfig.species[species]!.displayName}';

  Set<String> get _nurseryMarketReservedIds => <String>{
        for (final stack in <Zone0InventoryStack>[
          ...marketStock,
          for (final shop in marketShops) ...shop.stock,
          for (final shop in marketShops) ...?shop.distributor?.stock,
          ...marketDistributor.stock,
        ])
          ...stack.sourceItemIds,
      };

  List<String> _availableNurseryMarketItemIds(String resource) {
    final reserved = _nurseryMarketReservedIds;
    final capsuleSpecies = resource.startsWith('Capsule P’TIBUG ')
        ? _marketPTibugSpecies(resource)
        : null;
    if (capsuleSpecies != null) {
      return pTibugCapsules
          .where((capsule) =>
              capsule.status == CertifiedPTibugCapsuleStatus.certified &&
              capsule.species == capsuleSpecies &&
              !reserved.contains(capsule.id))
          .map((capsule) => capsule.id)
          .toList();
    }
    if (_isMarketMatrixResource(resource)) {
      final species = _marketMatrixSpecies(resource);
      return pTibugAspectMatrices
          .where((matrix) =>
              (species == null || matrix.species == species) &&
              !reserved.contains(matrix.id))
          .map((matrix) => matrix.id)
          .toList();
    }
    return const <String>[];
  }

  int nurseryMarketInventoryAmount(String resource) =>
      _availableNurseryMarketItemIds(resource).length;

  /// Les Capsules et Matrices restent des objets identifiés même une fois
  /// déposés dans une pile du Marché. Cette étiquette évite de vendre une
  /// Capsule anonyme dans l'interface de stock.
  String marketInventoryDisplayLabel(Zone0InventoryStack stack) {
    if (stack.sourceItemIds.isEmpty) return stack.resource;
    final labels = <String>[];
    for (final sourceId in stack.sourceItemIds) {
      final capsule =
          pTibugCapsules.where((item) => item.id == sourceId).firstOrNull;
      if (capsule != null) {
        labels.add(capsule.displayName);
        continue;
      }
      final matrix =
          pTibugAspectMatrices.where((item) => item.id == sourceId).firstOrNull;
      if (matrix != null) labels.add(matrix.sourceDisplayName);
    }
    if (labels.isEmpty) return stack.resource;
    if (labels.length == 1) return '${stack.resource} · ${labels.first}';
    return '${stack.resource} · ${labels.first} +${labels.length - 1}';
  }

  List<PTibugCapsule> get nurseryInventoryCapsules {
    final reserved = _nurseryMarketReservedIds;
    return pTibugCapsules
        .where((capsule) =>
            capsule.status == CertifiedPTibugCapsuleStatus.certified &&
            !reserved.contains(capsule.id))
        .toList(growable: false);
  }

  List<PTibugAspectMatrix> get nurseryInventoryMatrices {
    final reserved = _nurseryMarketReservedIds;
    return pTibugAspectMatrices
        .where((matrix) => !reserved.contains(matrix.id))
        .toList(growable: false);
  }

  /// A matrix keeps the identity and the visual data of its source P'TIBUG.
  /// The market therefore exposes it as an individual object rather than as
  /// an anonymous species stack.
  List<PTibugAspectMatrix> nurseryMarketMatricesForShop(String shopId) =>
      nurseryInventoryMatrices
          .where(
            (matrix) => marketShopAccepts(
              shopId,
              marketMatrixItemForSpecies(matrix.species),
            ),
          )
          .toList(growable: false);

  List<String> marketTransferableItemsForShop(String shopId) {
    final resources = <String>{
      ...marketConfig.saleValues.keys.where((resource) =>
          !_isMarketMatrixResource(resource) &&
          resourceAmount(resource) > 0 &&
          marketShopAccepts(shopId, resource)),
    };
    return resources.toList()..sort();
  }

  /// Capsules are never merged in the Market picker: each certified P'TIBUG
  /// keeps its own name, level and visual identity before it is deposited.
  List<PTibugCapsule> nurseryMarketCapsulesForShop(String shopId) {
    final reserved = _nurseryMarketReservedIds;
    return pTibugCapsules
        .where((capsule) =>
            capsule.status == CertifiedPTibugCapsuleStatus.certified &&
            !reserved.contains(capsule.id) &&
            marketShopAccepts(
              shopId,
              marketItemForCertifiedCapsule(capsule.species),
            ))
        .toList(growable: false);
  }

  String marketItemForCertifiedCapsule(PTibugSpecies species) =>
      'Capsule P’TIBUG ${switch (species) {
        PTibugSpecies.scarabe => 'Scarabé',
        PTibugSpecies.hyme => 'Hyme',
        PTibugSpecies.arac => 'Arac'
      }}';

  bool _isBasicMarketPTibug(PTibug bug) =>
      bug.biologicalTraitId == null &&
      bug.secondTraitId == null &&
      bug.traitDataId == null &&
      !bug.isRenewed &&
      bug.equippedModules.isEmpty &&
      bug.equippedModuleInstanceIds.isEmpty;

  int _marketPTibugAmount(String resource) {
    final species = _marketPTibugSpecies(resource);
    if (species == null) return 0;
    if (resource.startsWith('Capsule ')) {
      return pTibugCapsules
          .where((capsule) =>
              capsule.species == species &&
              capsule.status == CertifiedPTibugCapsuleStatus.certified)
          .length;
    }
    final raw = pTibugs
        .where((bug) => bug.species == species && _isBasicMarketPTibug(bug))
        .length;
    final capsules = pTibugCapsules
        .where((capsule) =>
            capsule.species == species &&
            capsule.status == CertifiedPTibugCapsuleStatus.certified)
        .length;
    return raw + capsules;
  }

  bool _consumeMarketPTibugs(String resource, int amount) {
    final species = _marketPTibugSpecies(resource);
    if (species == null) return false;
    if (resource.startsWith('Capsule ')) {
      final capsules = pTibugCapsules
          .where((capsule) =>
              capsule.species == species &&
              capsule.status == CertifiedPTibugCapsuleStatus.certified)
          .take(amount)
          .toList();
      if (capsules.length < amount) return false;
      pTibugCapsules.removeWhere(capsules.contains);
      return true;
    }
    final candidates = pTibugs
        .where((bug) => bug.species == species && _isBasicMarketPTibug(bug))
        .take(amount)
        .toList(growable: false);
    final missing = amount - candidates.length;
    final capsules = missing <= 0
        ? <PTibugCapsule>[]
        : pTibugCapsules
            .where((capsule) =>
                capsule.species == species &&
                capsule.status == CertifiedPTibugCapsuleStatus.certified)
            .take(missing)
            .toList();
    if (candidates.length + capsules.length < amount) return false;
    final now = DateTime.now();
    for (final bug in candidates) {
      final valuation = pTibugValuationFor(bug);
      bug
        ..lifecycleStatus = PTibugLifecycleStatus.sold
        ..updatedAt = now;
      pTibugCapsules.add(PTibugCapsule(
        id: 'certified-ptibug-${now.microsecondsSinceEpoch}-${bug.id}',
        sourcePtibugId: bug.id,
        species: bug.species,
        styleVariant: bug.styleVariant,
        displayName: bug.displayName,
        level: bug.level,
        xp: bug.xp,
        baseValueSnapshot: valuation.baseValue,
        levelValueSnapshot: valuation.levelValue,
        traitValueSnapshot: valuation.traitValue,
        moduleValueSnapshot: valuation.moduleValue,
        estimatedValueSnapshot: valuation.total,
        valuationConfigVersion: valuation.configVersion,
        certificationId: 'cert-${bug.id}-${now.microsecondsSinceEpoch}',
        status: CertifiedPTibugCapsuleStatus.sold,
        soldAt: now,
        createdAt: now,
      ));
      soldPTibugArchive.add(bug);
    }
    pTibugs.removeWhere(candidates.contains);
    if (capsules.isNotEmpty) pTibugCapsules.removeWhere(capsules.contains);
    return true;
  }

  int get marketDistributorSlotLimit => marketDistributor.isBuilt
      ? marketConfig.distributorSlotsForLevel(marketDistributor.level)
      : 0;

  double get sourcierConfidencePaymentMultiplier =>
      1 +
      (sourcierConfidence.clamp(0, 100) / 100) *
          (marketConfig.confidenceMaxPaymentBonusPercent / 100);

  bool isEquipmentResource(String resource) {
    return craftConfig.recipes.any(
      (recipe) => recipe.resultItem == resource && recipe.isEquipment,
    );
  }

  int marketStackLimitFor(String resource) =>
      isEquipmentResource(resource) ? 1 : marketConfig.stackQuantityLimit;

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

  /// The Bio-générateur now belongs to the player's House. Its legacy
  /// production curve still follows the already unlocked Camp Heart tier.
  int get generatorDisplayLevel => math.max(1, _lastKnownCampHeartLevel);

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
    if (!isBuildingOperational('house')) {
      generatorCycleStartedAt = null;
      return false;
    }
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
    final produced = math.max(
      0,
      (possibleCycles *
              campGeneratorConfig.bioBatteriesPerCycle *
              buildingProductionMultiplier('house'))
          .floor(),
    );
    bioBatteries += produced;
    _resolveEnergyCoreMilestones();
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
    return persistentMissions.toList(growable: false);
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

  KernelMissionConfig? _kernelMissionById(String missionId) {
    final staticMission = kernelConfig.missions
        .where((mission) => mission.id == missionId)
        .firstOrNull;
    return staticMission;
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

  /// 0: hidden, 1: icon only, 2: name and requirements, 3: discovered.
  int kernelPlanVisibility(KernelTechnologyPlanConfig plan) {
    if (kernelPlanState(plan) != KernelPlanState.unknown) return 3;
    final deficits = <int>[
      plan.requiredTrustLevel - kernelTrustLevel,
      if (plan.requiredAxis != null)
        plan.requiredAxisLevel - kernelAxisLevel(plan.requiredAxis!),
      plan.requiredBreederLevel - kernelAxisLevel(KernelAxis.breeder),
      plan.requiredBuilderLevel - kernelAxisLevel(KernelAxis.builder),
      plan.requiredRestorerLevel - kernelAxisLevel(KernelAxis.restorer),
    ];
    final largestDeficit = deficits.reduce(math.max);
    if (largestDeficit > 2) return 0;
    if (largestDeficit > 1) return 1;
    return 2;
  }

  PTibugDataFamily? _dataFamilyForName(String name) => PTibugDataFamily.values
      .where((family) => family.name == name)
      .firstOrNull;

  Map<PTibugDataFamily, int> kernelPlanMissingData(
    KernelTechnologyPlanConfig plan,
  ) {
    final invested =
        kernelPlanDataInvestments[plan.id] ?? const <PTibugDataFamily, int>{};
    return <PTibugDataFamily, int>{
      for (final entry in plan.dataRequirements.entries)
        if (_dataFamilyForName(entry.key) case final family?)
          family: math.max(0, entry.value - (invested[family] ?? 0)),
    };
  }

  bool kernelPlanDataRequirementsMet(KernelTechnologyPlanConfig plan) =>
      kernelPlanMissingData(plan).values.every((amount) => amount == 0);

  String kernelPlanDataRequirementsLabel(KernelTechnologyPlanConfig plan) =>
      plan.dataRequirements.entries.map((entry) {
        final family = _dataFamilyForName(entry.key);
        return '${family == null ? entry.key : _ptibugDataFamilyLabel(family)} ${entry.value}';
      }).join(' · ');

  Zone0ActionResult investKernelPlanDataAutomatically(String planId) {
    final plan = kernelProgressConfig.plans
        .where((item) => item.id == planId)
        .firstOrNull;
    if (plan == null || kernelPlanState(plan) == KernelPlanState.unknown) {
      return const Zone0ActionResult(
          success: false, message: 'Pattern introuvable.');
    }
    if (!kernelPlanRequirementsMet(plan)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Les niveaux requis ne sont pas encore atteints.');
    }
    final investments = kernelPlanDataInvestments.putIfAbsent(
      plan.id,
      () => <PTibugDataFamily, int>{},
    );
    var investedAny = false;
    for (final entry in kernelPlanMissingData(plan).entries) {
      final available = pTibugDataReserve[entry.key] ?? 0;
      final amount = math.min(available, entry.value);
      if (amount == 0) continue;
      pTibugDataReserve[entry.key] = available - amount;
      investments[entry.key] = (investments[entry.key] ?? 0) + amount;
      investedAny = true;
    }
    if (!investedAny) {
      return const Zone0ActionResult(
          success: false, message: 'Réserve de données insuffisante.');
    }
    _refreshKernelPlanReadiness();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Données disponibles investies.');
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
    final researchPattern = pTibugConfig.researchPatterns.values
        .where((item) => item.linkedSpecies == species)
        .firstOrNull;
    if (researchPattern != null) {
      final progress = _patternProgressFor(researchPattern.id);
      progress
        ..state = PTibugPatternState.discovered
        ..discoveredAt ??= DateTime.now();
    }
    final planId = pTibugConfig.patterns[species]!.kernelPlanId;
    discoveredKernelPlanIds.remove(planId);
    readyKernelPlanIds.add(planId);
    activeKernelPlanIds.remove(planId);
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Le Pattern ${pTibugConfig.species[species]!.displayName} est prêt. Active-le dans les Plans du Kernel avant de le créer dans la Nurserie.',
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

  KernelTechnologyPlanConfig? kernelPlanForPTibugResearchPattern(
    String patternId,
  ) {
    final pattern = pTibugResearchPattern(patternId);
    final species = pattern?.linkedSpecies;
    if (species == null) return null;
    final planId = pTibugConfig.patterns[species]?.kernelPlanId;
    if (planId == null) return null;
    return kernelProgressConfig.plans
        .where((plan) => plan.id == planId)
        .firstOrNull;
  }

  bool sourcierPatternRequirementsMet(String patternId) {
    final pattern = pTibugResearchPattern(patternId);
    return pattern != null && pTibugResearchPatternRequirementsMet(pattern);
  }

  String sourcierPatternRequirementsLabel(String patternId) {
    final pattern = pTibugResearchPattern(patternId);
    return pattern == null
        ? 'Pattern inconnu.'
        : pTibugResearchPatternRequirementsLabel(pattern);
  }

  bool pTibugResearchPatternRequirementsMet(
    PTibugResearchPatternConfig pattern,
  ) =>
      kernelTrustLevel >= pattern.requiredTrustLevel &&
      kernelAxisLevel(KernelAxis.breeder) >= pattern.requiredBreederLevel &&
      kernelAxisLevel(KernelAxis.builder) >= pattern.requiredBuilderLevel &&
      kernelAxisLevel(KernelAxis.restorer) >= pattern.requiredRestorerLevel;

  String pTibugResearchPatternRequirementsLabel(
    PTibugResearchPatternConfig pattern,
  ) =>
      <String>[
        'Confiance niv. ${pattern.requiredTrustLevel}',
        if (pattern.requiredBreederLevel > 0)
          'Éleveur niv. ${pattern.requiredBreederLevel}',
        if (pattern.requiredBuilderLevel > 0)
          'Bâtisseur niv. ${pattern.requiredBuilderLevel}',
        if (pattern.requiredRestorerLevel > 0)
          'Régénérateur niv. ${pattern.requiredRestorerLevel}',
      ].join(' · ');

  int pTibugResearchPatternVisibility(PTibugResearchPatternConfig pattern) {
    final deficits = <int>[
      pattern.requiredTrustLevel - kernelTrustLevel,
      pattern.requiredBreederLevel - kernelAxisLevel(KernelAxis.breeder),
      pattern.requiredBuilderLevel - kernelAxisLevel(KernelAxis.builder),
      pattern.requiredRestorerLevel - kernelAxisLevel(KernelAxis.restorer),
    ];
    final largestDeficit = deficits.reduce(math.max);
    if (largestDeficit > 2) return 0;
    if (largestDeficit > 1) return 1;
    return 2;
  }

  String? merchantOfferRequirementLabel(MerchantOffer offer) {
    final patternId = offer.kind == MerchantOfferKind.speciesPattern &&
            offer.pTibugSpecies != null
        ? 'ptibug-species-${offer.pTibugSpecies!.name}'
        : offer.kind == MerchantOfferKind.researchPattern
            ? offer.patternId
            : null;
    if (patternId == null || sourcierPatternRequirementsMet(patternId)) {
      return null;
    }
    return 'Pas le niveau requis : ${sourcierPatternRequirementsLabel(patternId)}';
  }

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
    if (pattern.category != PTibugPatternCategory.trait &&
        progress.masteryLevel >= 1) {
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
    final canEvolveAgain = pattern.category == PTibugPatternCategory.trait &&
        pattern.masteryCosts.containsKey(nextLevel + 1);
    progress
      ..masteryLevel = nextLevel
      ..investedDataByFamily.clear()
      ..activatedAt = DateTime.now()
      ..state = canEvolveAgain
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
    if (plan == null ||
        kernelPlanState(plan) != KernelPlanState.ready ||
        !kernelPlanDataRequirementsMet(plan)) {
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
      final researchPattern = pTibugConfig.researchPatterns.values
          .where((item) => item.linkedSpecies == pTibugPattern.species)
          .firstOrNull;
      if (researchPattern != null) {
        final progress = _patternProgressFor(researchPattern.id);
        progress
          ..state = PTibugPatternState.active
          ..masteryLevel = math.max(progress.masteryLevel, 1)
          ..discoveredAt ??= DateTime.now()
          ..activatedAt ??= DateTime.now();
      }
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
      // Le Pattern Cœur d'énergie est révélé exclusivement par
      // _resolveEnergyCoreMilestones() à partir de 600 Bio-batteries.
      if (plan.id == 'energy-core') continue;
      final discoveryReached = kernelPlanRequirementsMet(plan);
      if (kernelPlanState(plan) == KernelPlanState.unknown &&
          discoveryReached) {
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
      if (kernelPlanRequirementsMet(plan) &&
          kernelPlanDataRequirementsMet(plan)) {
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
    _refreshPTibugResearchPatternDiscoveries();
  }

  bool _refreshPTibugResearchPatternDiscoveries() {
    var changed = false;
    for (final pattern in pTibugConfig.researchPatterns.values) {
      final progress = _patternProgressFor(pattern.id);
      if (progress.state != PTibugPatternState.unknown ||
          !pTibugResearchPatternRequirementsMet(pattern)) continue;
      progress
        ..state = PTibugPatternState.discovered
        ..discoveredAt = DateTime.now();
      changed = true;
      reports.add(
        PtipoteMissionReport.system(
          message: 'Le Kernel peut maintenant étudier ${pattern.displayName}.',
          sourceBuildingId: 'kernel',
          mailbox: Zone0MessageMailbox.kernel,
          subject: 'Pattern découvert',
          concerned: 'Joueur',
          summary: 'Les Cellules peuvent désormais être investies.',
        ),
      );
    }
    return changed;
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
    // Une figurine peut avoir été montée de niveau avant l'introduction de la
    // sauvegarde Zone 0. On ne doit jamais laisser une ancienne valeur locale
    // (souvent 1) masquer le niveau effectivement inscrit sur la figurine.
    return math.max(
      levelOverrides[figurine.id] ?? figurine.levelValue,
      figurine.levelValue,
    );
  }

  void _synchronizePtipoteProgress(PtipoteFigurine figurine) {
    final canonicalLevel = levelFor(figurine);
    if (levelOverrides[figurine.id] != canonicalLevel) {
      levelOverrides[figurine.id] = canonicalLevel;
    }
    xpOverrides.putIfAbsent(figurine.id, () => figurine.xpValue);
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
    if (ensurePtipoteV2Profiles(figurines)) changed = true;
    for (final figurine in figurines) {
      if (ptipoteV2ProfileFor(figurine).isArrivalComplete &&
          hatchedPtipoteIds.add(figurine.id)) {
        changed = true;
      }
    }
    if (changed) {
      unawaited(saveRuntimeToFirebase());
    }
  }

  /// One-time, idempotent migration for all existing physical P'TIPOTES.
  /// The source NFC fields remain untouched; only Zone 0 runtime gains a V2
  /// profile keyed by the same figurine id.
  bool ensurePtipoteV2Profiles(List<PtipoteFigurine> figurines) {
    var changed = false;
    for (final figurine in figurines) {
      if (ptipoteV2Profiles.containsKey(figurine.id)) continue;
      final legacy = figurine.legacyV2Profile(
        baseCarryCapacity: ptipoteStatsConfig.v2.defaultBaseCarryCapacity,
      );
      // A legacy runtime which had no arrival data contained only active
      // companions. If it did keep the former nursery list, preserve its
      // pending entries as eggs instead of silently activating them.
      ptipoteV2Profiles[figurine.id] = _legacyArrivalSnapshotPresent &&
              !hatchedPtipoteIds.contains(figurine.id)
          ? PtipoteArrivalService.sendPtipoteToIncubator(
              profile: legacy.copyWith(
                arrivalState: PtipoteArrivalState.pendingEgg,
              ),
              config: ptipoteStatsConfig.v2,
              systemName: figurine.displayName,
            )
          : legacy.copyWith(
              systemName: figurine.displayName,
              displayName: figurine.displayName,
              arrivalState: PtipoteArrivalState.completed,
            );
      changed = true;
    }
    return changed;
  }

  PtipoteV2Profile ptipoteV2ProfileFor(PtipoteFigurine figurine) {
    return ptipoteV2Profiles.putIfAbsent(
      figurine.id,
      () => figurine
          .legacyV2Profile(
            baseCarryCapacity: ptipoteStatsConfig.v2.defaultBaseCarryCapacity,
          )
          .copyWith(
            systemName: figurine.displayName,
            displayName: figurine.displayName,
            arrivalState: PtipoteArrivalState.completed,
          ),
    );
  }

  /// Common public entry point for NFC scans and the future Co-élevage flow.
  /// Calling it again for the same pending arrival is intentionally a no-op.
  void sendPtipoteToIncubator(
    PtipoteFigurine figurine, {
    PtipoteAcquisitionOrigin acquisitionOrigin =
        PtipoteAcquisitionOrigin.physicalScan,
    PtipoteOwnershipMode ownershipMode = PtipoteOwnershipMode.owned,
    PtipoteGeneration? generation,
    String? coBreedingSessionId,
    DateTime? now,
  }) {
    final existing = ptipoteV2Profiles[figurine.id];
    if (existing != null && existing.isAwaitingIncubator) return;
    final base = existing ??
        figurine.legacyV2Profile(
          baseCarryCapacity: ptipoteStatsConfig.v2.defaultBaseCarryCapacity,
        );
    sendPtipoteProfileToIncubator(
      base.copyWith(
        acquisitionOrigin: acquisitionOrigin,
        ownershipMode: ownershipMode,
        ptipoteGeneration: generation ?? base.ptipoteGeneration,
        // This is only the future physical fabrication route marker. It does
        // not grant an Envelope and it is never used by Co-élevage.
        envelopeAcquisitionMode:
            acquisitionOrigin == PtipoteAcquisitionOrigin.physicalScan &&
                    (generation ?? base.ptipoteGeneration) ==
                        PtipoteGeneration.protocol
                ? 'cultivated'
                : base.envelopeAcquisitionMode,
        coBreedingSessionId: coBreedingSessionId,
      ),
      systemName: figurine.displayName,
      now: now,
    );
  }

  /// Shared future entry point for Co-élevage. It only needs the common V2
  /// profile, unlike the physical-figurine wrapper above.
  void sendPtipoteProfileToIncubator(
    PtipoteV2Profile profile, {
    required String systemName,
    DateTime? now,
  }) {
    final existing = ptipoteV2Profiles[profile.ptipoteId];
    if (existing != null && existing.isAwaitingIncubator) return;
    final pending = profile.copyWith(
      arrivalState: PtipoteArrivalState.pendingEgg,
      systemName: systemName,
      displayName: '',
      rhythmPattern: const <int>[],
      rhythmAttemptCount: 0,
      arrivalCreatedAt: now ?? DateTime.now(),
      updatedAt: now ?? DateTime.now(),
    );
    ptipoteV2Profiles[profile.ptipoteId] =
        PtipoteArrivalService.sendPtipoteToIncubator(
      profile: pending,
      config: ptipoteStatsConfig.v2,
      systemName: systemName,
      now: now,
    );
    hatchedPtipoteIds.remove(profile.ptipoteId);
    levelOverrides[profile.ptipoteId] =
        ptipoteStatsConfig.v2.arrivalInitialLevel;
    xpOverrides[profile.ptipoteId] = ptipoteStatsConfig.v2.arrivalInitialXp;
    _recordPtipoteArrivalReport(
      PtipoteMissionReport.system(
        id: 'ptipote-egg-${profile.ptipoteId}',
        message: 'Un œuf vous attend dans la Couveuse de la Maison.',
        mailbox: Zone0MessageMailbox.companions,
        sourceBuildingId: 'house',
        subject: 'Œuf dans la Couveuse',
        concerned: 'Maison',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void preparePtipoteArrivalRhythm(PtipoteFigurine figurine) {
    final profile = ptipoteV2ProfileFor(figurine);
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.prepareRhythm(
        profile,
        config: ptipoteStatsConfig.v2,
      ),
    );
  }

  void beginPtipoteArrivalRhythm(PtipoteFigurine figurine) {
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.beginRhythm(ptipoteV2ProfileFor(figurine)),
    );
  }

  void failPtipoteArrivalRhythm(PtipoteFigurine figurine) {
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.failRhythm(ptipoteV2ProfileFor(figurine)),
    );
  }

  void hatchPtipoteArrival(PtipoteFigurine figurine) {
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.hatch(ptipoteV2ProfileFor(figurine)),
    );
  }

  void beginPtipoteArrivalNaming(PtipoteFigurine figurine) {
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.startNaming(ptipoteV2ProfileFor(figurine)),
    );
  }

  void completePtipoteArrival(PtipoteFigurine figurine, String displayName) {
    final profile = PtipoteArrivalService.finalizeNaming(
      ptipoteV2ProfileFor(figurine),
      displayName: displayName,
    );
    _replacePtipoteArrivalProfile(profile);
    hatchedPtipoteIds.add(figurine.id);
    _recordPtipoteArrivalReport(
      PtipoteMissionReport.system(
        id: 'ptipote-hatched-${figurine.id}',
        message: profile.ownershipMode == PtipoteOwnershipMode.coBred
            ? '${profile.displayName} rejoint temporairement le refuge.'
            : '${profile.displayName} a éclos dans la Couveuse.',
        mailbox: Zone0MessageMailbox.companions,
        sourceBuildingId: 'house',
        subject: 'Éclosion terminée',
        concerned: profile.displayName,
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void resumeInterruptedPtipoteArrival(PtipoteFigurine figurine) {
    _replacePtipoteArrivalProfile(
      PtipoteArrivalService.resumeAfterInterruption(
        ptipoteV2ProfileFor(figurine),
      ),
    );
  }

  int get breederLevel => kernelAxisLevel(KernelAxis.breeder);

  /// One temporary companion per breeder level. This is intentionally not a
  /// multiplier: Éleveur 10 means exactly ten possible Co-élevages.
  int get coBreedingCapacity => math.max(1, breederLevel);

  Duration coBreedingSelectionCooldownRemaining({DateTime? now}) {
    return coBreedingSelectionCooldownFor(
      lastSelectionAt: lastCoBreedingSelectionAt,
      config: coBreedingConfig,
      now: now ?? DateTime.now(),
    );
  }

  bool get canSelectCoBreeding =>
      coBreedingSelectionCooldownRemaining() == Duration.zero;

  List<CoBreedingSession> get activeCoBreedingSessions => coBreedingSessions
      .where(
        (session) =>
            session.status != CoBreedingSessionStatus.completed &&
            session.status != CoBreedingSessionStatus.archived,
      )
      .toList();

  List<CoBreedingSession> get pendingCoBreedingDepartures => coBreedingSessions
      .where(
        (session) =>
            session.departurePending &&
            session.status != CoBreedingSessionStatus.completed &&
            session.status != CoBreedingSessionStatus.archived,
      )
      .toList()
    ..sort(
      (a, b) => (a.departurePendingAt ?? a.startedAt)
          .compareTo(b.departurePendingAt ?? b.startedAt),
    );

  int get activeCoBredCount => activeCoBreedingSessions.length;

  bool get isCoBreedingCapacityReached =>
      activeCoBredCount >= coBreedingCapacity;

  List<PtipoteFigurine> coBredFigurines() => activeCoBreedingSessions
      .map((session) => ptipoteV2Profiles[session.ptipoteId])
      .whereType<PtipoteV2Profile>()
      .map(coBredFigurineFromProfile)
      .toList();

  List<PtipoteFigurine> allPtipotes(List<PtipoteFigurine> physical) =>
      <PtipoteFigurine>[...physical, ...coBredFigurines()];

  /// The single source used by every activity selector. Physical figures and
  /// temporary Co-élevage profiles share the same activity engine once their
  /// arrival ritual is completed. Eggs and P'TIPOTES preparing a departure
  /// deliberately stay out of every Craft, Lisière, Tour and Marché picker.
  List<PtipoteFigurine> ptipotesAvailableForActivities(
    List<PtipoteFigurine> physical,
  ) =>
      allPtipotes(physical).where((figurine) {
        final profile = ptipoteV2ProfileFor(figurine);
        return profile.isArrivalComplete &&
            profile.lifecycleStatus == PtipoteLifecycleStatus.active &&
            !profile.departurePending;
      }).toList();

  /// Needs use the same living roster as activities. Co-élevage companions
  /// are real P’TIPOTES after hatching, so hunger and rest must evolve too.
  List<PtipoteFigurine> ptipotesWithNeeds(
    List<PtipoteFigurine> physical,
  ) =>
      ptipotesAvailableForActivities(physical);

  bool shouldShowInitialPtipoteChoice(List<PtipoteFigurine> physical) =>
      allPtipotes(physical).isEmpty &&
      ptipoteV2Profiles.values.every((profile) => profile.isArrivalComplete);

  bool isCoBreedingIntroMissionAvailable(List<PtipoteFigurine> physical) =>
      !coBreedingUnlocked &&
      !coBreedingIntroMissionDismissed &&
      !shouldShowInitialPtipoteChoice(physical) &&
      kernelTrustLevel >= coBreedingConfig.kernelUnlockLevel;

  void acceptCoBreedingIntroMission() {
    if (coBreedingUnlocked) return;
    coBreedingUnlocked = true;
    reports.add(
      PtipoteMissionReport.system(
        id: 'co-breeding-unlocked',
        message: 'Le Co-élevage est désormais disponible depuis la Maison.',
        sourceBuildingId: 'kernel',
        mailbox: Zone0MessageMailbox.kernel,
        subject: 'Co-élevage débloqué',
        concerned: 'Joueur',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void dismissCoBreedingIntroMission() {
    coBreedingIntroMissionDismissed = true;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  List<CoBreedingTemplate> availableCoBreedingTemplates({
    PtipoteTypeId? type,
    PtipoteGeneration? generation,
  }) {
    final useDev = coBreedingDevMode;
    return <CoBreedingTemplate>[
      ...defaultCoBreedingVestiges,
      ...defaultCoBreedingProtocols,
    ].where((template) {
      if (type != null && template.typeId != type) return false;
      if (generation != null && template.generation != generation) return false;
      if (template.minBreederLevel > breederLevel) return false;
      return useDev ? template.devEnabled : template.publicEnabled;
    }).toList();
  }

  CoBreedingOffer? ensureCoBreedingOffer({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    if (coBreedingOffer != null &&
        !coBreedingOffer!.consumed &&
        coBreedingOffer!.expiresAt.isAfter(timestamp)) {
      return coBreedingOffer;
    }
    final templates = availableCoBreedingTemplates();
    if (templates.isEmpty) {
      coBreedingOffer = null;
      return null;
    }
    final seed = timestamp.millisecondsSinceEpoch ~/ 1000;
    final template = _weightedCoBreedingTemplate(templates, seed);
    coBreedingOffer = CoBreedingOffer(
      offerId: 'co-offer-$seed-${template.templateId}',
      templateId: template.templateId,
      typeId: template.typeId,
      generation: template.generation,
      generatedAt: timestamp,
      expiresAt: timestamp.add(
        Duration(hours: math.max(1, coBreedingConfig.offerRotationHours)),
      ),
      randomSeed: seed,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return coBreedingOffer;
  }

  CoBreedingTemplate _weightedCoBreedingTemplate(
    List<CoBreedingTemplate> templates,
    int seed,
  ) {
    final total = templates.fold<int>(
      0,
      (sum, item) => sum + math.max(1, item.drawWeight),
    );
    var cursor = math.Random(seed).nextInt(math.max(1, total));
    for (final template in templates) {
      cursor -= math.max(1, template.drawWeight);
      if (cursor < 0) return template;
    }
    return templates.first;
  }

  CoBreedingTemplate? coBreedingTemplateFor(String templateId) {
    for (final template in <CoBreedingTemplate>[
      ...defaultCoBreedingVestiges,
      ...defaultCoBreedingProtocols,
    ]) {
      if (template.templateId == templateId) return template;
    }
    return null;
  }

  CoBreedingSession? activeCoBreedingSessionFor(String ptipoteId) {
    for (final session in coBreedingSessions) {
      if (session.ptipoteId == ptipoteId &&
          session.status == CoBreedingSessionStatus.active &&
          !session.departurePending) {
        return session;
      }
    }
    return null;
  }

  /// Read-only lookup used by profiles. Unlike the activity eligibility
  /// helper above it deliberately keeps a departure-pending session visible
  /// until its House departure has actually been completed.
  CoBreedingSession? coBreedingSessionFor(String ptipoteId) =>
      coBreedingSessions
          .where((session) =>
              session.ptipoteId == ptipoteId &&
              session.status != CoBreedingSessionStatus.completed &&
              session.status != CoBreedingSessionStatus.archived)
          .firstOrNull;

  /// Business-rule guard used by both the offer generator and the UI. A
  /// Vestige, a departing companion or an owned physical Protocol can never
  /// acquire a temporary Co-élevage envelope through this path.
  bool isEligibleForEnvelope(String ptipoteId) {
    final profile = ptipoteV2Profiles[ptipoteId];
    if (profile == null ||
        !profile.isProtocol ||
        profile.ownershipMode != PtipoteOwnershipMode.coBred ||
        profile.envelopeId != null ||
        profile.departurePending ||
        levelForId(ptipoteId) <
            ptipoteStatsConfig.v2.envelopeUnlockPtipoteLevel) {
      return false;
    }
    return activeCoBreedingSessionFor(ptipoteId) != null;
  }

  int levelForId(String ptipoteId) => levelOverrides[ptipoteId] ?? 1;

  List<CoBreedingEnvelopeTemplate> availableCoBreedingEnvelopeTemplatesFor(
    String ptipoteId,
  ) {
    final session = activeCoBreedingSessionFor(ptipoteId);
    final template = session == null
        ? null
        : coBreedingTemplateFor(session.ptipoteTemplateId);
    if (template == null) return const <CoBreedingEnvelopeTemplate>[];
    return defaultCoBreedingEnvelopeTemplates.where((envelope) {
      if (envelope.minBreederLevel > breederLevel) return false;
      if (!template.compatibleEnvelopeIds.contains(envelope.envelopeId)) {
        return false;
      }
      return coBreedingDevMode ? envelope.devEnabled : envelope.publicEnabled;
    }).toList();
  }

  CoBreedingEnvelopeOffer? ensureCoBreedingEnvelopeOffer(
    String ptipoteId, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    if (!isEligibleForEnvelope(ptipoteId)) return null;
    final existing = coBreedingEnvelopeOffers[ptipoteId];
    if (existing != null &&
        existing.ptipoteId == ptipoteId &&
        !existing.consumed &&
        existing.expiresAt.isAfter(timestamp) &&
        availableCoBreedingEnvelopeTemplatesFor(ptipoteId)
            .any((item) => item.envelopeId == existing.envelopeId)) {
      return existing;
    }
    final templates = availableCoBreedingEnvelopeTemplatesFor(ptipoteId);
    if (templates.isEmpty) return null;
    final seed = timestamp.millisecondsSinceEpoch ~/ 1000;
    final chosen = _weightedCoBreedingEnvelopeTemplate(templates, seed);
    final created = CoBreedingEnvelopeOffer(
      offerId: 'co-envelope-$seed-$ptipoteId-${chosen.envelopeId}',
      ptipoteId: ptipoteId,
      envelopeId: chosen.envelopeId,
      generatedAt: timestamp,
      expiresAt: timestamp.add(
        Duration(hours: math.max(1, coBreedingConfig.offerRotationHours)),
      ),
      randomSeed: seed,
    );
    coBreedingEnvelopeOffers[ptipoteId] = created;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return created;
  }

  CoBreedingEnvelopeTemplate _weightedCoBreedingEnvelopeTemplate(
    List<CoBreedingEnvelopeTemplate> templates,
    int seed,
  ) {
    final total = templates.fold<int>(
      0,
      (sum, item) => sum + math.max(1, item.drawWeight),
    );
    var cursor = math.Random(seed).nextInt(math.max(1, total));
    for (final template in templates) {
      cursor -= math.max(1, template.drawWeight);
      if (cursor < 0) return template;
    }
    return templates.first;
  }

  Zone0ActionResult acceptFreeCoBreedingEnvelope(String ptipoteId) {
    final offer = ensureCoBreedingEnvelopeOffer(ptipoteId);
    if (offer == null ||
        offer.consumed ||
        !offer.expiresAt.isAfter(DateTime.now())) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune Enveloppe compatible disponible actuellement.',
      );
    }
    final result = _assignCoBreedingEnvelope(
      ptipoteId: ptipoteId,
      envelopeId: offer.envelopeId,
    );
    if (result.success) {
      coBreedingEnvelopeOffers[ptipoteId] = offer.copyWith(consumed: true);
    }
    return result;
  }

  Zone0ActionResult chooseExactCoBreedingEnvelope(
    String ptipoteId,
    String envelopeId,
  ) {
    if (!availableCoBreedingEnvelopeTemplatesFor(ptipoteId)
        .any((item) => item.envelopeId == envelopeId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette Enveloppe n’est pas compatible ou indisponible.',
      );
    }
    return _assignCoBreedingEnvelope(
      ptipoteId: ptipoteId,
      envelopeId: envelopeId,
      bioBatteryCost: coBreedingConfig.chooseExactEnvelopeCost,
    );
  }

  Zone0ActionResult _assignCoBreedingEnvelope({
    required String ptipoteId,
    required String envelopeId,
    int bioBatteryCost = 0,
  }) {
    final profile = ptipoteV2Profiles[ptipoteId];
    if (!isEligibleForEnvelope(ptipoteId) || profile == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce P’TIPOTE ne peut pas encore recevoir d’Enveloppe.',
      );
    }
    if (!availableCoBreedingEnvelopeTemplatesFor(ptipoteId)
        .any((item) => item.envelopeId == envelopeId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Enveloppe incompatible.',
      );
    }
    if (bioBatteryCost > 0 && bioBatteries < bioBatteryCost) {
      return Zone0ActionResult(
        success: false,
        message: '$bioBatteryCost Bio-batteries requises.',
      );
    }
    final now = DateTime.now();
    final assetKey = '${normalizePtipoteAssetKey(profile.natureId)}_'
        '${normalizePtipoteAssetKey(envelopeId)}';
    final symbiosis = PtipoteEnvelopeSymbiosis(
      envelopeId: envelopeId,
      symbiosisLevel: 0,
      symbiosisProgressPercent: 0,
      startedAt: now,
      lastCalculatedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    // Every failing validation is complete before the debit: this is the
    // transaction boundary for local/Firebase eventual persistence.
    if (bioBatteryCost > 0) bioBatteries -= bioBatteryCost;
    ptipoteV2Profiles[ptipoteId] = profile.copyWith(
      envelopeId: envelopeId,
      envelopeAcquisitionMode: 'coBreedingTemporary',
      envelopeSymbiosis: symbiosis,
      visualAssetKey: assetKey,
      clearProtocolEfficiencyMultiplier: true,
      updatedAt: now,
    );
    reports.add(PtipoteMissionReport.system(
      id: 'co-envelope-$ptipoteId-$envelopeId-${now.millisecondsSinceEpoch}',
      message:
          '${profile.displayName.isNotEmpty ? profile.displayName : profile.systemName} reçoit l’Enveloppe $envelopeId.',
      sourceBuildingId: 'house',
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Enveloppe obtenue',
      concerned: profile.displayName.isNotEmpty
          ? profile.displayName
          : profile.systemName,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Enveloppe attribuée.');
  }

  Zone0ActionResult startInitialCoBreeding(PtipoteTypeId type) {
    if (!coBreedingConfig.initialFreeCoBreedingEnabled) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le premier Co-élevage est indisponible.',
      );
    }
    return _startCoBreedingFromTemplate(
      templates: availableCoBreedingTemplates(type: type),
      selectionMode: CoBreedingSelectionMode.initialFreeTypeChoice,
      randomSeed: DateTime.now().microsecondsSinceEpoch,
    );
  }

  Zone0ActionResult acceptCoBreedingOffer() {
    final offer = ensureCoBreedingOffer();
    if (offer == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun P’TIPOTE disponible actuellement.',
      );
    }
    if (offer.consumed || !offer.expiresAt.isAfter(DateTime.now())) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cette proposition n’est plus disponible.',
      );
    }
    final template = coBreedingTemplateFor(offer.templateId);
    if (template == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Proposition indisponible actuellement.',
      );
    }
    final result = _startCoBreedingTemplate(
      template,
      selectionMode: CoBreedingSelectionMode.randomFreeOffer,
      sourceOfferId: offer.offerId,
    );
    if (result.success) {
      coBreedingOffer = offer.copyWith(consumed: true);
      ensureCoBreedingOffer(
          now: DateTime.now().add(const Duration(seconds: 1)));
    }
    return result;
  }

  Zone0ActionResult chooseCoBreedingType(PtipoteTypeId type) {
    if (breederLevel < 3) {
      return const Zone0ActionResult(
        success: false,
        message: 'Niveau Éleveur 3 requis.',
      );
    }
    return _startCoBreedingFromTemplate(
      templates: availableCoBreedingTemplates(type: type),
      selectionMode: CoBreedingSelectionMode.paidTypeChoice,
      randomSeed: DateTime.now().microsecondsSinceEpoch,
      bioBatteryCost: coBreedingConfig.chooseTypeCost,
    );
  }

  Zone0ActionResult chooseExactCoBreedingPtipote(String templateId) {
    if (breederLevel < 4) {
      return const Zone0ActionResult(
        success: false,
        message: 'Niveau Éleveur 4 requis.',
      );
    }
    final template = availableCoBreedingTemplates()
        .where(
          (item) => item.templateId == templateId,
        )
        .firstOrNull;
    if (template == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE indisponible actuellement.',
      );
    }
    return _startCoBreedingTemplate(
      template,
      selectionMode: CoBreedingSelectionMode.paidExactPtipote,
      bioBatteryCost: coBreedingConfig.chooseExactPtipoteCost,
    );
  }

  Zone0ActionResult _startCoBreedingFromTemplate({
    required List<CoBreedingTemplate> templates,
    required CoBreedingSelectionMode selectionMode,
    required int randomSeed,
    int bioBatteryCost = 0,
  }) {
    if (templates.isEmpty) {
      return const Zone0ActionResult(
        success: false,
        message: 'Indisponible actuellement.',
      );
    }
    return _startCoBreedingTemplate(
      _weightedCoBreedingTemplate(templates, randomSeed),
      selectionMode: selectionMode,
      bioBatteryCost: bioBatteryCost,
    );
  }

  Zone0ActionResult _startCoBreedingTemplate(
    CoBreedingTemplate template, {
    required CoBreedingSelectionMode selectionMode,
    String? sourceOfferId,
    int bioBatteryCost = 0,
  }) {
    if (!coBreedingConfig.enabled) {
      return const Zone0ActionResult(
          success: false, message: 'Co-élevage indisponible.');
    }
    if (isCoBreedingCapacityReached) {
      return const Zone0ActionResult(
        success: false,
        message: 'Capacité de Co-élevage atteinte.',
      );
    }
    final cooldown = coBreedingSelectionCooldownRemaining();
    if (cooldown > Duration.zero) {
      final hours = cooldown.inHours;
      final minutes = cooldown.inMinutes.remainder(60);
      return Zone0ActionResult(
        success: false,
        message:
            'Prochain accueil de Co-élevage dans ${hours} h ${minutes} min.',
      );
    }
    if (bioBatteryCost > 0 && bioBatteries < bioBatteryCost) {
      return Zone0ActionResult(
        success: false,
        message: '$bioBatteryCost Bio-batteries requises.',
      );
    }
    final now = DateTime.now();
    final sessionId = 'co-${now.microsecondsSinceEpoch}-${template.templateId}';
    final ptipoteId = 'co-ptipote-$sessionId';
    final duration = Duration(hours: coBreedingConfig.maxDurationHours);
    final profile = PtipoteV2Profile(
      ptipoteId: ptipoteId,
      acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
      ownershipMode: PtipoteOwnershipMode.coBred,
      ptipoteGeneration: template.generation,
      typeId: template.typeId,
      natureId: template.natureId,
      coreId: template.coreId,
      systemName: template.systemName,
      baseCarryCapacity: ptipoteStatsConfig.v2.defaultBaseCarryCapacity,
      coBreedingSessionId: sessionId,
      coBreedingStartedAt: now,
      coBreedingExpiresAt: now.add(duration),
      createdAt: now,
      updatedAt: now,
    );
    // All checks precede the only debit: atomic from the game’s perspective.
    if (bioBatteryCost > 0) bioBatteries -= bioBatteryCost;
    coBreedingSessions.add(CoBreedingSession(
      sessionId: sessionId,
      ptipoteId: ptipoteId,
      sourceOfferId: sourceOfferId,
      selectionMode: selectionMode,
      typeId: template.typeId,
      ptipoteTemplateId: template.templateId,
      startedAt: now,
      expiresAt: now.add(duration),
      initialDurationSeconds: duration.inSeconds,
      remainingSeconds: duration.inSeconds,
      lastPlayerActiveAt: now,
    ));
    lastCoBreedingSelectionAt = now;
    sendPtipoteProfileToIncubator(profile,
        systemName: template.systemName, now: now);
    reports.add(PtipoteMissionReport.system(
      id: 'co-breeding-start-$sessionId',
      message: '${template.systemName} rejoint temporairement la Couveuse.',
      sourceBuildingId: 'house',
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Co-élevage commencé',
      concerned: template.systemName,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Un œuf vous attend dans la Couveuse de la Maison.',
    );
  }

  void resolveCoBreedingSessions({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    var changed = false;
    for (var index = 0; index < coBreedingSessions.length; index += 1) {
      final session = coBreedingSessions[index];
      final resolved = CoBreedingTimeService.resolve(
        session,
        config: coBreedingConfig,
        now: timestamp,
      );
      if (resolved == session) continue;
      coBreedingSessions[index] = resolved;
      changed = true;
      if (resolved.departurePending) {
        final profile = ptipoteV2Profiles[resolved.ptipoteId];
        if (profile != null) {
          ptipoteV2Profiles[profile.ptipoteId] = profile.copyWith(
            departurePending: true,
            departureReason: resolved.departureReason?.name,
            lifecycleStatus: PtipoteLifecycleStatus.departurePending,
          );
        }
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    resolveEnvelopeSymbiosis(now: timestamp);
  }

  /// Marks the oldest departure as presented so only one Maison modal can be
  /// active at a time. A crash retains this state and the same session resumes
  /// before any other departure can be finalised.
  CoBreedingSession? prepareNextCoBreedingDeparture() {
    final pending = pendingCoBreedingDepartures;
    if (pending.isEmpty) return null;
    final next = pending.first;
    final index = coBreedingSessions.indexWhere(
      (session) => session.sessionId == next.sessionId,
    );
    if (index < 0) return null;
    final presented = next.status == CoBreedingSessionStatus.departurePresented
        ? next
        : next.copyWith(status: CoBreedingSessionStatus.departurePresented);
    coBreedingSessions[index] = presented;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return presented;
  }

  CoBreedingCompletionResult? finalizeCoBreedingDeparture(String sessionId) {
    final index = coBreedingSessions.indexWhere(
      (session) => session.sessionId == sessionId,
    );
    if (index < 0) return null;
    final session = coBreedingSessions[index];
    final profile = ptipoteV2Profiles[session.ptipoteId];
    if (profile == null) return null;
    final existingReward = coBreedingXpRewards
        .where((reward) => reward.sourceSessionId == sessionId)
        .firstOrNull;
    final finalLevel = levelForId(profile.ptipoteId);
    final finalXp = xpOverrides[profile.ptipoteId] ?? 0;
    final displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.systemName;
    final v2 = ptipoteStatsConfig.v2;
    final rewards = CoBreedingCompletionService.rewardsFor(
      config: v2,
      finalLevel: finalLevel,
    );
    final ptipoteXp = rewards.ptipoteXp;
    final breederXp = rewards.breederXp;
    final trustXp = rewards.kernelTrust;
    if (session.rewardsGrantedAt != null || existingReward != null) {
      return CoBreedingCompletionResult(
        sessionId: sessionId,
        displayName: displayName,
        typeId: profile.typeId,
        ptipoteXpAmount: existingReward?.xpAmount ?? ptipoteXp,
        breederXpAmount: breederXp,
        kernelTrustAmount: trustXp,
        alreadyCompleted: true,
      );
    }
    if (!CoBreedingCompletionService.canFinalize(session, profile)) {
      return null;
    }
    final now = DateTime.now();
    final transactionId =
        'co-complete-$sessionId-${now.microsecondsSinceEpoch}';
    final archive = CoBreedingArchive(
      sessionId: sessionId,
      ptipoteId: profile.ptipoteId,
      displayName: profile.displayName,
      systemName: profile.systemName,
      typeId: profile.typeId,
      natureId: profile.natureId,
      generation: profile.ptipoteGeneration,
      coreId: profile.coreId,
      envelopeId: profile.envelopeId,
      finalLevel: finalLevel,
      finalXp: finalXp,
      symbiosisLevel: profile.envelopeSymbiosis?.symbiosisLevel,
      symbiosisProgressPercent:
          profile.envelopeSymbiosis?.symbiosisProgressPercent,
      protocolEfficiency:
          profile.isProtocol ? profile.effectiveProtocolEfficiency(v2) : null,
      arrivedAt: session.startedAt,
      departedAt: now,
      departureReason: session.departureReason,
    );
    // One local transaction: archive, immutable reward, generic Kernel gains,
    // and terminal session status are written together before persistence.
    coBreedingArchive.removeWhere((entry) => entry.sessionId == sessionId);
    coBreedingArchive.add(archive);
    coBreedingXpRewards.add(CoBreedingXpReward(
      itemId: 'co-xp-$sessionId',
      compatibleTypeId: profile.typeId,
      xpAmount: ptipoteXp,
      sourceSessionId: sessionId,
      sourcePtipoteId: profile.ptipoteId,
      createdAt: now,
    ));
    _addKernelAxisXp(KernelAxis.breeder, breederXp);
    _addKernelTrustXp(trustXp);
    kernelProgressHistory.add(KernelProgressHistoryEntry(
      occurredAt: now,
      eventType: KernelProgressEventType.craftCompleted,
      trustXp: trustXp,
      breederXp: breederXp,
      builderXp: 0,
      restorerXp: 0,
    ));
    completedCoBreedingCount += 1;
    ptipoteV2Profiles[profile.ptipoteId] = profile.copyWith(
      lifecycleStatus: PtipoteLifecycleStatus.departedCoBreeding,
      departurePending: true,
      updatedAt: now,
    );
    coBreedingSessions[index] = session.copyWith(
      status: CoBreedingSessionStatus.completed,
      departurePending: true,
      rewardsGrantedAt: now,
      completionTransactionId: transactionId,
    );
    reports.add(PtipoteMissionReport.system(
      id: 'co-breeding-departure-$sessionId',
      message:
          '$displayName a quitté le refuge après son Co-élevage · niveau $finalLevel.',
      sourceBuildingId: 'house',
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Co-élevage terminé',
      concerned: displayName,
      summary:
          'Bonus XP ${_ptipoteTypeLabel(profile.typeId)} +$ptipoteXp · Éleveur +$breederXp · Kernel +$trustXp.',
    ));
    _refreshKernelPlanReadiness();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return CoBreedingCompletionResult(
      sessionId: sessionId,
      displayName: displayName,
      typeId: profile.typeId,
      ptipoteXpAmount: ptipoteXp,
      breederXpAmount: breederXp,
      kernelTrustAmount: trustXp,
      alreadyCompleted: false,
    );
  }

  List<PtipoteFigurine> eligibleTargetsForCoBreedingXpReward(
    CoBreedingXpReward reward,
    List<PtipoteFigurine> physical,
  ) =>
      physical.where((figurine) {
        final profile = ptipoteV2ProfileFor(figurine);
        return profile.ownershipMode == PtipoteOwnershipMode.owned &&
            profile.lifecycleStatus == PtipoteLifecycleStatus.active &&
            profile.typeId == reward.compatibleTypeId &&
            !profile.departurePending &&
            !isOnMission(figurine.id);
      }).toList();

  Zone0ActionResult consumeCoBreedingXpReward(
    String itemId,
    PtipoteFigurine target,
  ) {
    final index = coBreedingXpRewards.indexWhere(
      (reward) => reward.itemId == itemId && !reward.isConsumed,
    );
    if (index < 0) {
      return const Zone0ActionResult(
          success: false, message: 'Bonus XP indisponible.');
    }
    final reward = coBreedingXpRewards[index];
    final profile = ptipoteV2ProfileFor(target);
    if (profile.ownershipMode != PtipoteOwnershipMode.owned ||
        profile.lifecycleStatus != PtipoteLifecycleStatus.active ||
        profile.departurePending) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce Bonus XP vise uniquement un P’TIPOTE possédé actif.',
      );
    }
    if (profile.typeId != reward.compatibleTypeId) {
      return const Zone0ActionResult(
          success: false, message: 'Type incompatible.');
    }
    // Normal XP resolution first, then irreversible consumption.
    addMissionXp(target.id, reward.xpAmount);
    coBreedingXpRewards[index] = reward.consume(target.id, DateTime.now());
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '+${reward.xpAmount} XP appliquée à ${target.displayName}.');
  }

  /// Applies the continuous +1%/h symbiosis credit once per elapsed period.
  /// The timestamp is advanced even for fractional hours, preventing a second
  /// reconnect from crediting the same time again.
  void resolveEnvelopeSymbiosis({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    var changed = false;
    for (final entry in ptipoteV2Profiles.entries.toList()) {
      final profile = entry.value;
      final current = profile.envelopeSymbiosis;
      if (current == null ||
          profile.envelopeId == null ||
          profile.departurePending ||
          !profile.isArrivalComplete ||
          activeCoBreedingSessionFor(profile.ptipoteId) == null) {
        continue;
      }
      final resolved = EnvelopeSymbiosisService.resolveTime(
        current,
        config: ptipoteStatsConfig.v2,
        now: timestamp,
      );
      if (resolved == current) continue;
      ptipoteV2Profiles[entry.key] = profile.copyWith(
        envelopeSymbiosis: resolved,
        updatedAt: timestamp,
      );
      changed = true;
      if (resolved.symbiosisLevel > current.symbiosisLevel) {
        final completed = resolved.maxLevelReached;
        reports.add(PtipoteMissionReport.system(
          id: 'symbiosis-level-${profile.ptipoteId}-${resolved.symbiosisLevel}',
          message: completed
              ? '${profile.displayName.isNotEmpty ? profile.displayName : profile.systemName} a pleinement adopté son Enveloppe.'
              : '${profile.displayName.isNotEmpty ? profile.displayName : profile.systemName} s’habitue à son Enveloppe.',
          sourceBuildingId: 'house',
          mailbox: Zone0MessageMailbox.companions,
          subject: completed ? 'Symbiose complète' : 'Symbiose renforcée',
          concerned: profile.displayName.isNotEmpty
              ? profile.displayName
              : profile.systemName,
        ));
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  void recordPtipoteActivityCompleted(String ptipoteId) {
    final profile = ptipoteV2Profiles[ptipoteId];
    final current = profile?.envelopeSymbiosis;
    if (profile == null ||
        current == null ||
        profile.departurePending ||
        activeCoBreedingSessionFor(ptipoteId) == null) {
      return;
    }
    final now = DateTime.now();
    final updated = EnvelopeSymbiosisService.addActivity(
      current,
      config: ptipoteStatsConfig.v2,
      now: now,
    );
    if (updated == current) return;
    ptipoteV2Profiles[ptipoteId] = profile.copyWith(
      envelopeSymbiosis: updated,
      updatedAt: now,
    );
    if (updated.symbiosisLevel > current.symbiosisLevel) {
      reports.add(PtipoteMissionReport.system(
        id: 'symbiosis-activity-level-$ptipoteId-${updated.symbiosisLevel}',
        message: updated.maxLevelReached
            ? '${profile.displayName.isNotEmpty ? profile.displayName : profile.systemName} a pleinement adopté son Enveloppe.'
            : '${profile.displayName.isNotEmpty ? profile.displayName : profile.systemName} s’habitue à son Enveloppe.',
        sourceBuildingId: 'house',
        mailbox: Zone0MessageMailbox.companions,
        subject: updated.maxLevelReached
            ? 'Symbiose complète'
            : 'Symbiose renforcée',
        concerned: profile.displayName.isNotEmpty
            ? profile.displayName
            : profile.systemName,
      ));
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void _replacePtipoteArrivalProfile(PtipoteV2Profile profile) {
    if (ptipoteV2Profiles[profile.ptipoteId] == profile) return;
    ptipoteV2Profiles[profile.ptipoteId] = profile;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void _recordPtipoteArrivalReport(PtipoteMissionReport report) {
    if (reports.any((existing) => existing.id == report.id)) return;
    reports.insert(0, report);
  }

  PtipoteEffectiveModifiers modifiersFor(
    PtipoteFigurine figurine, {
    int eligibleGroupPtipoteCount = 1,
  }) {
    return PtipoteModifierService.resolve(
      profile: ptipoteV2ProfileFor(figurine),
      config: ptipoteStatsConfig.v2,
      mycelialGatherBonus:
          lisiereForageConfig.myceliumExploration.mycelialTypeGatherBonus,
      eligibleGroupPtipoteCount: eligibleGroupPtipoteCount,
    );
  }

  int effectiveCarryCapacityFor(
    PtipoteFigurine figurine, {
    int eligibleGroupPtipoteCount = 1,
  }) {
    final profile = ptipoteV2ProfileFor(figurine);
    return PtipoteModifierService.effectiveCarryCapacity(
      profile: profile,
      modifiers: modifiersFor(
        figurine,
        eligibleGroupPtipoteCount: eligibleGroupPtipoteCount,
      ),
    );
  }

  /// Future Protocol editor / Co-élevage entry point. It is intentionally
  /// limited to data changes in this first V2 foundation prompt.
  void updatePtipoteV2Profile(PtipoteV2Profile profile) {
    ptipoteV2Profiles[profile.ptipoteId] = profile.copyWith(
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  bool isInNursery(PtipoteFigurine figurine) =>
      !ptipoteV2ProfileFor(figurine).isArrivalComplete;

  bool canHatchFromNursery(PtipoteFigurine figurine) => isInNursery(figurine);

  void hatchFromNursery(PtipoteFigurine figurine) {
    hatchPtipoteArrival(figurine);
  }

  bool isBusy(PtipoteFigurine figurine) {
    return isInNursery(figurine) ||
        activeCoBreedingSessions.any(
          (session) =>
              session.ptipoteId == figurine.id && session.departurePending,
        ) ||
        isOnMission(figurine.id) ||
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
    return (workshopConfig.ptipoteCraftTimeReductionPercent +
            figurineBonus.clamp(0, workshopConfig.maxLevelSpeedBonusPercent) +
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
    if (!isBuildingOperational('atelier')) {
      return const Zone0ActionResult(
          success: false,
          message: 'Atelier hors service : remise en marche requise.');
    }
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
    if (quantity == -1 && figurine == null) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Le lot ∞ est réservé à une fabrication confiée à un P’TIPOTE.',
      );
    }
    if (quantity == -1 && atelierLevel < 4) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le lot ∞ se débloque avec l’Atelier niveau 4.',
      );
    }
    if (quantity == 50 && atelierLevel < 3) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le lot x50 se débloque avec l’Atelier niveau 3.',
      );
    }
    if (quantity == -1) {
      final materialLimit = recipe.ingredients.entries
          .map((entry) => resourceAmount(entry.key) ~/ math.max(1, entry.value))
          .fold<int>(1 << 30, math.min);
      final batteryLimit = recipe.bioBatteryCost <= 0
          ? 1 << 30
          : bioBatteries ~/ recipe.bioBatteryCost;
      final energyLimit =
          recipe.energyCost <= 0 ? 1 << 30 : energyUnits ~/ recipe.energyCost;
      quantity = math.min(materialLimit, math.min(batteryLimit, energyLimit));
    }
    if (quantity <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Stock insuffisant pour démarrer cette fabrication.',
      );
    }
    final bioBatteryCost = recipe.bioBatteryCost * quantity;
    final craftEnergyCost =
        recipe.energyCost * quantity + (figurine == null ? 1 : 0);
    if (bioBatteries < bioBatteryCost) {
      return Zone0ActionResult(
        success: false,
        message: '$bioBatteryCost Bio-batteries requises.',
      );
    }
    if (energyUnits < craftEnergyCost) {
      return Zone0ActionResult(
        success: false,
        message: '$craftEnergyCost unité(s) d’énergie requise(s).',
      );
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
        success: false,
        message: 'P’TIPOTE occupé.',
      );
    }
    final totalCosts = buildingCraftCosts(
        'atelier',
        recipe.ingredients.map(
          (key, value) => MapEntry(key, value * quantity),
        ));
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
    bioBatteries -= bioBatteryCost;
    energyUnits -= craftEnergyCost;
    final speedBonus = craftSpeedBonus(figurine, atelierLevel);
    final unitSeconds = math.max(
      1,
      (Duration(minutes: recipe.durationMinutes).inSeconds *
              (1 - speedBonus) *
              buildingCraftDurationMultiplier('atelier'))
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
    if (!isBuildingOperational('cuisine')) {
      return const Zone0ActionResult(
          success: false,
          message: 'Cuisine hors service : remise en marche requise.');
    }
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
    if (quantity == -1 && figurine == null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le mode ∞ est réservé à un craft confié à un P’TIPOTE.',
      );
    }
    if (quantity == -1 && cuisineLevel < 4) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le mode ∞ se débloque au niveau 4 de la Cuisine.',
      );
    }
    if (quantity == 50 && cuisineLevel < 3) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le lot x50 se débloque au niveau 3 de la Cuisine.',
      );
    }
    if (quantity == -1) {
      final materialLimit = recipe.ingredients.entries
          .map((entry) => resourceAmount(entry.key) ~/ entry.value)
          .fold<int>(1 << 30, math.min);
      final batteryLimit = recipe.bioBatteryCost <= 0
          ? 1 << 30
          : bioBatteries ~/ recipe.bioBatteryCost;
      final energyLimit =
          recipe.energyCost <= 0 ? 1 << 30 : energyUnits ~/ recipe.energyCost;
      quantity = math.min(materialLimit, math.min(batteryLimit, energyLimit));
    }
    if (quantity <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Quantité invalide.',
      );
    }
    final totalCosts = buildingCraftCosts(
        'cuisine',
        recipe.ingredients.map(
          (key, value) => MapEntry(key, value * quantity),
        ));
    final output = <String, int>{
      recipe.resultItem: recipe.resultAmount * quantity,
    };
    final bioBatteryCost = recipe.bioBatteryCost * quantity;
    final craftEnergyCost =
        recipe.energyCost * quantity + (figurine == null ? 1 : 0);
    if (bioBatteries < bioBatteryCost) {
      return Zone0ActionResult(
        success: false,
        message: '$bioBatteryCost Bio-batteries requises.',
      );
    }
    if (energyUnits < craftEnergyCost) {
      return Zone0ActionResult(
        success: false,
        message: '$craftEnergyCost unité(s) d’énergie requise(s).',
      );
    }
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
    bioBatteries -= bioBatteryCost;
    energyUnits -= craftEnergyCost;
    final speedBonus = craftSpeedBonus(figurine, cuisineLevel);
    final unitSeconds = math.max(
      1,
      (Duration(minutes: recipe.durationMinutes).inSeconds *
              (1 - speedBonus) *
              buildingCraftDurationMultiplier('cuisine'))
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
    final buildingId =
        order.area == WorkshopOrderArea.kitchen ? 'cuisine' : 'atelier';
    // Une panne suspend le craft sans perdre ni ingrédients ni progression.
    if (!isBuildingOperational(buildingId)) return false;
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
      final craftXp = order.assignedPtipoteId == null
          ? 0
          : 5 + (order.requestedQuantity > 1 ? 5 : 0);
      if (craftXp > 0) addMissionXp(order.assignedPtipoteId!, craftXp);
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
              : 'Commande ${order.area == WorkshopOrderArea.kitchen ? 'Cuisine' : 'Atelier'} terminée : $displayName.${craftXp == 0 ? '' : ' +$craftXp XP pour ${order.assignedPtipoteName}.'}',
          sourceBuildingId:
              order.area == WorkshopOrderArea.kitchen ? 'cuisine' : 'atelier',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: order.assignedPtipoteName ?? 'Joueur',
          summary: tired
              ? '$displayName arrêté : P’TIPOTE fatigué.'
              : '$displayName × ${order.completedQuantity} terminé.${craftXp == 0 ? '' : ' +$craftXp XP.'}',
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
    if (!marketShopAccepts(primaryMarketShopId, resource)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce produit ne correspond pas à la boutique principale.',
      );
    }
    if (marketStock.length >= marketSlotLimit) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les trois emplacements sont occupés.',
      );
    }
    final moved = removeResource(
      resource,
      math.min(amount,
          math.min(resourceAmount(resource), marketStackLimitFor(resource))),
    );
    if (moved <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Stock insuffisant.',
      );
    }
    // Each placement is intentionally a distinct pile: identical products can
    // occupy several Market slots and are consumed pile by pile.
    marketStock.add(Zone0InventoryStack(
      id: 'market-${DateTime.now().microsecondsSinceEpoch}-${marketStock.length}',
      resource: resource,
      amount: moved,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$moved $resource placé au Marché.',
    );
  }

  Zone0ActionResult choosePrimaryMarketShop(String specialization) {
    return prepareMarketShopConstruction(specialization, primary: true);
  }

  /// La construction d'un magasin suit le même dépôt progressif que les
  /// bâtiments : sélectionner le type ne consomme rien immédiatement.
  Zone0ActionResult prepareMarketShopConstruction(
    String specialization, {
    required bool primary,
  }) {
    // Les anciennes sauvegardes n'avaient pas toujours leurs emplacements
    // spécialisés persistés. Les créer avant toute réservation garde le
    // compteur affiché et les emplacements réellement utilisables alignés.
    _migrateMarketShopSlots(DateTime.now());
    if (!const <String>{
      'restaurant',
      'home',
      'equipment',
      'ptibug',
      'wholesale',
    }.contains(specialization)) {
      return const Zone0ActionResult(
          success: false, message: 'Spécialisation invalide.');
    }
    if (marketShopConstructionOrder != null) {
      return const Zone0ActionResult(
          success: false, message: 'Un magasin est déjà en préparation.');
    }
    if (specialization == 'ptibug' && marketLevel < 4) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Magasin P’TIBUG est débloqué au Marché niveau 4.',
      );
    }
    if (primary) {
      if (primaryMarketShopChosen) {
        return const Zone0ActionResult(
            success: false, message: 'La boutique principale existe déjà.');
      }
    } else if (marketLevel < 2 || _playerBuildMarketShopSlot() == null) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun emplacement de magasin libre.');
    }
    marketShopConstructionOrder = MarketShopConstructionOrder(
      id: 'market-shop-build-${DateTime.now().microsecondsSinceEpoch}',
      specialization: specialization,
      isPrimary: primary,
    );
    if (!primary) {
      final slot = _playerBuildMarketShopSlot();
      if (slot != null) {
        slot
          ..status = MarketShopSlotStatus.reserved
          ..reservedByResidentId = null
          ..claimCandidateResidentId = null
          ..claimWarningStartedAt = null
          ..claimFinalizationAt = null;
      }
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Dépôt de construction du magasin ouvert.');
  }

  /// Une amélioration de magasin est également un chantier : aucun coût
  /// n'est prélevé avant que le joueur ait complété le dépôt et démarré les
  /// travaux. Cela évite le paiement instantané qui différait du Fablab.
  Zone0ActionResult prepareMarketShopUpgrade(String shopId) {
    if (marketShopConstructionOrder != null) {
      return const Zone0ActionResult(
          success: false, message: 'Un chantier de magasin est déjà en cours.');
    }
    final isPrimary = shopId == primaryMarketShopId;
    final currentLevel =
        isPrimary ? primaryMarketShopLevel : marketShopById(shopId)?.level;
    if (currentLevel == null || currentLevel >= 2) {
      return const Zone0ActionResult(
          success: false, message: 'Amélioration indisponible.');
    }
    final multiplier = marketConfig.shopUpgradeCostMultiplier;
    marketShopConstructionOrder = MarketShopConstructionOrder(
      id: 'market-shop-upgrade-${DateTime.now().microsecondsSinceEpoch}',
      specialization: isPrimary
          ? primaryMarketShopSpecialization
          : marketShopById(shopId)!.specialization,
      isPrimary: isPrimary,
      targetShopId: shopId,
      targetLevel: currentLevel + 1,
      requirements: marketConfig.shopConstructionCost.map(
        (resource, amount) => MapEntry(resource, amount * multiplier),
      ),
      requiredBioBatteries:
          marketConfig.shopConstructionBioBatteries * multiplier,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Dépôt d’amélioration du magasin ouvert.');
  }

  Zone0ActionResult depositMarketShopConstruction(
    String resource,
    int amount,
  ) {
    final order = marketShopConstructionOrder;
    if (order == null || order.isInProgress || amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt impossible.');
    }
    final required = order.requirements[resource] ?? 0;
    final missing = math.max(0, required - (order.deposits[resource] ?? 0));
    final moved = removeResource(resource, math.min(amount, missing));
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune ressource à déposer.');
    }
    order.deposits[resource] = (order.deposits[resource] ?? 0) + moved;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved $resource déposé(s).');
  }

  Zone0ActionResult withdrawMarketShopConstruction(String resource) {
    final order = marketShopConstructionOrder;
    final amount = order?.deposits[resource] ?? 0;
    if (order == null || order.isInProgress || amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Retrait impossible.');
    }
    final result = addResources(<String, int>{resource: amount});
    if (result.pending.isNotEmpty) {
      return const Zone0ActionResult(
          success: false, message: 'Inventaire plein : retrait impossible.');
    }
    order.deposits.remove(resource);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$amount $resource rendu à la Maison.');
  }

  Zone0ActionResult depositMarketShopConstructionBatteries(int amount) {
    final order = marketShopConstructionOrder;
    if (order == null || order.isInProgress || amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt impossible.');
    }
    final missing =
        math.max(0, order.requiredBioBatteries - order.depositedBioBatteries);
    final moved = math.min(amount, math.min(bioBatteries, missing));
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune Bio-batterie à déposer.');
    }
    bioBatteries -= moved;
    order.depositedBioBatteries += moved;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved Bio-batterie(s) déposée(s).');
  }

  Zone0ActionResult withdrawMarketShopConstructionBatteries() {
    final order = marketShopConstructionOrder;
    if (order == null ||
        order.isInProgress ||
        order.depositedBioBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Retrait impossible.');
    }
    bioBatteries += order.depositedBioBatteries;
    final returned = order.depositedBioBatteries;
    order.depositedBioBatteries = 0;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$returned Bio-batterie(s) rendue(s).');
  }

  bool get isMarketShopConstructionReady {
    final order = marketShopConstructionOrder;
    return order != null &&
        order.requirements.entries.every(
            (entry) => (order.deposits[entry.key] ?? 0) >= entry.value) &&
        order.depositedBioBatteries >= order.requiredBioBatteries;
  }

  Zone0ActionResult startMarketShopConstruction() {
    final order = marketShopConstructionOrder;
    if (order == null || order.isInProgress || !isMarketShopConstructionReady) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt de construction incomplet.');
    }
    final now = DateTime.now();
    order
      ..startedAt = now
      ..endsAt = now.add(Duration(
          minutes: marketConfig
              .constructionMinutesForLevel(order.targetLevel ?? 1)));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Travaux du magasin commencés.');
  }

  Zone0ActionResult cancelMarketShopConstruction() {
    final order = marketShopConstructionOrder;
    if (order == null) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun chantier de magasin à arrêter.');
    }
    if (!hasInventoryCapacityFor(order.deposits)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Inventaire plein : remboursement impossible.');
    }
    final returned = addResources(order.deposits);
    if (returned.hasPending) {
      return const Zone0ActionResult(
          success: false, message: 'Remboursement impossible.');
    }
    bioBatteries += order.depositedBioBatteries;
    if (!order.isPrimary && order.targetShopId == null) {
      for (final slot in marketShopSlots
          .where((slot) => slot.status == MarketShopSlotStatus.reserved)) {
        slot
          ..status = MarketShopSlotStatus.vacant
          ..vacantSince = DateTime.now();
      }
    }
    marketShopConstructionOrder = null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true,
        message: 'Chantier arrêté : tous les dépôts sont rendus.');
  }

  bool _resolveMarketShopConstruction(DateTime now) {
    final order = marketShopConstructionOrder;
    if (order == null || !order.isInProgress || order.endsAt!.isAfter(now)) {
      return false;
    }
    if (order.targetShopId != null) {
      if (order.isPrimary) {
        primaryMarketShopLevel = order.targetLevel ?? primaryMarketShopLevel;
      } else {
        final shop = marketShopById(order.targetShopId!);
        if (shop != null) shop.level = order.targetLevel ?? shop.level;
      }
    } else if (order.isPrimary) {
      primaryMarketShopSpecialization = order.specialization;
      primaryMarketShopChosen = true;
    } else {
      final slot = unlockedMarketShopSlots
              .where((item) =>
                  item.status == MarketShopSlotStatus.reserved &&
                  item.reservedByResidentId == null)
              .firstOrNull ??
          _vacantMarketShopSlot();
      if (slot == null) return false;
      final shop = MarketShop(
        id: 'shop-${now.microsecondsSinceEpoch}',
        specialization: order.specialization,
        slotId: slot.slotId,
        emergencyPink: order.emergencyPink,
      );
      marketShops.add(shop);
      slot
        ..shopId = shop.id
        ..status = MarketShopSlotStatus.playerOccupied
        ..vacantSince = null;
      firstFreeShopClaimed = true;
    }
    _migrateMarketShopSlots(now);
    marketShopConstructionOrder = null;
    reports.add(PtipoteMissionReport.system(
        message: 'Les travaux du magasin sont terminés.'));
    return true;
  }

  String? _residentShopCategoryForNeed(ResidentUncoveredNeed need) =>
      switch (need.category) {
        'meal' || 'drink' || 'sweetFood' || 'highEnergyFood' => 'restaurant',
        'clothing' ||
        'heatProtection' ||
        'rainProtection' ||
        'toxicProtection' ||
        'tools' ||
        'technicalEquipment' =>
          'equipment',
        'furniture' ||
        'decoration' ||
        'householdInstallation' ||
        'repairKit' =>
          'home',
        _ => null,
      };

  bool _marketCategoryViable(String category) {
    final stockOrRecipe = marketConfig.saleValues.keys.any((item) =>
        MarketShop(id: 'check', specialization: category).accepts(item));
    return stockOrRecipe;
  }

  String? _chooseResidentShopCategory() {
    const categories = <String>['restaurant', 'equipment', 'home'];
    // Une catégorie communautaire est unique : le deuxième comptoir de la
    // même spécialisation n'apporterait aucune nouvelle couverture.
    final residentCategories = marketShops
        .where((shop) =>
            shop.ownershipType == MarketShopOwnershipType.residentCommunity)
        .map((shop) => shop.specialization)
        .toSet();
    final covered = <String>{
      if (primaryMarketShopChosen) primaryMarketShopSpecialization,
      ...marketShops.map((shop) => shop.specialization),
    };
    final counts = <String, int>{
      for (final category in categories) category: 0,
    };
    for (final need
        in residentUncoveredNeeds.where((need) => need.resolvedAt == null)) {
      final category = _residentShopCategoryForNeed(need);
      if (category != null)
        counts[category] = (counts[category] ?? 0) + need.quantity;
    }
    final viable = categories
        .where((category) => !residentCategories.contains(category))
        .where(_marketCategoryViable)
        .toList();
    if (viable.isEmpty) return null;
    viable.sort((a, b) {
      final missing =
          (covered.contains(a) ? 0 : 1).compareTo(covered.contains(b) ? 0 : 1);
      if (missing != 0) return -missing;
      final demand = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return demand != 0 ? demand : a.compareTo(b);
    });
    return viable.first;
  }

  bool _resolveResidentShopClaims(DateTime current) {
    if (marketLevel < 2) return false;
    var changed = false;
    for (final slot in unlockedMarketShopSlots) {
      if (slot.status == MarketShopSlotStatus.pendingResidentClaim &&
          slot.claimFinalizationAt != null &&
          !current.isBefore(slot.claimFinalizationAt!)) {
        final resident = residents
            .where((entry) => entry.id == slot.claimCandidateResidentId)
            .firstOrNull;
        final category = _chooseResidentShopCategory();
        final hasShop =
            marketShops.any((shop) => shop.ownerResidentId == resident?.id);
        if (resident == null ||
            resident.primaryPassionId != ResidentPassion.trading.name ||
            hasShop ||
            category == null) {
          slot
            ..status = MarketShopSlotStatus.vacant
            ..claimCandidateResidentId = null
            ..claimWarningStartedAt = null
            ..claimFinalizationAt = null
            ..vacantSince = current;
          changed = true;
          continue;
        }
        final shop = MarketShop(
          id: 'resident-shop-${slot.slotId}',
          specialization: category,
          slotId: slot.slotId,
          ownershipType: MarketShopOwnershipType.residentCommunity,
          ownerResidentId: resident.id,
          managerResidentId: resident.id,
          shopPileBalance: marketConfig.residentShopReservePiles,
          serviceCapacity: marketConfig.residentShopServiceCapacity,
          ownershipStartedAt: current,
          ownershipLocked: true,
        );
        marketShops.add(shop);
        slot
          ..status = MarketShopSlotStatus.residentOccupied
          ..shopId = shop.id
          ..claimCandidateResidentId = null
          ..claimWarningStartedAt = null
          ..claimFinalizationAt = null
          ..vacantSince = null;
        final previousRole = communityRoleForResident(resident.id);
        if (previousRole != null) {
          previousRole
            ..status = CommunityRoleStatus.archived
            ..updatedAt = current;
        }
        resident
          ..ownedShopId = shop.id
          ..assignedBuildingId = 'market'
          ..activeCommunityRoleId = null
          ..commercialAssignmentStatus = 'shopOwner';
        reports.add(PtipoteMissionReport.system(
          message:
              '${resident.displayName} ouvre un commerce $category au Marché.',
        ));
        changed = true;
        continue;
      }
      if (slot.status != MarketShopSlotStatus.vacant ||
          slot.vacantSince == null) continue;
      if (current.difference(slot.vacantSince!).inDays <
          marketConfig.residentClaimVacancyDays) continue;
      final candidate = residents
          .where((resident) =>
              resident.isActive &&
              resident.primaryPassionId == ResidentPassion.trading.name &&
              resident.ownedShopId == null &&
              (communityRoleForResident(resident.id) == null ||
                  communityRoleForResident(resident.id)!.roleType ==
                      CommunityRoleType.marketCounter))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final category = _chooseResidentShopCategory();
      if (candidate.isEmpty || category == null) continue;
      slot
        ..status = MarketShopSlotStatus.pendingResidentClaim
        ..claimCandidateResidentId = candidate.first.id
        ..claimWarningStartedAt = current
        ..claimFinalizationAt = current.add(
          Duration(hours: marketConfig.residentClaimWarningHours),
        );
      reports.add(PtipoteMissionReport.system(
        message:
            '${candidate.first.displayName} souhaite ouvrir un commerce $category dans ${marketConfig.residentClaimWarningHours} h.',
      ));
      changed = true;
    }
    return changed;
  }

  /// Réinitialisation explicitement demandée par le joueur. Les stocks sont
  /// d'abord rendus à la Maison, puis toutes les boutiques et machines sont
  /// supprimées afin de recommencer avec le premier emplacement propre.
  Zone0ActionResult resetMarketShops() {
    final returned = <String, int>{};
    void collect(Iterable<Zone0InventoryStack> stacks) {
      for (final stack in stacks) {
        returned.update(
          stack.resource,
          (amount) => amount + stack.amount,
          ifAbsent: () => stack.amount,
        );
      }
    }

    collect(marketStock);
    collect(marketDistributor.stock);
    final pendingConstruction = marketShopConstructionOrder;
    if (pendingConstruction != null) {
      collect(pendingConstruction.deposits.entries.map(
        (entry) => Zone0InventoryStack(
          id: 'returned-${entry.key}',
          resource: entry.key,
          amount: entry.value,
        ),
      ));
      bioBatteries += pendingConstruction.depositedBioBatteries;
    }
    for (final shop in marketShops) {
      collect(shop.stock);
      collect(shop.distributor?.stock ?? const <Zone0InventoryStack>[]);
    }
    final result = returned.isEmpty ? null : addResources(returned);
    marketStock.clear();
    marketShops.removeWhere(
        (shop) => shop.ownershipType == MarketShopOwnershipType.player);
    primaryMarketShopSpecialization = 'general';
    primaryMarketShopChosen = false;
    primaryMarketShopLevel = 1;
    firstFreeShopClaimed = false;
    marketShopConstructionOrder = null;
    marketDistributor
      ..isBuilt = false
      ..level = 0
      ..energy = 0
      ..isBroken = false
      ..lastEnergyTickAt = null
      ..constructionStartedAt = null
      ..constructionEndsAt = null
      ..repairEndsAt = null
      ..repairStartedBy = null;
    marketDistributor.stock.clear();
    marketDistributor.constructionDeposits.clear();
    for (final slot in marketShopSlots) {
      final shop = marketShopById(slot.shopId ?? '');
      if (shop == null &&
          slot.status != MarketShopSlotStatus.residentOccupied) {
        slot
          ..shopId = null
          ..status = slot.marketLevelRequired <= marketLevel
              ? MarketShopSlotStatus.vacant
              : MarketShopSlotStatus.locked
          ..vacantSince = DateTime.now();
      }
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    final pending = result?.pending.values.fold<int>(0, (a, b) => a + b) ?? 0;
    return Zone0ActionResult(
      success: true,
      message: pending == 0
          ? 'Boutiques réinitialisées : les stocks sont revenus à la Maison.'
          : 'Boutiques réinitialisées. $pending objet(s) n’ont pas pu revenir faute de place.',
    );
  }

  /// Outil réservé aux comptes dev/admin par l'interface. Les figurines NFC
  /// ne sont jamais touchées : seules leur progression et leurs jauges Zone 0
  /// repartent de leur valeur initiale.
  Zone0ActionResult developerResetZone0Progress() {
    vitalityOverrides.clear();
    hungerOverrides.clear();
    restOverrides.clear();
    xpOverrides.clear();
    levelOverrides.clear();
    wellRestedRewardedIds.clear();
    manualRestingIds.clear();
    waitingForBedIds.clear();
    lastCuddleAt.clear();
    autoPreferenceOverrides.clear();
    missions.clear();
    towerMissions.clear();
    workshopOrders.clear();
    inventory.clear();
    pTibugs.clear();
    soldPTibugArchive.clear();
    pTibugTraitData.clear();
    pTibugDataCells.clear();
    pTibugModuleInstances.clear();
    pTibugModuleCraftOrders.clear();
    pTibugCapsules.clear();
    pTibugArmatures.clear();
    pTibugCultivationTanks.clear();
    pTibugCultivationOperations.clear();
    pTibugAspectMatrices.clear();
    pTibugAspectExtractionOrder = null;
    activePTibugPatterns.clear();
    unlockedPTibugModules.clear();
    sourcierPatternIds.clear();
    pTibugPatternProgress.clear();
    for (final family in PTibugDataFamily.values) {
      pTibugDataReserve[family] = 0;
    }
    pTibugModuleCapacityLevel = 0;
    plaineNurseryLevel = 0;
    pTibugTerritoryBuildings.clear();
    starterPTibugChoiceMade = false;
    firstCultivationTankGranted = false;
    residents.clear();
    residentHouses.clear();
    residentArrivalCandidates.clear();
    residentVisions.clear();
    householdRepairJobs.clear();
    communityRoleAssignments.clear();
    communityProductionBatches.clear();
    residentEconomicTransactions.clear();
    economicSettlementBatches.clear();
    residentUncoveredNeeds.clear();
    marketStock.clear();
    marketRequests.clear();
    marketRequestLog.clear();
    marketContracts.clear();
    marketShops.clear();
    marketShopSlots.clear();
    marketRestockRules.clear();
    marketShopConstructionOrder = null;
    residentCommunityShopConstructionOrder = null;
    lastResidentCommunityShopConstructionAt = null;
    marketDistributor
      ..isBuilt = false
      ..level = 0
      ..energy = 0
      ..isBroken = false
      ..stock.clear()
      ..constructionDeposits.clear()
      ..constructionStartedAt = null
      ..constructionEndsAt = null
      ..upgradeEndsAt = null
      ..repairEndsAt = null
      ..repairStartedBy = null
      ..upgradeTargetLevel = null;
    marketAssignedPtipoteId = null;
    marketAssignedPtipoteName = null;
    marketLevel = 0;
    primaryMarketShopChosen = false;
    primaryMarketShopSpecialization = 'general';
    primaryMarketShopLevel = 1;
    firstFreeShopClaimed = false;
    fablabLevel = 0;
    atelierLevel = 0;
    cuisineLevel = 0;
    recyclerLevel = 0;
    securityTowerLevel = 0;
    towerWeatherModuleInstalled = false;
    towerResearchModuleInstalled = false;
    houseLevel = 1;
    alcoveCapacity = 2;
    housingUnits = 0;
    housingCapacity = 0;
    currentPopulation = 0;
    bioBatteries = 0;
    energyUnits = 0;
    generatorOrganic = 0;
    generatorMineral = 0;
    generatorTotalProduced = 0;
    refugeSafety = lisiereForageConfig.refugeSafetyFallback;
    constructionProjects.clear();
    buildingViabilities.clear();
    reports.clear();
    notifyListeners();
    unawaited(saveInventoryToFirebase());
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Zone 0 réinitialisée. Les P’TIPOTES sont conservés.',
    );
  }

  Zone0ActionResult setMarketRestockRule(
    String resource, {
    required bool enabled,
    required int minimumToKeep,
  }) {
    if (!marketConfig.saleValues.containsKey(resource)) {
      return const Zone0ActionResult(
          success: false, message: 'Produit invalide.');
    }
    if (enabled) {
      marketRestockEnabledItems.add(resource);
      marketRestockMinimums[resource] = math.max(0, minimumToKeep);
      final existing = marketRestockRules
          .where((rule) =>
              rule.shopId == primaryMarketShopId &&
              rule.itemDefinitionId == resource)
          .firstOrNull;
      if (existing == null) {
        marketRestockRules.add(MarketRestockRule(
          ruleId: 'restock-$primaryMarketShopId-$resource',
          shopId: primaryMarketShopId,
          itemDefinitionId: resource,
          enabled: true,
          reserveMinimum: math.max(0, minimumToKeep),
          targetStock: marketConfig.residentShopStockTarget,
          maximumTransfer: marketConfig.stackQuantityLimit,
        ));
      } else {
        existing
          ..enabled = true
          ..reserveMinimum = math.max(0, minimumToKeep);
      }
    } else {
      marketRestockEnabledItems.remove(resource);
      marketRestockMinimums.remove(resource);
      for (final rule in marketRestockRules.where((rule) =>
          rule.shopId == primaryMarketShopId &&
          rule.itemDefinitionId == resource)) {
        rule.enabled = false;
      }
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Ordre de réapprovisionnement enregistré.');
  }

  Zone0ActionResult setMarketShopRestockRule({
    required String shopId,
    required String itemDefinitionId,
    required bool enabled,
    required int reserveMinimum,
    required int targetStock,
    required int maximumTransfer,
    int priority = 0,
  }) {
    if (!isMarketInformationPointUnlocked) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Point Information est débloqué au niveau ${marketConfig.informationPointLevel}.',
      );
    }
    if (!marketShopAccepts(shopId, itemDefinitionId)) {
      return const Zone0ActionResult(
          success: false, message: 'Produit incompatible avec ce magasin.');
    }
    final rule = marketRestockRules
        .where((item) =>
            item.shopId == shopId && item.itemDefinitionId == itemDefinitionId)
        .firstOrNull;
    if (rule == null) {
      marketRestockRules.add(MarketRestockRule(
        ruleId: 'restock-$shopId-$itemDefinitionId',
        shopId: shopId,
        itemDefinitionId: itemDefinitionId,
        enabled: enabled,
        reserveMinimum: math.max(0, reserveMinimum),
        targetStock: math.max(0, targetStock),
        maximumTransfer: math.max(1, maximumTransfer),
        priority: priority,
      ));
    } else {
      rule
        ..enabled = enabled
        ..reserveMinimum = math.max(0, reserveMinimum)
        ..targetStock = math.max(0, targetStock)
        ..maximumTransfer = math.max(1, maximumTransfer)
        ..priority = priority;
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Consigne de réapprovisionnement enregistrée.');
  }

  bool _resolveMarketInformationPoint(DateTime current) {
    if (!isMarketInformationPointUnlocked || marketAssignedPtipoteId == null) {
      return false;
    }
    var changed = false;
    final rules = marketRestockRules.where((rule) => rule.enabled).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (final rule in rules) {
      final stock = marketStockForShop(rule.shopId);
      if (stock == null ||
          !marketShopAccepts(rule.shopId, rule.itemDefinitionId)) {
        rule.lastStatus = 'invalidShop';
        continue;
      }
      final currentAmount = stock
          .where((stack) => stack.resource == rule.itemDefinitionId)
          .fold<int>(0, (sum, stack) => sum + stack.amount);
      final needed = math.max(0, rule.targetStock - currentAmount);
      final available = math.max(
          0, resourceAmount(rule.itemDefinitionId) - rule.reserveMinimum);
      final transfer =
          math.min(needed, math.min(available, rule.maximumTransfer));
      if (transfer <= 0 || stock.length >= marketShopStockLimit(rule.shopId)) {
        rule.lastStatus = available <= 0 ? 'awaitingStock' : 'targetReached';
        continue;
      }
      final moved = removeResource(rule.itemDefinitionId, transfer);
      if (moved <= 0) {
        rule.lastStatus = 'awaitingStock';
        continue;
      }
      stock.add(Zone0InventoryStack(
        id: 'point-info-${rule.ruleId}-${current.microsecondsSinceEpoch}',
        resource: rule.itemDefinitionId,
        amount: moved,
      ));
      rule.lastStatus = 'transferred';
      changed = true;
    }
    return changed;
  }

  Zone0ActionResult returnMarketStock(Zone0InventoryStack stack) {
    if (!marketStock.contains(stack)) {
      return const Zone0ActionResult(success: false, message: 'Stock absent.');
    }
    final result = addResources(<String, int>{stack.resource: stack.amount});
    final returned = stack.amount - (result.pending[stack.resource] ?? 0);
    stack.amount -= returned;
    if (stack.amount <= 0) marketStock.remove(stack);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: returned > 0,
      message: '$returned ${stack.resource} rendu à la Maison.',
    );
  }

  Zone0ActionResult transferToMarketShop(
    String shopId,
    String resource,
    int amount,
  ) {
    final shop = marketShopById(shopId);
    if (shop?.ownershipType == MarketShopOwnershipType.residentCommunity) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le comptoir communautaire n’utilise pas de stock.',
      );
    }
    final stock = marketStockForShop(shopId);
    if (stock == null || !marketShopAccepts(shopId, resource)) {
      return const Zone0ActionResult(
          success: false, message: 'Produit incompatible avec ce magasin.');
    }
    if (stock.length >= marketShopStockLimit(shopId)) {
      return const Zone0ActionResult(
          success: false, message: 'Stock du magasin complet.');
    }
    final isNurseryObject = _marketPTibugSpecies(resource) != null ||
        _isMarketMatrixResource(resource);
    final sourceItemIds = isNurseryObject
        ? _availableNurseryMarketItemIds(resource)
            .take(math.min(amount, marketConfig.stackQuantityLimit))
            .toList()
        : const <String>[];
    final moved = isNurseryObject
        ? sourceItemIds.length
        : removeResource(
            resource,
            math.min(
                amount,
                math.min(
                    resourceAmount(resource), marketConfig.stackQuantityLimit)),
          );
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Stock insuffisant.');
    }
    stock.add(Zone0InventoryStack(
      id: 'shop-$shopId-${DateTime.now().microsecondsSinceEpoch}-${stock.length}',
      resource: resource,
      amount: moved,
      sourceItemIds: sourceItemIds,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved $resource placé(s) dans ce magasin.');
  }

  Zone0ActionResult transferNurseryCapsuleToMarketShop(
    String shopId,
    String capsuleId,
  ) {
    final capsule =
        pTibugCapsules.where((item) => item.id == capsuleId).firstOrNull;
    if (capsule == null ||
        capsule.status != CertifiedPTibugCapsuleStatus.certified ||
        _nurseryMarketReservedIds.contains(capsuleId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Capsule P’TIBUG indisponible.',
      );
    }
    final resource = marketItemForCertifiedCapsule(capsule.species);
    final shop = marketShopById(shopId);
    final stock = marketStockForShop(shopId);
    if (shop?.ownershipType == MarketShopOwnershipType.residentCommunity) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le comptoir communautaire n’utilise pas de stock.',
      );
    }
    if (stock == null || !marketShopAccepts(shopId, resource)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Capsule incompatible avec ce magasin.',
      );
    }
    if (stock.length >= marketShopStockLimit(shopId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Stock du magasin complet.',
      );
    }
    stock.add(Zone0InventoryStack(
      id: 'shop-$shopId-capsule-${DateTime.now().microsecondsSinceEpoch}',
      resource: resource,
      amount: 1,
      sourceItemIds: <String>[capsule.id],
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${capsule.displayName} placé(e) dans ce magasin.',
    );
  }

  Zone0ActionResult transferNurseryMatrixToMarketShop(
    String shopId,
    String matrixId,
  ) {
    final matrix =
        pTibugAspectMatrices.where((item) => item.id == matrixId).firstOrNull;
    if (matrix == null || _nurseryMarketReservedIds.contains(matrixId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Matrice d’aspect indisponible.',
      );
    }
    final resource = marketMatrixItemForSpecies(matrix.species);
    final shop = marketShopById(shopId);
    final stock = marketStockForShop(shopId);
    if (shop?.ownershipType == MarketShopOwnershipType.residentCommunity) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le comptoir communautaire n’utilise pas de stock.',
      );
    }
    if (stock == null || !marketShopAccepts(shopId, resource)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Matrice incompatible avec ce magasin.',
      );
    }
    if (stock.length >= marketShopStockLimit(shopId)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Stock du magasin complet.',
      );
    }
    stock.add(Zone0InventoryStack(
      id: 'shop-$shopId-matrix-${DateTime.now().microsecondsSinceEpoch}',
      resource: resource,
      amount: 1,
      sourceItemIds: <String>[matrix.id],
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Matrice ${matrix.sourceDisplayName} placée dans ce magasin.',
    );
  }

  Zone0ActionResult returnMarketShopStock(
      String shopId, Zone0InventoryStack stack) {
    final stock = marketStockForShop(shopId);
    if (stock == null || !stock.contains(stack)) {
      return const Zone0ActionResult(success: false, message: 'Stock absent.');
    }
    final isNurseryObject = _marketPTibugSpecies(stack.resource) != null ||
        _isMarketMatrixResource(stack.resource);
    final result = isNurseryObject
        ? const InventoryAddResult(addedAny: true, pending: <String, int>{})
        : addResources(<String, int>{stack.resource: stack.amount});
    final returned = isNurseryObject
        ? stack.amount
        : stack.amount - (result.pending[stack.resource] ?? 0);
    stack.amount -= returned;
    if (stack.amount <= 0) stock.remove(stack);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: returned > 0,
        message: '$returned ${stack.resource} rendu à la Maison.');
  }

  int marketStockAmount(String resource) => marketStock
      .where((stack) => stack.resource == resource)
      .fold(0, (sum, stack) => sum + stack.amount);

  int marketShopStockAmount(String shopId, String resource) {
    return (marketStockForShop(shopId) ?? const <Zone0InventoryStack>[])
        .where((stack) => stack.resource == resource)
        .fold(0, (sum, stack) => sum + stack.amount);
  }

  /// Uses an already started pile first, then the next matching one. This is
  /// the single stock transition used by manual sales, automation and contracts.
  void _consumeNurserySourceItems(Zone0InventoryStack stack, int amount) {
    if (stack.sourceItemIds.isEmpty || amount <= 0) return;
    final ids = stack.sourceItemIds.take(amount).toList();
    if (_marketPTibugSpecies(stack.resource) != null) {
      pTibugCapsules.removeWhere((capsule) => ids.contains(capsule.id));
    } else if (_isMarketMatrixResource(stack.resource)) {
      pTibugAspectMatrices.removeWhere((matrix) => ids.contains(matrix.id));
    }
    stack.sourceItemIds.removeRange(0, ids.length);
  }

  void _consumeMarketStack(Zone0InventoryStack stack, int amount) {
    _consumeNurserySourceItems(stack, amount);
    stack.amount -= amount;
  }

  bool _consumeMarketStock(String resource, int amount) {
    if (amount <= 0 || marketStockAmount(resource) < amount) return false;
    var remaining = amount;
    final matching = marketStock
        .where((stack) => stack.resource == resource)
        .toList()
      ..sort((a, b) => a.amount.compareTo(b.amount));
    for (final stack in matching) {
      if (remaining <= 0) break;
      final used = math.min(remaining, stack.amount);
      _consumeMarketStack(stack, used);
      remaining -= used;
      if (stack.amount <= 0) marketStock.remove(stack);
    }
    return remaining == 0;
  }

  bool _consumeMarketShopStock(String shopId, String resource, int amount) {
    if (shopId == primaryMarketShopId)
      return _consumeMarketStock(resource, amount);
    final stock = marketStockForShop(shopId);
    if (stock == null || marketShopStockAmount(shopId, resource) < amount)
      return false;
    var remaining = amount;
    for (final stack
        in stock.where((stack) => stack.resource == resource).toList()) {
      final used = math.min(remaining, stack.amount);
      _consumeMarketStack(stack, used);
      remaining -= used;
      if (stack.amount <= 0) stock.remove(stack);
      if (remaining <= 0) break;
    }
    return remaining == 0;
  }

  /// Le Point info n'est pas attaché à une seule boutique : il peut préparer
  /// une demande depuis n'importe quel stock compatible du Marché.
  bool _consumeAnyMarketShopStock(String resource, int amount) {
    final shopIds = <String>[
      ...marketShops.where((shop) => !shop.isPrimary).map((shop) => shop.id),
      primaryMarketShopId,
    ];
    for (final shopId in shopIds) {
      if (_consumeMarketShopStock(shopId, resource, amount)) return true;
    }
    return false;
  }

  Zone0ActionResult sellMarketRequest(
    MarketCustomerRequest request, {
    MarketRequestResponder responder = MarketRequestResponder.player,
    bool allowAnyShop = false,
  }) {
    if (!marketRequests.contains(request) || !request.isOpen) {
      return const Zone0ActionResult(
          success: false, message: 'Demande indisponible.');
    }
    final resident = request.customerName == null
        ? null
        : residents
            .where((entry) => entry.displayName == request.customerName)
            .firstOrNull;
    if (resident != null &&
        _isFinishedResidentProduct(request.requestedItemId)) {
      final category =
          _residentItemCategory(request.requestedItemId) ?? 'finished';
      final house = residentHouseForId(resident.houseId);
      if ((house == null ||
              !_isHouseholdFinishedItem(request.requestedItemId)) &&
          !_canResidentStoreOwnedItems(
            resident,
            request.requestedItemId,
            category,
            request.requestedQuantity,
          )) {
        return Zone0ActionResult(
          success: false,
          message:
              'Inventaire de ${resident.displayName} plein (${residentInventorySlotsFor(resident)} cases).',
        );
      }
    }
    final sold = allowAnyShop
        ? _consumeAnyMarketShopStock(
            request.requestedItemId, request.requestedQuantity)
        : _consumeMarketShopStock(
            request.shopId, request.requestedItemId, request.requestedQuantity);
    if (!sold) {
      return const Zone0ActionResult(
          success: false, message: 'Stock du Marché insuffisant.');
    }
    // Une vente à un habitant transfère toujours l'objet physique vers son
    // bon stockage. Les biens du foyer restent dans la Maison, les objets
    // personnels rejoignent le sac de l'habitant.
    if (resident != null &&
        _isFinishedResidentProduct(request.requestedItemId)) {
      final category =
          _residentItemCategory(request.requestedItemId) ?? 'finished';
      final house = residentHouseForId(resident.houseId);
      if (house != null && _isHouseholdFinishedItem(request.requestedItemId)) {
        _addHouseholdInventoryItem(
            house, request.requestedItemId, request.requestedQuantity);
        if (request.requestedItemId == 'Kit de réparation domestique') {
          _applyPurchasedHouseholdRepairKit(
            house,
            DateTime.now(),
            requesterName: resident.displayName,
          );
        }
      } else {
        _addResidentOwnedItems(
          resident,
          request.requestedItemId,
          category,
          request.requestedQuantity,
          DateTime.now(),
          sourceTransactionId: request.id,
        );
      }
    }
    _creditMarketBioPiles(request.rewardBioPiles);
    if (responder == MarketRequestResponder.ptipote) {
      marketBioPilesEarnedThisAssignment += request.rewardBioPiles;
      marketArticlesSoldThisAssignment += request.requestedQuantity;
      if (marketAssignedPtipoteId != null) {
        addMissionXp(marketAssignedPtipoteId!, 5);
        marketXpEarnedThisAssignment += 5;
      }
    }
    campWellbeing = math.min(100, campWellbeing + request.rewardWellbeing);
    request.status = MarketRequestStatus.completed;
    _recordMarketRequestOutcome(
      request,
      completedAt: DateTime.now(),
      responder: responder,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Vente réalisée : ${request.requestedQuantity} ${request.requestedItemId} · +${request.rewardBioPiles} bio-pile(s).',
    );
  }

  Zone0ActionResult assignToMarket(PtipoteFigurine figurine) {
    if (!isMarketBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Marché non construit.',
      );
    }
    if (!isMarketInformationPointUnlocked) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Point Information est débloqué au niveau ${marketConfig.informationPointLevel} du Marché.',
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
    _synchronizePtipoteProgress(figurine);
    marketAssignedPtipoteId = figurine.id;
    marketAssignedPtipoteName = figurine.displayName;
    marketLastWorkTickAt = DateTime.now();
    marketLastXpTickAt = marketLastWorkTickAt;
    marketAssignedAt = marketLastWorkTickAt;
    marketXpEarnedThisAssignment = 0;
    marketBioPilesEarnedThisAssignment = 0;
    marketArticlesSoldThisAssignment = 0;
    marketDistributorsRepairedThisAssignment = 0;
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
    final xp = marketXpEarnedThisAssignment;
    final vitality = vitalityOverrides[id] ?? ptipoteStatsConfig.maxVitality;
    final hunger = hungerOverrides[id] ?? ptipoteStatsConfig.baseHunger;
    final rest = restOverrides[id] ?? ptipoteStatsConfig.maxRest;
    final elapsed =
        DateTime.now().difference(marketAssignedAt ?? DateTime.now());
    final minutes = math.max(0, elapsed.inMinutes);
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final durationLabel = hours > 0
        ? '$hours h ${remainingMinutes.toString().padLeft(2, '0')} min'
        : '$remainingMinutes min';
    final earnedPiles = marketBioPilesEarnedThisAssignment;
    final articles = marketArticlesSoldThisAssignment;
    final repaired = marketDistributorsRepairedThisAssignment;
    marketAssignedPtipoteId = null;
    marketAssignedPtipoteName = null;
    marketLastWorkTickAt = null;
    marketLastXpTickAt = null;
    marketAssignedAt = null;
    marketXpEarnedThisAssignment = 0;
    marketBioPilesEarnedThisAssignment = 0;
    marketArticlesSoldThisAssignment = 0;
    marketDistributorsRepairedThisAssignment = 0;
    reports.add(PtipoteMissionReport.system(
      message:
          '$name rentre du Marché : +$xp XP, $articles article(s) vendu(s), $repaired distributeur(s) réparé(s).',
      sourceBuildingId: 'market',
      subject: 'Bilan du Marché',
      concerned: name,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '$name rentre du Marché après $durationLabel · +$earnedPiles bio-pile(s) · +$xp XP · $articles article(s) vendu(s) · $repaired distributeur(s) réparé(s) · énergie $vitality/${ptipoteStatsConfig.maxVitality} · faim $hunger/${ptipoteStatsConfig.baseHunger} · repos $rest/${ptipoteStatsConfig.maxRest}.',
    );
  }

  bool resolveMarket({DateTime? now}) {
    final current = now ?? DateTime.now();
    _migrateMarketShopSlots(current);
    var changed = _resolveMarketShopConstruction(current);
    if (!isMarketBuilt || !isBuildingOperational('market')) return changed;
    // Les commerces habitants sont déclenchés par les demandes expirées,
    // pas par le simple temps de vacance d'un emplacement.
    changed = _resolveMerchantSchedule(current) || changed;
    // Migration du cycle de vente V1 : aucun stock ne doit plus être vendu
    // sans demande habitant. La valeur est ensuite sauvegardée à null.
    if (marketNextSaleAt != null || marketValueRemainder != 0) {
      marketNextSaleAt = null;
      marketValueRemainder = 0;
      changed = true;
    }
    // Older builds kept requests but did not always create their Book entry.
    // Backfill every still-persisted request once, without inventing history
    // for requests that had already been deleted by those builds.
    final logsBeforeBackfill = marketRequestLog.length;
    for (final request in marketRequests) {
      _ensureMarketRequestLog(request);
    }
    changed = changed || logsBeforeBackfill != marketRequestLog.length;
    // Existing saves did not have a scheduled request. A first release of
    // the feature could also persist a future date without recording any
    // request. Start both cases immediately so the player is never left with
    // an empty Book merely because the market stock is empty.
    if (marketNextRequestAt == null ||
        (marketLevel >= 3 && marketRequestLog.isEmpty)) {
      marketNextRequestAt = current;
    }
    var requestGuard = 0;
    while (marketNextRequestAt != null &&
        !current.isBefore(marketNextRequestAt!) &&
        requestGuard++ < 48) {
      final createdAt = marketNextRequestAt!;
      _createMarketRequest(createdAt);
      marketNextRequestAt = createdAt.add(_marketRequestInterval());
      changed = true;
    }
    final historyCutoff = current.subtract(const Duration(hours: 24));
    final beforeRequests = marketRequests.length;
    marketRequests.removeWhere((request) =>
        !request.isOpen && request.customerReturnTime.isBefore(historyCutoff));
    final beforeLog = marketRequestLog.length;
    marketRequestLog
        .removeWhere((entry) => entry.createdAt.isBefore(historyCutoff));
    changed = changed ||
        beforeRequests != marketRequests.length ||
        beforeLog != marketRequestLog.length;
    if (marketAssignedPtipoteId != null && isMarketInformationPointUnlocked) {
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
      marketLastXpTickAt ??= current;
      final xpPeriods = current.difference(marketLastXpTickAt!).inMinutes ~/ 60;
      if (xpPeriods > 0 && marketAssignedPtipoteId != null) {
        final xpGain = xpPeriods;
        addMissionXp(marketAssignedPtipoteId!, xpGain);
        marketXpEarnedThisAssignment += xpGain;
        marketLastXpTickAt =
            marketLastXpTickAt!.add(Duration(hours: xpPeriods));
        changed = true;
      }
    }
    // Le stock n'est jamais consommé de lui-même. Les demandes ouvertes sont
    // le seul chemin de vente, y compris pour le Distributeur.
    // La machine a toujours priorité : elle se remplit depuis son magasin et
    // répond après une minute avant que le P’TIPOTE prenne le relais.
    changed = _resolveMarketDistributor(current) || changed;
    changed = _resolveMarketInformationPoint(current) || changed;
    // Le P’TIPOTE du Point info conserve une fenêtre de trois minutes : le
    // joueur peut donc répondre immédiatement et le Distributeur en une minute.
    if (marketAssignedPtipoteId != null) {
      for (final request
          in marketRequests.where((item) => item.isOpen).toList()) {
        if (current
            .isBefore(request.createdAt.add(const Duration(minutes: 3)))) {
          continue;
        }
        final result = sellMarketRequest(
          request,
          responder: MarketRequestResponder.ptipote,
          allowAnyShop: true,
        );
        changed = changed || result.success;
      }
    }
    for (final request
        in marketRequests.where((item) => item.isOpen).toList()) {
      if (!current.isBefore(request.customerReturnTime)) {
        request.status = MarketRequestStatus.expired;
        _recordMarketRequestOutcome(request, completedAt: current);
        changed = true;
      }
    }
    changed = _maybeStartEmergencyCounterShop(current) || changed;
    changed = _resolveCommunityCounterSales(current) || changed;
    changed = _resolveMarketContracts(current) || changed;
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  bool _maybeStartEmergencyCounterShop(DateTime now) {
    if (residentCommunityShopConstructionOrder != null) return false;
    if (lastResidentCommunityShopConstructionAt != null &&
        now.difference(lastResidentCommunityShopConstructionAt!).inDays < 3) {
      return false;
    }
    final expiredByItem = <String, int>{};
    for (final entry in marketRequestLog.where((entry) =>
        entry.status == MarketRequestStatus.expired &&
        now.difference(entry.resolvedAt ?? entry.deadline).inHours <= 24)) {
      expiredByItem.update(entry.requestedItemId, (count) => count + 1,
          ifAbsent: () => 1);
    }
    final item = expiredByItem.entries
        .where((entry) => entry.value >= 10)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    if (item.isEmpty) return false;
    final slot = _vacantMarketShopSlot();
    if (slot == null) return false;
    const categories = <String>['restaurant', 'equipment', 'home'];
    final category = categories.firstWhere(
      (candidate) => MarketShop(id: 'counter-check', specialization: candidate)
          .accepts(item.first),
      orElse: () => '',
    );
    if (category.isEmpty) return false;
    // Un seul comptoir communautaire par spécialisation : deux magasins du
    // foyer roses ne peuvent plus occuper deux emplacements.
    if (marketShops.any((shop) =>
        shop.ownershipType == MarketShopOwnershipType.residentCommunity &&
        shop.specialization == category)) {
      return false;
    }
    slot
      ..status = MarketShopSlotStatus.reserved
      ..reservedByResidentId = 'community-counter'
      ..vacantSince = null;
    residentCommunityShopConstructionOrder = MarketShopConstructionOrder(
      id: 'community-counter-${now.microsecondsSinceEpoch}',
      specialization: category,
      isPrimary: false,
      requirements: const <String, int>{},
      requiredBioBatteries: 0,
      emergencyPink: true,
      startedAt: now,
      endsAt: now.add(const Duration(hours: 48)),
    );
    reports.add(PtipoteMissionReport.system(
      message:
          'Suite à un manque de produits, un habitant a l’autorisation de construire un magasin $category. Si rien ne change, il sera construit dans 2 jours.',
      sourceBuildingId: 'market',
      subject: 'Magasin communautaire',
    ));
    return true;
  }

  bool _resolveCommunityCounterSales(DateTime current) {
    final order = residentCommunityShopConstructionOrder;
    if (order != null) {
      final missingStillActive = marketRequestLog
              .where((entry) =>
                  entry.status == MarketRequestStatus.expired &&
                  current
                          .difference(entry.resolvedAt ?? entry.deadline)
                          .inHours <=
                      24 &&
                  MarketShop(
                          id: 'counter-check',
                          specialization: order.specialization)
                      .accepts(entry.requestedItemId))
              .length >=
          10;
      if (!missingStillActive) {
        final reserved = unlockedMarketShopSlots
            .where((slot) =>
                slot.status == MarketShopSlotStatus.reserved &&
                slot.reservedByResidentId == 'community-counter')
            .firstOrNull;
        if (reserved != null) {
          reserved
            ..status = MarketShopSlotStatus.vacant
            ..reservedByResidentId = null
            ..vacantSince = current;
        }
        residentCommunityShopConstructionOrder = null;
        reports.add(PtipoteMissionReport.system(
          message:
              'Le manque de produits a été résolu : le chantier communautaire est annulé.',
          sourceBuildingId: 'market',
          subject: 'Magasin communautaire',
        ));
        return true;
      }
      if (order.endsAt != null && !current.isBefore(order.endsAt!)) {
        final slot = unlockedMarketShopSlots
                .where((slot) =>
                    slot.status == MarketShopSlotStatus.reserved &&
                    slot.reservedByResidentId == 'community-counter')
                .firstOrNull ??
            _vacantMarketShopSlot();
        if (slot != null) {
          final shop = MarketShop(
            id: 'community-counter-${current.microsecondsSinceEpoch}',
            specialization: order.specialization,
            slotId: slot.slotId,
            ownershipType: MarketShopOwnershipType.residentCommunity,
            emergencyPink: true,
            serviceCapacity: 1,
          );
          marketShops.add(shop);
          slot
            ..shopId = shop.id
            ..status = MarketShopSlotStatus.residentOccupied
            ..reservedByResidentId = null
            ..vacantSince = null;
          lastResidentCommunityShopConstructionAt = current;
          residentCommunityShopConstructionOrder = null;
          reports.add(PtipoteMissionReport.system(
            message:
                'Le magasin communautaire ${order.specialization} est construit.',
            sourceBuildingId: 'market',
            subject: 'Magasin communautaire',
          ));
          return true;
        }
      }
      return false;
    }
    final counterResident = communityRoleAssignments
        .where((role) =>
            role.roleType == CommunityRoleType.marketCounter && role.isActive)
        .map((role) => residents
            .where((resident) => resident.id == role.residentId)
            .firstOrNull)
        .whereType<Zone0Resident>()
        .firstOrNull;
    if (counterResident == null || !_hasCommunityCounterProductionLine()) {
      return false;
    }
    var changed = false;
    for (final shop in marketShops.where((shop) =>
        shop.ownershipType == MarketShopOwnershipType.residentCommunity)) {
      final previous = shop.lastCommunityCounterSaleAt ??
          current.subtract(const Duration(minutes: 10));
      if (current.difference(previous).inMinutes < 10) continue;
      final request = marketRequests
          .where((item) => item.isOpen && shop.accepts(item.requestedItemId))
          .firstOrNull;
      if (request == null) continue;
      // Les comptoirs roses n'ont volontairement pas de stock ni de
      // distributeur. Leur ligne de production habitante livre une demande
      // toutes les dix minutes lorsque Cuisine, Atelier, Lisière et Marché
      // sont effectivement tenus.
      _creditMarketBioPiles(request.rewardBioPiles);
      request.status = MarketRequestStatus.completed;
      _recordMarketRequestOutcome(
        request,
        completedAt: current,
        responder: MarketRequestResponder.ptipote,
      );
      shop.lastCommunityCounterSaleAt = current;
      final log = marketRequestLog
          .where((entry) => entry.requestId == request.id)
          .firstOrNull;
      if (log != null) {
        log.responderDisplayName =
            '${counterResident.displayName} · depuis le comptoir communautaire';
      }
      changed = true;
    }
    return changed;
  }

  bool _hasCommunityCounterProductionLine() => <CommunityRoleType>{
        CommunityRoleType.marketCounter,
        CommunityRoleType.kitchenCook,
        CommunityRoleType.fablabMaker,
        CommunityRoleType.lisiereObserver,
      }.every((role) =>
          activeCommunityRoles.any((entry) => entry.roleType == role));

  void _createMarketRequest(DateTime now) {
    final entries = marketConfig.saleValues.keys
        .where((item) => _isFinishedResidentProduct(item))
        .where((item) =>
            marketLevel >= marketConfig.requestMinimumMarketLevelFor(item))
        .where((item) =>
            marketShopAccepts(primaryMarketShopId, item) ||
            marketShops.any((shop) => !shop.isPrimary && shop.accepts(item)))
        .toSet()
        .toList();
    if (entries.isEmpty) return;
    final weather = _marketWeatherRequestType();
    final weatherItems = weather == null
        ? const <String>[]
        : marketConfig.weatherRequestItems[weather.name] ?? const <String>[];
    final weatherActiveCount = marketRequests
        .where((request) => request.isOpen && request.weatherType != null)
        .length;
    final weatherCap = residents.where((resident) => resident.isActive).isEmpty
        ? 0
        : math.max(
            1,
            residents.where((resident) => resident.isActive).length ~/
                math.max(1, marketConfig.weatherRequestPopulationDivisor),
          );
    final useWeather = weather != null &&
        weatherItems.isNotEmpty &&
        weatherActiveCount < weatherCap &&
        _random.nextInt(100) < marketConfig.weatherRequestRatioPercent;
    final eligibleWeatherItems =
        weatherItems.where(entries.contains).toList(growable: false);
    final item = useWeather && eligibleWeatherItems.isNotEmpty
        ? eligibleWeatherItems[_random.nextInt(eligibleWeatherItems.length)]
        : _pickMarketRequestItem(entries);
    // Une boutique spécialisée est servie avant la boutique principale :
    // celle-ci reste généraliste, mais ne doit pas absorber toutes les
    // demandes dès qu'un commerce spécialisé existe.
    final specialist = marketShops
        .where((shop) => !shop.isPrimary && shop.accepts(item))
        .firstOrNull;
    final shopId = specialist?.id ?? primaryMarketShopId;
    final activeResidents = residents
        .where((resident) => resident.isActive)
        .toList(growable: false);
    final request = MarketCustomerRequest(
      id: 'request-${now.microsecondsSinceEpoch}-${marketRequests.length}',
      requestedItemId: item,
      requestedQuantity: 1,
      rewardBioPiles: _marketPriceInBioPiles(item, shopId: shopId),
      rewardWellbeing: 1,
      createdAt: now,
      customerReturnTime: now.add(_randomMarketReturnDelay()),
      distributorEligibleAt: now.add(
        Duration(minutes: marketConfig.distributorResponseDelayMinutes),
      ),
      status: MarketRequestStatus.noted,
      customerName: activeResidents.isEmpty
          ? null
          : activeResidents[_random.nextInt(activeResidents.length)]
              .displayName,
      weatherType:
          useWeather && eligibleWeatherItems.isNotEmpty ? weather.name : null,
      shopId: shopId,
    );
    marketRequests.add(request);
    _ensureMarketRequestLog(request);
  }

  int get marketEconomicActivityPercent {
    final wellbeing = (campWellbeing.clamp(0, 100) /
            100 *
            marketConfig.economicActivityWellbeingMaxPercent)
        .round();
    final heart = math.min(
      marketConfig.economicActivityHeartLevelCapPercent,
      _lastKnownCampHeartLevel * marketConfig.economicActivityHeartLevelPercent,
    );
    final market = math.min(
      marketConfig.economicActivityMarketLevelCapPercent,
      marketLevel * marketConfig.economicActivityMarketLevelPercent,
    );
    final weather = activeGlobalWeatherEvent == null
        ? 0
        : marketConfig.economicActivityWeatherPercent[
                activeGlobalWeatherEvent!.intensity.name] ??
            0;
    return (wellbeing + heart + market + weather).clamp(0, 100);
  }

  Duration _marketRequestInterval() {
    final basePerHour = marketConfig.requestBasePerHourForLevel(marketLevel);
    if (basePerHour <= 0) return const Duration(hours: 1);
    final boostedPerHour =
        basePerHour * (1 + marketEconomicActivityPercent / 100);
    final rawMinutes = 60 / boostedPerHour;
    final jitterMin = marketConfig.requestJitterMinPercent / 100;
    final jitterMax = marketConfig.requestJitterMaxPercent / 100;
    final amplitude =
        jitterMin + _random.nextDouble() * (jitterMax - jitterMin);
    final signedJitter = _random.nextBool() ? amplitude : -amplitude;
    return Duration(
      minutes: math.max(
        marketConfig.requestMinimumSpacingMinutes,
        (rawMinutes * (1 + signedJitter)).round(),
      ),
    );
  }

  String _pickMarketRequestItem(List<String> entries) {
    final byCategory = <String, List<String>>{};
    for (final item in entries) {
      byCategory
          .putIfAbsent(_marketItemCategory(item), () => <String>[])
          .add(item);
    }
    final availableWeights = <String, int>{
      for (final entry in marketConfig.requestCategoryWeights.entries)
        if ((byCategory[entry.key] ?? const <String>[]).isNotEmpty)
          entry.key: entry.value,
    };
    final total =
        availableWeights.values.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return entries[_random.nextInt(entries.length)];
    var pick = _random.nextInt(total);
    for (final entry in availableWeights.entries) {
      pick -= entry.value;
      if (pick < 0) {
        final items = byCategory[entry.key]!;
        return items[_random.nextInt(items.length)];
      }
    }
    return entries.first;
  }

  String _marketItemCategory(String item) {
    if (craftConfig.recipes
        .any((recipe) => recipe.resultItem == item && recipe.isConsumable)) {
      return 'food';
    }
    if (item.contains('Tenue') ||
        const <String>{
          'Couche imperméabilisante',
          'Réflecteur thermique',
          'Filtre personnel',
        }.contains(item)) {
      return 'clothing';
    }
    if (item.contains('Meuble')) return 'furniture';
    return 'materials';
  }

  int _marketPriceInBioPiles(String item, {required String shopId}) {
    final base = math.max(1, marketConfig.salePriceInBioPiles(item));
    // Le malus ne concerne que l'ancien magasin généraliste. Dès que le
    // joueur a choisi une spécialisation, il vend au même tarif qu'un magasin
    // spécialisé et l'interface ne l'affiche plus comme un rabais permanent.
    if (shopId == primaryMarketShopId && !primaryMarketShopChosen) {
      return math.max(
          1,
          (base * (100 - marketConfig.baseStorePricePenaltyPercent) / 100)
              .round());
    }
    return math.max(
        1,
        (base * (100 + marketConfig.specializedShopGainBonusPercent) / 100)
            .round());
  }

  void _creditMarketBioPiles(int amount) {
    bioPiles += math.max(0, amount);
    final converted = bioPiles ~/ 100;
    if (converted > 0) {
      bioPiles -= converted * 100;
      bioBatteries += converted;
      marketBioBatteriesEarned += converted;
      _resolveEnergyCoreMilestones();
    }
  }

  TowerWeatherType? _marketWeatherRequestType() {
    final upcoming = nextGlobalWeatherEvent;
    if (upcoming != null &&
        upcoming.status == GlobalWeatherEventStatus.announced &&
        upcoming.type != TowerWeatherType.calm) {
      return upcoming.type;
    }
    final active = activeGlobalWeatherEvent;
    if (active != null &&
        active.status == GlobalWeatherEventStatus.active &&
        active.type != TowerWeatherType.calm) {
      return active.type;
    }
    return null;
  }

  void _recordMarketRequestOutcome(
    MarketCustomerRequest request, {
    required DateTime completedAt,
    MarketRequestResponder? responder,
  }) {
    _ensureMarketRequestLog(request);
    final entry = marketRequestLog
        .where((item) => item.requestId == request.id)
        .firstOrNull;
    if (entry == null) return;
    entry
      ..status = request.status
      ..resolvedAt = completedAt
      ..rewardBioBatteries = request.status == MarketRequestStatus.completed
          ? request.rewardBioPiles
          : 0
      ..responder = responder
      ..responderDisplayName = responder == MarketRequestResponder.ptipote
          ? marketAssignedPtipoteName
          : null;
  }

  void _ensureMarketRequestLog(MarketCustomerRequest request) {
    final shouldRecord = marketLevel >= 3 ||
        (marketLevel >= 2 && marketAssignedPtipoteId != null);
    if (!shouldRecord ||
        marketRequestLog.any((entry) => entry.requestId == request.id)) {
      return;
    }
    marketRequestLog.add(MarketRequestLogEntry.fromRequest(request));
  }

  void _recordDistributorIncident(String message, DateTime at) {
    marketRequestLog.add(MarketRequestLogEntry(
      requestId:
          'distributor-${at.microsecondsSinceEpoch}-${marketRequestLog.length}',
      createdAt: at,
      deadline: at,
      requestedItemId: message,
      requestedQuantity: 0,
      customerName: null,
      status: MarketRequestStatus.completed,
      resolvedAt: at,
      responder: MarketRequestResponder.distributor,
    ));
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

  Zone0ActionResult depositMarketDistributorMaterial(
      String resource, int amount,
      {String shopId = primaryMarketShopId}) {
    if (marketLevel < marketConfig.distributorMarketLevelFor(1)) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Distributeur niveau 1 est débloqué au niveau ${marketConfig.distributorMarketLevelFor(1)} du Marché.',
      );
    }
    if (shopId == primaryMarketShopId && !primaryMarketShopChosen) {
      return const Zone0ActionResult(
          success: false,
          message: 'Choisissez d’abord le type de la boutique.');
    }
    final distributor = _ensureMarketDistributorForShop(shopId);
    if (distributor.isBuilt || amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt impossible.');
    }
    final required = marketConfig.distributorConstructionCost[resource] ?? 0;
    final missing = math.max(
        0, required - (distributor.constructionDeposits[resource] ?? 0));
    final moved = removeResource(resource, math.min(amount, missing));
    if (moved <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Aucune ressource à déposer.');
    distributor.constructionDeposits[resource] =
        (distributor.constructionDeposits[resource] ?? 0) + moved;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved $resource déposé(s).');
  }

  bool isMarketDistributorReadyToBuildFor(String shopId) {
    final distributor = marketDistributorForShop(shopId);
    return distributor != null &&
        marketConfig.distributorConstructionCost.entries.every((entry) =>
            (distributor.constructionDeposits[entry.key] ?? 0) >=
            entry.value) &&
        (distributor.constructionDeposits['Bio-batteries'] ?? 0) >=
            marketConfig.distributorConstructionBioBatteries;
  }

  Zone0ActionResult depositMarketDistributorBioBatteries(int amount,
      {String shopId = primaryMarketShopId}) {
    final distributor = _ensureMarketDistributorForShop(shopId);
    if (distributor.isBuilt || distributor.constructionStartedAt != null) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt impossible.');
    }
    final missing = math.max(
        0,
        marketConfig.distributorConstructionBioBatteries -
            (distributor.constructionDeposits['Bio-batteries'] ?? 0));
    final moved = math.min(amount, math.min(bioBatteries, missing));
    if (moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune Bio-batterie à déposer.');
    }
    bioBatteries -= moved;
    distributor.constructionDeposits['Bio-batteries'] =
        (distributor.constructionDeposits['Bio-batteries'] ?? 0) + moved;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$moved Bio-batterie(s) déposée(s).');
  }

  Zone0ActionResult withdrawMarketDistributorConstructionMaterial(
      String resource,
      {String shopId = primaryMarketShopId}) {
    final distributor = marketDistributorForShop(shopId);
    final amount = distributor?.constructionDeposits[resource] ?? 0;
    if (distributor == null ||
        distributor.isBuilt ||
        distributor.constructionStartedAt != null ||
        amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Retrait impossible.');
    }
    if (resource == 'Bio-batteries') {
      bioBatteries += amount;
    } else {
      final result = addResources(<String, int>{resource: amount});
      if (result.pending.isNotEmpty) {
        return const Zone0ActionResult(
            success: false, message: 'Inventaire plein : retrait impossible.');
      }
    }
    distributor.constructionDeposits.remove(resource);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$amount $resource rendu à la Maison.');
  }

  bool get isMarketDistributorReadyToBuild =>
      isMarketDistributorReadyToBuildFor(primaryMarketShopId);

  Zone0ActionResult startMarketDistributorConstruction(
      {String shopId = primaryMarketShopId}) {
    if (marketLevel < marketConfig.distributorMarketLevelFor(1)) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Distributeur niveau 1 est débloqué au niveau ${marketConfig.distributorMarketLevelFor(1)} du Marché.',
      );
    }
    if (shopId == primaryMarketShopId && !primaryMarketShopChosen) {
      return const Zone0ActionResult(
          success: false,
          message: 'Choisissez d’abord le type de la boutique.');
    }
    final distributor = _ensureMarketDistributorForShop(shopId);
    if (distributor.isBuilt || distributor.constructionStartedAt != null) {
      return const Zone0ActionResult(
          success: false, message: 'Travaux indisponibles.');
    }
    if (!isMarketDistributorReadyToBuildFor(shopId)) {
      return const Zone0ActionResult(
          success: false, message: 'Matériaux de construction incomplets.');
    }
    distributor.constructionStartedAt = DateTime.now();
    distributor.constructionEndsAt = distributor.constructionStartedAt!.add(
      Duration(minutes: marketConfig.constructionMinutesForLevel(1)),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Travaux du Distributeur commencés.');
  }

  Zone0ActionResult openBioBatteryForMarketDistributor(
      {String shopId = primaryMarketShopId}) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null || !distributor.isBuilt || bioBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Bio-batterie indisponible.');
    }
    if (distributor.energy >= marketConfig.distributorEnergyCapacity) {
      return const Zone0ActionResult(
          success: false, message: 'Réserve d’énergie pleine.');
    }
    final gain = energyFromBioBatteryForBuildingLevel(distributor.level);
    bioBatteries -= 1;
    distributor.energy = math.min(
      marketConfig.distributorEnergyCapacity,
      distributor.energy + gain,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '+$gain énergie du Distributeur.');
  }

  Zone0ActionResult setMarketDistributorType(MarketDistributorType type) {
    if (marketDistributor.isBuilt ||
        marketDistributor.constructionEndsAt != null) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le type est choisi avant la construction du Distributeur.',
      );
    }
    marketDistributor.type = type;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Distributeur ${type.label.toLowerCase()} sélectionné.',
    );
  }

  Zone0ActionResult transferToMarketDistributor(String resource, int amount,
      {String shopId = primaryMarketShopId}) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null ||
        !distributor.isBuilt ||
        !marketShopAccepts(shopId, resource)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Produit incompatible avec le Distributeur.');
    }
    final slotLimit = distributorSlotsForShop(shopId);
    if (distributor.stock.length >= slotLimit) {
      return const Zone0ActionResult(
          success: false, message: 'Emplacements du Distributeur occupés.');
    }
    final moved = removeResource(
        resource, math.min(amount, marketConfig.stackQuantityLimit));
    if (moved <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Stock insuffisant.');
    distributor.stock.add(Zone0InventoryStack(
      id: 'distributor-${shopId}-${DateTime.now().microsecondsSinceEpoch}-${distributor.stock.length}',
      resource: resource,
      amount: moved,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$moved $resource placé(s) dans le Distributeur.');
  }

  int distributorSlotsForShop(String shopId) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null || !distributor.isBuilt) return 0;
    return shopId == primaryMarketShopId
        ? marketDistributorSlotLimit
        : math.min(marketShopById(shopId)?.distributorSlots ?? 0,
            marketConfig.distributorSlotsForLevel(distributor.level));
  }

  Zone0ActionResult returnMarketDistributorStock(Zone0InventoryStack stack,
      {String shopId = primaryMarketShopId}) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null || !distributor.stock.contains(stack)) {
      return const Zone0ActionResult(success: false, message: 'Stock absent.');
    }
    final result = addResources(<String, int>{stack.resource: stack.amount});
    final returned = stack.amount - (result.pending[stack.resource] ?? 0);
    stack.amount -= returned;
    if (stack.amount <= 0) distributor.stock.remove(stack);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: returned > 0,
      message: '$returned ${stack.resource} rendu à la Maison.',
    );
  }

  Zone0ActionResult repairMarketDistributor({
    bool byPtipote = false,
    String shopId = primaryMarketShopId,
  }) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null || !distributor.isBroken) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune réparation à lancer.');
    }
    if (!byPtipote &&
        (!hasResources(marketConfig.distributorRepairCost) ||
            !removeResources(marketConfig.distributorRepairCost))) {
      return Zone0ActionResult(
          success: false,
          message: missingResourcesLabel(marketConfig.distributorRepairCost));
    }
    _repairDistributor(
      distributor,
      byPtipote: byPtipote,
      shopLabel: shopId == primaryMarketShopId
          ? 'Distributeur de la boutique principale'
          : 'Distributeur du magasin',
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Réparation du Distributeur lancée.');
  }

  Zone0ActionResult upgradeMarketDistributor({
    String shopId = primaryMarketShopId,
  }) {
    final distributor = marketDistributorForShop(shopId);
    if (distributor == null ||
        !distributor.isBuilt ||
        distributor.upgradeEndsAt != null ||
        distributor.level >= 3) {
      return const Zone0ActionResult(
          success: false,
          message: 'Amélioration du Distributeur indisponible.');
    }
    final target = distributor.level + 1;
    if (marketLevel < marketConfig.distributorMarketLevelFor(target)) {
      return Zone0ActionResult(
          success: false,
          message:
              'Le Marché niveau ${marketConfig.distributorMarketLevelFor(target)} est requis.');
    }
    final cost = marketConfig.distributorConstructionCost
        .map((resource, amount) => MapEntry(resource, amount * target));
    if (!hasResources(cost) || !removeResources(cost)) {
      return Zone0ActionResult(
          success: false, message: missingResourcesLabel(cost));
    }
    distributor
      ..upgradeTargetLevel = target
      ..upgradeEndsAt = DateTime.now().add(
          Duration(minutes: marketConfig.constructionMinutesForLevel(target)));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Amélioration indépendante du Distributeur vers le niveau $target lancée.');
  }

  void _repairDistributor(
    MarketDistributorState distributor, {
    required bool byPtipote,
    required String shopLabel,
  }) {
    // Le joueur peut remplacer une réparation P’TIPOTE par une intervention
    // courte. La même machine ne peut jamais lancer deux réparations.
    distributor.repairEndsAt = DateTime.now().add(
      Duration(
          minutes: byPtipote
              ? marketConfig.distributorRepairMinutesForLevel(distributor.level)
              : 1),
    );
    distributor.repairStartedBy = byPtipote ? 'ptipote' : 'player';
    if (byPtipote) {
      marketDistributorsRepairedThisAssignment += 1;
      final ptipoteId = marketAssignedPtipoteId;
      if (ptipoteId != null) {
        addMissionXp(ptipoteId, 5);
        marketXpEarnedThisAssignment += 5;
      }
    }
    _recordDistributorIncident(
      '$shopLabel : réparation lancée par ${byPtipote ? 'le P’TIPOTE' : 'le joueur'}.',
      DateTime.now(),
    );
  }

  bool _resolveMarketDistributor(DateTime current) {
    var changed = _resolveMarketDistributorForShop(
      primaryMarketShopId,
      marketDistributor,
      current,
    );
    for (final shop in marketShops.where((shop) => !shop.isPrimary)) {
      final distributor = shop.distributor;
      if (distributor != null) {
        changed =
            _resolveMarketDistributorForShop(shop.id, distributor, current) ||
                changed;
      }
    }
    return changed;
  }

  bool _resolveMarketDistributorForShop(
    String shopId,
    MarketDistributorState distributor,
    DateTime current,
  ) {
    final shopLabel = shopId == primaryMarketShopId
        ? 'Distributeur de la boutique principale'
        : 'Distributeur du magasin';
    var changed = false;
    if (distributor.constructionEndsAt != null &&
        !current.isBefore(distributor.constructionEndsAt!)) {
      distributor
        ..isBuilt = true
        ..level = 1
        ..constructionStartedAt = null
        ..constructionEndsAt = null;
      reports.add(
          PtipoteMissionReport.system(message: '$shopLabel est opérationnel.'));
      changed = true;
    }
    if (distributor.upgradeEndsAt != null &&
        !current.isBefore(distributor.upgradeEndsAt!)) {
      distributor
        ..level = distributor.upgradeTargetLevel ?? distributor.level
        ..upgradeTargetLevel = null
        ..upgradeEndsAt = null;
      reports.add(PtipoteMissionReport.system(
          message:
              '$shopLabel : Distributeur amélioré au niveau ${distributor.level}.'));
      changed = true;
    }
    if (distributor.repairEndsAt != null &&
        !current.isBefore(distributor.repairEndsAt!)) {
      distributor
        ..isBroken = false
        ..repairEndsAt = null;
      _recordDistributorIncident(
        '$shopLabel réparé par ${distributor.repairStartedBy == 'ptipote' ? 'le P’TIPOTE' : 'le joueur'}.',
        current,
      );
      distributor.repairStartedBy = null;
      changed = true;
    }
    if (distributor.isBroken &&
        distributor.repairEndsAt == null &&
        marketAssignedPtipoteId != null) {
      _repairDistributor(distributor, byPtipote: true, shopLabel: shopLabel);
      return true;
    }
    if (!distributor.isOperational) return changed;
    distributor.lastEnergyTickAt ??= current;
    final elapsed = current.difference(distributor.lastEnergyTickAt!);
    final units = elapsed.inMinutes /
        (24 * 60) *
        marketConfig.distributorEnergyPerDayForLevel(distributor.level);
    if (units >= 1) {
      final used = units.floor();
      distributor.energy = math.max(0, distributor.energy - used);
      distributor.lastEnergyTickAt = distributor.lastEnergyTickAt!.add(
        Duration(
            minutes: (used *
                    24 *
                    60 /
                    math.max(
                        1,
                        marketConfig.distributorEnergyPerDayForLevel(
                            distributor.level)))
                .round()),
      );
      changed = true;
    }
    if (distributor.energy <= 0) return changed;
    // Le P’TIPOTE du Point info approvisionne le Distributeur depuis le stock
    // de sa boutique principale ; aucune ressource ne vient de la Maison.
    final sourceStock = marketStockForShop(shopId) ?? <Zone0InventoryStack>[];
    if (marketAssignedPtipoteId != null &&
        isMarketInformationPointUnlocked &&
        distributor.stock.length < distributorSlotsForShop(shopId)) {
      final source = sourceStock
          .where((stack) =>
              marketShopAccepts(shopId, stack.resource) && stack.amount > 0)
          .firstOrNull;
      if (source != null) {
        final transferred =
            math.min(source.amount, marketConfig.stackQuantityLimit);
        final sourceItemIds = source.sourceItemIds.take(transferred).toList();
        source.amount -= transferred;
        source.sourceItemIds.removeRange(0, sourceItemIds.length);
        if (source.amount <= 0) sourceStock.remove(source);
        distributor.stock.add(Zone0InventoryStack(
          id: 'distributor-refill-$shopId-${DateTime.now().microsecondsSinceEpoch}',
          resource: source.resource,
          amount: transferred,
          sourceItemIds: sourceItemIds,
        ));
        changed = true;
      }
    }
    for (final request in marketRequests
        .where((item) => item.isOpen && item.shopId == shopId)
        .toList()) {
      if (current.isBefore(request.distributorEligibleAt)) continue;
      final stack = distributor.stock
          .where((item) => item.resource == request.requestedItemId)
          .firstOrNull;
      if (stack == null || stack.amount < request.requestedQuantity) continue;
      _consumeMarketStack(stack, request.requestedQuantity);
      if (stack.amount <= 0) distributor.stock.remove(stack);
      _creditMarketBioPiles(request.rewardBioPiles);
      request.status = MarketRequestStatus.completed;
      _recordMarketRequestOutcome(
        request,
        completedAt: current,
        responder: MarketRequestResponder.distributor,
      );
      changed = true;
      if (_random.nextInt(math.max(
              1,
              marketConfig
                  .distributorBreakDenominatorForLevel(distributor.level))) ==
          0) {
        distributor.isBroken = true;
        _recordDistributorIncident(
            '$shopLabel en panne après une vente.', current);
        reports.add(
            PtipoteMissionReport.system(message: '$shopLabel est en panne.'));
        break;
      }
    }
    return changed;
  }

  bool _resolveMarketContracts(DateTime current) {
    var changed = false;
    for (final contract in marketContracts
        .where((item) => item.status == MarketContractStatus.accepted)
        .toList()) {
      if (!current.isBefore(contract.expiresAt)) {
        contract.status = MarketContractStatus.failed;
        sourcierConfidence = math.max(
            0, sourcierConfidence - marketConfig.confidenceFailurePenalty);
        changed = true;
      } else if (contract.autoDeliverAllowed &&
          marketAssignedPtipoteId != null &&
          contract.requestedItems.entries.every(
              (entry) => _contractAvailableAmount(entry.key) >= entry.value)) {
        _deliverMarketContract(contract);
        changed = true;
      }
    }
    return changed;
  }

  Zone0ActionResult acceptMarketContract(MarketSourcierContract contract) {
    if (!marketContracts.contains(contract) ||
        contract.status != MarketContractStatus.offered) {
      return const Zone0ActionResult(
          success: false, message: 'Contrat indisponible.');
    }
    contract
      ..status = MarketContractStatus.accepted
      ..acceptedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(success: true, message: 'Contrat accepté.');
  }

  Zone0ActionResult deliverMarketContract(MarketSourcierContract contract) {
    if (contract.status != MarketContractStatus.accepted) {
      return const Zone0ActionResult(
          success: false, message: 'Contrat non accepté.');
    }
    if (!_deliverMarketContract(contract)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Marchandises insuffisantes dans le Marché.');
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Contrat livré au Sourcier.');
  }

  bool _deliverMarketContract(MarketSourcierContract contract) {
    if (!contract.requestedItems.entries
        .every((entry) => _contractAvailableAmount(entry.key) >= entry.value)) {
      return false;
    }
    for (final entry in contract.requestedItems.entries) {
      final isPTibug = _marketPTibugSpecies(entry.key) != null;
      if (isPTibug || _isMarketMatrixResource(entry.key)) {
        if (!_consumeContractPTibugStock(entry.key, entry.value)) {
          return false;
        }
      } else if (!_consumeAnyMarketShopStock(entry.key, entry.value)) {
        return false;
      }
    }
    final payment =
        (contract.rewardBioBatteries * sourcierConfidencePaymentMultiplier)
            .floor();
    bioBatteries += payment;
    _resolveEnergyCoreMilestones();
    sourcierConfidence =
        math.min(100, sourcierConfidence + contract.confidenceReward);
    contract
      ..status = MarketContractStatus.completed
      ..deliveredAt = DateTime.now();
    return true;
  }

  int _marketStockAmountAcrossCompatibleShops(String item) {
    final shopIds = <String>[
      primaryMarketShopId,
      ...marketShops.map((shop) => shop.id)
    ];
    return shopIds.fold<int>(
        0,
        (total, shopId) =>
            total +
            (marketShopAccepts(shopId, item)
                ? marketShopStockAmount(shopId, item)
                : 0));
  }

  int _contractAvailableAmount(String item) => _isMarketMatrixResource(item)
      ? _marketMatrixStockAmount(item)
      : _marketPTibugSpecies(item) != null
          ? _marketStockAmountAcrossCompatibleShops(item)
          : _marketStockAmountAcrossCompatibleShops(item);

  int _marketMatrixStockAmount(String item) {
    final resources = item == 'Matrice P’TIBUG'
        ? <String>{
            for (final species in PTibugSpecies.values)
              marketMatrixItemForSpecies(species),
          }
        : <String>{item};
    return resources.fold<int>(
      0,
      (total, resource) =>
          total + _marketStockAmountAcrossCompatibleShops(resource),
    );
  }

  bool _consumeContractPTibugStock(String item, int amount) {
    if (item != 'Matrice P’TIBUG') {
      return _consumeAnyMarketShopStock(item, amount);
    }
    var remaining = amount;
    for (final species in PTibugSpecies.values) {
      if (remaining <= 0) break;
      final resource = marketMatrixItemForSpecies(species);
      final available = _marketStockAmountAcrossCompatibleShops(resource);
      final taken = math.min(available, remaining);
      if (taken > 0 && !_consumeAnyMarketShopStock(resource, taken)) {
        return false;
      }
      remaining -= taken;
    }
    return remaining == 0;
  }

  String sourcierRequiredShopLabel(String item) {
    if (_marketPTibugSpecies(item) != null || _isMarketMatrixResource(item)) {
      return 'Magasin P’TIBUG';
    }
    if (const <String>{'Organique', 'Minéral', 'Mycélium'}.contains(item)) {
      return 'Grossiste';
    }
    final category = _residentItemCategory(item);
    return switch (category) {
      'meal' || 'drink' || 'sweetFood' || 'highEnergyFood' => 'Restaurant',
      'furniture' ||
      'decoration' ||
      'householdInstallation' ||
      'repairKit' =>
        'Magasin du foyer',
      _ => 'Magasin d’équipement',
    };
  }

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
    if (resolveResidentNeeds()) {
      changed = true;
    }
    if (resolveCommunityRoles()) {
      changed = true;
    }
    if (resolveResidentEconomy()) {
      changed = true;
    }
    if (resolveResidentArrivals()) {
      changed = true;
    }
    if (_resolveResidentVisions()) {
      changed = true;
    }
    if (resolveHouseholdAutonomy()) {
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
      final recoveryTick = math.max(
        1,
        ptipoteStatsConfig.statRecoveryTimeMultiplier.round(),
      );
      if (resting && tick % (2 * recoveryTick) == 0) {
        vitalityGain = ptipoteStatsConfig.vitalityRecoveryPerMinute;
      } else if (happy && tick % (2 * recoveryTick) == 0) {
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
      if (resting && tick % recoveryTick == 0) {
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
      final recoveryMinutes =
          (elapsedMinutes / ptipoteStatsConfig.statRecoveryTimeMultiplier)
              .floor();

      final hungerLoss =
          elapsedMinutes ~/ math.max(1, ptipoteStatsConfig.hungerDecayMinutes);
      if (hungerLoss > 0 && currentHunger > 0) {
        currentHunger = math.max(0, currentHunger - hungerLoss);
        hungerOverrides[figurine.id] = currentHunger;
        changed = true;
      }

      if (resting) {
        final restGain =
            recoveryMinutes * ptipoteStatsConfig.sleepRestRecoveryPerMinute;
        if (restGain > 0 && currentRest < ptipoteStatsConfig.maxRest) {
          final previousRest = currentRest;
          currentRest = math
              .min(
                ptipoteStatsConfig.maxRest,
                currentRest + restGain,
              )
              .toInt();
          restOverrides[figurine.id] = currentRest;
          _trackWellRestedTransition(
            figurineId: figurine.id,
            previousRest: previousRest,
            nextRest: currentRest,
          );
          changed = true;
        }
        if (currentVitality < ptipoteStatsConfig.maxVitality) {
          currentVitality = math
              .min(
                ptipoteStatsConfig.maxVitality,
                currentVitality +
                    recoveryMinutes *
                        ptipoteStatsConfig.vitalityRecoveryPerMinute,
              )
              .toInt();
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
        var vitalityGain = recoveryMinutes ~/ math.max(1, recoveryInterval);
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
          currentVitality = math
              .min(
                ptipoteStatsConfig.maxVitality,
                currentVitality + vitalityGain,
              )
              .toInt();
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

  int energyFromBioBatteryForBuildingLevel(int buildingLevel) =>
      wasteRecyclerConfig.energyUnitsForBuildingLevel(buildingLevel);

  Zone0ActionResult openBioBattery() {
    if (bioBatteries <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune Bio-batterie disponible.',
      );
    }
    bioBatteries -= 1;
    final gain = energyFromBioBatteryForBuildingLevel(fablabLevel);
    energyUnits += gain;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '+$gain Énergie.',
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
    // A legacy save can still contain the retired third Recycler output.
    // Keep that quantity by folding it into Minéral before retrieval.
    if (recyclerOutputOther > 0) {
      recyclerOutputMineral += recyclerOutputOther;
      recyclerOutputOther = 0;
    }
    final rewards = <String, int>{
      'Organique': recyclerOutputOrganic,
      'Minéral': recyclerOutputMineral,
    };
    final result = addResources(rewards);
    final organicLeft = result.pending['Organique'] ?? 0;
    final mineralLeft = result.pending['Minéral'] ?? 0;
    recyclerOutputOrganic = organicLeft;
    recyclerOutputMineral = mineralLeft;
    recyclerOutputOther = 0;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: result.addedAny,
      message: result.hasPending
          ? 'Inventaire plein : production conservée dans le Recycleur.'
          : 'Production récupérée.',
    );
  }

  LisiereTerritoryZone territoryZone(ForageBiome biome) =>
      lisiereTerritoryZones.putIfAbsent(
        biome,
        () => LisiereTerritoryZone.initial(biome),
      );

  int activePollinatorsForBiofermenter(ForageBiome biome) {
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return pTibugs
        .where((bug) =>
            bug.lifecycleStatus == PTibugLifecycleStatus.active &&
            bug.refugeBiome == biome &&
            bug.assignedBuildingId != null &&
            (bug.biologicalTraitId == config.pollinatorTraitId ||
                bug.secondTraitId == config.pollinatorTraitId))
        .length
        .clamp(0, config.maxPollinatorsCounted);
  }

  int activeMycelialPTibugsForBiofermenter(ForageBiome biome) {
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return pTibugs
        .where((bug) =>
            bug.lifecycleStatus == PTibugLifecycleStatus.active &&
            bug.refugeBiome == biome &&
            bug.assignedBuildingId != null &&
            (bug.biologicalTraitId == config.mycelialTraitId ||
                bug.secondTraitId == config.mycelialTraitId))
        .length
        .clamp(0, config.maxMycelialPTibugsCounted);
  }

  double biofermenterOrganicPerDay(ForageBiome biome) {
    final zone = territoryZone(biome);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    if (zone.buildingId != 'biofermenter' || zone.buildingLevel <= 0) return 0;
    final buildingId = biofermenterTargetId(biome);
    if (!isBuildingOperational(buildingId)) return 0;
    var result = (config.passiveOrganicPerDayByLevel[zone.buildingLevel] ?? 0) *
        config.passiveProductionMultiplier *
        zone.vatEfficiencyMultiplier *
        buildingProductionMultiplier(buildingId);
    if (zone.edibleForestInstalled && config.edibleForestEnabled) {
      result *= 1 +
          activePollinatorsForBiofermenter(biome) * config.bonusPerPollinator;
    }
    return result;
  }

  int biofermenterOrganicReserveCapacity(ForageBiome biome) {
    final zone = territoryZone(biome);
    if (zone.buildingId != 'biofermenter' || zone.buildingLevel <= 0) {
      return 0;
    }
    return 30 + (zone.buildingLevel - 1) * 10;
  }

  int lithocultureTankCapacity(ForageBiome biome) {
    final level = math.max(1, territoryZone(biome).buildingLevel);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return config.lithocultureTankBaseCapacity +
        (level - 1) * config.lithocultureTankCapacityPerLevel;
  }

  int calciumOrganicCapacity(ForageBiome biome) {
    final level = math.max(1, territoryZone(biome).buildingLevel);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return config.calciumOrganicBaseCapacity +
        (level - 1) * config.calciumOrganicCapacityPerLevel;
  }

  int calciumWaterCapacity(ForageBiome biome) {
    final level = math.max(1, territoryZone(biome).buildingLevel);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return config.calciumWaterBaseCapacity +
        (level - 1) * config.calciumWaterCapacityPerLevel;
  }

  int calciumMineralReserveCapacity(ForageBiome biome) {
    final level = math.max(1, territoryZone(biome).buildingLevel);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return config.calciumMineralReserveBaseCapacity +
        (level - 1) * config.calciumMineralReserveCapacityPerLevel;
  }

  bool canInstallCalciumBasin(ForageBiome biome) =>
      biome == ForageBiome.bassinMineral &&
      lisiereForageConfig.territoryBuildings.biofermenter.calciumBasinEnabled;

  int activeCalciumMinerPTibugsForBiofermenter(ForageBiome biome) {
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    return pTibugs
        .where((bug) =>
            bug.lifecycleStatus == PTibugLifecycleStatus.active &&
            bug.refugeBiome == biome &&
            bug.assignedBuildingId != null &&
            config.calciumEligibleTraitIds.any((traitId) =>
                bug.biologicalTraitId == traitId ||
                bug.secondTraitId == traitId))
        .length;
  }

  /// The ceiling is applied once to the complete daily formula, then the
  /// continuous resolver preserves hourly fractions. This favours the player
  /// without compounding rounding on each multiplier or refresh.
  int biofermenterMyceliumPerDay(ForageBiome biome) {
    final zone = territoryZone(biome);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    if (zone.buildingId != 'biofermenter' || !zone.mycelialNetworkInstalled) {
      return 0;
    }
    final buildingId = biofermenterTargetId(biome);
    if (!isBuildingOperational(buildingId)) return 0;
    final richness = lisiereForageConfig.biomes[biome]!.myceliumRichness;
    final biomeMultiplier = config.myceliumBiomeMultipliers[richness] ?? 1;
    final traitMultiplier = 1 +
        activeMycelialPTibugsForBiofermenter(biome) *
            config.mycelialTraitBonusPerPTibug;
    return (config.baseMyceliumPerDay * biomeMultiplier * traitMultiplier)
        .ceil();
  }

  bool resolveBiofermenterProduction({DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = false;
    for (final biome in ForageBiome.values) {
      final zone = territoryZone(biome);
      if (zone.buildingId != 'biofermenter') continue;
      final buildingId = biofermenterTargetId(biome);
      if (!isBuildingOperational(buildingId)) {
        // A disabled Biofermenter cannot catch up the time it spent broken.
        // Its passive production and Lithoculture both resume after repair.
        zone
          ..lastProductionResolvedAt = current
          ..lithocultureCycleStartedAt =
              zone.lithocultureCycleStartedAt == null ? null : current
          ..updatedAt = current;
        changed = true;
        continue;
      }
      final config = lisiereForageConfig.territoryBuildings.biofermenter;
      final last = zone.lastProductionResolvedAt ?? current;
      final elapsedHours = current.difference(last).inMilliseconds /
          Duration.millisecondsPerHour;
      if (elapsedHours > 0) {
        final exact = elapsedHours * biofermenterOrganicPerDay(biome) / 24 +
            zone.organicProductionRemainder;
        final requested = exact.floor();
        final reserveRoom = math.max(
          0,
          biofermenterOrganicReserveCapacity(biome) - zone.organicReserve,
        );
        final whole = math.min(requested, reserveRoom);
        zone
          // Une réserve pleine interrompt la production au lieu de créer un
          // crédit invisible. Les fractions ne sont conservées que tant que
          // le Biofermenteur possède réellement une place libre.
          ..organicProductionRemainder = whole == requested ? exact - whole : 0
          ..lastProductionResolvedAt = current
          ..updatedAt = current;
        // La production passive attend désormais dans le réservoir du
        // Biofermenteur, comme une réserve P'TIBUG : elle n'est jamais versée
        // automatiquement dans l'inventaire global.
        if (whole > 0) zone.organicReserve += whole;
        final myceliumExact =
            elapsedHours * biofermenterMyceliumPerDay(biome) / 24 +
                zone.myceliumProductionRemainder;
        final myceliumWhole = myceliumExact.floor();
        zone.myceliumProductionRemainder = myceliumExact - myceliumWhole;
        if (myceliumWhole > 0) {
          addResources(<String, int>{'Mycélium': myceliumWhole});
        }
        changed = true;

        if (zone.calciumBasinInstalled) {
          final weather = activeGlobalWeatherEvent;
          final rainRate = weather != null &&
                  weather.status == GlobalWeatherEventStatus.active &&
                  weather.type == TowerWeatherType.heavyRain &&
                  weather.isBiomeAffected(biome)
              ? switch (weather.intensity) {
                  GlobalWeatherIntensity.moderate => 2,
                  GlobalWeatherIntensity.strong => 5,
                  GlobalWeatherIntensity.severe => 10,
                  GlobalWeatherIntensity.calm => 0,
                }
              : 0;
          if (rainRate > 0) {
            zone.calciumWaterTank = math.min(
              calciumWaterCapacity(biome),
              zone.calciumWaterTank + (elapsedHours * rainRate).floor(),
            );
          }
          final exactHours = elapsedHours + zone.calciumProductionHourRemainder;
          final wholeHours = exactHours.floor();
          zone.calciumProductionHourRemainder = exactHours - wholeHours;
          for (var hour = 0; hour < wholeHours; hour++) {
            final base = zone.lithocultureMineralTank ~/
                config.lithocultureMineralPerCycle;
            if (base <= 0 ||
                zone.calciumOrganicTank < config.calciumOrganicPerActiveHour ||
                zone.calciumWaterTank < config.calciumWaterPerActiveHour) {
              break;
            }
            final output = base +
                activeCalciumMinerPTibugsForBiofermenter(biome) *
                    config.calciumMinerTraitBonusPerPTibug;
            final room = calciumMineralReserveCapacity(biome) -
                zone.calciumMineralReserve;
            if (room <= 0) break;
            zone
              ..calciumMineralReserve += math.min(room, output)
              ..calciumOrganicTank -= config.calciumOrganicPerActiveHour
              ..calciumWaterTank -= config.calciumWaterPerActiveHour;
          }
        }
      }
      while (zone.lithocultureCycleStartedAt != null) {
        final finishedAt = zone.lithocultureCycleStartedAt!.add(
          Duration(minutes: config.lithocultureCycleMinutes),
        );
        if (finishedAt.isAfter(current) ||
            zone.organicReserve + config.lithocultureOrganicPerCycle >
                biofermenterOrganicReserveCapacity(biome)) {
          break;
        }
        zone.organicReserve += config.lithocultureOrganicPerCycle;
        zone.lithocultureCycleStartedAt = null;
        if (zone.lithocultureMineralTank >=
            config.lithocultureMineralPerCycle) {
          zone.lithocultureMineralTank -= config.lithocultureMineralPerCycle;
          zone.lithocultureCycleStartedAt = finishedAt;
        }
      }
      if (zone.lithocultureCycleStartedAt == null &&
          zone.lithocultureMineralTank >= config.lithocultureMineralPerCycle &&
          zone.organicReserve + config.lithocultureOrganicPerCycle <=
              biofermenterOrganicReserveCapacity(biome)) {
        zone.lithocultureMineralTank -= config.lithocultureMineralPerCycle;
        zone.lithocultureCycleStartedAt = current;
      }
      changed = changed || zone.lithocultureCycleStartedAt != null;
    }
    return changed;
  }

  int get lithocultureMineralPerCycle => lisiereForageConfig
      .territoryBuildings.biofermenter.lithocultureMineralPerCycle;
  int get lithocultureOrganicPerCycle => lisiereForageConfig
      .territoryBuildings.biofermenter.lithocultureOrganicPerCycle;

  Zone0ActionResult transferMineralToLithoculture(
    ForageBiome biome,
    int amount,
  ) {
    final zone = territoryZone(biome);
    if (zone.buildingId != 'biofermenter' || amount <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Biofermenteur indisponible.',
      );
    }
    if (!isBuildingOperational(biofermenterTargetId(biome))) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Biofermenteur doit être réparé avant la Lithoculture.',
      );
    }
    final moved = math.min(
      amount,
      math.min(
        resourceAmount('Minéral'),
        math.max(
            0, lithocultureTankCapacity(biome) - zone.lithocultureMineralTank),
      ),
    );
    if (moved <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Minéral insuffisant.',
      );
    }
    removeResources(<String, int>{'Minéral': moved});
    zone
      ..lithocultureMineralTank += moved
      ..updatedAt = DateTime.now();
    resolveBiofermenterProduction();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$moved Minéral versé dans la cuve de Lithoculture.',
    );
  }

  Zone0ActionResult retrieveBiofermenterOrganic(ForageBiome biome) {
    final zone = territoryZone(biome);
    if (zone.buildingId != 'biofermenter' || zone.organicReserve <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun Organique à récolter.',
      );
    }
    final result =
        addResources(<String, int>{'Organique': zone.organicReserve});
    zone.organicReserve = result.pending['Organique'] ?? 0;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: result.addedAny,
      message: result.hasPending
          ? 'Inventaire plein : l’Organique reste dans le Biofermenteur.'
          : 'Organique récolté.',
    );
  }

  Zone0ActionResult retrieveCalciumBasinMineral(ForageBiome biome) {
    final zone = territoryZone(biome);
    if (!zone.calciumBasinInstalled || zone.calciumMineralReserve <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun Minéral à récolter.');
    }
    final result =
        addResources(<String, int>{'Minéral': zone.calciumMineralReserve});
    zone.calciumMineralReserve = result.pending['Minéral'] ?? 0;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: result.addedAny,
      message: result.hasPending
          ? 'Inventaire plein : le Minéral reste dans le Bassin de calcium.'
          : 'Minéral récolté.',
    );
  }

  Zone0ActionResult transferOrganicToCalciumBasin(
      ForageBiome biome, int amount) {
    final zone = territoryZone(biome);
    final moved = math.min(
        amount,
        math.min(
            resourceAmount('Organique'),
            math.max(
                0, calciumOrganicCapacity(biome) - zone.calciumOrganicTank)));
    if (!zone.calciumBasinInstalled || moved <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Bassin de calcium ou espace indisponible.');
    }
    removeResource('Organique', moved);
    zone.calciumOrganicTank += moved;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message: '$moved Organique versé dans le Bassin de calcium.');
  }

  int getLithocultureMineralCostPerOrganic(ForageBiome biome) =>
      territoryZone(biome).terrainTags.contains('mineralBasin')
          ? lisiereForageConfig
              .territoryBuildings.biofermenter.mineralBasinMineralPerOrganic
          : lisiereForageConfig
              .territoryBuildings.biofermenter.normalMineralPerOrganic;

  LithoculturePreview lithoculturePreview(
      ForageBiome biome, int organicAmount) {
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    final mineralCost =
        getLithocultureMineralCostPerOrganic(biome) * organicAmount;
    final availableWaste = resourceAmount('Déchets');
    final wasteUsed = config.wasteCanReplaceMineral
        ? math.min(availableWaste,
            (mineralCost * config.maxWasteSharePerBatch).floor())
        : 0;
    final mineralCovered =
        (wasteUsed * config.mineralEquivalentPerWaste).floor();
    return LithoculturePreview(
      organicAmount,
      math.max(0, mineralCost - mineralCovered).toInt(),
      wasteUsed,
    );
  }

  /// Compatibilité avec les anciens appelants : la Lithoculture ne crédite
  /// plus jamais l'inventaire directement. La quantité correspond maintenant
  /// au Minéral versé dans sa cuve.
  bool runLithoculture(ForageBiome biome, int mineralAmount) =>
      transferMineralToLithoculture(biome, mineralAmount).success;

  String _wasteDayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  CampWasteDailyReport _wasteReport(DateTime at) {
    final key = _wasteDayKey(at);
    return campWasteDailyReports.firstWhere(
      (report) => report.reportDate == key,
      orElse: () {
        final report = CampWasteDailyReport(reportDate: key, createdAt: at);
        campWasteDailyReports.add(report);
        return report;
      },
    );
  }

  void registerWasteGeneration(String sourceType, String sourceId, int amount,
      {DateTime? timestamp}) {
    if (amount <= 0) return;
    final at = timestamp ?? DateTime.now();
    final result = addResources(<String, int>{'Déchets': amount});
    pendingWaste = math.min(wasteRecyclerConfig.pendingWasteCapacity,
        pendingWaste + (result.pending['Déchets'] ?? 0));
    _wasteReport(at).technicalWasteGenerated += amount;
  }

  /// Prévision lisible de la production quotidienne du camp. Elle emploie
  /// exactement la même formule que le calcul offline des Déchets.
  double get campWasteGeneratedPerDay {
    final activeBugs = pTibugs
        .where((bug) => bug.lifecycleStatus == PTibugLifecycleStatus.active)
        .length;
    return residents.where((resident) => resident.isActive).length *
            wasteRecyclerConfig.wastePerResidentPerDay +
        hatchedPtipoteIds.length * wasteRecyclerConfig.wastePerPtibotePerDay +
        activeBugs * wasteRecyclerConfig.wastePerPtibugPerDay;
  }

  bool _resolveCampWaste(DateTime current) {
    final last = lastCampWasteCalculationAt;
    // Migration : aucune production rétroactive à la première ouverture.
    if (last == null) {
      lastCampWasteCalculationAt = current;
      return false;
    }
    if (!current.isAfter(last)) return false;
    final daily = campWasteGeneratedPerDay;
    var cursor = last;
    var generated = 0;
    while (cursor.isBefore(current)) {
      final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segmentEnd =
          nextMidnight.isBefore(current) ? nextMidnight : current;
      final hours = segmentEnd.difference(cursor).inMilliseconds /
          Duration.millisecondsPerHour;
      final exact = daily * hours / 24 + campWasteRemainder;
      final whole = exact.floor();
      campWasteRemainder = exact - whole;
      if (whole > 0) {
        generated += whole;
        _wasteReport(cursor).domesticWasteGenerated += whole;
        if (segmentEnd == nextMidnight) {
          reports.add(PtipoteMissionReport.system(
            message:
                'Rapport Déchets du ${_wasteDayKey(cursor)} : $whole Déchet(s) domestique(s) produit(s).',
            sourceBuildingId: 'recycler',
            mailbox: Zone0MessageMailbox.fablab,
            subject: 'Rapport du camp',
            concerned: 'Refuge',
          ));
        }
      }
      cursor = segmentEnd;
    }
    lastCampWasteCalculationAt = current;
    if (generated <= 0) return true;
    final result = addResources(<String, int>{'Déchets': generated});
    pendingWaste = math.min(wasteRecyclerConfig.pendingWasteCapacity,
        pendingWaste + (result.pending['Déchets'] ?? 0));
    final cutoff = current.subtract(
        Duration(days: wasteRecyclerConfig.wasteHistoryRetentionDays));
    campWasteDailyReports
        .removeWhere((report) => report.createdAt.isBefore(cutoff));
    return true;
  }

  bool installRecyclerBiologicalOrientation() {
    if (recyclerBiologicalOrientationInstalled ||
        !hasResources(wasteRecyclerConfig.biologicalOrientationModuleCost)) {
      return false;
    }
    removeResources(wasteRecyclerConfig.biologicalOrientationModuleCost);
    recyclerBiologicalOrientationInstalled = true;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return true;
  }

  bool setRecyclerBiologicalOrientation(bool active) {
    if (active && !recyclerBiologicalOrientationInstalled) return false;
    recyclerBiologicalOrientationActive = active;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return true;
  }

  List<int> _recyclerRatios() {
    if (recyclerBiologicalOrientationActive) {
      return <int>[
        wasteRecyclerConfig.biologicalOrganicRatio,
        wasteRecyclerConfig.biologicalMineralRatio,
        0,
      ];
    }
    final splits = wasteRecyclerConfig.outputSplits;
    if (splits.isEmpty) {
      return <int>[
        wasteRecyclerConfig.standardOrganicRatio,
        wasteRecyclerConfig.standardMineralRatio,
        0,
      ];
    }
    final split = splits[_random.nextInt(splits.length)];
    final reverse = _random.nextBool();
    return <int>[
      (reverse ? split.mineral : split.organic) * 10,
      (reverse ? split.organic : split.mineral) * 10,
      0,
    ];
  }

  bool resolveWasteAndRecycler({required int campHeartLevel, DateTime? now}) {
    final current = now ?? DateTime.now();
    var changed = resolveBiofermenterProduction(now: current);
    if (pendingWaste > 0) {
      final result = addResources(<String, int>{'Déchets': pendingWaste});
      pendingWaste = result.pending['Déchets'] ?? 0;
      changed = result.addedAny;
    }
    changed = _resolveCampWaste(current) || changed;
    if (!isRecyclerUnlocked(campHeartLevel) ||
        !isBuildingOperational('recycler')) return changed;
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
      final ratios = recyclerActiveBatch?.ratios ?? _recyclerRatios();
      final units = wasteRecyclerConfig.outputResourcesPerCycle;
      final organic = units * ratios[0] ~/ 100;
      // Old 40/40/20 snapshots are resolved as matter-only output: the
      // retired third share is credited as Minéral instead of Eau.
      final mineral = units - organic;
      recyclerOutputOrganic += organic;
      recyclerOutputMineral += mineral;
      recyclerOutputOther = 0;
      completedCycles += 1;
      producedOrganic += organic;
      producedMineral += mineral;
      recyclerCycleStartedAt = finishedAt;
      recyclerActiveBatch = null;
      changed = true;
      if (recyclerOutputAmount + wasteRecyclerConfig.outputResourcesPerCycle >
          recyclerOutputCapacity) {
        recyclerCycleStartedAt = null;
      } else if (recyclerWasteTank < recyclerWasteRequired ||
          energyUnits < wasteRecyclerConfig.energyCostPerCycle) {
        recyclerCycleStartedAt = null;
      } else {
        recyclerWasteTank -= recyclerWasteRequired;
        _wasteReport(finishedAt).wasteRecycled += recyclerWasteRequired;
        energyUnits -= wasteRecyclerConfig.energyCostPerCycle;
        recyclerActiveBatch = RecyclerBatchSnapshot.fromRatios(
            _recyclerRatios(), recyclerBiologicalOrientationActive);
      }
    }
    if (recyclerCycleStartedAt == null &&
        recyclerOutputAmount + wasteRecyclerConfig.outputResourcesPerCycle <=
            recyclerOutputCapacity &&
        recyclerWasteTank >= recyclerWasteRequired &&
        energyUnits >= wasteRecyclerConfig.energyCostPerCycle) {
      recyclerWasteTank -= recyclerWasteRequired;
      _wasteReport(current).wasteRecycled += recyclerWasteRequired;
      energyUnits -= wasteRecyclerConfig.energyCostPerCycle;
      recyclerCycleStartedAt = current;
      recyclerActiveBatch = RecyclerBatchSnapshot.fromRatios(
          _recyclerRatios(), recyclerBiologicalOrientationActive);
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
      if (targetId == 'plaineNursery' &&
          currentLevel == 0 &&
          !existing.isInProgress &&
          (existing.state == ConstructionProjectState.built ||
              existing.state == ConstructionProjectState.maxLevel)) {
        // Some legacy saves persisted an unbuilt nursery with a terminal
        // project state. Normalize it back to the initial construction.
        existing.currentLevel = 0;
        existing.prepareNextLevel(
          targetLevel: 1,
          requirements: _projectRequirements(targetId, 1),
          constructionDuration: _projectDuration(targetId),
        );
      }
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
    final territoryBiome = _biofermenterBiomeForTarget(targetId);
    if (territoryBiome != null) {
      final config = lisiereForageConfig.territoryBuildings.biofermenter;
      return targetLevel == 1
          ? config.constructionCost
          : config.upgradeCosts[targetLevel] ?? const <String, int>{};
    }
    if (_edibleForestBiomeForTarget(targetId) != null) {
      return lisiereForageConfig
          .territoryBuildings.biofermenter.edibleForestCost;
    }
    if (_mycelialNetworkBiomeForTarget(targetId) != null) {
      return lisiereForageConfig
          .territoryBuildings.biofermenter.mycelialNetworkCost;
    }
    if (_calciumBasinBiomeForTarget(targetId) != null) {
      return lisiereForageConfig
          .territoryBuildings.biofermenter.calciumBasinCost;
    }
    if (_isRefugeTarget(targetId)) {
      return pTibugConfig.territory.refugeRequirementsForLevel(targetLevel);
    }
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
        minutes: _biofermenterBiomeForTarget(targetId) != null
            ? lisiereForageConfig.territoryBuildings.biofermenter
                    .constructionMinutesByLevel[_buildingLevel(targetId) + 1] ??
                60
            : _edibleForestBiomeForTarget(targetId) != null
                ? lisiereForageConfig.territoryBuildings.biofermenter
                    .edibleForestConstructionMinutes
                : _mycelialNetworkBiomeForTarget(targetId) != null
                    ? lisiereForageConfig.territoryBuildings.biofermenter
                        .mycelialNetworkConstructionMinutes
                    : _calciumBasinBiomeForTarget(targetId) != null
                        ? lisiereForageConfig.territoryBuildings.biofermenter
                            .calciumBasinConstructionMinutes
                        : targetId == 'housing'
                            ? housingConfig.housingDurationMinutes
                            : _isRefugeTarget(targetId)
                                ? pTibugConfig.territory.refugeMinutesForLevel(
                                    _buildingLevel(targetId) + 1)
                                : buildingConstructionConfig
                                    .project(targetId)
                                    .durationMinutes,
      );

  int _buildingLevel(String targetId) {
    final territoryBiome = _biofermenterBiomeForTarget(targetId);
    if (territoryBiome != null)
      return territoryZone(territoryBiome).buildingLevel;
    final forestBiome = _edibleForestBiomeForTarget(targetId);
    if (forestBiome != null)
      return territoryZone(forestBiome).edibleForestInstalled ? 1 : 0;
    final networkBiome = _mycelialNetworkBiomeForTarget(targetId);
    if (networkBiome != null) {
      return territoryZone(networkBiome).mycelialNetworkInstalled ? 1 : 0;
    }
    final calciumBiome = _calciumBasinBiomeForTarget(targetId);
    if (calciumBiome != null) {
      return territoryZone(calciumBiome).calciumBasinInstalled ? 1 : 0;
    }
    if (_isRefugeTarget(targetId)) {
      return territoryBuildingForId(targetId)?.level ?? 0;
    }
    return switch (targetId) {
      'fablab' => atelierLevel,
      'cuisine' => cuisineLevel,
      'atelier' => atelierLevel,
      'recycler' => recyclerLevel,
      'securityTower' => securityTowerLevel,
      'towerWeatherModule' => towerWeatherModuleInstalled ? 1 : 0,
      'towerResearchModule' => towerResearchModuleInstalled ? 1 : 0,
      'market' => marketLevel,
      'house' => houseLevel,
      'housing' => housingUnits,
      'plaineNursery' => plaineNurseryLevel,
      _ => 0,
    };
  }

  int _projectMaxLevel(String targetId) {
    if (_biofermenterBiomeForTarget(targetId) != null) return 4;
    if (_edibleForestBiomeForTarget(targetId) != null) return 1;
    if (_mycelialNetworkBiomeForTarget(targetId) != null) return 1;
    if (_calciumBasinBiomeForTarget(targetId) != null) return 1;
    if (_isRefugeTarget(targetId))
      return pTibugConfig.territory.refugeMaximumLevel;
    return switch (targetId) {
      'fablab' => 1,
      'cuisine' => fablabConfig.cuisineMaxLevel,
      'atelier' => fablabConfig.atelierMaxLevel,
      'recycler' => wasteRecyclerConfig.recyclerMaxLevel,
      'securityTower' => 3,
      'towerWeatherModule' => 1,
      'towerResearchModule' => 1,
      'market' => 5,
      'house' => housingConfig.houseMaxLevel,
      'housing' => 99,
      'plaineNursery' => pTibugConfig.territory.nurseryMaximumLevel,
      _ => 1,
    };
  }

  String biofermenterTargetId(ForageBiome biome) =>
      'biofermenter-${biome.name}';
  String edibleForestTargetId(ForageBiome biome) =>
      'edibleForest-${biome.name}';
  String mycelialNetworkTargetId(ForageBiome biome) =>
      'mycelialNetwork-${biome.name}';
  String calciumBasinTargetId(ForageBiome biome) =>
      'calciumBasin-${biome.name}';
  ForageBiome? _biofermenterBiomeForTarget(String targetId) {
    const prefix = 'biofermenter-';
    if (!targetId.startsWith(prefix)) return null;
    return ForageBiome.values
        .where((biome) => biome.name == targetId.substring(prefix.length))
        .firstOrNull;
  }

  ForageBiome? _edibleForestBiomeForTarget(String targetId) {
    const prefix = 'edibleForest-';
    if (!targetId.startsWith(prefix)) return null;
    return ForageBiome.values
        .where((biome) => biome.name == targetId.substring(prefix.length))
        .firstOrNull;
  }

  ForageBiome? _mycelialNetworkBiomeForTarget(String targetId) {
    const prefix = 'mycelialNetwork-';
    if (!targetId.startsWith(prefix)) return null;
    final name = targetId.substring(prefix.length);
    return ForageBiome.values.where((item) => item.name == name).firstOrNull;
  }

  ForageBiome? _calciumBasinBiomeForTarget(String targetId) {
    const prefix = 'calciumBasin-';
    if (!targetId.startsWith(prefix)) return null;
    return ForageBiome.values
        .where((item) => item.name == targetId.substring(prefix.length))
        .firstOrNull;
  }

  int projectBioBatteryRequirement(String targetId) {
    final project = projectFor(targetId);
    if (!_isRefugeTarget(targetId)) return 0;
    return pTibugConfig.territory
        .refugeBioBatteriesForLevel(project.targetLevel);
  }

  Zone0ActionResult depositProjectBioBattery(String targetId,
      {int amount = 1}) {
    final project = projectFor(targetId);
    final required = projectBioBatteryRequirement(targetId);
    if (!_isRefugeTarget(targetId) ||
        !project.canEditMaterials ||
        required <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt impossible.');
    }
    final deposit = math.min(amount,
        math.min(bioBatteries, required - project.depositedBioBatteries));
    if (deposit <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Aucune Bio-batterie à déposer.');
    bioBatteries -= deposit;
    project.depositedBioBatteries += deposit;
    project.refreshState(extraReady: project.depositedBioBatteries >= required);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$deposit Bio-batterie(s) déposée(s).');
  }

  Zone0ActionResult depositProjectMaterial(
    String targetId,
    String resource,
    int amount,
  ) {
    final project = projectFor(targetId);
    final refugeBiome = _refugeBiomeForTarget(targetId);
    if (refugeBiome != null &&
        (refugeBiome == ForageBiome.plaineRiche ||
            !isBiomeUnlocked(refugeBiome))) {
      return const Zone0ActionResult(
          success: false, message: 'Ce Refuge ne peut pas être construit ici.');
    }
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
    final biofermenterBiome = _biofermenterBiomeForTarget(targetId);
    if (biofermenterBiome != null && !isBiomeUnlocked(biofermenterBiome)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce biome doit être découvert avant la construction.',
      );
    }
    final forestBiome = _edibleForestBiomeForTarget(targetId);
    if (forestBiome != null &&
        territoryZone(forestBiome).buildingId != 'biofermenter') {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Biofermenteur doit être construit avant ce module.',
      );
    }
    final networkBiome = _mycelialNetworkBiomeForTarget(targetId);
    if (networkBiome != null) {
      final zone = territoryZone(networkBiome);
      if (!lisiereForageConfig
              .territoryBuildings.biofermenter.mycelialNetworkEnabled ||
          zone.buildingId != 'biofermenter') {
        return const Zone0ActionResult(
          success: false,
          message: 'Le Biofermenteur doit être construit avant ce module.',
        );
      }
      if (zone.edibleForestInstalled) {
        return const Zone0ActionResult(
          success: false,
          message: 'La Forêt comestible est déjà la spécialisation active.',
        );
      }
      if (constructionProjects[edibleForestTargetId(networkBiome)]
              ?.isInProgress ??
          false) {
        return const Zone0ActionResult(
          success: false,
          message: 'La Forêt comestible est déjà en cours d’installation.',
        );
      }
    }
    final calciumBiome = _calciumBasinBiomeForTarget(targetId);
    if (calciumBiome != null) {
      final zone = territoryZone(calciumBiome);
      if (!canInstallCalciumBasin(calciumBiome) ||
          zone.buildingId != 'biofermenter') {
        return const Zone0ActionResult(
          success: false,
          message:
              'Le Bassin de calcium est réservé au Biofermenteur du Bassin minéral.',
        );
      }
    }
    if (forestBiome != null &&
        territoryZone(forestBiome).mycelialNetworkInstalled) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Réseau mycélien est déjà la spécialisation active.',
      );
    }
    if (forestBiome != null &&
        (constructionProjects[mycelialNetworkTargetId(forestBiome)]
                ?.isInProgress ??
            false)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Réseau mycélien est déjà en cours d’installation.',
      );
    }
    final refugeBiome = _refugeBiomeForTarget(targetId);
    if (refugeBiome != null &&
        (refugeBiome == ForageBiome.plaineRiche ||
            !isBiomeUnlocked(refugeBiome))) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce Refuge ne peut pas être construit ici.',
      );
    }
    if (targetId == 'securityTower' &&
        (campHeartLevel ?? 0) < securityTowerConfig.requiredCampHeartLevel) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le Cœur du Camp doit atteindre le niveau ${securityTowerConfig.requiredCampHeartLevel}.',
      );
    }
    if ((targetId == 'towerWeatherModule' ||
            targetId == 'towerResearchModule') &&
        !isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construisez d’abord la Tour de sécurité.',
      );
    }
    if (targetId == 'plaineNursery' && (campHeartLevel ?? 0) < 2) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Cœur du Camp doit atteindre le niveau 2.',
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
    if (project.isInProgress) {
      return const Zone0ActionResult(
        success: false,
        message: 'Les travaux sont déjà en cours.',
      );
    }
    if (!project.isReady ||
        project.depositedBioBatteries <
            projectBioBatteryRequirement(targetId)) {
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
      case 'towerWeatherModule':
        towerWeatherModuleInstalled = true;
        ensureWeatherForecast();
      case 'towerResearchModule':
        towerResearchModuleInstalled = true;
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
        final nursery = plaineNurseryTerritory;
        nursery
          ..level = plaineNurseryLevel
          ..isBuilt = plaineNurseryLevel > 0;
        emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
      default:
        final territoryBiome = _biofermenterBiomeForTarget(project.targetId);
        if (territoryBiome != null) {
          territoryZone(territoryBiome)
            ..buildingId = 'biofermenter'
            ..buildingLevel = project.currentLevel
            ..lastProductionResolvedAt = now
            ..updatedAt = now;
          emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
          break;
        }
        final forestBiome = _edibleForestBiomeForTarget(project.targetId);
        if (forestBiome != null) {
          territoryZone(forestBiome)
            ..edibleForestInstalled = true
            ..lastProductionResolvedAt = now
            ..updatedAt = now;
          break;
        }
        final networkBiome = _mycelialNetworkBiomeForTarget(project.targetId);
        if (networkBiome != null) {
          territoryZone(networkBiome)
            ..mycelialNetworkInstalled = true
            ..lastProductionResolvedAt = now
            ..updatedAt = now;
          break;
        }
        final calciumBiome = _calciumBasinBiomeForTarget(project.targetId);
        if (calciumBiome != null) {
          territoryZone(calciumBiome)
            ..calciumBasinInstalled = true
            ..lastProductionResolvedAt = now
            ..updatedAt = now;
          break;
        }
        final refugeBiome = _refugeBiomeForTarget(project.targetId);
        if (refugeBiome != null) {
          final refuge = pTibugTerritoryBuildings.putIfAbsent(
            project.targetId,
            () => PTibugTerritoryBuilding(
              id: project.targetId,
              kind: PTibugTerritoryKind.refuge,
              biome: refugeBiome,
              level: project.currentLevel,
              isBuilt: true,
              lastConsumptionAt: now,
            ),
          );
          refuge
            ..level = project.currentLevel
            ..isBuilt = true
            ..lastConsumptionAt = now;
          for (final bug in pTibugsForTerritory(refuge.id)) {
            if (bug.inactiveReason == 'Travaux en cours') {
              bug
                ..inactiveReason = null
                ..nextProductionAt = now.add(_pTibugCycleDuration(bug));
            }
          }
          emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
        }
    }
    _migrateResidentsAndHouses();
    if (!project.notificationCreated) {
      final isFablabUnit = const <String>{
        'cuisine',
        'atelier',
        'recycler',
      }.contains(project.targetId);
      reports.add(
        PtipoteMissionReport.system(
          message:
              'Les travaux de ${_projectLabel(project.targetId)} sont terminés. Niveau ${project.currentLevel}.',
          sourceBuildingId: project.targetId,
          mailbox: isFablabUnit
              ? Zone0MessageMailbox.fablab
              : Zone0MessageMailbox.companions,
          subject: 'Fin de chantier',
          concerned: 'Joueur',
          summary:
              '${_projectLabel(project.targetId)} niveau ${project.currentLevel} est prêt.',
        ),
      );
      project.notificationCreated = true;
    }
  }

  String _projectLabel(String targetId) => _isRefugeTarget(targetId)
      ? 'Refuge P’TIBUG'
      : buildingConstructionConfig.project(targetId).label;

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

  /// Starts the first stage of a new P'TIBUG: the Armature. The old direct
  /// order is retained only to resolve a craft that was already running when
  /// the cultivation migration was installed.
  Zone0ActionResult startPTibugCreation(
    PTibugSpecies species, {
    PtipoteFigurine? figurine,
  }) {
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
    if (!isFablabBuilt ||
        atelierLevel <= 0 ||
        !isBuildingOperational('atelier')) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Construis et remets en marche l’Atelier pour fabriquer une Armature.',
      );
    }
    // Une Armature est un craft Atelier normal : le créneau manuel et les
    // emplacements P'TIPOTE limitent la concurrence, pas un verrou global
    // entre toutes les espèces.
    if (figurine == null && activeManualWorkshopOrders >= 1) {
      return const Zone0ActionResult(
          success: false,
          message: 'Le créneau manuel de l’Atelier est occupé.');
    }
    if (figurine != null && activePtipoteWorkshopOrders >= workshopSlots) {
      return const Zone0ActionResult(
          success: false,
          message: 'Tous les emplacements P’TIPOTE de l’Atelier sont occupés.');
    }
    if (figurine != null && isBusy(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
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
    pTibugArmatures.add(PTibugArmature(
      id: 'ptibug-armature-${now.microsecondsSinceEpoch}',
      species: species,
      startedAt: now,
      completesAt:
          now.add(Duration(minutes: pTibugConfig.cultivation.armatureMinutes)),
      materialCosts: Map<String, int>.from(config.creationCost),
      createdAt: now,
      assignedPtipoteId: figurine?.id,
      assignedPtipoteName: figurine?.displayName,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Armature ${config.displayName} lancée à l’Atelier${figurine == null ? '' : ' avec ${figurine.displayName}'}.',
    );
  }

  int get cultivationTankSlotCount => math.max(
        0,
        plaineNurseryLevel * pTibugConfig.cultivation.tankSlotsPerNurseryLevel,
      );

  List<PTibugCultivationTank> get builtCultivationTanks =>
      pTibugCultivationTanks.where((tank) => tank.isBuilt).toList()
        ..sort((first, second) => first.slotIndex.compareTo(second.slotIndex));

  PTibugCultivationTank? cultivationTankForId(String id) =>
      pTibugCultivationTanks.where((tank) => tank.id == id).firstOrNull;

  PTibugCultivationOperation? cultivationOperationForTank(String tankId) =>
      pTibugCultivationOperations
          .where((operation) =>
              operation.tankId == tankId &&
              operation.status != PTibugCultivationOperationStatus.cancelled)
          .firstOrNull;

  void _ensureCultivationTankSlots() {
    for (var index = 0; index < cultivationTankSlotCount; index++) {
      if (pTibugCultivationTanks.any((tank) => tank.slotIndex == index))
        continue;
      pTibugCultivationTanks.add(PTibugCultivationTank(
        id: 'ptibug-tank-$index',
        slotIndex: index,
      ));
    }
    if (!firstCultivationTankGranted && cultivationTankSlotCount > 0) {
      final first = cultivationTankForId('ptibug-tank-0');
      if (first != null) {
        first
          ..isBuilt = true
          ..status = PTibugCultivationTankStatus.available;
      }
      firstCultivationTankGranted = true;
    }
  }

  Zone0ActionResult depositCultivationTankConstruction({
    required String tankId,
    required Map<String, int> resources,
    int bioBatteriesAmount = 0,
  }) {
    _ensureCultivationTankSlots();
    final tank = cultivationTankForId(tankId);
    if (tank == null ||
        tank.isBuilt ||
        tank.status == PTibugCultivationTankStatus.underConstruction) {
      return const Zone0ActionResult(
          success: false,
          message: 'Cette cuve ne peut pas recevoir de travaux.');
    }
    final config = pTibugConfig.cultivation;
    final requested = <String, int>{
      for (final entry in resources.entries)
        entry.key: math.max(
            0,
            math.min(
                entry.value,
                math.max(
                    0,
                    (config.tankConstructionCost[entry.key] ?? 0) -
                        (tank.constructionDeposits[entry.key] ?? 0)))),
    };
    final requestedBatteries = math.max(
      0,
      math.min(
        bioBatteriesAmount,
        math.max(
          0,
          config.tankConstructionBioBatteries -
              (tank.constructionDeposits['Bio-batteries'] ?? 0),
        ),
      ),
    );
    if (requested.values.every((amount) => amount == 0) &&
        requestedBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Aucune ressource à déposer.');
    }
    if (!hasResources(requested) || bioBatteries < requestedBatteries) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ressources ou Bio-batteries insuffisantes.');
    }
    if (!removeResources(requested))
      return const Zone0ActionResult(
          success: false, message: 'Ressources insuffisantes.');
    bioBatteries -= requestedBatteries;
    for (final entry in requested.entries) {
      tank.constructionDeposits[entry.key] =
          (tank.constructionDeposits[entry.key] ?? 0) + entry.value;
    }
    tank.constructionDeposits['Bio-batteries'] =
        (tank.constructionDeposits['Bio-batteries'] ?? 0) + requestedBatteries;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Matériaux déposés dans la cuve.');
  }

  bool cultivationTankConstructionReady(PTibugCultivationTank tank) {
    final config = pTibugConfig.cultivation;
    return config.tankConstructionCost.entries.every((entry) =>
            (tank.constructionDeposits[entry.key] ?? 0) >= entry.value) &&
        (tank.constructionDeposits['Bio-batteries'] ?? 0) >=
            config.tankConstructionBioBatteries;
  }

  Zone0ActionResult withdrawCultivationTankConstruction({
    required String tankId,
    required String resource,
  }) {
    final tank = cultivationTankForId(tankId);
    final amount = tank?.constructionDeposits[resource] ?? 0;
    if (tank == null ||
        tank.isBuilt ||
        tank.status == PTibugCultivationTankStatus.underConstruction ||
        amount <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Retrait impossible.');
    }
    if (resource == 'Bio-batteries') {
      bioBatteries += amount;
    } else {
      final result = addResources(<String, int>{resource: amount});
      if (result.pending.isNotEmpty) {
        return const Zone0ActionResult(
            success: false, message: 'Inventaire plein : retrait impossible.');
      }
    }
    tank.constructionDeposits.remove(resource);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$amount $resource rendu à la Maison.');
  }

  Zone0ActionResult startCultivationTankConstruction(String tankId) {
    final tank = cultivationTankForId(tankId);
    if (tank == null ||
        !cultivationTankConstructionReady(tank) ||
        tank.isBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Dépôt de construction incomplet.');
    }
    final now = DateTime.now();
    tank
      ..status = PTibugCultivationTankStatus.underConstruction
      ..constructionStartedAt = now
      ..constructionEndsAt = now.add(
          Duration(minutes: pTibugConfig.cultivation.tankConstructionMinutes));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Construction de la cuve lancée.');
  }

  Zone0ActionResult addCultivationTankResources({
    required String tankId,
    required String resource,
    required int amount,
  }) {
    final tank = cultivationTankForId(tankId);
    final operation =
        tank == null ? null : cultivationOperationForTank(tank.id);
    if (tank == null || !tank.isBuilt || amount <= 0 || resource == 'Énergie') {
      return const Zone0ActionResult(
          success: false, message: 'Ajout impossible.');
    }
    final species = operation?.species ?? PTibugSpecies.arac;
    final capacity = operation == null
        ? resource == 'Organique'
            ? pTibugConfig.cultivation.organicCapacityFor(species)
            : pTibugConfig.cultivation.mineralCapacityFor(species)
        : _cultivationRateFor(operation, resource) *
            pTibugConfig.cultivation.targetAutonomyHours;
    final stored =
        resource == 'Organique' ? tank.organicStored : tank.mineralStored;
    final added = math.min(amount, math.max(0, (capacity - stored).floor()));
    if (added <= 0 || resourceAmount(resource) < added) {
      return const Zone0ActionResult(
          success: false, message: 'Stock insuffisant ou cuve pleine.');
    }
    if (!removeResources(<String, int>{resource: added})) {
      return const Zone0ActionResult(
          success: false, message: 'Stock insuffisant.');
    }
    if (resource == 'Organique')
      tank.organicStored += added;
    else
      tank.mineralStored += added;
    _resumeCultivationIfReady(tank);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$added $resource ajoutés à la cuve.');
  }

  Zone0ActionResult openBioBatteryForCultivationTank(String tankId) {
    final tank = cultivationTankForId(tankId);
    if (tank == null || !tank.isBuilt || bioBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Bio-batterie ou cuve indisponible.');
    }
    final operation = cultivationOperationForTank(tank.id);
    final gainPerBattery = energyFromBioBatteryForBuildingLevel(
      math.max(1, plaineNurseryLevel),
    );
    final capacity = math.max(
      gainPerBattery,
      operation == null
          ? pTibugConfig.cultivation.energyCapacityFor(PTibugSpecies.arac)
          : _cultivationRateFor(operation, 'Énergie') *
              pTibugConfig.cultivation.targetAutonomyHours,
    );
    final gain = math.min(
        gainPerBattery, math.max(0, (capacity - tank.energyStored).floor()));
    if (gain <= 0)
      return const Zone0ActionResult(
          success: false, message: 'Réserve d’énergie pleine.');
    bioBatteries -= 1;
    tank.energyStored += gain;
    _resumeCultivationIfReady(tank);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$gain Énergies ajoutées à la cuve.');
  }

  Zone0ActionResult startPTibugCultivation({
    required String armatureId,
    required String tankId,
    List<String> aspectMatrixIds = const <String>[],
  }) {
    _ensureCultivationTankSlots();
    final armature =
        pTibugArmatures.where((item) => item.id == armatureId).firstOrNull;
    final tank = cultivationTankForId(tankId);
    if (armature == null ||
        !armature.isCompleted ||
        tank == null ||
        !tank.isBuilt ||
        tank.currentOperationId != null) {
      return const Zone0ActionResult(
          success: false, message: 'Armature ou cuve indisponible.');
    }
    final matrices = aspectMatrixIds
        .map((id) =>
            pTibugAspectMatrices.where((matrix) => matrix.id == id).firstOrNull)
        .whereType<PTibugAspectMatrix>()
        .toList(growable: false);
    if (aspectMatrixIds.length > 2 ||
        aspectMatrixIds.toSet().length != aspectMatrixIds.length ||
        matrices.length != aspectMatrixIds.length) {
      return const Zone0ActionResult(
        success: false,
        message: 'Sélectionnez au maximum deux Matrices disponibles.',
      );
    }
    final now = DateTime.now();
    final operation = PTibugCultivationOperation(
      id: 'ptibug-cultivation-${now.microsecondsSinceEpoch}',
      tankId: tankId,
      type: PTibugCultivationOperationType.cultivation,
      armatureId: armatureId,
      species: armature.species,
      startedAt: now,
      lastCalculatedAt: now,
      activeSecondsRequired: pTibugConfig.cultivation.activeSecondsRequired,
      aspectMatrices: matrices,
    );
    if (matrices.isNotEmpty) {
      pTibugAspectMatrices.removeWhere(
          (matrix) => matrices.any((selected) => selected.id == matrix.id));
    }
    pTibugCultivationOperations.add(operation);
    tank
      ..currentOperationId = operation.id
      ..status = PTibugCultivationTankStatus.pausedMissingResources;
    _resumeCultivationIfReady(tank);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Cultivation placée en cuve.');
  }

  int get aspectMatrixExtractorLevel => math
      .max(pTibugAspectExtractorLevel, plaineNurseryLevel)
      .clamp(1, 4)
      .toInt();
  PTibugAspectExtractionOrder? get activeAspectMatrixExtraction =>
      pTibugAspectExtractionOrder?.isActive == true
          ? pTibugAspectExtractionOrder
          : null;

  Zone0ActionResult startPTibugAspectExtraction(PTibug source) {
    final nursery = plaineNurseryTerritory;
    if (!nursery.isBuilt || isPTibugInCultivation(source)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIBUG source ou Nurserie indisponible.');
    }
    if (activeAspectMatrixExtraction != null) {
      return const Zone0ActionResult(
          success: false, message: 'L’Extracteur de matrice est déjà actif.');
    }
    final config = pTibugConfig.aspectMatrixExtractor;
    final modules = config.moduleCountFor(aspectMatrixExtractorLevel);
    final mineral = config.mineralCostPerModule * modules;
    final organic = config.organicCostPerModule * modules;
    final energy = config.nurseryEnergyCostPerModule * modules;
    if (resourceAmount('Minéral') < mineral ||
        resourceAmount('Organique') < organic) {
      return const Zone0ActionResult(
          success: false, message: 'Minéral ou Organique insuffisant.');
    }
    if (nursery.localEnergy < energy) {
      return const Zone0ActionResult(
          success: false,
          message: 'Énergie locale de la Nurserie insuffisante.');
    }
    removeResource('Minéral', mineral);
    removeResource('Organique', organic);
    nursery.localEnergy -= energy;
    final now = DateTime.now();
    pTibugAspectExtractionOrder = PTibugAspectExtractionOrder(
      id: 'aspect-matrix-${now.microsecondsSinceEpoch}',
      sourcePTibugId: source.id,
      sourceDisplayName: source.displayName,
      species: source.species,
      primaryColorHex: source.primaryColorHex,
      motifId: source.motifId,
      motifColorHex: source.motifColorHex,
      traitColorHex: source.traitColorHex,
      animationName: source.animationName,
      matrixCount: config
          .matricesFor(aspectMatrixExtractorLevel)
          .fold<int>(0, (total, count) => total + count),
      moduleCount: modules,
      startedAt: now,
      endsAt: now.add(
          Duration(minutes: config.durationFor(aspectMatrixExtractorLevel))),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Extraction lancée : ${pTibugAspectExtractionOrder!.matrixCount} Matrice(s) en préparation.',
    );
  }

  bool _resolveAspectMatrixExtraction(DateTime now) {
    final order = activeAspectMatrixExtraction;
    if (order == null || now.isBefore(order.endsAt)) return false;
    for (var index = 0; index < order.matrixCount; index++) {
      pTibugAspectMatrices.add(PTibugAspectMatrix(
        id: '${order.id}-$index',
        sourcePTibugId: order.sourcePTibugId,
        sourceDisplayName: order.sourceDisplayName,
        species: order.species,
        primaryColorHex: order.primaryColorHex,
        motifId: order.motifId,
        motifColorHex: order.motifColorHex,
        traitColorHex: order.traitColorHex,
        animationName: order.animationName,
        createdAt: now,
      ));
    }
    order.completedAt = now;
    reports.add(PtipoteMissionReport.system(
      message:
          '${order.matrixCount} Matrice(s) d’aspect de ${order.sourceDisplayName} sont prêtes.',
      sourceBuildingId: plaineNurseryTerritoryId,
      subject: 'Extracteur de matrice',
      concerned: order.sourceDisplayName,
    ));
    return true;
  }

  PTibugCultivationOperation? cultivationOperationForPTibug(String ptibugId) =>
      pTibugCultivationOperations
          .where((operation) =>
              operation.targetPtibugId == ptibugId &&
              operation.status != PTibugCultivationOperationStatus.cancelled)
          .firstOrNull;

  bool isPTibugInCultivation(PTibug bug) =>
      cultivationOperationForPTibug(bug.id) != null;

  double _cultivationRateFor(
    PTibugCultivationOperation operation,
    String resource,
  ) {
    final config = pTibugConfig.cultivation;
    final base = switch (resource) {
      'Organique' => config.organicPerActiveHour[operation.species] ?? 0,
      'Minéral' => config.mineralPerActiveHour[operation.species] ?? 0,
      _ => config.energyPerActiveHour[operation.species] ?? 0,
    };
    final coefficient = resource == 'Énergie'
        ? config.energyCoefficientFor(operation.type)
        : config.materialCoefficientFor(operation.type);
    // Coefficients describe the *total* operation cost relative to a full
    // 24 h Cultivation. Rates are scaled to the shorter 6 h / 12 h windows,
    // so a full reservoir still represents roughly eight active hours.
    final operationHours =
        operation.activeSecondsRequired / Duration.secondsPerHour;
    final rateMultiplier = operationHours <= 0
        ? coefficient
        : coefficient * config.activeHours / operationHours;
    return base * rateMultiplier;
  }

  Map<String, double> cultivationOperationTotalCosts(
    PTibugCultivationOperation operation,
  ) {
    final hours = operation.activeSecondsRequired / Duration.secondsPerHour;
    return <String, double>{
      'Organique': _cultivationRateFor(operation, 'Organique') * hours,
      'Minéral': _cultivationRateFor(operation, 'Minéral') * hours,
      'Énergie': _cultivationRateFor(operation, 'Énergie') * hours,
    };
  }

  String? _ptibugTankEligibility(PTibug bug) {
    if (!pTibugs.contains(bug)) return 'P’TIBUG introuvable.';
    if (isPTibugInCultivation(bug)) return 'Ce P’TIBUG est déjà en cuve.';
    if (bug.inactiveReason == 'En mission') {
      return 'Ce P’TIBUG est actuellement en mission.';
    }
    return null;
  }

  bool _placePTibugInCultivation(PTibug bug) {
    // A P’TIBUG entering a tank must never leave a hidden local reserve behind.
    // The regular collector keeps any material inventory overflow on the bug,
    // so this remains lossless when the global inventory is full.
    final harvested =
        bug.storedResources.isNotEmpty || bug.storedDataCells.isNotEmpty;
    if (harvested) {
      collectPTibugProductionFor(bug);
    }
    bug
      ..assignedSlotIndex = null
      ..assignedBuildingId = null
      ..nextProductionAt = null
      ..inactiveReason = 'En cuve';
    return harvested;
  }

  Zone0ActionResult startPTibugTraitInfusion({
    required PTibug bug,
    required String traitId,
    required String tankId,
  }) {
    _ensureCultivationTankSlots();
    final tank = cultivationTankForId(tankId);
    final definition = pTibugConfig.traitDefinitionFor(traitId);
    final eligibility = _ptibugTankEligibility(bug);
    final targetLevel = nextPTibugTraitLevelFor(bug, traitId);
    final progress = pTibugPatternProgress['ptibug-trait-$traitId'];
    if (tank == null || !tank.isBuilt || tank.currentOperationId != null) {
      return const Zone0ActionResult(
          success: false, message: 'Cuve indisponible.');
    }
    if (eligibility != null) {
      return Zone0ActionResult(success: false, message: eligibility);
    }
    if (definition == null || targetLevel == null) {
      return const Zone0ActionResult(
          success: false, message: 'Ce Trait ne peut pas être infusé.');
    }
    if (!isPTibugPatternActive('ptibug-trait-$traitId') ||
        (progress?.masteryLevel ?? 0) < targetLevel) {
      return Zone0ActionResult(
        success: false,
        message: 'Le Pattern doit atteindre la maîtrise $targetLevel.',
      );
    }
    final dataCost = definition.dataCostForLevel(targetLevel);
    if (!_hasPTibugData(dataCost)) {
      return const Zone0ActionResult(
          success: false, message: 'Cellules de données insuffisantes.');
    }
    final now = DateTime.now();
    final previousAssignmentId = bug.assignedBuildingId;
    _consumePTibugData(dataCost);
    final operation = PTibugCultivationOperation(
      id: 'ptibug-trait-${now.microsecondsSinceEpoch}',
      tankId: tankId,
      type: PTibugCultivationOperationType.traitInfusion,
      species: bug.species,
      startedAt: now,
      lastCalculatedAt: now,
      activeSecondsRequired: pTibugConfig.cultivation
          .activeSecondsFor(PTibugCultivationOperationType.traitInfusion),
      targetPtibugId: bug.id,
      targetTraitId: traitId,
      targetTraitRank: targetLevel,
      reservedDataCells: Map<PTibugDataFamily, int>.from(dataCost),
      previousAssignmentId: previousAssignmentId,
    );
    final harvested = _placePTibugInCultivation(bug);
    pTibugCultivationOperations.add(operation);
    tank
      ..currentOperationId = operation.id
      ..status = PTibugCultivationTankStatus.pausedMissingResources;
    _resumeCultivationIfReady(tank);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${definition.displayName} rang $targetLevel placé en infusion.${harvested ? ' Production récoltée.' : ''}',
    );
  }

  bool canEvolvePTibug(PTibug bug) {
    final config = pTibugConfig.progression;
    return !bug.isRenewed &&
        bug.renewalCount < config.maximumRenewals &&
        bug.level >= config.renewalLevel &&
        bug.biologicalTraitLevel >= 3 &&
        !isPTibugInCultivation(bug);
  }

  Zone0ActionResult startPTibugEvolution({
    required PTibug bug,
    required String tankId,
  }) {
    _ensureCultivationTankSlots();
    final tank = cultivationTankForId(tankId);
    if (tank == null || !tank.isBuilt || tank.currentOperationId != null) {
      return const Zone0ActionResult(
          success: false, message: 'Cuve indisponible.');
    }
    if (!canEvolvePTibug(bug)) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Évolution indisponible : niveau 3 et Trait I rang III requis.',
      );
    }
    final dataCost = pTibugConfig.cultivation.evolutionDataCost;
    if (!_hasPTibugData(dataCost)) {
      return const Zone0ActionResult(
          success: false, message: 'Cellules de données insuffisantes.');
    }
    final now = DateTime.now();
    final previousAssignmentId = bug.assignedBuildingId;
    _consumePTibugData(dataCost);
    final operation = PTibugCultivationOperation(
      id: 'ptibug-evolution-${now.microsecondsSinceEpoch}',
      tankId: tankId,
      type: PTibugCultivationOperationType.evolution,
      species: bug.species,
      startedAt: now,
      lastCalculatedAt: now,
      activeSecondsRequired: pTibugConfig.cultivation
          .activeSecondsFor(PTibugCultivationOperationType.evolution),
      targetPtibugId: bug.id,
      targetEvolutionLevel: 1,
      reservedDataCells: Map<PTibugDataFamily, int>.from(dataCost),
      previousAssignmentId: previousAssignmentId,
    );
    final harvested = _placePTibugInCultivation(bug);
    pTibugCultivationOperations.add(operation);
    tank
      ..currentOperationId = operation.id
      ..status = PTibugCultivationTankStatus.pausedMissingResources;
    _resumeCultivationIfReady(tank);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Évolution placée en cuve.${harvested ? ' Production récoltée.' : ''}',
    );
  }

  void _resumeCultivationIfReady(PTibugCultivationTank tank) {
    final operation = cultivationOperationForTank(tank.id);
    if (operation == null || operation.isCompleted) return;
    final ready = tank.organicStored >=
            _cultivationRateFor(operation, 'Organique') / 3600 &&
        tank.mineralStored >=
            _cultivationRateFor(operation, 'Minéral') / 3600 &&
        plaineNurseryTerritory.localEnergy >=
            _cultivationRateFor(operation, 'Énergie') / 3600;
    if (!ready) return;
    final resumed = operation.status ==
        PTibugCultivationOperationStatus.pausedMissingResources;
    operation
      ..status = PTibugCultivationOperationStatus.active
      ..pauseReason = null
      ..lastCalculatedAt = DateTime.now();
    tank.status = PTibugCultivationTankStatus.active;
    if (resumed) {
      reports.add(PtipoteMissionReport.system(
        message:
            'Cuve ${tank.slotIndex + 1} : ${_cultivationOperationLabel(operation)} a repris.',
        sourceBuildingId: 'plaineNursery',
        mailbox: Zone0MessageMailbox.companions,
        subject: '${_cultivationOperationLabel(operation)} reprise',
      ));
    }
  }

  /// Cultivation uses the Nurserie’s shared local energy, not a private tank
  /// battery. Opening a Bio-battery must wake every paused tank whose other
  /// local resources are ready as well.
  bool _resumePausedCultivationTanks() {
    var resumed = false;
    for (final tank in pTibugCultivationTanks) {
      final operation = cultivationOperationForTank(tank.id);
      if (operation?.status !=
          PTibugCultivationOperationStatus.pausedMissingResources) {
        continue;
      }
      _resumeCultivationIfReady(tank);
      if (operation?.status == PTibugCultivationOperationStatus.active) {
        resumed = true;
      }
    }
    return resumed;
  }

  double cultivationTankAutonomyHours(
      PTibugCultivationTank tank, String resource) {
    final operation = cultivationOperationForTank(tank.id);
    if (operation == null) return 0;
    final rate = _cultivationRateFor(operation, resource);
    final stored = switch (resource) {
      'Organique' => tank.organicStored,
      'Minéral' => tank.mineralStored,
      _ => plaineNurseryTerritory.localEnergy,
    };
    return rate <= 0 ? double.infinity : stored / rate;
  }

  String _cultivationOperationLabel(PTibugCultivationOperation operation) =>
      switch (operation.type) {
        PTibugCultivationOperationType.cultivation => 'Cultivation',
        PTibugCultivationOperationType.traitInfusion => 'Infusion de Trait',
        PTibugCultivationOperationType.evolution => 'Évolution',
      };

  String _cultivationCompletionMessage(
    PTibugCultivationOperation operation,
    PTibugCultivationTank tank,
  ) =>
      switch (operation.type) {
        PTibugCultivationOperationType.cultivation =>
          'Cuve ${tank.slotIndex + 1} : votre P’TIBUG est prêt.',
        PTibugCultivationOperationType.traitInfusion =>
          'Cuve ${tank.slotIndex + 1} : le Trait ${pTibugConfig.traitDefinitionFor(operation.targetTraitId ?? '')?.displayName ?? ''} est prêt à être appliqué.',
        PTibugCultivationOperationType.evolution =>
          'Cuve ${tank.slotIndex + 1} : l’Évolution de votre P’TIBUG est terminée.',
      };

  void _resolveCultivation(DateTime current) {
    _ensureCultivationTankSlots();
    var changed = _resolveAspectMatrixExtraction(current);
    changed = _resumePausedCultivationTanks() || changed;
    for (final armature in pTibugArmatures.where((item) => item.isCrafting)) {
      if (armature.completesAt.isAfter(current)) continue;
      armature
        ..status = PTibugArmatureStatus.completed
        ..updatedAt = current;
      reports.add(PtipoteMissionReport.system(
        message:
            'Armature ${pTibugConfig.species[armature.species]!.displayName} terminée : place-la dans une cuve.',
        sourceBuildingId: 'plaineNursery',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Armature prête',
      ));
      changed = true;
    }
    for (final tank in pTibugCultivationTanks) {
      if (tank.status == PTibugCultivationTankStatus.underConstruction &&
          tank.constructionEndsAt != null &&
          !tank.constructionEndsAt!.isAfter(current)) {
        tank
          ..isBuilt = true
          ..status = PTibugCultivationTankStatus.available
          ..constructionEndsAt = null;
        reports.add(PtipoteMissionReport.system(
          message: 'Cuve ${tank.slotIndex + 1} construite dans la Nurserie.',
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Cuve prête',
        ));
        changed = true;
      }
      final operation = cultivationOperationForTank(tank.id);
      if (operation == null ||
          operation.status != PTibugCultivationOperationStatus.active) continue;
      final elapsed =
          math.max(0, current.difference(operation.lastCalculatedAt).inSeconds);
      if (elapsed == 0) continue;
      final organicRate = _cultivationRateFor(operation, 'Organique') / 3600;
      final mineralRate = _cultivationRateFor(operation, 'Minéral') / 3600;
      final energyRate = _cultivationRateFor(operation, 'Énergie') / 3600;
      final nursery = plaineNurseryTerritory;
      final availability = <double>[
        operation.activeSecondsRemaining.toDouble(),
        elapsed.toDouble(),
        organicRate <= 0 ? double.infinity : tank.organicStored / organicRate,
        mineralRate <= 0 ? double.infinity : tank.mineralStored / mineralRate,
        energyRate <= 0 ? double.infinity : nursery.localEnergy / energyRate,
      ].reduce(math.min);
      final activeSeconds = math.max(0, availability.floor());
      if (activeSeconds > 0) {
        tank
          ..organicStored =
              math.max(0, tank.organicStored - organicRate * activeSeconds)
          ..mineralStored =
              math.max(0, tank.mineralStored - mineralRate * activeSeconds)
          ..energyStored = tank.energyStored;
        nursery.localEnergy =
            math.max(0, nursery.localEnergy - energyRate * activeSeconds);
        operation
          ..activeSecondsCompleted = math.min(operation.activeSecondsRequired,
              operation.activeSecondsCompleted + activeSeconds)
          ..lastCalculatedAt =
              operation.lastCalculatedAt.add(Duration(seconds: activeSeconds));
        changed = true;
      }
      if (operation.activeSecondsCompleted >= operation.activeSecondsRequired) {
        operation
          ..status = PTibugCultivationOperationStatus.completed
          ..completedAt = current;
        tank.status = PTibugCultivationTankStatus.completed;
        reports.add(PtipoteMissionReport.system(
          message: _cultivationCompletionMessage(operation, tank),
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: '${_cultivationOperationLabel(operation)} terminée',
        ));
        changed = true;
        continue;
      }
      if (activeSeconds < elapsed) {
        final reasons = <String>[
          if (organicRate > 0 && tank.organicStored <= 0.0001) 'Organique',
          if (mineralRate > 0 && tank.mineralStored <= 0.0001) 'Minéral',
          if (energyRate > 0 && nursery.localEnergy <= 0.0001)
            'Énergie Nurserie',
        ];
        operation
          ..status = PTibugCultivationOperationStatus.pausedMissingResources
          ..pauseReason =
              reasons.isEmpty ? 'Ressources insuffisantes' : reasons.join(', ');
        tank.status = PTibugCultivationTankStatus.pausedMissingResources;
        reports.add(PtipoteMissionReport.system(
          message:
              'Cuve ${tank.slotIndex + 1} : ${_cultivationOperationLabel(operation)} en pause, ${operation.pauseReason} insuffisant.',
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: '${_cultivationOperationLabel(operation)} en pause',
        ));
        changed = true;
      }
    }
    if (changed) unawaited(saveRuntimeToFirebase());
  }

  Zone0ActionResult applyCultivationTap(String tankId, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final tank = cultivationTankForId(tankId);
    final operation =
        tank == null ? null : cultivationOperationForTank(tank.id);
    if (tank == null ||
        operation == null ||
        operation.status != PTibugCultivationOperationStatus.active) {
      return const Zone0ActionResult(
          success: false,
          message: 'Aucune Cultivation active dans cette cuve.');
    }
    final config = pTibugConfig.cultivation;
    operation.tapSessions
        .removeWhere((time) => current.difference(time).inHours >= 24);
    if (operation.tapSessions.length >= config.tapMaximumPerDay ||
        (operation.tapSessions.isNotEmpty &&
            current.difference(operation.tapSessions.last).inHours <
                config.tapMinimumDelayHours)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Prochaine séance de tapotement indisponible.');
    }
    final bonus = math.min(config.tapBonusFor(operation.type) * 60,
        operation.activeSecondsRemaining);
    operation
      ..tapSessions.add(current)
      ..bonusSecondsApplied += bonus
      ..activeSecondsCompleted += bonus;
    if (operation.activeSecondsCompleted >= operation.activeSecondsRequired) {
      operation
        ..status = PTibugCultivationOperationStatus.completed
        ..completedAt = current;
      tank.status = PTibugCultivationTankStatus.completed;
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Tapotement réussi : +${bonus ~/ 60} min de ${_cultivationOperationLabel(operation)}.');
  }

  Zone0ActionResult openCultivationTank(String tankId) {
    final tank = cultivationTankForId(tankId);
    final operation =
        tank == null ? null : cultivationOperationForTank(tank.id);
    if (tank == null || operation == null || !operation.isCompleted) {
      return const Zone0ActionResult(
          success: false,
          message: 'Cette cuve n’est pas prête à être finalisée.');
    }
    if (operation.type != PTibugCultivationOperationType.cultivation) {
      return _completePTibugTankOperation(tank, operation);
    }
    final armature = pTibugArmatures
        .where((item) => item.id == operation.armatureId)
        .firstOrNull;
    if (armature == null || operation.resultPtibugId != null) {
      return const Zone0ActionResult(
          success: false,
          message: 'Cette cuve n’est pas prête à être ouverte.');
    }
    final config = pTibugConfig.species[operation.species]!;
    final id = 'ptibug-${DateTime.now().microsecondsSinceEpoch}';
    final temporaryName =
        '${config.displayName} ${id.substring(id.length - 4)}';
    final createdBug = PTibug(
      id: id,
      displayName: temporaryName,
      defaultDisplayName: temporaryName,
      species: operation.species,
      styleVariant: config.styles[_random.nextInt(config.styles.length)],
      createdAt: DateTime.now(),
    );
    _applyCultivationAppearance(createdBug, operation.aspectMatrices);
    pTibugs.add(createdBug);
    operation.resultPtibugId = id;
    pTibugArmatures.remove(armature);
    pTibugCultivationOperations.remove(operation);
    tank
      ..currentOperationId = null
      ..status = PTibugCultivationTankStatus.available;
    emitKernelProgressEvent(KernelProgressEventType.ptibugCreated);
    refreshKernelMissions();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '$temporaryName rejoint la Collection.');
  }

  void _applyCultivationAppearance(
      PTibug bug, List<PTibugAspectMatrix> matrices) {
    if (matrices.isEmpty) {
      _ensurePTibugAppearance(bug);
      return;
    }
    final first = matrices.first;
    final second = matrices.length > 1 ? matrices[1] : null;
    PTibugAspectMatrix? pick(PTibugAspectMatrix? a, PTibugAspectMatrix? b) {
      if (b == null) return _random.nextBool() ? a : null;
      return _random.nextBool() ? a : b;
    }

    final primary = pick(first, second);
    final motif = pick(first, second);
    final motifColor = pick(first, second);
    final traitColor = pick(first, second);
    final animation = pick(first, second);
    bug
      ..primaryColorHex = primary?.primaryColorHex
      ..motifId = motif?.motifId
      ..motifColorHex = motifColor?.motifColorHex
      ..traitColorHex = traitColor?.traitColorHex
      ..animationName = animation?.animationName;
    // Une caractéristique non héritée reste aléatoire plutôt que vide.
    _ensurePTibugAppearance(bug);
  }

  Zone0ActionResult _completePTibugTankOperation(
    PTibugCultivationTank tank,
    PTibugCultivationOperation operation,
  ) {
    final bug = pTibugs
        .where((item) => item.id == operation.targetPtibugId)
        .firstOrNull;
    if (bug == null || operation.resultAppliedAt != null) {
      return const Zone0ActionResult(
          success: false,
          message: 'Résultat de cuve déjà appliqué ou indisponible.');
    }
    final now = DateTime.now();
    switch (operation.type) {
      case PTibugCultivationOperationType.traitInfusion:
        final traitId = operation.targetTraitId;
        final targetRank = operation.targetTraitRank;
        final definition =
            traitId == null ? null : pTibugConfig.traitDefinitionFor(traitId);
        if (traitId == null || targetRank == null || definition == null) {
          return const Zone0ActionResult(
              success: false, message: 'Trait d’infusion invalide.');
        }
        if (bug.biologicalTraitId == null || bug.biologicalTraitId == traitId) {
          bug
            ..biologicalTraitId = traitId
            ..biologicalTraitLevel = targetRank;
        } else if (bug.secondTraitId == null || bug.secondTraitId == traitId) {
          bug
            ..secondTraitId = traitId
            ..secondTraitLevel = targetRank;
        } else {
          return const Zone0ActionResult(
              success: false, message: 'Les deux Traits sont déjà distincts.');
        }
        // An Infusion changes biological data only. The species, level and
        // cosmetic identity were chosen at Cultivation and must remain stable:
        // never re-roll primary colour, motif or animation here.
        emitKernelProgressEvent(KernelProgressEventType.ptibugTraitEquipped);
        reports.add(PtipoteMissionReport.system(
          message:
              '${bug.displayName} reçoit ${definition.displayName} rang $targetRank. Aspect : ${pTibugAppearanceLabelFor(bug)}.',
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Infusion terminée',
          concerned: bug.displayName,
        ));
        break;
      case PTibugCultivationOperationType.evolution:
        bug
          ..isRenewed = true
          ..renewedAt = now
          ..renewalCount = math.max(1, bug.renewalCount + 1);
        reports.add(PtipoteMissionReport.system(
          message:
              '${bug.displayName} a achevé son Évolution. Le second Trait est désormais accessible au niveau 4.',
          sourceBuildingId: 'plaineNursery',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Évolution terminée',
          concerned: bug.displayName,
        ));
        break;
      case PTibugCultivationOperationType.cultivation:
        return const Zone0ActionResult(
            success: false, message: 'Utilise l’ouverture de Cultivation.');
    }
    operation.resultAppliedAt = now;
    pTibugCultivationOperations.remove(operation);
    tank
      ..currentOperationId = null
      ..status = PTibugCultivationTankStatus.available;
    bug
      ..inactiveReason = 'En attente de réaffectation'
      ..nextProductionAt = null;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: operation.type == PTibugCultivationOperationType.evolution
          ? 'Évolution achevée : ${bug.displayName} est disponible.'
          : 'Infusion achevée : ${bug.displayName} est disponible.',
    );
  }

  Zone0ActionResult cancelPTibugCultivation(String tankId) {
    final tank = cultivationTankForId(tankId);
    final operation =
        tank == null ? null : cultivationOperationForTank(tank.id);
    final armature = operation == null
        ? null
        : pTibugArmatures
            .where((item) => item.id == operation.armatureId)
            .firstOrNull;
    if (tank == null || operation == null || operation.isCompleted) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune Cultivation annulable dans cette cuve.',
      );
    }
    operation.status = PTibugCultivationOperationStatus.cancelled;
    if (armature != null) armature.status = PTibugArmatureStatus.completed;
    final bug = pTibugs
        .where((item) => item.id == operation.targetPtibugId)
        .firstOrNull;
    if (bug != null) {
      for (final entry in operation.reservedDataCells.entries) {
        pTibugDataReserve[entry.key] =
            (pTibugDataReserve[entry.key] ?? 0) + entry.value;
      }
      bug
        ..inactiveReason = 'En attente de réaffectation'
        ..nextProductionAt = null;
    }
    tank
      ..currentOperationId = null
      ..status = PTibugCultivationTankStatus.available;
    pTibugCultivationOperations.remove(operation);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${_cultivationOperationLabel(operation)} annulée : les réserves et Cellules non consommées sont restituées.',
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
          message:
              'Le module ${order.moduleType.displayName} est prêt.${order.assignedPtipoteId == null ? '' : ' ${order.assignedPtipoteName} gagne 10 XP.'}',
          sourceBuildingId: 'fablab',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: order.assignedPtipoteName ?? 'Le joueur',
          summary:
              'Module P’TIBUG ${order.moduleType.displayName} créé${order.assignedPtipoteId == null ? '.' : ' · +10 XP.'}',
        ),
      );
      if (order.assignedPtipoteId != null) {
        addMissionXp(order.assignedPtipoteId!, 10);
      }
      changed = true;
    }
    return changed;
  }

  Zone0ActionResult startPTibugModuleCraft(
    PTibugModuleType type, {
    PtipoteFigurine? figurine,
  }) {
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
    resolveWorkshopOrder();
    if (figurine == null && activeManualWorkshopOrders >= 1) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le créneau manuel de l’Atelier est occupé.',
      );
    }
    if (figurine != null && activePtipoteWorkshopOrders >= workshopSlots) {
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
    final cost = pTibugConfig.moduleCraftCostFor(type);
    final energyCost = math.max(
      0,
      pTibugConfig.moduleCraftEnergyFor(type) -
          _activePTibugEffect('Réduction énergie'),
    );
    final totalEnergyCost = energyCost + (figurine == null ? 1 : 0);
    if (!hasResources(cost) || energyUnits < totalEnergyCost) {
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
    energyUnits -= totalEnergyCost;
    final current = DateTime.now();
    final duration = Duration(
      minutes: pTibugConfig.moduleCraftMinutesFor(type),
    );
    final speedBonus = craftSpeedBonus(figurine, atelierLevel);
    pTibugModuleCraftOrders.add(
      PTibugModuleCraftOrder(
        id: current.microsecondsSinceEpoch.toString(),
        moduleType: type,
        startedAt: current,
        endsAt: current.add(Duration(
          seconds: math.max(1, (duration.inSeconds * (1 - speedBonus)).round()),
        )),
        assignedPtipoteId: figurine?.id,
        assignedPtipoteName: figurine?.displayName,
        energyCost: totalEnergyCost,
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Fabrication de ${type.displayName} lancée${figurine == null ? ' manuellement' : ' avec ${figurine.displayName}'}.',
    );
  }

  /// Returns the only biological Trait level this P'TIBUG may receive next.
  /// Traits are permanent, but their own Pattern can improve them one level
  /// at a time. A different Trait can never replace the existing one.
  int? nextPTibugTraitLevelFor(PTibug bug, String traitId) {
    final definition = pTibugConfig.traitDefinitionFor(traitId);
    if (!pTibugs.contains(bug) || definition == null) {
      return null;
    }
    if (bug.biologicalTraitId == null) return bug.level >= 1 ? 1 : null;
    if (bug.biologicalTraitId == traitId) {
      final nextLevel = bug.biologicalTraitLevel + 1;
      return nextLevel <= definition.maxLevel &&
              nextLevel <= bug.level.clamp(1, 3)
          ? nextLevel
          : null;
    }
    if (!bug.isRenewed || bug.level < 4) {
      return null;
    }
    if (bug.secondTraitId == null)
      return traitId == bug.biologicalTraitId ? null : 1;
    if (bug.secondTraitId != traitId) return null;
    final nextLevel = bug.secondTraitLevel + 1;
    return nextLevel <= definition.maxLevel && nextLevel <= bug.level - 3
        ? nextLevel
        : null;
  }

  /// Legacy entry point intentionally kept for old integrations: traits are
  /// no longer applied instantly and must always go through a cultivation tank.
  @Deprecated('Utiliser startPTibugTraitInfusion.')
  Zone0ActionResult applyPTibugPermanentTrait({
    required PTibug bug,
    required String traitId,
  }) {
    return const Zone0ActionResult(
      success: false,
      message:
          'L’infusion d’un Trait doit désormais être lancée dans une cuve.',
    );
  }

  /// Compatibility alias for saves and integrations that still use the former
  /// technical name. The player-facing system is now always Évolution.
  bool canRenewPTibug(PTibug bug) => canEvolvePTibug(bug);

  Zone0ActionResult renewPTibug(PTibug bug) {
    return const Zone0ActionResult(
      success: false,
      message:
          'L’Évolution doit désormais être lancée dans une cuve de la Nurserie.',
    );
  }

  Zone0ActionResult upgradePTibugModuleCapacity() {
    final config = pTibugConfig.moduleCapacity;
    final targetLevel = pTibugModuleCapacityLevel + 1;
    if (targetLevel > config.maximumUpgrades) {
      return const Zone0ActionResult(
          success: false, message: 'Capacité de Modules maximale atteinte.');
    }
    final materials =
        config.materialCostsByLevel[targetLevel] ?? const <String, int>{};
    final data =
        config.dataCostsByLevel[targetLevel] ?? const <PTibugDataFamily, int>{};
    final batteries = config.bioBatteryCostsByLevel[targetLevel] ?? 0;
    if (!hasResources(materials) ||
        !_hasPTibugData(data) ||
        bioBatteries < batteries) {
      return const Zone0ActionResult(
          success: false,
          message: 'Matériaux, Bio-batteries ou données insuffisants.');
    }
    if (!removeResources(materials)) {
      return const Zone0ActionResult(
          success: false, message: 'Matériaux insuffisants.');
    }
    _consumePTibugData(data);
    bioBatteries -= batteries;
    pTibugModuleCapacityLevel = targetLevel;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Capacité globale : $maxModulesPerPTibug Modules par P’TIBUG.');
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
    if (isPTibugInCultivation(bug)) {
      return const Zone0ActionResult(
          success: false, message: 'Module indisponible : P’TIBUG en cuve.');
    }
    if (instance == null ||
        instance.isEquipped ||
        !pTibugs.contains(bug) ||
        equippedModules.any((item) => item.type == instance.type) ||
        equippedModules.length >= maxModulesPerPTibug) {
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
    if (isPTibugInCultivation(bug)) {
      return const Zone0ActionResult(
          success: false, message: 'Module indisponible : P’TIBUG en cuve.');
    }
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
    final blocker = pTibugCertificationBlocker(bug);
    if (blocker != null) {
      return Zone0ActionResult(success: false, message: blocker);
    }
    const mineralCost = 10;
    if (bioBatteries < pTibugConfig.capsuleEnergyCost ||
        resourceAmount('Minéral') < mineralCost) {
      return Zone0ActionResult(
        success: false,
        message:
            'Coût : ${pTibugConfig.capsuleEnergyCost} bio-batterie et $mineralCost Minéral.',
      );
    }
    final now = DateTime.now();
    final valuation = pTibugValuationFor(bug);
    bioBatteries -= pTibugConfig.capsuleEnergyCost;
    removeResource('Minéral', mineralCost);
    pTibugCapsules.add(PTibugCapsule(
      id: 'capsule-${now.microsecondsSinceEpoch}',
      sourcePtibugId: bug.id,
      species: bug.species,
      styleVariant: bug.styleVariant,
      displayName: bug.displayName,
      primaryColorHex: bug.primaryColorHex,
      motifId: bug.motifId,
      motifColorHex: bug.motifColorHex,
      traitColorHex: bug.traitColorHex,
      animationName: bug.animationName,
      biologicalTraitId: bug.biologicalTraitId,
      biologicalTraitLevel: bug.biologicalTraitLevel,
      secondTraitId: bug.secondTraitId,
      secondTraitLevel: bug.secondTraitLevel,
      isEvolved: bug.isRenewed,
      moduleSnapshots: bug.equippedModules.map((item) => item.name).toList(),
      level: bug.level,
      xp: bug.xp,
      baseValueSnapshot: valuation.baseValue,
      levelValueSnapshot: valuation.levelValue,
      traitValueSnapshot: valuation.traitValue,
      moduleValueSnapshot: valuation.moduleValue,
      estimatedValueSnapshot: valuation.total,
      valuationConfigVersion: valuation.configVersion,
      certificationId: 'capsule-${bug.id}-${now.microsecondsSinceEpoch}',
      createdAt: now,
    ));
    for (final module in pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id)) {
      module.equippedPTibugId = null;
    }
    pTibugs.remove(bug);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'P’TIBUG placé en Capsule.',
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
    if (pTibugs.length >= pTibugConfig.nurseryReserveCapacity) {
      return Zone0ActionResult(
        success: false,
        message:
            'La r\u00e9serve de la Nurserie est pleine (${pTibugConfig.nurseryReserveCapacity}).',
      );
    }
    pTibugCapsules.remove(capsule);
    pTibugs.add(
      PTibug(
        id: 'ptibug-${DateTime.now().microsecondsSinceEpoch}',
        displayName: capsule.displayName,
        species: capsule.species,
        styleVariant: capsule.styleVariant,
        primaryColorHex: capsule.primaryColorHex,
        motifId: capsule.motifId,
        motifColorHex: capsule.motifColorHex,
        traitColorHex: capsule.traitColorHex,
        animationName: capsule.animationName,
        createdAt: DateTime.now(),
        level: capsule.level,
        xp: capsule.xp,
        biologicalTraitId: capsule.biologicalTraitId,
        biologicalTraitLevel: capsule.biologicalTraitLevel,
        secondTraitId: capsule.secondTraitId,
        secondTraitLevel: capsule.secondTraitLevel,
        isRenewed: capsule.isEvolved,
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
    _resolveEnergyCoreMilestones();
    _resolveCultivation(current);
    if (_resolvePTibugTerritoryConsumption(current)) {
      changed = true;
    }
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
      refreshKernelMissions();
      changed = true;
    }
    for (final bug in pTibugs.where(
      (item) => item.assignedBuildingId != null && item.inactiveReason == null,
    )) {
      final building = territoryBuildingForId(bug.assignedBuildingId);
      if (building != null && isTerritoryUnderConstruction(building)) {
        bug
          ..inactiveReason = 'Travaux en cours'
          ..nextProductionAt = null;
        changed = true;
        continue;
      }
      if (building != null && !isBuildingOperational(building.id)) {
        bug
          ..inactiveReason =
              '${building.kind == PTibugTerritoryKind.nursery ? 'Nurserie' : 'Refuge'} hors service'
          ..nextProductionAt = null;
        changed = true;
        continue;
      }
      final capacity = _pTibugCapacity(bug);
      // Also pause saves written by older builds: their full-stock marker may
      // coexist with an overdue cycle timestamp, especially after capacity
      // tuning changes.
      if (bug.stockFullNotified) {
        if (bug.nextProductionAt != null) {
          bug.nextProductionAt = null;
          changed = true;
        }
        continue;
      }
      if (bug.storedAmount >= capacity) {
        // A full internal stock pauses production. Keeping an overdue date here
        // would replay every elapsed cycle immediately after a collection.
        if (bug.nextProductionAt != null) {
          bug.nextProductionAt = null;
          changed = true;
        }
        if (!bug.stockFullNotified) {
          bug.stockFullNotified = true;
          reports.add(
            PtipoteMissionReport.system(
              message: '${bug.displayName} a atteint sa capacité de stockage.',
              sourceBuildingId: 'plaineNursery',
              mailbox: Zone0MessageMailbox.companions,
              subject: 'Stock P’TIBUG plein',
              concerned: bug.displayName,
              summary: 'Production en pause jusqu’à la récolte.',
            ),
          );
          changed = true;
        }
        continue;
      }
      final next = bug.nextProductionAt;
      if (next == null || next.isAfter(current)) {
        continue;
      }
      var cycleAt = next;
      var producedCycles = 0;
      while (!cycleAt.isAfter(current) && bug.storedAmount < capacity) {
        final production = _pTibugProduction(bug);
        if (bug.storedAmount +
                production.values.fold(0, (total, value) => total + value) >
            capacity) {
          break;
        }
        production.forEach((resource, amount) {
          bug.storedResources[resource] =
              (bug.storedResources[resource] ?? 0) + amount;
        });
        _tryDetectSensorDataCell(bug, cycleAt);
        _gainPTibugXp(bug, pTibugConfig.xpPerCycle);
        producedCycles += 1;
        cycleAt = cycleAt.add(_pTibugCycleDuration(bug));
      }
      // Do not keep a due timestamp when the stock cannot accept another
      // cycle. Collection explicitly schedules the next production cycle.
      bug.nextProductionAt = bug.storedAmount >= capacity ? null : cycleAt;
      if (producedCycles > 0) {
        _applyPTibugStability(bug, producedCycles);
      }
      if (bug.storedAmount >= capacity && !bug.stockFullNotified) {
        bug.stockFullNotified = true;
        reports.add(
          PtipoteMissionReport.system(
            message: '${bug.displayName} a atteint sa capacité de stockage.',
            sourceBuildingId: 'plaineNursery',
            mailbox: Zone0MessageMailbox.companions,
            subject: 'Stock P’TIBUG plein',
            concerned: bug.displayName,
            summary: 'Production en pause jusqu’à la récolte.',
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

  void _gainPTibugXp(PTibug bug, int amount) {
    final config = pTibugConfig.progression;
    if (bug.level >= config.maximumLevel) return;
    final wasEvolutionReady = canEvolvePTibug(bug);
    bug.xp += amount;
    while (bug.level < config.maximumLevel) {
      final required = config.xpForNextLevel(bug.level);
      if (required <= 0 || bug.xp < required) break;
      bug.xp -= required;
      bug.level += 1;
    }
    if (!wasEvolutionReady && canEvolvePTibug(bug)) {
      reports.add(
        PtipoteMissionReport.system(
          message:
              '${bug.displayName} peut désormais évoluer dans une cuve de la Nurserie.',
          sourceBuildingId: plaineNurseryTerritoryId,
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Évolution disponible',
          concerned: bug.displayName,
          summary: 'Niveau et Trait I requis atteints.',
        ),
      );
    }
  }

  bool _resolvePTibugTerritoryConsumption(DateTime current) {
    var changed = false;
    for (final building in activePTibugTerritories) {
      if (isTerritoryUnderConstruction(building)) continue;
      if (!isBuildingOperational(building.id)) {
        for (final bug in pTibugsForTerritory(building.id)) {
          bug
            ..inactiveReason =
                '${building.kind == PTibugTerritoryKind.nursery ? 'Nurserie' : 'Refuge'} hors service'
            ..nextProductionAt = null;
        }
        building.lastConsumptionAt = current;
        changed = true;
        continue;
      }
      final previous = building.lastConsumptionAt ?? current;
      final elapsedHours = math.max(0, current.difference(previous).inHours);
      final residents = pTibugsForTerritory(building.id);
      final organicCycles =
          elapsedHours ~/ math.max(1, pTibugConfig.territory.organicEveryHours);
      final mineralCycles =
          elapsedHours ~/ math.max(1, pTibugConfig.territory.mineralEveryHours);
      final moduleEnergyCycles = elapsedHours ~/
          math.max(1, pTibugConfig.territory.moduleEnergyEveryHours);
      final buildingEnergyEveryHours =
          building.kind == PTibugTerritoryKind.nursery
              ? pTibugConfig.territory.nurseryEnergyEveryHours
              : pTibugConfig.territory.refugeEnergyEveryHours;
      final buildingEnergyAmount = building.kind == PTibugTerritoryKind.nursery
          ? pTibugConfig.territory.nurseryEnergyAmount
          : pTibugConfig.territory.refugeEnergyAmount;
      final buildingEnergyCycles =
          elapsedHours ~/ math.max(1, buildingEnergyEveryHours);
      final equippedResidents = residents
          .where((bug) =>
              bug.equippedModules.isNotEmpty ||
              bug.equippedModuleInstanceIds.isNotEmpty)
          .length;
      final organicExact = building.pTibugOrganicRemainder +
          residents.fold<double>(
            0,
            (total, bug) =>
                total +
                organicCycles *
                    pTibugConfig.territory.organicAmount *
                    pTibugConfig.weather.multiplierForPenalty(
                      _pTibugEffectFor(bug, 'Réduction Organique %'),
                    ),
          );
      final organicNeed = organicExact.floor();
      final mineralNeed = residents.length *
          mineralCycles *
          pTibugConfig.territory.mineralAmount;
      final bugEnergyExact = building.pTibugEnergyRemainder +
          residents.fold<double>(
            0,
            (total, bug) =>
                total +
                pTibugConfig.progression.baseEnergyPerDayForLevel(bug.level) *
                    pTibugConfig.weather.multiplierForPenalty(
                      _pTibugEffectFor(bug, 'Réduction énergie %'),
                    ) *
                    elapsedHours /
                    24,
          );
      final bugEnergyNeed = bugEnergyExact.floor();
      final energyNeed = buildingEnergyCycles * buildingEnergyAmount +
          bugEnergyNeed +
          equippedResidents *
              moduleEnergyCycles *
              pTibugConfig.territory.moduleEnergyAmount;
      if (organicNeed == 0 && mineralNeed == 0 && energyNeed == 0) {
        for (final bug in residents) {
          if (bug.inactiveReason != null) {
            bug.inactiveReason = null;
            bug.nextProductionAt ??= current.add(_pTibugCycleDuration(bug));
            changed = true;
          }
        }
        continue;
      }
      final missing = building.resourceAmount('Organique') < organicNeed
          ? 'Organique insuffisant'
          : building.resourceAmount('Minéral') < mineralNeed
              ? 'Minéral insuffisant'
              : building.localEnergy < energyNeed
                  ? 'Énergie locale insuffisante'
                  : null;
      if (missing != null) {
        for (final bug in residents) {
          bug
            ..inactiveReason = missing
            ..nextProductionAt = null;
        }
        building.lastConsumptionAt = current;
        building.pTibugOrganicRemainder = 0;
        building.pTibugEnergyRemainder = 0;
        changed = true;
        continue;
      }
      if (organicNeed > 0) {
        building.localResources['Organique'] =
            building.resourceAmount('Organique') - organicNeed;
      }
      if (mineralNeed > 0) {
        building.localResources['Minéral'] =
            building.resourceAmount('Minéral') - mineralNeed;
      }
      if (energyNeed > 0) building.localEnergy -= energyNeed;
      building.lastConsumptionAt = current;
      building.pTibugOrganicRemainder = organicExact - organicNeed;
      building.pTibugEnergyRemainder = bugEnergyExact - bugEnergyNeed;
      for (final bug in residents) {
        if (bug.inactiveReason != null) {
          bug.inactiveReason = null;
          bug.nextProductionAt ??= current.add(_pTibugCycleDuration(bug));
        }
      }
      changed = true;
    }
    return changed;
  }

  PTibugTerritoryConsumption pTibugTerritoryDailyConsumption(
    PTibugTerritoryBuilding building,
  ) {
    final residents = pTibugsForTerritory(building.id);
    final territory = pTibugConfig.territory;
    int perDay(int amount, int everyHours) =>
        (amount * 24 / math.max(1, everyHours)).ceil();
    final equipped = residents
        .where((bug) =>
            bug.equippedModules.isNotEmpty ||
            bug.equippedModuleInstanceIds.isNotEmpty)
        .length;
    final buildingEnergy = building.kind == PTibugTerritoryKind.nursery
        ? perDay(
            territory.nurseryEnergyAmount, territory.nurseryEnergyEveryHours)
        : perDay(
            territory.refugeEnergyAmount, territory.refugeEnergyEveryHours);
    return PTibugTerritoryConsumption(
      organicPerDay: residents.fold<int>(
        0,
        (total, bug) =>
            total +
            (perDay(territory.organicAmount, territory.organicEveryHours) *
                    pTibugConfig.weather.multiplierForPenalty(
                      _pTibugEffectFor(bug, 'Réduction Organique %'),
                    ))
                .ceil(),
      ),
      mineralPerDay: residents.length *
          perDay(territory.mineralAmount, territory.mineralEveryHours),
      energyPerDay: buildingEnergy +
          residents.fold<int>(
            0,
            (total, bug) =>
                total +
                (pTibugConfig.progression.baseEnergyPerDayForLevel(bug.level) *
                        pTibugConfig.weather.multiplierForPenalty(
                          _pTibugEffectFor(bug, 'Réduction énergie %'),
                        ))
                    .ceil(),
          ) +
          equipped *
              perDay(territory.moduleEnergyAmount,
                  territory.moduleEnergyEveryHours),
    );
  }

  Map<String, double> pTibugDailyConsumptionFor(PTibug bug) {
    final territory = pTibugConfig.territory;
    double perDay(int amount, int everyHours) =>
        amount * 24 / math.max(1, everyHours);
    final organic =
        perDay(territory.organicAmount, territory.organicEveryHours) *
            pTibugConfig.weather.multiplierForPenalty(
              _pTibugEffectFor(bug, 'Réduction Organique %'),
            );
    final mineral =
        perDay(territory.mineralAmount, territory.mineralEveryHours);
    final energy = pTibugConfig.progression
                .baseEnergyPerDayForLevel(bug.level) *
            pTibugConfig.weather.multiplierForPenalty(
              _pTibugEffectFor(bug, 'Réduction énergie %'),
            ) +
        ((bug.equippedModules.isNotEmpty ||
                bug.equippedModuleInstanceIds.isNotEmpty)
            ? perDay(
                territory.moduleEnergyAmount, territory.moduleEnergyEveryHours)
            : 0);
    return <String, double>{
      'Organique': organic,
      'Minéral': mineral,
      'Énergie': energy,
    };
  }

  int get pTibugActiveSlots => pTibugConfig.slotsForLevel(plaineNurseryLevel);

  List<PTibugModuleCraftOrder> get activePTibugModuleCraftOrders =>
      pTibugModuleCraftOrders.where((item) => item.isActive).toList();

  PTibugModuleCraftOrder? get activePTibugModuleCraftOrder =>
      activePTibugModuleCraftOrders.firstOrNull;

  /// Personal identity is always preferred in player-facing cards.
  String pTibugBiologicalNameFor(PTibug bug) => bug.displayName;

  String pTibugSpeciesNameFor(PTibug bug) => _pTibugBiologicalName(bug);

  /// Technical identity for territory cards, separate from the Collection
  /// nickname and from the purely cosmetic aspect selected during infusion.
  String pTibugTerritoryIdentityFor(PTibug bug) {
    final species = pTibugConfig.species[bug.species]!.displayName;
    final trait = bug.biologicalTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!);
    final traitLabel = trait == null || bug.biologicalTraitLevel <= 0
        ? null
        : '${trait.displayName} ${bug.biologicalTraitLevel}';
    return <String>[species, if (traitLabel != null) traitLabel].join(' · ');
  }

  /// Identité courte, partagée par la Collection, les refuges et la Nurserie.
  /// `styleVariant` est une donnée historique : le Trait biologique est la
  /// caractéristique utile à montrer après l'espèce.
  String pTibugIdentityLabelFor(PTibug bug) => pTibugTerritoryIdentityFor(bug);

  /// Les codes RGB restent des données de configuration du Dashboard. Les
  /// cartes joueur n'affichent que des noms de couleurs lisibles.
  String pTibugColorNameFor(String? hex) {
    if (hex == null || hex.isEmpty) return '—';
    final raw = hex.replaceFirst('#', '').toUpperCase();
    const exact = <String, String>{
      'F2C94C': 'Jaune',
      '4A90D9': 'Bleu',
      'F2994A': 'Orange',
      '1E1E1E': 'Noir',
      '5E9B5A': 'Vert',
      'D85C55': 'Rouge',
      '8B5FBF': 'Violet',
    };
    final direct = exact[raw];
    if (direct != null) return direct;
    for (final entry in exact.entries) {
      if (_pastelHex('#${entry.key}').replaceFirst('#', '') == raw) {
        return '${entry.value.toLowerCase()} pastel';
      }
    }
    if (raw.length != 6) return 'Couleur inconnue';
    final red = int.tryParse(raw.substring(0, 2), radix: 16) ?? 0;
    final green = int.tryParse(raw.substring(2, 4), radix: 16) ?? 0;
    final blue = int.tryParse(raw.substring(4, 6), radix: 16) ?? 0;
    if (red < 50 && green < 50 && blue < 50) return 'Noir';
    if (red > green * 1.25 && red > blue * 1.25) return 'Rouge';
    if (green > red * 1.15 && green > blue * 1.15) return 'Vert';
    if (blue > red * 1.15 && blue > green * 1.15) return 'Bleu';
    if (red > 150 && green > 120 && blue < 110) return 'Jaune';
    if (red > 130 && blue > 100) return 'Violet';
    return 'Couleur';
  }

  String pTibugAppearanceLabelFor(PTibug bug) {
    final primary = pTibugColorNameFor(bug.primaryColorHex);
    final motif = bug.motifId == null
        ? 'aucun'
        : '${bug.motifId} · ${pTibugColorNameFor(bug.motifColorHex)}';
    return 'Couleur $primary · Motif $motif · Animation ${bug.animationName ?? '—'}';
  }

  void _ensurePTibugAppearance(PTibug bug, {bool reroll = false}) {
    final colors = pTibugConfig.appearance.primaryColorsBySpecies[bug.species];
    if (colors == null || colors.isEmpty) return;
    final animations =
        pTibugConfig.appearance.animationNamesBySpecies[bug.species];
    if (!reroll && bug.primaryColorHex != null) {
      bug.animationName ??= animations == null || animations.isEmpty
          ? null
          : animations[_random.nextInt(animations.length)];
      return;
    }
    final primary = colors[_random.nextInt(colors.length)];
    final hasMotif =
        _random.nextInt(100) < pTibugConfig.appearance.motifChancePercent;
    bug.primaryColorHex = primary;
    bug.animationName = animations == null || animations.isEmpty
        ? null
        : animations[_random.nextInt(animations.length)];
    bug.motifId =
        hasMotif ? pTibugConfig.appearance.motifBySpecies[bug.species] : null;
    if (!hasMotif) {
      bug.motifColorHex = null;
      return;
    }
    final candidates = colors
        .where((color) => !(primary.toUpperCase() == '#1E1E1E' &&
            color.toUpperCase() == '#1E1E1E'))
        .toList(growable: false);
    final motifBase = candidates[_random.nextInt(candidates.length)];
    // Black remains black; the other palette colors are stored as pastel
    // variants so the renderer can later attach the species-specific motif.
    bug.motifColorHex = motifBase.toUpperCase() == '#1E1E1E'
        ? motifBase
        : _pastelHex(motifBase);
  }

  String _pastelHex(String color) {
    final raw = color.replaceFirst('#', '');
    if (raw.length != 6) return color;
    int soften(int value) => (value + (255 - value) * .45).round();
    final red = soften(int.parse(raw.substring(0, 2), radix: 16));
    final green = soften(int.parse(raw.substring(2, 4), radix: 16));
    final blue = soften(int.parse(raw.substring(4, 6), radix: 16));
    return '#${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  PTibugValuationBreakdown pTibugValuationFor(PTibug bug) {
    final instanceModules = pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id)
        .map((item) => item.type)
        .toList();
    final modules = instanceModules.isEmpty
        ? List<PTibugModuleType>.from(bug.equippedModules)
        : instanceModules;
    final traits = <int>[
      if (bug.biologicalTraitId != null && bug.biologicalTraitLevel > 0)
        bug.biologicalTraitLevel,
      if (bug.secondTraitId != null && bug.secondTraitLevel > 0)
        bug.secondTraitLevel,
    ];
    return PTibugValuationService(pTibugConfig.valuation).evaluate(
      PTibugValuationInput(
        species: bug.species,
        level: bug.level,
        traitRanks: traits,
        modules: modules,
      ),
    );
  }

  /// Number of full operating days the local reserves can sustain. The lowest
  /// required reserve is the limiting factor: a territory cannot keep running
  /// when just one of its daily inputs is exhausted.
  double pTibugTerritoryAutonomyDays(PTibugTerritoryBuilding building) {
    final consumption = pTibugTerritoryDailyConsumption(building);
    final days = <double>[
      if (consumption.organicPerDay > 0)
        building.resourceAmount('Organique') / consumption.organicPerDay,
      if (consumption.mineralPerDay > 0)
        building.resourceAmount('Minéral') / consumption.mineralPerDay,
      if (consumption.energyPerDay > 0)
        building.localEnergy / consumption.energyPerDay,
    ];
    return days.isEmpty ? double.infinity : days.reduce(math.min);
  }

  int pTibugEstimatedValueFor(PTibug bug) => pTibugValuationFor(bug).total;

  Zone0ActionResult renamePTibug(PTibug bug, String rawName) {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final config = pTibugConfig.valuation;
    if (!pTibugs.contains(bug) ||
        bug.lifecycleStatus != PTibugLifecycleStatus.active) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIBUG indisponible.');
    }
    if (name.length < config.minimumNameLength ||
        name.length > config.maximumNameLength ||
        !RegExp(r"^[\p{L}\p{N} '\-]+$", unicode: true).hasMatch(name)) {
      return Zone0ActionResult(
        success: false,
        message:
            'Le nom doit contenir entre ${config.minimumNameLength} et ${config.maximumNameLength} caractères.',
      );
    }
    if (bug.displayName != name) {
      bug.nameHistory.add(bug.displayName);
      bug
        ..displayName = name
        ..renamedAt = DateTime.now()
        ..renameCount += 1
        ..updatedAt = DateTime.now();
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return Zone0ActionResult(success: true, message: '$name est enregistré.');
  }

  String? pTibugCertificationBlocker(PTibug bug) {
    if (!pTibugs.contains(bug) ||
        bug.lifecycleStatus != PTibugLifecycleStatus.active) {
      return 'Ce P’TIBUG n’est plus disponible.';
    }
    if (bug.reservedForSaleId != null) return 'Ce P’TIBUG est déjà réservé.';
    if (isPTibugInCultivation(bug))
      return 'Le P’TIBUG est actuellement en cuve.';
    if (bug.assignedBuildingId != null)
      return 'Retire le P’TIBUG de son bâtiment avant certification.';
    if (bug.storedAmount > 0 || bug.storedDataCells.isNotEmpty) {
      return 'Récolte sa production et ses Cellules avant certification.';
    }
    return null;
  }

  Zone0ActionResult sellCertifiedPTibug(
    PTibug bug, {
    required String source,
    String? requestId,
    String? contractId,
    bool sourcierContract = false,
    double bonusMultiplier = 1,
  }) {
    final blocker = pTibugCertificationBlocker(bug);
    if (blocker != null)
      return Zone0ActionResult(success: false, message: blocker);
    final modules = pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id)
        .toList(growable: false);
    final includedModules = modules.isEmpty
        ? List<PTibugModuleType>.from(bug.equippedModules)
        : modules.map((item) => item.type).toList(growable: false);
    final valuation = pTibugValuationFor(bug);
    final payment = PTibugValuationService(pTibugConfig.valuation).paymentFor(
      valuation,
      sourcierContract: sourcierContract,
      bonusMultiplier: bonusMultiplier,
    );
    final now = DateTime.now();
    final capsule = PTibugCapsule(
      id: 'certified-ptibug-${now.microsecondsSinceEpoch}',
      sourcePtibugId: bug.id,
      species: bug.species,
      styleVariant: bug.styleVariant,
      displayName: bug.displayName,
      primaryColorHex: bug.primaryColorHex,
      motifId: bug.motifId,
      motifColorHex: bug.motifColorHex,
      traitColorHex: bug.traitColorHex,
      animationName: bug.animationName,
      biologicalTraitId: bug.biologicalTraitId,
      biologicalTraitLevel: bug.biologicalTraitLevel,
      secondTraitId: bug.secondTraitId,
      secondTraitLevel: bug.secondTraitLevel,
      isEvolved: bug.isRenewed,
      moduleSnapshots: includedModules.map((item) => item.name).toList(),
      level: bug.level,
      xp: bug.xp,
      baseValueSnapshot: valuation.baseValue,
      levelValueSnapshot: valuation.levelValue,
      traitValueSnapshot: valuation.traitValue,
      moduleValueSnapshot: valuation.moduleValue,
      estimatedValueSnapshot: valuation.total,
      valuationConfigVersion: valuation.configVersion,
      certificationId: 'cert-${bug.id}-${now.microsecondsSinceEpoch}',
      linkedRequestId: requestId,
      linkedContractId: contractId,
      finalSalePrice: payment,
      soldAt: now,
      status: CertifiedPTibugCapsuleStatus.sold,
      createdAt: now,
    );
    // Atomic in-memory mutation: validation above is complete before any owned
    // object is removed. The transaction is then persisted as one save.
    pTibugModuleInstances
        .removeWhere((item) => item.equippedPTibugId == bug.id);
    bug
      ..equippedModules.clear()
      ..equippedModuleInstanceIds.clear()
      ..lifecycleStatus = PTibugLifecycleStatus.sold
      ..updatedAt = now
      ..reservedForSaleId = null;
    pTibugs.remove(bug);
    soldPTibugArchive.add(bug);
    pTibugCapsules.add(capsule);
    bioBatteries += payment;
    _resolveEnergyCoreMilestones();
    reports.add(PtipoteMissionReport.system(
      message: '${bug.displayName} est vendu sous Capsule P’TIBUG certifiée.',
      sourceBuildingId: 'market',
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Capsule P’TIBUG certifiée',
      concerned: bug.displayName,
      summary:
          '$source · valeur ${valuation.total} · paiement $payment Bio-batteries.',
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Capsule certifiée vendue : +$payment Bio-batteries.',
    );
  }

  List<MarketSourcierContract> eligiblePTibugContractsFor(PTibug bug) {
    final resource = switch (bug.species) {
      PTibugSpecies.scarabe => 'P’TIBUG Scarabé',
      PTibugSpecies.hyme => 'P’TIBUG Hyme',
      PTibugSpecies.arac => 'P’TIBUG Arac',
    };
    return marketContracts
        .where((contract) =>
            contract.status == MarketContractStatus.accepted &&
            contract.requestedItems.length == 1 &&
            contract.requestedItems[resource] == 1)
        .toList(growable: false);
  }

  Zone0ActionResult deliverCertifiedPTibugContract(
    PTibug bug,
    MarketSourcierContract contract,
  ) {
    if (!eligiblePTibugContractsFor(bug).contains(contract)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce contrat n’est pas compatible avec ce P’TIBUG.',
      );
    }
    final result = sellCertifiedPTibug(
      bug,
      source: 'Contrat du Sourcier',
      contractId: contract.contractId,
      // La valeur certifiée (niveau, Traits, Modules) est la base du
      // paiement. Le Sourcier n'ajoute ici que son bonus de confiance.
      sourcierContract: false,
      bonusMultiplier: sourcierConfidencePaymentMultiplier,
    );
    if (!result.success) return result;
    contract
      ..status = MarketContractStatus.completed
      ..deliveredAt = DateTime.now();
    sourcierConfidence =
        math.min(100, sourcierConfidence + contract.confidenceReward);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return result;
  }

  int pTibugCapacityFor(PTibug bug) => _pTibugCapacity(bug);

  Duration pTibugCycleDurationFor(PTibug bug) => _pTibugCycleDuration(bug);

  /// Prévision stable pour les cartes et fiches. Les tirages propres au cycle
  /// (notamment Arac) ne doivent jamais modifier l'interface à chaque build.
  Map<String, int> pTibugProductionFor(PTibug bug) =>
      Map<String, int>.unmodifiable(
        _pTibugProduction(bug, randomizeAracResource: false),
      );

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

  int _pTibugCapacity(PTibug bug) {
    final baseCapacity = pTibugConfig.carryingCapacity +
        _pTibugModuleEffect(
          bug,
          PTibugModuleType.reservoir,
          pTibugConfig.reservoirCapacityBonusByLevel,
        ).round();
    return math.max(1, baseCapacity * pTibugConfig.storageMultiplier);
  }

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

  Map<String, int> _pTibugProduction(
    PTibug bug, {
    bool randomizeAracResource = true,
  }) {
    final output = <String, int>{};
    void add(String resource, int amount) =>
        output[resource] = (output[resource] ?? 0) + amount;
    switch (bug.species) {
      case PTibugSpecies.scarabe:
        add('Minéral', 3);
      case PTibugSpecies.hyme:
        add('Organique', 3);
      case PTibugSpecies.arac:
        add(
          _pTibugAracResourceForBiome(
            bug.biome,
            stableSeed: randomizeAracResource ? null : bug.id,
          ),
          3,
        );
    }
    final biome = pTibugConfig.biomes[bug.biome];
    biome?.localProductionBonus[bug.species]?.forEach(add);
    // The level bonus is intentionally applied here: after species and biome,
    // before Traits and Modules. It has one unique place in the pipeline.
    final levelMultiplier =
        pTibugConfig.progression.yieldMultiplierForLevel(bug.level);
    for (final entry in output.entries.toList()) {
      output[entry.key] = (entry.value * levelMultiplier).round();
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
    final secondTrait = bug.secondTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.secondTraitId!);
    if (secondTrait != null) {
      secondTrait.productionForLevel(bug.secondTraitLevel).forEach(add);
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
            _pTibugAracResourceForBiome(
              bug.biome,
              stableSeed: randomizeAracResource ? null : bug.id,
            ),
            claws,
          );
      }
    }
    final sensorPenalty = _pTibugEffectFor(bug, 'Malus matériel %');
    if (sensorPenalty > 0) {
      final sensorMultiplier = pTibugConfig.weather.multiplierForPenalty(
        sensorPenalty,
      );
      for (final entry in output.entries.toList()) {
        // A scientific P'TIBUG never becomes a false zero-producer merely
        // because a one-unit material output is halved.
        output[entry.key] =
            math.max(1, (entry.value * sensorMultiplier).round());
      }
    }
    // Déchets are local to the biome: a full waste reserve boosts their
    // production, while an assainied biome no longer yields exploitable waste.
    if (output.containsKey('Déchets')) {
      output['Déchets'] =
          (output['Déchets']! * wasteMultiplierFor(bug.refugeBiome)).round();
    }
    final weather = pTibugWeatherFor(bug);
    final protected =
        weather != null && _hasPTibugWeatherProtection(bug, weather);
    final multiplier = buildingProductionMultiplier(
          bug.assignedBuildingId ?? plaineNurseryTerritoryId,
        ) *
        biomassPTibugMultiplierFor(bug.refugeBiome) *
        (weather == null || protected
            ? 1
            : pTibugConfig.weather.multiplierForPenalty(
                pTibugWeatherMalusPercentFor(bug),
              ));
    return <String, int>{
      for (final entry in output.entries)
        entry.key: math.max(0, (entry.value * multiplier).round()),
    };
  }

  TowerWeatherType? pTibugWeatherFor(PTibug bug) {
    final event = activeGlobalWeatherEvent;
    if (event == null ||
        event.status != GlobalWeatherEventStatus.active ||
        event.type == TowerWeatherType.calm ||
        !event.isBiomeAffected(bug.refugeBiome)) return null;
    return event.type;
  }

  int pTibugWeatherMalusPercentFor(PTibug bug) {
    final event = activeGlobalWeatherEvent;
    if (event == null || !event.isBiomeAffected(bug.refugeBiome)) return 0;
    final base = towerOperationsConfig
        .globalWeather.intensities[event.intensity]!.ptibugMalusPercent;
    return (base * event.impactFor(bug.refugeBiome).localImpactMultiplier)
        .round()
        .clamp(
            0, towerOperationsConfig.globalWeather.maximumPTibugMalusPercent);
  }

  bool _hasPTibugWeatherProtection(PTibug bug, TowerWeatherType weather) =>
      switch (weather) {
        TowerWeatherType.calm => true,
        TowerWeatherType.toxicCloud =>
          _pTibugEffectFor(bug, 'Protection Nuage toxique') > 0,
        TowerWeatherType.heatWave =>
          _pTibugModuleLevel(bug, PTibugModuleType.reflecteur) > 0,
        TowerWeatherType.heavyRain =>
          _pTibugModuleLevel(bug, PTibugModuleType.etancheite) > 0,
      };

  void _tryDetectSensorDataCell(PTibug bug, DateTime cycleAt) {
    final level = bug.biologicalTraitId == 'capteurIntelligent'
        ? bug.biologicalTraitLevel
        : bug.secondTraitId == 'capteurIntelligent'
            ? bug.secondTraitLevel
            : 0;
    if (level <= 0 ||
        bug.storedDataCells.length >=
            pTibugConfig.territory.dataCellStorageCapacity ||
        _random.nextInt(100) >=
            (pTibugConfig.weather.sensorChanceByLevel[level] ?? 0)) {
      return;
    }
    final biome = pTibugConfig.biomes[bug.biome];
    if (biome == null) return;
    final dominant = _pickWeightedDataFamily(biome.dataWeights);
    final entries = List<PTibugDataCellEntry>.generate(
        5,
        (index) => PTibugDataCellEntry(
              family: index < 2
                  ? dominant
                  : _pickWeightedDataFamily(biome.dataWeights),
              quality: _pickWeightedDataQuality(),
              slotIndex: index,
            ));
    bug.storedDataCells.add(PTibugDataCell(
      id: 'sensor-${bug.id}-${cycleAt.microsecondsSinceEpoch}',
      displayName:
          'Cellule ${_ptibugDataFamilyLabel(dominant)} · ${biome.displayName}',
      sourceBiomeId: bug.biome.name,
      dominantFamily: dominant,
      isNeutralCell: false,
      entries: entries,
      createdAt: cycleAt,
    ));
  }

  /// Effects that do not create an inventory resource are consumed here by
  /// their related system. A P'TIBUG must be assigned to a refuge slot for
  /// its biological trait to help that biome.
  int _pTibugEffectFor(PTibug bug, String effect) {
    var result = 0;
    final legacyTrait = bug.traitDataId == null
        ? null
        : pTibugTraitData
            .where((item) => item.id == bug.traitDataId)
            .firstOrNull;
    if (legacyTrait != null) {
      result += pTibugConfig
              .traitDefinitionFor(legacyTrait.definitionId)
              ?.effectForGrade(effect, legacyTrait.grade) ??
          0;
    }
    final permanentTrait = bug.biologicalTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!);
    if (permanentTrait != null) {
      result += permanentTrait.effectForLevel(
        effect,
        bug.biologicalTraitLevel,
      );
    }
    final secondTrait = bug.secondTraitId == null
        ? null
        : pTibugConfig.traitDefinitionFor(bug.secondTraitId!);
    if (secondTrait != null) {
      result += secondTrait.effectForLevel(effect, bug.secondTraitLevel);
    }
    return result;
  }

  int _activePTibugEffect(String effect, {PTibugBiome? biome}) => pTibugs
      .where(
        (bug) =>
            bug.assignedSlotIndex != null &&
            (biome == null || bug.biome == biome),
      )
      .fold<int>(0, (total, bug) => total + _pTibugEffectFor(bug, effect));

  String _pTibugAracResourceForBiome(
    PTibugBiome biome, {
    String? stableSeed,
  }) {
    final weights = pTibugConfig.biomes[biome]?.aracProductionWeights ??
        const <String, int>{};
    final entries = weights.entries.where((entry) => entry.value > 0).toList();
    if (entries.isEmpty) return 'Organique';
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final stableValue = stableSeed == null
        ? null
        : stableSeed.codeUnits
            .fold<int>(0, (hash, unit) => ((hash * 31) + unit) & 0x7fffffff);
    var cursor =
        stableValue == null ? _random.nextInt(total) : stableValue % total;
    for (final entry in entries) {
      cursor -= entry.value;
      if (cursor < 0) return entry.key;
    }
    return entries.last.key;
  }

  void _applyPTibugStability(PTibug bug, int producedCycles) {
    final gain = _pTibugEffectFor(bug, 'Sécurité locale') * producedCycles;
    final forageBiome = _forageBiomeForPTibugBiome(bug.biome);
    if (gain <= 0 || forageBiome == null) return;
    final state = biomeSecurity[forageBiome];
    if (state == null) return;
    state.localSecurity = (state.localSecurity + gain)
        .clamp(0, towerOperationsConfig.localSecurityMaximum)
        .round();
  }

  ForageBiome? _forageBiomeForPTibugBiome(PTibugBiome biome) => switch (biome) {
        PTibugBiome.hautsRefuges => ForageBiome.colline,
        PTibugBiome.savaneTropicale => ForageBiome.plaineRiche,
        PTibugBiome.semiDesertGarrigueTropicale => ForageBiome.bassinMineral,
        PTibugBiome.foretHumideRelictuelle => ForageBiome.sousBois,
        _ => null,
      };

  Zone0ActionResult assignPTibugSlot(PTibug bug, int slot) {
    return assignPTibugToTerritory(bug, plaineNurseryTerritoryId);
  }

  Zone0ActionResult removePTibugSlot(PTibug bug) {
    return setPTibugInactive(bug);
  }

  Zone0ActionResult assignPTibugToTerritory(PTibug bug, String territoryId) {
    if (isPTibugInCultivation(bug)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ce P’TIBUG est indisponible : il est en cuve.');
    }
    final building = territoryBuildingForId(territoryId);
    if (building == null || !building.isBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce bâtiment P’TIBUG n’est pas encore construit.',
      );
    }
    final residents = pTibugsForTerritory(territoryId)
        .where((item) => item.id != bug.id)
        .length;
    if (residents >= pTibugTerritoryCapacity(building)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucun emplacement libre dans ce bâtiment.',
      );
    }
    bug
      ..assignedBuildingId = territoryId
      ..refugeBiome = building.biome
      ..assignedSlotIndex = residents
      ..inactiveReason = null
      ..nextProductionAt ??= DateTime.now().add(_pTibugCycleDuration(bug));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${bug.displayName} affecté à ${building.kind == PTibugTerritoryKind.nursery ? 'la Nurserie' : 'ce Refuge'}.',
    );
  }

  Zone0ActionResult setPTibugInactive(PTibug bug) {
    if (isPTibugInCultivation(bug)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ce P’TIBUG est indisponible : il est en cuve.');
    }
    bug.assignedSlotIndex = null;
    bug
      ..assignedBuildingId = null
      ..nextProductionAt = null
      ..inactiveReason = 'En attente d’affectation';
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'P’TIBUG placé dans les inactifs.',
    );
  }

  Zone0ActionResult transferResourcesToPTibugTerritory({
    required String territoryId,
    required Map<String, int> resources,
  }) {
    final building = territoryBuildingForId(territoryId);
    if (building == null ||
        !building.isBuilt ||
        resources.values.any((v) => v < 0)) {
      return const Zone0ActionResult(
          success: false, message: 'Transfert impossible.');
    }
    if (!hasResources(resources) || !removeResources(resources)) {
      return const Zone0ActionResult(
          success: false, message: 'Inventaire insuffisant.');
    }
    resources.forEach((resource, amount) {
      building.localResources[resource] =
          building.resourceAmount(resource) + amount;
    });
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Stocks locaux alimentés.');
  }

  Zone0ActionResult openBioBatteryForPTibugTerritory(String territoryId) {
    final building = territoryBuildingForId(territoryId);
    if (building == null || !building.isBuilt || bioBatteries <= 0) {
      return const Zone0ActionResult(
          success: false, message: 'Bio-batterie indisponible.');
    }
    final gain = energyFromBioBatteryForBuildingLevel(building.level);
    bioBatteries -= 1;
    building.localEnergy += gain;
    _resumePausedCultivationTanks();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '+$gain énergie locale.',
    );
  }

  /// Future Refuge buildings use this transition. The main Nurserie is the
  /// Plaine Refuge by default; moving a P'TIBUG immediately switches only its
  /// local Biomass source, never its species, Traits or stored production.
  Zone0ActionResult movePTibugToRefugeBiome(
    PTibug bug,
    ForageBiome refugeBiome,
  ) {
    if (!isBiomeUnlocked(refugeBiome)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ce biome ne possède pas encore de Refuge disponible.',
      );
    }
    bug.refugeBiome = refugeBiome;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${bug.displayName} utilise désormais la Biomasse de ${lisiereForageConfig.biomes[refugeBiome]!.label}.',
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
      if (bug.assignedSlotIndex != null) {
        bug.nextProductionAt = DateTime.now().add(_pTibugCycleDuration(bug));
      }
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
    if (bug.storedResources.isEmpty && bug.storedDataCells.isEmpty) {
      return const Zone0ActionResult(
        success: false,
        message: 'Aucune production prête.',
      );
    }
    final output = Map<String, int>.from(bug.storedResources);
    final materialResult = output.isEmpty ? null : addResources(output);
    bug.storedResources
      ..clear()
      ..addAll(materialResult?.pending ?? const <String, int>{});
    final collectedResourceDetails = <String>[
      for (final entry in output.entries)
        if (entry.value - (materialResult?.pending[entry.key] ?? 0) > 0)
          '${entry.value - (materialResult?.pending[entry.key] ?? 0)} ${entry.key}',
    ];
    final collectedCellDetails = <String>[
      for (final family in bug.storedDataCells
          .map((cell) => cell.dominantFamily)
          .whereType<PTibugDataFamily>()
          .toSet())
        '${bug.storedDataCells.where((cell) => cell.dominantFamily == family).length} Cellule ${_ptibugDataFamilyLabel(family)}',
    ];
    if (bug.storedDataCells.isNotEmpty) {
      pTibugDataCells.addAll(bug.storedDataCells);
      bug.storedDataCells.clear();
    }
    bug.stockFullNotified = false;
    if (bug.assignedBuildingId != null && bug.inactiveReason == null) {
      bug.nextProductionAt = DateTime.now().add(_pTibugCycleDuration(bug));
    }
    emitKernelProgressEvent(KernelProgressEventType.ptibugProductionCollected);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${bug.displayName} : '
          '${collectedResourceDetails.isEmpty ? 'aucune ressource' : collectedResourceDetails.join(', ')}'
          '${collectedCellDetails.isEmpty ? '' : ' · ${collectedCellDetails.join(', ')}'}'
          '${materialResult?.hasPending == true ? ' · reliquat conservé : ${materialResult!.pending.entries.map((entry) => '${entry.value} ${entry.key}').join(', ')}' : ''}.',
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
    if (isPTibugInCultivation(bug)) {
      return const Zone0ActionResult(
          success: false, message: 'Module indisponible : P’TIBUG en cuve.');
    }
    if (!unlockedPTibugModules.contains(module) ||
        bug.hasModule(module) ||
        bug.equippedModules.length >= maxModulesPerPTibug) {
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
                  Zone0InventoryStack.fromFirebase,
                )
                .where(
                  (stack) => stack.resource.isNotEmpty && stack.amount > 0,
                ),
          );
        // Eau is now contextual to Cuisine. Remove only this deprecated
        // inventory representation; no other stack is touched.
        final removedLegacyWater = inventory
            .where((stack) => stack.resource == 'Eau')
            .fold<int>(0, (total, stack) => total + stack.amount);
        if (removedLegacyWater > 0) {
          inventory.removeWhere((stack) => stack.resource == 'Eau');
          unawaited(saveInventoryToFirebase());
        }
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

      // Les niveaux et XP P'TIPOTE font partie de la progression Zone 0.
      // Les anciennes sauvegardes ne possèdent pas ces maps : dans ce cas les
      // valeurs du scan restent la référence sans réinitialiser la figurine.
      final xpData = data['xpOverrides'];
      if (xpData is Map) {
        xpOverrides
          ..clear()
          ..addEntries(
            xpData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }
      final levelData = data['levelOverrides'];
      if (levelData is Map) {
        levelOverrides
          ..clear()
          ..addEntries(
            levelData.entries.map(
              (entry) =>
                  MapEntry('${entry.key}', _readInt(entry.value, fallback: 1)),
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
      _legacyArrivalSnapshotPresent = data.containsKey('hatchedPtipoteIds');
      if (hatchedData is List) {
        hatchedPtipoteIds
          ..clear()
          ..addAll(hatchedData.map((id) => '$id'));
      }
      final v2ProfilesData = data['ptipoteV2Profiles'];
      if (v2ProfilesData is Map) {
        ptipoteV2Profiles
          ..clear()
          ..addEntries(
            v2ProfilesData.entries.where((entry) => entry.value is Map).map(
                  (entry) => MapEntry(
                    '${entry.key}',
                    PtipoteV2Profile.fromFirebase(
                      '${entry.key}',
                      entry.value as Map,
                    ),
                  ),
                ),
          );
      }
      final coBreedingData = data['coBreeding'];
      if (coBreedingData is Map) {
        coBreedingUnlocked = coBreedingData['unlocked'] == true;
        coBreedingIntroMissionDismissed =
            coBreedingData['introMissionDismissed'] == true;
        coBreedingDevMode = coBreedingData['devMode'] == true;
        lastCoBreedingSelectionAt =
            _readDate(coBreedingData['lastSelectionAt']);
        final offer = coBreedingData['offer'];
        coBreedingOffer =
            offer is Map ? CoBreedingOffer.fromFirebase(offer) : null;
        final envelopeOffer = coBreedingData['envelopeOffer'];
        final envelopeOffers = coBreedingData['envelopeOffers'];
        coBreedingEnvelopeOffers.clear();
        if (envelopeOffers is Map) {
          for (final entry in envelopeOffers.entries) {
            if (entry.value is Map) {
              final parsed = CoBreedingEnvelopeOffer.fromFirebase(
                entry.value as Map,
              );
              if (parsed.ptipoteId.isNotEmpty) {
                coBreedingEnvelopeOffers[parsed.ptipoteId] = parsed;
              }
            }
          }
        } else if (envelopeOffer is Map) {
          // Prompt 4 alpha migration: retain the one previously stored offer.
          final parsed = CoBreedingEnvelopeOffer.fromFirebase(envelopeOffer);
          if (parsed.ptipoteId.isNotEmpty) {
            coBreedingEnvelopeOffers[parsed.ptipoteId] = parsed;
          }
        }
        final sessions = coBreedingData['sessions'];
        if (sessions is List) {
          coBreedingSessions
            ..clear()
            ..addAll(
              sessions.whereType<Map>().map(CoBreedingSession.fromFirebase),
            );
        }
        final rewards = coBreedingData['xpRewards'];
        if (rewards is List) {
          coBreedingXpRewards
            ..clear()
            ..addAll(
              rewards.whereType<Map>().map(CoBreedingXpReward.fromFirebase),
            );
        }
        final archive = coBreedingData['archive'];
        if (archive is List) {
          coBreedingArchive
            ..clear()
            ..addAll(
              archive.whereType<Map>().map(CoBreedingArchive.fromFirebase),
            );
        }
        completedCoBreedingCount = _readInt(
          coBreedingData['completedCount'],
          fallback: coBreedingArchive.length,
        );
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
      final towerResearchData = data['towerBiomeResearch'];
      if (towerResearchData is List) {
        towerBiomeResearch
          ..clear()
          ..addAll(towerResearchData.whereType<Map>().map(
                TowerBiomeResearch.fromFirebase,
              ));
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
                // Keep the stack id and the nursery source ids.  Rebuilding
                // only `{resource, amount}` made a saved market pile lose its
                // identity on reload and was the root of ghost / zero piles.
                .map(Zone0InventoryStack.fromFirebase)
                .where((item) => item.resource.isNotEmpty && item.amount > 0),
          );
        marketRequests
          ..clear()
          ..addAll(
            (marketData['requests'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(MarketCustomerRequest.fromFirebase),
          );
        marketRequestLog
          ..clear()
          ..addAll((marketData['requestLog'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketRequestLogEntry.fromFirebase));
        marketNextSaleAt = _readDate(marketData['nextSaleAt']);
        marketNextRequestAt = _readDate(marketData['nextRequestAt']);
        marketLastWorkTickAt = _readDate(marketData['lastWorkTickAt']);
        marketLastXpTickAt = _readDate(marketData['lastXpTickAt']);
        marketAssignedAt = _readDate(marketData['assignedAt']);
        marketXpEarnedThisAssignment =
            _readInt(marketData['xpEarnedThisAssignment']);
        marketBioPilesEarnedThisAssignment =
            _readInt(marketData['bioPilesEarnedThisAssignment']);
        marketArticlesSoldThisAssignment =
            _readInt(marketData['articlesSoldThisAssignment']);
        marketDistributorsRepairedThisAssignment =
            _readInt(marketData['distributorsRepairedThisAssignment']);
        marketAssignedPtipoteId = marketData['assignedPtipoteId'] as String?;
        marketAssignedPtipoteName =
            marketData['assignedPtipoteName'] as String?;
        marketRestockEnabledItems
          ..clear()
          ..addAll(
              (marketData['restockEnabledItems'] as List? ?? const <dynamic>[])
                  .map((value) => '$value'));
        marketRestockMinimums
          ..clear()
          ..addAll((marketData['restockMinimums'] as Map? ??
                  const <dynamic, dynamic>{})
              .map((key, value) => MapEntry('$key', _readInt(value))));
        marketValueRemainder = _readInt(marketData['valueRemainder']);
        marketBioBatteriesEarned = _readInt(marketData['bioBatteriesEarned']);
        sourcierConfidence =
            _readInt(marketData['sourcierConfidence']).clamp(0, 100);
        firstFreeShopClaimed = marketData['firstFreeShopClaimed'] == true;
        primaryMarketShopSpecialization =
            '${marketData['primaryShopSpecialization'] ?? 'general'}';
        primaryMarketShopChosen = marketData['primaryShopChosen'] == true;
        primaryMarketShopLevel = _readInt(
          marketData['primaryShopLevel'],
          fallback: 1,
        ).clamp(1, 2);
        final shopConstruction = marketData['shopConstruction'];
        marketShopConstructionOrder = shopConstruction is Map
            ? MarketShopConstructionOrder.fromFirebase(shopConstruction)
            : null;
        final communityShopConstruction =
            marketData['residentCommunityShopConstruction'];
        residentCommunityShopConstructionOrder =
            communityShopConstruction is Map
                ? MarketShopConstructionOrder.fromFirebase(
                    communityShopConstruction)
                : null;
        lastResidentCommunityShopConstructionAt =
            _readDate(marketData['lastResidentCommunityShopConstructionAt']);
        activeMarketLicenses
          ..clear()
          ..addAll((marketData['activeLicenses'] as List? ?? const <dynamic>[])
              .map((value) => '$value'));
        marketShops
          ..clear()
          ..addAll((marketData['shops'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketShop.fromFirebase)
              .where((shop) => shop.id.isNotEmpty));
        marketShopSlots
          ..clear()
          ..addAll((marketData['shopSlots'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketShopSlot.fromFirebase)
              .where((slot) => slot.slotId.isNotEmpty));
        marketRestockRules
          ..clear()
          ..addAll((marketData['restockRules'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketRestockRule.fromFirebase)
              .where((rule) => rule.ruleId.isNotEmpty));
        marketShopSlotsMigrationCompleted =
            marketData['shopSlotsMigrationCompleted'] == true;
        MarketDistributorState? migratedPrimaryDistributor;
        final migratedPrimary =
            marketShops.where((shop) => shop.isPrimary).firstOrNull;
        if (migratedPrimary != null) {
          primaryMarketShopSpecialization = migratedPrimary.specialization;
          primaryMarketShopChosen = true;
        } else if (!primaryMarketShopChosen && marketShops.length == 1) {
          final legacy = marketShops.single;
          primaryMarketShopSpecialization = legacy.specialization;
          primaryMarketShopChosen = true;
          primaryMarketShopLevel = legacy.level.clamp(1, 2);
          // Migration explicitement validée : la première boutique héritée
          // devient réellement la boutique principale. Ses piles rejoignent
          // le stock historique et ne restent plus cachées dans un doublon.
          marketStock.addAll(legacy.stock);
          migratedPrimaryDistributor = legacy.distributor;
          marketShops..clear();
        }
        marketContracts
          ..clear()
          ..addAll((marketData['contracts'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketSourcierContract.fromFirebase)
              .where((contract) => contract.contractId.isNotEmpty));
        _migrateLegacyPTibugContractValues();
        final distributorData = marketData['distributor'];
        if (distributorData is Map) {
          final restored = MarketDistributorState.fromFirebase(distributorData);
          marketDistributor
            ..isBuilt = restored.isBuilt
            ..level = restored.level
            ..energy = restored.energy
            ..isBroken = restored.isBroken
            ..lastEnergyTickAt = restored.lastEnergyTickAt
            ..constructionStartedAt = restored.constructionStartedAt
            ..constructionEndsAt = restored.constructionEndsAt
            ..repairEndsAt = restored.repairEndsAt
            ..repairStartedBy = restored.repairStartedBy;
          marketDistributor.constructionDeposits
            ..clear()
            ..addAll(restored.constructionDeposits);
          marketDistributor.stock
            ..clear()
            ..addAll(restored.stock);
        }
        if (migratedPrimaryDistributor != null) {
          final legacy = migratedPrimaryDistributor;
          if (!marketDistributor.isBuilt && legacy.isBuilt) {
            marketDistributor
              ..isBuilt = true
              ..level = legacy.level
              ..energy = legacy.energy
              ..isBroken = legacy.isBroken
              ..lastEnergyTickAt = legacy.lastEnergyTickAt
              ..constructionStartedAt = legacy.constructionStartedAt
              ..constructionEndsAt = legacy.constructionEndsAt
              ..repairEndsAt = legacy.repairEndsAt
              ..repairStartedBy = legacy.repairStartedBy
              ..type = legacy.type;
          }
          // Des piles sont fusionnées sans suppression : chaque produit reste
          // vendable après la transformation de l'ancienne boutique.
          marketDistributor.stock.addAll(legacy.stock);
          legacy.constructionDeposits.forEach((resource, amount) {
            marketDistributor.constructionDeposits[resource] = math.max(
              marketDistributor.constructionDeposits[resource] ?? 0,
              amount,
            );
          });
        }
        _migrateMarketShopSlots(DateTime.now());
        merchantAvailableUntil = _readDate(
          marketData['merchantAvailableUntil'],
        );
        merchantNextArrivalAt = _readDate(marketData['merchantNextArrivalAt']);
        merchantCallRequestedAt = _readDate(
          marketData['merchantCallRequestedAt'],
        );
        merchantVisitsDayKey = '${marketData['merchantVisitsDayKey'] ?? ''}';
        merchantVisitsToday = _readInt(marketData['merchantVisitsToday']);
        merchantOffers
          ..clear()
          ..addAll(
            (marketData['merchantOffers'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(MerchantOffer.fromFirebase)
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
      final territoryZonesData = data['lisiereTerritoryZones'];
      if (territoryZonesData is Map) {
        for (final biome in ForageBiome.values) {
          final item = territoryZonesData[biome.name];
          if (item is Map) {
            lisiereTerritoryZones[biome] =
                LisiereTerritoryZone.fromFirebase(biome, item);
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
        final activeGlobal = weatherData['activeGlobalEvent'];
        activeGlobalWeatherEvent = activeGlobal is Map
            ? GlobalWeatherEvent.fromFirebase(activeGlobal)
            : null;
        final nextGlobal = weatherData['nextGlobalEvent'];
        nextGlobalWeatherEvent = nextGlobal is Map
            ? GlobalWeatherEvent.fromFirebase(nextGlobal)
            : null;
        globalWeatherConsecutiveAdverseEvents =
            _readInt(weatherData['consecutiveAdverseEvents']);
        globalWeatherConsecutiveSevereEvents =
            _readInt(weatherData['consecutiveSevereEvents']);
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
        bioPiles = _readInt(kernelData['bioPiles']);
        energyCorePatternDiscovered =
            kernelData['energyCorePatternDiscovered'] == true;
        energyCoreWarning600Shown =
            kernelData['energyCoreWarning600Shown'] == true;
        energyCoreWarning699Shown =
            kernelData['energyCoreWarning699Shown'] == true;
        storedEnergyCores = _readInt(kernelData['storedEnergyCores']);
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
        kernelPlanDataInvestments.clear();
        final planDataInvestments = kernelData['planDataInvestments'] as Map?;
        if (planDataInvestments != null) {
          for (final entry in planDataInvestments.entries) {
            if (entry.value is! Map) continue;
            final values = <PTibugDataFamily, int>{};
            for (final family in PTibugDataFamily.values) {
              final amount = _readInt((entry.value as Map)[family.name]);
              if (amount > 0) values[family] = amount;
            }
            if (values.isNotEmpty) {
              kernelPlanDataInvestments['${entry.key}'] = values;
            }
          }
        }
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
        recyclerOutputOther = _readInt(recyclerData['outputOther']);
        recyclerBiologicalOrientationInstalled =
            recyclerData['biologicalOrientationInstalled'] == true;
        recyclerBiologicalOrientationActive =
            recyclerData['biologicalOrientationActive'] == true;
        recyclerActiveBatch = recyclerData['activeBatch'] is Map
            ? RecyclerBatchSnapshot.fromFirebase(
                recyclerData['activeBatch'] as Map)
            : null;
        pendingWaste = _readInt(recyclerData['pendingWaste']);
        recyclerCycleStartedAt = _readDate(recyclerData['cycleStartedAt']);
        lastWasteGenerationAt = _readDate(
          recyclerData['lastWasteGenerationAt'],
        );
        lastCampWasteCalculationAt =
            _readDate(recyclerData['lastCampWasteCalculationAt']);
        campWasteRemainder =
            (recyclerData['campWasteRemainder'] as num?)?.toDouble() ?? 0;
        campWasteDailyReports
          ..clear()
          ..addAll((recyclerData['dailyReports'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(CampWasteDailyReport.fromFirebase));
      }
      final ptibugData = data['ptibug'];
      if (ptibugData is Map) {
        pTibugModuleCapacityLevel = _readInt(
          ptibugData['moduleCapacityLevel'],
        ).clamp(0, pTibugConfig.moduleCapacity.maximumUpgrades);
        plaineNurseryLevel = _readInt(ptibugData['nurseryLevel']).clamp(
          0,
          pTibugConfig.territory.nurseryMaximumLevel,
        );
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
        soldPTibugArchive
          ..clear()
          ..addAll((ptibugData['soldArchive'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(PTibug.fromFirebase));
        pTibugTerritoryBuildings
          ..clear()
          ..addEntries(
            (ptibugData['territoryBuildings'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(PTibugTerritoryBuilding.fromFirebase)
                .where((building) => building.id.isNotEmpty)
                .map((building) => MapEntry(building.id, building)),
          );
        final nursery = pTibugTerritoryBuildings.putIfAbsent(
          plaineNurseryTerritoryId,
          () => PTibugTerritoryBuilding.nurseryPlaine(
            level: plaineNurseryLevel,
          ),
        );
        nursery
          ..level = plaineNurseryLevel
          ..isBuilt = plaineNurseryLevel > 0
          ..lastConsumptionAt ??= DateTime.now();
        final nurseryCapacity = pTibugTerritoryCapacity(nursery);
        var assignedNursery = 0;
        for (final bug in pTibugs) {
          _ensurePTibugAppearance(bug);
          if (bug.traitColorHex == null && bug.biologicalTraitId != null) {
            bug.traitColorHex = pTibugConfig
                .traitDefinitionFor(bug.biologicalTraitId!)
                ?.colorHex;
          }
          if (bug.secondTraitId == bug.biologicalTraitId) {
            bug.secondTraitId = null;
            bug.secondTraitLevel = 0;
          }
          // Existing saves had a single slot system. Preserve the old active
          // residents in the Plaine nursery, and place any overflow safely in
          // the inactive reserve rather than duplicating or deleting a bug.
          if (bug.assignedBuildingId == null && bug.assignedSlotIndex != null) {
            bug.assignedBuildingId = plaineNurseryTerritoryId;
          }
          if (bug.assignedBuildingId == plaineNurseryTerritoryId) {
            if (assignedNursery >= nurseryCapacity) {
              bug.assignedBuildingId = null;
              bug.assignedSlotIndex = null;
            } else {
              bug.assignedSlotIndex = assignedNursery++;
            }
          } else if (bug.assignedBuildingId != null &&
              !pTibugTerritoryBuildings.containsKey(bug.assignedBuildingId)) {
            bug.assignedBuildingId = null;
            bug.assignedSlotIndex = null;
          }
        }
        for (final bug in soldPTibugArchive) {
          _ensurePTibugAppearance(bug);
        }
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
        sourcierPatternIds
          ..clear()
          ..addAll(
            (ptibugData['sourcierPatternIds'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .where(pTibugConfig.researchPatterns.containsKey),
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
        pTibugArmatures
          ..clear()
          ..addAll((ptibugData['armatures'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(PTibugArmature.fromFirebase));
        pTibugCultivationTanks
          ..clear()
          ..addAll(
              (ptibugData['cultivationTanks'] as List? ?? const <dynamic>[])
                  .whereType<Map>()
                  .map(PTibugCultivationTank.fromFirebase));
        pTibugCultivationOperations
          ..clear()
          ..addAll((ptibugData['cultivationOperations'] as List? ??
                  const <dynamic>[])
              .whereType<Map>()
              .map(PTibugCultivationOperation.fromFirebase));
        pTibugAspectMatrices
          ..clear()
          ..addAll((ptibugData['aspectMatrices'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(PTibugAspectMatrix.fromFirebase));
        pTibugAspectExtractionOrder = ptibugData['aspectExtractionOrder'] is Map
            ? PTibugAspectExtractionOrder.fromFirebase(
                ptibugData['aspectExtractionOrder'] as Map)
            : null;
        pTibugAspectExtractorLevel = _readInt(
          ptibugData['aspectExtractorLevel'],
          fallback: 1,
        ).clamp(1, 4).toInt();
        firstCultivationTankGranted =
            ptibugData['firstCultivationTankGranted'] == true;
        // Exactly one free tank for old and new saves. Existing direct orders
        // remain untouched and are resolved once by the compatibility flow.
        _ensureCultivationTankSlots();
      }

      final buildingsData = data['buildings'];
      if (buildingsData is Map) {
        final communityData = buildingsData['communityProjects'];
        if (communityData is List) {
          communityProjects
            ..clear()
            ..addEntries(communityData.whereType<Map>().map((data) {
              final definition =
                  communityProjectDefinition('${data['projectId'] ?? ''}');
              return definition == null
                  ? null
                  : MapEntry(definition.id,
                      CommunityProjectProgress.fromFirebase(data, definition));
            }).whereType<MapEntry<String, CommunityProjectProgress>>());
        }
        final stockLossData = buildingsData['weatherStockLoss'];
        if (stockLossData is Map) {
          resolvedWeatherStockLossEventIds
            ..clear()
            ..addAll((stockLossData['resolvedEventIds'] as List? ?? const [])
                .map((item) => '$item'));
          lastWeatherStockIncident = stockLossData['lastIncident'] is Map
              ? WeatherStockIncident.fromFirebase(
                  stockLossData['lastIncident'] as Map)
              : null;
        }
        final viabilityData = buildingsData['viability'];
        if (viabilityData is Map) {
          buildingViabilities
            ..clear()
            ..addEntries(
              viabilityData.entries.whereType<MapEntry>().map(
                    (entry) => MapEntry(
                      '${entry.key}',
                      BuildingViabilityState.fromFirebase(entry.value as Map),
                    ),
                  ),
            );
        }
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
          towerWeatherModuleInstalled =
              towerData['weatherModuleInstalled'] == true;
          towerResearchModuleInstalled =
              towerData['researchModuleInstalled'] == true;
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
          protectedBatteryChestLevel = _readInt(
            houseData['protectedBatteryChestLevel'],
          ).clamp(
              0,
              campHeartConfig
                  .communityProjects.protectedBatteryUpgradeMaxLevel);
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
          residents
            ..clear()
            ..addAll(
              (housingData['residents'] as List? ?? const [])
                  .whereType<Map>()
                  .map(Zone0Resident.fromFirebase),
            );
          residentHouses
            ..clear()
            ..addAll(
              (housingData['functionalHouses'] as List? ?? const [])
                  .whereType<Map>()
                  .map(ResidentHouse.fromFirebase),
            );
          residentArrivalCandidates
            ..clear()
            ..addAll(
              (housingData['arrivalCandidates'] as List? ?? const [])
                  .whereType<Map>()
                  .map(ResidentArrivalCandidate.fromFirebase),
            );
          residentVisions
            ..clear()
            ..addAll((housingData['residentVisions'] as List? ?? const [])
                .whereType<Map>()
                .map(ResidentVision.fromFirebase)
                .where((vision) => vision.id.isNotEmpty));
          householdRepairJobs
            ..clear()
            ..addAll((housingData['householdRepairJobs'] as List? ?? const [])
                .whereType<Map>()
                .map(HouseholdRepairJob.fromFirebase)
                .where((job) => job.id.isNotEmpty));
          lastResidentArrivalResolutionAt =
              _readDate(housingData['lastResidentArrivalResolutionAt']);
          residentAutonomyGraceUntil =
              _readDate(housingData['residentAutonomyGraceUntil']);
          communityRoleAssignments
            ..clear()
            ..addAll(
              (housingData['communityRoleAssignments'] as List? ?? const [])
                  .whereType<Map>()
                  .map(CommunityRoleAssignment.fromFirebase)
                  .where((assignment) => assignment.id.isNotEmpty),
            );
          communityProductionBatches
            ..clear()
            ..addAll(
              (housingData['communityProductionBatches'] as List? ?? const [])
                  .whereType<Map>()
                  .map(CommunityProductionBatch.fromFirebase)
                  .where((batch) => batch.id.isNotEmpty),
            );
          residentEconomicTransactions
            ..clear()
            ..addAll(
              (housingData['residentEconomicTransactions'] as List? ?? const [])
                  .whereType<Map>()
                  .map(ResidentEconomicTransaction.fromFirebase)
                  .where((transaction) => transaction.id.isNotEmpty),
            );
          economicSettlementBatches
            ..clear()
            ..addAll(
              (housingData['economicSettlementBatches'] as List? ?? const [])
                  .whereType<Map>()
                  .map(EconomicSettlementBatch.fromFirebase)
                  .where((batch) => batch.id.isNotEmpty),
            );
          residentUncoveredNeeds
            ..clear()
            ..addAll(
              (housingData['residentUncoveredNeeds'] as List? ?? const [])
                  .whereType<Map>()
                  .map(ResidentUncoveredNeed.fromFirebase)
                  .where((need) => need.id.isNotEmpty),
            );
          residentPopulationMigrationCompleted =
              housingData['residentPopulationMigrationCompleted'] == true;
          residentNeedsMigrationCompleted =
              housingData['residentNeedsMigrationCompleted'] == true;
          residentNeedsGraceUntil =
              _readDate(housingData['residentNeedsGraceUntil']);
          lastResidentNeedsResolutionDayKey =
              '${housingData['lastResidentNeedsResolutionDayKey'] ?? ''}';
          resolvedResidentWeatherEventIds
            ..clear()
            ..addAll((housingData['resolvedResidentWeatherEventIds'] as List? ??
                    const [])
                .map((item) => '$item'));
          residentPassionMigrationCompleted =
              housingData['residentPassionMigrationCompleted'] == true;
          lastCommunityRoleResolutionAt =
              _readDate(housingData['lastCommunityRoleResolutionAt']);
          residentEconomyMigrationCompleted =
              housingData['residentEconomyMigrationCompleted'] == true;
          lastResidentEconomyResolvedAt =
              _readDate(housingData['lastResidentEconomyResolvedAt']);
          lastEconomicSettlementDayKey =
              '${housingData['lastEconomicSettlementDayKey'] ?? ''}';
          lastDomesticEnergyDistributionAt =
              _readDate(housingData['lastDomesticEnergyDistributionAt']);
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
      _migrateBuildingViability();
      _migrateResidentsAndHouses();
      _migrateResidentNeeds();
      resolveResidentNeeds();
      _migrateResidentPassionsAndRoles();
      _migrateResidentEconomy();
      _resolveResidentVisions();
      residentAutonomyGraceUntil ??= DateTime.now()
          .add(Duration(hours: housingConfig.householdAutonomyGraceHours));
      bioGeneratorMovedToPlayerHouse =
          data['bioGeneratorMovedToPlayerHouse'] == true ||
              bioGeneratorMovedToPlayerHouse;
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
      final discoveredSourcierPatterns =
          _refreshPTibugResearchPatternDiscoveries();
      final refreshedMerchantOffers = _refreshMerchantOffersForCurrentRules();
      final hadEnergyCorePattern = energyCorePatternDiscovered;
      final removedPrematureEnergyCore = _migratePrematureEnergyCorePattern();
      _loadedFromFirebase = true;
      resolveCoBreedingSessions();
      _resolveEnergyCoreMilestones();
      resolveConstructionProjects();
      if (migratedPTibugState ||
          discoveredSourcierPatterns ||
          refreshedMerchantOffers ||
          removedPrematureEnergyCore ||
          hadEnergyCorePattern != energyCorePatternDiscovered) {
        unawaited(saveRuntimeToFirebase());
      }
    });
  }

  /// Keeps saves made before data cells, permanent traits and module instances.
  /// The migration only adds compatibility data; it never removes player items.
  bool _migratePTibugScientificState() {
    var changed = false;
    final now = DateTime.now();

    // Older P’TIBUGs sometimes used their species as their only visible name.
    // Give those entries one stable temporary identity once, never on every
    // launch, while preserving player-created names verbatim.
    for (final bug in pTibugs) {
      final speciesName = pTibugConfig.species[bug.species]?.displayName;
      if (speciesName != null && bug.displayName == speciesName) {
        final suffix =
            bug.id.length <= 4 ? bug.id : bug.id.substring(bug.id.length - 4);
        bug
          ..defaultDisplayName = '$speciesName $suffix'
          ..displayName = '$speciesName $suffix'
          ..updatedAt = now;
        changed = true;
      }
      if (bug.defaultDisplayName.trim().isEmpty) {
        bug.defaultDisplayName = bug.displayName;
        changed = true;
      }
    }

    // Éclaireur is the historical name of Capteur intelligent. Keep every
    // acquired level, owner and Pattern investment; this is a rename, never a
    // new free Trait or a new Cellule roll.
    for (final oldId in <String>[
      'trait-eclaireur',
      'ptibug-trait-eclaireur',
    ]) {
      final progress = pTibugPatternProgress.remove(oldId);
      if (progress == null) continue;
      final targetId = 'ptibug-trait-capteurIntelligent';
      final target = pTibugPatternProgress[targetId];
      if (target == null) {
        pTibugPatternProgress[targetId] = PTibugPatternProgress(
          patternId: targetId,
          state: progress.state,
          masteryLevel: progress.masteryLevel,
          investedDataByFamily: progress.investedDataByFamily,
          discoveredAt: progress.discoveredAt,
          activatedAt: progress.activatedAt,
        );
      } else {
        target.masteryLevel =
            math.max(target.masteryLevel, progress.masteryLevel);
        if (progress.state.index > target.state.index)
          target.state = progress.state;
      }
      changed = true;
    }
    for (var index = 0; index < pTibugTraitData.length; index += 1) {
      final data = pTibugTraitData[index];
      if (data.definitionId != 'eclaireur') continue;
      pTibugTraitData[index] = PTibugTraitData(
        id: data.id,
        definitionId: 'capteurIntelligent',
        grade: data.grade,
      );
      changed = true;
    }

    // Early remote configurations used `trait-<id>` for Trait Patterns.
    // Keep the player's existing mastery under the canonical Pattern id so an
    // already researched Trait remains usable after the configuration update.
    for (final trait in pTibugConfig.traitDefinitions.keys) {
      final legacyId = 'trait-$trait';
      final canonicalId = 'ptibug-trait-$trait';
      final legacyProgress = pTibugPatternProgress.remove(legacyId);
      if (legacyProgress == null) continue;
      final canonicalProgress = pTibugPatternProgress[canonicalId];
      if (canonicalProgress == null) {
        pTibugPatternProgress[canonicalId] = PTibugPatternProgress(
          patternId: canonicalId,
          state: legacyProgress.state,
          masteryLevel: legacyProgress.masteryLevel,
          investedDataByFamily: legacyProgress.investedDataByFamily,
          discoveredAt: legacyProgress.discoveredAt,
          activatedAt: legacyProgress.activatedAt,
        );
      } else {
        if (legacyProgress.masteryLevel > canonicalProgress.masteryLevel) {
          canonicalProgress.masteryLevel = legacyProgress.masteryLevel;
        }
        if (legacyProgress.state.index > canonicalProgress.state.index) {
          canonicalProgress.state = legacyProgress.state;
        }
        canonicalProgress
          ..discoveredAt ??= legacyProgress.discoveredAt
          ..activatedAt ??= legacyProgress.activatedAt;
        for (final entry in legacyProgress.investedDataByFamily.entries) {
          final current =
              canonicalProgress.investedDataByFamily[entry.key] ?? 0;
          if (entry.value > current) {
            canonicalProgress.investedDataByFamily[entry.key] = entry.value;
          }
        }
      }
      changed = true;
    }
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
      if (bug.biologicalTraitId == 'eclaireur') {
        bug.biologicalTraitId = 'capteurIntelligent';
        changed = true;
      }
      if (bug.secondTraitId == 'eclaireur') {
        bug.secondTraitId = 'capteurIntelligent';
        changed = true;
      }
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

    // Older saves can contain cells created before the five-entry contract.
    // Only unopened cells are completed, so no already-granted data is added.
    for (final cell in pTibugDataCells.where((item) => !item.isOpened)) {
      final fallbackFamily = cell.dominantFamily ?? PTibugDataFamily.organique;
      while (cell.entries.length < 5) {
        cell.entries.add(
          PTibugDataCellEntry(
            family: fallbackFamily,
            quality: PTibugDataQuality.common,
            slotIndex: cell.entries.length,
          ),
        );
        changed = true;
      }
      if (cell.entries.length > 5) {
        cell.entries.removeRange(5, cell.entries.length);
        changed = true;
      }
    }

    for (var index = 0; index < pTibugCapsules.length; index += 1) {
      final capsule = pTibugCapsules[index];
      if (capsule.originRefugeId != null &&
          capsule.creatorPlayerId != null &&
          capsule.certificationId != null) {
        continue;
      }
      pTibugCapsules[index] = capsule.copyWith(
        originRefugeId: capsule.originRefugeId ?? 'legacy-refuge',
        creatorPlayerId: capsule.creatorPlayerId ?? 'legacy-player',
        certificationId: capsule.certificationId ?? 'legacy-${capsule.id}',
      );
      changed = true;
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
    ForageMissionType type = ForageMissionType.harvest,
  }) {
    final start = DateTime.now();
    final durationConfig = lisiereForageConfig.durations[duration]!;
    final intensityConfig = lisiereForageConfig.intensities[intensity]!;
    for (final figurine in figurines) {
      _synchronizePtipoteProgress(figurine);
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
      type: type,
      startTime: start,
      endTime: start.add(
        Duration(
          seconds: math.max(
            1,
            (durationConfig
                        .realDuration(lisiereForageConfig.forageTimeScale)
                        .inSeconds *
                    intensityConfig.timeMultiplier)
                .round(),
          ),
        ),
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
    for (final research in towerBiomeResearch.where(
      (item) => item.isActive && !item.endsAt.isAfter(current),
    )) {
      final state = biomeSecurity[research.biome]!;
      state.researchProgress = math.min(
        100,
        state.researchProgress +
            research.theoreticalHours *
                towerOperationsConfig.research.progressPerHour,
      );
      state.lastResearchDecayAt = current;
      final cells = _createTowerResearchCells(research, completedAt: current);
      pTibugDataCells.addAll(cells);
      research.completedAt = current;
      reports.add(PtipoteMissionReport.system(
        message:
            'Recherche de ${lisiereForageConfig.biomes[research.biome]!.label} : ${state.researchProgress}% de données locales${cells.isEmpty ? '' : ' · ${cells.length} Cellule(s) trouvée(s)'}.',
      ));
      changed = true;
    }
    for (final state in biomeSecurity.values) {
      changed = _regenerateBiomeWaste(state: state, now: current) || changed;
      changed = _regenerateBiomeBiomass(state: state, now: current) || changed;
      final lastResearch = state.lastResearchDecayAt;
      if (lastResearch == null || current.isBefore(lastResearch)) {
        state.lastResearchDecayAt = current;
        changed = true;
      } else {
        final elapsedDays = current.difference(lastResearch).inDays;
        if (elapsedDays > 0 && state.researchProgress > 0) {
          state.researchProgress = math.max(
            0,
            state.researchProgress -
                elapsedDays *
                    towerOperationsConfig.research.progressDecayPerDay,
          );
          state.lastResearchDecayAt =
              lastResearch.add(Duration(days: elapsedDays));
          changed = true;
        }
      }
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
    merchantCallRequestedAt = null;
    merchantAvailableUntil = current.add(
      Duration(hours: towerOperationsConfig.merchantPresenceHours),
    );
    _generateMerchantOffers();
    _generateSourcierContract(current);
    reports.add(
      PtipoteMissionReport.system(
        message:
            'Le Sourcier est arrivé au Marché avec trois Cellules et un lot de produit fini de l’Atelier.',
        sourceBuildingId: 'market',
        subject: 'Sourcier arrivé',
        concerned: 'Joueur',
        summary: 'Nouvelles offres disponibles pendant deux heures.',
      ),
    );
  }

  void _generateSourcierContract(DateTime now) {
    final openOffers = marketContracts.where((item) =>
        item.status == MarketContractStatus.offered ||
        item.status == MarketContractStatus.accepted);
    if (openOffers.isNotEmpty || marketLevel < 1) return;
    final useLicense = activeMarketLicenses.isNotEmpty &&
        _random.nextInt(100) < marketConfig.licenseDirectedRatioPercent;
    final category = useLicense
        ? activeMarketLicenses.elementAt(
            _random.nextInt(activeMarketLicenses.length),
          )
        : 'materials';
    final item = category == 'atelier' && marketLevel >= 2
        ? 'Filtre'
        : category == 'structure' && marketLevel >= 3
            ? 'Ventilation Termite'
            : category == 'ptibug'
                ? (_random.nextInt(100) < 60
                    ? (_random.nextBool()
                        ? 'Matrice P’TIBUG'
                        : marketMatrixItemForSpecies(PTibugSpecies.values[
                            _random.nextInt(PTibugSpecies.values.length)]))
                    : <String>[
                        'P’TIBUG Scarabé',
                        'P’TIBUG Hyme',
                        'P’TIBUG Arac',
                      ][_random.nextInt(3)])
                : _random.nextBool()
                    ? 'Organique'
                    : 'Minéral';
    final isMatrix = _isMarketMatrixResource(item);
    final quantity = item == 'Organique' || item == 'Minéral'
        ? 10
        : isMatrix
            ? 2 + (_random.nextInt(6) * 2)
            : 1;
    final ptibugSpecies = _marketPTibugSpecies(item);
    // La base d'un contrat P'TIBUG est la certification Nurserie : un niveau
    // 1 ne peut donc jamais être proposé sous sa valeur de base. La confiance
    // reste appliquée séparément au moment du paiement.
    final basePayment = isMatrix
        ? quantity * (item == 'Matrice P’TIBUG' ? 1 : 2)
        : ptibugSpecies == null
            ? (marketConfig.salePriceInBioPiles(item) * quantity / 100).ceil()
            : _sourcierPTibugContractBasePaymentFor(ptibugSpecies);
    marketContracts.add(MarketSourcierContract(
      contractId: 'contract-${now.microsecondsSinceEpoch}',
      marketLevelRequired: marketLevel,
      category: category,
      requestedItems: <String, int>{item: quantity},
      rewardBioBatteries: math.max(1, basePayment),
      confidenceReward: marketConfig.confidenceSuccessGain,
      confidencePenalty: marketConfig.confidenceFailurePenalty,
      offeredAt: now,
      // Le Sourcier laisse davantage de temps à la Nurserie pour un P’TIBUG
      // de base. Les commandes Trait et Module seront ajoutées séparément.
      expiresAt: now.add(Duration(hours: category == 'ptibug' ? 48 : 12)),
      assignedLicense:
          activeMarketLicenses.contains(category) ? category : null,
    ));
  }

  int _sourcierPTibugContractBasePaymentFor(PTibugSpecies species) {
    final valuation = PTibugValuationService(pTibugConfig.valuation).evaluate(
      PTibugValuationInput(
        species: species,
        level: 1,
        traitRanks: const <int>[],
        modules: const <PTibugModuleType>[],
      ),
    );
    return math.max(
      pTibugConfig.valuation.baseValueFor(species),
      valuation.total,
    );
  }

  /// Anciennes sauvegardes : certains contrats P'TIBUG ont été créés avec
  /// une conversion de piles erronée. Les contrats encore ouverts sont remis
  /// au minimum de la certification Nurserie, sans modifier les ventes déjà
  /// réalisées ni les autres catégories de contrat.
  bool _migrateLegacyPTibugContractValues() {
    var changed = false;
    for (final contract in marketContracts) {
      if (contract.status == MarketContractStatus.completed ||
          contract.category != 'ptibug' ||
          contract.requestedItems.length != 1) {
        continue;
      }
      final species = _marketPTibugSpecies(contract.requestedItems.keys.first);
      if (species == null) continue;
      final minimum = _sourcierPTibugContractBasePaymentFor(species);
      if (contract.rewardBioBatteries < minimum) {
        contract.rewardBioBatteries = minimum;
        changed = true;
      }
    }
    return changed;
  }

  Zone0ActionResult claimFirstMarketShop(String specialization) {
    return prepareMarketShopConstruction(specialization, primary: false);
  }

  Zone0ActionResult buildMarketShop(String specialization) {
    return prepareMarketShopConstruction(specialization, primary: false);
  }

  Zone0ActionResult upgradeMarketShop(String shopId) {
    return prepareMarketShopUpgrade(shopId);
  }

  Zone0ActionResult setMarketLicense(String category) {
    if (marketConfig.licenseSlotsForLevel(marketLevel) <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Licences disponibles à partir du Marché niveau 2.',
      );
    }
    const categories = <String>{'materials', 'atelier', 'structure', 'ptibug'};
    if (!categories.contains(category))
      return const Zone0ActionResult(
          success: false, message: 'Licence inconnue.');
    final replacing = activeMarketLicenses.isNotEmpty &&
        activeMarketLicenses.length >=
            marketConfig.licenseSlotsForLevel(marketLevel);
    final cost = activeMarketLicenses.contains(category)
        ? 0
        : replacing
            ? marketConfig.licenseCostBioBatteries +
                marketConfig.licenseChangeCostBioBatteries
            : marketConfig.licenseCostBioBatteries;
    if (bioBatteries < cost)
      return const Zone0ActionResult(
          success: false, message: 'Bio-batteries insuffisantes.');
    if (replacing) activeMarketLicenses.remove(activeMarketLicenses.first);
    bioBatteries -= cost;
    activeMarketLicenses.add(category);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: 'Licence $category active.');
  }

  void _generateMerchantOffers() {
    merchantOffers.clear();
    final families = List<PTibugDataFamily>.from(PTibugDataFamily.values)
      ..shuffle(_random);
    final firstDominant = families.first;
    final secondDominant = families[1];
    final thirdDominant = families[2];
    final firstCell = _createMerchantDataCell(
      neutral: false,
      dominant: firstDominant,
    );
    final secondCell = _createMerchantDataCell(
      neutral: false,
      dominant: secondDominant,
    );
    final thirdCell = _createMerchantDataCell(
      neutral: false,
      dominant: thirdDominant,
    );
    merchantOffers.addAll(<MerchantOffer>[
      MerchantOffer(
        planName: 'Cellule ${_ptibugDataFamilyLabel(firstDominant)}',
        price: _merchantDataCellPrice(firstCell),
        kind: MerchantOfferKind.specializedDataCell,
        dominantDataFamily: firstDominant,
        dataCell: firstCell,
      ),
      MerchantOffer(
        planName: 'Cellule ${_ptibugDataFamilyLabel(secondDominant)}',
        price: _merchantDataCellPrice(secondCell),
        kind: MerchantOfferKind.specializedDataCell,
        dominantDataFamily: secondDominant,
        dataCell: secondCell,
      ),
      MerchantOffer(
        planName: 'Cellule ${_ptibugDataFamilyLabel(thirdDominant)}',
        price: _merchantDataCellPrice(thirdCell),
        kind: MerchantOfferKind.specializedDataCell,
        dominantDataFamily: thirdDominant,
        dataCell: thirdCell,
      ),
    ]);
    final products = towerOperationsConfig.merchantOfferPrices.entries
        .toList(growable: false)
      ..shuffle(_random);
    final minimumQuantity = math.max(
      1,
      towerOperationsConfig.merchantWorkshopMinimumQuantity,
    );
    final maximumQuantity = math.max(
      minimumQuantity,
      towerOperationsConfig.merchantWorkshopMaximumQuantity,
    );
    final offerCount = math.min(
      products.length,
      math.max(0, towerOperationsConfig.merchantWorkshopOfferCount),
    );
    for (final product in products.take(offerCount)) {
      final amount = minimumQuantity +
          _random.nextInt(maximumQuantity - minimumQuantity + 1);
      merchantOffers.add(
        MerchantOffer(
          planName: product.key,
          price: product.value,
          kind: MerchantOfferKind.workshopItem,
          itemName: product.key,
          itemAmount: amount,
          remainingItemAmount: amount,
        ),
      );
    }
  }

  int _merchantDataCellPrice(PTibugDataCell cell) {
    final value = cell.entries.fold<int>(
      0,
      (total, entry) => total + entry.value(pTibugConfig),
    );
    return math.max(1, value * pTibugConfig.sourcierCellPricePerDataValue);
  }

  bool _refreshMerchantOffersForCurrentRules() {
    if (!isMerchantAvailable) return false;
    final patterns = merchantOffers
        .where((offer) => offer.kind == MerchantOfferKind.researchPattern)
        .length;
    final cells = merchantOffers
        .where(
          (offer) =>
              offer.kind == MerchantOfferKind.specializedDataCell ||
              offer.kind == MerchantOfferKind.neutralDataCell,
        )
        .toList(growable: false);
    final products = merchantOffers
        .where((offer) => offer.kind == MerchantOfferKind.workshopItem)
        .toList(growable: false);
    final desiredProductCount = math.min(
      towerOperationsConfig.merchantOfferPrices.length,
      math.max(0, towerOperationsConfig.merchantWorkshopOfferCount),
    );
    final minimumQuantity = math.max(
      1,
      towerOperationsConfig.merchantWorkshopMinimumQuantity,
    );
    final maximumQuantity = math.max(
      minimumQuantity,
      towerOperationsConfig.merchantWorkshopMaximumQuantity,
    );
    final matchesCurrentRules = patterns == 0 &&
        cells.length == 3 &&
        cells.every((offer) => offer.dataCell != null) &&
        products.length == desiredProductCount &&
        products.every(
          (offer) =>
              offer.itemAmount >= minimumQuantity &&
              offer.itemAmount <= maximumQuantity &&
              offer.itemName != null &&
              towerOperationsConfig.merchantOfferPrices.containsKey(
                offer.itemName,
              ) &&
              offer.planName == offer.itemName,
        );
    if (matchesCurrentRules) return false;
    _generateMerchantOffers();
    return true;
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

  Zone0ActionResult requestMerchantVisit() {
    final current = DateTime.now();
    _resetMerchantVisitDay(current);
    if (isMerchantAvailable) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Sourcier est déjà présent au Marché.',
      );
    }
    if (merchantVisitsRemaining <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Sourcier a déjà effectué ses passages aujourd’hui.',
      );
    }
    if (hasPendingMerchantCall) {
      return const Zone0ActionResult(
        success: false,
        message: 'Un appel au Sourcier est déjà en cours.',
      );
    }
    final batteryCost =
        math.max(0, towerOperationsConfig.merchantCallBatteryCost);
    if (bioBatteries < batteryCost) {
      return Zone0ActionResult(
        success: false,
        message:
            'Il faut $batteryCost bio-batterie(s) pour appeler le Sourcier.',
      );
    }

    final randomWait = math.max(
      0,
      towerOperationsConfig.merchantCallRandomWaitAdditionalMinutes,
    );
    final waitMinutes = math.max(
          0,
          towerOperationsConfig.merchantCallMinimumWaitMinutes,
        ) +
        (randomWait == 0 ? 0 : _random.nextInt(randomWait + 1));
    bioBatteries -= batteryCost;
    merchantCallRequestedAt = current;
    merchantNextArrivalAt = current.add(Duration(minutes: waitMinutes));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Le Sourcier arrivera dans $waitMinutes min.',
    );
  }

  void _finishMerchantVisit(DateTime current, {required String message}) {
    merchantAvailableUntil = null;
    merchantCallRequestedAt = null;
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

  Zone0ActionResult buyMerchantOffer(MerchantOffer offer, {int quantity = 1}) {
    if (!isMerchantAvailable || offer.isUnavailable) {
      return const Zone0ActionResult(
        success: false,
        message: 'Offre indisponible.',
      );
    }
    if (offer.kind == MerchantOfferKind.speciesPattern ||
        offer.kind == MerchantOfferKind.researchPattern) {
      return const Zone0ActionResult(
        success: false,
        message:
            'Les Patterns sont désormais découverts directement par le Kernel.',
      );
    }
    final selectedQuantity = offer.kind == MerchantOfferKind.workshopItem
        ? quantity.clamp(1, offer.remainingItemAmount).toInt()
        : 1;
    final totalPrice = offer.priceForQuantity(selectedQuantity);
    if (bioBatteries < totalPrice) {
      return const Zone0ActionResult(
        success: false,
        message: 'Bio-batteries insuffisantes.',
      );
    }
    bioBatteries -= totalPrice;
    if (offer.kind == MerchantOfferKind.workshopItem) {
      offer.remainingItemAmount -= selectedQuantity;
      offer.purchased = offer.remainingItemAmount <= 0;
    } else {
      offer.purchased = true;
    }
    final sourcierPatternId = offer.kind == MerchantOfferKind.speciesPattern &&
            offer.pTibugSpecies != null
        ? 'ptibug-species-${offer.pTibugSpecies!.name}'
        : offer.kind == MerchantOfferKind.researchPattern
            ? offer.patternId
            : null;
    if (sourcierPatternId != null) {
      sourcierPatternIds.add(sourcierPatternId);
      _refreshPTibugResearchPatternDiscoveries();
      reports.add(
        PtipoteMissionReport.system(
          message:
              '${offer.planName} est conservé dans le stock du Kernel. Il sera découvert dès que les niveaux requis seront atteints, puis les Cellules permettront son activation.',
          sourceBuildingId: 'kernel',
          subject: 'Recherche disponible',
          concerned: 'Kernel',
          summary: offer.planName,
        ),
      );
    } else if (offer.kind == MerchantOfferKind.workshopItem ||
        offer.kind == MerchantOfferKind.plan) {
      final itemName =
          offer.itemName ?? offer.planName.replaceFirst('Plan ', '');
      final amount = selectedQuantity;
      addResources(<String, int>{itemName: amount});
      reports.add(
        PtipoteMissionReport.system(
          message: '$amount $itemName reçu(s) du Sourcier.',
          sourceBuildingId: 'market',
        ),
      );
    } else if (offer.kind == MerchantOfferKind.specializedDataCell ||
        offer.kind == MerchantOfferKind.neutralDataCell) {
      pTibugDataCells.add(
        offer.dataCell ??
            _createMerchantDataCell(
              neutral: offer.kind == MerchantOfferKind.neutralDataCell,
              dominant: offer.dominantDataFamily,
            ),
      );
    } else if (offer.kind == MerchantOfferKind.module &&
        offer.moduleType != null) {
      pTibugModuleInstances.add(
        PTibugModuleInstance(
          id: 'sourcier-module-${DateTime.now().microsecondsSinceEpoch}',
          type: offer.moduleType!,
          createdAt: DateTime.now(),
          source: 'sourcier',
        ),
      );
    } else if (offer.kind == MerchantOfferKind.capsule &&
        offer.capsule != null) {
      pTibugCapsules.add(
        offer.capsule!.copyWith(
          id: 'sourcier-capsule-${DateTime.now().microsecondsSinceEpoch}',
          createdAt: DateTime.now(),
          certificationId:
              'sourcier-cert-${DateTime.now().microsecondsSinceEpoch}',
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
        merchantOffers.every((item) => item.isUnavailable)) {
      _finishMerchantVisit(
        DateTime.now(),
        message: 'Toutes les offres du Sourcier ont été acquises.',
      );
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${offer.planName} acheté${selectedQuantity > 1 ? ' ×$selectedQuantity' : ''}.',
    );
  }

  PTibugDataCell _createMerchantDataCell({
    required bool neutral,
    PTibugDataFamily? dominant,
  }) {
    final selectedDominant =
        neutral ? null : (dominant ?? PTibugDataFamily.organique);
    final shuffledFamilies = List<PTibugDataFamily>.from(
      PTibugDataFamily.values,
    )..shuffle(_random);
    return PTibugDataCell(
      id: 'sourcier-cell-${DateTime.now().microsecondsSinceEpoch}',
      displayName: neutral
          ? 'Cellule neutre du Sourcier'
          : 'Cellule ${_ptibugDataFamilyLabel(selectedDominant!)} du Sourcier',
      sourceBiomeId: 'sourcier',
      dominantFamily: selectedDominant,
      isNeutralCell: neutral,
      entries: List<PTibugDataCellEntry>.generate(5, (index) {
        final family = neutral
            ? shuffledFamilies[index % shuffledFamilies.length]
            : index < 2
                ? selectedDominant!
                : _pickWeightedDataFamily(<PTibugDataFamily, int>{
                    for (final value in PTibugDataFamily.values) value: 1,
                    selectedDominant!: 5,
                  });
        return PTibugDataCellEntry(
          family: family,
          quality: _pickWeightedDataQuality(),
          slotIndex: index,
        );
      }),
      createdAt: DateTime.now(),
    );
  }

  void ensureWeatherForecast() {
    resolveWeatherCycle(forceFirstAlert: true);
  }

  bool resolveWeatherCycle({DateTime? now, bool forceFirstAlert = false}) {
    final current = now ?? DateTime.now();
    _resolveCommunityDailyContribution(current);
    var changed = _closeFinishedWeatherAlerts(current);
    if (!isTowerWeatherUnlocked) return changed;

    _migrateGlobalWeatherIfNeeded(current);
    activeGlobalWeatherEvent ??= _newGlobalWeatherEvent(
      startsAt: current,
      intensity: GlobalWeatherIntensity.calm,
    )..status = GlobalWeatherEventStatus.active;
    // Les anciennes sauvegardes n'ont pas de Viabilité : marquer l'événement
    // transitoire sans dégâts évite d'appliquer rétroactivement la météo.
    for (final state in buildingViabilities.values) {
      state.lastDamageEventId ??= activeGlobalWeatherEvent!.id;
    }
    nextGlobalWeatherEvent ??= _newGlobalWeatherEvent(
      startsAt: activeGlobalWeatherEvent!.endsAt,
    );

    while (!current.isBefore(activeGlobalWeatherEvent!.endsAt)) {
      _clearResidentWeatherImpact(activeGlobalWeatherEvent!);
      activeGlobalWeatherEvent!.status = GlobalWeatherEventStatus.completed;
      final promoted = nextGlobalWeatherEvent!;
      promoted.status = GlobalWeatherEventStatus.active;
      activeGlobalWeatherEvent = promoted;
      _applyWeatherViabilityDamage(promoted);
      _applyWeatherHouseDamage(promoted);
      _applyWeatherStockLosses(promoted);
      _resolveResidentWeatherImpact(promoted);
      _notifyGlobalWeatherStarted(promoted);
      nextGlobalWeatherEvent = _newGlobalWeatherEvent(
        startsAt: promoted.endsAt,
      );
      changed = true;
    }
    final upcoming = nextGlobalWeatherEvent!;
    if (upcoming.status == GlobalWeatherEventStatus.planned &&
        !current.isBefore(upcoming.announcedAt)) {
      upcoming.status = GlobalWeatherEventStatus.announced;
      _announceGlobalWeather(upcoming);
      _prepareResidentWeatherNeeds(upcoming);
      changed = true;
    }
    return changed || forceFirstAlert;
  }

  void _migrateGlobalWeatherIfNeeded(DateTime now) {
    if (activeGlobalWeatherEvent != null) return;
    final legacy =
        weatherAlerts.where((alert) => alert.endsAt.isAfter(now)).firstOrNull;
    if (legacy == null) return;
    activeGlobalWeatherEvent = _newGlobalWeatherEvent(
      startsAt: legacy.startsAt,
      type: legacy.type,
      intensity: GlobalWeatherIntensity.strong,
      endsAt: legacy.endsAt,
      status: legacy.startsAt.isAfter(now)
          ? GlobalWeatherEventStatus.announced
          : GlobalWeatherEventStatus.active,
      id: 'migrated-${legacy.id}',
    );
  }

  GlobalWeatherEvent _newGlobalWeatherEvent({
    required DateTime startsAt,
    TowerWeatherType? type,
    GlobalWeatherIntensity? intensity,
    DateTime? endsAt,
    GlobalWeatherEventStatus status = GlobalWeatherEventStatus.planned,
    String? id,
  }) {
    final settings = towerOperationsConfig.globalWeather;
    final selectedIntensity = intensity ?? _pickGlobalWeatherIntensity();
    final selectedType = type ??
        (selectedIntensity == GlobalWeatherIntensity.calm
            ? TowerWeatherType.calm
            : _weightedWeatherConfig().type);
    final eventEndsAt =
        endsAt ?? startsAt.add(Duration(minutes: settings.cycleMinutes));
    return GlobalWeatherEvent(
      id: id ?? 'global-weather-${startsAt.microsecondsSinceEpoch}',
      type: selectedType,
      intensity: selectedIntensity,
      plannedAt: startsAt,
      announcedAt:
          startsAt.subtract(Duration(minutes: settings.forecastMinutes)),
      startsAt: startsAt,
      endsAt: eventEndsAt,
      status: status,
      affectedBiomes:
          _globalWeatherBiomeImpacts(selectedType, selectedIntensity),
      seed: _random.nextInt(1 << 31),
    );
  }

  GlobalWeatherIntensity _pickGlobalWeatherIntensity() {
    final settings = towerOperationsConfig.globalWeather;
    final forceCalm = globalWeatherConsecutiveAdverseEvents >=
            settings.maximumConsecutiveAdverseEvents &&
        _random.nextInt(100) < settings.forcedCalmChancePercent;
    if (forceCalm) return GlobalWeatherIntensity.calm;
    final choices = GlobalWeatherIntensity.values.where((intensity) {
      if (intensity != GlobalWeatherIntensity.severe) return true;
      return globalWeatherConsecutiveSevereEvents <
          settings.allowConsecutiveSevereEvents + 1;
    }).toList();
    final total = choices.fold<int>(0,
        (sum, item) => sum + math.max(0, settings.intensities[item]!.weight));
    if (total <= 0) return GlobalWeatherIntensity.calm;
    var roll = _random.nextInt(total);
    for (final item in choices) {
      roll -= math.max(0, settings.intensities[item]!.weight);
      if (roll < 0) return item;
    }
    return choices.last;
  }

  List<GlobalWeatherBiomeImpact> _globalWeatherBiomeImpacts(
    TowerWeatherType type,
    GlobalWeatherIntensity intensity,
  ) {
    if (type == TowerWeatherType.calm) {
      return <GlobalWeatherBiomeImpact>[
        for (final biome in ForageBiome.values)
          GlobalWeatherBiomeImpact(biome: biome, isAffected: false),
      ];
    }
    final settings = towerOperationsConfig.globalWeather;
    final requested = settings.intensities[intensity]!;
    final eligible = ForageBiome.values.where((biome) {
      final sensitivity = settings.biomeSensitivities[biome.name]?[type];
      return sensitivity != null && !sensitivity.immune;
    }).toList()
      ..sort((a, b) => (settings
                  .biomeSensitivities[b.name]?[type]?.chancePercent ??
              0)
          .compareTo(
              settings.biomeSensitivities[a.name]?[type]?.chancePercent ?? 0));
    final count = math.min(
      eligible.length,
      math.max(
          requested.minimumAffectedBiomes,
          requested.minimumAffectedBiomes +
              _random.nextInt(math.max(
                  1,
                  requested.maximumAffectedBiomes -
                      requested.minimumAffectedBiomes +
                      1))),
    );
    final affected = eligible.take(count).toSet();
    return <GlobalWeatherBiomeImpact>[
      for (final biome in ForageBiome.values)
        () {
          final sensitivity = settings.biomeSensitivities[biome.name]?[type];
          final active = affected.contains(biome);
          final multiplier = sensitivity?.impactMultiplier ?? 0;
          final level = multiplier >= 1.25
              ? 'high'
              : multiplier <= 0.75
                  ? 'low'
                  : 'medium';
          return GlobalWeatherBiomeImpact(
            biome: biome,
            isAffected: active,
            localImpactLevel: active ? level : 'none',
            localImpactMultiplier: active ? multiplier : 0,
            sensitivityMultiplier: multiplier,
            displayReason: sensitivity?.reason,
          );
        }(),
    ];
  }

  void _announceGlobalWeather(GlobalWeatherEvent event) {
    if (event.type == TowerWeatherType.calm) return;
    final config = towerOperationsConfig.weatherEvents
        .where((item) => item.type == event.type)
        .firstOrNull;
    if (config == null) return;
    _createWeatherAlert(
      config,
      event.announcedAt,
      manual: false,
      startsAt: event.startsAt,
      endsAt: event.endsAt,
      globalWeatherEventId: event.id,
      announcementMessage:
          'Prévision de la Tour : ${_weatherTypeLabel(event.type)} ${_weatherIntensityLabel(event.intensity)} dans ${towerOperationsConfig.globalWeather.forecastMinutes ~/ 60} h. Biomes affectés : ${event.affectedBiomes.where((item) => item.isAffected).map((item) => lisiereForageConfig.biomes[item.biome]!.label).join(', ')}.',
    );
  }

  void _notifyGlobalWeatherStarted(GlobalWeatherEvent event) {
    if (event.type == TowerWeatherType.calm) {
      globalWeatherConsecutiveAdverseEvents = 0;
      globalWeatherConsecutiveSevereEvents = 0;
      return;
    }
    reports.add(PtipoteMissionReport.system(
      message:
          '${_weatherTypeLabel(event.type)} ${_weatherIntensityLabel(event.intensity)} active.',
      sourceBuildingId: 'securityTower',
      mailbox: Zone0MessageMailbox.companions,
      subject: 'Météo active',
      concerned: 'Zone 0',
      summary:
          'Biomes touchés : ${event.affectedBiomes.where((item) => item.isAffected).map((item) => lisiereForageConfig.biomes[item.biome]!.label).join(', ')}. Consulte la Tour.',
    ));
    globalWeatherConsecutiveAdverseEvents += 1;
    globalWeatherConsecutiveSevereEvents =
        event.intensity == GlobalWeatherIntensity.severe
            ? globalWeatherConsecutiveSevereEvents + 1
            : 0;
  }

  String _weatherTypeLabel(TowerWeatherType type) => switch (type) {
        TowerWeatherType.calm => 'Temps calme',
        TowerWeatherType.toxicCloud => 'Nuage toxique',
        TowerWeatherType.heatWave => 'Forte chaleur',
        TowerWeatherType.heavyRain => 'Pluie intense',
      };

  String _weatherIntensityLabel(GlobalWeatherIntensity intensity) =>
      switch (intensity) {
        GlobalWeatherIntensity.calm => 'Calme',
        GlobalWeatherIntensity.moderate => 'Modérée',
        GlobalWeatherIntensity.strong => 'Forte',
        GlobalWeatherIntensity.severe => 'Sévère',
      };

  Zone0ActionResult triggerManualWeatherAlert(TowerWeatherType type) {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Tour de sécurité doit être construite.',
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
    final current = DateTime.now();
    activeGlobalWeatherEvent = _newGlobalWeatherEvent(
      startsAt: current,
      type: type,
      intensity: GlobalWeatherIntensity.strong,
      status: GlobalWeatherEventStatus.active,
      id: 'manual-global-${current.microsecondsSinceEpoch}',
    );
    _applyWeatherViabilityDamage(activeGlobalWeatherEvent!);
    _applyWeatherHouseDamage(activeGlobalWeatherEvent!);
    _applyWeatherStockLosses(activeGlobalWeatherEvent!);
    nextGlobalWeatherEvent = _newGlobalWeatherEvent(
      startsAt: activeGlobalWeatherEvent!.endsAt,
    );
    _createWeatherAlert(
      config,
      current,
      manual: true,
      startsAt: current,
      endsAt: activeGlobalWeatherEvent!.endsAt,
      globalWeatherEventId: activeGlobalWeatherEvent!.id,
    );
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
    DateTime? startsAt,
    DateTime? endsAt,
    String? globalWeatherEventId,
    String? announcementMessage,
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
      startsAt: startsAt ?? now.add(Duration(minutes: config.warningMinutes)),
      endsAt: endsAt ??
          now.add(
            Duration(minutes: config.warningMinutes + config.durationMinutes),
          ),
      manual: manual,
      globalWeatherEventId: globalWeatherEventId,
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
        message: announcementMessage ??
            'Alerte Tour : ${config.label} approche. Consulte le Kernel pour voir la demande de préparation.',
        sourceBuildingId: 'securityTower',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Alerte météo',
        concerned: 'Maison',
        summary:
            '${config.announcement}${requestedItem == null ? '' : ' Demande : $requestedAmount $requestedItem.'} Durée : ${config.durationMinutes} min.',
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
              ? '$label atténué. Préparation validée : ${alert.requestedAmount} ${alert.requestedItem ?? 'objet'}.'
              : '$label non préparé. Les Refuges concernés ont subi leur malus de production.',
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
      ..removeWhere((resource, amount) => amount <= 0 || resource == 'Eau');
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

  void deleteReports({Zone0MessageMailbox? mailbox}) {
    final before = reports.length;
    reports.removeWhere(
      (report) => mailbox == null || report.mailbox == mailbox,
    );
    if (reports.length != before) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  int _kernelMissionProgress(KernelMissionConfig mission) {
    return switch (mission.conditionType) {
      KernelMissionConditionType.fablabBuilt => isFablabBuilt ? 1 : 0,
      KernelMissionConditionType.ptibugCreated => pTibugs.isNotEmpty ? 1 : 0,
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
        'plaineNursery' => plaineNurseryLevel,
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
    _resolveEnergyCoreMilestones();
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

    final organicBonus = organicBonusForBiome(mission.biome);
    if (mission.type == ForageMissionType.harvest && organicBonus > 0) {
      rewards['Organique'] =
          ((rewards['Organique'] ?? 0) * (1 + organicBonus)).round();
    }
    _depleteBiomeWaste(
      biome: mission.biome,
      theoreticalHours: duration.theoreticalHours,
      completionRatio: rewardRatio,
      completedAt: completedAt,
    );
    final biomassBefore = biomassFor(mission.biome);
    final configuredBiomassCost = biomassMissionConsumptionFor(
      mission.intensity,
      mission.type,
    );
    final biomassCost = configuredBiomassCost <= 0
        ? 0
        : math.max(1, (configuredBiomassCost * rewardRatio).ceil());
    _depleteBiomeBiomass(
      biome: mission.biome,
      intensity: mission.intensity,
      missionType: mission.type,
      theoreticalHours: duration.theoreticalHours,
      completionRatio: rewardRatio,
      completedAt: completedAt,
    );
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
    final dataCells = _createDataCellsForMission(
      mission: mission,
      duration: duration,
      completedAt: completedAt,
    );
    if (dataCells.isNotEmpty) {
      pTibugDataCells.addAll(dataCells);
    }
    final localState = biomeSecurity[mission.biome];
    if (localState != null) {
      localState.lastMissionAt = completedAt;
      localState.lastDecayAt = completedAt;
      if (mission.type == ForageMissionType.research &&
          isTowerResearchUnlocked) {
        localState.researchProgress = math.min(
          100,
          localState.researchProgress +
              duration.theoreticalHours *
                  towerOperationsConfig.research.progressPerHour,
        );
        localState.lastResearchDecayAt = completedAt;
      }
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
          rest: rest,
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
      mission.type == ForageMissionType.research
          ? isTowerResearchUnlocked
              ? 'Recherche : aucune ressource naturelle extraite. Le savoir local progresse de ${duration.theoreticalHours * towerOperationsConfig.research.progressPerHour}%.'
              : 'Recherche : aucune ressource naturelle extraite. Une Tour de recherche est nécessaire pour comprendre les données de ce biome.'
          : 'Récolte : ressources naturelles prélevées.',
      'Vigueur : $biomassBefore% → ${math.max(0, biomassBefore - biomassCost)}% (-$biomassCost%).',
      if (emergencyReturn)
        'Retour d’urgence : le butin est calculé au temps écoulé, avec +5% de risque événement.',
      if (dataCells.isNotEmpty)
        '${dataCells.length} Cellule${dataCells.length > 1 ? 's' : ''} de données à analyser dans le Kernel.',
      ...memberStateLabels,
    ].join(' ');
    reports.add(
      PtipoteMissionReport(
        id: 'report-${completedAt.microsecondsSinceEpoch}',
        figurineName: mission.figurineName,
        biomeLabel: biome.label,
        durationLabel: duration.label,
        intensityLabel:
            '${mission.type == ForageMissionType.research ? 'Recherche · ' : 'Récolte · '}${intensity.label}',
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
        summary:
            '${mission.type == ForageMissionType.research ? 'Recherche' : 'Récolte'} : '
            '${rewards.isEmpty ? 'aucune ressource matérielle' : rewards.entries.map((entry) => '${entry.value} ${entry.key}').join(', ')}'
            '${dataCells.isEmpty ? '' : ' · ${dataCells.length} Cellule(s)'}'
            ' · Vigueur -$biomassCost%'
            '${incident == 'aucun' ? '' : ' · événement : $incident'}.',
      ),
    );
    mission.status = ForageMissionStatus.completed;
  }

  int wasteLevelFor(ForageBiome biome) {
    return biomeSecurity[biome]?.wasteLevel ??
        lisiereForageConfig.wasteLevelMax;
  }

  int biomassFor(ForageBiome biome) {
    final maximum = lisiereForageConfig.biomass.maximumPercent;
    return (biomeSecurity[biome]?.biomassPercent ?? maximum)
        .clamp(0, maximum)
        .toInt();
  }

  BiomassVisualStateConfig biomassVisualStateFor(ForageBiome biome) {
    final percent = biomassFor(biome);
    return lisiereForageConfig.biomass.visualStates
            .where((state) => state.contains(percent))
            .firstOrNull ??
        lisiereForageConfig.biomass.visualStates.last;
  }

  double _biomassMultiplierFor(int percent, List<BiomassTierConfig> tiers) =>
      tiers.where((tier) => tier.contains(percent)).firstOrNull?.multiplier ??
      1;

  double biomassResourceMultiplierFor(ForageBiome biome) =>
      _biomassMultiplierFor(
        biomassFor(biome),
        lisiereForageConfig.biomass.resourceYieldTiers,
      );

  double biomassPTibugMultiplierFor(ForageBiome biome) => _biomassMultiplierFor(
        biomassFor(biome),
        lisiereForageConfig.biomass.ptibugYieldTiers,
      );

  Map<String, int> biomassAdjustedNaturalRewards(
    ForageBiome biome,
    Map<String, int> rewards,
  ) {
    final multiplier = biomassResourceMultiplierFor(biome);
    const naturalResources = <String>{
      'Organique',
      'Minéral',
      'Déchets',
      'Mycélium',
    };
    return <String, int>{
      for (final entry in rewards.entries)
        entry.key: naturalResources.contains(entry.key)
            ? math.max(0, (entry.value * multiplier).round())
            : entry.value,
    };
  }

  int biomassMissionConsumption(ForageIntensity intensity) => math.max(
        0,
        lisiereForageConfig.biomass.missionConsumptionByIntensity[intensity] ??
            0,
      );

  int biomassMissionConsumptionFor(
    ForageIntensity intensity,
    ForageMissionType type, {
    int theoreticalHours = 1,
  }) {
    final base = biomassMissionConsumption(intensity);
    final multiplier =
        lisiereForageConfig.missionTypes[type]?.vigorMultiplier ?? 1;
    return math.max(
        0, (base * multiplier * math.max(0, theoreticalHours)).round());
  }

  Map<String, int> biomassRevitalizeCost(ForageBiome biome) {
    return <String, int>{
      'Dispositif de régénération': 1,
    };
  }

  Duration biomassRevitalizeCooldownRemaining(ForageBiome biome,
      {DateTime? now}) {
    final last = biomeSecurity[biome]?.lastBiomassRevitalizedAt;
    if (last == null) return Duration.zero;
    final cooldown = Duration(
        hours:
            math.max(0, lisiereForageConfig.biomass.revitalizeCooldownHours));
    final elapsed = (now ?? DateTime.now()).difference(last);
    return elapsed >= cooldown ? Duration.zero : cooldown - elapsed;
  }

  Zone0ActionResult revitalizeBiome(ForageBiome biome) {
    final state = biomeSecurity.putIfAbsent(
      biome,
      () => BiomeSecurityState.initial(biome),
    );
    final maximum = lisiereForageConfig.biomass.maximumPercent;
    if (state.biomassPercent >= maximum) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Biomasse de ce biome est déjà au maximum.',
      );
    }
    final cooldown = biomassRevitalizeCooldownRemaining(biome);
    if (cooldown > Duration.zero) {
      final hours = cooldown.inHours;
      final minutes = cooldown.inMinutes.remainder(60);
      return Zone0ActionResult(
        success: false,
        message:
            'Dispositif en recharge : ${hours}h ${minutes.toString().padLeft(2, '0')} min.',
      );
    }
    const device = 'Dispositif de régénération';
    if (resourceAmount(device) < 1 || removeResource(device, 1) <= 0) {
      return Zone0ActionResult(
        success: false,
        message: 'Un Dispositif de régénération est requis.',
      );
    }
    final gain = math.max(1, lisiereForageConfig.biomass.revitalizeGain);
    state.biomassPercent = math.min(maximum, state.biomassPercent + gain);
    state.lastBiomassRevitalizedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Biomasse de ${lisiereForageConfig.biomes[biome]!.label} : +$gain%.',
    );
  }

  double wasteMultiplierFor(ForageBiome biome) {
    final maximum = lisiereForageConfig.wasteLevelMax;
    if (maximum <= 0) return 0;
    final level = wasteLevelFor(biome).clamp(0, maximum);
    return (level * lisiereForageConfig.wasteMultiplierPerLevel)
        .clamp(0, 1.5)
        .toDouble();
  }

  double organicBonusForBiome(ForageBiome biome) {
    return wasteLevelFor(biome) <= 0
        ? lisiereForageConfig.organicBonusAtZeroWaste
        : 0;
  }

  int estimatedBiomeWasteReward({
    required ForageBiome biome,
    required int theoreticalHours,
    required double rewardMultiplier,
  }) {
    final baseReward = lisiereForageConfig.biomes[biome]?.wasteBaseGain ?? 0;
    return (baseReward *
            wasteMultiplierFor(biome) *
            theoreticalHours *
            rewardMultiplier)
        .floor();
  }

  void _depleteBiomeWaste({
    required ForageBiome biome,
    required int theoreticalHours,
    required double completionRatio,
    required DateTime completedAt,
  }) {
    final hoursPerLevel = lisiereForageConfig.wasteHoursPerLevelDepletion;
    if (hoursPerLevel <= 0) return;
    final levelLoss =
        (theoreticalHours * completionRatio / hoursPerLevel).floor();
    if (levelLoss <= 0) return;
    final state = biomeSecurity.putIfAbsent(
      biome,
      () => BiomeSecurityState.initial(biome),
    );
    state.wasteLevel = math.max(0, state.wasteLevel - levelLoss).toInt();
    state.lastWasteRegenerationAt = completedAt;
  }

  bool _regenerateBiomeWaste({
    required BiomeSecurityState state,
    required DateTime now,
  }) {
    final maximum = lisiereForageConfig.wasteLevelMax;
    if (state.wasteLevel >= maximum) return false;
    final hoursPerLevel =
        lisiereForageConfig.biomes[state.biome]?.wasteHoursPerLevelRegeneration;
    if (hoursPerLevel == null || hoursPerLevel <= 0) return false;

    final last = state.lastWasteRegenerationAt;
    if (last == null || now.isBefore(last)) {
      state.lastWasteRegenerationAt = now;
      return true;
    }
    final minutesPerLevel = math.max(1, (hoursPerLevel * 60).round());
    final gainedLevels = now.difference(last).inMinutes ~/ minutesPerLevel;
    if (gainedLevels <= 0) return false;

    state.wasteLevel = math.min(maximum, state.wasteLevel + gainedLevels);
    state.lastWasteRegenerationAt = state.wasteLevel >= maximum
        ? now
        : last.add(Duration(minutes: gainedLevels * minutesPerLevel));
    return true;
  }

  void _depleteBiomeBiomass({
    required ForageBiome biome,
    required ForageIntensity intensity,
    ForageMissionType missionType = ForageMissionType.harvest,
    required int theoreticalHours,
    required double completionRatio,
    required DateTime completedAt,
  }) {
    final base = biomassMissionConsumptionFor(
      intensity,
      missionType,
      theoreticalHours: theoreticalHours,
    );
    if (base <= 0) return;
    final consumed = math.max(1, (base * completionRatio).ceil());
    final state = biomeSecurity.putIfAbsent(
      biome,
      () => BiomeSecurityState.initial(biome),
    );
    state.biomassPercent = math.max(0, state.biomassPercent - consumed);
    state.lastBiomassRegenerationAt = completedAt;
  }

  bool _regenerateBiomeBiomass({
    required BiomeSecurityState state,
    required DateTime now,
  }) {
    final config = lisiereForageConfig.biomass;
    if (state.biomassPercent >= config.maximumPercent) return false;
    final last = state.lastBiomassRegenerationAt;
    if (last == null || now.isBefore(last)) {
      state.lastBiomassRegenerationAt = now;
      return true;
    }
    var cursor = last;
    var biomass = state.biomassPercent;
    final pTibugBiome = _ptibugBiomeForForageBiome(state.biome);
    final stabilizerBonus = _activePTibugEffect(
      'Régénération Vigueur %',
      biome: pTibugBiome,
    ).clamp(0, pTibugConfig.weather.stabilizerMaximumPercent);
    while (biomass < config.maximumPercent) {
      final multiplier = _biomassMultiplierFor(biomass, config.recoveryTiers);
      final minutes = math.max(
        1,
        (config.recoveryHoursPerPoint *
                multiplier *
                60 /
                (1 + stabilizerBonus / 100))
            .round(),
      );
      final next = cursor.add(Duration(minutes: minutes));
      if (next.isAfter(now)) break;
      biomass += 1;
      cursor = next;
    }
    if (biomass == state.biomassPercent) return false;
    state.biomassPercent = biomass;
    state.lastBiomassRegenerationAt =
        biomass >= config.maximumPercent ? now : cursor;
    return true;
  }

  /// Creates scientific discoveries once for a completed Lisière mission.
  /// The legacy four mission biomes are mapped to the closest P'TIBUG biome
  /// until all eight zones are directly explorable in the Lisière UI.
  List<PTibugDataCell> _createDataCellsForMission({
    required ForageMission mission,
    required ForageDurationConfig duration,
    required DateTime completedAt,
  }) {
    if (pTibugDataCells.any((cell) => cell.sourceMissionId == mission.id)) {
      return const <PTibugDataCell>[];
    }
    final biomeId = _ptibugBiomeForForageBiome(mission.biome);
    final biome = pTibugConfig.biomes[biomeId];
    if (biome == null) return const <PTibugDataCell>[];

    final weatherMultiplier = mission.type == ForageMissionType.research
        ? towerResearchWeatherMultiplierFor(mission.biome)
        : 1.0;
    final attempts = mission.type == ForageMissionType.research ? 5 : 2;
    final cells = <PTibugDataCell>[];
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      final chance = (towerOperationsConfig.research
                  .cellChanceFor(mission.type, attempt + 1) *
              weatherMultiplier *
              capsuleDiscoveryMultiplierFor(mission.biome))
          .round()
          .clamp(0, 100);
      if (_random.nextInt(100) >= chance) continue;
      final weights = Map<PTibugDataFamily, int>.from(biome.dataWeights);
      final toxineWeightBonus =
          _activePTibugEffect('Poids Toxine', biome: biomeId);
      if (toxineWeightBonus > 0) {
        weights[PTibugDataFamily.toxine] =
            (weights[PTibugDataFamily.toxine] ?? 0) + toxineWeightBonus;
      }
      if (biomeId == PTibugBiome.savaneTropicale && plaineNurseryLevel > 0) {
        weights[PTibugDataFamily.comportementInsectoide] =
            (weights[PTibugDataFamily.comportementInsectoide] ?? 0) +
                biome.nurseryInsectBehaviourWeight;
      }
      final dominant = _pickWeightedDataFamily(weights);
      final entries = <PTibugDataCellEntry>[];
      final targetValue = _pickDataCellValue(mission.type);
      for (var slot = 0; slot < 5; slot += 1) {
        final family = slot < 2 ? dominant : _pickWeightedDataFamily(weights);
        entries.add(
          PTibugDataCellEntry(
            family: family,
            quality: slot < targetValue - 5
                ? PTibugDataQuality.sought
                : PTibugDataQuality.common,
            slotIndex: slot,
          ),
        );
      }
      cells.add(
        PTibugDataCell(
          id: 'cell-${mission.id}-$attempt',
          displayName:
              'Cellule ${_ptibugDataFamilyLabel(dominant)} · ${biome.displayName}',
          sourceBiomeId: biomeId.name,
          sourceMissionId: mission.id,
          dominantFamily: dominant,
          isNeutralCell: false,
          entries: entries,
          createdAt: completedAt,
        ),
      );
    }
    return cells;
  }

  int _pickDataCellValue(ForageMissionType type) {
    final research = towerOperationsConfig.research;
    final valueNineChance = type == ForageMissionType.research
        ? research.researchValueNineChance
        : research.harvestValueNineChance;
    final valueSevenEightChance = type == ForageMissionType.research
        ? research.researchValueSevenEightChance
        : research.harvestValueSevenEightChance;
    if (_random.nextInt(100) < valueNineChance) return 9;
    if (_random.nextInt(100) < valueSevenEightChance) {
      return _random.nextBool() ? 7 : 8;
    }
    return _random.nextBool() ? 5 : 6;
  }

  List<PTibugDataCell> _createTowerResearchCells(
    TowerBiomeResearch research, {
    required DateTime completedAt,
  }) {
    final biomeId = _ptibugBiomeForForageBiome(research.biome);
    final biome = pTibugConfig.biomes[biomeId];
    if (biome == null) return const <PTibugDataCell>[];
    final cells = <PTibugDataCell>[];
    for (var attempt = 0; attempt < research.theoreticalHours; attempt += 1) {
      if (_random.nextInt(100) >=
          towerOperationsConfig.research.cellChancePerHour) continue;
      final weights = Map<PTibugDataFamily, int>.from(biome.dataWeights);
      final dominant = _pickWeightedDataFamily(weights);
      final targetValue = _pickDataCellValue(ForageMissionType.research);
      final entries = List<PTibugDataCellEntry>.generate(
        5,
        (slot) => PTibugDataCellEntry(
          family: slot < 2 ? dominant : _pickWeightedDataFamily(weights),
          quality: slot < targetValue - 5
              ? PTibugDataQuality.sought
              : PTibugDataQuality.common,
          slotIndex: slot,
        ),
      );
      cells.add(PTibugDataCell(
        id: 'tower-cell-${research.id}-$attempt',
        displayName:
            'Cellule ${_ptibugDataFamilyLabel(dominant)} · ${biome.displayName}',
        sourceBiomeId: biomeId.name,
        sourceMissionId: research.id,
        dominantFamily: dominant,
        entries: entries,
        createdAt: completedAt,
      ));
    }
    return cells;
  }

  PTibugBiome _ptibugBiomeForForageBiome(ForageBiome biome) => switch (biome) {
        ForageBiome.colline => PTibugBiome.hautsRefuges,
        ForageBiome.plaineRiche => PTibugBiome.savaneTropicale,
        ForageBiome.bassinMineral => PTibugBiome.semiDesertGarrigueTropicale,
        ForageBiome.sousBois => PTibugBiome.foretHumideRelictuelle,
      };

  PTibugDataFamily _pickWeightedDataFamily(
    Map<PTibugDataFamily, int> weights,
  ) {
    final positiveWeights = weights.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    if (positiveWeights.isEmpty) return PTibugDataFamily.organique;
    final total = positiveWeights.fold<int>(
      0,
      (totalWeight, entry) => totalWeight + entry.value,
    );
    var cursor = _random.nextInt(total);
    for (final entry in positiveWeights) {
      cursor -= entry.value;
      if (cursor < 0) return entry.key;
    }
    return positiveWeights.last.key;
  }

  PTibugDataQuality _pickWeightedDataQuality() {
    final weights = pTibugConfig.dataQualityWeights.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    final total = weights.fold<int>(
      0,
      (totalWeight, entry) => totalWeight + entry.value,
    );
    var cursor = _random.nextInt(math.max(1, total));
    for (final entry in weights) {
      cursor -= entry.value;
      if (cursor < 0) return entry.key;
    }
    return PTibugDataQuality.common;
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
    required int rest,
    required String moodLabel,
  }) {
    final fatigue = math.max(0, ptipoteStatsConfig.maxRest - rest);
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
    notes.add(
      'Énergie : $vitality/${ptipoteStatsConfig.maxVitality} · faim : $hunger/${ptipoteStatsConfig.baseHunger} · fatigue : $fatigue/${ptipoteStatsConfig.maxRest} · repos : $rest/${ptipoteStatsConfig.maxRest} · bonheur : $moodLabel.',
    );
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
    final sessionIndex = coBreedingSessions.indexWhere(
      (session) => session.ptipoteId == figurineId,
    );
    if (sessionIndex >= 0 &&
        level >= coBreedingConfig.levelEarlyDeparture &&
        !coBreedingSessions[sessionIndex].departurePending) {
      final updated = CoBreedingTimeService.markLevelCap(
        coBreedingSessions[sessionIndex],
        now: DateTime.now(),
      );
      coBreedingSessions[sessionIndex] = updated;
      final profile = ptipoteV2Profiles[figurineId];
      if (profile != null) {
        ptipoteV2Profiles[figurineId] = profile.copyWith(
          departurePending: true,
          departureReason: CoBreedingDepartureReason.levelCapReached.name,
          lifecycleStatus: PtipoteLifecycleStatus.departurePending,
        );
      }
      reports.add(
        PtipoteMissionReport.system(
          id: 'co-breeding-level-cap-${updated.sessionId}',
          message:
              '${profile?.displayName.isNotEmpty == true ? profile!.displayName : profile?.systemName ?? 'Ce P’TIPOTE'} a terminé sa croissance.',
          sourceBuildingId: 'house',
          mailbox: Zone0MessageMailbox.companions,
          subject: 'Co-élevage terminé',
          concerned: profile?.displayName ?? profile?.systemName ?? 'P’TIPOTE',
        ),
      );
    }
    // XP is granted only when a real activity resolves. Reusing this central
    // point makes every eligible activity worth one Symbiose credit, never one
    // credit per produced object or per UI refresh.
    if (xpGain > 0) recordPtipoteActivityCompleted(figurineId);
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
    if (!_loadedFromFirebase) return;
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
    if (!_loadedFromFirebase) return;
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
    if (!_loadedFromFirebase) return;
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde missions/vitalité', () {
      return _zone0Doc(user.uid).set(<String, dynamic>{
        'vitalityOverrides': vitalityOverrides,
        'hungerOverrides': hungerOverrides,
        'restOverrides': restOverrides,
        'xpOverrides': xpOverrides,
        'levelOverrides': levelOverrides,
        'wellRestedRewardedIds': wellRestedRewardedIds.toList(),
        'manualRestingIds': manualRestingIds.toList(),
        'waitingForBedIds': waitingForBedIds.toList(),
        'hatchedPtipoteIds': hatchedPtipoteIds.toList(),
        'ptipoteV2Profiles': ptipoteV2Profiles.map(
          (id, profile) => MapEntry(id, profile.toFirebase()),
        ),
        'coBreeding': <String, dynamic>{
          'unlocked': coBreedingUnlocked,
          'introMissionDismissed': coBreedingIntroMissionDismissed,
          'devMode': coBreedingDevMode,
          'lastSelectionAt': lastCoBreedingSelectionAt == null
              ? null
              : Timestamp.fromDate(lastCoBreedingSelectionAt!),
          'offer': coBreedingOffer?.toFirebase(),
          'envelopeOffers': coBreedingEnvelopeOffers.map(
            (id, offer) => MapEntry(id, offer.toFirebase()),
          ),
          'sessions': coBreedingSessions
              .map((session) => session.toFirebase())
              .toList(),
          'xpRewards':
              coBreedingXpRewards.map((reward) => reward.toFirebase()).toList(),
          'archive':
              coBreedingArchive.map((entry) => entry.toFirebase()).toList(),
          'completedCount': completedCoBreedingCount,
        },
        'autoPreferenceOverrides': autoPreferenceOverrides.map(
          (key, value) => MapEntry(key, value.name),
        ),
        'towerAssignedIds': towerAssignedIds.toList(),
        'towerMissions':
            towerMissions.map((mission) => mission.toFirebase()).toList(),
        'towerBiomeResearch': towerBiomeResearch
            .map((research) => research.toFirebase())
            .toList(),
        'workshopOrder': null,
        'workshopOrders':
            workshopOrders.map((order) => order.toFirebase()).toList(),
        'market': <String, dynamic>{
          'stock': marketStock.map((item) => item.toFirebase()).toList(),
          'requests': marketRequests.map((item) => item.toFirebase()).toList(),
          'requestLog':
              marketRequestLog.map((item) => item.toFirebase()).toList(),
          'nextSaleAt': marketNextSaleAt == null
              ? null
              : Timestamp.fromDate(marketNextSaleAt!),
          'nextRequestAt': marketNextRequestAt == null
              ? null
              : Timestamp.fromDate(marketNextRequestAt!),
          'lastWorkTickAt': marketLastWorkTickAt == null
              ? null
              : Timestamp.fromDate(marketLastWorkTickAt!),
          'lastXpTickAt': marketLastXpTickAt == null
              ? null
              : Timestamp.fromDate(marketLastXpTickAt!),
          'assignedAt': marketAssignedAt == null
              ? null
              : Timestamp.fromDate(marketAssignedAt!),
          'xpEarnedThisAssignment': marketXpEarnedThisAssignment,
          'bioPilesEarnedThisAssignment': marketBioPilesEarnedThisAssignment,
          'articlesSoldThisAssignment': marketArticlesSoldThisAssignment,
          'distributorsRepairedThisAssignment':
              marketDistributorsRepairedThisAssignment,
          'assignedPtipoteId': marketAssignedPtipoteId,
          'assignedPtipoteName': marketAssignedPtipoteName,
          'restockEnabledItems': marketRestockEnabledItems.toList(),
          'restockMinimums': marketRestockMinimums,
          'valueRemainder': marketValueRemainder,
          'bioBatteriesEarned': marketBioBatteriesEarned,
          'sourcierConfidence': sourcierConfidence,
          'firstFreeShopClaimed': firstFreeShopClaimed,
          'primaryShopSpecialization': primaryMarketShopSpecialization,
          'primaryShopChosen': primaryMarketShopChosen,
          'primaryShopLevel': primaryMarketShopLevel,
          'shopConstruction': marketShopConstructionOrder?.toFirebase(),
          'residentCommunityShopConstruction':
              residentCommunityShopConstructionOrder?.toFirebase(),
          'lastResidentCommunityShopConstructionAt':
              lastResidentCommunityShopConstructionAt == null
                  ? null
                  : Timestamp.fromDate(
                      lastResidentCommunityShopConstructionAt!),
          'activeLicenses': activeMarketLicenses.toList(),
          'shops': marketShops.map((item) => item.toFirebase()).toList(),
          'shopSlots':
              marketShopSlots.map((item) => item.toFirebase()).toList(),
          'restockRules':
              marketRestockRules.map((item) => item.toFirebase()).toList(),
          'shopSlotsMigrationCompleted': marketShopSlotsMigrationCompleted,
          'contracts':
              marketContracts.map((item) => item.toFirebase()).toList(),
          'distributor': marketDistributor.toFirebase(),
          'merchantAvailableUntil': merchantAvailableUntil == null
              ? null
              : Timestamp.fromDate(merchantAvailableUntil!),
          'merchantNextArrivalAt': merchantNextArrivalAt == null
              ? null
              : Timestamp.fromDate(merchantNextArrivalAt!),
          'merchantCallRequestedAt': merchantCallRequestedAt == null
              ? null
              : Timestamp.fromDate(merchantCallRequestedAt!),
          'merchantVisitsDayKey': merchantVisitsDayKey,
          'merchantVisitsToday': merchantVisitsToday,
          'merchantOffers':
              merchantOffers.map((item) => item.toFirebase()).toList(),
        },
        'biomeSecurity': biomeSecurity.map(
          (key, value) => MapEntry(key.name, value.toFirebase()),
        ),
        'lisiereTerritoryZones': lisiereTerritoryZones.map(
          (biome, zone) => MapEntry(biome.name, zone.toFirebase()),
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
          'bioPiles': bioPiles,
          'energyCorePatternDiscovered': energyCorePatternDiscovered,
          'energyCoreWarning600Shown': energyCoreWarning600Shown,
          'energyCoreWarning699Shown': energyCoreWarning699Shown,
          'storedEnergyCores': storedEnergyCores,
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
          'planDataInvestments': <String, Map<String, int>>{
            for (final entry in kernelPlanDataInvestments.entries)
              entry.key: <String, int>{
                for (final invested in entry.value.entries)
                  invested.key.name: invested.value,
              },
          },
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
        'bioGeneratorMovedToPlayerHouse': bioGeneratorMovedToPlayerHouse,
        'recycler': <String, dynamic>{
          'level': recyclerLevel,
          'wasteTank': recyclerWasteTank,
          'outputOrganic': recyclerOutputOrganic,
          'outputMineral': recyclerOutputMineral,
          'outputOther': recyclerOutputOther,
          'biologicalOrientationInstalled':
              recyclerBiologicalOrientationInstalled,
          'biologicalOrientationActive': recyclerBiologicalOrientationActive,
          'activeBatch': recyclerActiveBatch?.toFirebase(),
          'pendingWaste': pendingWaste,
          'cycleStartedAt': recyclerCycleStartedAt == null
              ? null
              : Timestamp.fromDate(recyclerCycleStartedAt!),
          'lastWasteGenerationAt': lastWasteGenerationAt == null
              ? null
              : Timestamp.fromDate(lastWasteGenerationAt!),
          'lastCampWasteCalculationAt': lastCampWasteCalculationAt == null
              ? null
              : Timestamp.fromDate(lastCampWasteCalculationAt!),
          'campWasteRemainder': campWasteRemainder,
          'dailyReports': campWasteDailyReports
              .map((report) => report.toFirebase())
              .toList(),
        },
        'ptibug': <String, dynamic>{
          'nurseryLevel': plaineNurseryLevel,
          'activePatterns':
              activePTibugPatterns.map((item) => item.name).toList(),
          'starterChoiceMade': starterPTibugChoiceMade,
          'creation': pTibugCreationOrder?.toFirebase(),
          'armatures':
              pTibugArmatures.map((item) => item.toFirebase()).toList(),
          'cultivationTanks':
              pTibugCultivationTanks.map((item) => item.toFirebase()).toList(),
          'cultivationOperations': pTibugCultivationOperations
              .map((item) => item.toFirebase())
              .toList(),
          'aspectMatrices':
              pTibugAspectMatrices.map((item) => item.toFirebase()).toList(),
          'aspectExtractionOrder': pTibugAspectExtractionOrder?.toFirebase(),
          'aspectExtractorLevel': aspectMatrixExtractorLevel,
          'firstCultivationTankGranted': firstCultivationTankGranted,
          'items': pTibugs.map((item) => item.toFirebase()).toList(),
          'soldArchive':
              soldPTibugArchive.map((item) => item.toFirebase()).toList(),
          'territoryBuildings': pTibugTerritoryBuildings.values
              .map((item) => item.toFirebase())
              .toList(),
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
          'sourcierPatternIds': sourcierPatternIds.toList(),
          'patternProgress': pTibugPatternProgress.values
              .map((item) => item.toFirebase())
              .toList(),
          'moduleInstances':
              pTibugModuleInstances.map((item) => item.toFirebase()).toList(),
          'moduleCraftOrders':
              pTibugModuleCraftOrders.map((item) => item.toFirebase()).toList(),
          'moduleCapacityLevel': pTibugModuleCapacityLevel,
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
          'activeGlobalEvent': activeGlobalWeatherEvent?.toFirebase(),
          'nextGlobalEvent': nextGlobalWeatherEvent?.toFirebase(),
          'consecutiveAdverseEvents': globalWeatherConsecutiveAdverseEvents,
          'consecutiveSevereEvents': globalWeatherConsecutiveSevereEvents,
        },
        'missions': missions.map((mission) => mission.toFirebase()).toList(),
        'reports': reports.map((report) => report.toFirebase()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> saveBuildingsToFirebase() async {
    if (!_loadedFromFirebase) return;
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
            'weatherModuleInstalled': towerWeatherModuleInstalled,
            'researchModuleInstalled': towerResearchModuleInstalled,
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
            'protectedBatteryChestLevel': protectedBatteryChestLevel,
            'isVisible': true,
          },
          'housing': <String, dynamic>{
            'units': housingUnits,
            'capacity': housingCapacity,
            'thanks': communityConstructionThanks?.toFirebase(),
            'residents':
                residents.map((resident) => resident.toFirebase()).toList(),
            'functionalHouses':
                residentHouses.map((house) => house.toFirebase()).toList(),
            'arrivalCandidates': residentArrivalCandidates
                .map((candidate) => candidate.toFirebase())
                .toList(),
            'residentVisions':
                residentVisions.map((vision) => vision.toFirebase()).toList(),
            'householdRepairJobs':
                householdRepairJobs.map((job) => job.toFirebase()).toList(),
            'lastResidentArrivalResolutionAt':
                lastResidentArrivalResolutionAt == null
                    ? null
                    : Timestamp.fromDate(lastResidentArrivalResolutionAt!),
            'residentAutonomyGraceUntil': residentAutonomyGraceUntil == null
                ? null
                : Timestamp.fromDate(residentAutonomyGraceUntil!),
            'communityRoleAssignments': communityRoleAssignments
                .map((assignment) => assignment.toFirebase())
                .toList(),
            'communityProductionBatches': communityProductionBatches
                .map((batch) => batch.toFirebase())
                .toList(),
            'residentEconomicTransactions': residentEconomicTransactions
                .map((transaction) => transaction.toFirebase())
                .toList(),
            'economicSettlementBatches': economicSettlementBatches
                .map((batch) => batch.toFirebase())
                .toList(),
            'residentUncoveredNeeds': residentUncoveredNeeds
                .map((need) => need.toFirebase())
                .toList(),
            'residentPopulationMigrationCompleted':
                residentPopulationMigrationCompleted,
            'residentNeedsMigrationCompleted': residentNeedsMigrationCompleted,
            'residentNeedsGraceUntil': residentNeedsGraceUntil == null
                ? null
                : Timestamp.fromDate(residentNeedsGraceUntil!),
            'lastResidentNeedsResolutionDayKey':
                lastResidentNeedsResolutionDayKey,
            'resolvedResidentWeatherEventIds':
                resolvedResidentWeatherEventIds.toList(),
            'residentPassionMigrationCompleted':
                residentPassionMigrationCompleted,
            'lastCommunityRoleResolutionAt':
                lastCommunityRoleResolutionAt == null
                    ? null
                    : Timestamp.fromDate(lastCommunityRoleResolutionAt!),
            'residentEconomyMigrationCompleted':
                residentEconomyMigrationCompleted,
            'lastResidentEconomyResolvedAt':
                lastResidentEconomyResolvedAt == null
                    ? null
                    : Timestamp.fromDate(lastResidentEconomyResolvedAt!),
            'lastEconomicSettlementDayKey': lastEconomicSettlementDayKey,
            'lastDomesticEnergyDistributionAt':
                lastDomesticEnergyDistributionAt == null
                    ? null
                    : Timestamp.fromDate(lastDomesticEnergyDistributionAt!),
          },
          'viability': buildingViabilities.map(
            (key, value) => MapEntry(key, value.toFirebase()),
          ),
          'communityProjects': communityProjects.values
              .map((project) => project.toFirebase())
              .toList(),
          'weatherStockLoss': <String, dynamic>{
            'resolvedEventIds': resolvedWeatherStockLossEventIds.toList(),
            'lastIncident': lastWeatherStockIncident?.toFirebase(),
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

  double _readDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
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
          .timeout(const Duration(seconds: 20));
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
  ) {
    // Toutes les écritures partagent la même file : une sauvegarde plus
    // ancienne ne peut pas terminer après une sauvegarde plus récente.
    final queuedSync = _firebaseWriteQueue.then((_) async {
      _firebaseSyncCount += 1;
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
        _firebaseSyncCount -= 1;
        isFirebaseSyncing = _firebaseSyncCount > 0;
        notifyListeners();
      }
    });
    _firebaseWriteQueue = queuedSync;
    return queuedSync;
  }

  /// Sauvegarde les trois fragments de Zone 0 avant une mise en arrière-plan.
  Future<void> saveAllToFirebase() async {
    if (!_loadedFromFirebase) return;
    await saveInventoryToFirebase();
    await saveBuildingsToFirebase();
    await saveRuntimeToFirebase();
  }

  /// Attend les écritures déjà demandées, utile lors de la fermeture de l'app.
  Future<void> flushFirebaseWrites() => _firebaseWriteQueue;
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
  Zone0InventoryStack({
    String? id,
    required this.resource,
    required int amount,
    List<String>? sourceItemIds,
  })  : id = id ?? 'stack-${DateTime.now().microsecondsSinceEpoch}',
        amount = math.max(0, amount),
        sourceItemIds = sourceItemIds ?? <String>[];

  final String id;
  final String resource;
  int amount;

  /// Identifiants d'objets de Nurserie déposés au Marché (Capsules ou
  /// Matrices). Ils gardent leur identité visuelle tout en restant un stack.
  final List<String> sourceItemIds;

  factory Zone0InventoryStack.fromFirebase(Map<dynamic, dynamic> data) =>
      Zone0InventoryStack(
        id: data['id'] as String?,
        resource: '${data['resource'] ?? ''}',
        amount: Zone0GameState.instance._readInt(data['amount']),
        sourceItemIds: (data['sourceItemIds'] as List? ?? const <dynamic>[])
            .map((item) => '$item')
            .toList(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'resource': resource,
        'amount': amount,
        'sourceItemIds': sourceItemIds,
      };
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

enum MarketRequestStatus {
  noted,
  ready,
  waitingCustomer,
  completed,
  cancelled,
  expired,
}

enum MarketRequestResponder { player, ptipote, distributor }

extension MarketRequestResponderLabel on MarketRequestResponder {
  String get label => switch (this) {
        MarketRequestResponder.player => 'Joueur',
        MarketRequestResponder.ptipote => 'P’TIPOTE',
        MarketRequestResponder.distributor => 'Distributeur',
      };
}

enum MarketContractStatus {
  offered,
  accepted,
  completed,
  failed,
  rejected,
  expiredUnaccepted,
}

enum MarketDistributorType { resources, food, general }

extension MarketDistributorTypeLabel on MarketDistributorType {
  String get label => switch (this) {
        MarketDistributorType.resources => 'Ressources',
        MarketDistributorType.food => 'Alimentaire',
        MarketDistributorType.general => 'Généraliste',
      };

  String get stockDescription => switch (this) {
        MarketDistributorType.resources =>
          'Organique, Minéral, Déchets et Mycélium.',
        MarketDistributorType.food => 'Aliments et consommables préparés.',
        MarketDistributorType.general =>
          'Matériaux transformés et produits de l’Atelier.',
      };
}

class MarketDistributorState {
  MarketDistributorState();
  MarketDistributorType type = MarketDistributorType.resources;
  bool isBuilt = false;
  int level = 0;
  int energy = 0;
  bool isBroken = false;
  DateTime? lastEnergyTickAt;
  DateTime? constructionStartedAt;
  DateTime? constructionEndsAt;
  DateTime? repairEndsAt;
  String? repairStartedBy;
  DateTime? upgradeEndsAt;
  int? upgradeTargetLevel;
  final Map<String, int> constructionDeposits = <String, int>{};
  final List<Zone0InventoryStack> stock = <Zone0InventoryStack>[];

  bool get isOperational => isBuilt && !isBroken && repairEndsAt == null;
  bool accepts(String resource) => switch (type) {
        MarketDistributorType.resources => const <String>{
            'Organique',
            'Minéral',
            'Déchets',
            'Mycélium'
          }.contains(resource),
        MarketDistributorType.food => craftConfig.recipes.any(
            (recipe) => recipe.resultItem == resource && recipe.isConsumable,
          ),
        MarketDistributorType.general => !const <String>{
              'Organique',
              'Minéral',
              'Déchets',
              'Mycélium'
            }.contains(resource) &&
            !craftConfig.recipes.any(
              (recipe) => recipe.resultItem == resource && recipe.isConsumable,
            ),
      };

  factory MarketDistributorState.fromFirebase(Map<dynamic, dynamic> data) {
    final result = MarketDistributorState()
      ..type = ForageMission._enumByName(
        MarketDistributorType.values,
        '${data['type'] ?? ''}',
        MarketDistributorType.resources,
      )
      ..isBuilt = data['isBuilt'] == true
      ..level = Zone0GameState.instance._readInt(data['level'])
      ..energy = Zone0GameState.instance._readInt(data['energy'])
      ..isBroken = data['isBroken'] == true
      ..lastEnergyTickAt =
          Zone0GameState.instance._readDate(data['lastEnergyTickAt'])
      ..constructionStartedAt =
          Zone0GameState.instance._readDate(data['constructionStartedAt'])
      ..constructionEndsAt =
          Zone0GameState.instance._readDate(data['constructionEndsAt'])
      ..repairEndsAt = Zone0GameState.instance._readDate(data['repairEndsAt'])
      ..repairStartedBy = data['repairStartedBy'] as String?
      ..upgradeEndsAt = Zone0GameState.instance._readDate(data['upgradeEndsAt'])
      ..upgradeTargetLevel = data['upgradeTargetLevel'] as int?;
    final deposits = data['constructionDeposits'];
    if (deposits is Map) {
      for (final entry in deposits.entries) {
        result.constructionDeposits['${entry.key}'] =
            Zone0GameState.instance._readInt(entry.value);
      }
    }
    result.stock.addAll(
        (data['stock'] as List? ?? const <dynamic>[]).whereType<Map>().map(
              (item) => Zone0InventoryStack.fromFirebase(item),
            ));
    return result;
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'isBuilt': isBuilt,
        'type': type.name,
        'level': level,
        'energy': energy,
        'isBroken': isBroken,
        'lastEnergyTickAt': lastEnergyTickAt == null
            ? null
            : Timestamp.fromDate(lastEnergyTickAt!),
        'constructionStartedAt': constructionStartedAt == null
            ? null
            : Timestamp.fromDate(constructionStartedAt!),
        'constructionEndsAt': constructionEndsAt == null
            ? null
            : Timestamp.fromDate(constructionEndsAt!),
        'repairEndsAt':
            repairEndsAt == null ? null : Timestamp.fromDate(repairEndsAt!),
        'repairStartedBy': repairStartedBy,
        'upgradeEndsAt':
            upgradeEndsAt == null ? null : Timestamp.fromDate(upgradeEndsAt!),
        'upgradeTargetLevel': upgradeTargetLevel,
        'constructionDeposits': constructionDeposits,
        'stock': stock.map((item) => item.toFirebase()).toList(),
      };
}

class MarketShopConstructionOrder {
  MarketShopConstructionOrder({
    required this.id,
    required this.specialization,
    required this.isPrimary,
    Map<String, int>? requirements,
    int? requiredBioBatteries,
    this.targetShopId,
    this.targetLevel,
    this.emergencyPink = false,
    Map<String, int>? deposits,
    this.depositedBioBatteries = 0,
    this.startedAt,
    this.endsAt,
  })  : requirements = requirements ??
            Map<String, int>.from(marketConfig.shopConstructionCost),
        requiredBioBatteries =
            requiredBioBatteries ?? marketConfig.shopConstructionBioBatteries,
        deposits = deposits ?? <String, int>{};

  final String id;
  final String specialization;
  final bool isPrimary;
  final Map<String, int> requirements;
  final int requiredBioBatteries;
  final String? targetShopId;
  final int? targetLevel;
  final bool emergencyPink;
  final Map<String, int> deposits;
  int depositedBioBatteries;
  DateTime? startedAt;
  DateTime? endsAt;

  bool get isInProgress => startedAt != null && endsAt != null;

  factory MarketShopConstructionOrder.fromFirebase(
          Map<dynamic, dynamic> data) =>
      MarketShopConstructionOrder(
        id: '${data['id'] ?? ''}',
        specialization: '${data['specialization'] ?? 'restaurant'}',
        isPrimary: data['isPrimary'] == true,
        requirements: Map<String, int>.fromEntries(
          (data['requirements'] as Map? ?? marketConfig.shopConstructionCost)
              .entries
              .map((entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value))),
        ),
        requiredBioBatteries: Zone0GameState.instance._readInt(
            data['requiredBioBatteries'],
            fallback: marketConfig.shopConstructionBioBatteries),
        targetShopId: data['targetShopId']?.toString(),
        targetLevel: data['targetLevel'] == null
            ? null
            : Zone0GameState.instance._readInt(data['targetLevel']),
        emergencyPink: data['emergencyPink'] == true,
        deposits: Map<String, int>.fromEntries(
          (data['deposits'] as Map? ?? const <dynamic, dynamic>{}).entries.map(
              (entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value))),
        ),
        depositedBioBatteries:
            Zone0GameState.instance._readInt(data['depositedBioBatteries']),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']),
        endsAt: Zone0GameState.instance._readDate(data['endsAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'specialization': specialization,
        'isPrimary': isPrimary,
        'requirements': requirements,
        'requiredBioBatteries': requiredBioBatteries,
        'targetShopId': targetShopId,
        'targetLevel': targetLevel,
        'emergencyPink': emergencyPink,
        'deposits': deposits,
        'depositedBioBatteries': depositedBioBatteries,
        'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
        'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
      };
}

enum MarketShopSlotStatus {
  locked,
  vacant,
  playerOccupied,
  residentOccupied,
  pendingResidentClaim,
  reserved,
  unavailable,
}

enum MarketShopOwnershipType { player, residentCommunity }

/// Emplacement commercial persistant. Il est volontairement séparé du
/// magasin afin qu'une boutique supprimée ou migrée ne recrée jamais un slot.
class MarketShopSlot {
  MarketShopSlot({
    required this.slotId,
    required this.marketLevelRequired,
    required this.slotIndex,
    this.status = MarketShopSlotStatus.locked,
    this.shopId,
    this.reservedByResidentId,
    this.vacantSince,
    this.claimCandidateResidentId,
    this.claimWarningStartedAt,
    this.claimFinalizationAt,
  });

  final String slotId;
  final int marketLevelRequired;
  final int slotIndex;
  MarketShopSlotStatus status;
  String? shopId;
  String? reservedByResidentId;
  DateTime? vacantSince;
  String? claimCandidateResidentId;
  DateTime? claimWarningStartedAt;
  DateTime? claimFinalizationAt;

  factory MarketShopSlot.fromFirebase(Map<dynamic, dynamic> data) =>
      MarketShopSlot(
        slotId: '${data['slotId'] ?? ''}',
        marketLevelRequired: Zone0GameState.instance
            ._readInt(data['marketLevelRequired'], fallback: 1),
        slotIndex: Zone0GameState.instance._readInt(data['slotIndex']),
        status: ForageMission._enumByName(
          MarketShopSlotStatus.values,
          '${data['status'] ?? ''}',
          MarketShopSlotStatus.locked,
        ),
        shopId: data['shopId']?.toString(),
        reservedByResidentId: data['reservedByResidentId']?.toString(),
        vacantSince: Zone0GameState.instance._readDate(data['vacantSince']),
        claimCandidateResidentId: data['claimCandidateResidentId']?.toString(),
        claimWarningStartedAt:
            Zone0GameState.instance._readDate(data['claimWarningStartedAt']),
        claimFinalizationAt:
            Zone0GameState.instance._readDate(data['claimFinalizationAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'slotId': slotId,
        'marketLevelRequired': marketLevelRequired,
        'slotIndex': slotIndex,
        'status': status.name,
        'shopId': shopId,
        'reservedByResidentId': reservedByResidentId,
        'vacantSince':
            vacantSince == null ? null : Timestamp.fromDate(vacantSince!),
        'claimCandidateResidentId': claimCandidateResidentId,
        'claimWarningStartedAt': claimWarningStartedAt == null
            ? null
            : Timestamp.fromDate(claimWarningStartedAt!),
        'claimFinalizationAt': claimFinalizationAt == null
            ? null
            : Timestamp.fromDate(claimFinalizationAt!),
      };
}

class MarketRestockRule {
  MarketRestockRule({
    required this.ruleId,
    required this.shopId,
    required this.itemDefinitionId,
    this.enabled = false,
    this.reserveMinimum = 0,
    this.targetStock = 0,
    this.maximumTransfer = 1,
    this.priority = 0,
    this.lastStatus = 'inactive',
  });

  final String ruleId;
  final String shopId;
  final String itemDefinitionId;
  bool enabled;
  int reserveMinimum;
  int targetStock;
  int maximumTransfer;
  int priority;
  String lastStatus;

  factory MarketRestockRule.fromFirebase(Map<dynamic, dynamic> data) =>
      MarketRestockRule(
        ruleId: '${data['ruleId'] ?? ''}',
        shopId: '${data['shopId'] ?? ''}',
        itemDefinitionId: '${data['itemDefinitionId'] ?? ''}',
        enabled: data['enabled'] == true,
        reserveMinimum:
            Zone0GameState.instance._readInt(data['reserveMinimum']),
        targetStock: Zone0GameState.instance._readInt(data['targetStock']),
        maximumTransfer: Zone0GameState.instance
            ._readInt(data['maximumTransfer'], fallback: 1),
        priority: Zone0GameState.instance._readInt(data['priority']),
        lastStatus: '${data['lastStatus'] ?? 'inactive'}',
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'ruleId': ruleId,
        'shopId': shopId,
        'itemDefinitionId': itemDefinitionId,
        'enabled': enabled,
        'reserveMinimum': reserveMinimum,
        'targetStock': targetStock,
        'maximumTransfer': maximumTransfer,
        'priority': priority,
        'lastStatus': lastStatus,
      };
}

class MarketCoverage {
  const MarketCoverage({
    required this.openNeeds,
    required this.coveredCategories,
    required this.availableShopIds,
  });

  final int openNeeds;
  final Set<String> coveredCategories;
  final Set<String> availableShopIds;
}

/// Lecture centralisée de la couverture commerciale : les widgets ne doivent
/// ni choisir un magasin ni déduire une catégorie eux-mêmes.
class MarketCoverageService {
  const MarketCoverageService._();

  static MarketCoverage calculate(Zone0GameState state) {
    final shops = <MarketShop>[
      if (state.primaryMarketShopChosen)
        MarketShop(
          id: Zone0GameState.primaryMarketShopId,
          specialization: state.primaryMarketShopSpecialization,
          level: state.primaryMarketShopLevel,
          isPrimary: true,
        ),
      ...state.marketShops.where((shop) => !shop.legacyExtraSlot),
    ];
    return MarketCoverage(
      openNeeds: state.residentUncoveredNeeds
          .where((need) => need.resolvedAt == null)
          .length,
      coveredCategories: shops.map((shop) => shop.specialization).toSet(),
      availableShopIds: shops.map((shop) => shop.id).toSet(),
    );
  }
}

class MarketInformationPointService {
  const MarketInformationPointService._();

  static bool isActive(Zone0GameState state) =>
      state.isMarketInformationPointUnlocked &&
      state.marketAssignedPtipoteId != null;

  static List<MarketShop> eligibleShops(Zone0GameState state) => state
      .marketShops
      .where(
          (shop) => shop.informationPointBonusEligible && !shop.legacyExtraSlot)
      .toList(growable: false);
}

class MarketShop {
  MarketShop({
    required this.id,
    required this.specialization,
    this.level = 1,
    List<Zone0InventoryStack>? stock,
    this.distributor,
    this.isPrimary = false,
    this.slotId,
    this.ownershipType = MarketShopOwnershipType.player,
    this.ownerResidentId,
    this.managerResidentId,
    this.shopPileBalance = 0,
    this.serviceCapacity = 0,
    this.ownershipStartedAt,
    this.ownershipLocked = false,
    this.informationPointBonusEligible = true,
    this.legacyExtraSlot = false,
    this.emergencyPink = false,
    this.lastCommunityCounterSaleAt,
  }) : stock = stock ?? <Zone0InventoryStack>[];
  final String id;
  final String specialization;
  int level;
  final List<Zone0InventoryStack> stock;
  MarketDistributorState? distributor;
  final bool isPrimary;
  String? slotId;
  MarketShopOwnershipType ownershipType;
  String? ownerResidentId;
  String? managerResidentId;
  int shopPileBalance;
  int serviceCapacity;
  DateTime? ownershipStartedAt;
  bool ownershipLocked;
  bool informationPointBonusEligible;
  bool legacyExtraSlot;
  bool emergencyPink;
  DateTime? lastCommunityCounterSaleAt;

  bool accepts(String resource) => switch (specialization) {
        'restaurant' => craftConfig.recipes.any(
            (recipe) => recipe.resultItem == resource && recipe.isConsumable,
          ),
        'home' || 'ameublement' => const <String>{
              'Ventilation Termite',
              'Chloro-canaux',
              'Installation filtrante',
              'Lumière solaire',
              'Cartouche de filtration',
              'Kit de réparation domestique',
            }.contains(resource) ||
            resource.contains('Meuble'),
        'equipment' => craftConfig.recipes.any(
            (recipe) =>
                recipe.resultItem == resource &&
                !recipe.isConsumable &&
                !resource.contains('Meuble') &&
                !resource.contains('Ventilation') &&
                !resource.contains('Lumière') &&
                !resource.contains('Cartouche') &&
                !resource.contains('Chloro-canaux') &&
                !resource.contains('Installation filtrante') &&
                !resource.contains('Kit de réparation'),
          ),
        'ptibug' => resource.startsWith('P’TIBUG ') ||
            resource.startsWith('Capsule P’TIBUG ') ||
            resource == 'Matrice P’TIBUG' ||
            resource.startsWith('Matrice '),
        // Le Grossiste est une spécialisation technique : il ne génère pas
        // de demandes habitantes et sert pour l'instant au Sourcier.
        'wholesale' => const <String>{
            'Organique',
            'Minéral',
            'Mycélium',
          }.contains(resource),
        // Compatibilité de lecture des anciennes sauvegardes : ce type ne
        // peut plus être choisi, mais son stock reste utilisable.
        'general' => true,
        _ => false,
      };

  int get stockSlots => level >= 2 ? 6 : 3;
  int get distributorSlots => level >= 2 ? 2 : 1;

  factory MarketShop.fromFirebase(Map<dynamic, dynamic> data) => MarketShop(
        id: '${data['id'] ?? ''}',
        specialization: '${data['specialization'] ?? 'general'}',
        level: Zone0GameState.instance._readInt(data['level'], fallback: 1),
        stock: (data['stock'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(Zone0InventoryStack.fromFirebase)
            .toList(),
        distributor: data['distributor'] is Map
            ? MarketDistributorState.fromFirebase(data['distributor'] as Map)
            : null,
        isPrimary: data['isPrimary'] == true,
        slotId: data['slotId']?.toString(),
        ownershipType: ForageMission._enumByName(
          MarketShopOwnershipType.values,
          '${data['ownershipType'] ?? ''}',
          data['ownerResidentId'] == null
              ? MarketShopOwnershipType.player
              : MarketShopOwnershipType.residentCommunity,
        ),
        ownerResidentId: data['ownerResidentId']?.toString(),
        managerResidentId: data['managerResidentId']?.toString(),
        shopPileBalance:
            Zone0GameState.instance._readInt(data['shopPileBalance']),
        serviceCapacity: Zone0GameState.instance._readInt(
            data['serviceCapacity'],
            fallback: marketConfig.residentShopServiceCapacity),
        ownershipStartedAt:
            Zone0GameState.instance._readDate(data['ownershipStartedAt']),
        ownershipLocked: data['ownershipLocked'] == true,
        informationPointBonusEligible:
            data['informationPointBonusEligible'] != false,
        legacyExtraSlot: data['legacyExtraSlot'] == true,
        emergencyPink: data['emergencyPink'] == true,
        lastCommunityCounterSaleAt: Zone0GameState.instance
            ._readDate(data['lastCommunityCounterSaleAt']),
      );
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'specialization': specialization,
        'level': level,
        'stock': stock.map((item) => item.toFirebase()).toList(),
        'distributor': distributor?.toFirebase(),
        'isPrimary': isPrimary,
        'slotId': slotId,
        'ownershipType': ownershipType.name,
        'ownerResidentId': ownerResidentId,
        'managerResidentId': managerResidentId,
        'shopPileBalance': shopPileBalance,
        'serviceCapacity': serviceCapacity,
        'ownershipStartedAt': ownershipStartedAt == null
            ? null
            : Timestamp.fromDate(ownershipStartedAt!),
        'ownershipLocked': ownershipLocked,
        'informationPointBonusEligible': informationPointBonusEligible,
        'legacyExtraSlot': legacyExtraSlot,
        'emergencyPink': emergencyPink,
        'lastCommunityCounterSaleAt': lastCommunityCounterSaleAt == null
            ? null
            : Timestamp.fromDate(lastCommunityCounterSaleAt!),
      };
}

class MarketSourcierContract {
  MarketSourcierContract({
    required this.contractId,
    required this.marketLevelRequired,
    required this.category,
    required this.requestedItems,
    required this.rewardBioBatteries,
    required this.confidenceReward,
    required this.confidencePenalty,
    required this.offeredAt,
    required this.expiresAt,
    this.status = MarketContractStatus.offered,
    this.acceptedAt,
    this.deliveredAt,
    this.assignedLicense,
    this.autoDeliverAllowed = true,
  });
  final String contractId;
  final int marketLevelRequired;
  final String category;
  final Map<String, int> requestedItems;
  int rewardBioBatteries;
  final int confidenceReward;
  final int confidencePenalty;
  final DateTime offeredAt;
  final DateTime expiresAt;
  MarketContractStatus status;
  DateTime? acceptedAt;
  DateTime? deliveredAt;
  final String? assignedLicense;
  final bool autoDeliverAllowed;
  factory MarketSourcierContract.fromFirebase(Map<dynamic, dynamic> data) =>
      MarketSourcierContract(
        contractId: '${data['contractId'] ?? ''}',
        marketLevelRequired: Zone0GameState.instance
            ._readInt(data['marketLevelRequired'], fallback: 1),
        category: '${data['category'] ?? 'materials'}',
        requestedItems:
            (data['requestedItems'] as Map? ?? const <dynamic, dynamic>{}).map(
          (key, value) =>
              MapEntry('$key', Zone0GameState.instance._readInt(value)),
        ),
        rewardBioBatteries: Zone0GameState.instance._readInt(
          data['rewardBioPiles'],
          fallback: () {
            final saved =
                Zone0GameState.instance._readInt(data['rewardBioBatteries']);
            // Une version de transition a multiplié les contrats en cours
            // par 100. Ces seules valeurs sont ramenées à leur montant
            // original ; les nouveaux contrats ne passent jamais ici.
            return saved >= 100 && saved % 100 == 0 ? saved ~/ 100 : saved;
          }(),
        ),
        confidenceReward:
            Zone0GameState.instance._readInt(data['confidenceReward']),
        confidencePenalty:
            Zone0GameState.instance._readInt(data['confidencePenalty']),
        offeredAt: Zone0GameState.instance._readDate(data['offeredAt']) ??
            DateTime.now(),
        expiresAt: Zone0GameState.instance._readDate(data['expiresAt']) ??
            DateTime.now(),
        status: ForageMission._enumByName(MarketContractStatus.values,
            '${data['status'] ?? ''}', MarketContractStatus.offered),
        acceptedAt: Zone0GameState.instance._readDate(data['acceptedAt']),
        deliveredAt: Zone0GameState.instance._readDate(data['deliveredAt']),
        assignedLicense: data['assignedLicense'] as String?,
        autoDeliverAllowed: data['autoDeliverAllowed'] != false,
      );
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'contractId': contractId,
        'source': 'sourcier',
        'marketLevelRequired': marketLevelRequired,
        'category': category,
        'requestedItems': requestedItems,
        'rewardBioBatteries': rewardBioBatteries,
        'confidenceReward': confidenceReward,
        'confidencePenalty': confidencePenalty,
        'offeredAt': Timestamp.fromDate(offeredAt),
        'acceptedAt':
            acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': status.name,
        'assignedLicense': assignedLicense,
        'autoDeliverAllowed': autoDeliverAllowed,
        'deliveredAt':
            deliveredAt == null ? null : Timestamp.fromDate(deliveredAt!),
      };
}

class MarketCustomerRequest {
  MarketCustomerRequest({
    required this.id,
    required this.requestedItemId,
    required this.requestedQuantity,
    required this.rewardBioPiles,
    required this.rewardWellbeing,
    required this.createdAt,
    required this.customerReturnTime,
    required this.status,
    DateTime? distributorEligibleAt,
    this.shopId = Zone0GameState.primaryMarketShopId,
    this.customerName,
    this.weatherType,
  }) : distributorEligibleAt = distributorEligibleAt ?? createdAt;

  factory MarketCustomerRequest.fromFirebase(
    Map<dynamic, dynamic> data,
  ) =>
      MarketCustomerRequest(
        id: '${data['id'] ?? ''}',
        requestedItemId: '${data['requestedItemId'] ?? ''}',
        requestedQuantity: Zone0GameState.instance._readInt(
          data['requestedQuantity'],
        ),
        rewardBioPiles: Zone0GameState.instance._readInt(
          data['rewardBioPiles'],
          fallback:
              Zone0GameState.instance._readInt(data['rewardBioBattery']) * 100,
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
        customerName: data['customerName'] as String?,
        weatherType: data['weatherType'] as String?,
        distributorEligibleAt: Zone0GameState.instance._readDate(
          data['distributorEligibleAt'],
        ),
        shopId: '${data['shopId'] ?? Zone0GameState.primaryMarketShopId}',
      );

  final String id;
  final String requestedItemId;
  final int requestedQuantity;
  final int rewardBioPiles;
  int get rewardBioBattery => rewardBioPiles ~/ 100;
  final int rewardWellbeing;
  final DateTime createdAt;
  DateTime customerReturnTime;
  MarketRequestStatus status;
  final String? customerName;
  final String? weatherType;
  final DateTime distributorEligibleAt;
  final String shopId;

  bool get isOpen =>
      status == MarketRequestStatus.noted ||
      status == MarketRequestStatus.ready ||
      status == MarketRequestStatus.waitingCustomer;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'requestedItemId': requestedItemId,
        'requestedQuantity': requestedQuantity,
        // Keep the old field for a safe read by previous app versions.
        'rewardBioBattery': rewardBioBattery,
        'rewardBioPiles': rewardBioPiles,
        'rewardWellbeing': rewardWellbeing,
        'createdAt': Timestamp.fromDate(createdAt),
        'customerReturnTime': Timestamp.fromDate(customerReturnTime),
        'status': status.name,
        'customerName': customerName,
        'weatherType': weatherType,
        'distributorEligibleAt': Timestamp.fromDate(distributorEligibleAt),
        'shopId': shopId,
      };
}

class MarketRequestLogEntry {
  MarketRequestLogEntry({
    required this.requestId,
    required this.createdAt,
    required this.deadline,
    required this.requestedItemId,
    required this.requestedQuantity,
    required this.customerName,
    required this.status,
    this.resolvedAt,
    this.rewardBioBatteries = 0,
    this.responder,
    this.responderDisplayName,
  });

  factory MarketRequestLogEntry.fromRequest(MarketCustomerRequest request) =>
      MarketRequestLogEntry(
        requestId: request.id,
        createdAt: request.createdAt,
        deadline: request.customerReturnTime,
        requestedItemId: request.requestedItemId,
        requestedQuantity: request.requestedQuantity,
        customerName: request.customerName,
        status: request.status,
      );

  factory MarketRequestLogEntry.fromFirebase(Map<dynamic, dynamic> data) =>
      MarketRequestLogEntry(
        requestId: '${data['requestId'] ?? ''}',
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        deadline: Zone0GameState.instance._readDate(data['deadline']) ??
            DateTime.now(),
        requestedItemId: '${data['requestedItemId'] ?? ''}',
        requestedQuantity:
            Zone0GameState.instance._readInt(data['requestedQuantity']),
        customerName: data['customerName'] as String?,
        status: ForageMission._enumByName(MarketRequestStatus.values,
            '${data['status'] ?? ''}', MarketRequestStatus.noted),
        resolvedAt: Zone0GameState.instance._readDate(data['resolvedAt']),
        rewardBioBatteries: Zone0GameState.instance._readInt(
          data['rewardBioPiles'],
          fallback:
              Zone0GameState.instance._readInt(data['rewardBioBatteries']) *
                  100,
        ),
        responder: data['responder'] == null
            ? null
            : ForageMission._enumByName(
                MarketRequestResponder.values,
                '${data['responder']}',
                MarketRequestResponder.player,
              ),
        responderDisplayName: data['responderDisplayName'] as String?,
      );

  final String requestId;
  final DateTime createdAt;
  final DateTime deadline;
  final String requestedItemId;
  final int requestedQuantity;
  final String? customerName;
  MarketRequestStatus status;
  DateTime? resolvedAt;

  /// Nom historique conservé pour ne pas casser les anciennes sauvegardes :
  /// la valeur est désormais exprimée en bio-piles.
  int rewardBioBatteries;
  MarketRequestResponder? responder;
  String? responderDisplayName;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'requestId': requestId,
        'createdAt': Timestamp.fromDate(createdAt),
        'deadline': Timestamp.fromDate(deadline),
        'requestedItemId': requestedItemId,
        'requestedQuantity': requestedQuantity,
        'customerName': customerName,
        'status': status.name,
        'resolvedAt':
            resolvedAt == null ? null : Timestamp.fromDate(resolvedAt!),
        'rewardBioBatteries': rewardBioBatteries ~/ 100,
        'rewardBioPiles': rewardBioBatteries,
        'responder': responder?.name,
        'responderDisplayName': responderDisplayName,
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
    this.depositedBioBatteries = 0,
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
      depositedBioBatteries:
          Zone0GameState.instance._readInt(data['depositedBioBatteries']),
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
  int depositedBioBatteries;
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
    depositedBioBatteries = 0;
    startedAt = null;
    endsAt = null;
    completedAt = null;
    state = ConstructionProjectState.available;
  }

  void refreshState({bool extraReady = true}) {
    if (isInProgress || state == ConstructionProjectState.built) return;
    if (depositedMaterials.isEmpty) {
      state = ConstructionProjectState.available;
    } else if (isReady && extraReady) {
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
    depositedBioBatteries = 0;
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
        'depositedBioBatteries': depositedBioBatteries,
        'constructionDurationSeconds': constructionDuration.inSeconds,
        'state': state.name,
        'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
        'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'notificationCreated': notificationCreated,
      };
}

enum StructuralProtectionType { ventilationTermite, chloroCanaux, filtration }

class BuildingViabilityState {
  BuildingViabilityState({
    required this.buildingId,
    required this.current,
    required this.maximum,
    this.lastViabilityUpdateAt,
    this.lastDamageEventId,
    this.viabilityWarningShown = false,
    this.restartRequired = false,
    List<StructuralProtectionType>? installedStructuralProtections,
    Map<String, int>? structuralConsumables,
  })  : installedStructuralProtections =
            installedStructuralProtections ?? <StructuralProtectionType>[],
        structuralConsumables = structuralConsumables ?? <String, int>{};

  factory BuildingViabilityState.fresh(
    String buildingId, {
    required int maximum,
    required int initial,
  }) =>
      BuildingViabilityState(
        buildingId: buildingId,
        current: initial.clamp(0, maximum),
        maximum: maximum,
      );

  factory BuildingViabilityState.fromFirebase(Map<dynamic, dynamic> data) {
    final maximum = Zone0GameState.instance
        ._readInt(
          data['maxViability'],
          fallback: 100,
        )
        .clamp(1, 1000);
    return BuildingViabilityState(
      buildingId: '${data['buildingId'] ?? ''}',
      current: Zone0GameState.instance
          ._readInt(
            data['currentViability'],
            fallback: maximum,
          )
          .clamp(0, maximum),
      maximum: maximum,
      lastViabilityUpdateAt: Zone0GameState.instance._readDate(
        data['lastViabilityUpdateAt'],
      ),
      lastDamageEventId: data['lastDamageEventId'] as String?,
      viabilityWarningShown: data['viabilityWarningShown'] == true,
      restartRequired: data['restartRequired'] == true,
      installedStructuralProtections:
          (data['installedStructuralProtections'] as List? ?? const [])
              .map(
                (value) => ForageMission._enumByName(
                  StructuralProtectionType.values,
                  '$value',
                  StructuralProtectionType.ventilationTermite,
                ),
              )
              .toList(),
      structuralConsumables:
          (data['structuralConsumables'] as Map? ?? const <dynamic, dynamic>{})
              .map((key, value) => MapEntry(
                    '$key',
                    Zone0GameState.instance._readInt(value),
                  )),
    );
  }

  final String buildingId;
  int current;
  int maximum;
  DateTime? lastViabilityUpdateAt;
  String? lastDamageEventId;
  bool viabilityWarningShown;
  bool restartRequired;
  final List<StructuralProtectionType> installedStructuralProtections;
  final Map<String, int> structuralConsumables;

  bool get isDisabled => current <= 0 || restartRequired;
  bool isDegraded(int threshold) => !isDisabled && current < threshold;

  void restoreToMinimum(int amount) {
    current = amount.clamp(1, maximum);
    restartRequired = false;
    viabilityWarningShown = current < maximum;
    lastViabilityUpdateAt = DateTime.now();
  }

  void restore(int amount) {
    current = (current + amount).clamp(0, maximum);
    if (current > 0) restartRequired = false;
    lastViabilityUpdateAt = DateTime.now();
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'buildingId': buildingId,
        'currentViability': current,
        'maxViability': maximum,
        'lastViabilityUpdateAt': lastViabilityUpdateAt == null
            ? null
            : Timestamp.fromDate(lastViabilityUpdateAt!),
        'lastDamageEventId': lastDamageEventId,
        'isDisabledByViability': isDisabled,
        'viabilityWarningShown': viabilityWarningShown,
        'restartRequired': restartRequired,
        'installedStructuralProtections':
            installedStructuralProtections.map((item) => item.name).toList(),
        'structuralConsumables': structuralConsumables,
      };
}

enum ResidentStatus { active, awaitingHousing, arriving, inactive, archived }

enum ResidentNutritionStatus { nourri, partiellementNourri, nonNourri }

enum ResidentPassion {
  cooking,
  crafting,
  trading,
  livingObservation,
  watching,
}

enum CommunityRoleType {
  kitchenCook,
  fablabMaker,
  marketCounter,
  lisiereObserver,
  securityWatch,
  weatherWatch,
}

enum CommunityRoleStatus {
  active,
  paused,
  unavailable,
  awaitingBuilding,
  awaitingResources,
  archived,
}

class CommunityRoleAssignment {
  CommunityRoleAssignment({
    required this.id,
    required this.residentId,
    required this.passion,
    required this.roleType,
    required this.buildingId,
    required this.slotId,
    required this.startedAt,
    this.status = CommunityRoleStatus.active,
    this.pausedAt,
    this.lastResolvedAt,
    this.coverageCapacity = 0,
    this.dailyOutput = 0,
    this.outputDayKey = '',
    this.efficiencyRemainder = 0,
    this.productionDefinitionId,
    this.previousAssignmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? startedAt,
        updatedAt = updatedAt ?? startedAt;

  final String id;
  final String residentId;
  final ResidentPassion passion;
  final CommunityRoleType roleType;
  final String buildingId;
  final String slotId;
  CommunityRoleStatus status;
  final DateTime startedAt;
  DateTime? pausedAt;
  DateTime? lastResolvedAt;
  int coverageCapacity;
  int dailyOutput;
  String outputDayKey;
  int efficiencyRemainder;
  String? productionDefinitionId;
  String? previousAssignmentId;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isActive => status == CommunityRoleStatus.active;

  factory CommunityRoleAssignment.fromFirebase(Map<dynamic, dynamic> data) =>
      CommunityRoleAssignment(
        id: '${data['assignmentId'] ?? ''}',
        residentId: '${data['residentId'] ?? ''}',
        passion: ForageMission._enumByName(
          ResidentPassion.values,
          '${data['passionId'] ?? ''}',
          ResidentPassion.cooking,
        ),
        roleType: ForageMission._enumByName(
          CommunityRoleType.values,
          '${data['roleType'] ?? ''}',
          CommunityRoleType.kitchenCook,
        ),
        buildingId: '${data['buildingId'] ?? ''}',
        slotId: '${data['slotId'] ?? ''}',
        status: ForageMission._enumByName(
          CommunityRoleStatus.values,
          '${data['status'] ?? ''}',
          CommunityRoleStatus.awaitingBuilding,
        ),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        pausedAt: Zone0GameState.instance._readDate(data['pausedAt']),
        lastResolvedAt:
            Zone0GameState.instance._readDate(data['lastResolvedAt']),
        coverageCapacity:
            Zone0GameState.instance._readInt(data['coverageCapacity']),
        dailyOutput: Zone0GameState.instance._readInt(data['dailyOutput']),
        outputDayKey: '${data['outputDayKey'] ?? ''}',
        efficiencyRemainder:
            Zone0GameState.instance._readInt(data['efficiencyRemainder']),
        productionDefinitionId: data['productionDefinitionId'] as String?,
        previousAssignmentId: data['previousAssignmentId'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'assignmentId': id,
        'residentId': residentId,
        'passionId': passion.name,
        'roleType': roleType.name,
        'buildingId': buildingId,
        'slotId': slotId,
        'status': status.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'pausedAt': pausedAt == null ? null : Timestamp.fromDate(pausedAt!),
        'lastResolvedAt':
            lastResolvedAt == null ? null : Timestamp.fromDate(lastResolvedAt!),
        'coverageCapacity': coverageCapacity,
        'dailyOutput': dailyOutput,
        'outputDayKey': outputDayKey,
        'efficiencyRemainder': efficiencyRemainder,
        'productionDefinitionId': productionDefinitionId,
        'previousAssignmentId': previousAssignmentId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

enum ResidentEconomicTransactionType {
  householdEnergyProduction,
  householdEnergyDistribution,
  residentPurchase,
  residentSale,
  communityProductionPayment,
  merchantPayment,
  producerPayment,
  supplierPayment,
  playerSaleToResident,
  householdInstallationPurchase,
  refund,
  migrationAdjustment,
}

class _ResidentPaymentParts {
  const _ResidentPaymentParts(
      this.producer, this.supplier, this.merchant, this.player);
  final int producer;
  final int supplier;
  final int merchant;
  final int player;
}

enum ResidentEconomicTransactionStatus {
  pending,
  completed,
  cancelled,
  failed,
  archived,
}

class SupplierContribution {
  SupplierContribution({
    required this.id,
    this.residentId,
    required this.sourceType,
    required this.itemDefinitionId,
    required this.quantity,
    required this.contributionWeight,
    required this.createdAt,
  });

  final String id;
  final String? residentId;
  final String sourceType;
  final String itemDefinitionId;
  final int quantity;
  final int contributionWeight;
  final DateTime createdAt;

  factory SupplierContribution.fromFirebase(Map<dynamic, dynamic> data) =>
      SupplierContribution(
        id: '${data['contributionId'] ?? ''}',
        residentId: data['residentId'] as String?,
        sourceType: '${data['sourceType'] ?? 'legacyUnknown'}',
        itemDefinitionId: '${data['itemDefinitionId'] ?? ''}',
        quantity: Zone0GameState.instance._readInt(data['quantity']),
        contributionWeight:
            Zone0GameState.instance._readInt(data['contributionWeight']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'contributionId': id,
        'residentId': residentId,
        'sourceType': sourceType,
        'itemDefinitionId': itemDefinitionId,
        'quantity': quantity,
        'contributionWeight': contributionWeight,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

class CommunityProductionBatch {
  CommunityProductionBatch({
    required this.id,
    required this.itemDefinitionId,
    required this.outputQuantity,
    int? remainingQuantity,
    this.producerResidentId,
    List<SupplierContribution>? supplierContributions,
    required this.buildingId,
    Map<String, int>? inputSnapshot,
    this.unitCostPiles,
    this.status = ResidentEconomicTransactionStatus.completed,
    required this.producedAt,
    DateTime? updatedAt,
  })  : remainingQuantity = remainingQuantity ?? outputQuantity,
        supplierContributions =
            supplierContributions ?? <SupplierContribution>[],
        inputSnapshot = inputSnapshot ?? <String, int>{},
        updatedAt = updatedAt ?? producedAt;

  final String id;
  final String itemDefinitionId;
  final int outputQuantity;
  int remainingQuantity;
  final String? producerResidentId;
  final List<SupplierContribution> supplierContributions;
  final String buildingId;
  final Map<String, int> inputSnapshot;
  final int? unitCostPiles;
  ResidentEconomicTransactionStatus status;
  final DateTime producedAt;
  DateTime updatedAt;

  bool get isAvailable =>
      status == ResidentEconomicTransactionStatus.completed &&
      remainingQuantity > 0;

  factory CommunityProductionBatch.fromFirebase(Map<dynamic, dynamic> data) =>
      CommunityProductionBatch(
        id: '${data['batchId'] ?? ''}',
        itemDefinitionId: '${data['outputItemDefinitionId'] ?? ''}',
        outputQuantity:
            Zone0GameState.instance._readInt(data['outputQuantity']),
        remainingQuantity:
            Zone0GameState.instance._readInt(data['remainingQuantity']),
        producerResidentId: data['producerResidentId'] as String?,
        supplierContributions:
            (data['supplierContributions'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(SupplierContribution.fromFirebase)
                .toList(),
        buildingId: '${data['buildingId'] ?? ''}',
        inputSnapshot: Map<String, int>.fromEntries(
          (data['inputSnapshot'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value))),
        ),
        unitCostPiles: data['unitCostPiles'] == null
            ? null
            : Zone0GameState.instance._readInt(data['unitCostPiles']),
        status: ForageMission._enumByName(
          ResidentEconomicTransactionStatus.values,
          '${data['status'] ?? ''}',
          ResidentEconomicTransactionStatus.completed,
        ),
        producedAt: Zone0GameState.instance._readDate(data['producedAt']) ??
            DateTime.now(),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'batchId': id,
        'outputItemDefinitionId': itemDefinitionId,
        'outputQuantity': outputQuantity,
        'remainingQuantity': remainingQuantity,
        'producerResidentId': producerResidentId,
        'supplierContributions':
            supplierContributions.map((item) => item.toFirebase()).toList(),
        'buildingId': buildingId,
        'inputSnapshot': inputSnapshot,
        'unitCostPiles': unitCostPiles,
        'status': status.name,
        'producedAt': Timestamp.fromDate(producedAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

class ResidentEconomicTransaction {
  ResidentEconomicTransaction({
    required this.id,
    required this.type,
    this.buyerResidentId,
    this.sellerResidentId,
    this.householdId,
    this.buildingId,
    this.shopId,
    this.itemDefinitionId,
    this.quantity = 1,
    this.grossAmountPiles = 0,
    this.merchantSharePiles = 0,
    this.producerSharePiles = 0,
    this.supplierSharePiles = 0,
    this.playerSharePiles = 0,
    this.otherSharePiles = 0,
    this.sourceNeedId,
    this.sourceProductionId,
    this.sourceRequestId,
    List<String>? participantResidentIds,
    this.status = ResidentEconomicTransactionStatus.pending,
    required this.createdAt,
    this.completedAt,
    this.cancelledAt,
    this.settlementBatchId,
    required this.idempotencyKey,
  }) : participantResidentIds = participantResidentIds ?? <String>[];

  final String id;
  final ResidentEconomicTransactionType type;
  final String? buyerResidentId;
  final String? sellerResidentId;
  final String? householdId;
  final String? buildingId;
  final String? shopId;
  final String? itemDefinitionId;
  final int quantity;
  final int grossAmountPiles;
  final int merchantSharePiles;
  final int producerSharePiles;
  final int supplierSharePiles;
  final int playerSharePiles;
  final int otherSharePiles;
  final String? sourceNeedId;
  final String? sourceProductionId;
  final String? sourceRequestId;
  final List<String> participantResidentIds;
  ResidentEconomicTransactionStatus status;
  final DateTime createdAt;
  DateTime? completedAt;
  DateTime? cancelledAt;
  String? settlementBatchId;
  final String idempotencyKey;

  factory ResidentEconomicTransaction.fromFirebase(
          Map<dynamic, dynamic> data) =>
      ResidentEconomicTransaction(
        id: '${data['transactionId'] ?? ''}',
        type: ForageMission._enumByName(
          ResidentEconomicTransactionType.values,
          '${data['transactionType'] ?? ''}',
          ResidentEconomicTransactionType.migrationAdjustment,
        ),
        buyerResidentId: data['buyerResidentId'] as String?,
        sellerResidentId: data['sellerResidentId'] as String?,
        householdId: data['householdId'] as String?,
        buildingId: data['buildingId'] as String?,
        shopId: data['shopId'] as String?,
        itemDefinitionId: data['itemDefinitionId'] as String?,
        quantity:
            Zone0GameState.instance._readInt(data['quantity'], fallback: 1),
        grossAmountPiles:
            Zone0GameState.instance._readInt(data['grossAmountPiles']),
        merchantSharePiles:
            Zone0GameState.instance._readInt(data['merchantSharePiles']),
        producerSharePiles:
            Zone0GameState.instance._readInt(data['producerSharePiles']),
        supplierSharePiles:
            Zone0GameState.instance._readInt(data['supplierSharePiles']),
        playerSharePiles:
            Zone0GameState.instance._readInt(data['playerSharePiles']),
        otherSharePiles:
            Zone0GameState.instance._readInt(data['otherSharePiles']),
        sourceNeedId: data['sourceNeedId'] as String?,
        sourceProductionId: data['sourceProductionId'] as String?,
        sourceRequestId: data['sourceRequestId'] as String?,
        participantResidentIds:
            (data['participantResidentIds'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        status: ForageMission._enumByName(
          ResidentEconomicTransactionStatus.values,
          '${data['status'] ?? ''}',
          ResidentEconomicTransactionStatus.pending,
        ),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
        cancelledAt: Zone0GameState.instance._readDate(data['cancelledAt']),
        settlementBatchId: data['settlementBatchId'] as String?,
        idempotencyKey: '${data['idempotencyKey'] ?? ''}',
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'transactionId': id,
        'transactionType': type.name,
        'buyerResidentId': buyerResidentId,
        'sellerResidentId': sellerResidentId,
        'householdId': householdId,
        'buildingId': buildingId,
        'shopId': shopId,
        'itemDefinitionId': itemDefinitionId,
        'quantity': quantity,
        'grossAmountPiles': grossAmountPiles,
        'merchantSharePiles': merchantSharePiles,
        'producerSharePiles': producerSharePiles,
        'supplierSharePiles': supplierSharePiles,
        'playerSharePiles': playerSharePiles,
        'otherSharePiles': otherSharePiles,
        'sourceNeedId': sourceNeedId,
        'sourceProductionId': sourceProductionId,
        'sourceRequestId': sourceRequestId,
        'participantResidentIds': participantResidentIds,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'cancelledAt':
            cancelledAt == null ? null : Timestamp.fromDate(cancelledAt!),
        'settlementBatchId': settlementBatchId,
        'idempotencyKey': idempotencyKey,
      };
}

class EconomicSettlementBatch {
  EconomicSettlementBatch({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    List<String>? transactionIds,
    this.totalGrossPiles = 0,
    this.totalMerchantPiles = 0,
    this.totalProducerPiles = 0,
    this.totalSupplierPiles = 0,
    this.totalPlayerPiles = 0,
    this.status = ResidentEconomicTransactionStatus.completed,
    required this.createdAt,
    this.completedAt,
    required this.idempotencyKey,
  }) : transactionIds = transactionIds ?? <String>[];

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<String> transactionIds;
  final int totalGrossPiles;
  final int totalMerchantPiles;
  final int totalProducerPiles;
  final int totalSupplierPiles;
  final int totalPlayerPiles;
  ResidentEconomicTransactionStatus status;
  final DateTime createdAt;
  DateTime? completedAt;
  final String idempotencyKey;

  factory EconomicSettlementBatch.fromFirebase(Map<dynamic, dynamic> data) =>
      EconomicSettlementBatch(
        id: '${data['settlementBatchId'] ?? ''}',
        periodStart: Zone0GameState.instance._readDate(data['periodStart']) ??
            DateTime.now(),
        periodEnd: Zone0GameState.instance._readDate(data['periodEnd']) ??
            DateTime.now(),
        transactionIds: (data['transactionIds'] as List? ?? const <dynamic>[])
            .map((item) => '$item')
            .toList(),
        totalGrossPiles:
            Zone0GameState.instance._readInt(data['totalGrossPiles']),
        totalMerchantPiles:
            Zone0GameState.instance._readInt(data['totalMerchantPiles']),
        totalProducerPiles:
            Zone0GameState.instance._readInt(data['totalProducerPiles']),
        totalSupplierPiles:
            Zone0GameState.instance._readInt(data['totalSupplierPiles']),
        totalPlayerPiles:
            Zone0GameState.instance._readInt(data['totalPlayerPiles']),
        status: ForageMission._enumByName(
          ResidentEconomicTransactionStatus.values,
          '${data['status'] ?? ''}',
          ResidentEconomicTransactionStatus.completed,
        ),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
        idempotencyKey: '${data['idempotencyKey'] ?? ''}',
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'settlementBatchId': id,
        'periodStart': Timestamp.fromDate(periodStart),
        'periodEnd': Timestamp.fromDate(periodEnd),
        'transactionIds': transactionIds,
        'totalGrossPiles': totalGrossPiles,
        'totalMerchantPiles': totalMerchantPiles,
        'totalProducerPiles': totalProducerPiles,
        'totalSupplierPiles': totalSupplierPiles,
        'totalPlayerPiles': totalPlayerPiles,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'idempotencyKey': idempotencyKey,
      };
}

enum ResidentUncoveredNeedReason {
  noStock,
  noProducer,
  noMerchant,
  insufficientFunds,
  buildingUnavailable,
  recipeLocked,
  noCompatibleShop,
  inventoryFull,
}

class ResidentUncoveredNeed {
  ResidentUncoveredNeed({
    required this.id,
    required this.residentId,
    required this.itemDefinitionId,
    required this.category,
    required this.quantity,
    required this.budgetPiles,
    required this.reason,
    required this.urgency,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String residentId;
  final String itemDefinitionId;
  final String category;
  final int quantity;
  final int budgetPiles;
  ResidentUncoveredNeedReason reason;
  final int urgency;
  final DateTime createdAt;
  DateTime? resolvedAt;

  factory ResidentUncoveredNeed.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentUncoveredNeed(
        id: '${data['needId'] ?? ''}',
        residentId: '${data['residentId'] ?? ''}',
        itemDefinitionId: '${data['itemDefinitionId'] ?? ''}',
        category: '${data['category'] ?? ''}',
        quantity:
            Zone0GameState.instance._readInt(data['quantity'], fallback: 1),
        budgetPiles: Zone0GameState.instance._readInt(data['budgetPiles']),
        reason: ForageMission._enumByName(
          ResidentUncoveredNeedReason.values,
          '${data['reason'] ?? ''}',
          ResidentUncoveredNeedReason.noStock,
        ),
        urgency: Zone0GameState.instance._readInt(data['urgency'], fallback: 1),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        resolvedAt: Zone0GameState.instance._readDate(data['resolvedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'needId': id,
        'residentId': residentId,
        'itemDefinitionId': itemDefinitionId,
        'category': category,
        'quantity': quantity,
        'budgetPiles': budgetPiles,
        'reason': reason.name,
        'urgency': urgency,
        'createdAt': Timestamp.fromDate(createdAt),
        'resolvedAt':
            resolvedAt == null ? null : Timestamp.fromDate(resolvedAt!),
      };
}

/// Read-only gateway used by the future Market demand layer. The economic
/// resolver owns creation and resolution; UI and future systems never invent
/// parallel customer needs from raw materials.
class ResidentUncoveredNeedsService {
  const ResidentUncoveredNeedsService._();

  static List<ResidentUncoveredNeed> activeFor(Zone0GameState state) =>
      state.residentUncoveredNeeds
          .where((need) => need.resolvedAt == null)
          .toList(growable: false);

  static Map<ResidentUncoveredNeedReason, int> countByReason(
      Zone0GameState state) {
    final counts = <ResidentUncoveredNeedReason, int>{};
    for (final need in activeFor(state)) {
      counts.update(need.reason, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

class CommunityCoverage {
  const CommunityCoverage({
    required this.activeRoles,
    required this.pausedRoles,
    required this.freeSlots,
    required this.foodCoverageCapacity,
    required this.foodNeedsRemaining,
    required this.securityProducedToday,
    required this.observationProducedToday,
    required this.commerceAvailable,
  });

  final int activeRoles;
  final int pausedRoles;
  final int freeSlots;
  final int foodCoverageCapacity;
  final int foodNeedsRemaining;
  final int securityProducedToday;
  final int observationProducedToday;
  final int commerceAvailable;
}

class CommunityCoverageService {
  const CommunityCoverageService._();

  static CommunityCoverage calculate(Zone0GameState state) {
    final active = state.activeCommunityRoles.toList();
    final paused = state.communityRoleAssignments
        .where((assignment) =>
            assignment.status != CommunityRoleStatus.active &&
            assignment.status != CommunityRoleStatus.archived)
        .length;
    final totalSlots = CommunityRoleType.values.fold<int>(
      0,
      (sum, role) => sum + state.communityRoleSlotCount(role),
    );
    // The two Tower roles share the same physical resident slots.
    final sharedTowerSlots =
        state.communityRoleSlotCount(CommunityRoleType.securityWatch);
    final uniqueSlots = totalSlots - sharedTowerSlots;
    final foodRoles = active
        .where((role) => role.roleType == CommunityRoleType.kitchenCook)
        .toList();
    final foodCapacity = foodRoles.fold<int>(
      0,
      (sum, role) => sum + communityRolesConfig.cookingCoveragePerCycle,
    );
    final needsRemaining = state.residents
        .where((resident) => resident.isActive)
        .fold<int>(
            0, (sum, resident) => sum + resident.needsState.mealsMissing);
    return CommunityCoverage(
      activeRoles: active.length,
      pausedRoles: paused,
      freeSlots: math.max(0, uniqueSlots - active.length),
      foodCoverageCapacity: foodCapacity,
      foodNeedsRemaining: needsRemaining,
      securityProducedToday: active
          .where((role) => role.roleType == CommunityRoleType.securityWatch)
          .fold<int>(0, (sum, role) => sum + role.dailyOutput),
      observationProducedToday: active
          .where((role) => role.roleType == CommunityRoleType.lisiereObserver)
          .fold<int>(0, (sum, role) => sum + role.dailyOutput),
      commerceAvailable: active
          .where((role) => role.roleType == CommunityRoleType.marketCounter)
          .length,
    );
  }
}

enum ResidentDesireType { sweetTooth, fashion, comfort, tools }

enum ResidentInteriorProfile { simple, technique, esthete }

enum ResidentOwnedItemStatus {
  stored,
  active,
  consumed,
  broken,
  discarded,
  installedInHouse,
}

/// A finished good owned by a resident. Raw production materials deliberately
/// cannot enter this model: validation stays in [giveResidentFinishedItem].
class ResidentOwnedItem {
  ResidentOwnedItem({
    required this.id,
    required this.itemDefinitionId,
    required this.category,
    required this.quantity,
    required this.acquiredAt,
    this.currentDurability,
    this.maxDurability,
    this.lastUsedAt,
    this.equippedOrActive = false,
    this.sourceTransactionId,
    this.status = ResidentOwnedItemStatus.stored,
  });

  final String id;
  final String itemDefinitionId;
  final String category;
  int quantity;
  int? currentDurability;
  int? maxDurability;
  DateTime acquiredAt;
  DateTime? lastUsedAt;
  bool equippedOrActive;
  String? sourceTransactionId;
  ResidentOwnedItemStatus status;

  bool get isUsable =>
      quantity > 0 &&
      status != ResidentOwnedItemStatus.broken &&
      status != ResidentOwnedItemStatus.consumed &&
      status != ResidentOwnedItemStatus.discarded &&
      (currentDurability == null || currentDurability! > 0);

  factory ResidentOwnedItem.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentOwnedItem(
        id: '${data['ownedItemId'] ?? ''}',
        itemDefinitionId: '${data['itemDefinitionId'] ?? ''}',
        category: '${data['category'] ?? 'other'}',
        quantity:
            Zone0GameState.instance._readInt(data['quantity'], fallback: 1),
        currentDurability: data['currentDurability'] == null
            ? null
            : Zone0GameState.instance._readInt(data['currentDurability']),
        maxDurability: data['maxDurability'] == null
            ? null
            : Zone0GameState.instance._readInt(data['maxDurability']),
        acquiredAt: Zone0GameState.instance._readDate(data['acquiredAt']) ??
            DateTime.now(),
        lastUsedAt: Zone0GameState.instance._readDate(data['lastUsedAt']),
        equippedOrActive: data['equippedOrActive'] == true,
        sourceTransactionId: data['sourceTransactionId'] as String?,
        status: ForageMission._enumByName(
          ResidentOwnedItemStatus.values,
          '${data['status'] ?? ''}',
          ResidentOwnedItemStatus.stored,
        ),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'ownedItemId': id,
        'itemDefinitionId': itemDefinitionId,
        'category': category,
        'quantity': quantity,
        'currentDurability': currentDurability,
        'maxDurability': maxDurability,
        'acquiredAt': Timestamp.fromDate(acquiredAt),
        'lastUsedAt':
            lastUsedAt == null ? null : Timestamp.fromDate(lastUsedAt!),
        'equippedOrActive': equippedOrActive,
        'sourceTransactionId': sourceTransactionId,
        'status': status.name,
      };
}

/// Per-resident, explainable state. It is persisted separately from the
/// aggregate happiness so a day/event never has to be inferred from widgets.
class ResidentNeedsState {
  ResidentNeedsState({
    required this.currentDayKey,
    required this.mealsRequired,
    this.mealsConsumed = 0,
    this.nutritionStatus = ResidentNutritionStatus.nourri,
    List<String>? requiredWeatherProtectionTypes,
    List<String>? missingWeatherProtectionTypes,
    this.activeDesireId,
    this.desireSatisfied = false,
    this.interiorProfileId = 'simple',
    this.interiorSatisfied = false,
    this.houseViabilitySatisfied = true,
    this.lastResolvedAt,
    this.nextResolutionAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : requiredWeatherProtectionTypes =
            requiredWeatherProtectionTypes ?? <String>[],
        missingWeatherProtectionTypes =
            missingWeatherProtectionTypes ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String currentDayKey;
  int mealsRequired;
  int mealsConsumed;
  ResidentNutritionStatus nutritionStatus;
  final List<String> requiredWeatherProtectionTypes;
  final List<String> missingWeatherProtectionTypes;
  String? activeDesireId;
  bool desireSatisfied;
  String interiorProfileId;
  bool interiorSatisfied;
  bool houseViabilitySatisfied;
  DateTime? lastResolvedAt;
  DateTime? nextResolutionAt;
  DateTime createdAt;
  DateTime updatedAt;

  int get mealsMissing => math.max(0, mealsRequired - mealsConsumed);

  factory ResidentNeedsState.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentNeedsState(
        currentDayKey: '${data['currentDayKey'] ?? ''}',
        mealsRequired: Zone0GameState.instance
            ._readInt(data['mealsRequired'], fallback: 2),
        mealsConsumed: Zone0GameState.instance._readInt(data['mealsConsumed']),
        nutritionStatus: ForageMission._enumByName(
          ResidentNutritionStatus.values,
          '${data['nutritionStatus'] ?? ''}',
          ResidentNutritionStatus.nourri,
        ),
        requiredWeatherProtectionTypes:
            (data['requiredWeatherProtectionTypes'] as List? ?? const [])
                .map((item) => '$item')
                .toList(),
        missingWeatherProtectionTypes:
            (data['missingWeatherProtectionTypes'] as List? ?? const [])
                .map((item) => '$item')
                .toList(),
        activeDesireId: data['activeDesireId'] as String?,
        desireSatisfied: data['desireSatisfied'] == true,
        interiorProfileId: '${data['interiorProfileId'] ?? 'simple'}',
        interiorSatisfied: data['interiorSatisfied'] == true,
        houseViabilitySatisfied: data['houseViabilitySatisfied'] != false,
        lastResolvedAt:
            Zone0GameState.instance._readDate(data['lastResolvedAt']),
        nextResolutionAt:
            Zone0GameState.instance._readDate(data['nextResolutionAt']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'currentDayKey': currentDayKey,
        'mealsRequired': mealsRequired,
        'mealsConsumed': mealsConsumed,
        'mealsMissing': mealsMissing,
        'nutritionStatus': nutritionStatus.name,
        'requiredWeatherProtectionTypes': requiredWeatherProtectionTypes,
        'missingWeatherProtectionTypes': missingWeatherProtectionTypes,
        'activeDesireId': activeDesireId,
        'desireSatisfied': desireSatisfied,
        'interiorProfileId': interiorProfileId,
        'interiorSatisfied': interiorSatisfied,
        'houseViabilitySatisfied': houseViabilitySatisfied,
        'lastResolvedAt':
            lastResolvedAt == null ? null : Timestamp.fromDate(lastResolvedAt!),
        'nextResolutionAt': nextResolutionAt == null
            ? null
            : Timestamp.fromDate(nextResolutionAt!),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

/// Single source of truth for the additive V2 happiness calculation. Widgets
/// read the same breakdown used by persistence and the global Harmony average.
class ResidentHappinessService {
  const ResidentHappinessService._();

  static Map<String, int> breakdown({
    required Zone0Resident resident,
    required ResidentHouse? house,
  }) {
    final values = <String, int>{'Base': resident.baseHappiness};
    resident.happinessModifiers.forEach((key, value) {
      if (value != 0) values[key] = value;
    });
    if (resident.temporaryHappinessModifier != 0) {
      values['legacy'] = resident.temporaryHappinessModifier;
    }
    if (house != null && house.currentViability < 50) {
      values['viabilité maison'] =
          -housingConfig.houseViabilityDamageHappinessPercent;
    }
    if (resident.houseId == null) {
      values['sans logement'] =
          -housingConfig.wellbeingPenaltyPerUnhousedResident;
    }
    return values;
  }

  static int calculate({
    required Zone0Resident resident,
    required ResidentHouse? house,
  }) =>
      breakdown(resident: resident, house: house)
          .values
          .fold<int>(0, (sum, value) => sum + value)
          .clamp(0, 100);
}

/// Persisted placeholder for the next Residents update. No candidate is
/// generated in Habitants V1; retaining this model avoids another migration
/// once Arrivées receives its narrative and acceptance flow.
enum ResidentArrivalStatus {
  available,
  postponed,
  acceptedPendingConditions,
  acceptedReady,
  arrivalScheduled,
  arrived,
  rejected,
  expired,
  cancelled,
  archived,
}

class ResidentArrivalCompanion {
  ResidentArrivalCompanion({
    required this.id,
    required this.displayName,
    required this.primaryPassionId,
    required this.primaryDesireId,
    required this.interiorProfileId,
  });

  factory ResidentArrivalCompanion.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentArrivalCompanion(
        id: '${data['candidateId'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Habitant'}',
        primaryPassionId: '${data['primaryPassionId'] ?? 'cooking'}',
        primaryDesireId: '${data['primaryDesireId'] ?? 'sweetTooth'}',
        interiorProfileId: '${data['interiorProfileId'] ?? 'simple'}',
      );

  final String id;
  final String displayName;
  final String primaryPassionId;
  final String primaryDesireId;
  final String interiorProfileId;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'candidateId': id,
        'displayName': displayName,
        'primaryPassionId': primaryPassionId,
        'primaryDesireId': primaryDesireId,
        'interiorProfileId': interiorProfileId,
      };
}

class ResidentArrivalCandidate {
  ResidentArrivalCandidate({
    required this.id,
    required this.displayName,
    required this.originText,
    required this.arrivalReasonText,
    required this.promisedContributionText,
    required this.accompanyingResidentCount,
    required this.createdAt,
    this.requestedConditions = const <String>[],
    this.departureReasonText = '',
    this.shortStoryText = '',
    this.primaryPassionId = 'cooking',
    this.primaryDesireId = 'sweetTooth',
    this.interiorProfileId = 'simple',
    this.promisedContributionType = '',
    this.accompanyingCandidates = const <ResidentArrivalCompanion>[],
    this.requiredHousingCapacity = 1,
    this.requiredBuildingConditions = const <String>[],
    this.requiredItemConditions = const <String>[],
    this.requiredProjectConditions = const <String>[],
    this.reservedHouseId,
    this.status = ResidentArrivalStatus.available,
    this.expiresAt,
    this.postponedAt,
    this.acceptedAt,
    this.arrivalScheduledAt,
    this.arrivedAt,
    this.initialVisionProjectId,
    this.idempotencyKey,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  factory ResidentArrivalCandidate.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentArrivalCandidate(
        id: '${data['candidateId'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Habitant'}',
        originText: '${data['originText'] ?? ''}',
        arrivalReasonText: '${data['arrivalReasonText'] ?? ''}',
        promisedContributionText: '${data['promisedContributionText'] ?? ''}',
        accompanyingResidentCount:
            Zone0GameState.instance._readInt(data['accompanyingResidentCount']),
        requestedConditions:
            (data['requestedConditions'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        departureReasonText: '${data['departureReasonText'] ?? ''}',
        shortStoryText: '${data['shortStoryText'] ?? ''}',
        primaryPassionId: '${data['primaryPassionId'] ?? 'cooking'}',
        primaryDesireId: '${data['primaryDesireId'] ?? 'sweetTooth'}',
        interiorProfileId: '${data['interiorProfileId'] ?? 'simple'}',
        promisedContributionType: '${data['promisedContributionType'] ?? ''}',
        accompanyingCandidates:
            (data['accompanyingCandidates'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map(ResidentArrivalCompanion.fromFirebase)
                .toList(),
        requiredHousingCapacity: Zone0GameState.instance._readInt(
          data['requiredHousingCapacity'],
          fallback: math.max(
              1,
              Zone0GameState.instance
                      ._readInt(data['accompanyingResidentCount']) +
                  1),
        ),
        requiredBuildingConditions:
            (data['requiredBuildingConditions'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        requiredItemConditions:
            (data['requiredItemConditions'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        requiredProjectConditions:
            (data['requiredProjectConditions'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        reservedHouseId: data['reservedHouseId'] as String?,
        status: ForageMission._enumByName(
          ResidentArrivalStatus.values,
          '${data['status'] ?? ''}',
          ResidentArrivalStatus.available,
        ),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        expiresAt: Zone0GameState.instance._readDate(data['expiresAt']),
        postponedAt: Zone0GameState.instance._readDate(data['postponedAt']),
        acceptedAt: Zone0GameState.instance._readDate(data['acceptedAt']),
        arrivalScheduledAt:
            Zone0GameState.instance._readDate(data['arrivalScheduledAt']),
        arrivedAt: Zone0GameState.instance._readDate(data['arrivedAt']),
        initialVisionProjectId: data['initialVisionProjectId'] as String?,
        idempotencyKey: data['idempotencyKey'] as String?,
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  final String id;
  final String displayName;
  final String originText;
  final String arrivalReasonText;
  final List<String> requestedConditions;
  final String promisedContributionText;
  final int accompanyingResidentCount;
  final String departureReasonText;
  final String shortStoryText;
  final String primaryPassionId;
  final String primaryDesireId;
  final String interiorProfileId;
  final String? initialVisionProjectId;
  final String promisedContributionType;
  final List<ResidentArrivalCompanion> accompanyingCandidates;
  final int requiredHousingCapacity;
  final List<String> requiredBuildingConditions;
  final List<String> requiredItemConditions;
  final List<String> requiredProjectConditions;
  String? reservedHouseId;
  ResidentArrivalStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  DateTime? postponedAt;
  DateTime? acceptedAt;
  DateTime? arrivalScheduledAt;
  DateTime? arrivedAt;
  final String? idempotencyKey;
  DateTime updatedAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'candidateId': id,
        'displayName': displayName,
        'originText': originText,
        'arrivalReasonText': arrivalReasonText,
        'departureReasonText': departureReasonText,
        'shortStoryText': shortStoryText,
        'requestedConditions': requestedConditions,
        'promisedContributionText': promisedContributionText,
        'promisedContributionType': promisedContributionType,
        'accompanyingResidentCount': accompanyingResidentCount,
        'accompanyingCandidates':
            accompanyingCandidates.map((item) => item.toFirebase()).toList(),
        'primaryPassionId': primaryPassionId,
        'primaryDesireId': primaryDesireId,
        'interiorProfileId': interiorProfileId,
        'initialVisionProjectId': initialVisionProjectId,
        'requiredHousingCapacity': requiredHousingCapacity,
        'requiredBuildingConditions': requiredBuildingConditions,
        'requiredItemConditions': requiredItemConditions,
        'requiredProjectConditions': requiredProjectConditions,
        'reservedHouseId': reservedHouseId,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
        'postponedAt':
            postponedAt == null ? null : Timestamp.fromDate(postponedAt!),
        'acceptedAt':
            acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
        'arrivalScheduledAt': arrivalScheduledAt == null
            ? null
            : Timestamp.fromDate(arrivalScheduledAt!),
        'arrivedAt': arrivedAt == null ? null : Timestamp.fromDate(arrivedAt!),
        'idempotencyKey': idempotencyKey,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

class Zone0Resident {
  Zone0Resident({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.houseId,
    this.baseHappiness = 100,
    int? currentHappiness,
    this.temporaryHappinessModifier = 0,
    this.isActive = true,
    this.contributionEligible = false,
    this.internalPileBalance = 0,
    this.financialStrainScore = 0,
    this.recentDomesticIncomePiles = 0,
    this.recentSpendingPiles = 0,
    this.status = ResidentStatus.active,
    Map<String, int>? happinessModifiers,
    this.arrivedAt,
    this.sourceMigrationId,
    this.primaryDesireId,
    this.primaryPassionId,
    this.secondaryPassionId,
    this.interiorProfileId,
    this.currentVisionProjectId,
    this.inventorySlotBonus = 0,
    Map<String, int>? personalInventory,
    Map<String, int>? wardrobeInventory,
    List<String>? ownedCertifiedPtibugIds,
    this.activeCommunityRoleId,
    this.assignedBuildingId,
    this.eligibleForShopOwnership = false,
    this.ownedShopId,
    this.shopOwnershipStartedAt,
    this.preferredShopCategory,
    this.commercialAssignmentStatus,
    Map<String, dynamic>? dailyNeedsState,
    ResidentNeedsState? needsState,
    List<ResidentOwnedItem>? ownedItems,
    DateTime? updatedAt,
  })  : currentHappiness = currentHappiness ?? baseHappiness,
        happinessModifiers = happinessModifiers ?? <String, int>{},
        personalInventory = personalInventory ?? <String, int>{},
        wardrobeInventory = wardrobeInventory ?? <String, int>{},
        ownedCertifiedPtibugIds = ownedCertifiedPtibugIds ?? <String>[],
        dailyNeedsState = dailyNeedsState ?? <String, dynamic>{},
        needsState = needsState ??
            ResidentNeedsState(
              currentDayKey: '',
              mealsRequired: housingConfig.mealsRequiredPerDay,
            ),
        ownedItems = ownedItems ?? <ResidentOwnedItem>[],
        updatedAt = updatedAt ?? createdAt;

  factory Zone0Resident.fromFirebase(Map<dynamic, dynamic> data) =>
      Zone0Resident(
        id: '${data['residentId'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Habitant'}',
        houseId: data['houseId'] as String?,
        baseHappiness: Zone0GameState.instance
            ._readInt(data['baseHappiness'], fallback: 100)
            .clamp(0, 100),
        currentHappiness: Zone0GameState.instance
            ._readInt(data['currentHappiness'], fallback: 100)
            .clamp(0, 100),
        temporaryHappinessModifier: Zone0GameState.instance
            ._readInt(data['temporaryHappinessModifier']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
        isActive: data['isActive'] != false,
        contributionEligible: data['contributionEligible'] == true,
        internalPileBalance:
            Zone0GameState.instance._readInt(data['internalPileBalance']),
        financialStrainScore:
            Zone0GameState.instance._readInt(data['financialStrainScore']),
        recentDomesticIncomePiles:
            Zone0GameState.instance._readInt(data['recentDomesticIncomePiles']),
        recentSpendingPiles:
            Zone0GameState.instance._readInt(data['recentSpendingPiles']),
        status: ForageMission._enumByName(
          ResidentStatus.values,
          '${data['status'] ?? ''}',
          data['houseId'] == null
              ? ResidentStatus.awaitingHousing
              : ResidentStatus.active,
        ),
        happinessModifiers: Map<String, int>.fromEntries(
          (data['happinessModifiers'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry(
                    '${entry.key}',
                    Zone0GameState.instance._readInt(entry.value),
                  )),
        ),
        arrivedAt: Zone0GameState.instance._readDate(data['arrivedAt']),
        sourceMigrationId: data['sourceMigrationId'] as String?,
        primaryDesireId: data['primaryDesireId'] as String?,
        primaryPassionId: data['primaryPassionId'] as String?,
        secondaryPassionId: data['secondaryPassionId'] as String?,
        interiorProfileId: data['interiorProfileId'] as String?,
        currentVisionProjectId: data['currentVisionProjectId'] as String?,
        inventorySlotBonus:
            Zone0GameState.instance._readInt(data['inventorySlotBonus']),
        personalInventory: Map<String, int>.fromEntries(
          (data['personalInventory'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry(
                    '${entry.key}',
                    Zone0GameState.instance._readInt(entry.value),
                  )),
        ),
        wardrobeInventory: Map<String, int>.fromEntries(
          (data['wardrobeInventory'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry(
                    '${entry.key}',
                    Zone0GameState.instance._readInt(entry.value),
                  )),
        ),
        ownedCertifiedPtibugIds:
            (data['ownedCertifiedPtibugIds'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        activeCommunityRoleId: data['activeCommunityRoleId'] as String?,
        assignedBuildingId: data['assignedBuildingId'] as String?,
        eligibleForShopOwnership: data['eligibleForShopOwnership'] == true,
        ownedShopId: data['ownedShopId'] as String?,
        shopOwnershipStartedAt:
            Zone0GameState.instance._readDate(data['shopOwnershipStartedAt']),
        preferredShopCategory: data['preferredShopCategory'] as String?,
        commercialAssignmentStatus:
            data['commercialAssignmentStatus'] as String?,
        dailyNeedsState: Map<String, dynamic>.from(
            data['dailyNeedsState'] as Map? ?? const <dynamic, dynamic>{}),
        needsState: data['needsState'] is Map
            ? ResidentNeedsState.fromFirebase(data['needsState'] as Map)
            : ResidentNeedsState(
                currentDayKey:
                    '${(data['dailyNeedsState'] as Map?)?['currentDayKey'] ?? ''}',
                mealsRequired: Zone0GameState.instance._readInt(
                  (data['dailyNeedsState'] as Map?)?['mealsRequired'],
                  fallback: housingConfig.mealsRequiredPerDay,
                ),
              ),
        ownedItems: (data['ownedItems'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(ResidentOwnedItem.fromFirebase)
            .where((item) => item.id.isNotEmpty && item.quantity > 0)
            .toList(),
      );

  final String id;
  String displayName;
  String? houseId;
  int baseHappiness;
  int currentHappiness;
  int temporaryHappinessModifier;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isActive;
  bool contributionEligible;
  int internalPileBalance;
  int financialStrainScore;
  int recentDomesticIncomePiles;
  int recentSpendingPiles;
  ResidentStatus status;
  final Map<String, int> happinessModifiers;
  DateTime? arrivedAt;
  String? sourceMigrationId;
  String? primaryDesireId;
  String? primaryPassionId;
  String? secondaryPassionId;
  String? interiorProfileId;
  String? currentVisionProjectId;
  int inventorySlotBonus;
  final Map<String, int> personalInventory;
  final Map<String, int> wardrobeInventory;
  final List<String> ownedCertifiedPtibugIds;
  String? activeCommunityRoleId;
  String? assignedBuildingId;
  bool eligibleForShopOwnership;
  String? ownedShopId;
  DateTime? shopOwnershipStartedAt;
  String? preferredShopCategory;
  String? commercialAssignmentStatus;
  final Map<String, dynamic> dailyNeedsState;
  final ResidentNeedsState needsState;
  final List<ResidentOwnedItem> ownedItems;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'residentId': id,
        'displayName': displayName,
        'houseId': houseId,
        'baseHappiness': baseHappiness,
        'currentHappiness': currentHappiness,
        'temporaryHappinessModifier': temporaryHappinessModifier,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'isActive': isActive,
        'contributionEligible': contributionEligible,
        'internalPileBalance': internalPileBalance,
        'financialStrainScore': financialStrainScore,
        'recentDomesticIncomePiles': recentDomesticIncomePiles,
        'recentSpendingPiles': recentSpendingPiles,
        'status': status.name,
        'happinessModifiers': happinessModifiers,
        'arrivedAt': arrivedAt == null ? null : Timestamp.fromDate(arrivedAt!),
        'sourceMigrationId': sourceMigrationId,
        'primaryDesireId': primaryDesireId,
        'primaryPassionId': primaryPassionId,
        'secondaryPassionId': secondaryPassionId,
        'interiorProfileId': interiorProfileId,
        'currentVisionProjectId': currentVisionProjectId,
        'inventorySlotBonus': inventorySlotBonus,
        'personalInventory': personalInventory,
        'wardrobeInventory': wardrobeInventory,
        'ownedCertifiedPtibugIds': ownedCertifiedPtibugIds,
        'activeCommunityRoleId': activeCommunityRoleId,
        'assignedBuildingId': assignedBuildingId,
        'eligibleForShopOwnership': eligibleForShopOwnership,
        'ownedShopId': ownedShopId,
        'shopOwnershipStartedAt': shopOwnershipStartedAt == null
            ? null
            : Timestamp.fromDate(shopOwnershipStartedAt!),
        'preferredShopCategory': preferredShopCategory,
        'commercialAssignmentStatus': commercialAssignmentStatus,
        'dailyNeedsState': dailyNeedsState,
        'needsState': needsState.toFirebase(),
        'ownedItems': ownedItems.map((item) => item.toFirebase()).toList(),
      };
}

enum ResidentVisionStatus {
  active,
  fulfilled,
  disappointed,
  replaced,
  archived
}

class ResidentVision {
  ResidentVision({
    required this.id,
    required this.residentId,
    required this.projectId,
    required this.projectTier,
    this.branchId,
    this.status = ResidentVisionStatus.active,
    required this.selectedAt,
    this.fulfilledAt,
    this.disappointedAt,
    this.disappointmentEndsAt,
    this.persistentBonus = 0,
    this.nextVisionGeneratedAt,
  });

  factory ResidentVision.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentVision(
        id: '${data['visionId'] ?? ''}',
        residentId: '${data['residentId'] ?? ''}',
        projectId: '${data['projectId'] ?? ''}',
        projectTier:
            Zone0GameState.instance._readInt(data['projectTier'], fallback: 1),
        branchId: data['branchId'] as String?,
        status: ForageMission._enumByName(ResidentVisionStatus.values,
            '${data['status'] ?? ''}', ResidentVisionStatus.active),
        selectedAt: Zone0GameState.instance._readDate(data['selectedAt']) ??
            DateTime.now(),
        fulfilledAt: Zone0GameState.instance._readDate(data['fulfilledAt']),
        disappointedAt:
            Zone0GameState.instance._readDate(data['disappointedAt']),
        disappointmentEndsAt:
            Zone0GameState.instance._readDate(data['disappointmentEndsAt']),
        persistentBonus:
            Zone0GameState.instance._readInt(data['persistentBonus']),
        nextVisionGeneratedAt:
            Zone0GameState.instance._readDate(data['nextVisionGeneratedAt']),
      );

  final String id;
  final String residentId;
  final String projectId;
  final int projectTier;
  final String? branchId;
  ResidentVisionStatus status;
  final DateTime selectedAt;
  DateTime? fulfilledAt;
  DateTime? disappointedAt;
  DateTime? disappointmentEndsAt;
  int persistentBonus;
  DateTime? nextVisionGeneratedAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'visionId': id,
        'residentId': residentId,
        'projectId': projectId,
        'projectTier': projectTier,
        'branchId': branchId,
        'status': status.name,
        'selectedAt': Timestamp.fromDate(selectedAt),
        'fulfilledAt':
            fulfilledAt == null ? null : Timestamp.fromDate(fulfilledAt!),
        'disappointedAt':
            disappointedAt == null ? null : Timestamp.fromDate(disappointedAt!),
        'disappointmentEndsAt': disappointmentEndsAt == null
            ? null
            : Timestamp.fromDate(disappointmentEndsAt!),
        'persistentBonus': persistentBonus,
        'nextVisionGeneratedAt': nextVisionGeneratedAt == null
            ? null
            : Timestamp.fromDate(nextVisionGeneratedAt!),
      };
}

enum HouseholdRepairStatus { active, paused, completed, cancelled }

class HouseholdRepairJob {
  HouseholdRepairJob({
    required this.id,
    required this.houseId,
    required this.startedAt,
    required this.endsAt,
    required this.viabilityGain,
    required this.isPlayerRepair,
    this.reservedKitItemId,
    this.status = HouseholdRepairStatus.active,
  });

  factory HouseholdRepairJob.fromFirebase(Map<dynamic, dynamic> data) =>
      HouseholdRepairJob(
        id: '${data['repairJobId'] ?? ''}',
        houseId: '${data['houseId'] ?? ''}',
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        viabilityGain: Zone0GameState.instance._readInt(data['viabilityGain']),
        isPlayerRepair: data['isPlayerRepair'] == true,
        reservedKitItemId: data['reservedKitItemId'] as String?,
        status: ForageMission._enumByName(HouseholdRepairStatus.values,
            '${data['status'] ?? ''}', HouseholdRepairStatus.active),
      );

  final String id;
  final String houseId;
  final DateTime startedAt;
  final DateTime endsAt;
  final int viabilityGain;
  final bool isPlayerRepair;
  final String? reservedKitItemId;
  HouseholdRepairStatus status;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'repairJobId': id,
        'houseId': houseId,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'viabilityGain': viabilityGain,
        'isPlayerRepair': isPlayerRepair,
        'reservedKitItemId': reservedKitItemId,
        'status': status.name,
      };
}

class ResidentHouse {
  ResidentHouse({
    required this.id,
    required this.displayName,
    required this.biome,
    required this.capacity,
    this.currentViability = 100,
    this.maximumViability = 100,
    List<String>? residentIds,
    List<StructuralProtectionType>? installedStructuralProtections,
    this.lastDamageEventId,
    this.isUnderRepair = false,
    int? weatherProtectionSlots,
    int? furnitureSlots,
    List<String>? installedFurnitureItems,
    this.installationSlots = 4,
    List<String>? installedInstallationItems,
    Map<String, int>? householdInventory,
    Map<String, int>? structuralConsumables,
    this.baseGeneratorInstalled = true,
    int? additionalGeneratorSlots,
    this.additionalGeneratorInstalled = false,
    this.householdPileBalance = 0,
    this.householdDistributionRemainder = 0,
    this.lastEnergyDistributionAt,
    this.lastHouseholdEnergyResolvedAt,
    this.energyProductionRemainder = 0,
    this.recentEnergyProducedPiles = 0,
    this.recentHouseholdSpendingPiles = 0,
    List<String>? reservedArrivalCandidateIds,
    this.activeRepairJobId,
    this.autonomyLockedUntil,
    this.lastAutonomyDecision,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : residentIds = residentIds ?? <String>[],
        installedStructuralProtections =
            installedStructuralProtections ?? <StructuralProtectionType>[],
        weatherProtectionSlots =
            weatherProtectionSlots ?? housingConfig.houseProtectionSlots,
        furnitureSlots = furnitureSlots ?? housingConfig.residentFurnitureSlots,
        installedFurnitureItems = installedFurnitureItems ?? <String>[],
        installedInstallationItems = installedInstallationItems ?? <String>[],
        householdInventory = householdInventory ?? <String, int>{},
        structuralConsumables = structuralConsumables ?? <String, int>{},
        reservedArrivalCandidateIds = reservedArrivalCandidateIds ?? <String>[],
        additionalGeneratorSlots =
            additionalGeneratorSlots ?? housingConfig.additionalGeneratorSlots,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ResidentHouse.fromFirebase(Map<dynamic, dynamic> data) =>
      ResidentHouse(
        id: '${data['houseId'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Maison'}',
        biome: ForageMission._enumByName(ForageBiome.values,
            '${data['biomeId'] ?? ''}', ForageBiome.plaineRiche),
        capacity: Zone0GameState.instance
            ._readInt(data['residentCapacity'], fallback: 3),
        currentViability: Zone0GameState.instance
            ._readInt(data['currentViability'], fallback: 100),
        maximumViability: Zone0GameState.instance
            ._readInt(data['maxViability'], fallback: 100),
        residentIds: (data['residentIds'] as List? ?? const [])
            .map((item) => '$item')
            .toList(),
        installedStructuralProtections:
            (data['installedStructuralProtections'] as List? ?? const [])
                .map((item) => ForageMission._enumByName(
                    StructuralProtectionType.values,
                    '$item',
                    StructuralProtectionType.ventilationTermite))
                .toList(),
        lastDamageEventId: data['lastDamageEventId'] as String?,
        isUnderRepair: data['isUnderRepair'] == true,
        weatherProtectionSlots: Zone0GameState.instance._readInt(
          data['weatherProtectionSlots'],
          fallback: housingConfig.houseProtectionSlots,
        ),
        furnitureSlots: Zone0GameState.instance._readInt(
          data['furnitureSlots'],
          fallback: housingConfig.residentFurnitureSlots,
        ),
        installedFurnitureItems:
            (data['installedFurnitureItems'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        installationSlots: Zone0GameState.instance._readInt(
          data['installationSlots'],
          fallback: 4,
        ),
        installedInstallationItems:
            (data['installedInstallationItems'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        householdInventory: (data['householdInventory'] as Map? ?? const {})
            .map((key, value) => MapEntry(
                  '$key',
                  Zone0GameState.instance._readInt(value),
                )),
        structuralConsumables: (data['structuralConsumables'] as Map? ??
                const <dynamic, dynamic>{})
            .map((key, value) => MapEntry(
                  '$key',
                  Zone0GameState.instance._readInt(value),
                )),
        baseGeneratorInstalled: data['baseGeneratorInstalled'] != false,
        additionalGeneratorSlots: Zone0GameState.instance._readInt(
          data['additionalGeneratorSlots'],
          fallback: housingConfig.additionalGeneratorSlots,
        ),
        additionalGeneratorInstalled:
            data['additionalGeneratorInstalled'] == true,
        householdPileBalance:
            Zone0GameState.instance._readInt(data['householdPileBalance']),
        householdDistributionRemainder: Zone0GameState.instance
            ._readInt(data['householdDistributionRemainder']),
        lastEnergyDistributionAt:
            Zone0GameState.instance._readDate(data['lastEnergyDistributionAt']),
        lastHouseholdEnergyResolvedAt: Zone0GameState.instance
            ._readDate(data['lastHouseholdEnergyResolvedAt']),
        energyProductionRemainder:
            Zone0GameState.instance._readInt(data['energyProductionRemainder']),
        recentEnergyProducedPiles:
            Zone0GameState.instance._readInt(data['recentEnergyProducedPiles']),
        recentHouseholdSpendingPiles: Zone0GameState.instance
            ._readInt(data['recentHouseholdSpendingPiles']),
        reservedArrivalCandidateIds:
            (data['reservedArrivalCandidateIds'] as List? ?? const <dynamic>[])
                .map((item) => '$item')
                .toList(),
        activeRepairJobId: data['activeRepairJobId'] as String?,
        autonomyLockedUntil:
            Zone0GameState.instance._readDate(data['autonomyLockedUntil']),
        lastAutonomyDecision: data['lastAutonomyDecision'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  final String id;
  String displayName;
  ForageBiome biome;
  int capacity;
  int currentViability;
  int maximumViability;
  final List<String> residentIds;
  final List<StructuralProtectionType> installedStructuralProtections;
  String? lastDamageEventId;
  bool isUnderRepair;
  int weatherProtectionSlots;
  int furnitureSlots;
  final List<String> installedFurnitureItems;
  int installationSlots;
  final List<String> installedInstallationItems;
  final Map<String, int> householdInventory;
  final Map<String, int> structuralConsumables;
  bool baseGeneratorInstalled;
  int additionalGeneratorSlots;
  bool additionalGeneratorInstalled;
  int householdPileBalance;
  int householdDistributionRemainder;
  DateTime? lastEnergyDistributionAt;
  DateTime? lastHouseholdEnergyResolvedAt;
  int energyProductionRemainder;
  int recentEnergyProducedPiles;
  int recentHouseholdSpendingPiles;
  final List<String> reservedArrivalCandidateIds;
  String? activeRepairJobId;
  DateTime? autonomyLockedUntil;
  String? lastAutonomyDecision;
  final DateTime createdAt;
  DateTime updatedAt;

  int protectionReductionPercent(
      TowerWeatherType weather, BuildingViabilityConfig config) {
    final type = switch (weather) {
      TowerWeatherType.heatWave => StructuralProtectionType.ventilationTermite,
      TowerWeatherType.heavyRain => StructuralProtectionType.chloroCanaux,
      TowerWeatherType.toxicCloud => StructuralProtectionType.filtration,
      TowerWeatherType.calm => null,
    };
    if (type == null || config.protectionReductionPercents.isEmpty) return 0;
    final count =
        installedStructuralProtections.where((item) => item == type).length;
    var total = 0;
    for (var index = 0; index < count; index++) {
      total += config.protectionReductionPercents[
          index < config.protectionReductionPercents.length
              ? index
              : config.protectionReductionPercents.length - 1];
    }
    return total.clamp(0, config.protectionCapPercent);
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'houseId': id,
        'displayName': displayName,
        'biomeId': biome.name,
        'currentViability': currentViability,
        'maxViability': maximumViability,
        'residentCapacity': capacity,
        'residentIds': residentIds,
        'installedStructuralProtections':
            installedStructuralProtections.map((item) => item.name).toList(),
        'lastDamageEventId': lastDamageEventId,
        'isUnderRepair': isUnderRepair,
        'weatherProtectionSlots': weatherProtectionSlots,
        'furnitureSlots': furnitureSlots,
        'installedFurnitureItems': installedFurnitureItems,
        'installationSlots': installationSlots,
        'installedInstallationItems': installedInstallationItems,
        'householdInventory': householdInventory,
        'structuralConsumables': structuralConsumables,
        'baseGeneratorInstalled': baseGeneratorInstalled,
        'additionalGeneratorSlots': additionalGeneratorSlots,
        'additionalGeneratorInstalled': additionalGeneratorInstalled,
        'householdPileBalance': householdPileBalance,
        'householdDistributionRemainder': householdDistributionRemainder,
        'lastEnergyDistributionAt': lastEnergyDistributionAt == null
            ? null
            : Timestamp.fromDate(lastEnergyDistributionAt!),
        'lastHouseholdEnergyResolvedAt': lastHouseholdEnergyResolvedAt == null
            ? null
            : Timestamp.fromDate(lastHouseholdEnergyResolvedAt!),
        'energyProductionRemainder': energyProductionRemainder,
        'recentEnergyProducedPiles': recentEnergyProducedPiles,
        'recentHouseholdSpendingPiles': recentHouseholdSpendingPiles,
        'reservedArrivalCandidateIds': reservedArrivalCandidateIds,
        'activeRepairJobId': activeRepairJobId,
        'autonomyLockedUntil': autonomyLockedUntil == null
            ? null
            : Timestamp.fromDate(autonomyLockedUntil!),
        'lastAutonomyDecision': lastAutonomyDecision,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

enum CommunityProjectStatus { selected, active, paused, completed }

enum HouseholdAutonomyAction { protection, repair, furniture, generator, none }

/// Central, deterministic prioritisation for household decisions. The state
/// owns transactions; this service only explains and orders real needs.
class HouseholdAutonomyService {
  const HouseholdAutonomyService._();

  static StructuralProtectionType? requiredProtection(TowerWeatherType? type) =>
      switch (type) {
        TowerWeatherType.heatWave =>
          StructuralProtectionType.ventilationTermite,
        TowerWeatherType.heavyRain => StructuralProtectionType.chloroCanaux,
        TowerWeatherType.toxicCloud => StructuralProtectionType.filtration,
        _ => null,
      };

  static String? protectionItem(StructuralProtectionType? type) =>
      switch (type) {
        StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
        StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
        StructuralProtectionType.filtration => 'Installation filtrante',
        null => null,
      };

  static HouseholdAutonomyAction nextAction(
      Zone0GameState state, ResidentHouse house) {
    final neededProtection =
        requiredProtection(state.nextGlobalWeatherEvent?.type);
    if (neededProtection != null &&
        !house.installedStructuralProtections.contains(neededProtection) &&
        house.installedStructuralProtections.length <
            house.weatherProtectionSlots) {
      house.lastAutonomyDecision =
          'Protection recherchée avant la prochaine météo.';
      return HouseholdAutonomyAction.protection;
    }
    final occupants =
        state.residents.where((resident) => resident.houseId == house.id);
    if (occupants.any((resident) => !resident.needsState.interiorSatisfied)) {
      house.lastAutonomyDecision =
          'Mobilier fonctionnel recherché pour le foyer.';
      return HouseholdAutonomyAction.furniture;
    }
    final strain = occupants.fold<int>(
        0, (total, resident) => total + resident.financialStrainScore);
    if (!house.additionalGeneratorInstalled &&
        house.additionalGeneratorSlots > 0 &&
        strain >= residentEconomyConfig.financialStrainCriticalThreshold &&
        occupants.every((resident) => resident.needsState.mealsConsumed > 0)) {
      house.lastAutonomyDecision =
          'Second générateur envisagé : manque financier durable.';
      return HouseholdAutonomyAction.generator;
    }
    house.lastAutonomyDecision = 'Aucun achat domestique prioritaire.';
    return HouseholdAutonomyAction.none;
  }
}

class CommunityProjectProgress {
  CommunityProjectProgress({
    required this.definition,
    this.status = CommunityProjectStatus.selected,
    Map<String, int>? depositedMaterials,
    this.currentContributionPoints = 0,
    this.playerContributionDay,
    this.residentContributionDay,
    this.residentContributionToday = 0,
    this.startedAt,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : depositedMaterials = depositedMaterials ?? <String, int>{},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final CommunityProjectDefinition definition;
  CommunityProjectStatus status;
  final Map<String, int> depositedMaterials;
  int currentContributionPoints;
  String? playerContributionDay;
  String? residentContributionDay;
  int residentContributionToday;
  DateTime? startedAt;
  DateTime? completedAt;
  final DateTime createdAt;
  DateTime updatedAt;
  bool get materialsComplete => definition.materialCosts.entries
      .every((entry) => (depositedMaterials[entry.key] ?? 0) >= entry.value);

  factory CommunityProjectProgress.fromFirebase(
          Map<dynamic, dynamic> data, CommunityProjectDefinition definition) =>
      CommunityProjectProgress(
        definition: definition,
        status: ForageMission._enumByName(CommunityProjectStatus.values,
            '${data['status'] ?? ''}', CommunityProjectStatus.selected),
        depositedMaterials: Map<String, int>.fromEntries(
            (data['depositedMaterials'] as Map? ?? const {}).entries.map(
                (entry) => MapEntry('${entry.key}',
                    Zone0GameState.instance._readInt(entry.value)))),
        currentContributionPoints:
            Zone0GameState.instance._readInt(data['currentContributionPoints']),
        playerContributionDay: data['playerContributionDay'] as String?,
        residentContributionDay: data['residentContributionDay'] as String?,
        residentContributionToday:
            Zone0GameState.instance._readInt(data['residentContributionToday']),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'projectId': definition.id,
        'status': status.name,
        'depositedMaterials': depositedMaterials,
        'currentContributionPoints': currentContributionPoints,
        'playerContributionDay': playerContributionDay,
        'residentContributionDay': residentContributionDay,
        'residentContributionToday': residentContributionToday,
        'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

class WeatherStockIncident {
  const WeatherStockIncident(
      {required this.eventId,
      required this.wasteCreated,
      required this.organicLost,
      required this.batteriesLost,
      required this.protectionPercent,
      required this.resolvedAt});
  final String eventId;
  final int wasteCreated;
  final int organicLost;
  final int batteriesLost;
  final int protectionPercent;
  final DateTime resolvedAt;
  factory WeatherStockIncident.fromFirebase(Map<dynamic, dynamic> data) =>
      WeatherStockIncident(
          eventId: '${data['eventId'] ?? ''}',
          wasteCreated: Zone0GameState.instance._readInt(data['wasteCreated']),
          organicLost: Zone0GameState.instance._readInt(data['organicLost']),
          batteriesLost:
              Zone0GameState.instance._readInt(data['batteriesLost']),
          protectionPercent:
              Zone0GameState.instance._readInt(data['protectionPercent']),
          resolvedAt: Zone0GameState.instance._readDate(data['resolvedAt']) ??
              DateTime.now());
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'eventId': eventId,
        'wasteCreated': wasteCreated,
        'organicLost': organicLost,
        'batteriesLost': batteriesLost,
        'protectionPercent': protectionPercent,
        'resolvedAt': Timestamp.fromDate(resolvedAt)
      };
}

enum PTibugTerritoryKind { nursery, refuge }

class PTibugTerritoryConsumption {
  const PTibugTerritoryConsumption({
    required this.organicPerDay,
    required this.mineralPerDay,
    required this.energyPerDay,
  });

  final int organicPerDay;
  final int mineralPerDay;
  final int energyPerDay;
}

class PTibugTerritoryBuilding {
  PTibugTerritoryBuilding({
    required this.id,
    required this.kind,
    required this.biome,
    required this.level,
    required this.isBuilt,
    Map<String, int>? localResources,
    this.localEnergy = 0,
    this.pTibugOrganicRemainder = 0,
    this.pTibugEnergyRemainder = 0,
    this.lastConsumptionAt,
  }) : localResources = localResources ?? <String, int>{};

  factory PTibugTerritoryBuilding.nurseryPlaine({required int level}) =>
      PTibugTerritoryBuilding(
        id: Zone0GameState.plaineNurseryTerritoryId,
        kind: PTibugTerritoryKind.nursery,
        biome: ForageBiome.plaineRiche,
        level: level,
        isBuilt: level > 0,
        lastConsumptionAt: DateTime.now(),
      );

  final String id;
  final PTibugTerritoryKind kind;
  final ForageBiome biome;
  int level;
  bool isBuilt;
  final Map<String, int> localResources;

  /// Shared Nursery/Refuge energy. Keeping fractions prevents a cuve using
  /// 1 energy per hour from losing a whole unit at every short game tick.
  double localEnergy;

  double pTibugOrganicRemainder;

  /// Fractional daily P'TIBUG energy consumption carried between offline
  /// resolutions. It prevents low-consumption, high-level bugs from being
  /// skipped whenever the building is resolved more often than once a day.
  double pTibugEnergyRemainder;
  DateTime? lastConsumptionAt;

  int resourceAmount(String resource) => localResources[resource] ?? 0;

  factory PTibugTerritoryBuilding.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugTerritoryBuilding(
        id: '${data['id'] ?? ''}',
        kind: ForageMission._enumByName(
          PTibugTerritoryKind.values,
          '${data['kind'] ?? ''}',
          PTibugTerritoryKind.refuge,
        ),
        biome: ForageMission._enumByName(
          ForageBiome.values,
          '${data['biome'] ?? ''}',
          ForageBiome.plaineRiche,
        ),
        level: Zone0GameState.instance._readInt(data['level']),
        isBuilt: data['isBuilt'] == true,
        localResources: Map<String, int>.fromEntries(
          (data['localResources'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map(
                (entry) => MapEntry(
                  '${entry.key}',
                  Zone0GameState.instance._readInt(entry.value),
                ),
              ),
        ),
        localEnergy: Zone0GameState.instance._readDouble(data['localEnergy']),
        pTibugOrganicRemainder:
            Zone0GameState.instance._readDouble(data['pTibugOrganicRemainder']),
        pTibugEnergyRemainder:
            Zone0GameState.instance._readDouble(data['pTibugEnergyRemainder']),
        lastConsumptionAt: Zone0GameState.instance._readDate(
          data['lastConsumptionAt'],
        ),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'biome': biome.name,
        'level': level,
        'isBuilt': isBuilt,
        'localResources': localResources,
        'localEnergy': localEnergy,
        'pTibugOrganicRemainder': pTibugOrganicRemainder,
        'pTibugEnergyRemainder': pTibugEnergyRemainder,
        'lastConsumptionAt': lastConsumptionAt == null
            ? null
            : Timestamp.fromDate(lastConsumptionAt!),
      };
}

enum PTibugLifecycleStatus { active, sold, archived }

class PTibug {
  PTibug({
    required this.id,
    required this.displayName,
    required this.species,
    required this.styleVariant,
    required this.createdAt,
    this.primaryColorHex,
    this.motifId,
    this.motifColorHex,
    this.traitColorHex,
    this.animationName,
    String? defaultDisplayName,
    this.renamedAt,
    this.renameCount = 0,
    List<String>? nameHistory,
    this.updatedAt,
    this.lifecycleStatus = PTibugLifecycleStatus.active,
    this.reservedForSaleId,
    this.assignedSlotIndex,
    this.assignedBuildingId,
    Map<String, int>? storedResources,
    List<PTibugDataCell>? storedDataCells,
    this.level = 1,
    this.xp = 0,
    this.traitDataId,
    this.biologicalTraitId,
    this.biologicalTraitLevel = 0,
    this.secondTraitId,
    this.secondTraitLevel = 0,
    this.isRenewed = false,
    this.renewedAt,
    this.renewalCount = 0,
    List<PTibugModuleType>? equippedModules,
    List<String>? equippedModuleInstanceIds,
    this.biome = PTibugBiome.savaneTropicale,
    this.refugeBiome = ForageBiome.plaineRiche,
    this.inactiveReason,
    this.stockFullNotified = false,
    this.nextProductionAt,
  })  : defaultDisplayName = defaultDisplayName ?? displayName,
        nameHistory = nameHistory ?? <String>[],
        storedResources = storedResources ?? <String, int>{},
        storedDataCells = storedDataCells ?? <PTibugDataCell>[],
        equippedModules = equippedModules ?? <PTibugModuleType>[],
        equippedModuleInstanceIds = equippedModuleInstanceIds ?? <String>[];
  final String id;
  String displayName;
  String defaultDisplayName;
  DateTime? renamedAt;
  int renameCount;
  final List<String> nameHistory;
  DateTime? updatedAt;
  PTibugLifecycleStatus lifecycleStatus;
  String? reservedForSaleId;
  final PTibugSpecies species;
  final String styleVariant;
  final DateTime createdAt;
  String? primaryColorHex;
  String? motifId;
  String? motifColorHex;
  String? traitColorHex;
  String? animationName;
  int? assignedSlotIndex;
  String? assignedBuildingId;
  final Map<String, int> storedResources;
  final List<PTibugDataCell> storedDataCells;
  int level;
  int xp;
  String? traitDataId;
  String? biologicalTraitId;
  int biologicalTraitLevel;
  String? secondTraitId;
  int secondTraitLevel;
  bool isRenewed;
  DateTime? renewedAt;
  int renewalCount;
  final List<PTibugModuleType> equippedModules;
  final List<String> equippedModuleInstanceIds;
  PTibugBiome biome;

  /// The P'TIBUG works in one Refuge at a time. The main Nurserie is Plaine;
  /// future local Refuges will only update this biome association.
  ForageBiome refugeBiome;
  String? inactiveReason;
  bool stockFullNotified;
  DateTime? nextProductionAt;
  int get storedAmount =>
      storedResources.values.fold(0, (total, value) => total + value);
  Map<String, int> get storedMaterialProduction => storedResources;
  int get materialStorageCapacity =>
      pTibugConfig.carryingCapacity * pTibugConfig.storageMultiplier;
  bool hasModule(PTibugModuleType type) => equippedModules.contains(type);

  factory PTibug.fromFirebase(Map<dynamic, dynamic> data) => PTibug(
        id: '${data['id'] ?? ''}',
        displayName: '${data['displayName'] ?? 'P’TIBUG'}',
        defaultDisplayName:
            '${data['defaultDisplayName'] ?? data['displayName'] ?? 'P’TIBUG'}',
        renamedAt: Zone0GameState.instance._readDate(data['renamedAt']),
        renameCount: Zone0GameState.instance._readInt(data['renameCount']),
        nameHistory: (data['nameHistory'] as List? ?? const <dynamic>[])
            .map((value) => '$value')
            .toList(),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
        lifecycleStatus: ForageMission._enumByName(
          PTibugLifecycleStatus.values,
          '${data['lifecycleStatus'] ?? ''}',
          PTibugLifecycleStatus.active,
        ),
        reservedForSaleId: data['reservedForSaleId'] as String?,
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        styleVariant: '${data['styleVariant'] ?? 'compact'}',
        primaryColorHex: data['primaryColorHex'] as String?,
        motifId: data['motifId'] as String?,
        motifColorHex: data['motifColorHex'] as String?,
        traitColorHex: data['traitColorHex'] as String?,
        animationName: data['animationName'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        assignedSlotIndex: data['assignedSlotIndex'] as int?,
        assignedBuildingId: data['assignedBuildingId'] as String?,
        level: Zone0GameState.instance._readInt(data['level'], fallback: 1),
        xp: Zone0GameState.instance._readInt(data['xp']),
        traitDataId: data['traitDataId'] as String?,
        biologicalTraitId: data['biologicalTraitId'] as String?,
        biologicalTraitLevel: Zone0GameState.instance._readInt(
          data['biologicalTraitLevel'],
        ),
        secondTraitId: data['secondTraitId'] as String?,
        secondTraitLevel:
            Zone0GameState.instance._readInt(data['secondTraitLevel']),
        isRenewed: data['isRenewed'] == true,
        renewedAt: Zone0GameState.instance._readDate(data['renewedAt']),
        renewalCount: Zone0GameState.instance._readInt(data['renewalCount']),
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
        refugeBiome: ForageMission._enumByName(
          ForageBiome.values,
          '${data['refugeBiome'] ?? ''}',
          ForageBiome.plaineRiche,
        ),
        inactiveReason: data['inactiveReason'] as String?,
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
        storedDataCells: (data['storedDataCells'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(PTibugDataCell.fromFirebase)
            .toList(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'defaultDisplayName': defaultDisplayName,
        'renamedAt': renamedAt == null ? null : Timestamp.fromDate(renamedAt!),
        'renameCount': renameCount,
        'nameHistory': nameHistory,
        'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
        'lifecycleStatus': lifecycleStatus.name,
        'reservedForSaleId': reservedForSaleId,
        'species': species.name,
        'styleVariant': styleVariant,
        'primaryColorHex': primaryColorHex,
        'motifId': motifId,
        'motifColorHex': motifColorHex,
        'traitColorHex': traitColorHex,
        'animationName': animationName,
        'createdAt': Timestamp.fromDate(createdAt),
        'assignedSlotIndex': assignedSlotIndex,
        'assignedBuildingId': assignedBuildingId,
        'storedResources': storedResources,
        'storedMaterialProduction': storedResources,
        'storedDataCells':
            storedDataCells.map((item) => item.toFirebase()).toList(),
        'level': level,
        'xp': xp,
        'traitDataId': traitDataId,
        'biologicalTraitId': biologicalTraitId,
        'biologicalTraitLevel': biologicalTraitLevel,
        'secondTraitId': secondTraitId,
        'secondTraitLevel': secondTraitLevel,
        'isRenewed': isRenewed,
        'renewedAt': renewedAt == null ? null : Timestamp.fromDate(renewedAt!),
        'renewalCount': renewalCount,
        'equippedModules': equippedModules.map((item) => item.name).toList(),
        'equippedModuleInstanceIds': equippedModuleInstanceIds,
        'biome': biome.name,
        'refugeBiome': refugeBiome.name,
        'inactiveReason': inactiveReason,
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
    this.assignedPtipoteId,
    this.assignedPtipoteName,
    this.energyCost = 0,
    this.completedAt,
  });

  final String id;
  final PTibugModuleType moduleType;
  final DateTime startedAt;
  final DateTime endsAt;
  final String? assignedPtipoteId;
  final String? assignedPtipoteName;
  final int energyCost;
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
        assignedPtipoteId: data['assignedPtipoteId'] as String?,
        assignedPtipoteName: data['assignedPtipoteName'] as String?,
        energyCost: Zone0GameState.instance._readInt(data['energyCost']),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'moduleType': moduleType.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'assignedPtipoteId': assignedPtipoteId,
        'assignedPtipoteName': assignedPtipoteName,
        'energyCost': energyCost,
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

enum CertifiedPTibugCapsuleStatus { certified, sold, archived }

class PTibugCapsule {
  const PTibugCapsule({
    required this.id,
    required this.species,
    required this.styleVariant,
    required this.displayName,
    required this.createdAt,
    this.primaryColorHex,
    this.motifId,
    this.motifColorHex,
    this.traitColorHex,
    this.animationName,
    this.biologicalTraitId,
    this.biologicalTraitLevel = 0,
    this.level = 1,
    this.xp = 0,
    this.originRefugeId,
    this.creatorPlayerId,
    this.certificationId,
    this.sourcePtibugId,
    this.secondTraitId,
    this.secondTraitLevel = 0,
    this.isEvolved = false,
    this.moduleSnapshots = const <String>[],
    this.baseValueSnapshot = 0,
    this.levelValueSnapshot = 0,
    this.traitValueSnapshot = 0,
    this.moduleValueSnapshot = 0,
    this.estimatedValueSnapshot = 0,
    this.valuationConfigVersion = 1,
    this.linkedRequestId,
    this.linkedContractId,
    this.finalSalePrice,
    this.soldAt,
    this.status = CertifiedPTibugCapsuleStatus.certified,
  });

  final String id;
  final PTibugSpecies species;
  final String styleVariant;
  final String displayName;
  final String? primaryColorHex;
  final String? motifId;
  final String? motifColorHex;
  final String? traitColorHex;
  final String? animationName;
  final String? biologicalTraitId;
  final int biologicalTraitLevel;
  final int level;
  final int xp;
  final String? originRefugeId;
  final String? creatorPlayerId;
  final String? certificationId;
  final String? sourcePtibugId;
  final String? secondTraitId;
  final int secondTraitLevel;
  final bool isEvolved;
  final List<String> moduleSnapshots;
  final int baseValueSnapshot;
  final int levelValueSnapshot;
  final int traitValueSnapshot;
  final int moduleValueSnapshot;
  final int estimatedValueSnapshot;
  final int valuationConfigVersion;
  final String? linkedRequestId;
  final String? linkedContractId;
  final int? finalSalePrice;
  final DateTime? soldAt;
  final CertifiedPTibugCapsuleStatus status;
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
        primaryColorHex: data['primaryColorHex'] as String?,
        motifId: data['motifId'] as String?,
        motifColorHex: data['motifColorHex'] as String?,
        traitColorHex: data['traitColorHex'] as String?,
        animationName: data['animationName'] as String?,
        biologicalTraitId: data['biologicalTraitId'] as String?,
        biologicalTraitLevel: Zone0GameState.instance._readInt(
          data['biologicalTraitLevel'],
        ),
        level: Zone0GameState.instance._readInt(data['level'], fallback: 1),
        xp: Zone0GameState.instance._readInt(data['xp']),
        originRefugeId: data['originRefugeId'] as String?,
        creatorPlayerId: data['creatorPlayerId'] as String?,
        certificationId: data['certificationId'] as String?,
        sourcePtibugId: data['sourcePtibugId'] as String?,
        secondTraitId: data['secondTraitId'] as String?,
        secondTraitLevel:
            Zone0GameState.instance._readInt(data['secondTraitLevel']),
        isEvolved: data['isEvolved'] == true,
        moduleSnapshots: (data['moduleSnapshots'] as List? ?? const <dynamic>[])
            .map((value) => '$value')
            .toList(),
        baseValueSnapshot:
            Zone0GameState.instance._readInt(data['baseValueSnapshot']),
        levelValueSnapshot:
            Zone0GameState.instance._readInt(data['levelValueSnapshot']),
        traitValueSnapshot:
            Zone0GameState.instance._readInt(data['traitValueSnapshot']),
        moduleValueSnapshot:
            Zone0GameState.instance._readInt(data['moduleValueSnapshot']),
        estimatedValueSnapshot:
            Zone0GameState.instance._readInt(data['estimatedValueSnapshot']),
        valuationConfigVersion: Zone0GameState.instance
            ._readInt(data['valuationConfigVersion'], fallback: 1),
        linkedRequestId: data['linkedRequestId'] as String?,
        linkedContractId: data['linkedContractId'] as String?,
        finalSalePrice: data['finalSalePrice'] as int?,
        soldAt: Zone0GameState.instance._readDate(data['soldAt']),
        status: ForageMission._enumByName(
          CertifiedPTibugCapsuleStatus.values,
          '${data['status'] ?? ''}',
          CertifiedPTibugCapsuleStatus.certified,
        ),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'species': species.name,
        'styleVariant': styleVariant,
        'displayName': displayName,
        'primaryColorHex': primaryColorHex,
        'motifId': motifId,
        'motifColorHex': motifColorHex,
        'traitColorHex': traitColorHex,
        'animationName': animationName,
        'biologicalTraitId': biologicalTraitId,
        'biologicalTraitLevel': biologicalTraitLevel,
        'level': level,
        'xp': xp,
        'originRefugeId': originRefugeId,
        'creatorPlayerId': creatorPlayerId,
        'certificationId': certificationId,
        'sourcePtibugId': sourcePtibugId,
        'secondTraitId': secondTraitId,
        'secondTraitLevel': secondTraitLevel,
        'isEvolved': isEvolved,
        'moduleSnapshots': moduleSnapshots,
        'baseValueSnapshot': baseValueSnapshot,
        'levelValueSnapshot': levelValueSnapshot,
        'traitValueSnapshot': traitValueSnapshot,
        'moduleValueSnapshot': moduleValueSnapshot,
        'estimatedValueSnapshot': estimatedValueSnapshot,
        'valuationConfigVersion': valuationConfigVersion,
        'linkedRequestId': linkedRequestId,
        'linkedContractId': linkedContractId,
        'finalSalePrice': finalSalePrice,
        'soldAt': soldAt == null ? null : Timestamp.fromDate(soldAt!),
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  PTibugCapsule copyWith({
    String? id,
    PTibugSpecies? species,
    String? styleVariant,
    String? displayName,
    String? biologicalTraitId,
    int? biologicalTraitLevel,
    int? level,
    int? xp,
    String? originRefugeId,
    String? creatorPlayerId,
    String? certificationId,
    String? sourcePtibugId,
    String? secondTraitId,
    int? secondTraitLevel,
    bool? isEvolved,
    List<String>? moduleSnapshots,
    int? baseValueSnapshot,
    int? levelValueSnapshot,
    int? traitValueSnapshot,
    int? moduleValueSnapshot,
    int? estimatedValueSnapshot,
    int? valuationConfigVersion,
    String? linkedRequestId,
    String? linkedContractId,
    int? finalSalePrice,
    DateTime? soldAt,
    CertifiedPTibugCapsuleStatus? status,
    DateTime? createdAt,
  }) =>
      PTibugCapsule(
        id: id ?? this.id,
        species: species ?? this.species,
        styleVariant: styleVariant ?? this.styleVariant,
        displayName: displayName ?? this.displayName,
        biologicalTraitId: biologicalTraitId ?? this.biologicalTraitId,
        biologicalTraitLevel: biologicalTraitLevel ?? this.biologicalTraitLevel,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        originRefugeId: originRefugeId ?? this.originRefugeId,
        creatorPlayerId: creatorPlayerId ?? this.creatorPlayerId,
        certificationId: certificationId ?? this.certificationId,
        sourcePtibugId: sourcePtibugId ?? this.sourcePtibugId,
        secondTraitId: secondTraitId ?? this.secondTraitId,
        secondTraitLevel: secondTraitLevel ?? this.secondTraitLevel,
        isEvolved: isEvolved ?? this.isEvolved,
        moduleSnapshots: moduleSnapshots ?? this.moduleSnapshots,
        baseValueSnapshot: baseValueSnapshot ?? this.baseValueSnapshot,
        levelValueSnapshot: levelValueSnapshot ?? this.levelValueSnapshot,
        traitValueSnapshot: traitValueSnapshot ?? this.traitValueSnapshot,
        moduleValueSnapshot: moduleValueSnapshot ?? this.moduleValueSnapshot,
        estimatedValueSnapshot:
            estimatedValueSnapshot ?? this.estimatedValueSnapshot,
        valuationConfigVersion:
            valuationConfigVersion ?? this.valuationConfigVersion,
        linkedRequestId: linkedRequestId ?? this.linkedRequestId,
        linkedContractId: linkedContractId ?? this.linkedContractId,
        finalSalePrice: finalSalePrice ?? this.finalSalePrice,
        soldAt: soldAt ?? this.soldAt,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
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

enum PTibugArmatureStatus { crafting, completed, cancelled }

class PTibugArmature {
  PTibugArmature({
    required this.id,
    required this.species,
    required this.startedAt,
    required this.completesAt,
    required this.materialCosts,
    required this.createdAt,
    this.status = PTibugArmatureStatus.crafting,
    this.updatedAt,
    this.assignedPtipoteId,
    this.assignedPtipoteName,
  });

  final String id;
  final PTibugSpecies species;
  final DateTime startedAt;
  final DateTime completesAt;
  final Map<String, int> materialCosts;
  final DateTime createdAt;
  PTibugArmatureStatus status;
  DateTime? updatedAt;
  final String? assignedPtipoteId;
  final String? assignedPtipoteName;
  bool get isCrafting => status == PTibugArmatureStatus.crafting;
  bool get isCompleted => status == PTibugArmatureStatus.completed;

  factory PTibugArmature.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugArmature(
        id: '${data['id'] ?? ''}',
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        completesAt: Zone0GameState.instance._readDate(data['completesAt']) ??
            DateTime.now(),
        materialCosts: Map<String, int>.fromEntries(
          (data['materialCosts'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value))),
        ),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        status: ForageMission._enumByName(
          PTibugArmatureStatus.values,
          '${data['status'] ?? ''}',
          PTibugArmatureStatus.crafting,
        ),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
        assignedPtipoteId: data['assignedPtipoteId']?.toString(),
        assignedPtipoteName: data['assignedPtipoteName']?.toString(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'species': species.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'completesAt': Timestamp.fromDate(completesAt),
        'materialCosts': materialCosts,
        'createdAt': Timestamp.fromDate(createdAt),
        'status': status.name,
        'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
        'assignedPtipoteId': assignedPtipoteId,
        'assignedPtipoteName': assignedPtipoteName,
      };
}

enum PTibugCultivationTankStatus {
  unbuilt,
  underConstruction,
  available,
  active,
  pausedMissingResources,
  completed,
}

class PTibugCultivationTank {
  PTibugCultivationTank({
    required this.id,
    required this.slotIndex,
    this.isBuilt = false,
    this.status = PTibugCultivationTankStatus.unbuilt,
    this.organicStored = 0,
    this.mineralStored = 0,
    this.energyStored = 0,
    Map<String, int>? constructionDeposits,
    this.constructionStartedAt,
    this.constructionEndsAt,
    this.currentOperationId,
  }) : constructionDeposits = constructionDeposits ?? <String, int>{};

  final String id;
  final int slotIndex;
  bool isBuilt;
  PTibugCultivationTankStatus status;
  double organicStored;
  double mineralStored;
  double energyStored;
  final Map<String, int> constructionDeposits;
  DateTime? constructionStartedAt;
  DateTime? constructionEndsAt;
  String? currentOperationId;

  factory PTibugCultivationTank.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugCultivationTank(
        id: '${data['id'] ?? ''}',
        slotIndex: Zone0GameState.instance._readInt(data['slotIndex']),
        isBuilt: data['isBuilt'] == true,
        status: ForageMission._enumByName(
          PTibugCultivationTankStatus.values,
          '${data['status'] ?? ''}',
          PTibugCultivationTankStatus.unbuilt,
        ),
        organicStored:
            Zone0GameState.instance._readDouble(data['organicStored']),
        mineralStored:
            Zone0GameState.instance._readDouble(data['mineralStored']),
        energyStored: Zone0GameState.instance._readDouble(data['energyStored']),
        constructionDeposits: Map<String, int>.fromEntries(
          (data['constructionDeposits'] as Map? ?? const <dynamic, dynamic>{})
              .entries
              .map((entry) => MapEntry('${entry.key}',
                  Zone0GameState.instance._readInt(entry.value))),
        ),
        constructionStartedAt:
            Zone0GameState.instance._readDate(data['constructionStartedAt']),
        constructionEndsAt:
            Zone0GameState.instance._readDate(data['constructionEndsAt']),
        currentOperationId: data['currentOperationId']?.toString(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'slotIndex': slotIndex,
        'isBuilt': isBuilt,
        'status': status.name,
        'organicStored': organicStored,
        'mineralStored': mineralStored,
        'energyStored': energyStored,
        'constructionDeposits': constructionDeposits,
        'constructionStartedAt': constructionStartedAt == null
            ? null
            : Timestamp.fromDate(constructionStartedAt!),
        'constructionEndsAt': constructionEndsAt == null
            ? null
            : Timestamp.fromDate(constructionEndsAt!),
        'currentOperationId': currentOperationId,
      };
}

enum PTibugCultivationOperationStatus {
  active,
  pausedMissingResources,
  completed,
  cancelled
}

class PTibugAspectMatrix {
  const PTibugAspectMatrix({
    required this.id,
    required this.sourcePTibugId,
    required this.sourceDisplayName,
    required this.species,
    required this.createdAt,
    this.primaryColorHex,
    this.motifId,
    this.motifColorHex,
    this.traitColorHex,
    this.animationName,
  });

  final String id;
  final String sourcePTibugId;
  final String sourceDisplayName;
  final PTibugSpecies species;
  final String? primaryColorHex;
  final String? motifId;
  final String? motifColorHex;
  final String? traitColorHex;
  final String? animationName;
  final DateTime createdAt;

  factory PTibugAspectMatrix.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugAspectMatrix(
        id: '${data['id'] ?? ''}',
        sourcePTibugId: '${data['sourcePTibugId'] ?? ''}',
        sourceDisplayName: '${data['sourceDisplayName'] ?? 'P’TIBUG'}',
        species: ForageMission._enumByName(PTibugSpecies.values,
            '${data['species'] ?? ''}', PTibugSpecies.scarabe),
        primaryColorHex: data['primaryColorHex'] as String?,
        motifId: data['motifId'] as String?,
        motifColorHex: data['motifColorHex'] as String?,
        traitColorHex: data['traitColorHex'] as String?,
        animationName: data['animationName'] as String?,
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'sourcePTibugId': sourcePTibugId,
        'sourceDisplayName': sourceDisplayName,
        'species': species.name,
        'primaryColorHex': primaryColorHex,
        'motifId': motifId,
        'motifColorHex': motifColorHex,
        'traitColorHex': traitColorHex,
        'animationName': animationName,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

class PTibugAspectExtractionOrder {
  PTibugAspectExtractionOrder({
    required this.id,
    required this.sourcePTibugId,
    required this.sourceDisplayName,
    required this.species,
    required this.matrixCount,
    required this.moduleCount,
    required this.startedAt,
    required this.endsAt,
    this.primaryColorHex,
    this.motifId,
    this.motifColorHex,
    this.traitColorHex,
    this.animationName,
    this.completedAt,
  });

  final String id;
  final String sourcePTibugId;
  final String sourceDisplayName;
  final PTibugSpecies species;
  final int matrixCount;
  final int moduleCount;
  final DateTime startedAt;
  final DateTime endsAt;
  final String? primaryColorHex;
  final String? motifId;
  final String? motifColorHex;
  final String? traitColorHex;
  final String? animationName;
  DateTime? completedAt;
  bool get isActive => completedAt == null;

  factory PTibugAspectExtractionOrder.fromFirebase(
          Map<dynamic, dynamic> data) =>
      PTibugAspectExtractionOrder(
        id: '${data['id'] ?? ''}',
        sourcePTibugId: '${data['sourcePTibugId'] ?? ''}',
        sourceDisplayName: '${data['sourceDisplayName'] ?? 'P’TIBUG'}',
        species: ForageMission._enumByName(PTibugSpecies.values,
            '${data['species'] ?? ''}', PTibugSpecies.scarabe),
        matrixCount: Zone0GameState.instance._readInt(data['matrixCount']),
        moduleCount: Zone0GameState.instance._readInt(data['moduleCount']),
        primaryColorHex: data['primaryColorHex'] as String?,
        motifId: data['motifId'] as String?,
        motifColorHex: data['motifColorHex'] as String?,
        traitColorHex: data['traitColorHex'] as String?,
        animationName: data['animationName'] as String?,
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'sourcePTibugId': sourcePTibugId,
        'sourceDisplayName': sourceDisplayName,
        'species': species.name,
        'matrixCount': matrixCount,
        'moduleCount': moduleCount,
        'primaryColorHex': primaryColorHex,
        'motifId': motifId,
        'motifColorHex': motifColorHex,
        'traitColorHex': traitColorHex,
        'animationName': animationName,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

class PTibugCultivationOperation {
  PTibugCultivationOperation({
    required this.id,
    required this.tankId,
    required this.type,
    required this.species,
    required this.startedAt,
    required this.lastCalculatedAt,
    required this.activeSecondsRequired,
    this.armatureId,
    this.targetPtibugId,
    this.targetTraitId,
    this.targetTraitRank,
    this.targetEvolutionLevel,
    List<PTibugAspectMatrix>? aspectMatrices,
    Map<PTibugDataFamily, int>? reservedDataCells,
    this.previousAssignmentId,
    this.activeSecondsCompleted = 0,
    this.bonusSecondsApplied = 0,
    this.status = PTibugCultivationOperationStatus.pausedMissingResources,
    this.pauseReason,
    List<DateTime>? tapSessions,
  })  : reservedDataCells = reservedDataCells ?? <PTibugDataFamily, int>{},
        aspectMatrices = aspectMatrices ?? <PTibugAspectMatrix>[],
        tapSessions = tapSessions ?? <DateTime>[];

  final String id;
  final String tankId;
  final PTibugCultivationOperationType type;
  final String? armatureId;
  final String? targetPtibugId;
  final String? targetTraitId;
  final int? targetTraitRank;
  final int? targetEvolutionLevel;
  final List<PTibugAspectMatrix> aspectMatrices;
  final Map<PTibugDataFamily, int> reservedDataCells;
  final String? previousAssignmentId;
  final PTibugSpecies species;
  final DateTime startedAt;
  DateTime lastCalculatedAt;
  final int activeSecondsRequired;
  int activeSecondsCompleted;
  int bonusSecondsApplied;
  PTibugCultivationOperationStatus status;
  String? pauseReason;
  final List<DateTime> tapSessions;
  DateTime? completedAt;
  String? resultPtibugId;
  DateTime? resultAppliedAt;

  int get activeSecondsRemaining =>
      math.max(0, activeSecondsRequired - activeSecondsCompleted);
  bool get isCompleted => status == PTibugCultivationOperationStatus.completed;

  factory PTibugCultivationOperation.fromFirebase(Map<dynamic, dynamic> data) =>
      PTibugCultivationOperation(
        id: '${data['id'] ?? ''}',
        tankId: '${data['tankId'] ?? ''}',
        type: ForageMission._enumByName(
          PTibugCultivationOperationType.values,
          '${data['type'] ?? ''}',
          PTibugCultivationOperationType.cultivation,
        ),
        species: ForageMission._enumByName(PTibugSpecies.values,
            '${data['species'] ?? ''}', PTibugSpecies.scarabe),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        lastCalculatedAt:
            Zone0GameState.instance._readDate(data['lastCalculatedAt']) ??
                DateTime.now(),
        activeSecondsRequired:
            Zone0GameState.instance._readInt(data['activeSecondsRequired']),
        activeSecondsCompleted:
            Zone0GameState.instance._readInt(data['activeSecondsCompleted']),
        armatureId: data['armatureId']?.toString(),
        targetPtibugId: data['targetPtibugId']?.toString(),
        targetTraitId: data['targetTraitId']?.toString(),
        targetTraitRank: data['targetTraitRank'] as int?,
        targetEvolutionLevel: data['targetEvolutionLevel'] as int?,
        aspectMatrices: (data['aspectMatrices'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(PTibugAspectMatrix.fromFirebase)
            .toList(),
        reservedDataCells: <PTibugDataFamily, int>{
          for (final family in PTibugDataFamily.values)
            family: Zone0GameState.instance._readInt(
              (data['reservedDataCells'] as Map?)?[family.name],
            ),
        }..removeWhere((_, value) => value <= 0),
        previousAssignmentId: data['previousAssignmentId']?.toString(),
        bonusSecondsApplied:
            Zone0GameState.instance._readInt(data['bonusSecondsApplied']),
        status: ForageMission._enumByName(
            PTibugCultivationOperationStatus.values,
            '${data['status'] ?? ''}',
            PTibugCultivationOperationStatus.pausedMissingResources),
        pauseReason: data['pauseReason']?.toString(),
        tapSessions: (data['tapSessions'] as List? ?? const <dynamic>[])
            .map(Zone0GameState.instance._readDate)
            .whereType<DateTime>()
            .toList(),
      )
        ..completedAt = Zone0GameState.instance._readDate(data['completedAt'])
        ..resultPtibugId = data['resultPtibugId']?.toString()
        ..resultAppliedAt =
            Zone0GameState.instance._readDate(data['resultAppliedAt']);

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'tankId': tankId,
        'type': type.name,
        'armatureId': armatureId,
        'targetPtibugId': targetPtibugId,
        'targetTraitId': targetTraitId,
        'targetTraitRank': targetTraitRank,
        'targetEvolutionLevel': targetEvolutionLevel,
        'aspectMatrices':
            aspectMatrices.map((matrix) => matrix.toFirebase()).toList(),
        'reservedDataCells': <String, int>{
          for (final entry in reservedDataCells.entries)
            entry.key.name: entry.value,
        },
        'previousAssignmentId': previousAssignmentId,
        'species': species.name,
        'startedAt': Timestamp.fromDate(startedAt),
        'lastCalculatedAt': Timestamp.fromDate(lastCalculatedAt),
        'activeSecondsRequired': activeSecondsRequired,
        'activeSecondsCompleted': activeSecondsCompleted,
        'bonusSecondsApplied': bonusSecondsApplied,
        'status': status.name,
        'pauseReason': pauseReason,
        'tapSessions': tapSessions.map(Timestamp.fromDate).toList(),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'resultPtibugId': resultPtibugId,
        'resultAppliedAt': resultAppliedAt == null
            ? null
            : Timestamp.fromDate(resultAppliedAt!),
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

class TowerBiomeResearch {
  TowerBiomeResearch({
    required this.id,
    required this.biome,
    required this.theoreticalHours,
    required this.startedAt,
    required this.endsAt,
    this.completedAt,
  });

  final String id;
  final ForageBiome biome;
  final int theoreticalHours;
  final DateTime startedAt;
  final DateTime endsAt;
  DateTime? completedAt;
  bool get isActive => completedAt == null;

  factory TowerBiomeResearch.fromFirebase(Map<dynamic, dynamic> data) =>
      TowerBiomeResearch(
        id: '${data['id'] ?? ''}',
        biome: ForageMission._enumByName(
          ForageBiome.values,
          '${data['biome'] ?? ''}',
          ForageBiome.plaineRiche,
        ),
        theoreticalHours: Zone0GameState.instance._readInt(
          data['theoreticalHours'],
          fallback: 1,
        ),
        startedAt: Zone0GameState.instance._readDate(data['startedAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        completedAt: Zone0GameState.instance._readDate(data['completedAt']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'biome': biome.name,
        'theoreticalHours': theoreticalHours,
        'startedAt': Timestamp.fromDate(startedAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}

enum BiomeDiscoveryStatus { discovered, exploring, unlocked }

class LisiereTerritoryZone {
  LisiereTerritoryZone({
    required this.zoneId,
    required this.biome,
    required this.terrainTags,
    this.buildingId,
    this.buildingLevel = 0,
    this.edibleForestInstalled = false,
    this.mycelialNetworkInstalled = false,
    this.calciumBasinInstalled = false,
    this.vatCount = 1,
    this.vatEfficiencyMultiplier = 1,
    this.organicProductionRemainder = 0,
    this.organicReserve = 0,
    this.lithocultureMineralTank = 0,
    this.lithocultureCycleStartedAt,
    this.calciumOrganicTank = 0,
    this.calciumWaterTank = 0,
    this.calciumMineralReserve = 0,
    this.calciumProductionHourRemainder = 0,
    this.myceliumProductionRemainder = 0,
    this.lastProductionResolvedAt,
    this.updatedAt,
  });
  factory LisiereTerritoryZone.initial(ForageBiome biome) =>
      LisiereTerritoryZone(
        zoneId: biome.name,
        biome: biome,
        terrainTags: <String>{
          if (biome == ForageBiome.bassinMineral) 'mineralBasin' else 'normal'
        },
      );
  factory LisiereTerritoryZone.fromFirebase(
          ForageBiome biome, Map<dynamic, dynamic> data) =>
      LisiereTerritoryZone(
        zoneId: '${data['zoneId'] ?? biome.name}',
        biome: biome,
        terrainTags: ((data['terrainTags'] as List?) ?? const <dynamic>[])
            .map((item) => '$item')
            .toSet()
          ..addAll(biome == ForageBiome.bassinMineral
              ? <String>{'mineralBasin'}
              : <String>{'normal'}),
        buildingId: data['buildingId'] as String?,
        buildingLevel: ForageMission._readStaticInt(data['buildingLevel']),
        edibleForestInstalled: data['edibleForestInstalled'] == true,
        mycelialNetworkInstalled: data['mycelialNetworkInstalled'] == true,
        calciumBasinInstalled: data['calciumBasinInstalled'] == true,
        vatCount: math.max(1, ForageMission._readStaticInt(data['vatCount'])),
        vatEfficiencyMultiplier:
            (data['vatEfficiencyMultiplier'] as num?)?.toDouble() ?? 1,
        organicProductionRemainder:
            (data['organicProductionRemainder'] as num?)?.toDouble() ?? 0,
        organicReserve: ForageMission._readStaticInt(data['organicReserve']),
        lithocultureMineralTank:
            ForageMission._readStaticInt(data['lithocultureMineralTank']),
        lithocultureCycleStartedAt:
            ForageMission._readDate(data['lithocultureCycleStartedAt']),
        calciumOrganicTank:
            ForageMission._readStaticInt(data['calciumOrganicTank']),
        calciumWaterTank:
            ForageMission._readStaticInt(data['calciumWaterTank']),
        calciumMineralReserve:
            ForageMission._readStaticInt(data['calciumMineralReserve']),
        calciumProductionHourRemainder:
            (data['calciumProductionHourRemainder'] as num?)?.toDouble() ?? 0,
        myceliumProductionRemainder:
            (data['myceliumProductionRemainder'] as num?)?.toDouble() ?? 0,
        lastProductionResolvedAt:
            ForageMission._readDate(data['lastProductionResolvedAt']),
        updatedAt: ForageMission._readDate(data['updatedAt']),
      );
  final String zoneId;
  final ForageBiome biome;
  final Set<String> terrainTags;
  String? buildingId;
  int buildingLevel;
  bool edibleForestInstalled;
  bool mycelialNetworkInstalled;
  bool calciumBasinInstalled;
  int vatCount;
  double vatEfficiencyMultiplier;
  double organicProductionRemainder;
  int organicReserve;
  int lithocultureMineralTank;
  DateTime? lithocultureCycleStartedAt;
  int calciumOrganicTank;
  int calciumWaterTank;
  int calciumMineralReserve;
  double calciumProductionHourRemainder;
  double myceliumProductionRemainder;
  DateTime? lastProductionResolvedAt;
  DateTime? updatedAt;
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'zoneId': zoneId,
        'biome': biome.name,
        'terrainTags': terrainTags.toList(),
        'buildingId': buildingId,
        'buildingLevel': buildingLevel,
        'edibleForestInstalled': edibleForestInstalled,
        'mycelialNetworkInstalled': mycelialNetworkInstalled,
        'calciumBasinInstalled': calciumBasinInstalled,
        'vatCount': vatCount,
        'vatEfficiencyMultiplier': vatEfficiencyMultiplier,
        'organicProductionRemainder': organicProductionRemainder,
        'organicReserve': organicReserve,
        'lithocultureMineralTank': lithocultureMineralTank,
        'lithocultureCycleStartedAt': lithocultureCycleStartedAt == null
            ? null
            : Timestamp.fromDate(lithocultureCycleStartedAt!),
        'calciumOrganicTank': calciumOrganicTank,
        'calciumWaterTank': calciumWaterTank,
        'calciumMineralReserve': calciumMineralReserve,
        'calciumProductionHourRemainder': calciumProductionHourRemainder,
        'myceliumProductionRemainder': myceliumProductionRemainder,
        'lastProductionResolvedAt': lastProductionResolvedAt == null
            ? null
            : Timestamp.fromDate(lastProductionResolvedAt!),
        'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      };
}

class LithoculturePreview {
  const LithoculturePreview(
      this.organicOutput, this.mineralCost, this.wasteCost);
  final int organicOutput;
  final int mineralCost;
  final int wasteCost;
}

class CampWasteDailyReport {
  CampWasteDailyReport(
      {required this.reportDate,
      required this.createdAt,
      this.domesticWasteGenerated = 0,
      this.technicalWasteGenerated = 0,
      this.wasteRecycled = 0});
  factory CampWasteDailyReport.fromFirebase(Map<dynamic, dynamic> data) =>
      CampWasteDailyReport(
        reportDate: '${data['reportDate'] ?? ''}',
        createdAt: ForageMission._readDate(data['createdAt']) ?? DateTime.now(),
        domesticWasteGenerated:
            ForageMission._readStaticInt(data['domesticWasteGenerated']),
        technicalWasteGenerated:
            ForageMission._readStaticInt(data['technicalWasteGenerated']),
        wasteRecycled: ForageMission._readStaticInt(data['wasteRecycled']),
      );
  final String reportDate;
  final DateTime createdAt;
  int domesticWasteGenerated;
  int technicalWasteGenerated;
  int wasteRecycled;
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'reportDate': reportDate,
        'createdAt': Timestamp.fromDate(createdAt),
        'domesticWasteGenerated': domesticWasteGenerated,
        'technicalWasteGenerated': technicalWasteGenerated,
        'wasteRecycled': wasteRecycled,
      };
}

class RecyclerBatchSnapshot {
  const RecyclerBatchSnapshot(
      {required this.ratios, required this.orientationModuleActive});
  factory RecyclerBatchSnapshot.fromRatios(List<int> ratios, bool active) =>
      RecyclerBatchSnapshot(
          ratios: List<int>.from(ratios), orientationModuleActive: active);
  factory RecyclerBatchSnapshot.fromFirebase(Map<dynamic, dynamic> data) =>
      RecyclerBatchSnapshot(
        ratios: ((data['ratios'] as List?) ?? const <dynamic>[])
            .map((item) => ForageMission._readStaticInt(item))
            .toList(),
        orientationModuleActive: data['orientationModuleActive'] == true,
      );
  final List<int> ratios;
  final bool orientationModuleActive;
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'ratios': ratios,
        'orientationModuleActive': orientationModuleActive,
      };
}

class BiomeSecurityState {
  BiomeSecurityState({
    required this.biome,
    required this.status,
    this.localSecurity = 0,
    this.explorationProgress = 0,
    // Keep a const-compatible fallback for legacy states; loaded settings clamp it.
    this.wasteLevel = 10,
    this.biomassPercent = 100,
    this.lastPatrolAt,
    this.lastMissionAt,
    this.lastDecayAt,
    this.lastWasteRegenerationAt,
    this.lastBiomassRegenerationAt,
    this.lastBiomassRevitalizedAt,
    this.researchProgress = 0,
    this.lastResearchDecayAt,
  });

  factory BiomeSecurityState.initial(ForageBiome biome) => BiomeSecurityState(
        biome: biome,
        status: biome == ForageBiome.plaineRiche
            ? BiomeDiscoveryStatus.unlocked
            : BiomeDiscoveryStatus.discovered,
        biomassPercent: lisiereForageConfig.biomass.maximumPercent,
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
        wasteLevel: data.containsKey('wasteLevel')
            ? ForageMission._readStaticInt(data['wasteLevel'])
                .clamp(0, defaultLisiereForageConfig.wasteLevelMax)
                .toInt()
            : defaultLisiereForageConfig.wasteLevelMax,
        // Existing biomes begin fully preserved. Avoid retroactive recovery
        // while still making their future Biomass persist independently.
        biomassPercent: data.containsKey('biomassPercent')
            ? ForageMission._readStaticInt(data['biomassPercent'])
                .clamp(0, lisiereForageConfig.biomass.maximumPercent)
                .toInt()
            : lisiereForageConfig.biomass.maximumPercent,
        lastPatrolAt: ForageMission._readDate(data['lastPatrolAt']),
        lastMissionAt: ForageMission._readDate(data['lastMissionAt']),
        lastDecayAt: ForageMission._readDate(data['lastDecayAt']),
        lastWasteRegenerationAt: ForageMission._readDate(
          data['lastWasteRegenerationAt'],
        ),
        lastBiomassRegenerationAt: ForageMission._readDate(
          data['lastBiomassRegenerationAt'],
        ),
        lastBiomassRevitalizedAt: ForageMission._readDate(
          data['lastBiomassRevitalizedAt'],
        ),
        researchProgress: ForageMission._readStaticInt(data['researchProgress'])
            .clamp(0, 100)
            .toInt(),
        lastResearchDecayAt:
            ForageMission._readDate(data['lastResearchDecayAt']),
      );

  final ForageBiome biome;
  BiomeDiscoveryStatus status;
  int localSecurity;
  int explorationProgress;
  int wasteLevel;
  int biomassPercent;
  DateTime? lastPatrolAt;
  DateTime? lastMissionAt;
  DateTime? lastDecayAt;
  DateTime? lastWasteRegenerationAt;
  DateTime? lastBiomassRegenerationAt;
  DateTime? lastBiomassRevitalizedAt;
  int researchProgress;
  DateTime? lastResearchDecayAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'securitySchema': 2,
        'status': status.name,
        'localSecurity': localSecurity,
        'explorationProgress': explorationProgress,
        'wasteLevel': wasteLevel,
        'biomassPercent': biomassPercent,
        'lastPatrolAt':
            lastPatrolAt == null ? null : Timestamp.fromDate(lastPatrolAt!),
        'lastMissionAt':
            lastMissionAt == null ? null : Timestamp.fromDate(lastMissionAt!),
        'lastDecayAt':
            lastDecayAt == null ? null : Timestamp.fromDate(lastDecayAt!),
        'lastWasteRegenerationAt': lastWasteRegenerationAt == null
            ? null
            : Timestamp.fromDate(lastWasteRegenerationAt!),
        'lastBiomassRegenerationAt': lastBiomassRegenerationAt == null
            ? null
            : Timestamp.fromDate(lastBiomassRegenerationAt!),
        'lastBiomassRevitalizedAt': lastBiomassRevitalizedAt == null
            ? null
            : Timestamp.fromDate(lastBiomassRevitalizedAt!),
        'researchProgress': researchProgress,
        'lastResearchDecayAt': lastResearchDecayAt == null
            ? null
            : Timestamp.fromDate(lastResearchDecayAt!),
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

class GlobalWeatherBiomeImpact {
  GlobalWeatherBiomeImpact({
    required this.biome,
    required this.isAffected,
    this.localImpactLevel = 'none',
    this.localImpactMultiplier = 0,
    this.sensitivityMultiplier = 0,
    this.displayReason,
  });

  final ForageBiome biome;
  final bool isAffected;
  final String localImpactLevel;
  final double localImpactMultiplier;
  final double sensitivityMultiplier;
  final String? displayReason;

  factory GlobalWeatherBiomeImpact.fromFirebase(Map<dynamic, dynamic> data) =>
      GlobalWeatherBiomeImpact(
        biome: ForageMission._enumByName(
          ForageBiome.values,
          '${data['biome'] ?? ''}',
          ForageBiome.plaineRiche,
        ),
        isAffected: data['isAffected'] == true,
        localImpactLevel: '${data['localImpactLevel'] ?? 'none'}',
        localImpactMultiplier:
            (data['localImpactMultiplier'] as num?)?.toDouble() ?? 0,
        sensitivityMultiplier:
            (data['sensitivityMultiplier'] as num?)?.toDouble() ?? 0,
        displayReason: data['displayReason'] as String?,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'biome': biome.name,
        'isAffected': isAffected,
        'localImpactLevel': localImpactLevel,
        'localImpactMultiplier': localImpactMultiplier,
        'sensitivityMultiplier': sensitivityMultiplier,
        'displayReason': displayReason,
      };
}

class GlobalWeatherEvent {
  GlobalWeatherEvent({
    required this.id,
    required this.type,
    required this.intensity,
    required this.plannedAt,
    required this.announcedAt,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.affectedBiomes,
    required this.seed,
    this.consequencesResolved = false,
    this.preparationMissionId,
  });

  final String id;
  final TowerWeatherType type;
  final GlobalWeatherIntensity intensity;
  final DateTime plannedAt;
  final DateTime announcedAt;
  final DateTime startsAt;
  final DateTime endsAt;
  GlobalWeatherEventStatus status;
  final List<GlobalWeatherBiomeImpact> affectedBiomes;
  final int seed;
  bool consequencesResolved;
  String? preparationMissionId;

  bool isBiomeAffected(ForageBiome biome) =>
      affectedBiomes
          .where((item) => item.biome == biome)
          .firstOrNull
          ?.isAffected ??
      false;
  GlobalWeatherBiomeImpact impactFor(ForageBiome biome) =>
      affectedBiomes.where((item) => item.biome == biome).firstOrNull ??
      GlobalWeatherBiomeImpact(biome: biome, isAffected: false);

  factory GlobalWeatherEvent.fromFirebase(Map<dynamic, dynamic> data) =>
      GlobalWeatherEvent(
        id: '${data['id'] ?? ''}',
        type: ForageMission._enumByName(TowerWeatherType.values,
            '${data['type'] ?? ''}', TowerWeatherType.calm),
        intensity: ForageMission._enumByName(GlobalWeatherIntensity.values,
            '${data['intensity'] ?? ''}', GlobalWeatherIntensity.calm),
        plannedAt: Zone0GameState.instance._readDate(data['plannedAt']) ??
            DateTime.now(),
        announcedAt: Zone0GameState.instance._readDate(data['announcedAt']) ??
            DateTime.now(),
        startsAt: Zone0GameState.instance._readDate(data['startsAt']) ??
            DateTime.now(),
        endsAt:
            Zone0GameState.instance._readDate(data['endsAt']) ?? DateTime.now(),
        status: ForageMission._enumByName(GlobalWeatherEventStatus.values,
            '${data['status'] ?? ''}', GlobalWeatherEventStatus.planned),
        affectedBiomes: (data['affectedBiomes'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(GlobalWeatherBiomeImpact.fromFirebase)
            .toList(),
        seed: Zone0GameState.instance._readInt(data['seed']),
        consequencesResolved: data['consequencesResolved'] == true,
        preparationMissionId: data['preparationMissionId'] as String?,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'intensity': intensity.name,
        'plannedAt': Timestamp.fromDate(plannedAt),
        'announcedAt': Timestamp.fromDate(announcedAt),
        'startsAt': Timestamp.fromDate(startsAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'status': status.name,
        'affectedBiomes':
            affectedBiomes.map((item) => item.toFirebase()).toList(),
        'seed': seed,
        'consequencesResolved': consequencesResolved,
        'preparationMissionId': preparationMissionId,
      };
}

class WeatherAlert {
  WeatherAlert({
    required this.id,
    required this.type,
    required this.startsAt,
    required this.endsAt,
    this.preparationCompleted = false,
    this.reportSent = false,
    this.manual = false,
    this.globalWeatherEventId,
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
  final String? globalWeatherEventId;
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
        globalWeatherEventId: data['globalWeatherEventId'] as String?,
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
        'globalWeatherEventId': globalWeatherEventId,
        'requestedItem': requestedItem,
        'requestedAmount': requestedAmount,
      };
}

enum MerchantOfferKind {
  plan,
  speciesPattern,
  researchPattern,
  specializedDataCell,
  neutralDataCell,
  workshopItem,
  module,
  capsule,
}

class MerchantOffer {
  MerchantOffer({
    required this.planName,
    required this.price,
    this.purchased = false,
    this.pTibugSpecies,
    this.kind = MerchantOfferKind.plan,
    this.patternId,
    this.dominantDataFamily,
    this.itemName,
    this.itemAmount = 1,
    int? remainingItemAmount,
    this.moduleType,
    this.capsule,
    this.dataCell,
  }) : remainingItemAmount = remainingItemAmount ?? itemAmount;
  final String planName;
  final int price;
  bool purchased;
  final PTibugSpecies? pTibugSpecies;
  final MerchantOfferKind kind;
  final String? patternId;
  final PTibugDataFamily? dominantDataFamily;
  final String? itemName;
  final int itemAmount;
  int remainingItemAmount;
  final PTibugModuleType? moduleType;
  final PTibugCapsule? capsule;
  final PTibugDataCell? dataCell;

  bool get isUnavailable =>
      purchased ||
      (kind == MerchantOfferKind.workshopItem && remainingItemAmount <= 0);

  int priceForQuantity(int quantity) =>
      kind == MerchantOfferKind.workshopItem ? price * quantity : price;

  factory MerchantOffer.fromFirebase(Map<dynamic, dynamic> data) =>
      MerchantOffer(
        planName: '${data['planName'] ?? 'Offre du Sourcier'}',
        price: Zone0GameState.instance._readInt(data['price']),
        purchased: data['purchased'] == true,
        pTibugSpecies: data['pTibugSpecies'] == null
            ? null
            : ForageMission._enumByName(
                PTibugSpecies.values,
                '${data['pTibugSpecies']}',
                PTibugSpecies.scarabe,
              ),
        kind: ForageMission._enumByName(
          MerchantOfferKind.values,
          '${data['kind'] ?? ''}',
          MerchantOfferKind.plan,
        ),
        patternId: data['patternId'] as String?,
        dominantDataFamily: data['dominantDataFamily'] == null
            ? null
            : ForageMission._enumByName(
                PTibugDataFamily.values,
                '${data['dominantDataFamily']}',
                PTibugDataFamily.organique,
              ),
        itemName: data['itemName'] as String?,
        itemAmount: Zone0GameState.instance._readInt(
          data['itemAmount'],
          fallback: 1,
        ),
        remainingItemAmount: Zone0GameState.instance._readInt(
          data['remainingItemAmount'],
          fallback:
              Zone0GameState.instance._readInt(data['itemAmount'], fallback: 1),
        ),
        moduleType: data['moduleType'] == null
            ? null
            : ForageMission._enumByName(
                PTibugModuleType.values,
                '${data['moduleType']}',
                PTibugModuleType.ailes,
              ),
        capsule: data['capsule'] is Map
            ? PTibugCapsule.fromFirebase(data['capsule'] as Map)
            : null,
        dataCell: data['dataCell'] is Map
            ? PTibugDataCell.fromFirebase(data['dataCell'] as Map)
            : null,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'planName': planName,
        'price': price,
        'purchased': purchased,
        'pTibugSpecies': pTibugSpecies?.name,
        'kind': kind.name,
        'patternId': patternId,
        'dominantDataFamily': dominantDataFamily?.name,
        'itemName': itemName,
        'itemAmount': itemAmount,
        'remainingItemAmount': remainingItemAmount,
        'moduleType': moduleType?.name,
        'capsule': capsule?.toFirebase(),
        'dataCell': dataCell?.toFirebase(),
      };
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
    required this.type,
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
    final type = _enumByName(
      ForageMissionType.values,
      '${data['type'] ?? ''}',
      ForageMissionType.harvest,
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
      type: type,
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

  /// Old missions omit this field and are migrated as harvest missions.
  final ForageMissionType type;
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
      'type': type.name,
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
    String? id,
    required String message,
    String? sourceBuildingId,
    Zone0MessageMailbox mailbox = Zone0MessageMailbox.companions,
    String? subject,
    String? concerned,
    String? summary,
  }) {
    final now = DateTime.now();
    return PtipoteMissionReport(
      id: id ?? 'system-${now.microsecondsSinceEpoch}',
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
