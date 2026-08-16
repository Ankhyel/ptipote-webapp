import 'fablab_config.dart';

/// The physical FabLab is the only building. Its rooms deliberately carry
/// production progression, never a second viability/weather/storage state.
enum FabLabRoom { kitchen, workshop, recycler }

enum RecyclerModuleType { organic, mineral }

class FabLabRoomState {
  FabLabRoomState({
    this.level = 0,
    Set<String>? permanentWorkerIds,
    Set<String>? marketRestockRecipeIds,
    Map<String, int>? marketRestockTargets,
  })  : permanentWorkerIds = permanentWorkerIds ?? <String>{},
        marketRestockRecipeIds = marketRestockRecipeIds ?? <String>{},
        marketRestockTargets = marketRestockTargets ?? <String, int>{};

  factory FabLabRoomState.fromFirebase(Map<dynamic, dynamic>? data) =>
      FabLabRoomState(
        level: (data?['level'] as num?)?.toInt() ?? 0,
        permanentWorkerIds: (data?['permanentWorkerIds'] as List? ?? const [])
            .map((value) => '$value')
            .where((value) => value.isNotEmpty)
            .toSet(),
        marketRestockRecipeIds:
            (data?['marketRestockRecipeIds'] as List? ?? const [])
                .map((value) => '$value')
                .where((value) => value.isNotEmpty)
                .toSet(),
        marketRestockTargets: (data?['marketRestockTargets'] as Map? ??
                const <dynamic, dynamic>{})
            .map((key, value) =>
                MapEntry('$key', (value as num?)?.toInt() ?? 0)),
      );

  int level;
  final Set<String> permanentWorkerIds;
  final Set<String> marketRestockRecipeIds;
  final Map<String, int> marketRestockTargets;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'level': level,
        'permanentWorkerIds': permanentWorkerIds.toList(),
        'marketRestockRecipeIds': marketRestockRecipeIds.toList(),
        'marketRestockTargets': marketRestockTargets,
      };
}

class FabLabRecyclerVatState {
  FabLabRecyclerVatState({
    this.storedWaste = 0,
    this.moduleType,
    this.cycleStartedAt,
    this.batchRatios,
  });

  factory FabLabRecyclerVatState.fromFirebase(Map<dynamic, dynamic>? data) =>
      FabLabRecyclerVatState(
        storedWaste: (data?['storedWaste'] as num?)?.toInt() ?? 0,
        moduleType: _moduleTypeFromName('${data?['moduleType'] ?? ''}'),
        cycleStartedAt: _dateFromStorage(data?['cycleStartedAt']),
        batchRatios: (data?['batchRatios'] as List?)
            ?.whereType<num>()
            .map((value) => value.toInt())
            .toList(),
      );

  int storedWaste;
  RecyclerModuleType? moduleType;
  DateTime? cycleStartedAt;
  List<int>? batchRatios;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'storedWaste': storedWaste,
        'moduleType': moduleType?.name,
        'cycleStartedAt': cycleStartedAt?.millisecondsSinceEpoch,
        'batchRatios': batchRatios,
      };
}

DateTime? _dateFromStorage(dynamic value) {
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is DateTime) return value;
  return null;
}

RecyclerModuleType? _moduleTypeFromName(String name) {
  for (final type in RecyclerModuleType.values) {
    if (type.name == name) return type;
  }
  return null;
}

class FabLabBuilding {
  FabLabBuilding({
    this.level = 0,
    this.migrationVersion = 0,
    Map<FabLabRoom, FabLabRoomState>? rooms,
    List<FabLabRecyclerVatState>? recyclerVats,
  })  : rooms = rooms ??
            <FabLabRoom, FabLabRoomState>{
              for (final room in FabLabRoom.values) room: FabLabRoomState(),
            },
        recyclerVats = recyclerVats ??
            <FabLabRecyclerVatState>[
              FabLabRecyclerVatState(),
              FabLabRecyclerVatState()
            ];

  factory FabLabBuilding.fromFirebase(Map<dynamic, dynamic>? data) {
    final roomData = data?['rooms'] as Map?;
    final vatData = data?['recyclerVats'] as List?;
    return FabLabBuilding(
      level: (data?['level'] as num?)?.toInt() ?? 0,
      migrationVersion: (data?['migrationVersion'] as num?)?.toInt() ?? 0,
      rooms: <FabLabRoom, FabLabRoomState>{
        for (final room in FabLabRoom.values)
          room: FabLabRoomState.fromFirebase(roomData?[room.name] as Map?),
      },
      recyclerVats: List<FabLabRecyclerVatState>.generate(
        2,
        (index) => FabLabRecyclerVatState.fromFirebase(
          index < (vatData?.length ?? 0) ? vatData![index] as Map? : null,
        ),
      ),
    );
  }

  int level;
  int migrationVersion;
  final Map<FabLabRoom, FabLabRoomState> rooms;
  final List<FabLabRecyclerVatState> recyclerVats;

  FabLabRoomState room(FabLabRoom room) =>
      rooms.putIfAbsent(room, FabLabRoomState.new);

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'level': level,
        'migrationVersion': migrationVersion,
        'rooms': <String, dynamic>{
          for (final entry in rooms.entries)
            entry.key.name: entry.value.toFirebase(),
        },
        'recyclerVats': recyclerVats.map((vat) => vat.toFirebase()).toList(),
      };
}

extension FabLabRoomRules on FablabConfig {
  int fablabStorageForLevel(int level) =>
      fablabStorageByLevel[level.clamp(1, fablabMaxLevel)] ?? 0;

  int houseStorageForLevel(int level) =>
      houseStorageByLevel[level.clamp(1, houseStorageByLevel.length)] ?? 100;

  int roomWorkersFor(FabLabRoom room, int level) =>
      room == FabLabRoom.recycler ? 0 : roomConfigFor(room, level).workers;

  FablabRoomLevelConfig roomConfigFor(FabLabRoom room, int level) {
    final configs =
        room == FabLabRoom.kitchen ? kitchenRoomLevels : workshopRoomLevels;
    return configs[level.clamp(1, 4)] ?? configs[4]!;
  }

  int queueCapacityFor(FabLabRoom room, int level) =>
      room == FabLabRoom.recycler
          ? 0
          : roomConfigFor(room, level).queueCapacity;

  List<int> quantitiesFor(FabLabRoom room, int level) =>
      roomConfigFor(room, level).quantities;

  bool roomSupportsMarketRestock(FabLabRoom room, int level) =>
      room != FabLabRoom.recycler && roomConfigFor(room, level).marketRestock;

  int recyclerInputForLevel(int level) =>
      recyclerInputByLevel[level.clamp(1, 4)] ?? 18;

  int recyclerVatCapacityFor(int vatIndex, int level) {
    if (vatIndex == 0)
      return recyclerVatOneCapacityByLevel[level.clamp(1, 4)] ?? 20;
    return level >= 3
        ? (recyclerVatTwoCapacityByLevel[level.clamp(3, 4)] ?? 20)
        : 0;
  }

  bool recyclerVatSupportsModule(int vatIndex, int level) =>
      vatIndex == 0 ? level >= 3 : level >= 4;
}
