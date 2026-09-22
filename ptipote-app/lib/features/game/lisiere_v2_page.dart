import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_image.dart';
import '../figurines/ptipote_stats_config.dart';
import '../figurines/ptipote_v2.dart';
import 'lisiere_v2.dart';
import 'lisiere_v2_service.dart';
import 'ptibug_config.dart';
import 'worldcraft_v2_service.dart';
import 'zone0_game_state.dart';
import 'zone0_v2_foundation_service.dart';

/// Persistent Lisière V2. Unlike the diagnostic simulation, every action here
/// reads the Region chosen in onboarding and writes the V2 expedition document.
class LisiereV2Page extends StatefulWidget {
  const LisiereV2Page({super.key});

  static const route = '/game/v2/lisiere';

  @override
  State<LisiereV2Page> createState() => _LisiereV2PageState();
}

class _LisiereV2PageState extends State<LisiereV2Page> {
  final _foundation = Zone0V2FoundationService();
  final _lisiere = LisiereV2Service();
  final _worldcraft = WorldcraftV2Service();
  final _figurines = FigurineService();
  Future<_LisiereContext>? _context;
  final Set<String> _draftPtipotes = <String>{};
  final Set<String> _draftPTibugs = <String>{};
  String? _selectedBiomeId;
  String? _selectedParcelId;
  final Set<String> _selectedParcelIds = <String>{};
  String? _selectedTeamId;
  String? _carrierId;
  LisiereMissionDuration _duration = LisiereMissionDuration.minutes30;
  LisiereHarvestRegime _missionRegime = LisiereHarvestRegime.normal;
  String _notice = '';
  Timer? _harvestTimer;
  bool _harvestInFlight = false;
  bool _trainingEnabled = false;
  String? _heldNodeId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _harvestTimer?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _context = _load());

  Future<_LisiereContext> _load() async {
    final world = await _foundation.load();
    if (world == null) {
      throw StateError('Le monde V2 n’a pas encore été créé.');
    }
    final selectedWorldcraft = world['worldcraft'];
    final Map<String, dynamic> region;
    final List<Map<String, dynamic>> biomes;
    if (selectedWorldcraft is Map) {
      final regionId = '${selectedWorldcraft['regionId'] ?? ''}';
      await _worldcraft.resolveRegionUntil(regionId);
      final sharedRegion = await _worldcraft.loadRegion(regionId);
      if (sharedRegion == null) {
        throw StateError('Région mondiale introuvable.');
      }
      region = sharedRegion;
      biomes = (await _worldcraft.loadBiomes(regionId))
          .map((biome) => <String, dynamic>{
                ...biome,
                'id': biome['biomeId'],
                'connectedBiomeIds': const <String>[],
              })
          .toList(growable: false);
    } else {
      if (world['region'] is! Map) {
        throw StateError('Le monde V2 n’a pas encore été créé.');
      }
      region = Map<String, dynamic>.from(world['region'] as Map);
      biomes = (world['biomes'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
    }
    LisiereV2Snapshot snapshot = await _lisiere.ensureCreated(
      biomeIds: biomes.map((biome) => '${biome['id']}'),
      biomeConnections: selectedWorldcraft is Map
          ? _worldcraftBiomeConnections(biomes)
          : <String, List<String>>{
              for (final biome in biomes)
                '${biome['id']}': List<String>.from(
                  biome['connectedBiomeIds'] as List? ?? const <String>[],
                ),
            },
      seed: (region['seed'] as num?)?.toInt() ?? lisiereStableSeed('region-v2'),
      createdAt: DateTime.now(),
      biomeSeeds: <String, int>{
        for (final biome in biomes)
          if (biome['seed'] is num)
            '${biome['id']}': (biome['seed'] as num).toInt(),
      },
    );
    if (selectedWorldcraft is Map) {
      snapshot = await _lisiere.syncSharedBiomeDanger(<String, int>{
        for (final biome in biomes)
          '${biome['id']}': (biome['danger'] as num?)?.toInt() ?? 0,
      });
    }
    final physical = await _figurines.watchMyFigurines().first;
    final linked = _linkedPtipotes(world, physical);
    if (linked.isNotEmpty) snapshot = await _lisiere.linkPtipotes(linked);
    if (snapshot.teams.isEmpty && linked.isNotEmpty) {
      snapshot = await _lisiere.createTeam(
        teamId: 'team-principale',
        ptipoteIds: <String>[linked.first.id],
      );
    }
    snapshot = await _lisiere.resolveAutonomousMissions(DateTime.now());
    snapshot = await _lisiere.resolvePTibugMaintenance(DateTime.now());
    for (final entry in snapshot.pendingToxicAfflictions.entries.toList()) {
      Zone0GameState.instance.applyLisiereToxicAffliction(
        ptipoteId: entry.value,
        encounterId: entry.key,
      );
      snapshot = await _lisiere.acknowledgeToxicAffliction(entry.key);
    }
    // Rest remains owned by the existing daily-life system. V2 only asks it
    // to take over once an expedition has left a P’TIPOTE below 30% vitality.
    for (final figurine in physical) {
      final expedition = snapshot.ptipotes[figurine.id];
      if (expedition != null &&
          expedition.currentVitality * 100 <= expedition.maxVitality * 30) {
        Zone0GameState.instance.sendToSleep(figurine);
      }
    }
    return _LisiereContext(
        world: world, biomes: biomes, snapshot: snapshot, physical: physical);
  }

  List<LisierePtipoteState> _linkedPtipotes(
    Map<String, dynamic> world,
    List<PtipoteFigurine> physical,
  ) {
    final rawProfiles = world['ptipotes'] as Map? ?? const <String, dynamic>{};
    final byId = <String, PtipoteFigurine>{
      for (final item in physical) item.id: item
    };
    return rawProfiles.entries
        .where((entry) => entry.value is Map)
        .map((entry) {
      final profile = PtipoteV2Profile.fromFirebase(
        '${entry.key}',
        Map<String, dynamic>.from(entry.value as Map),
      );
      final figurine = byId[profile.ptipoteId];
      final modifiers = PtipoteModifierService.resolve(
        profile: profile,
        config: ptipoteStatsConfig.v2,
        mycelialGatherBonus: 0,
      );
      return LisierePtipoteState(
        id: profile.ptipoteId,
        displayName: profile.displayName.isEmpty
            ? (figurine?.displayName ?? 'P’TIPOTE')
            : profile.displayName,
        currentVitality: figurine?.vitality ?? ptipoteStatsConfig.maxVitality,
        maxVitality: figurine?.maxVitality ?? ptipoteStatsConfig.maxVitality,
        carryCapacity: PtipoteModifierService.effectiveCarryCapacity(
          profile: profile,
          modifiers: modifiers,
        ),
        organicYieldModifier: 1 + modifiers.gather.forResource('Organique'),
        mineralYieldModifier: 1 + modifiers.gather.forResource('Minéral'),
        wasteYieldModifier: 1 + modifiers.gather.forResource('Déchets'),
        yieldModifier: 1 +
            <double>[
              modifiers.gather.forResource('Organique'),
              modifiers.gather.forResource('Minéral'),
              modifiers.gather.forResource('Déchets'),
            ].reduce((left, right) => left > right ? left : right),
        security: modifiers.missionSecurityBonus * 100,
      );
    }).toList();
  }

  Map<String, List<String>> _worldcraftBiomeConnections(
    List<Map<String, dynamic>> biomes,
  ) {
    final ids = biomes.map((biome) => '${biome['id']}').toList();
    if (ids.length != 5) {
      return <String, List<String>>{
        for (final id in ids) id: const <String>[],
      };
    }
    // The territorial central site is implicit: the five shared Biomes keep
    // their topology whether a Camp is free, active or autonomous.
    return <String, List<String>>{
      ids[0]: <String>[ids[1], ids[3]],
      ids[1]: <String>[ids[0], ids[2], ids[4]],
      ids[2]: <String>[ids[1]],
      ids[3]: <String>[ids[0]],
      ids[4]: <String>[ids[1]],
    };
  }

  Future<void> _run(
      Future<void> Function(_LisiereContext context) action) async {
    try {
      final contextData = await _context!;
      await action(contextData);
      if (mounted) _reload();
    } on StateError catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Action indisponible pour le moment.');
      }
    }
  }

  Future<void> _moveAndEnterBiome({
    required LisiereTeam team,
    required String parcelId,
    required String biomeId,
    required bool bossDroneActive,
  }) async {
    // Accompanied entry resolves the boss before the regular encounter. The
    // QTE is deliberately not a separate optional button: entering is enough.
    final qteSucceeded = bossDroneActive ? await _showBossQte() : true;
    if (!mounted) return;
    await _run((_) async {
      await _lisiere.moveAccompaniedTeam(
        teamId: team.id,
        targetParcelId: parcelId,
      );
      if (bossDroneActive) {
        await _lisiere.resolveBossDrone(
          biomeId: biomeId,
          teamId: team.id,
          accompaniedQteSucceeded: qteSucceeded == true,
        );
        if (qteSucceeded != true) return;
      }
      final event = await _lisiere.enterBiome(
        visitId:
            'visit-${team.id}-$biomeId-${DateTime.now().millisecondsSinceEpoch}',
        biomeId: biomeId,
        teamId: team.id,
      );
      if (event?.appliesToxicAffliction == true) {
        Zone0GameState.instance.applyLisiereToxicAffliction(
          ptipoteId: event!.ptipoteId,
          encounterId: event.visitId,
        );
      }
    });
  }

  void _startHarvest(String nodeId) {
    if (_selectedTeamId == null || _harvestInFlight) return;
    _harvestTimer?.cancel();
    _heldNodeId = nodeId;
    unawaited(_harvestTick());
    _harvestTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_harvestTick());
    });
    setState(() {});
  }

  void _stopHarvest() {
    _harvestTimer?.cancel();
    _harvestTimer = null;
    _heldNodeId = null;
    if (mounted) setState(() {});
  }

  Future<void> _harvestTick() async {
    final nodeId = _heldNodeId;
    final teamId = _selectedTeamId;
    if (nodeId == null || teamId == null || _harvestInFlight) return;
    _harvestInFlight = true;
    try {
      final data = await _context!;
      final team = data.snapshot.teams[teamId];
      if (team == null || team.ptipoteIds.isEmpty) return;
      final node = data.snapshot.nodes[nodeId];
      final collector = data.snapshot.ptipotes[team.ptipoteIds.first];
      final isSharedWorld =
          data.world['worldcraft'] is Map && _selectedBiomeId != null;
      // Detailed nodes remain a local visual projection. Mineral credits are
      // capped by the shared server reserve before they enter player cargo.
      final harvestPower =
          1 + (_trainingEnabled ? (collector?.harvestPower ?? 0) : 0);
      final mineralYield = node != null &&
              node.kind == LisiereResourceKind.mineral &&
              node.resistance - harvestPower <= 0
          ? (node.standardYield *
                      (_trainingEnabled
                          ? (collector?.yieldModifierFor(node.kind) ?? 1)
                          : 1) +
                  node.yieldRemainder)
              .floor()
          : 0;
      final sharedMineralLimit = isSharedWorld && mineralYield > 0
          ? await _worldcraft.extractSharedMineral(
              operationId:
                  'extract-$nodeId-${DateTime.now().microsecondsSinceEpoch}',
              biomeId: _selectedBiomeId!,
              requestedAmount: mineralYield,
            )
          : null;
      await _lisiere.harvestWithLinkedPtipote(
        actionId: 'hold-${DateTime.now().microsecondsSinceEpoch}',
        nodeId: nodeId,
        inventoryId: team.fieldInventoryId,
        ptipoteId: team.ptipoteIds.first,
        isTraining: _trainingEnabled,
        sharedMineralLimit: sharedMineralLimit,
      );
      if (isSharedWorld) {
        await _worldcraft.adjustBiomeDanger(
          operationId:
              'danger-harvest-$nodeId-${DateTime.now().microsecondsSinceEpoch}',
          biomeId: _selectedBiomeId!,
          delta: -1,
        );
      }
      if (mounted) _reload();
    } on StateError catch (error) {
      if (mounted) setState(() => _notice = error.message);
      _stopHarvest();
    } finally {
      _harvestInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_LisiereContext>(
        future: _context,
        builder: (context, result) {
          if (result.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (result.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Lisière V2')),
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/game/v2'),
                  child: const Text('Reprendre l’onboarding'),
                ),
              ),
            );
          }
          return _ready(result.requireData);
        },
      );

  Widget _ready(_LisiereContext data) {
    final snapshot = data.snapshot;
    final biomeId = _selectedBiomeId ?? snapshot.graphs.keys.firstOrNull;
    _selectedBiomeId ??= biomeId;
    _selectedTeamId ??= snapshot.teams.keys.firstOrNull;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Outil et équipement',
            icon: const Icon(Icons.person_outline),
            onPressed: () => _showLoadout(data.snapshot.playerLoadout),
          ),
          title: const Text('PTIPOTE V2 · Lisière'),
          actions: <Widget>[
            IconButton(
                tooltip: 'Actualiser',
                onPressed: _reload,
                icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(tabs: <Widget>[
            Tab(text: 'Carte'),
            Tab(text: 'Équipe'),
            Tab(text: 'Logistique'),
          ]),
        ),
        body: TabBarView(children: <Widget>[
          _mapTab(data, biomeId),
          _teamTab(data),
          _logisticsTab(data),
        ]),
      ),
    );
  }

  Widget _mapTab(_LisiereContext data, String? biomeId) {
    final snapshot = data.snapshot;
    final graph = biomeId == null ? null : snapshot.graphs[biomeId];
    final danger = biomeId == null ? null : snapshot.dangers[biomeId];
    final team =
        _selectedTeamId == null ? null : snapshot.teams[_selectedTeamId];
    final targets = graph?.parcels ?? const <ParcelInstance>[];
    final selectedBiome =
        data.biomes.where((biome) => biome['id'] == biomeId).firstOrNull;
    final sceneParcelId = _selectedParcelId ?? team?.currentParcelId;
    final sceneNodes = sceneParcelId == null
        ? const <LisiereResourceNode>[]
        : snapshot.nodes.values
            .where((node) => node.parcelId == sceneParcelId)
            .toList(growable: false);
    final scenePtipotes = team?.ptipoteIds
            .map((id) => _profileFor(data.world, id))
            .whereType<PtipoteV2Profile>()
            .toList(growable: false) ??
        const <PtipoteV2Profile>[];
    final sceneBugs = team?.ptibugIds
            .map((id) => _ptibugIcon(snapshot.ptibugs[id]?.speciesId))
            .toList(growable: false) ??
        const <String>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_notice.isNotEmpty) _noticeCard(),
        const Text('Région mondiale partagée',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _starterMissionCard(snapshot.starterMission),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: data.biomes
              .map((biome) => ChoiceChip(
                    label: Text('${biome['biomeType'] ?? biome['id']}'),
                    selected: biome['id'] == biomeId,
                    // A regional connection is the only gateway condition.
                    // Discovery presentation must never lock a valid route.
                    onSelected: (_) => setState(() {
                      _selectedBiomeId = '${biome['id']}';
                      _selectedParcelId = null;
                    }),
                  ))
              .toList(),
        ),
        if (danger != null)
          Card(
            child: ListTile(
              leading: Icon(danger.bossDroneActive
                  ? Icons.smart_toy
                  : Icons.warning_amber_outlined),
              title: Text('Danger ${danger.danger}/${danger.dangerCap}'),
              subtitle: Text(danger.bossDroneActive
                  ? 'Drone chef persistant · ${danger.lastBossDroneOutcome ?? 'à traiter'}'
                  : 'Progression hors ligne : +1 toutes les 2 h'),
            ),
          ),
        if (graph != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
              '${graph.parcels.length} parcelles · déplacements accompagnés instantanés',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _WorldbuildingParcelScene(
            biome: selectedBiome,
            nodes: sceneNodes,
            ptipotes: scenePtipotes,
            ptibugIcons: sceneBugs,
            active: sceneParcelId != null,
          ),
          const SizedBox(height: 8),
          if (team?.currentParcelId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '👣 Équipe en route / présente sur ${team!.currentParcelId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ...targets.map((parcel) {
            final selected = _selectedParcelIds.contains(parcel.id);
            final nodes = snapshot.nodes.values
                .where((node) => node.parcelId == parcel.id)
                .toList();
            return Card(
              color: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              child: Column(
                children: <Widget>[
                  ListTile(
                    onTap: () {
                      setState(() {
                        _selectedParcelId = parcel.id;
                        selected
                            ? _selectedParcelIds.remove(parcel.id)
                            : _selectedParcelIds.add(parcel.id);
                      });
                      if (team != null && biomeId != null) {
                        unawaited(_moveAndEnterBiome(
                          team: team,
                          parcelId: parcel.id,
                          biomeId: biomeId,
                          bossDroneActive: danger?.bossDroneActive ?? false,
                        ));
                      }
                    },
                    leading: const Icon(Icons.landscape_outlined),
                    title: Text('Parcelle ${parcel.ordinal + 1}'),
                    subtitle:
                        Text('${parcel.connectedParcelIds.length} liaison(s)'),
                  ),
                  if (team?.currentParcelId == parcel.id)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          const Text('Équipe :'),
                          ...team!.ptipoteIds.map((id) {
                            final profile = _profileFor(data.world, id);
                            return profile == null
                                ? const Icon(Icons.pets)
                                : SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: PtipoteImage(
                                      type: profile.typeId.name,
                                      species: profile.natureId,
                                      visualAssetKey: profile.visualAssetKey,
                                      height: 34,
                                    ),
                                  );
                          }),
                          ...team.ptibugIds.map((id) => Text(
                                _ptibugIcon(snapshot.ptibugs[id]?.speciesId),
                                style: const TextStyle(fontSize: 26),
                              )),
                        ],
                      ),
                    ),
                  ...nodes.map(
                    (node) => GestureDetector(
                      onTapDown:
                          team == null ? null : (_) => _startHarvest(node.id),
                      onTapUp: team == null ? null : (_) => _stopHarvest(),
                      onTapCancel: _stopHarvest,
                      child: ListTile(
                        dense: true,
                        leading: Text(node.visualVariant,
                            style: const TextStyle(fontSize: 24)),
                        title: Text(node.kind == LisiereResourceKind.organic
                            ? 'Nœud Organique'
                            : node.kind == LisiereResourceKind.mineral
                                ? 'Nœud Minéral'
                                : 'Nœud Déchets'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(_heldNodeId == node.id
                                ? 'Outil actif · 1 dégât/s'
                                : 'Maintenir appuyé pour utiliser l’outil'),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: (node.resistance / node.maxResistance)
                                  .clamp(0, 1),
                              minHeight: 8,
                              color: Colors.redAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            ActionChip(
              avatar: const Icon(Icons.construction_outlined),
              label: const Text('Multi-outils'),
              onPressed: () => _showToolDetails(),
            ),
            ActionChip(
              avatar: const Icon(Icons.shield_outlined),
              label: Text(snapshot.playerLoadout.equipmentId == null
                  ? 'Équipement vide'
                  : 'Équipement'),
              onPressed: () => _showLoadout(snapshot.playerLoadout),
            ),
            FilterChip(
              selected: _trainingEnabled,
              onSelected: team == null
                  ? null
                  : (value) => setState(() => _trainingEnabled = value),
              avatar: const Icon(Icons.school_outlined),
              label: const Text('Entraîner le Récolteur'),
            ),
            const Chip(
              avatar: Icon(Icons.explore_outlined),
              label: Text('Entrer sur une parcelle déclenche les rencontres'),
            ),
          ]),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: biomeId == null
                ? null
                : () => _run((_) async {
                      await _lisiere.buildOutpost(
                          biomeId: biomeId, parcelId: _selectedParcelId);
                    }),
            icon: const Icon(Icons.cabin_outlined),
            label: const Text('Construire un avant-poste'),
          ),
        ],
      ],
    );
  }

  Widget _teamTab(_LisiereContext data) {
    final snapshot = data.snapshot;
    final ptipotes = snapshot.ptipotes.values.toList();
    final selectedTeam =
        _selectedTeamId == null ? null : snapshot.teams[_selectedTeamId];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_notice.isNotEmpty) _noticeCard(),
        const Text('P’TIPOTES réels et métiers V2',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Text(
            'Les vitalités sont prises à la figurine au premier lien, puis persistées pour l’expédition.'),
        ...ptipotes.map((ptipote) {
          final profile = _profileFor(data.world, ptipote.id);
          final recolteur = snapshot
              .jobProgress['${ptipote.id}:${LisierePtipoteJob.recolteur.name}'];
          final patrol = snapshot.jobProgress[
              '${ptipote.id}:${LisierePtipoteJob.patrouilleur.name}'];
          return Card(
              child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: <Widget>[
              if (profile != null)
                SizedBox(
                    width: 58,
                    height: 58,
                    child: PtipoteImage(
                        type: profile.typeId.name,
                        species: profile.natureId,
                        visualAssetKey: profile.visualAssetKey,
                        height: 58)),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(ptipote.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        'Vitalité ${ptipote.currentVitality}/${ptipote.maxVitality}'),
                    Text(
                        'Récolteur ${recolteur?.currentProgress ?? 0}/${recolteur?.requiredProgress ?? lisiereV2Config.recolteurActionsForN1} · Patrouilleur ${patrol?.currentProgress ?? 0}/${patrol?.requiredProgress ?? lisiereV2Config.patrouilleurExperienceForN1}'),
                  ])),
              Checkbox(
                value: _draftPtipotes.contains(ptipote.id),
                onChanged: (value) => setState(() => value == true
                    ? _draftPtipotes.add(ptipote.id)
                    : _draftPtipotes.remove(ptipote.id)),
              ),
              PopupMenuButton<LisierePtipoteJob>(
                onSelected: (job) => _run((_) async =>
                    _lisiere.assignJob(ptipoteId: ptipote.id, job: job)),
                itemBuilder: (_) => const <PopupMenuEntry<LisierePtipoteJob>>[
                  PopupMenuItem(
                      value: LisierePtipoteJob.recolteur,
                      child: Text('Métier : Récolteur')),
                  PopupMenuItem(
                      value: LisierePtipoteJob.patrouilleur,
                      child: Text('Métier : Patrouilleur')),
                ],
              ),
            ]),
          ));
        }),
        if (snapshot.ptibugs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const Text('Transporteurs P’TIBUG',
              style: TextStyle(fontWeight: FontWeight.w700)),
          ...snapshot.ptibugs.values.map((bug) => CheckboxListTile(
                value: _draftPTibugs.contains(bug.id),
                onChanged: (value) => setState(() => value == true
                    ? _draftPTibugs.add(bug.id)
                    : _draftPTibugs.remove(bug.id)),
                title: Text('${bug.displayName} · capacité ${bug.capacity}'),
                subtitle: const Text('Prioritaire pour les rotations'),
              )),
          DropdownButtonFormField<String>(
            initialValue: _carrierId,
            decoration: const InputDecoration(labelText: 'Porteur prioritaire'),
            hint: const Text('P’TIBUG désigné'),
            items: snapshot.ptibugs.values
                .map((bug) => DropdownMenuItem<String>(
                      value: bug.id,
                      child: Text(bug.displayName),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _carrierId = value),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _draftPtipotes.isEmpty
              ? null
              : () => _run((_) async {
                    await _lisiere.createTeam(
                      teamId: 'team-principale',
                      ptipoteIds: _draftPtipotes.toList(),
                      ptibugIds: <String>[
                        if (_carrierId != null &&
                            _draftPTibugs.contains(_carrierId))
                          _carrierId!,
                        ..._draftPTibugs.where((id) => id != _carrierId),
                      ],
                    );
                    _selectedTeamId = 'team-principale';
                  }),
          child: const Text('Créer / mettre à jour l’équipe'),
        ),
        const SizedBox(height: 16),
        if (selectedTeam != null) ...<Widget>[
          Text('Mission autonome · équipe ${selectedTeam.id}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Wrap(
              spacing: 8,
              children: LisiereMissionDuration.values
                  .map((value) => ChoiceChip(
                        label: Text(_durationLabel(value)),
                        selected: value == _duration,
                        onSelected: (_) => setState(() => _duration = value),
                      ))
                  .toList()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: LisiereHarvestRegime.values
                .map((regime) => ChoiceChip(
                      label: Text('Rythme ${regime.name}'),
                      selected: regime == _missionRegime,
                      onSelected: (_) =>
                          setState(() => _missionRegime = regime),
                    ))
                .toList(),
          ),
          Builder(builder: (context) {
            final targets = _selectedParcelIds.isEmpty
                ? (_selectedParcelId == null
                    ? const <String>[]
                    : <String>[_selectedParcelId!])
                : _selectedParcelIds.toList();
            final travel = _lisiere.estimateAutonomousTravel(
              snapshot,
              selectedTeam,
              targets,
            );
            final cargoCapacity = <String>[
              ...selectedTeam.ptibugIds.map((id) => 'ptibug-$id-cargo'),
              ...selectedTeam.ptipoteIds.map((id) => 'ptipote-$id-cargo'),
            ].fold<int>(
                0,
                (sum, id) =>
                    sum + (snapshot.inventories[id]?.remainingCapacity ?? 0));
            final members = selectedTeam.ptipoteIds
                .map((id) => snapshot.ptipotes[id])
                .whereType<LisierePtipoteState>()
                .toList();
            final security = members.isEmpty
                ? 0.0
                : members.fold<double>(0, (sum, item) => sum + item.security) /
                    members.length;
            final canFit = travel < _duration.duration;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Trajet estimé : ${_durationText(travel)}'),
                    Text(
                        'Fenêtre de récolte : ${_durationText(_duration.duration - travel)}'),
                    Text('Capacité disponible : $cargoCapacity'),
                    Text(
                        'Sécurité de groupe : ${security.toStringAsFixed(0)} %'),
                    Text(
                        'Vitalité P’TIPOTE : ${members.map((item) => '${item.currentVitality}/${item.maxVitality}').join(' · ')}'),
                    if (!canFit)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠️ Durée trop courte pour couvrir le trajet aller-retour.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    if (cargoCapacity == 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                            '⚠️ Aucun inventaire de mission disponible.',
                            style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
            );
          }),
          FilledButton.tonal(
            onPressed: _selectedParcelId == null
                ? null
                : () => _run((_) async {
                      await _lisiere.startAutonomousMission(
                        missionId:
                            'mission-${DateTime.now().microsecondsSinceEpoch}',
                        teamId: selectedTeam.id,
                        targetParcelIds: _selectedParcelIds.isEmpty
                            ? <String>[_selectedParcelId!]
                            : _selectedParcelIds.toList(),
                        duration: _duration,
                        regime: _missionRegime,
                        startedAt: DateTime.now(),
                      );
                    }),
            child: const Text('Lancer la mission autonome'),
          ),
        ],
        ...snapshot.missions.values.map((mission) => Card(
                child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text('Mission ${mission.status.name}'),
              subtitle: Text(
                  '${mission.targetParcelIds.length} cible(s) · ${mission.regime.name}\n'
                  'Trajet ${_durationText(mission.travelDuration)} · étape ${mission.stageAt(DateTime.now()).name} · fin ${_time(mission.plannedEndAt)}\n'
                  'Cargaison ${_missionCargo(snapshot, mission.teamId)} · temps restant ${_durationText(mission.plannedEndAt.difference(DateTime.now()))}'),
              isThreeLine: true,
            ))),
        OutlinedButton.icon(
          onPressed: () => _run(
              (_) async => _lisiere.resolveAutonomousMissions(DateTime.now())),
          icon: const Icon(Icons.update),
          label: const Text('Calculer les retours hors ligne'),
        ),
      ],
    );
  }

  Widget _logisticsTab(_LisiereContext data) {
    final snapshot = data.snapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_notice.isNotEmpty) _noticeCard(),
        const Text('Avant-postes, rotations et P’TIBUG',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ...snapshot.inventories.values
            .where((inventory) =>
                inventory.id.startsWith('ptipote-') ||
                inventory.id.startsWith('ptibug-'))
            .map((inventory) => Card(
                  child: ListTile(
                    leading: Icon(
                      inventory.remainingCapacity == 0
                          ? Icons.scale
                          : Icons.inventory_2_outlined,
                      color:
                          inventory.remainingCapacity == 0 ? Colors.red : null,
                    ),
                    title: Text(inventory.id.startsWith('ptibug-')
                        ? 'Cargaison P’TIBUG'
                        : 'Cargaison P’TIPOTE'),
                    subtitle: Text(
                      '${inventory.used}/${inventory.capacity} · ${inventory.amounts.entries.map((entry) => '${entry.key.name}: ${entry.value}').join(' · ').ifEmpty('vide')}',
                    ),
                  ),
                )),
        ...snapshot.outposts.values.map((outpost) => Card(
                child: ListTile(
              leading: const Icon(Icons.cabin_outlined),
              title: Text('Avant-poste · ${outpost.biomeId}'),
              subtitle: Text('Stock ${outpost.storageId} · ${outpost.state}'),
            ))),
        if (snapshot.outposts.isEmpty)
          const Text(
              'Aucun avant-poste : un seul pourra être construit par biome.'),
        const SizedBox(height: 12),
        ...snapshot.rotations.values.map((rotation) => Card(
                child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text('Rotation ${rotation.state.name}'),
              subtitle: Text(
                  '${rotation.originInventoryId} → ${rotation.destinationInventoryId}'),
              trailing: IconButton(
                tooltip: 'Avancer',
                icon: const Icon(Icons.arrow_forward),
                onPressed: rotation.state == LisiereCargoRotationState.completed
                    ? null
                    : () => _run(
                        (_) async => _lisiere.advanceRotation(rotation.id)),
              ),
            ))),
        if (_selectedTeamId != null)
          FilledButton.tonalIcon(
            onPressed: () => _run(
              (_) async => _lisiere.startReturnRotation(
                teamId: _selectedTeamId!,
              ),
            ),
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Ramener la cargaison au Camp'),
          ),
        const Divider(),
        ...snapshot.ptibugs.values.map((bug) => Card(
                child: ListTile(
              leading: Text(_ptibugIcon(bug.speciesId),
                  style: const TextStyle(fontSize: 28)),
              title: Text('${bug.displayName} · transport ${bug.capacity}'),
              subtitle: Text(
                  '${bug.speciesId} · ${bug.traitDefinitionIds.isEmpty ? 'sans trait de récolte' : bug.traitDefinitionIds.join(', ')}\n'
                  'Vitalité ${bug.currentVitality}/${bug.maxVitality} · autonomie ${(bug.maintenance.rationReserve / bug.maintenance.dailyRation * Duration.hoursPerDay).toStringAsFixed(1)} h · ${bug.maintenance.isSleeping ? 'repos' : 'actif'}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Ravitaillement 8 h (coût V1)',
                icon: const Icon(Icons.restaurant),
                onPressed: () => _run((_) async => _lisiere.feedPTibug(
                      ptibugId: bug.id,
                      ration: pTibugConfig.cultivation.targetAutonomyHours
                          .toDouble(),
                    )),
              ),
            ))),
        OutlinedButton.icon(
          onPressed: () => _run(
              (_) async => _lisiere.resolvePTibugMaintenance(DateTime.now())),
          icon: const Icon(Icons.schedule),
          label: const Text('Mettre à jour la maintenance'),
        ),
        OutlinedButton.icon(
          onPressed: () => _run((_) async {
            await Zone0GameState.instance.loadFromFirebase();
            await _lisiere.linkPTibugs(
                Zone0GameState.instance.pTibugs.map((bug) => LisierePTibugState(
                      id: bug.id,
                      displayName: bug.displayName,
                      capacity: _ptibugCarryCapacity(bug),
                      speciesId: bug.species.name,
                      traitDefinitionIds: _ptibugTraits(bug),
                      maintenance: LisierePTibugMaintenance(
                          ptibugId: bug.id,
                          dailyRation: 1,
                          lastResolvedAt: DateTime.now()),
                    )));
          }),
          icon: const Icon(Icons.link),
          label: const Text('Relier les P’TIBUG V1 réels'),
        ),
      ],
    );
  }

  PtipoteV2Profile? _profileFor(Map<String, dynamic> world, String id) {
    final raw = world['ptipotes'] as Map?;
    final value = raw?[id];
    return value is Map
        ? PtipoteV2Profile.fromFirebase(id, Map<String, dynamic>.from(value))
        : null;
  }

  Widget _starterMissionCard(LisiereStarterMission mission) => Card(
        color: mission.isCompleted
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.primaryContainer,
        child: ListTile(
          leading: Icon(
            mission.isCompleted ? Icons.check_circle : Icons.campaign,
          ),
          title: Text(
            mission.isCompleted
                ? 'Premiers matériaux livrés'
                : 'Première mission',
          ),
          subtitle: Text(mission.isCompleted
              ? 'Les ${mission.organicsRequired} Organique et ${mission.mineralsRequired} Minéral sont au Camp.'
              : mission.message),
        ),
      );

  int _ptibugCarryCapacity(PTibug bug) {
    final reservoirLevels = Zone0GameState.instance.pTibugModuleInstances
        .where((item) =>
            item.equippedPTibugId == bug.id &&
            item.type == PTibugModuleType.reservoir)
        .map((item) => item.qualityLevel);
    final reservoirLevel = reservoirLevels.isEmpty
        ? (bug.hasModule(PTibugModuleType.reservoir) ? 1 : 0)
        : reservoirLevels.reduce(
            (first, second) => first > second ? first : second,
          );
    final baseCapacity = pTibugConfig.carryingCapacity +
        (reservoirLevel == 0
            ? 0
            : pTibugConfig.reservoirCapacityForLevel(reservoirLevel));
    return (baseCapacity * pTibugConfig.storageMultiplier).clamp(1, 99999);
  }

  List<String> _ptibugTraits(PTibug bug) {
    final traitsById = <String, String>{
      for (final trait in Zone0GameState.instance.pTibugTraitData)
        trait.id: trait.definitionId,
    };
    return <String?>[
      bug.biologicalTraitId,
      bug.secondTraitId,
    ].whereType<String>().map((id) => traitsById[id] ?? id).toSet().toList();
  }

  String _ptibugIcon(String? speciesId) => switch (speciesId) {
        'scarabe' => '🪲',
        'hyme' => '🐝',
        'arac' => '🕷️',
        _ => '🐛',
      };

  Widget _noticeCard() => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(_notice)),
      );

  Future<void> _showToolDetails() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Multi-outils de base'),
          content: const Text(
            'Outil de départ\n\nRécolte : 1 action par seconde.\nDégâts sur un nœud : 1 par seconde.\n\nMaintiens un nœud dans la Lisière pour l’utiliser.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Compris'),
            ),
          ],
        ),
      );

  Future<void> _showLoadout(LisierePlayerLoadout loadout) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Personnage · équipement'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            ListTile(
              leading: const Icon(Icons.construction_outlined),
              title: const Text('Slot Outil'),
              subtitle: const Text('Multi-outils de base · 1 récolte/s'),
              onTap: () {
                Navigator.of(context).pop();
                _showToolDetails();
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Slot Équipement'),
              subtitle: Text(loadout.equipmentId == null
                  ? 'Vide · réservé aux protections et bonus futurs'
                  : loadout.equipmentId!),
            ),
          ]),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );

  String _durationLabel(LisiereMissionDuration duration) => switch (duration) {
        LisiereMissionDuration.minutes30 => '30 min',
        LisiereMissionDuration.hour1 => '1 h',
        LisiereMissionDuration.hours2 => '2 h',
        LisiereMissionDuration.hours4 => '4 h',
        LisiereMissionDuration.hours8 => '8 h',
      };

  String _durationText(Duration duration) {
    final value = duration.isNegative ? Duration.zero : duration;
    if (value.inHours > 0) {
      return '${value.inHours} h ${value.inMinutes % 60} min';
    }
    if (value.inMinutes > 0) return '${value.inMinutes} min';
    return '${value.inSeconds} s';
  }

  String _missionCargo(LisiereV2Snapshot snapshot, String teamId) {
    final team = snapshot.teams[teamId];
    if (team == null) return '—';
    final amount = <String>[
      ...team.ptibugIds.map((id) => 'ptibug-$id-cargo'),
      ...team.ptipoteIds.map((id) => 'ptipote-$id-cargo'),
    ].fold<int>(0, (sum, id) => sum + (snapshot.inventories[id]?.used ?? 0));
    return '$amount';
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<bool?> _showBossQte() => showDialog<bool>(
        context: context,
        builder: (_) => const _BossDroneQteDialog(),
      );
}

/// A deliberately light 2D / 3⁄4 projection. Positions are generated from
/// persisted parcel and Biome seeds elsewhere; this widget only gives the
/// player a readable local scene and never claims it is a synchronized MMO
/// terrain renderer.
class _WorldbuildingParcelScene extends StatelessWidget {
  const _WorldbuildingParcelScene({
    required this.biome,
    required this.nodes,
    required this.ptipotes,
    required this.ptibugIcons,
    required this.active,
  });

  final Map<String, dynamic>? biome;
  final List<LisiereResourceNode> nodes;
  final List<PtipoteV2Profile> ptipotes;
  final List<String> ptibugIcons;
  final bool active;

  Color get _ground => switch (
          '${biome?['visualProfile'] is Map ? (biome!['visualProfile'] as Map)['groundSet'] : ''}') {
        'shore' => const Color(0xff8ebdcc),
        'wet_roots' || 'marsh' => const Color(0xff607c67),
        'sand' => const Color(0xffc8a56a),
        'highland' || 'hillside' => const Color(0xff777a70),
        'leaf_litter' || 'dry_forest' || 'dry_grass' => const Color(0xff9b8752),
        _ => const Color(0xff628b63),
      };

  @override
  Widget build(BuildContext context) {
    final orderedNodes = nodes.indexed
        .map((entry) =>
            (index: entry.$1, node: entry.$2, y: 88.0 + entry.$1 * 27.0))
        .toList()
      ..sort((left, right) => left.y.compareTo(right.y));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 8.5,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParcelGroundPainter(_ground),
                ),
              ),
              Positioned(
                top: 8,
                left: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      active
                          ? '${biome?['biomeType'] ?? 'Biome'} · parcelle active'
                          : '${biome?['biomeType'] ?? 'Biome'} · choisir une parcelle',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              ...orderedNodes.map((item) => Positioned(
                    left: 32.0 + (item.index % 3) * constraints.maxWidth * .26,
                    top: item.y,
                    child: Opacity(
                      opacity:
                          item.node.state == LisiereResourceNodeState.available
                              ? 1
                              : .42,
                      child: Text(item.node.visualVariant,
                          style:
                              const TextStyle(fontSize: 27, shadows: <Shadow>[
                            Shadow(
                                color: Colors.black45,
                                offset: Offset(2, 3),
                                blurRadius: 2),
                          ])),
                    ),
                  )),
              ...ptipotes.indexed.map((entry) => Positioned(
                    left: constraints.maxWidth * (.36 + entry.$1 * .13),
                    top: constraints.maxHeight * (.56 + entry.$1 * .05),
                    child: SizedBox(
                      width: 44,
                      height: 52,
                      child: PtipoteImage(
                        type: entry.$2.typeId.name,
                        species: entry.$2.natureId,
                        visualAssetKey: entry.$2.visualAssetKey,
                        height: 52,
                      ),
                    ),
                  )),
              ...ptibugIcons.indexed.map((entry) => Positioned(
                    left: constraints.maxWidth * (.61 + entry.$1 * .08),
                    top: constraints.maxHeight * (.61 + entry.$1 * .05),
                    child: Text(entry.$2,
                        style: const TextStyle(fontSize: 29, shadows: <Shadow>[
                          Shadow(
                              color: Colors.black45,
                              offset: Offset(2, 3),
                              blurRadius: 2),
                        ])),
                  )),
              const Positioned(
                right: 8,
                bottom: 6,
                child: Text('projection locale',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParcelGroundPainter extends CustomPainter {
  const _ParcelGroundPainter(this.ground);

  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xff26312b));
    final land = Path()
      ..moveTo(size.width * .08, size.height * .27)
      ..lineTo(size.width * .88, size.height * .16)
      ..lineTo(size.width * .98, size.height * .72)
      ..lineTo(size.width * .16, size.height * .91)
      ..close();
    canvas.drawPath(
      land.shift(const Offset(0, 5)),
      Paint()..color = Colors.black26,
    );
    canvas.drawPath(land, Paint()..color = ground);
    for (var index = 0; index < 5; index++) {
      final y = size.height * (.32 + index * .12);
      canvas.drawLine(
        Offset(size.width * .14, y),
        Offset(size.width * .9, y - size.height * .1),
        Paint()
          ..color = Colors.white.withValues(alpha: .09)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParcelGroundPainter oldDelegate) =>
      oldDelegate.ground != ground;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

enum _BossQteDirection { up, down, left, right }

class _BossQteIntent extends Intent {
  const _BossQteIntent(this.direction);
  final _BossQteDirection direction;
}

class _BossDroneQteDialog extends StatefulWidget {
  const _BossDroneQteDialog();

  @override
  State<_BossDroneQteDialog> createState() => _BossDroneQteDialogState();
}

class _BossDroneQteDialogState extends State<_BossDroneQteDialog> {
  static const _sequence = <_BossQteDirection>[
    _BossQteDirection.up,
    _BossQteDirection.right,
    _BossQteDirection.down,
    _BossQteDirection.left,
  ];
  var _step = 0;

  void _receive(_BossQteDirection direction) {
    if (direction != _sequence[_step]) {
      Navigator.of(context).pop(false);
      return;
    }
    _step += 1;
    if (_step == _sequence.length) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp):
              _BossQteIntent(_BossQteDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _BossQteIntent(_BossQteDirection.down),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _BossQteIntent(_BossQteDirection.left),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _BossQteIntent(_BossQteDirection.right),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _BossQteIntent: CallbackAction<_BossQteIntent>(
              onInvoke: (intent) {
                _receive(intent.direction);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: const Text('Drone chef'),
              content: Text(
                'Saisis avec les flèches : ${_sequence.map(_bossArrow).join('  ')}\n'
                'Étape ${_step + 1}/${_sequence.length}',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Se replier'),
                ),
              ],
            ),
          ),
        ),
      );

  static String _bossArrow(_BossQteDirection direction) => switch (direction) {
        _BossQteDirection.up => '↑',
        _BossQteDirection.down => '↓',
        _BossQteDirection.left => '←',
        _BossQteDirection.right => '→',
      };
}

class _LisiereContext {
  const _LisiereContext(
      {required this.world,
      required this.biomes,
      required this.snapshot,
      required this.physical});
  final Map<String, dynamic> world;
  final List<Map<String, dynamic>> biomes;
  final LisiereV2Snapshot snapshot;
  final List<PtipoteFigurine> physical;
}
