import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/notification_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'building_construction_config.dart';
import 'camp_heart_config.dart';
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

String _ptibugDataFamilyLabel(PTibugDataFamily family) => switch (family) {
      PTibugDataFamily.organique => 'Organique',
      PTibugDataFamily.minerale => 'Minérale',
      PTibugDataFamily.mycelienne => 'Mycélienne',
      PTibugDataFamily.toxine => 'Toxine',
      PTibugDataFamily.biomimetisme => 'Biomimétisme',
      PTibugDataFamily.energie => 'Énergie',
      PTibugDataFamily.comportementInsectoide => 'Comportement insectoïde',
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
  final Map<String, CommunityProjectProgress> communityProjects =
      <String, CommunityProjectProgress>{};
  final Set<String> resolvedWeatherStockLossEventIds = <String>{};
  WeatherStockIncident? lastWeatherStockIncident;
  int protectedBatteryChestLevel = 0;
  CommunityConstructionThanks? communityConstructionThanks;
  int plaineNurseryLevel = 0;
  PTibugCreationOrder? pTibugCreationOrder;
  int securityTowerLevel = 0;
  int marketLevel = 0;
  int currentPopulation = kernelConfig.startingPopulation;
  int kernelTrustLevel = 1;
  int kernelTrustXp = 0;
  int bioBatteries = kernelConfig.startingBioBatteries;
  /// Monnaie fine du Marché. Dix bio-piles sont automatiquement compactées
  /// en une bio-batterie, sans modifier les coûts existants en batteries.
  int bioPiles = 0;
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
  // Compatibilité de lecture uniquement : les anciennes sauvegardes pouvaient
  // contenir un cycle de vente autonome. Les ventes passent désormais
  // exclusivement par une demande habitant ou un contrat du Sourcier.
  DateTime? marketNextSaleAt;
  DateTime? marketNextRequestAt;
  DateTime? marketLastWorkTickAt;
  DateTime? marketLastXpTickAt;
  int marketXpEarnedThisAssignment = 0;
  DateTime? lastManualTowerRechargeAt;
  DateTime? merchantAvailableUntil;
  DateTime? merchantNextArrivalAt;
  DateTime? merchantCallRequestedAt;
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
  Future<void> _firebaseWriteQueue = Future<void>.value();
  int _firebaseSyncCount = 0;

  /// Empêche les actions de simulation d'écraser les données avant le chargement.
  bool get hasLoadedFromFirebase => _loadedFromFirebase;

  bool get isFablabBuilt => atelierLevel >= fablabConfig.cuisineUnlockLevel;
  bool get isSecurityTowerBuilt => securityTowerLevel >= 1;
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
    final territory = territoryBuildingForId(buildingId);
    if (territory != null) return territory.level;
    return switch (buildingId) {
      'fablab' || 'atelier' => atelierLevel,
      'cuisine' => cuisineLevel,
      'recycler' => recyclerLevel,
      'generator' => 1,
      'market' => marketLevel,
      'securityTower' => securityTowerLevel,
      'campHeart' => _lastKnownCampHeartLevel,
      _ => 1,
    };
  }

  ForageBiome buildingBiomeForViability(String buildingId) =>
      territoryBuildingForId(buildingId)?.biome ?? ForageBiome.plaineRiche;

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
    return const Zone0ActionResult(
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

  Zone0ActionResult repairBuilding(String buildingId) {
    final viability = viabilityForBuilding(buildingId);
    final config = towerOperationsConfig.buildingViability;
    if (viability.current >= viability.maximum) {
      return const Zone0ActionResult(
          success: false, message: 'La Viabilité est déjà maximale.');
    }
    final costs = <String, int>{
      'Organique': config.repairOrganicCost,
      'Minéral': config.repairMineralCost
    };
    if (!hasResources(costs) || !removeResources(costs)) {
      return const Zone0ActionResult(
          success: false, message: 'Ressources insuffisantes pour réparer.');
    }
    viability.restore(config.repairGain);
    if (viability.current >= viability.maximum) {
      _reportBuildingViability(buildingId, 'est entièrement réparé.');
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: '+${config.repairGain}% de Viabilité.');
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
      'generator',
      'campHeart',
      ...activePTibugTerritories.map((building) => building.id),
    };
    final config = towerOperationsConfig.buildingViability;
    for (final buildingId in candidates) {
      if (constructionProjects[buildingId]?.isInProgress == true) continue;
      final state = viabilityForBuilding(buildingId);
      if (state.lastDamageEventId == event.id) continue;
      final impact = event.affectedBiomes
          .where((item) => item.biome == buildingBiomeForViability(buildingId))
          .firstOrNull;
      state.lastDamageEventId = event.id;
      if (impact == null || !impact.isAffected) continue;
      final raw = config.damageFor(event.type, event.intensity) *
          impact.localImpactMultiplier;
      final protection =
          (structuralProtectionReductionPercent(buildingId, event.type) +
                  globalWeatherProtectionPercent(event.type))
              .clamp(0, config.protectionCapPercent);
      final reduced = raw * (1 - protection / 100);
      final damage = reduced.ceil();
      if (damage <= 0) continue;
      final previous = state.current;
      state.current = math.max(0, state.current - damage);
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
  }

  void _migrateResidentsAndHouses() {
    final targetResidents = math.max(0, currentPopulation);
    while (residents.length < targetResidents) {
      final index = residents.length;
      residents.add(Zone0Resident(
        id: 'resident-migrated-${index + 1}',
        displayName: _residentNameFor(index),
        createdAt: DateTime.now(),
      ));
    }
    // Do not destroy identities when a temporary population value falls.
    while (residentHouses.length < housingUnits) {
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
      house.residentIds.removeWhere(
        (id) => !residents.any((resident) => resident.id == id),
      );
    }
    for (final resident in residents) {
      final assigned = residentHouseForId(resident.houseId);
      if (assigned != null && assigned.residentIds.contains(resident.id))
        continue;
      resident.houseId = null;
      final house = residentHouses
          .where((item) => item.residentIds.length < item.capacity)
          .firstOrNull;
      if (house != null) {
        house.residentIds.add(resident.id);
        resident.houseId = house.id;
      }
    }
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

  Zone0ActionResult repairResidentHouse(String houseId) {
    final house = residentHouseForId(houseId);
    if (house == null)
      return const Zone0ActionResult(
          success: false, message: 'Maison introuvable.');
    if (house.currentViability >= house.maximumViability) {
      return const Zone0ActionResult(
          success: false, message: 'La maison est déjà en bon état.');
    }
    final costs = <String, int>{
      'Organique': housingConfig.houseRepairOrganicCost,
      'Minéral': housingConfig.houseRepairMineralCost,
    };
    if (!hasResources(costs) || !removeResources(costs)) {
      return const Zone0ActionResult(
          success: false,
          message: 'Ressources insuffisantes pour réparer cette maison.');
    }
    house.currentViability = math.min(house.maximumViability,
        house.currentViability + housingConfig.houseRepairGain);
    house.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true,
        message:
            'Maison réparée : +${housingConfig.houseRepairGain}% de Viabilité.');
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
        housingConfig.houseProtectionSlots) {
      return const Zone0ActionResult(
          success: false,
          message: 'Aucun emplacement de protection disponible.');
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
    for (final house in residentHouses) {
      if (house.lastDamageEventId == event.id) continue;
      house.lastDamageEventId = event.id;
      final impact = event.affectedBiomes
          .where((item) => item.biome == house.biome)
          .firstOrNull;
      if (impact == null || !impact.isAffected) continue;
      final protection = (house.protectionReductionPercent(event.type, config) +
              globalWeatherProtectionPercent(event.type))
          .clamp(0, config.protectionCapPercent);
      final raw = config.damageFor(event.type, event.intensity) *
          impact.localImpactMultiplier;
      house.currentViability = math
          .max(
            0,
            house.currentViability - (raw * (1 - protection / 100)).ceil(),
          )
          .toInt();
      house.updatedAt = DateTime.now();
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
    for (final item in perishable) {
      final loss = (resourceAmount(item) * effectiveRate / 100).floor();
      if (loss > 0) {
        removeResource(item, loss);
        waste += loss;
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
        batteriesLost: batteriesLost,
        protectionPercent: reduction,
        resolvedAt: DateTime.now());
    if (waste > 0 || batteriesLost > 0)
      reports.add(PtipoteMissionReport.system(
          message:
              'Intempérie : $waste ressource(s) transformée(s) en Déchets, $batteriesLost Bio-batterie(s) exposée(s) perdue(s).',
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
        'generator' => 'Bio-générateur',
        'market' => 'Marché',
        'securityTower' => 'Tour',
        'campHeart' => 'Cœur du camp',
        _ => territoryBuildingForId(buildingId)?.kind ==
                PTibugTerritoryKind.nursery
            ? 'Nurserie'
            : territoryBuildingForId(buildingId) != null
                ? 'Refuge P’TIBUG'
                : 'Bâtiment',
      };

  void _migrateBuildingViability() {
    final ids = <String>{
      if (isFablabBuilt) 'fablab',
      if (atelierLevel > 0) 'atelier',
      if (cuisineLevel > 0) 'cuisine',
      if (recyclerLevel > 0) 'recycler',
      if (isMarketBuilt) 'market',
      if (isSecurityTowerBuilt) 'securityTower',
      'generator',
      'campHeart',
      ...activePTibugTerritories.map((building) => building.id),
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

  int get residentHappiness =>
      residents.where((resident) => resident.isActive).isEmpty
          ? housingConfig.neutralHappinessWithoutResidents
          : (residents
                      .where((resident) => resident.isActive)
                      .map(residentHappinessFor)
                      .reduce((sum, value) => sum + value) /
                  residents.where((resident) => resident.isActive).length)
              .round();

  ResidentHouse? residentHouseForId(String? houseId) => houseId == null
      ? null
      : residentHouses.where((house) => house.id == houseId).firstOrNull;

  int residentHappinessFor(Zone0Resident resident) {
    final house = residentHouseForId(resident.houseId);
    final homePenalty = house != null && house.currentViability < 50
        ? housingConfig.houseViabilityDamageHappinessPercent
        : 0;
    final unhousedPenalty = resident.houseId == null
        ? housingConfig.wellbeingPenaltyPerUnhousedResident
        : 0;
    return (resident.baseHappiness +
            resident.temporaryHappinessModifier -
            homePenalty -
            unhousedPenalty)
        .clamp(0, 100);
  }

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
  int get marketShopLimit => marketConfig.specializedShopSlotsForLevel(marketLevel);
  int get marketShopCount =>
      1 + marketShops.where((shop) => !shop.isPrimary).length;

  MarketShop? marketShopById(String id) =>
      marketShops.where((shop) => shop.id == id).firstOrNull;

  int marketShopStockLimit(String shopId) => shopId == primaryMarketShopId
      ? (primaryMarketShopLevel >= 2 ? 6 : 3)
      : marketShopById(shopId)?.stockSlots ?? 0;

  List<Zone0InventoryStack>? marketStockForShop(String shopId) =>
      shopId == primaryMarketShopId ? marketStock : marketShopById(shopId)?.stock;

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
        _ => MarketDistributorType.general,
      };
  }

  /// Prépare l'état de construction sans fabriquer le distributeur. Cette
  /// étape permet d'afficher les dépôts progressifs de chaque magasin.
  MarketDistributorState prepareMarketDistributorForShop(String shopId) =>
      _ensureMarketDistributorForShop(shopId);

  bool marketShopAccepts(String shopId, String resource) =>
      shopId == primaryMarketShopId
          ? MarketShop(id: primaryMarketShopId, specialization: primaryMarketShopSpecialization, level: primaryMarketShopLevel)
              .accepts(resource)
          : (marketShopById(shopId)?.accepts(resource) ?? false);

  PTibugSpecies? _marketPTibugSpecies(String resource) => switch (resource) {
        'P’TIBUG Scarabé' => PTibugSpecies.scarabe,
        'P’TIBUG Hyme' => PTibugSpecies.hyme,
        'P’TIBUG Arac' => PTibugSpecies.arac,
        _ => null,
      };

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
    return pTibugs.where((bug) => bug.species == species && _isBasicMarketPTibug(bug)).length;
  }

  bool _consumeMarketPTibugs(String resource, int amount) {
    final species = _marketPTibugSpecies(resource);
    if (species == null) return false;
    final candidates = pTibugs
        .where((bug) => bug.species == species && _isBasicMarketPTibug(bug))
        .take(amount)
        .toList(growable: false);
    if (candidates.length < amount) return false;
    pTibugs.removeWhere((bug) => candidates.contains(bug));
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
    if (!isBuildingOperational('generator')) {
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
              buildingProductionMultiplier('generator'))
          .floor(),
    );
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
    if (figurine == null) {
      energyUnits -= 1;
    }
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
    if (!const <String>{'restaurant', 'home', 'equipment', 'ptibug'}
        .contains(specialization)) {
      return const Zone0ActionResult(
          success: false, message: 'Spécialisation invalide.');
    }
    if (primaryMarketShopChosen) {
      return const Zone0ActionResult(
          success: false, message: 'La première boutique existe déjà.');
    }
    if (!hasResources(marketConfig.shopConstructionCost) ||
        bioBatteries < marketConfig.shopConstructionBioBatteries) {
      return Zone0ActionResult(
        success: false,
        message: '${missingResourcesLabel(marketConfig.shopConstructionCost)} · ${marketConfig.shopConstructionBioBatteries} bio-batteries requises.',
      );
    }
    removeResources(marketConfig.shopConstructionCost);
    bioBatteries -= marketConfig.shopConstructionBioBatteries;
    primaryMarketShopSpecialization = specialization;
    primaryMarketShopChosen = true;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Première boutique configurée.');
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
    final stock = marketStockForShop(shopId);
    if (stock == null || !marketShopAccepts(shopId, resource)) {
      return const Zone0ActionResult(
          success: false, message: 'Produit incompatible avec ce magasin.');
    }
    if (stock.length >= marketShopStockLimit(shopId)) {
      return const Zone0ActionResult(
          success: false, message: 'Stock du magasin complet.');
    }
    final moved = removeResource(
      resource,
      math.min(amount, math.min(resourceAmount(resource), marketConfig.stackQuantityLimit)),
    );
    if (moved <= 0) {
      return const Zone0ActionResult(success: false, message: 'Stock insuffisant.');
    }
    stock.add(Zone0InventoryStack(
      id: 'shop-$shopId-${DateTime.now().microsecondsSinceEpoch}-${stock.length}',
      resource: resource,
      amount: moved,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(success: true, message: '$moved $resource placé(s) dans ce magasin.');
  }

  Zone0ActionResult returnMarketShopStock(String shopId, Zone0InventoryStack stack) {
    final stock = marketStockForShop(shopId);
    if (stock == null || !stock.contains(stack)) {
      return const Zone0ActionResult(success: false, message: 'Stock absent.');
    }
    final result = addResources(<String, int>{stack.resource: stack.amount});
    final returned = stack.amount - (result.pending[stack.resource] ?? 0);
    stack.amount -= returned;
    if (stack.amount <= 0) stock.remove(stack);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(success: returned > 0, message: '$returned ${stack.resource} rendu à la Maison.');
  }

  int marketStockAmount(String resource) => marketStock
      .where((stack) => stack.resource == resource)
      .fold(0, (sum, stack) => sum + stack.amount);

  int marketShopStockAmount(String shopId, String resource) {
    if (_marketPTibugSpecies(resource) != null && marketShopAccepts(shopId, resource)) {
      return _marketPTibugAmount(resource);
    }
    return (marketStockForShop(shopId) ?? const <Zone0InventoryStack>[])
          .where((stack) => stack.resource == resource)
          .fold(0, (sum, stack) => sum + stack.amount);
  }

  /// Uses an already started pile first, then the next matching one. This is
  /// the single stock transition used by manual sales, automation and contracts.
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
      stack.amount -= used;
      remaining -= used;
      if (stack.amount <= 0) marketStock.remove(stack);
    }
    return remaining == 0;
  }

  bool _consumeMarketShopStock(String shopId, String resource, int amount) {
    if (_marketPTibugSpecies(resource) != null) {
      if (!marketShopAccepts(shopId, resource)) return false;
      return _consumeMarketPTibugs(resource, amount);
    }
    if (shopId == primaryMarketShopId) return _consumeMarketStock(resource, amount);
    final stock = marketStockForShop(shopId);
    if (stock == null || marketShopStockAmount(shopId, resource) < amount) return false;
    var remaining = amount;
    for (final stack in stock.where((stack) => stack.resource == resource).toList()) {
      final used = math.min(remaining, stack.amount);
      stack.amount -= used;
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
    final sold = allowAnyShop
        ? _consumeAnyMarketShopStock(
            request.requestedItemId, request.requestedQuantity)
        : _consumeMarketShopStock(
            request.shopId, request.requestedItemId, request.requestedQuantity);
    if (!sold) {
      return const Zone0ActionResult(
          success: false, message: 'Stock du Marché insuffisant.');
    }
    _creditMarketBioPiles(request.rewardBioPiles);
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
    marketLastXpTickAt = marketLastWorkTickAt;
    marketXpEarnedThisAssignment = 0;
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
    marketAssignedPtipoteId = null;
    marketAssignedPtipoteName = null;
    marketLastWorkTickAt = null;
    marketLastXpTickAt = null;
    marketXpEarnedThisAssignment = 0;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '$name rentre du Marché · +$xp XP · énergie $vitality/${ptipoteStatsConfig.maxVitality} · faim $hunger/${ptipoteStatsConfig.baseHunger} · repos $rest/${ptipoteStatsConfig.maxRest}.',
    );
  }

  bool resolveMarket({DateTime? now}) {
    if (!isMarketBuilt || !isBuildingOperational('market')) return false;
    final current = now ?? DateTime.now();
    var changed = _resolveMerchantSchedule(current);
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
      marketLastXpTickAt ??= current;
      final xpPeriods = current.difference(marketLastXpTickAt!).inMinutes ~/ 120;
      if (xpPeriods > 0 && marketAssignedPtipoteId != null) {
        final xpGain = xpPeriods * math.max(1, marketLevel).toInt();
        addMissionXp(marketAssignedPtipoteId!, xpGain);
        marketXpEarnedThisAssignment += xpGain;
        marketLastXpTickAt = marketLastXpTickAt!.add(Duration(hours: 2 * xpPeriods));
        changed = true;
      }
    }
    // Le stock n'est jamais consommé de lui-même. Les demandes ouvertes sont
    // le seul chemin de vente, y compris pour le Distributeur.
    // Le P’TIPOTE du Point info conserve une fenêtre de trois minutes : le
    // joueur peut donc répondre immédiatement et le Distributeur en une minute.
    if (marketAssignedPtipoteId != null) {
      for (final request in marketRequests.where((item) => item.isOpen).toList()) {
        if (current.isBefore(request.createdAt.add(const Duration(minutes: 3)))) {
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
    changed = _resolveMarketDistributor(current) || changed;
    changed = _resolveMarketContracts(current) || changed;
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _createMarketRequest(DateTime now) {
    final entries = marketConfig.saleValues.keys
        .where((item) => marketShopAccepts(primaryMarketShopId, item) ||
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
    final isResource = item == 'Organique' || item == 'Minéral';
    final activeResidents = residents
        .where((resident) => resident.isActive)
        .toList(growable: false);
    final request = MarketCustomerRequest(
      id: 'request-${now.microsecondsSinceEpoch}-${marketRequests.length}',
      requestedItemId: item,
      requestedQuantity:
          isResource ? lisiereForageConfig.inventoryStackLimit : 1,
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
    final wellbeing = (campWellbeing.clamp(0, 100) / 100 *
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
    final boostedPerHour = basePerHour * (1 + marketEconomicActivityPercent / 100);
    final rawMinutes = 60 / boostedPerHour;
    final jitterMin = marketConfig.requestJitterMinPercent / 100;
    final jitterMax = marketConfig.requestJitterMaxPercent / 100;
    final amplitude = jitterMin + _random.nextDouble() * (jitterMax - jitterMin);
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
      byCategory.putIfAbsent(_marketItemCategory(item), () => <String>[]).add(item);
    }
    final availableWeights = <String, int>{
      for (final entry in marketConfig.requestCategoryWeights.entries)
        if ((byCategory[entry.key] ?? const <String>[]).isNotEmpty) entry.key: entry.value,
    };
    final total = availableWeights.values.fold<int>(0, (sum, value) => sum + value);
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
    if (craftConfig.recipes.any((recipe) => recipe.resultItem == item && recipe.isConsumable)) {
      return 'food';
    }
    if (item.contains('Tenue')) return 'clothing';
    if (item.contains('Meuble')) return 'furniture';
    return 'materials';
  }

  int _marketPriceInBioPiles(String item, {required String shopId}) {
    final base = math.max(1, marketConfig.requestPriceBioPiles[item] ??
        (marketConfig.saleValues[item] ?? 1) * marketConfig.valuePerBioBattery);
    if (shopId == primaryMarketShopId) {
      return math.max(1, (base * (100 - marketConfig.baseStorePricePenaltyPercent) / 100).round());
    }
    return math.max(1, (base * (100 + marketConfig.specializedShopGainBonusPercent) / 100).round());
  }

  void _creditMarketBioPiles(int amount) {
    bioPiles += math.max(0, amount);
    final converted = bioPiles ~/ 10;
    if (converted > 0) {
      bioPiles -= converted * 10;
      bioBatteries += converted;
      marketBioBatteriesEarned += converted;
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
      ..responder = responder;
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
      requestId: 'distributor-${at.microsecondsSinceEpoch}-${marketRequestLog.length}',
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
      String resource, int amount, {String shopId = primaryMarketShopId}) {
    if (shopId == primaryMarketShopId && !primaryMarketShopChosen) {
      return const Zone0ActionResult(success: false, message: 'Choisissez d’abord le type de la boutique.');
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
          (distributor.constructionDeposits[entry.key] ?? 0) >= entry.value);
  }

  bool get isMarketDistributorReadyToBuild =>
      isMarketDistributorReadyToBuildFor(primaryMarketShopId);

  Zone0ActionResult startMarketDistributorConstruction(
      {String shopId = primaryMarketShopId}) {
    if (shopId == primaryMarketShopId && !primaryMarketShopChosen) {
      return const Zone0ActionResult(success: false, message: 'Choisissez d’abord le type de la boutique.');
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
    if (bioBatteries < marketConfig.distributorConstructionBioBatteries) {
      return Zone0ActionResult(
          success: false,
          message: '${marketConfig.distributorConstructionBioBatteries} bio-batteries requises.');
    }
    bioBatteries -= marketConfig.distributorConstructionBioBatteries;
    distributor.constructionStartedAt = DateTime.now();
    distributor.constructionEndsAt =
        distributor.constructionStartedAt!.add(
      Duration(minutes: marketConfig.distributorConstructionMinutes),
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
    bioBatteries -= 1;
    distributor.energy = math.min(
      marketConfig.distributorEnergyCapacity,
      distributor.energy + marketConfig.distributorEnergyPerBioBattery,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
        success: true, message: 'Énergie du Distributeur rechargée.');
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
    if (distributor == null || !distributor.isBuilt || !distributor.accepts(resource)) {
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
    if (!byPtipote && (!hasResources(marketConfig.distributorRepairCost) ||
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

  void _repairDistributor(
    MarketDistributorState distributor, {
    required bool byPtipote,
    required String shopLabel,
  }) {
    // Le joueur peut remplacer une réparation P’TIPOTE par une intervention
    // courte. La même machine ne peut jamais lancer deux réparations.
    distributor.repairEndsAt = DateTime.now().add(
      Duration(minutes: byPtipote
          ? marketConfig.distributorRepairMinutesForLevel(distributor.level)
          : 1),
    );
    distributor.repairStartedBy = byPtipote ? 'ptipote' : 'player';
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
        changed = _resolveMarketDistributorForShop(shop.id, distributor, current) || changed;
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
      reports.add(PtipoteMissionReport.system(
          message: '$shopLabel est opérationnel.'));
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
    if (distributor.isBroken && distributor.repairEndsAt == null &&
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
        distributor.stock.length < distributorSlotsForShop(shopId)) {
      final source = sourceStock
          .where((stack) =>
              distributor.accepts(stack.resource) && stack.amount > 0)
          .firstOrNull;
      if (source != null) {
        final transferred = math.min(source.amount, marketConfig.stackQuantityLimit);
        source.amount -= transferred;
        if (source.amount <= 0) sourceStock.remove(source);
        distributor.stock.add(Zone0InventoryStack(
          id: 'distributor-refill-$shopId-${DateTime.now().microsecondsSinceEpoch}',
          resource: source.resource,
          amount: transferred,
        ));
        changed = true;
      }
    }
    for (final request in marketRequests
        .where((item) => item.isOpen && item.shopId == shopId).toList()) {
      if (current.isBefore(request.distributorEligibleAt)) continue;
      final stack = distributor.stock
          .where((item) => item.resource == request.requestedItemId)
          .firstOrNull;
      if (stack == null || stack.amount < request.requestedQuantity) continue;
      stack.amount -= request.requestedQuantity;
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
              marketConfig.distributorBreakDenominatorForLevel(
                  distributor.level))) ==
          0) {
        distributor.isBroken = true;
        _recordDistributorIncident('$shopLabel en panne après une vente.', current);
        reports.add(PtipoteMissionReport.system(
            message: '$shopLabel est en panne.'));
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
          contract.requestedItems.entries
              .every((entry) => (_marketPTibugSpecies(entry.key) != null
                  ? _marketPTibugAmount(entry.key)
                  : marketStockAmount(entry.key)) >= entry.value)) {
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
    if (!contract.requestedItems.entries.every((entry) =>
        (_marketPTibugSpecies(entry.key) != null
            ? _marketPTibugAmount(entry.key)
            : marketStockAmount(entry.key)) >= entry.value))
      return false;
    for (final entry in contract.requestedItems.entries) {
      final isPTibug = _marketPTibugSpecies(entry.key) != null;
      if (isPTibug) {
        if (!_consumeMarketPTibugs(entry.key, entry.value)) {
          return false;
        }
      } else if (!_consumeMarketStock(entry.key, entry.value)) {
        return false;
      }
    }
    final payment =
        (contract.rewardBioBatteries * sourcierConfidencePaymentMultiplier)
            .floor();
    bioBatteries += payment;
    sourcierConfidence =
        math.min(100, sourcierConfidence + contract.confidenceReward);
    contract
      ..status = MarketContractStatus.completed
      ..deliveredAt = DateTime.now();
    return true;
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
        minutes: targetId == 'housing'
            ? housingConfig.housingDurationMinutes
            : _isRefugeTarget(targetId)
                ? pTibugConfig.territory
                    .refugeMinutesForLevel(_buildingLevel(targetId) + 1)
                : buildingConstructionConfig.project(targetId).durationMinutes,
      );

  int _buildingLevel(String targetId) {
    if (_isRefugeTarget(targetId)) {
      return territoryBuildingForId(targetId)?.level ?? 0;
    }
    return switch (targetId) {
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
  }

  int _projectMaxLevel(String targetId) {
    if (_isRefugeTarget(targetId))
      return pTibugConfig.territory.refugeMaximumLevel;
    return switch (targetId) {
      'fablab' => 1,
      'cuisine' => fablabConfig.cuisineMaxLevel,
      'atelier' => fablabConfig.atelierMaxLevel,
      'recycler' => wasteRecyclerConfig.recyclerMaxLevel,
      'securityTower' => 3,
      'market' => 5,
      'house' => housingConfig.houseMaxLevel,
      'housing' => 99,
      'plaineNursery' => pTibugConfig.territory.nurseryMaximumLevel,
      _ => 1,
    };
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
        final nursery = plaineNurseryTerritory;
        nursery
          ..level = plaineNurseryLevel
          ..isBuilt = plaineNurseryLevel > 0;
        emitKernelProgressEvent(KernelProgressEventType.buildingConstructed);
      default:
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
          message: 'Le module ${order.moduleType.displayName} est prêt.${order.assignedPtipoteId == null ? '' : ' ${order.assignedPtipoteName} gagne 10 XP.'}',
          sourceBuildingId: 'fablab',
          mailbox: Zone0MessageMailbox.fablab,
          subject: 'Fin de craft',
          concerned: order.assignedPtipoteName ?? 'Le joueur',
          summary: 'Module P’TIBUG ${order.moduleType.displayName} créé${order.assignedPtipoteId == null ? '.' : ' · +10 XP.'}',
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

  Zone0ActionResult applyPTibugPermanentTrait({
    required PTibug bug,
    required String traitId,
  }) {
    if (!pTibugs.contains(bug) ||
        !isPlaineNurseryBuilt ||
        bug.assignedBuildingId != plaineNurseryTerritoryId) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le P’TIBUG doit être présent dans la Nurserie.',
      );
    }
    final definition = pTibugConfig.traitDefinitionFor(traitId);
    final targetLevel = nextPTibugTraitLevelFor(bug, traitId);
    if (targetLevel == null) {
      final message = bug.biologicalTraitId == traitId
          ? 'Ce Trait est déjà au niveau maximum.'
          : 'Ce second Trait exige un Renouvellement et un niveau compatible.';
      return Zone0ActionResult(success: false, message: message);
    }
    final patternId = 'ptibug-trait-$traitId';
    final progress = pTibugPatternProgress[patternId];
    if (definition == null ||
        progress == null ||
        !definition.isActive ||
        !isPTibugPatternActive(patternId) ||
        progress.masteryLevel < targetLevel) {
      return Zone0ActionResult(
        success: false,
        message: 'Le Pattern doit atteindre la maîtrise $targetLevel.',
      );
    }
    // Only the target level is paid. Previous transformations are never paid
    // again when a P'TIBUG evolves from Trait I to Trait II or III.
    final dataCost = definition.dataCostForLevel(targetLevel);
    final materialCost = definition.materialCostForLevel(targetLevel);
    final energyCost = definition.energyCostForLevel(targetLevel);
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
    if (bug.biologicalTraitId == null || bug.biologicalTraitId == traitId) {
      bug
        ..biologicalTraitId = traitId
        ..biologicalTraitLevel = targetLevel;
    } else {
      bug
        ..secondTraitId = traitId
        ..secondTraitLevel = targetLevel;
    }
    emitKernelProgressEvent(KernelProgressEventType.ptibugTraitEquipped);
    reports.add(
      PtipoteMissionReport.system(
        message: '${_pTibugBiologicalName(bug)} reçoit un Trait permanent.',
        sourceBuildingId: 'plaineNursery',
        mailbox: Zone0MessageMailbox.companions,
        subject: 'Trait P’TIBUG',
        concerned: bug.displayName,
        summary:
            'Trait ${definition.displayName} niveau $targetLevel appliqué.',
      ),
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: 'Trait ${definition.displayName} niveau $targetLevel appliqué.',
    );
  }

  bool canRenewPTibug(PTibug bug) {
    final config = pTibugConfig.progression;
    return !bug.isRenewed &&
        bug.renewalCount < config.maximumRenewals &&
        bug.level >= config.renewalLevel &&
        bug.biologicalTraitLevel >= 3 &&
        bug.assignedBuildingId == plaineNurseryTerritoryId &&
        bug.storedAmount == 0 &&
        bug.storedDataCells.isEmpty;
  }

  Zone0ActionResult renewPTibug(PTibug bug) {
    final config = pTibugConfig.progression;
    if (!canRenewPTibug(bug)) {
      return const Zone0ActionResult(
          success: false,
          message:
              'Renouvellement indisponible : niveau 3, Trait I niveau III, Nurserie et stocks vides requis.');
    }
    if (!hasResources(config.renewalMaterialCost) ||
        energyUnits < config.renewalEnergyCost ||
        bioBatteries < config.renewalBioBatteryCost) {
      return const Zone0ActionResult(
          success: false, message: 'Coût de Renouvellement insuffisant.');
    }
    if (!removeResources(config.renewalMaterialCost)) {
      return const Zone0ActionResult(
          success: false, message: 'Matériaux insuffisants.');
    }
    energyUnits -= config.renewalEnergyCost;
    bioBatteries -= config.renewalBioBatteryCost;
    bug
      ..isRenewed = true
      ..renewedAt = DateTime.now()
      ..renewalCount += 1;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true,
        message:
            'Renouvellement accompli. Le second Trait est désormais accessible au niveau 4.');
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
        originRefugeId: 'zone0-refuge',
        creatorPlayerId: 'zone0-player',
        certificationId:
            'cert-${bug.id}-${DateTime.now().microsecondsSinceEpoch}',
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
    bug.xp += amount;
    while (bug.level < config.maximumLevel) {
      final required = config.xpForNextLevel(bug.level);
      if (required <= 0 || bug.xp < required) break;
      bug.xp -= required;
      bug.level += 1;
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
        add(_pTibugAracResourceForBiome(bug.biome), 3);
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
          add(_pTibugAracResourceForBiome(bug.biome), claws);
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

  String _pTibugAracResourceForBiome(PTibugBiome biome) {
    final weights = pTibugConfig.biomes[biome]?.aracProductionWeights ??
        const <String, int>{};
    final entries = weights.entries.where((entry) => entry.value > 0).toList();
    if (entries.isEmpty) return 'Organique';
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    var cursor = _random.nextInt(total);
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
    bioBatteries -= 1;
    building.localEnergy += wasteRecyclerConfig.energyUnitsPerBioBattery;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '+${wasteRecyclerConfig.energyUnitsPerBioBattery} énergie locale.',
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
        marketRequestLog
          ..clear()
          ..addAll((marketData['requestLog'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketRequestLogEntry.fromFirebase));
        marketNextSaleAt = _readDate(marketData['nextSaleAt']);
        marketNextRequestAt = _readDate(marketData['nextRequestAt']);
        marketLastWorkTickAt = _readDate(marketData['lastWorkTickAt']);
        marketLastXpTickAt = _readDate(marketData['lastXpTickAt']);
        marketXpEarnedThisAssignment = _readInt(marketData['xpEarnedThisAssignment']);
        marketAssignedPtipoteId = marketData['assignedPtipoteId'] as String?;
        marketAssignedPtipoteName =
            marketData['assignedPtipoteName'] as String?;
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
        MarketDistributorState? migratedPrimaryDistributor;
        final migratedPrimary = marketShops.where((shop) => shop.isPrimary).firstOrNull;
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
          marketShops
            ..clear();
        }
        marketContracts
          ..clear()
          ..addAll((marketData['contracts'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map(MarketSourcierContract.fromFirebase)
              .where((contract) => contract.contractId.isNotEmpty));
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
        pendingWaste = _readInt(recyclerData['pendingWaste']);
        recyclerCycleStartedAt = _readDate(recyclerData['cycleStartedAt']);
        lastWasteGenerationAt = _readDate(
          recyclerData['lastWasteGenerationAt'],
        );
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
      _loadedFromFirebase = true;
      resolveConstructionProjects();
      if (migratedPTibugState ||
          discoveredSourcierPatterns ||
          refreshedMerchantOffers) {
        unawaited(saveRuntimeToFirebase());
      }
    });
  }

  /// Keeps saves made before data cells, permanent traits and module instances.
  /// The migration only adds compatibility data; it never removes player items.
  bool _migratePTibugScientificState() {
    var changed = false;
    final now = DateTime.now();

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
    for (final state in biomeSecurity.values) {
      changed = _regenerateBiomeWaste(state: state, now: current) || changed;
      changed = _regenerateBiomeBiomass(state: state, now: current) || changed;
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
                ? <String>[
                    'P’TIBUG Scarabé',
                    'P’TIBUG Hyme',
                    'P’TIBUG Arac',
                  ][_random.nextInt(3)]
            : _random.nextBool()
                ? 'Organique'
                : 'Minéral';
    final quantity = item == 'Organique' || item == 'Minéral' ? 10 : 1;
    marketContracts.add(MarketSourcierContract(
      contractId: 'contract-${now.microsecondsSinceEpoch}',
      marketLevelRequired: marketLevel,
      category: category,
      requestedItems: <String, int>{item: quantity},
      rewardBioBatteries: math.max(
          1,
          ((marketConfig.saleValues[item] ?? 1) *
                  quantity /
                  marketConfig.valuePerBioBattery)
              .ceil()),
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

  Zone0ActionResult claimFirstMarketShop(String specialization) {
    if (marketLevel < 2 || firstFreeShopClaimed || marketShopCount >= marketShopLimit) {
      return const Zone0ActionResult(
          success: false, message: 'Magasin offert indisponible.');
    }
    if (!const <String>{'restaurant', 'home', 'equipment', 'ptibug'}
        .contains(specialization)) {
      return const Zone0ActionResult(
          success: false, message: 'Spécialisation invalide.');
    }
    firstFreeShopClaimed = true;
    marketShops.add(MarketShop(
        id: 'shop-${DateTime.now().microsecondsSinceEpoch}',
        specialization: specialization));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Premier magasin spécialisé construit.');
  }

  Zone0ActionResult buildMarketShop(String specialization) {
    if (marketLevel < 2 || marketShopCount >= marketShopLimit) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun emplacement de magasin libre.');
    }
    if (!const <String>{'restaurant', 'home', 'equipment', 'ptibug'}
        .contains(specialization)) {
      return const Zone0ActionResult(
          success: false, message: 'Spécialisation invalide.');
    }
    if (!hasResources(marketConfig.shopConstructionCost) ||
        bioBatteries < marketConfig.shopConstructionBioBatteries) {
      return Zone0ActionResult(
        success: false,
        message: '${missingResourcesLabel(marketConfig.shopConstructionCost)} · ${marketConfig.shopConstructionBioBatteries} bio-batteries requises.',
      );
    }
    removeResources(marketConfig.shopConstructionCost);
    bioBatteries -= marketConfig.shopConstructionBioBatteries;
    marketShops.add(MarketShop(
      id: 'shop-${DateTime.now().microsecondsSinceEpoch}',
      specialization: specialization,
    ));
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
        success: true, message: 'Nouveau magasin construit.');
  }

  Zone0ActionResult upgradeMarketShop(String shopId) {
    if (shopId == primaryMarketShopId) {
      if (primaryMarketShopLevel >= 2) {
        return const Zone0ActionResult(success: false, message: 'Niveau maximal atteint.');
      }
      final costs = marketConfig.shopConstructionCost.map(
        (resource, amount) => MapEntry(resource, amount * marketConfig.shopUpgradeCostMultiplier),
      );
      final batteries = marketConfig.shopConstructionBioBatteries * marketConfig.shopUpgradeCostMultiplier;
      if (!hasResources(costs) || bioBatteries < batteries) {
        return Zone0ActionResult(success: false,
            message: '${missingResourcesLabel(costs)} · $batteries bio-batteries requises.');
      }
      removeResources(costs);
      bioBatteries -= batteries;
      primaryMarketShopLevel = 2;
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
      return const Zone0ActionResult(success: true, message: 'Boutique principale améliorée.');
    }
    final shop = marketShopById(shopId);
    if (shop == null || shop.level >= 2) {
      return const Zone0ActionResult(
          success: false, message: 'Amélioration indisponible.');
    }
    final costs = marketConfig.shopConstructionCost.map(
      (resource, amount) => MapEntry(resource, amount * marketConfig.shopUpgradeCostMultiplier),
    );
    final batteries = marketConfig.shopConstructionBioBatteries * marketConfig.shopUpgradeCostMultiplier;
    if (!hasResources(costs) || bioBatteries < batteries) {
      return Zone0ActionResult(
          success: false,
          message: '${missingResourcesLabel(costs)} · $batteries bio-batteries requises.');
    }
    removeResources(costs);
    bioBatteries -= batteries;
    shop.level = 2;
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Magasin amélioré : 6 piles et 2 emplacements de Distributeur.',
    );
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
    if (!isSecurityTowerBuilt) return changed;

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
      activeGlobalWeatherEvent!.status = GlobalWeatherEventStatus.completed;
      final promoted = nextGlobalWeatherEvent!;
      promoted.status = GlobalWeatherEventStatus.active;
      activeGlobalWeatherEvent = promoted;
      _applyWeatherViabilityDamage(promoted);
      _applyWeatherHouseDamage(promoted);
      _applyWeatherStockLosses(promoted);
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
          ? 'Recherche : aucune ressource naturelle extraite.'
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
    const naturalResources = <String>{'Organique', 'Minéral', 'Déchets'};
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
    final config = lisiereForageConfig.biomass;
    final multiplier = _biomassMultiplierFor(
      biomassFor(biome),
      config.revitalizeCostTiers,
    );
    return <String, int>{
      'Organique': math.max(
        1,
        (config.revitalizeBaseOrganicCost * multiplier).ceil(),
      ),
      'Minéral': math.max(
        1,
        (config.revitalizeBaseMineralCost * multiplier).ceil(),
      ),
    };
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
    final cost = biomassRevitalizeCost(biome);
    if (!hasResources(cost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(cost),
      );
    }
    removeResources(cost);
    final gain = math.max(1, lisiereForageConfig.biomass.revitalizeGain);
    state.biomassPercent = math.min(maximum, state.biomassPercent + gain);
    state.lastBiomassRegenerationAt = DateTime.now();
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

    final typeConfig = lisiereForageConfig.missionTypes[mission.type] ??
        lisiereForageConfig.missionTypes[ForageMissionType.harvest]!;
    final intensityConfig = lisiereForageConfig.intensities[mission.intensity]!;
    final attempts = math.max(
      0,
      (pTibugConfig.maxCellsForMissionHours(duration.theoreticalHours) *
              typeConfig.maximumCellsMultiplier *
              intensityConfig.rewardMultiplier)
          .ceil(),
    );
    // Research is the active way to acquire Cells. Harvest keeps the same
    // biome table but its findings remain occasional.
    final cells = <PTibugDataCell>[];
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      final chance = (pTibugConfig.cellChanceForOrdinal(attempt + 1) *
              typeConfig.cellChanceMultiplier)
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
      for (var slot = 0; slot < 5; slot += 1) {
        final family = slot < 2 ? dominant : _pickWeightedDataFamily(weights);
        entries.add(
          PTibugDataCellEntry(
            family: family,
            quality: _pickWeightedDataQuality(),
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
          'xpEarnedThisAssignment': marketXpEarnedThisAssignment,
          'assignedPtipoteId': marketAssignedPtipoteId,
          'assignedPtipoteName': marketAssignedPtipoteName,
          'valueRemainder': marketValueRemainder,
          'bioBatteriesEarned': marketBioBatteriesEarned,
          'sourcierConfidence': sourcierConfidence,
          'firstFreeShopClaimed': firstFreeShopClaimed,
          'primaryShopSpecialization': primaryMarketShopSpecialization,
          'primaryShopChosen': primaryMarketShopChosen,
          'primaryShopLevel': primaryMarketShopLevel,
          'activeLicenses': activeMarketLicenses.toList(),
          'shops': marketShops.map((item) => item.toFirebase()).toList(),
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
  Zone0InventoryStack({String? id, required this.resource, required int amount})
      : id = id ?? 'stack-${DateTime.now().microsecondsSinceEpoch}',
        amount = math.max(0, amount);

  final String id;
  final String resource;
  int amount;

  factory Zone0InventoryStack.fromFirebase(Map<dynamic, dynamic> data) =>
      Zone0InventoryStack(
        id: data['id'] as String?,
        resource: '${data['resource'] ?? ''}',
        amount: Zone0GameState.instance._readInt(data['amount']),
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'resource': resource,
        'amount': amount,
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
          'Organique, Minéral, Déchets, Mycélium et Eau.',
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
  final Map<String, int> constructionDeposits = <String, int>{};
  final List<Zone0InventoryStack> stock = <Zone0InventoryStack>[];

  bool get isOperational => isBuilt && !isBroken && repairEndsAt == null;
  bool accepts(String resource) => switch (type) {
        MarketDistributorType.resources => const <String>{
            'Organique',
            'Minéral',
            'Déchets',
            'Mycélium',
            'Eau'
          }.contains(resource),
        MarketDistributorType.food => craftConfig.recipes.any(
            (recipe) => recipe.resultItem == resource && recipe.isConsumable,
          ),
        MarketDistributorType.general => !const <String>{
              'Organique',
              'Minéral',
              'Déchets',
              'Mycélium',
              'Eau'
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
      ..repairStartedBy = data['repairStartedBy'] as String?;
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
        'constructionDeposits': constructionDeposits,
        'stock': stock.map((item) => item.toFirebase()).toList(),
      };
}

class MarketShop {
  MarketShop({
    required this.id,
    required this.specialization,
    this.level = 1,
    List<Zone0InventoryStack>? stock,
    this.distributor,
    this.isPrimary = false,
  }) : stock = stock ?? <Zone0InventoryStack>[];
  final String id;
  final String specialization;
  int level;
  final List<Zone0InventoryStack> stock;
  MarketDistributorState? distributor;
  final bool isPrimary;

  bool accepts(String resource) => switch (specialization) {
        'restaurant' => craftConfig.recipes.any(
            (recipe) => recipe.resultItem == resource && recipe.isConsumable,
          ),
        'home' || 'ameublement' => resource.contains('Meuble') ||
            resource.contains('Ventilation') ||
            resource.contains('Lumière') ||
            resource.contains('Cartouche'),
        'equipment' => craftConfig.recipes.any(
            (recipe) => recipe.resultItem == resource &&
                !recipe.isConsumable &&
                !resource.contains('Meuble') &&
                !resource.contains('Ventilation') &&
                !resource.contains('Lumière') &&
                !resource.contains('Cartouche'),
          ),
        'ptibug' => resource.startsWith('P’TIBUG '),
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
      );
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'id': id,
        'specialization': specialization,
        'level': level,
        'stock': stock.map((item) => item.toFirebase()).toList(),
        'distributor': distributor?.toFirebase(),
        'isPrimary': isPrimary,
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
  final int rewardBioBatteries;
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
          fallback: Zone0GameState.instance._readInt(data['rewardBioBatteries']) * 10,
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
          fallback: Zone0GameState.instance._readInt(data['rewardBioBattery']) * 10,
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
  int get rewardBioBattery => rewardBioPiles ~/ 10;
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
          fallback: Zone0GameState.instance._readInt(data['rewardBioBatteries']) * 10,
        ),
        responder: data['responder'] == null
            ? null
            : ForageMission._enumByName(
                MarketRequestResponder.values,
                '${data['responder']}',
                MarketRequestResponder.player,
              ),
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
        'rewardBioBatteries': rewardBioBatteries ~/ 10,
        'rewardBioPiles': rewardBioBatteries,
        'responder': responder?.name,
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
  }) : installedStructuralProtections =
            installedStructuralProtections ?? <StructuralProtectionType>[];

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
      };
}

class Zone0Resident {
  Zone0Resident({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.houseId,
    this.baseHappiness = 100,
    this.temporaryHappinessModifier = 0,
    this.isActive = true,
    this.contributionEligible = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  factory Zone0Resident.fromFirebase(Map<dynamic, dynamic> data) =>
      Zone0Resident(
        id: '${data['residentId'] ?? ''}',
        displayName: '${data['displayName'] ?? 'Habitant'}',
        houseId: data['houseId'] as String?,
        baseHappiness: Zone0GameState.instance
            ._readInt(data['baseHappiness'], fallback: 100)
            .clamp(0, 100),
        temporaryHappinessModifier: Zone0GameState.instance
            ._readInt(data['temporaryHappinessModifier']),
        createdAt: Zone0GameState.instance._readDate(data['createdAt']) ??
            DateTime.now(),
        updatedAt: Zone0GameState.instance._readDate(data['updatedAt']),
        isActive: data['isActive'] != false,
        contributionEligible: data['contributionEligible'] == true,
      );

  final String id;
  String displayName;
  String? houseId;
  int baseHappiness;
  int temporaryHappinessModifier;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isActive;
  bool contributionEligible;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'residentId': id,
        'displayName': displayName,
        'houseId': houseId,
        'baseHappiness': baseHappiness,
        'temporaryHappinessModifier': temporaryHappinessModifier,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'isActive': isActive,
        'contributionEligible': contributionEligible,
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
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : residentIds = residentIds ?? <String>[],
        installedStructuralProtections =
            installedStructuralProtections ?? <StructuralProtectionType>[],
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
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

enum CommunityProjectStatus { selected, active, paused, completed }

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
      required this.batteriesLost,
      required this.protectionPercent,
      required this.resolvedAt});
  final String eventId;
  final int wasteCreated;
  final int batteriesLost;
  final int protectionPercent;
  final DateTime resolvedAt;
  factory WeatherStockIncident.fromFirebase(Map<dynamic, dynamic> data) =>
      WeatherStockIncident(
          eventId: '${data['eventId'] ?? ''}',
          wasteCreated: Zone0GameState.instance._readInt(data['wasteCreated']),
          batteriesLost:
              Zone0GameState.instance._readInt(data['batteriesLost']),
          protectionPercent:
              Zone0GameState.instance._readInt(data['protectionPercent']),
          resolvedAt: Zone0GameState.instance._readDate(data['resolvedAt']) ??
              DateTime.now());
  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'eventId': eventId,
        'wasteCreated': wasteCreated,
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
  int localEnergy;

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
        localEnergy: Zone0GameState.instance._readInt(data['localEnergy']),
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

class PTibug {
  PTibug({
    required this.id,
    required this.displayName,
    required this.species,
    required this.styleVariant,
    required this.createdAt,
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
  })  : storedResources = storedResources ?? <String, int>{},
        storedDataCells = storedDataCells ?? <PTibugDataCell>[],
        equippedModules = equippedModules ?? <PTibugModuleType>[],
        equippedModuleInstanceIds = equippedModuleInstanceIds ?? <String>[];
  final String id;
  String displayName;
  final PTibugSpecies species;
  final String styleVariant;
  final DateTime createdAt;
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
        species: ForageMission._enumByName(
          PTibugSpecies.values,
          '${data['species'] ?? ''}',
          PTibugSpecies.scarabe,
        ),
        styleVariant: '${data['styleVariant'] ?? 'compact'}',
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
        'species': species.name,
        'styleVariant': styleVariant,
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
    this.certificationId,
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
  final String? certificationId;
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
        certificationId: data['certificationId'] as String?,
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
        'certificationId': certificationId,
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
    // Keep a const-compatible fallback for legacy states; loaded settings clamp it.
    this.wasteLevel = 10,
    this.biomassPercent = 100,
    this.lastPatrolAt,
    this.lastMissionAt,
    this.lastDecayAt,
    this.lastWasteRegenerationAt,
    this.lastBiomassRegenerationAt,
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
