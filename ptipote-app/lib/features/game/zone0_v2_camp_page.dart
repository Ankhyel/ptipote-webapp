import 'package:flutter/material.dart';

import '../figurines/ptipote_image.dart';
import '../figurines/ptipote_v2.dart';
import 'lisiere_v2.dart';
import 'lisiere_v2_service.dart';
import 'worldcraft_v2_service.dart';
import 'zone0_v2_foundation_service.dart';

/// V2 Camp shell. It reads only the independent V2 foundation document and
/// never falls back to the V1 Refuge state.
class Zone0V2CampPage extends StatefulWidget {
  const Zone0V2CampPage({super.key});

  static const route = '/game/v2/camp';

  @override
  State<Zone0V2CampPage> createState() => _Zone0V2CampPageState();
}

class _Zone0V2CampPageState extends State<Zone0V2CampPage> {
  final Zone0V2FoundationService _foundation = Zone0V2FoundationService();
  final LisiereV2Service _lisiere = LisiereV2Service();
  final WorldcraftV2Service _worldcraft = WorldcraftV2Service();
  Future<_CampData?>? _world;

  @override
  void initState() {
    super.initState();
    _world = _load();
  }

  void _reload() => setState(() => _world = _load());

  Future<_CampData?> _load() async {
    final world = await _foundation.load();
    if (world == null) return null;
    final worldcraft = world['worldcraft'];
    if (worldcraft is Map) {
      final regionId = '${worldcraft['regionId'] ?? ''}';
      final campId = '${worldcraft['campId'] ?? ''}';
      if (regionId.isEmpty || campId.isEmpty) return null;
      await _worldcraft.resolveRegionUntil(regionId);
      await _worldcraft.resolveCampUntil(campId);
      final region = await _worldcraft.loadRegion(regionId);
      final camp = await _worldcraft.loadCamp(campId);
      if (region == null || camp == null) return null;
      final details = camp['detailedState'] is Map
          ? Map<String, dynamic>.from(camp['detailedState'] as Map)
          : const <String, dynamic>{};
      final sharedWorld = <String, dynamic>{
        ...world,
        'region': region,
        'camp': camp,
        'biomes': await _worldcraft.loadBiomes(regionId),
        'core': details['core'] ?? const <String, dynamic>{},
        'buildings': details['buildings'] ?? const <String, dynamic>{},
        'residents': details['residents'] ?? const <dynamic>[],
        'firstResidentHook': details['firstResidentHook'] ??
            const <String, dynamic>{'status': 'arrived'},
      };
      final lisiere = await _lisiere.ensureCreated(
        biomeIds: (sharedWorld['biomes'] as List)
            .whereType<Map>()
            .map((biome) => '${biome['biomeId']}')
            .toList(),
        seed: (region['seed'] as num?)?.toInt() ?? lisiereStableSeed(regionId),
        createdAt: DateTime.now(),
      );
      await _worldcraft.flushCampStorage(campId);
      sharedWorld['sharedStorage'] =
          await _worldcraft.loadCampStorage(campId) ?? const <String, dynamic>{};
      return _CampData(world: sharedWorld, lisiere: lisiere);
    }
    final region = Map<String, dynamic>.from(world['region'] as Map);
    final biomes = (world['biomes'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final lisiere = await _lisiere.ensureCreated(
      biomeIds: biomes.map((biome) => '${biome['id']}'),
      biomeConnections: <String, List<String>>{
        for (final biome in biomes)
          '${biome['id']}': List<String>.from(
            biome['connectedBiomeIds'] as List? ?? const <String>[],
          ),
      },
      seed: (region['seed'] as num?)?.toInt() ?? lisiereStableSeed('region-v2'),
      createdAt: DateTime.now(),
    );
    return _CampData(world: world, lisiere: lisiere);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CampData?>(
        future: _world,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final data = snapshot.data;
          final world = data?.world;
          if (world == null ||
              world['camp'] is! Map ||
              world['region'] is! Map) {
            return Scaffold(
              appBar: AppBar(title: const Text('PTIPOTE V2')),
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/game/v2'),
                  child: const Text('Commencer l’onboarding'),
                ),
              ),
            );
          }
          return _readyCamp(data!);
        },
      );

  Widget _readyCamp(_CampData data) {
    final world = data.world;
    final camp = Map<String, dynamic>.from(world['camp'] as Map);
    final region = Map<String, dynamic>.from(world['region'] as Map);
    final profileRaw = world['onboardingPtipote'];
    final profile = profileRaw is Map
        ? PtipoteV2Profile.fromFirebase(
            '${world['firstPtipoteId'] ?? 'ptipote-v2'}',
            profileRaw,
          )
        : null;
    final biomes = (world['biomes'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final sharedStorage = world['sharedStorage'];
    final campInventory = _sharedCampInventory(sharedStorage) ??
        data.lisiere.inventories['camp-storage-v2'] ??
        LisiereFieldInventory(id: 'camp-storage-v2', capacity: 0);
    final residents = (world['residents'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final buildings = world['buildings'] is Map
        ? Map<String, dynamic>.from(world['buildings'] as Map)
        : const <String, dynamic>{};
    final firstResident = world['firstResidentHook'] is Map
        ? Map<String, dynamic>.from(world['firstResidentHook'] as Map)
        : const <String, dynamic>{'status': 'pending'};
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PTIPOTE V2 · Camp'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Camp'),
              Tab(text: 'Maison'),
              Tab(text: 'Kernel'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _campTab(camp, region, biomes, campInventory, residents, buildings),
            _houseTab(profile),
            _kernelTab(firstResident, profile),
          ],
        ),
      ),
    );
  }

  Widget _campTab(
    Map<String, dynamic> camp,
    Map<String, dynamic> region,
    List<Map<String, dynamic>> biomes,
    LisiereFieldInventory campInventory,
    List<Map<String, dynamic>> residents,
    Map<String, dynamic> buildings,
  ) =>
      ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'ptipote-game/image_game/Camp.jpg',
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 180,
                child: Center(child: Icon(Icons.terrain, size: 64)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _infoCard('Cœur du Camp', 'Actif · palier 0'),
          _infoCard('Région', '${region['presetId'] ?? 'inconnue'}'),
          if (camp['pendingNarrative'] is Map)
            Card(
              child: ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Pendant ton absence'),
                subtitle: Text(
                  '${(camp['pendingNarrative'] as Map)['message'] ?? ''}',
                ),
              ),
            ),
          _infoCard(
            'Stock du Camp',
            campInventory.used == 0
                ? 'Vide'
                : '${campInventory.id == 'worldcraft-camp-storage' ? 'Partagé · ' : '${campInventory.used}/${campInventory.capacity} · '}${campInventory.amounts.entries.map((item) => '${item.key.label}: ${item.value}').join(' · ')}',
          ),
          _infoCard('Habitants', '${residents.length}/3 · bâtisseurs actifs'),
          ...residents.map(
            (resident) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('${resident['displayName'] ?? 'Habitant'}'),
                subtitle: Text(
                  'Envie de métier : ${resident['desiredJob'] ?? 'à découvrir'} · actuellement au chantier',
                ),
              ),
            ),
          ),
          ...buildings.entries.map((entry) {
            final building = entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : const <String, dynamic>{};
            final construction = building['construction'] is Map
                ? Map<String, dynamic>.from(building['construction'] as Map)
                : const <String, dynamic>{};
            final assistance =
                construction['assistanceEvents'] as List? ?? const <dynamic>[];
            final contributions =
                construction['resourceContributions'] as List? ??
                    const <dynamic>[];
            final remaining = _remainingConstruction(
                construction, assistance.length, contributions.length);
            final complete =
                remaining <= Duration.zero || building['state'] == 'active';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      const Text('⛺', style: TextStyle(fontSize: 30)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${building['buildingType'] ?? entry.key} · ${complete ? 'construit' : 'chantier'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(complete
                        ? 'Construit · accueille jusqu’à 3 habitants'
                        : 'Reste ${remaining.inHours} h · ${assistance.length} aide(s) · ${contributions.length} ressource(s) · 3 habitants'),
                    if (!complete) ...<Widget>[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                        FilledButton(
                          onPressed: () =>
                              _askConstructionHelp(entry.key, residents),
                          child: const Text('Aider · −3 h'),
                        ),
                        OutlinedButton(
                          onPressed: () => _contributeResource(
                            entry.key,
                            LisiereResourceKind.organic,
                          ),
                          child: const Text('🌿 Organique · −3 h'),
                        ),
                        OutlinedButton(
                          onPressed: () => _contributeResource(
                            entry.key,
                            LisiereResourceKind.mineral,
                          ),
                          child: const Text('🪨 Minéral · −3 h'),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed('/game/v2/lisiere'),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('Ouvrir la Lisière V2'),
          ),
          const SizedBox(height: 12),
          Text('Biomes de départ',
              style: Theme.of(context).textTheme.titleMedium),
          ...biomes.map(
            (biome) => Card(
              child: ListTile(
                leading: Icon(
                  biome['unlocked'] == true
                      ? Icons.explore
                      : Icons.lock_outline,
                ),
                title: Text('${biome['biomeType'] ?? 'Biome'}'),
                subtitle: Text(
                    '${biome['mapPosition'] ?? ''} · ${biome['unlocked'] == true ? 'accessible' : 'à découvrir'}'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Camp ${camp['id'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Future<void> _askConstructionHelp(
    String buildingId,
    List<Map<String, dynamic>> residents,
  ) async {
    final name = residents.isEmpty
        ? 'Un bâtisseur'
        : '${residents.first['displayName']}';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: const Text(
            '« Les tentes prennent forme. Tu peux nous donner un coup de main ? »'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Plus tard')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aider')),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }
    try {
      final message = await _foundation.helpConstruction(buildingId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        _reload();
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _contributeResource(
    String buildingId,
    LisiereResourceKind resource,
  ) async {
    try {
      final message = await _foundation.contributeConstructionResource(
        buildingId: buildingId,
        resource: resource,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        _reload();
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Duration _remainingConstruction(
    Map<String, dynamic> construction,
    int assistanceCount,
    int resourceCount,
  ) {
    final started = construction['startedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (construction['startedAt'] as num).toInt())
        : DateTime.now();
    final base = (construction['baseDurationSeconds'] as num?)?.toInt() ??
        const Duration(hours: 24).inSeconds;
    final reduction =
        (construction['assistanceReductionSeconds'] as num?)?.toInt() ??
            const Duration(hours: 3).inSeconds;
    final resourceReduction =
        (construction['resourceReductionSeconds'] as num?)?.toInt() ??
            const Duration(hours: 3).inSeconds;
    final remaining = Duration(
          seconds: base -
              reduction * assistanceCount -
              resourceReduction * resourceCount,
        ).inSeconds -
        DateTime.now().difference(started).inSeconds;
    return Duration(seconds: remaining.clamp(0, base));
  }

  Widget _houseTab(PtipoteV2Profile? profile) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'ptipote-game/image_game/Maison.jpg',
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 170,
                child: Center(child: Icon(Icons.home_outlined, size: 64)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Maison et Couveuse',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const Text('Le premier P’TIPOTE dispose de sa place au Camp.'),
          if (profile != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: PtipoteImage(
                        type: profile.typeId.name,
                        species: profile.natureId,
                        visualAssetKey: profile.visualAssetKey,
                        height: 92,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${profile.displayName}\n${profile.acquisitionOrigin == PtipoteAcquisitionOrigin.digitalAdoption ? 'Adoption numérique' : 'Figurine physique'}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _kernelTab(
          Map<String, dynamic> firstResident, PtipoteV2Profile? profile) =>
      ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'ptipote-game/image_game/Kernel.jpg',
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 170,
                child: Center(child: Icon(Icons.memory_outlined, size: 64)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Kernel',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          _infoCard('Données', '0'),
          _infoCard(
              'Premier habitant',
              firstResident['status'] == 'pending'
                  ? 'Crochet prêt pour une prochaine mécanique'
                  : '${firstResident['status']}'),
          _infoCard(
            'P’TIPOTE fondateur',
            profile != null && profile.displayName.isNotEmpty
                ? profile.displayName
                : 'En attente',
          ),
          const Text(
              'Les recherches et habitants V2 seront ajoutés ici sans reprendre la progression V1.'),
        ],
      );

  Widget _infoCard(String label, String value) => Card(
        child: ListTile(title: Text(label), trailing: Text(value)),
      );
}

class _CampData {
  const _CampData({required this.world, required this.lisiere});

  final Map<String, dynamic> world;
  final LisiereV2Snapshot lisiere;
}

LisiereFieldInventory? _sharedCampInventory(Object? rawStorage) {
  if (rawStorage is! Map) return null;
  final rawEntries = rawStorage['resourceEntries'];
  if (rawEntries is! Map) return null;
  final inventory = LisiereFieldInventory(
    id: 'worldcraft-camp-storage',
    capacity: 999999,
  );
  for (final resource in LisiereResourceKind.values) {
    final amount = rawEntries[resource.name];
    if (amount is num && amount > 0) inventory.add(resource, amount.toInt());
  }
  return inventory;
}
