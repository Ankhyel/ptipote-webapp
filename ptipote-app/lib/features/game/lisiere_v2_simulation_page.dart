import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_image.dart';
import 'lisiere_v2.dart';
import 'zone0_game_state.dart';

/// Local, playable V2 vertical slice. Its state is deliberately built from
/// the same serializable domain objects that the Firestore resolver will use.
class LisiereV2SimulationPage extends StatefulWidget {
  const LisiereV2SimulationPage({super.key, this.gameState});

  static const route = '/game/v2/lisiere-simulation';
  final Zone0GameState? gameState;

  @override
  State<LisiereV2SimulationPage> createState() =>
      _LisiereV2SimulationPageState();
}

enum _Direction { up, down, left, right }

class _DirectionIntent extends Intent {
  const _DirectionIntent(this.direction);
  final _Direction direction;
}

class _LisiereV2SimulationPageState extends State<LisiereV2SimulationPage> {
  final FigurineService _figurineService = FigurineService();
  late final LisiereV2Snapshot _world;
  late LisiereResourceNode _node;
  Timer? _harvestTimer;
  String _ptipoteId = 'simulation-ptipote';
  int _vitality = 100;
  final int _maxVitality = 100;
  double _security = 40;
  LisiereEncounterResolution? _pendingEncounter;
  bool _pendingBossDrone = false;
  List<_Direction> _qte = const <_Direction>[];
  int _qteStep = 0;
  String _eventLog = 'Explore une parcelle, puis maintiens Récolter.';

  LisiereFieldInventory get _fieldInventory =>
      _world.inventories['field-simulation']!;

  LisiereJobProgress get _recolteur =>
      _world.jobProgress['$_ptipoteId:${LisierePtipoteJob.recolteur.name}'] ??
      LisiereJobProgress(
        ptipoteId: _ptipoteId,
        job: LisierePtipoteJob.recolteur,
      );

  LisiereJobProgress get _patrouilleur =>
      _world
          .jobProgress['$_ptipoteId:${LisierePtipoteJob.patrouilleur.name}'] ??
      LisiereJobProgress(
        ptipoteId: _ptipoteId,
        job: LisierePtipoteJob.patrouilleur,
      );

  @override
  void initState() {
    super.initState();
    _world = createLisiereV2Snapshot(
      biomeIds: const <String>['lisiere-simulation'],
      seed: 20260918,
      createdAt: DateTime.now(),
    );
    _world.inventories['field-simulation'] =
        LisiereFieldInventory(id: 'field-simulation', capacity: 30);
    _node = _world.nodes.values.first;
  }

  @override
  void dispose() {
    _harvestTimer?.cancel();
    super.dispose();
  }

  void _storeProgress(LisiereJobProgress progress) {
    _world.jobProgress['${progress.ptipoteId}:${progress.job.name}'] = progress;
  }

  void _harvestOnce() {
    if (_node.state != LisiereResourceNodeState.available) return;
    final resolution = _node.applyAction(
      LisiereHarvestActor(
        id: _ptipoteId,
        harvestPower: 1,
        actionFrequency: 4,
        yieldModifier: 1,
        maxVitality: _maxVitality,
        currentVitality: _vitality,
      ),
    );
    _storeProgress(_recolteur.recordHarvestAction());
    if (resolution.creditedAmount > 0) {
      final accepted = _fieldInventory.add(
        resolution.resource,
        resolution.creditedAmount,
      );
      _eventLog = accepted == resolution.creditedAmount
          ? '${_node.visualVariant} +$accepted dans le stock de terrain.'
          : 'Stock de terrain plein : $accepted/${resolution.creditedAmount} récupérés.';
    }
    setState(() {});
  }

  void _startHarvest() {
    _harvestOnce();
    _harvestTimer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _harvestOnce(),
    );
  }

  void _stopHarvest() {
    _harvestTimer?.cancel();
    _harvestTimer = null;
  }

  void _startPatrol(LisiereEncounterResolution encounter) {
    _stopHarvest();
    _pendingEncounter = encounter;
    _storeProgress(_patrouilleur.recordPatrolEncounter());
    _qte = const <_Direction>[
      _Direction.up,
      _Direction.right,
      _Direction.down,
      _Direction.left,
    ];
    _qteStep = 0;
    _eventLog = 'Rencontre : saisis la séquence avec les flèches du clavier.';
    setState(() {});
  }

  void _startBossDrone() {
    _stopHarvest();
    _world.dangers['lisiere-simulation']!.bossDroneActive = true;
    _pendingBossDrone = true;
    _startPatrol(
      defaultLisiereEncounterResolutions[LisiereEncounterType.standardDrone]!,
    );
  }

  void _receiveDirection(_Direction direction) {
    if (_pendingEncounter == null || _qte.isEmpty) return;
    if (_qte[_qteStep] != direction) {
      _eventLog = 'QTE raté. La patrouille se replie sans gain de QTE.';
      _pendingEncounter = null;
      _pendingBossDrone = false;
      _qte = const <_Direction>[];
      _qteStep = 0;
      setState(() {});
      return;
    }
    _qteStep += 1;
    if (_qteStep < _qte.length) {
      setState(() {});
      return;
    }
    final encounter = _pendingEncounter!;
    _storeProgress(_patrouilleur.recordPatrolQte());
    if (_pendingBossDrone) {
      final outcome = resolveAutonomousBossDrone(groupSecurity: _security);
      if (outcome == BossDroneOutcome.neutralized) {
        _world.dangers['lisiere-simulation']!.bossDroneActive = false;
        _eventLog = 'Drone chef neutralisé : sécurité de groupe suffisante.';
      } else {
        _applyEncounter(encounter);
        _eventLog =
            'Drone chef : sécurité insuffisante, drone standard puis retour immédiat.';
      }
      _pendingBossDrone = false;
    } else {
      _applyEncounter(encounter);
    }
    _pendingEncounter = null;
    _qte = const <_Direction>[];
    _qteStep = 0;
    setState(() {});
  }

  void _applyEncounter(LisiereEncounterResolution encounter) {
    var remainingLoss = encounter.cargoLost(_fieldInventory.used);
    for (final resource in LisiereResourceKind.values) {
      if (remainingLoss <= 0) break;
      remainingLoss -= _fieldInventory.remove(resource, remainingLoss);
    }
    _vitality = encounter.vitalityAfter(
      currentVitality: _vitality,
      maxVitality: _maxVitality,
      requiredReturnVitality: defaultLisiereV2Config.returnSafetyReserve,
    );
    if (encounter.appliesToxicAffliction) {
      final applied = (widget.gameState ?? Zone0GameState.instance)
          .applyLisiereToxicAffliction(
        ptipoteId: _ptipoteId,
        encounterId: 'simulation-${DateTime.now().microsecondsSinceEpoch}',
      );
      _eventLog = applied
          ? 'Nuage toxique : Intoxiqué appliqué via le système météo V1.'
          : 'Nuage toxique déjà couvert par l’immunité météo existante.';
    } else {
      _eventLog =
          'Rencontre résolue : cargaison et vitalité ajustées sans passer sous le retour.';
    }
  }

  void _restoreBiomass() {
    _node.restoreOrganicFromBiomass();
    _eventLog = 'La Biomasse a régénéré la ressource organique.';
    setState(() {});
  }

  void _depositAtCamp() {
    final camp = _world.inventories['camp-storage-v2']!;
    for (final resource in LisiereResourceKind.values) {
      final moved = _fieldInventory.remove(resource, camp.remainingCapacity);
      camp.add(resource, moved);
    }
    _eventLog = 'Rotation terminée : stock de terrain déposé au Camp.';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp):
              _DirectionIntent(_Direction.up),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _DirectionIntent(_Direction.down),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _DirectionIntent(_Direction.left),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _DirectionIntent(_Direction.right),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DirectionIntent: CallbackAction<_DirectionIntent>(
              onInvoke: (intent) {
                _receiveDirection(intent.direction);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(title: const Text('PTIPOTE V2 · Lisière')),
              body: StreamBuilder<List<PtipoteFigurine>>(
                stream: _figurineService.watchMyFigurines(),
                builder: (context, snapshot) {
                  final figurine = snapshot.data?.isNotEmpty == true
                      ? snapshot.data!.first
                      : null;
                  if (figurine != null) _ptipoteId = figurine.id;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _PtipoteCard(
                        figurine: figurine,
                        vitality: _vitality,
                        maxVitality: _maxVitality,
                        recolteur: _recolteur,
                        patrouilleur: _patrouilleur,
                      ),
                      const SizedBox(height: 12),
                      _NodeCard(
                        node: _node,
                        holding: _harvestTimer != null,
                        onHoldStart: _startHarvest,
                        onHoldEnd: _stopHarvest,
                        onRestore: _restoreBiomass,
                      ),
                      const SizedBox(height: 12),
                      _InventoryCard(
                        field: _fieldInventory,
                        camp: _world.inventories['camp-storage-v2']!,
                        onDeposit: _depositAtCamp,
                      ),
                      const SizedBox(height: 12),
                      _PatrolCard(
                        pending: _pendingEncounter,
                        qte: _qte,
                        qteStep: _qteStep,
                        security: _security,
                        bossDroneActive: _world
                            .dangers['lisiere-simulation']!.bossDroneActive,
                        onSecurityChanged: (value) =>
                            setState(() => _security = value),
                        onToxic: () => _startPatrol(
                          defaultLisiereEncounterResolutions[
                              LisiereEncounterType.toxic]!,
                        ),
                        onDrone: () => _startPatrol(
                          defaultLisiereEncounterResolutions[
                              LisiereEncounterType.standardDrone]!,
                        ),
                        onFall: () => _startPatrol(
                          defaultLisiereEncounterResolutions[
                              LisiereEncounterType.fall]!,
                        ),
                        onBossDrone: _startBossDrone,
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(_eventLog),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class _PtipoteCard extends StatelessWidget {
  const _PtipoteCard({
    required this.figurine,
    required this.vitality,
    required this.maxVitality,
    required this.recolteur,
    required this.patrouilleur,
  });

  final PtipoteFigurine? figurine;
  final int vitality;
  final int maxVitality;
  final LisiereJobProgress recolteur;
  final LisiereJobProgress patrouilleur;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 88,
                height: 88,
                child: PtipoteImage(
                  type: figurine?.type ?? 'ptipote',
                  species: figurine?.species ?? 'simulation',
                  height: 88,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      figurine?.displayName ?? 'P’TIPOTE de simulation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Vitalité $vitality / $maxVitality'),
                    Text(
                        'Récolteur ${recolteur.level.name.toUpperCase()} · ${recolteur.currentProgress}/50 coups'),
                    Text(
                        'Patrouilleur ${patrouilleur.level.name.toUpperCase()} · ${patrouilleur.currentProgress}/50 XP'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.holding,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onRestore,
  });

  final LisiereResourceNode node;
  final bool holding;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('${node.visualVariant} Ressource ${node.kind.name}'),
              Text(
                  'Résistance ${node.resistance.toStringAsFixed(0)} / ${node.maxResistance.toStringAsFixed(0)} · ${node.state.name}'),
              const SizedBox(height: 8),
              GestureDetector(
                onTapDown: node.state == LisiereResourceNodeState.available
                    ? (_) => onHoldStart()
                    : null,
                onTapUp: (_) => onHoldEnd(),
                onTapCancel: onHoldEnd,
                child: IgnorePointer(
                  child: FilledButton.icon(
                    onPressed: node.state == LisiereResourceNodeState.available
                        ? () {}
                        : null,
                    icon: Icon(holding ? Icons.pan_tool : Icons.front_hand),
                    label: Text(holding
                        ? 'Récolte en cours… relâcher pour arrêter'
                        : 'Maintenir pour récolter'),
                  ),
                ),
              ),
              if (node.kind == LisiereResourceKind.organic &&
                  node.state != LisiereResourceNodeState.available)
                TextButton(
                  onPressed: onRestore,
                  child: const Text('Simuler le retour de Biomasse'),
                ),
            ],
          ),
        ),
      );
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.field,
    required this.camp,
    required this.onDeposit,
  });

  final LisiereFieldInventory field;
  final LisiereFieldInventory camp;
  final VoidCallback onDeposit;

  String _stock(LisiereFieldInventory inventory) => inventory.amounts.entries
      .map((entry) =>
          '${entry.key == LisiereResourceKind.organic ? '🌿' : '🪨'} ${entry.value}')
      .join(' · ');

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                  'Terrain ${field.used}/${field.capacity} : ${_stock(field).isEmpty ? 'vide' : _stock(field)}'),
              Text(
                  'Camp ${camp.used}/${camp.capacity} : ${_stock(camp).isEmpty ? 'vide' : _stock(camp)}'),
              TextButton.icon(
                onPressed: field.used == 0 ? null : onDeposit,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Simuler la rotation vers le Camp'),
              ),
            ],
          ),
        ),
      );
}

class _PatrolCard extends StatelessWidget {
  const _PatrolCard({
    required this.pending,
    required this.qte,
    required this.qteStep,
    required this.security,
    required this.bossDroneActive,
    required this.onSecurityChanged,
    required this.onToxic,
    required this.onDrone,
    required this.onFall,
    required this.onBossDrone,
  });

  final LisiereEncounterResolution? pending;
  final List<_Direction> qte;
  final int qteStep;
  final double security;
  final bool bossDroneActive;
  final ValueChanged<double> onSecurityChanged;
  final VoidCallback onToxic;
  final VoidCallback onDrone;
  final VoidCallback onFall;
  final VoidCallback onBossDrone;

  String _arrow(_Direction direction) => switch (direction) {
        _Direction.up => '↑',
        _Direction.down => '↓',
        _Direction.left => '←',
        _Direction.right => '→',
      };

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Patrouille et QTE'),
              Text('Sécurité de groupe : ${security.round()} %'),
              Slider(
                value: security,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${security.round()} %',
                onChanged: pending == null ? onSecurityChanged : null,
              ),
              if (pending == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                        onPressed: onToxic,
                        child: const Text('🤢 Nuage toxique')),
                    OutlinedButton(
                        onPressed: onDrone, child: const Text('🤖 Drone')),
                    OutlinedButton(
                        onPressed: onFall, child: const Text('🪨 Chute')),
                    OutlinedButton(
                      onPressed: onBossDrone,
                      child: Text(
                        bossDroneActive
                            ? '🤖 Drone chef actif'
                            : '🤖 Simuler Drone chef',
                      ),
                    ),
                  ],
                )
              else ...<Widget>[
                const SizedBox(height: 8),
                const Text(
                    'QTE actif — utilise les flèches ↑ → ↓ ← du clavier.'),
                Text(qte.map(_arrow).join('  '),
                    style: Theme.of(context).textTheme.headlineSmall),
                Text('Étape ${qteStep + 1} / ${qte.length}'),
              ],
              const SizedBox(height: 6),
              const Text(
                  'Chaque rencontre : +5 XP. QTE réussi : +15 XP. N1 à 50 XP.'),
            ],
          ),
        ),
      );
}
