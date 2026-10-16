import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'elevage_config.dart';
import 'elevage_controller.dart';
import 'elevage_engine.dart';
import 'elevage_presentation.dart';
import 'elevage_repository.dart';

class ElevagePage extends StatefulWidget {
  const ElevagePage({super.key});
  static const route = '/game/elevage';

  @override
  State<ElevagePage> createState() => _ElevagePageState();
}

class _ElevagePageState extends State<ElevagePage> {
  ElevageController? _controller;
  String? _individualId;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _open();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _open() async {
    final controller = ElevageController(await ElevageRepository.create());
    await controller.load();
    controller.addListener(_update);
    if (mounted) setState(() => _controller = controller);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.removeListener(_update);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!controller.config.featureEnabled) {
      return Scaffold(
          appBar: AppBar(title: const Text('P’TIPOTE Élevage')),
          body: const Center(
              child: Text('Élevage est momentanément désactivé.')));
    }
    final state = controller.state;
    if (state == null) return _StartPage(controller: controller);
    final id = _individualId;
    if (id != null &&
        (state.data['activeIndividualIds'] as List).contains(id)) {
      return _IndividualPage(
        controller: controller,
        individualId: id,
        onBack: () => setState(() => _individualId = null),
      );
    }
    return _AlcovesPage(
      controller: controller,
      onOpenIndividual: (value) => setState(() => _individualId = value),
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({required this.controller});
  final ElevageController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _appBar(context, controller),
        body: _elevageCanvas(
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const _ElevageMark(size: 76),
                  const SizedBox(height: 26),
                  const _Eyebrow('P’TIPOTE ÉLEVAGE'),
                  const SizedBox(height: 12),
                  Text('Une Alcôve vous attend',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 14),
                  const Text(
                    'Commencez une partie locale et apprenez à connaître votre P’TIPOTE.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: controller.initialize,
                    child: const Text('Commencer l’aventure'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _AlcovesPage extends StatelessWidget {
  const _AlcovesPage(
      {required this.controller, required this.onOpenIndividual});
  final ElevageController controller;
  final ValueChanged<String> onOpenIndividual;

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final alcoves = (state.data['alcoves'] as List).cast<Map>();
    return Scaffold(
      appBar: _appBar(context, controller),
      body: _elevageCanvas(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 42),
            children: <Widget>[
              const _Eyebrow('P’TIPOTE ÉLEVAGE'),
              const SizedBox(height: 16),
              Text('Les Alcôves',
                  style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 12),
              const Text('Chaque Alcôve peut accueillir un P’TIPOTE.'),
              if (controller.notifications.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${controller.notifications.first['name']} a été récupéré. Les Sourciers vous remercient pour votre contribution et le P’TIPOTE était en pleine forme.',
                        ),
                        TextButton(
                          onPressed: controller.acknowledgeNotifications,
                          child: const Text('Compris'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: alcoves.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: wide ? 2 : 1,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 292,
                ),
                itemBuilder: (context, index) {
                  final alcove = alcoves[index];
                  final occupant = alcove['occupantIndividualId'] as String?;
                  final individual = occupant == null
                      ? null
                      : (state.data['individuals'] as Map)[occupant] as Map?;
                  final occupied = individual != null &&
                      (state.data['activeIndividualIds'] as List)
                          .contains(occupant);
                  return _AlcoveOverviewCard(
                    index: index + 1,
                    now: controller.now,
                    occupied: occupied,
                    individual: individual,
                    onOpen: occupied
                        ? () => onOpenIndividual(occupant!)
                        : () => _welcome(
                            context, controller, alcove['id'] as String),
                    onMoveOut: !occupied &&
                            (alcove['slots'] as List)
                                .any((slot) => slot != null)
                        ? () => _moveOut(
                            context, controller, alcove['id'] as String)
                        : null,
                  );
                },
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _AlcoveOverviewCard extends StatelessWidget {
  const _AlcoveOverviewCard({
    required this.index,
    required this.now,
    required this.occupied,
    required this.individual,
    required this.onOpen,
    this.onMoveOut,
  });

  final int index;
  final int now;
  final bool occupied;
  final Map? individual;
  final VoidCallback onOpen;
  final VoidCallback? onMoveOut;

  @override
  Widget build(BuildContext context) {
    final name = occupied ? individual!['name'] as String : 'Libre';
    final stage = occupied
        ? _stageLabel(individual!['lifecycle']['stage'] as String)
        : null;
    return Card(
      color: occupied
          ? Theme.of(context).cardTheme.color
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Eyebrow('ALCÔVE $index'),
              const SizedBox(height: 16),
              const _ElevageMark(size: 54),
              const Spacer(),
              Text(name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 7),
              Text(
                occupied
                    ? '${_individualNatureLabel(individual!)} · $stage'
                    : 'Un espace calme attend un P’TIPOTE.',
              ),
              if (occupied) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  individual!['ownership']['mode'] == 'PHYSICAL'
                      ? 'Figurine'
                      : _coRemaining(individual!['ownership'] as Map, now),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpen,
                child: Text(
                    occupied ? 'Ouvrir l’Alcôve' : 'Accueillir un P’TIPOTE'),
              ),
              if (onMoveOut != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onMoveOut,
                    child: const Text('Déménager cette Alcôve'),
                  ),
                ),
            ]),
      ),
    );
  }
}

class _IndividualPage extends StatefulWidget {
  const _IndividualPage(
      {required this.controller,
      required this.individualId,
      required this.onBack});
  final ElevageController controller;
  final String individualId;
  final VoidCallback onBack;

  @override
  State<_IndividualPage> createState() => _IndividualPageState();
}

enum _SceneEventType { autonomous, follow, cuddle, wake }

class _SceneEvent {
  const _SceneEvent.autonomous({this.direct = false, this.targetInstanceId})
      : type = _SceneEventType.autonomous,
        zoneId = null;
  const _SceneEvent.follow(this.zoneId)
      : type = _SceneEventType.follow,
        targetInstanceId = null,
        direct = true;
  const _SceneEvent.cuddle()
      : type = _SceneEventType.cuddle,
        zoneId = null,
        targetInstanceId = null,
        direct = true;
  const _SceneEvent.wake()
      : type = _SceneEventType.wake,
        zoneId = null,
        targetInstanceId = null,
        direct = true;

  final _SceneEventType type;
  final String? zoneId;
  final String? targetInstanceId;
  final bool direct;
}

class _IndividualPageState extends State<_IndividualPage> {
  String? _reaction;
  String? _feedback;
  String? _pendingPlacementItem;
  Timer? _feedbackTimer;
  Timer? _autonomousTimer;
  Timer? _idleTimer;
  bool _autonomousInFlight = false;
  int _lastAutonomousAt = 0;
  String? _lastAutonomousBehavior;
  String _sceneAction = 'IDLE';
  String _ptipoteZoneId = 'ZONE_2';
  int _lastIdleMoveAt = 0;
  final List<_SceneEvent> _actionQueue = <_SceneEvent>[];
  Timer? _followHoldTimer;
  Timer? _ptipoteHoldTimer;
  Timer? _bubbleTimer;
  String? _followHoldZoneId;
  bool _followFingerHeld = false;
  int? _followHoldStartedAt;
  bool _ptipoteHoldActive = false;
  String? _sceneVoice;
  String? _bubbleItemId;
  int _actionRemainingMs = 0;

  @override
  void initState() {
    super.initState();
    _autonomousTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      widget.controller.refreshRequest(widget.individualId);
      _enqueueSceneEvent(const _SceneEvent.autonomous());
    });
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _autonomousInFlight) return;
      final state = widget.controller.state;
      if (state == null) return;
      final individual =
          (state.data['individuals'] as Map)[widget.individualId] as Map?;
      if (individual == null ||
          ElevageDomain.metamorphosisAvailable(state, widget.individualId,
              widget.controller.now, widget.controller.config) ||
          ElevageDomain.isSleeping(
              individual, widget.controller.now, widget.controller.config)) {
        return;
      }
      final now = widget.controller.now;
      if (now - _lastIdleMoveAt <
          ElevageDomain.idlePauseFor(individual, widget.controller.config) *
              1000) {
        return;
      }
      final zones = widget.controller.config.sceneZones;
      final index = zones.indexWhere((zone) => zone.id == _ptipoteZoneId);
      setState(() {
        _ptipoteZoneId = zones[(index + 1) % zones.length].id;
        _sceneAction = 'IDLE';
        _lastIdleMoveAt = now;
      });
    });
    Future<void>.delayed(
        Duration(milliseconds: widget.controller.config.objectReactionDelayMs),
        () => _enqueueSceneEvent(const _SceneEvent.autonomous(direct: true)));
  }

  void _showSceneFeedback(String feedback, {String? reaction}) {
    _feedbackTimer?.cancel();
    setState(() {
      _reaction = reaction;
      _feedback = feedback;
    });
    _feedbackTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _autonomousTimer?.cancel();
    _idleTimer?.cancel();
    _followHoldTimer?.cancel();
    _ptipoteHoldTimer?.cancel();
    _bubbleTimer?.cancel();
    super.dispose();
  }

  void _startFollowHold(String zoneId) {
    if (_pendingPlacementItem != null) return;
    _followHoldTimer?.cancel();
    setState(() {
      _followFingerHeld = true;
      _followHoldZoneId = zoneId;
      _followHoldStartedAt = widget.controller.now;
    });
    _followHoldTimer = Timer(
        Duration(seconds: widget.controller.config.longPressHoldSeconds), () {
      if (_followFingerHeld && _followHoldZoneId == zoneId) {
        _followZone(zoneId);
      }
    });
  }

  void _endFollowHold() {
    _followHoldTimer?.cancel();
    if (mounted) {
      setState(() {
        _followFingerHeld = false;
        _followHoldZoneId = null;
        _followHoldStartedAt = null;
      });
    }
  }

  void _setSceneAction(String action, {String? zoneId}) {
    if (!mounted) return;
    setState(() {
      _sceneAction = action;
      if (zoneId != null) _ptipoteZoneId = zoneId;
    });
  }

  Future<void> _waitSceneAction(int milliseconds,
      {bool interruptible = true}) async {
    _actionRemainingMs = milliseconds;
    while (mounted && _actionRemainingMs > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (interruptible) {
        _actionRemainingMs = max(0, _actionRemainingMs - 100);
      }
    }
    _actionRemainingMs = 0;
  }

  void _showSceneExpression(String action, Map individual, {String? itemId}) {
    final category = ElevageDomain.vocalCategoryForAction(action);
    final expression = ElevageDomain.communicationExpression(
        individual, category, widget.controller.config,
        precise: itemId == null ? null : ElevagePresentation.itemLabel(itemId));
    _bubbleTimer?.cancel();
    setState(() {
      _sceneVoice = expression['word'] ?? expression['vocal'];
      _bubbleItemId = action == 'STRUCTURAL_ABSORB' ||
              action == 'EAT' ||
              action == 'FLEE_WITH_ITEM'
          ? itemId
          : null;
    });
    widget.controller.recordCommunication(widget.individualId, category);
    _bubbleTimer = Timer(
        Duration(
            seconds: ElevageDomain.bubbleDurationSeconds(
                action, widget.controller.config)), () {
      if (mounted) {
        setState(() {
          _sceneVoice = null;
          _bubbleItemId = null;
        });
      }
    });
  }

  void _startPtipoteHold() {
    final state = widget.controller.state;
    if (state == null) return;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map?;
    if (individual == null ||
        !ElevageDomain.isSleeping(
            individual, widget.controller.now, widget.controller.config)) {
      return;
    }
    _ptipoteHoldTimer?.cancel();
    setState(() => _ptipoteHoldActive = true);
    _ptipoteHoldTimer = Timer(
        Duration(seconds: widget.controller.config.longPressHoldSeconds), () {
      if (_ptipoteHoldActive) _enqueueSceneEvent(const _SceneEvent.wake());
    });
  }

  void _endPtipoteHold() {
    _ptipoteHoldTimer?.cancel();
    if (mounted) setState(() => _ptipoteHoldActive = false);
  }

  void _onPtipoteTap() {
    final state = widget.controller.state;
    if (state == null) return;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map?;
    if (individual == null) return;
    if (ElevageDomain.metamorphosisAvailable(state, widget.individualId,
        widget.controller.now, widget.controller.config)) {
      _metamorphosis(context, widget.controller, widget.individualId);
      return;
    }
    if (ElevageDomain.isSleeping(
        individual, widget.controller.now, widget.controller.config)) {
      _setSceneAction('SLEEP');
      return;
    }
    _cuddle();
  }

  /// Les gestes joueur et les nouveaux objets attendent la fin de l’action
  /// atomique courante. Ainsi, aucune inspection ne peut survenir à distance.
  void _enqueueSceneEvent(_SceneEvent event) {
    if (!mounted) return;
    if (_autonomousInFlight &&
        _sceneAction != 'PICKUP' &&
        _sceneAction != 'FLEE_FAST' &&
        (event.type == _SceneEventType.autonomous ||
            event.type == _SceneEventType.cuddle)) {
      final state = widget.controller.state;
      final individual = state == null
          ? null
          : (state.data['individuals'] as Map)[widget.individualId] as Map?;
      if (individual != null) {
        _actionRemainingMs = ElevageDomain.interruptedRemainingMs(
          individual,
          _actionRemainingMs,
          eventType:
              event.type == _SceneEventType.cuddle ? 'CUDDLE' : 'NEW_ITEM',
        );
      }
    }
    _actionQueue.add(event);
    _drainActionQueue();
  }

  Future<void> _drainActionQueue() async {
    if (!mounted || _autonomousInFlight || _actionQueue.isEmpty) return;
    final event = _actionQueue.removeAt(0);
    if (event.type == _SceneEventType.autonomous) {
      await _executeAutonomousCycle(
          playerTriggered: event.direct,
          targetInstanceId: event.targetInstanceId);
    } else if (event.type == _SceneEventType.follow) {
      await _executeFollow(event.zoneId!);
    } else if (event.type == _SceneEventType.cuddle) {
      await _executeCuddle();
    } else {
      await _executeWake();
    }
    if (mounted) _drainActionQueue();
  }

  Future<void> _executeAutonomousCycle(
      {bool playerTriggered = false, String? targetInstanceId}) async {
    if (!mounted || _autonomousInFlight) return;
    final now = widget.controller.now;
    final config = widget.controller.config;
    if (!playerTriggered &&
        now - _lastAutonomousAt <
            config.autonomousReactionIntervalSeconds * 1000) {
      return;
    }
    final state = widget.controller.state;
    if (state == null) return;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map?;
    if (individual == null) return;
    if (ElevageDomain.metamorphosisAvailable(
        state, widget.individualId, now, config)) {
      _setSceneAction('METAMORPHOSIS');
      return;
    }
    final alcoveId = individual['alcoveId'] as String;
    if (ElevageDomain.isSleeping(individual, now, config)) {
      _setSceneAction('SLEEP',
          zoneId: ElevageDomain.sleepZone(
              state, widget.individualId, now, config,
              phaseOverride: widget.controller.forcedDayNightPhase));
      return;
    }
    if (_sceneAction == 'SLEEP') _setSceneAction('IDLE');
    final decision = targetInstanceId == null
        ? ElevageDomain.nextAutonomousSceneDecision(
            state, widget.individualId, alcoveId, now, config,
            lastBehavior: playerTriggered ? null : _lastAutonomousBehavior,
            phaseOverride: widget.controller.forcedDayNightPhase)
        : _decisionForInstance(state, alcoveId, targetInstanceId, now, config);
    if (decision == null) {
      final reorganization = ElevageDomain.nextHabitatReorganization(
          state, widget.individualId, alcoveId, now, config,
          phaseOverride: widget.controller.forcedDayNightPhase);
      if (reorganization != null) {
        await _executeHabitatReorganization(reorganization, individual);
      } else {
        final furniture = ElevageDomain.nextFurnitureActivity(
            state, widget.individualId, alcoveId, now, config);
        if (furniture != null) {
          await _executeFurnitureActivity(furniture, individual);
        }
      }
      return;
    }
    _autonomousInFlight = true;
    final targetZone = decision.zoneId;
    final carriesToSafety = decision.outcome.behavior == 'FLEE_WITH_ITEM';
    try {
      _setSceneAction('NOTICE_ITEM');
      await _waitSceneAction(config.objectReactionDelayMs);
      _setSceneAction('APPROACH_ITEM', zoneId: targetZone);
      await _waitSceneAction(
          ElevageDomain.normalMoveDurationFor(individual, config));
      // Une ressource intéressante dans une mauvaise zone doit être saisie
      // avant la fuite. Les autres arrivées gardent la réaction instinctive.
      if (!carriesToSafety &&
          await _respondToArrivalComfort(alcoveId, config)) {
        return;
      }
      _setSceneAction('INSPECT_ITEM');
      await _waitSceneAction(carriesToSafety
          ? (config.objectReactionDelayMs / 2).round()
          : config.objectReactionDelayMs);
      if (carriesToSafety) {
        _setSceneAction('PICKUP');
        await _waitSceneAction((config.objectReactionDelayMs / 2).round(),
            interruptible: false);
        final safeZone = decision.outcome.targetZoneId;
        if (safeZone == null) return;
        await widget.controller
            .relocateSceneItem(alcoveId, decision.instanceId, safeZone);
        if (widget.controller.error != null) return;
        _setSceneAction('FLEE_WITH_ITEM', zoneId: safeZone);
        await _waitSceneAction(config.runMoveDurationMs, interruptible: false);
      }
      _setSceneAction('THINK');
      await _waitSceneAction(config.objectReactionDelayMs);
      if (decision.outcome.behavior == 'MOVE_ITEM') {
        // L'objet est désiré, mais la zone elle-même gêne le Résonance : le
        // signal d'inconfort précède une course visible vers un meilleur coin.
        _setSceneAction('DISCOMFORT');
        await _waitSceneAction(config.objectReactionDelayMs);
        _setSceneAction('MOVE_ITEM', zoneId: decision.outcome.targetZoneId);
        await _waitSceneAction(config.runMoveDurationMs);
      }
      // L’objet peut avoir été récupéré uniquement par une action déjà en
      // file ; dans ce cas l’événement devient inoffensif.
      final latest = widget.controller.state;
      final target = latest == null
          ? null
          : ElevageDomain.sceneItems(latest, alcoveId)
              .where((item) => item['instanceId'] == decision.instanceId)
              .firstOrNull;
      if (target != null) await _interactSceneItem(target, automatic: true);
      _lastAutonomousAt = widget.controller.now;
      _lastAutonomousBehavior = decision.outcome.behavior;
      await _waitSceneAction(900);
      _setSceneAction('IDLE');
    } finally {
      _autonomousInFlight = false;
    }
  }

  Future<bool> _respondToArrivalComfort(
      String alcoveId, ElevageConfig config) async {
    final current = widget.controller.state;
    if (current == null) return true;
    final individual =
        (current.data['individuals'] as Map)[widget.individualId] as Map?;
    if (individual == null) return true;
    final now = widget.controller.now;
    final environment = ElevageDomain.zoneEnvironment(
        current, alcoveId, _ptipoteZoneId, config,
        now: now, phaseOverride: widget.controller.forcedDayNightPhase);
    final comfort =
        ElevageDomain.localComfort(environment, config, individual: individual);
    if (comfort != 'BAD' && comfort != 'EXTREME') return false;
    _setSceneAction(comfort == 'EXTREME' ? 'EXTREME' : 'DISCOMFORT');
    await _waitSceneAction(config.objectReactionDelayMs);
    final target = ElevageDomain.findBestSafeZone(
        current, alcoveId, config, now,
        phaseOverride: widget.controller.forcedDayNightPhase,
        excludingZoneId: _ptipoteZoneId,
        individual: individual);
    _setSceneAction(comfort == 'EXTREME' ? 'FLEE_FAST' : 'FLEE_NORMAL',
        zoneId: target);
    await _waitSceneAction(
        (config.normalMoveDurationMs / (comfort == 'EXTREME' ? 3 : 2)).round(),
        interruptible: false);
    _setSceneAction('IDLE');
    return true;
  }

  ElevageAutonomousSceneDecision? _decisionForInstance(ElevageSave state,
      String alcoveId, String instanceId, int now, ElevageConfig config) {
    final item = ElevageDomain.sceneItems(state, alcoveId)
        .where((entry) => entry['instanceId'] == instanceId)
        .firstOrNull;
    // L’objet récupéré avant son tour annule seulement cet événement : il ne
    // peut jamais être remplacé par le premier objet de la scène.
    if (item == null) return null;
    return ElevageAutonomousSceneDecision(
      instanceId: instanceId,
      zoneId: item['zoneId'] as String,
      outcome: ElevageDomain.sceneItemOutcome(
          state, widget.individualId, alcoveId, instanceId, now, config,
          phaseOverride: widget.controller.forcedDayNightPhase),
    );
  }

  Future<void> _executeHabitatReorganization(
      Map<String, String> reorganization, Map individual) async {
    _autonomousInFlight = true;
    try {
      _setSceneAction('PICKUP', zoneId: reorganization['fromZoneId']);
      await _waitSceneAction(
          (widget.controller.config.objectReactionDelayMs / 2).round(),
          interruptible: false);
      await widget.controller.moveHabitatItem(
          widget.individualId,
          individual['alcoveId'] as String,
          reorganization['instanceId']!,
          reorganization['targetZoneId']!);
      if (!mounted || widget.controller.error != null) return;
      _setSceneAction('MOVE_ITEM', zoneId: reorganization['targetZoneId']);
      await _waitSceneAction(ElevageDomain.normalMoveDurationFor(
          individual, widget.controller.config));
      _setSceneAction('IDLE');
    } finally {
      _autonomousInFlight = false;
    }
  }

  Future<void> _executeFurnitureActivity(Map furniture, Map individual) async {
    _autonomousInFlight = true;
    try {
      final zoneId = furniture['zoneId'] as String;
      _setSceneAction('APPROACH_ITEM', zoneId: zoneId);
      await _waitSceneAction(ElevageDomain.normalMoveDurationFor(
          individual, widget.controller.config));
      _setSceneAction('THINK');
      await _waitSceneAction(widget.controller.config.objectReactionDelayMs);
      await widget.controller.useFurniture(widget.individualId,
          individual['alcoveId'] as String, furniture['instanceId'] as String);
      if (!mounted || widget.controller.error != null) return;
      final activity = furniture['definitionId'] == 'HAMAC' ||
              furniture['definitionId'] == 'NID_COUCHETTE'
          ? 'REST'
          : furniture['definitionId'] == 'PARCOURS_OBSTACLES'
              ? 'PLAY'
              : 'USE_FURNITURE';
      _setSceneAction(activity);
      final updated = (widget.controller.state!.data['individuals']
          as Map)[widget.individualId] as Map;
      _showSceneExpression('CONTENT', updated);
      await _waitSceneAction(widget.controller.config.objectReactionDelayMs);
      _setSceneAction('IDLE');
    } finally {
      _autonomousInFlight = false;
    }
  }

  void _placeFromInventory(String item) {
    setState(() => _pendingPlacementItem = item);
    _showSceneFeedback(
        'Placez ${ElevagePresentation.itemLabel(item).toLowerCase()} dans une zone libre.');
  }

  Future<void> _placeInZone(String zoneId) async {
    final item = _pendingPlacementItem;
    if (item == null) return;
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final alcoveId = individual['alcoveId'] as String;
    final instanceId =
        await widget.controller.placeSceneItem(alcoveId, item, zoneId);
    if (!mounted) return;
    if (widget.controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ElevagePresentation.friendlyError(widget.controller.error))));
      return;
    }
    final zone = widget.controller.config.sceneZone(zoneId)!;
    setState(() => _pendingPlacementItem = null);
    _showSceneFeedback(
        'Vous posez ${ElevagePresentation.itemLabel(item).toLowerCase()} dans ${zone.label}.');
    if (instanceId != null) {
      _enqueueSceneEvent(
          _SceneEvent.autonomous(direct: true, targetInstanceId: instanceId));
    }
  }

  Future<void> _interactSceneItem(Map item, {bool automatic = false}) async {
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final outcome = await widget.controller.interactSceneItem(
        widget.individualId,
        individual['alcoveId'] as String,
        item['instanceId'] as String);
    if (!mounted) return;
    if (widget.controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ElevagePresentation.friendlyError(widget.controller.error))));
      return;
    }
    if (outcome == null) return;
    final feedback = !_sceneObservationConfirmed(item, outcome) &&
            outcome.observationCount >=
                widget.controller.config.observationTextThreshold
        ? ElevagePresentation.sceneObservationFeedback(
            outcome, item['itemId'] as String, individual['name'] as String)
        : null;
    final action =
        _sceneActionForOutcome(outcome.behavior, item['itemId'] as String);
    _setSceneAction(action);
    _showSceneExpression(action, individual, itemId: item['itemId'] as String);
    _showSceneFeedback(automatic ? (feedback ?? '') : (feedback ?? ''),
        reaction: outcome.behavior);
    if (feedback != null && !automatic) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(feedback)));
    }
  }

  bool _sceneObservationConfirmed(Map item, ElevageSceneItemOutcome outcome) {
    final individual = (widget.controller.state!.data['individuals']
        as Map)[widget.individualId] as Map;
    final itemId = item['itemId'] as String;
    final type = switch (outcome.behavior) {
      'MOVE_ITEM' => 'HUMIDITY_AVOIDANCE:HUMIDITY',
      'STEP_BACK' => 'STRUCTURAL_AVOIDED:$itemId',
      'VIBRATE' => 'STRUCTURAL_REACTION:$itemId',
      'APPROACH' when ElevageDomain.structuralItems.contains(itemId) =>
        'STRUCTURAL_REACTION:$itemId',
      'RUSH_SHAKE' => 'FOOD_FAVORITE:$itemId',
      _ => 'FOOD_ACCEPTED:$itemId',
    };
    final entry =
        (individual['observationJournal']['observations'] as Map)[type] as Map?;
    return entry?['status'] == 'CONFIRMED';
  }

  Future<void> _recoverSceneItem(Map item) async {
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    await widget.controller.recoverSceneItem(
        individual['alcoveId'] as String, item['instanceId'] as String);
    if (!mounted || widget.controller.error != null) return;
    _showSceneFeedback(
        'Vous récupérez ${ElevagePresentation.itemLabel(item['itemId'] as String).toLowerCase()}.');
  }

  Future<void> _followZone(String zoneId) async =>
      _enqueueSceneEvent(_SceneEvent.follow(zoneId));

  Future<void> _executeFollow(String zoneId) async {
    _autonomousInFlight = true;
    _setSceneAction('FOLLOW', zoneId: zoneId);
    await widget.controller.follow(widget.individualId, zoneId);
    if (!mounted || widget.controller.error != null) {
      _autonomousInFlight = false;
      return;
    }
    _showSceneFeedback('', reaction: 'FOLLOW');
    await _waitSceneAction(ElevageDomain.normalMoveDurationFor(
        (widget.controller.state!.data['individuals']
            as Map)[widget.individualId] as Map,
        widget.controller.config));
    final state = widget.controller.state;
    if (state != null) {
      final individual =
          (state.data['individuals'] as Map)[widget.individualId] as Map;
      if (await _respondToArrivalComfort(
          individual['alcoveId'] as String, widget.controller.config)) {
        _autonomousInFlight = false;
        return;
      }
    }
    if (_followFingerHeld) await _executeCuddle();
    _setSceneAction('IDLE');
    _autonomousInFlight = false;
  }

  Future<void> _cuddle() async =>
      _enqueueSceneEvent(const _SceneEvent.cuddle());

  Future<void> _executeCuddle() async {
    _autonomousInFlight = true;
    _setSceneAction('CUDDLE');
    final elapsed = _followHoldStartedAt == null
        ? 1000
        : (widget.controller.now - _followHoldStartedAt!).clamp(1000, 5000);
    await widget.controller.cuddle(widget.individualId, durationMs: elapsed);
    if (!mounted || widget.controller.error != null) {
      _autonomousInFlight = false;
      return;
    }
    final updated = (widget.controller.state!.data['individuals']
        as Map)[widget.individualId] as Map;
    final social = updated['social'] as Map;
    final socialReaction = social['lastReaction'] as String? ?? 'CONTENT';
    _setSceneAction(socialReaction == 'IRRITATED'
        ? 'IRRITATED'
        : socialReaction == 'RESERVED'
            ? 'NEUTRAL'
            : 'CUDDLE');
    _showSceneExpression(_sceneAction, updated);
    _showSceneFeedback('', reaction: socialReaction);
    await _waitSceneAction(elapsed);
    _setSceneAction('IDLE');
    _autonomousInFlight = false;
  }

  Future<void> _executeWake() async {
    final state = widget.controller.state;
    if (state == null) return;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map?;
    if (individual == null) return;
    _autonomousInFlight = true;
    await widget.controller.wake(widget.individualId);
    if (!mounted || widget.controller.error != null) {
      _autonomousInFlight = false;
      return;
    }
    final updated = (widget.controller.state!.data['individuals']
        as Map)[widget.individualId] as Map;
    _setSceneAction('WAKE');
    _showSceneExpression('WAKE', updated);
    final posed = ElevageDomain.personalityValue(updated, 'tempo') >= .5;
    await _waitSceneAction(posed ? 1400 : 700, interruptible: false);
    _setSceneAction('IDLE');
    _autonomousInFlight = false;
  }

  Future<void> _openSceneItemActions(Map item) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: <Widget>[
          ListTile(
            leading:
                Icon(ElevagePresentation.itemIcon(item['itemId'] as String)),
            title:
                Text(ElevagePresentation.itemLabel(item['itemId'] as String)),
            subtitle: const Text('Objet posé dans l’Alcôve'),
          ),
          if (widget.controller.config.devMode)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Forcer la réaction · QA'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _interactSceneItem(item);
              },
            ),
          ListTile(
            leading: const Icon(Icons.undo_outlined),
            title: const Text('Récupérer'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _recoverSceneItem(item);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _openHabitatItemActions(Map item) async {
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final alcoveId = individual['alcoveId'] as String;
    final definition =
        widget.controller.config.installation(item['definitionId'] as String);
    if (definition == null) return;
    final affinity = definition.category == 'DECORATION'
        ? ((individual['decorPreferences'] as Map?)?[definition.id] as Map?)
        : null;
    final affinityLabel = affinity == null
        ? 'Affinité à observer.'
        : affinity['liked'] == true
            ? 'Cette décoration semble lui plaire.'
            : 'Cette décoration lui paraît plutôt neutre.';
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
                child: Wrap(children: <Widget>[
              ListTile(
                  leading:
                      Icon(ElevagePresentation.installationIcon(definition.id)),
                  title: Text(definition.label),
                  subtitle: Text(
                      '${definition.category.toLowerCase()} · Z${(item['zoneId'] as String).split('_').last}\n${definition.description}${definition.category == 'DECORATION' ? '\n$affinityLabel' : ''}')),
              if (definition.category == 'MEUBLE')
                ListTile(
                    leading: const Icon(Icons.chair_outlined),
                    title: const Text('Encourager cette activité'),
                    subtitle: Text(definition.activity == 'REST'
                        ? 'Une pause calme peut légèrement améliorer son bien-être.'
                        : 'Cette station propose une activité sans produire de ressource.'),
                    onTap: () async {
                      await widget.controller.useFurniture(widget.individualId,
                          alcoveId, item['instanceId'] as String);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    }),
              if (definition.category == 'DECORATION')
                ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Observer la réaction'),
                    subtitle: const Text(
                        'Les goûts se révèlent par les comportements répétés.'),
                    onTap: () async {
                      await widget.controller.interactDecoration(
                          widget.individualId,
                          alcoveId,
                          item['instanceId'] as String);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    }),
              ListTile(
                  leading: const Icon(Icons.undo_outlined),
                  title: const Text('Récupérer'),
                  onTap: () async {
                    await widget.controller.recoverHabitatItem(
                        alcoveId, item['instanceId'] as String);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  }),
            ])));
  }

  Future<void> _openInstallationSlot(
      String alcoveId, int slot, Map<String, int> localEnvironment) async {
    final alcove = (widget.controller.state!.data['alcoves'] as List)
        .cast<Map>()
        .firstWhere((entry) => entry['id'] == alcoveId);
    final raw = (alcove['slots'] as List)[slot];
    if (raw is! Map) {
      await _placeInstallation(context, widget.controller, alcoveId, slot);
      return;
    }
    final definition =
        widget.controller.config.installation(raw['definitionId'] as String);
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
              child: Wrap(children: <Widget>[
                ListTile(
                    leading: Icon(ElevagePresentation.installationIcon(
                        raw['definitionId'] as String)),
                    title: Text(ElevagePresentation.installationLabel(
                        raw['definitionId'] as String)),
                    subtitle: Text('Installée en Z${slot + 1}')),
                if (definition != null)
                  ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Voir la fiche'),
                      onTap: () => _showInstallationDetails(
                          context,
                          widget.controller.config,
                          definition,
                          localEnvironment)),
                if (definition?.resonanceMaterial != null)
                  ListTile(
                      leading: const Icon(Icons.diamond_outlined),
                      title: const Text('Entrer en résonance'),
                      subtitle: Text(
                          'Renforce lentement la structure via ${ElevagePresentation.itemLabel(definition!.resonanceMaterial!)} sans consommer la Formation.'),
                      onTap: () async {
                        await widget.controller.resonateFormation(
                            widget.individualId,
                            alcoveId,
                            raw['instanceId'] as String);
                        if (sheetContext.mounted &&
                            widget.controller.error == null) {
                          final updated =
                              (widget.controller.state!.data['individuals']
                                  as Map)[widget.individualId] as Map;
                          _setSceneAction('RESONATE');
                          _showSceneExpression('STRUCTURAL_ABSORB', updated,
                              itemId: definition.resonanceMaterial);
                          Navigator.pop(sheetContext);
                        }
                      }),
                if (definition?.productive == true)
                  ...(((raw['productionState'] as Map?)?['availableByItemId']
                              as Map?)
                          ?.entries
                          .where((entry) => (entry.value as num).toInt() > 0)
                          .map<Widget>((entry) => ListTile(
                                leading: Icon(ElevagePresentation.itemIcon(
                                    entry.key as String)),
                                title: Text(
                                    '${ElevagePresentation.itemLabel(entry.key as String)} : ${entry.value}/${widget.controller.config.productionMaxStock}'),
                                trailing: OutlinedButton(
                                  onPressed: () async {
                                    await widget.controller.harvestLocal(
                                        alcoveId, slot, entry.key as String);
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                  },
                                  child: const Text('Récolter'),
                                ),
                              ))
                          .toList() ??
                      const <Widget>[]),
                ListTile(
                    leading: const Icon(Icons.swap_horiz_outlined),
                    title: const Text('Remplacer'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _placeInstallation(
                          context, widget.controller, alcoveId, slot);
                    }),
                ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Retirer'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.controller.remove(alcoveId, slot);
                    }),
              ]),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final profile = controller.config.profileForIndividual(individual);
    final alcove = (state.data['alcoves'] as List)
        .cast<Map>()
        .firstWhere((item) => item['id'] == individual['alcoveId']);
    final now = controller.now;
    final alcoveId = alcove['id'] as String;
    final zoneEnvironments = <String, Map<String, int>>{
      for (final zone in controller.config.sceneZones)
        zone.id: ElevageDomain.zoneEnvironment(
            state, alcoveId, zone.id, controller.config,
            now: now, phaseOverride: controller.forcedDayNightPhase),
    };
    final environment = ElevageDomain.averageZoneEnvironment(
        state, alcoveId, controller.config,
        now: now, phaseOverride: controller.forcedDayNightPhase);
    final localEnvironment =
        zoneEnvironments[_ptipoteZoneId] ?? const <String, int>{};
    final alcoveComfort =
        _alcoveComfort(zoneEnvironments, controller.config, individual);
    final hunger = ElevageDomain.hunger(
        state, widget.individualId, now, controller.config);
    final satiety = ElevageDomain.satietyPercent(
        state, widget.individualId, now, controller.config);
    final communication = ElevageDomain.communication(
        state, widget.individualId, now, controller.config);
    final available = ElevageDomain.metamorphosisAvailable(
        state, widget.individualId, now, controller.config);
    final stage = individual['lifecycle']['stage'] as String;
    final request =
        ElevageDomain.activeRequest(state, widget.individualId, now);
    final sleeping =
        ElevageDomain.isSleeping(individual, now, controller.config);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('Alcôve'),
        actions: <Widget>[
          IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Carnet d’observation',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => ElevageNotebookPage(
                          controller: controller,
                          individualId: widget.individualId)))),
          IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Inventaire',
              onPressed: () => _openInventory(
                  context, controller, individual, _placeFromInventory)),
          IconButton(
              icon: const Icon(Icons.chair_outlined),
              tooltip: 'Meubles et décorations',
              onPressed: () =>
                  _openHabitatInventory(context, controller, alcoveId)),
          if (controller.config.devMode)
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Dashboard',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            ElevageDashboardPage(controller: controller))))
        ],
      ),
      body: _elevageCanvas(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 42),
          children: <Widget>[
            const _Eyebrow('P’TIPOTE ÉLEVAGE'),
            const SizedBox(height: 12),
            _AlcoveScene(
                stage: stage,
                family: individual['family'] as String,
                reaction: _reaction,
                feedback: _feedback,
                slots: (alcove['slots'] as List).cast<dynamic>(),
                environment: environment,
                sceneItems:
                    ElevageDomain.sceneItems(state, alcove['id'] as String),
                habitatItems:
                    ElevageDomain.habitatItems(state, alcove['id'] as String),
                zones: controller.config.sceneZones,
                onSceneItemTap: (item) => _openSceneItemActions(item),
                onHabitatItemTap: (item) => _openHabitatItemActions(item),
                onZoneTap: (zoneId) =>
                    _pendingPlacementItem == null ? null : _placeInZone(zoneId),
                onZoneHoldStart: _startFollowHold,
                onZoneHoldEnd: _endFollowHold,
                onPtipoteTap: _onPtipoteTap,
                onPtipoteHoldStart: _startPtipoteHold,
                onPtipoteHoldEnd: _endPtipoteHold,
                onInstallationSlotTap: (slot) => _openInstallationSlot(
                    alcoveId, slot, zoneEnvironments['ZONE_${slot + 1}']!),
                onEnvironmentTap: () => _showEnvironmentPanel(
                    context, environment, zoneEnvironments),
                pendingItem: _pendingPlacementItem,
                followHoldZoneId: _followHoldZoneId,
                action: _sceneAction,
                voice: _sceneVoice,
                bubbleItemId: _bubbleItemId,
                ptipoteHoldActive: _ptipoteHoldActive,
                requestSignal: request?['signal'] as String?,
                sleeping: sleeping,
                crystallizing: available,
                ptipoteZoneId: _ptipoteZoneId,
                phase: controller.dayNightPhase(now),
                phaseRemainingMs: ElevageDomain.dayNightRemainingMs(
                    now, controller.config,
                    phaseOverride: controller.forcedDayNightPhase),
                now: now,
                config: controller.config,
                zoneEnvironments: zoneEnvironments),
            const SizedBox(height: 12),
            Center(
                child: Text('${individual['name']}',
                    style: Theme.of(context).textTheme.headlineMedium)),
            Center(child: Text('${profile.label} · ${_stageLabel(stage)}')),
            const SizedBox(height: 12),
            if (communication != null)
              Center(
                  child: Chip(
                      avatar: const Icon(Icons.chat_bubble_outline),
                      label: Text(_communicationLabel(communication)))),
            _section(context, 'État', <Widget>[
              ListTile(
                  leading: const Icon(Icons.restaurant_outlined),
                  title: Text(_hungerLabel(hunger)),
                  subtitle: const Text(
                      'La faim est lente et ne comporte aucune punition irréversible.')),
              ListTile(
                  leading: const Text('🍴', style: TextStyle(fontSize: 22)),
                  title: const Text('Satiété'),
                  subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(value: satiety / 100)),
                  trailing: Text('$satiety %')),
              if (controller.config.devMode && available)
                FilledButton.tonalIcon(
                    onPressed: () => _metamorphosis(
                        context, controller, widget.individualId),
                    icon: const Icon(Icons.diamond_outlined),
                    label: const Text('Debug · lancer l’évolution')),
              if (stage != 'BABY') ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Tempérament'),
                  subtitle: Text(_personalityLabel(individual)),
                ),
                ListTile(
                  leading: const Text('💎', style: TextStyle(fontSize: 22)),
                  title: const Text('Structure ferrique'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                        value: min(
                            1,
                            ((individual['care']['structuralIntake']
                                    as Map)['total'] as int) /
                                12)),
                  ),
                ),
              ],
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Confort de l’Alcôve : ${alcoveComfort['label']}',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: alcoveComfort['value'] as double),
                      const SizedBox(height: 12),
                      Text(
                          'Zone actuelle (${_ptipoteZoneId.replaceFirst('ZONE_', 'Z')})',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(_localComfortLabel(
                          ElevageDomain.localComfort(
                              localEnvironment, controller.config,
                              individual: individual),
                          individual['name'] as String)),
                      const SizedBox(height: 6),
                      Text(
                          '☀️ ${ElevagePresentation.environmentScale(localEnvironment['light'] ?? 0)}/5 · '
                          '🌡️ ${ElevagePresentation.environmentScale(localEnvironment['temperature'] ?? 0)}/5 · '
                          '💧 ${ElevagePresentation.environmentScale(localEnvironment['humidity'] ?? 0)}/5'),
                    ],
                  ),
                ),
              ),
              FilledButton.tonal(
                  onPressed: () =>
                      controller.refreshAlcove(alcove['id'] as String),
                  child: const Text('Actualiser l’Alcôve')),
              if (controller.config.devMode)
                Wrap(spacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                      onPressed: () => controller.forceDayNightPhase('DAY'),
                      icon: const Icon(Icons.light_mode_outlined),
                      label: const Text('Forcer Jour')),
                  OutlinedButton.icon(
                      onPressed: () => controller.forceDayNightPhase('NIGHT'),
                      icon: const Icon(Icons.dark_mode_outlined),
                      label: const Text('Forcer Nuit')),
                  TextButton(
                      onPressed: () => controller.forceDayNightPhase(null),
                      child: const Text('Cycle réel')),
                ]),
            ]),
            _section(context, 'Poser un objet', <Widget>[
              const Text(
                  'Choisissez un objet, puis posez-le dans une zone de l’Alcôve.'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                  onPressed: () => _openInventory(
                      context, controller, individual, _placeFromInventory),
                  icon: const Icon(Icons.card_giftcard_outlined),
                  label: const Text('Choisir dans l’inventaire')),
              if (controller.config.devMode)
                TextButton.icon(
                    onPressed: controller.addDevInventory,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Ajouter inventaire dev')),
            ]),
            _section(context, 'Installations', <Widget>[
              ...List<Widget>.generate((alcove['slots'] as List).length,
                  (index) {
                final raw = (alcove['slots'] as List)[index];
                if (raw is Map) {
                  final definition = controller.config
                      .installation(raw['definitionId'] as String);
                  final production = raw['productionState'];
                  final stock =
                      (definition?.productive ?? false) && production is Map
                          ? production['availableByItemId']
                          : null;
                  return ListTile(
                    leading: const Icon(Icons.cabin_outlined),
                    title: Text(ElevagePresentation.installationLabel(
                        raw['definitionId'] as String)),
                    subtitle: Text(stock is Map && stock.isNotEmpty
                        ? stock.entries
                            .where((entry) => entry.value != 0)
                            .map((entry) =>
                                '${ElevagePresentation.itemLabel(entry.key as String)} × ${entry.value}')
                            .join(' · ')
                        : 'En place'),
                    onTap: definition == null
                        ? null
                        : () => _showInstallationDetails(context,
                            controller.config, definition, environment),
                    trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () =>
                            controller.remove(alcove['id'] as String, index)),
                  );
                }
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text('Emplacement ${index + 1} · libre'),
                  onTap: () => _placeInstallation(
                      context, controller, alcove['id'] as String, index),
                );
              }),
              FilledButton.tonalIcon(
                  onPressed: () => _openBiofabricator(
                      context, controller, alcove['id'] as String),
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                  label: const Text('Bio-fabricateur')),
            ]),
            _section(context, 'Explorer', <Widget>[
              FilledButton.icon(
                  onPressed: () =>
                      _foraging(context, controller, widget.individualId),
                  icon: const Icon(Icons.forest_outlined),
                  label: const Text('Explorer la Mini-Lisière')),
              const SizedBox(height: 6),
              FilledButton.tonalIcon(
                  onPressed: () => _sourcier(context, controller),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Rencontrer le Sourcier')),
            ]),
            if (available)
              FilledButton.icon(
                  onPressed: () =>
                      _metamorphosis(context, controller, widget.individualId),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Accompagner la métamorphose')),
          ],
        ),
      ),
    );
  }
}

class ElevageNotebookPage extends StatelessWidget {
  const ElevageNotebookPage(
      {super.key, required this.controller, required this.individualId});
  final ElevageController controller;
  final String individualId;

  @override
  Widget build(BuildContext context) {
    final individual =
        (controller.state!.data['individuals'] as Map)[individualId] as Map;
    final name = individual['name'] as String;
    final journal = individual['observationJournal'] as Map;
    final observations =
        (journal['observations'] as Map? ?? <dynamic, dynamic>{})
            .values
            .whereType<Map>()
            .toList();
    final hypotheses = observations
        .where((item) =>
            item['status'] == 'SUSPECTED' || item['suspectedAt'] != null)
        .toList();
    final discoveries =
        observations.where((item) => item['status'] == 'CONFIRMED').toList();
    final memories =
        ((controller.state!.data['memoryEvents'] as Map)[individualId] as Map?)
                ?.keys
                .cast<String>()
                .toList() ??
            <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Carnet d’observation')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        Text('Carnet de $name',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Il se remplit au fil de vos observations significatives.'),
        _notebookSection(
            context,
            'Observations',
            observations.isEmpty
                ? const <Widget>[
                    Text('Aucune observation significative pour le moment.')
                  ]
                : observations
                    .map((item) => ListTile(
                        leading: const Icon(Icons.visibility_outlined),
                        title: Text(
                            ElevagePresentation.observationText(item, name)),
                        subtitle:
                            const Text('Comportement significatif relevé')))
                    .toList()),
        _notebookSection(
            context,
            'Hypothèses',
            hypotheses.isEmpty
                ? const <Widget>[Text('Aucune hypothèse pour le moment.')]
                : hypotheses
                    .map((item) => ListTile(
                        leading: const Icon(Icons.lightbulb_outline),
                        title: Text(
                            ElevagePresentation.hypothesisText(item, name)),
                        subtitle: ElevagePresentation.hypothesisAdvice(item) ==
                                null
                            ? null
                            : Text(ElevagePresentation.hypothesisAdvice(item)!),
                        trailing: item['status'] == 'CONFIRMED'
                            ? const Icon(Icons.check_circle_outline)
                            : null))
                    .toList()),
        _notebookSection(
            context,
            'Découvertes confirmées',
            discoveries.isEmpty
                ? const <Widget>[Text('Aucune découverte confirmée.')]
                : discoveries
                    .map((item) => ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(ElevagePresentation.confirmedText(item))))
                    .toList()),
        _notebookSection(
            context,
            'Souvenirs',
            memories.isEmpty
                ? const <Widget>[
                    Text('Aucun souvenir marquant pour le moment.')
                  ]
                : memories
                    .map((memory) => ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text(_memoryLabel(memory))))
                    .toList()),
      ]),
    );
  }
}

Widget _notebookSection(
        BuildContext context, String title, List<Widget> children) =>
    Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...children,
                ])));

class ElevageDashboardPage extends StatefulWidget {
  const ElevageDashboardPage({super.key, required this.controller});
  final ElevageController controller;
  @override
  State<ElevageDashboardPage> createState() => _ElevageDashboardPageState();
}

class _ElevageDashboardPageState extends State<ElevageDashboardPage> {
  late ElevageConfig config;
  @override
  void initState() {
    super.initState();
    config = widget.controller.config;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dashboard Élevage')),
        body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          SwitchListTile(
              value: config.featureEnabled,
              onChanged: (value) => setState(
                  () => config = config.copyWith(featureEnabled: value)),
              title: const Text('Élevage activé')),
          SwitchListTile(
              value: config.devMode,
              onChanged: (value) =>
                  setState(() => config = config.copyWith(devMode: value)),
              title: const Text('Mode dev')),
          DropdownButtonFormField<ElevagePreset>(
              initialValue: config.preset,
              decoration: const InputDecoration(labelText: 'Preset'),
              items: ElevagePreset.values
                  .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(item == ElevagePreset.prototype
                          ? 'PROTOTYPE'
                          : 'TARGET')))
                  .toList(),
              onChanged: (value) =>
                  setState(() => config = config.copyWith(preset: value))),
          _number(context, 'Alcôves (nouvelle partie)', config.alcoveCount,
              (value) => config = config.copyWith(alcoveCount: value)),
          _heading('Maturation, faim et découverte'),
          Text(
              'Bébé : ${config.babyMinimumHours} h · Intermédiaire : ${config.intermediateMinimumHours} h'),
          _number(context, 'Normal après (h)', config.hungerNormalHours,
              (value) => config = config.copyWith(hungerNormalHours: value)),
          _number(context, 'Faim après (h)', config.hungerHungryHours,
              (value) => config = config.copyWith(hungerHungryHours: value)),
          _number(
              context,
              'Très faim après (h)',
              config.hungerVeryHungryHours,
              (value) =>
                  config = config.copyWith(hungerVeryHungryHours: value)),
          _number(context, 'Preuves suspectées', config.suspectedThreshold,
              (value) => config = config.copyWith(suspectedThreshold: value)),
          _number(context, 'Preuves confirmées', config.confirmedThreshold,
              (value) => config = config.copyWith(confirmedThreshold: value)),
          _number(
              context,
              'Observation textuelle après',
              config.observationTextThreshold,
              (value) =>
                  config = config.copyWith(observationTextThreshold: value)),
          _number(
              context,
              'Fenêtre de preuve (min)',
              config.observationEvidenceCooldownMinutes,
              (value) => config =
                  config.copyWith(observationEvidenceCooldownMinutes: value)),
          _heading('Cycle et inventaire'),
          _number(context, 'Jour (h)', config.dayDurationHours,
              (value) => config = config.copyWith(dayDurationHours: value)),
          _number(context, 'Nuit (h)', config.nightDurationHours,
              (value) => config = config.copyWith(nightDurationHours: value)),
          _number(context, 'Taille d’une pile', config.inventoryStackSize,
              (value) => config = config.copyWith(inventoryStackSize: value)),
          _heading('Séjour dans une zone'),
          _number(
              context,
              'Bébé · séjour neutre (s)',
              config.baseStayBabySeconds,
              (value) => config = config.copyWith(baseStayBabySeconds: value)),
          _number(
              context,
              'Intermédiaire · séjour neutre (s)',
              config.baseStayIntermediateSeconds,
              (value) =>
                  config = config.copyWith(baseStayIntermediateSeconds: value)),
          _number(
              context,
              'Mature · séjour neutre (s)',
              config.baseStayMatureSeconds,
              (value) =>
                  config = config.copyWith(baseStayMatureSeconds: value)),
          _number(
              context,
              'Modificateur Posé (s)',
              config.tempoPosedStayModifierSeconds,
              (value) => config =
                  config.copyWith(tempoPosedStayModifierSeconds: value)),
          _number(
              context,
              'Modificateur Spontané (s)',
              config.tempoSpontaneousStayModifierSeconds,
              (value) => config =
                  config.copyWith(tempoSpontaneousStayModifierSeconds: value)),
          _number(
              context,
              'Zone idéale / bonne (s)',
              config.perfectZoneStayModifierSeconds,
              (value) => config =
                  config.copyWith(perfectZoneStayModifierSeconds: value)),
          _number(
              context,
              'Zone inconfortable (s)',
              config.badZoneStayModifierSeconds,
              (value) =>
                  config = config.copyWith(badZoneStayModifierSeconds: value)),
          _number(
              context,
              'Zone extrême (s)',
              config.extremeZoneStayModifierSeconds,
              (value) => config =
                  config.copyWith(extremeZoneStayModifierSeconds: value)),
          _number(context, 'Minimum absolu (s)', config.minStaySeconds,
              (value) => config = config.copyWith(minStaySeconds: value)),
          _number(context, 'Gain de résonance', config.resonanceGainPerUse,
              (value) => config = config.copyWith(resonanceGainPerUse: value)),
          _heading('Mini-Lisière et installations'),
          _number(
              context,
              'Durée de sortie (s)',
              config.foragingDurationSeconds,
              (value) =>
                  config = config.copyWith(foragingDurationSeconds: value)),
          _number(
              context,
              'Intervalle de production (s)',
              config.productionIntervalSeconds,
              (value) =>
                  config = config.copyWith(productionIntervalSeconds: value)),
          _number(context, 'Stock local maximum', config.productionMaxStock,
              (value) => config = config.copyWith(productionMaxStock: value)),
          _heading('Co-élevage et Sourcier'),
          _number(
              context,
              'Durée co-élevage (h)',
              config.coRearingDurationHours,
              (value) =>
                  config = config.copyWith(coRearingDurationHours: value)),
          _number(context, 'Prix Fruit fibreux', config.fibrousFruitPrice,
              (value) => config = config.copyWith(fibrousFruitPrice: value)),
          _number(context, 'Prix Jelly fruité', config.fruitJellyPrice,
              (value) => config = config.copyWith(fruitJellyPrice: value)),
          _number(context, 'Lot de rachat', config.buybackQuantity,
              (value) => config = config.copyWith(buybackQuantity: value)),
          _heading('Bio-fabricateur'),
          ...config.recipes.map((recipe) => ListTile(
              title: Text(recipe.label),
              subtitle: Text(_recipeCostSummary(recipe)),
              onTap: () => _editRecipe(context, recipe))),
          _heading('Effets des structures et de l’habitat'),
          const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                  'Les structures modifient Lumière, Température et Humidité. Les meubles et décorations ne règlent ici que leur effet de bien-être : leurs préférences individuelles restent secrètes.')),
          ...config.installations.map((definition) => ListTile(
              leading:
                  Icon(ElevagePresentation.installationIcon(definition.id)),
              title: Text(definition.label),
              subtitle: Text(_installationEffectSummary(definition)),
              trailing: const Icon(Icons.tune),
              onTap: () => _editInstallationEffects(context, definition))),
          _heading('Matrice écologique des Natures'),
          const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                  'Chaque Nature possède ses propres optima et courbes 0–5. Le pire axe local détermine le confort.')),
          ...config.natureProfiles.map((profile) => ListTile(
              leading: Text(profile.placeholder,
                  style: const TextStyle(fontSize: 26)),
              title: Text(profile.label),
              subtitle: Text(
                  'Optimum · ☀️ ${profile.preferredLight}/5 · 🌡️ ${profile.preferredTemperature}/5 · 💧 ${profile.preferredHumidity}/5'),
              trailing: const Icon(Icons.tune),
              onTap: () => _editNatureProfile(context, profile))),
          _heading('Métamorphose'),
          _number(
              context,
              'Tolérance rythmique (ms)',
              config.metamorphosisToleranceMs,
              (value) =>
                  config = config.copyWith(metamorphosisToleranceMs: value)),
          _heading('Voix et onomatopées'),
          const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                  'Ces textes apparaissent dans les petites bulles de communication.')),
          ..._vocalizationLabels.entries.map((entry) => ListTile(
                title: Text(entry.value),
                subtitle: Text(config.vocalizations[entry.key] ?? ''),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editVocalization(context, entry.key, entry.value),
              )),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () async {
                await widget.controller.saveConfig(config);
                if (!mounted) return;
                Navigator.of(this.context).pop();
              },
              child: const Text('Appliquer les réglages')),
          TextButton(
              onPressed: () async {
                await widget.controller.resetConfig();
                if (!mounted) return;
                setState(() => config = widget.controller.config);
              },
              child: const Text('Réinitialiser les réglages')),
          if (config.devMode) ...<Widget>[
            _heading('Réinitialisation QA'),
            OutlinedButton.icon(
                icon: const Icon(Icons.home_work_outlined),
                label: const Text('Réinitialiser seulement les Alcôves'),
                onPressed: () => _confirmReset(context, false)),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Réinitialiser la partie Élevage'),
                onPressed: () => _confirmReset(context, true)),
          ],
        ]),
      );

  Widget _heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge));
  Widget _number(BuildContext context, String label, int value,
          void Function(int) apply) =>
      ListTile(
          title: Text(label),
          trailing: Text('$value'),
          onTap: () async {
            final next = await _numberDialog(context, label, value);
            if (!context.mounted || next == null) return;
            setState(() => apply(next));
          });
  String _recipeCostSummary(ElevageRecipe recipe) => <String>[
        '${recipe.organic} Organique',
        '${recipe.mineral} Minéral',
        ...recipe.special.entries.map((entry) =>
            '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}'),
      ].join(' · ');

  String _installationEffectSummary(ElevageInstallationDefinition definition) {
    if (definition.category != 'STRUCTURE') {
      return 'Bien-être ${_signed(definition.wellbeingImpact)}';
    }
    return '☀️ ${_signed(definition.light)} · '
        '🌡️ ${_signed(definition.temperature)} · '
        '💧 ${_signed(definition.humidity)}';
  }

  Future<void> _editInstallationEffects(
      BuildContext context, ElevageInstallationDefinition definition) async {
    final fields = definition.category == 'STRUCTURE'
        ? <String, int>{
            'light': definition.light,
            'temperature': definition.temperature,
            'humidity': definition.humidity,
          }
        : <String, int>{'wellbeing': definition.wellbeingImpact};
    final labels = <String, String>{
      'light': 'Lumière',
      'temperature': 'Température',
      'humidity': 'Humidité',
      'wellbeing': 'Bien-être',
    };
    final controllers = <String, TextEditingController>{
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: '${entry.value}'),
    };
    Map<String, int>? next;
    String? error;
    try {
      next = await showDialog<Map<String, int>>(
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (dialogContext, setLocal) {
                return AlertDialog(
                    title: Text('${definition.label} · effets'),
                    content: SizedBox(
                        width: double.maxFinite,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(definition.category == 'STRUCTURE'
                              ? 'Effets locaux appliqués dans la zone de la structure.'
                              : 'Effet de bien-être de cet objet. Les affinités individuelles ne sont pas réglables ici.'),
                          const SizedBox(height: 12),
                          ...fields.keys.map((key) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextField(
                                  controller: controllers[key],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          signed: true),
                                  decoration: InputDecoration(
                                      labelText: labels[key],
                                      helperText: 'Entre -5 et +5')))),
                          if (error != null)
                            Text(error!,
                                style: const TextStyle(color: Colors.red)),
                        ])),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () {
                            final values = <String, int>{};
                            for (final key in fields.keys) {
                              final value =
                                  int.tryParse(controllers[key]!.text.trim());
                              if (value == null || value < -5 || value > 5) {
                                setLocal(() => error =
                                    'Utilisez un nombre entier entre -5 et +5.');
                                return;
                              }
                              values[key] = value;
                            }
                            Navigator.pop(dialogContext, values);
                          },
                          child: const Text('Valider'))
                    ]);
              }));
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    if (!context.mounted || next == null) return;
    setState(() => config = config.copyWith(installationEffects: {
          ...config.installationEffects,
          definition.id: next!,
        }));
  }

  Future<void> _editRecipe(BuildContext context, ElevageRecipe recipe) async {
    final organic = await _numberDialog(
        context, '${recipe.label} · Organique', recipe.organic);
    if (organic == null) return;
    if (!context.mounted) return;
    final mineral = await _numberDialog(
        context, '${recipe.label} · Minéral', recipe.mineral);
    if (!context.mounted || mineral == null) return;
    final special = await _editRecipeSpecialComponents(context, recipe);
    if (!context.mounted || special == null) return;
    setState(() => config = config.copyWith(
        recipes: config.recipes
            .map((item) => item.id == recipe.id
                ? item.copyWith(
                    organic: organic, mineral: mineral, special: special)
                : item)
            .toList()));
  }

  Future<Map<String, int>?> _editRecipeSpecialComponents(
      BuildContext context, ElevageRecipe recipe) async {
    final components = Map<String, int>.from(recipe.special);
    return showDialog<Map<String, int>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setLocal) => AlertDialog(
                title: Text('${recipe.label} · composants'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text(
                              'Organique et Minéral sont réglés séparément. Ajoutez ici les ressources spécifiques nécessaires.'),
                          const SizedBox(height: 12),
                          if (components.isEmpty)
                            const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Aucun composant spécifique.')),
                          ...components.entries.map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: <Widget>[
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                      initialValue: entry.key,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Composant'),
                                      items: elevageRecipeSpecialComponentIds
                                          .where((id) =>
                                              id == entry.key ||
                                              !components.containsKey(id))
                                          .map((id) => DropdownMenuItem(
                                              value: id,
                                              child: Text(
                                                  ElevagePresentation.itemLabel(
                                                      id))))
                                          .toList(),
                                      onChanged: (next) {
                                        if (next == null || next == entry.key) {
                                          return;
                                        }
                                        final quantity = entry.value;
                                        setLocal(() {
                                          components.remove(entry.key);
                                          components[next] = quantity;
                                        });
                                      }),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                    width: 68,
                                    child: TextFormField(
                                        key: ValueKey(
                                            '${entry.key}:${entry.value}'),
                                        initialValue: '${entry.value}',
                                        decoration: const InputDecoration(
                                            labelText: 'Qté'),
                                        keyboardType: TextInputType.number,
                                        onChanged: (raw) =>
                                            components[entry.key] =
                                                int.tryParse(raw) ?? 0)),
                                IconButton(
                                    tooltip: 'Retirer',
                                    onPressed: () => setLocal(
                                        () => components.remove(entry.key)),
                                    icon: const Icon(
                                        Icons.remove_circle_outline)),
                              ]))),
                          if (components.length <
                              elevageRecipeSpecialComponentIds.length)
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Ajouter un composant'),
                                    onPressed: () => setLocal(() {
                                          final next =
                                              elevageRecipeSpecialComponentIds
                                                  .firstWhere((id) =>
                                                      !components
                                                          .containsKey(id));
                                          components[next] = 1;
                                        }))),
                        ]),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () {
                        components.removeWhere((_, value) => value <= 0);
                        Navigator.pop(dialogContext, components);
                      },
                      child: const Text('Valider')),
                ],
              ),
            ));
  }

  Future<void> _editVocalization(
      BuildContext context, String key, String label) async {
    final current = config.vocalizations[key] ?? '';
    final next = await _textDialog(context, label, current);
    if (!context.mounted || next == null) return;
    final clean = next.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Une onomatopée ne peut pas être vide.')));
      return;
    }
    setState(() => config = config.copyWith(
        vocalizations: <String, String>{...config.vocalizations, key: clean}));
  }

  Future<void> _editNatureProfile(
      BuildContext context, ElevageNatureProfile profile) async {
    var draft = profile;
    final next = await showDialog<ElevageNatureProfile>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setLocal) {
                void updateCurve(String axis, int index, String value) {
                  final curves = <String, List<String>>{
                    for (final entry in draft.curves.entries)
                      entry.key: List<String>.from(entry.value),
                  };
                  curves[axis]![index] = value;
                  setLocal(() => draft = draft.copyWith(curves: curves));
                }

                Widget preference(String axis, int current) =>
                    DropdownButtonFormField<int>(
                        key: ValueKey('$axis:$current'),
                        initialValue: current,
                        decoration: InputDecoration(
                            labelText:
                                'Optimum ${_environmentAxisLabel(axis)}'),
                        items: List<DropdownMenuItem<int>>.generate(
                            6,
                            (value) => DropdownMenuItem(
                                value: value, child: Text('$value / 5'))),
                        onChanged: (value) {
                          if (value == null) return;
                          setLocal(() => draft = switch (axis) {
                                'light' =>
                                  draft.copyWith(preferredLight: value),
                                'temperature' =>
                                  draft.copyWith(preferredTemperature: value),
                                _ => draft.copyWith(preferredHumidity: value),
                              });
                        });

                return AlertDialog(
                    title: Text(draft.label),
                    content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                              const Text(
                                  'Les valeurs servent au domaine, aux diagnostics et aux futures découvertes ; elles ne révèlent rien au joueur avant observation.'),
                              const SizedBox(height: 12),
                              preference('light', draft.preferredLight),
                              preference(
                                  'temperature', draft.preferredTemperature),
                              preference('humidity', draft.preferredHumidity),
                              const SizedBox(height: 16),
                              for (final axis in <String>[
                                'light',
                                'temperature',
                                'humidity'
                              ]) ...<Widget>[
                                Text(_environmentAxisLabel(axis),
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                for (var index = 0; index <= 5; index++)
                                  DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          '$axis:$index:${draft.curves[axis]![index]}'),
                                      initialValue: draft.curves[axis]![index],
                                      decoration: InputDecoration(
                                          labelText: '$index / 5'),
                                      items: const <String>[
                                        'IDEAL',
                                        'GOOD',
                                        'NEUTRAL',
                                        'BAD',
                                        'EXTREME'
                                      ]
                                          .map((state) => DropdownMenuItem(
                                              value: state, child: Text(state)))
                                          .toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          updateCurve(axis, index, value);
                                        }
                                      }),
                                const SizedBox(height: 8),
                              ],
                            ]))),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, draft),
                          child: const Text('Valider')),
                    ]);
              },
            ));
    if (!context.mounted || next == null) return;
    setState(() => config = config.copyWith(
        natureProfiles: config.natureProfiles
            .map((current) => current.id == next.id ? next : current)
            .toList(growable: false)));
  }

  Future<void> _confirmReset(BuildContext context, bool wholeGame) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(wholeGame
                  ? 'Réinitialiser P’TIPOTE Élevage ?'
                  : 'Réinitialiser les Alcôves ?'),
              content: Text(wholeGame
                  ? 'Les individus, inventaires, observations et installations Élevage seront effacés. Zone 0 ne sera jamais touchée.'
                  : 'Les occupants, objets posés et installations des Alcôves seront effacés. Votre inventaire et vos réglages sont conservés.'),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Réinitialiser')),
              ],
            ));
    if (accepted != true) return;
    if (wholeGame) {
      await widget.controller.resetGame();
    } else {
      await widget.controller.resetAlcoves();
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}

PreferredSizeWidget _appBar(
        BuildContext context, ElevageController controller) =>
    AppBar(title: const Text('Expériences PTIPOTE'), actions: <Widget>[
      if (controller.config.devMode)
        IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Réglages de test',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ElevageDashboardPage(controller: controller))))
    ]);

Widget _elevageCanvas({required Widget child}) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF111C18),
        gradient: RadialGradient(
          center: Alignment(.98, -.82),
          radius: 1.14,
          colors: <Color>[Color(0x663C3420), Color(0x00111C18)],
          stops: <double>[0, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: child,
        ),
      ),
    );

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: Color(0xFFE7C67F),
          fontFamily: 'Avenir Next',
          fontFamilyFallback: <String>['Helvetica Neue', 'Arial', 'sans-serif'],
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.25,
        ),
      );
}

class _ElevageMark extends StatelessWidget {
  const _ElevageMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF9A9474)),
        ),
        child: Icon(
          Icons.diamond_outlined,
          size: size * .48,
          color: const Color(0xFFEFD298),
        ),
      );
}

Widget _section(BuildContext context, String title, List<Widget> children) =>
    Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...children
                ])));
String _stageLabel(String value) => switch (value) {
      'BABY' => 'Bébé',
      'INTERMEDIATE' => 'Intermédiaire',
      _ => 'Mature'
    };
String _individualNatureLabel(Map individual) {
  final family = individual['family'] as String? ?? 'MINERAL';
  final nature = individual['nature'] as String? ?? 'RESONANCE';
  return switch ('$family:$nature') {
    'VEGETAL:PHOTOSYNTHESIS' => 'Végétal · Photosynthèse',
    'FUNGAL:DECOMPOSITION' => 'Fongique · Décomposition',
    _ => 'Minéral · Résonance',
  };
}

String _environmentAxisLabel(String axis) => switch (axis) {
      'light' => 'Lumière',
      'temperature' => 'Température',
      _ => 'Humidité',
    };
String _hungerLabel(String value) => switch (value) {
      'SATIATED' => 'Rassasié',
      'NORMAL' => 'Bien',
      'HUNGRY' => 'A faim',
      _ => 'Très faim'
    };
String _communicationLabel(String value) => switch (value) {
      'ROOT' => 'Souhaite une racine',
      'LEAF' => 'Souhaite une feuille',
      'IRON' => 'Recherche du fer',
      'FOOD' => 'A faim',
      _ => 'Besoin minéral'
    };
String _coRemaining(Map ownership, int now) {
  final remaining = ((ownership['expiresAt'] as int) - now).clamp(0, 999999999);
  return 'Co-élevage · encore ${(remaining / const Duration(days: 1).inMilliseconds).ceil()} j';
}

String _personalityLabel(Map individual) {
  final baseline = individual['personality']['baseline'] as Map;
  final tendencies = individual['personality']['tendencies'] as Map;
  final initiative =
      (baseline['initiative'] as int) + (tendencies['initiative'] as int);
  final contact = (baseline['contact'] as int) + (tendencies['contact'] as int);
  final tempo = (baseline['tempo'] as int) + (tendencies['tempo'] as int);
  return '${initiative >= 50 ? 'Autonome' : 'Accompagné'} · ${contact >= 50 ? 'Chaleureux' : 'Réservé'} · ${tempo >= 50 ? 'Posé' : 'Spontané'}';
}

Widget _environmentBadge(String emoji, int value) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.black12, borderRadius: BorderRadius.circular(10)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Text('$emoji $value/5'))));

String _memoryLabel(String memory) => switch (memory) {
      'ADOPTED' => 'Arrivée dans l’Alcôve',
      'FIRST_FOOD' => 'Premier repas',
      'FIRST_FAVORITE_FOOD' => 'Premier aliment favori',
      'FIRST_TREAT' => 'Première friandise',
      'FIRST_AUTONOMOUS_MEAL' => 'Premier repas autonome',
      'FIRST_METAMORPHOSIS' => 'Première métamorphose',
      'SECOND_METAMORPHOSIS' => 'Deuxième métamorphose',
      _ => 'Souvenir important',
    };

/// Scène placeholder volontairement composée d’icônes Flutter : les futures
/// illustrations/sprites pourront remplacer cette couche sans toucher au domaine.
class _AlcoveScene extends StatefulWidget {
  const _AlcoveScene({
    required this.stage,
    required this.family,
    required this.reaction,
    required this.feedback,
    required this.slots,
    required this.environment,
    required this.sceneItems,
    required this.habitatItems,
    required this.zones,
    required this.onSceneItemTap,
    required this.onHabitatItemTap,
    required this.onZoneTap,
    required this.onZoneHoldStart,
    required this.onZoneHoldEnd,
    required this.onPtipoteTap,
    required this.onPtipoteHoldStart,
    required this.onPtipoteHoldEnd,
    required this.onInstallationSlotTap,
    required this.onEnvironmentTap,
    required this.pendingItem,
    required this.followHoldZoneId,
    required this.action,
    required this.voice,
    required this.bubbleItemId,
    required this.ptipoteHoldActive,
    required this.requestSignal,
    required this.sleeping,
    required this.crystallizing,
    required this.ptipoteZoneId,
    required this.phase,
    required this.phaseRemainingMs,
    required this.now,
    required this.config,
    required this.zoneEnvironments,
  });
  final String stage;
  final String family;
  final String? reaction;
  final String? feedback;
  final List<dynamic> slots;
  final Map<String, int> environment;
  final List<Map<String, dynamic>> sceneItems;
  final List<Map<String, dynamic>> habitatItems;
  final List<ElevageSceneZone> zones;
  final ValueChanged<Map> onSceneItemTap;
  final ValueChanged<Map> onHabitatItemTap;
  final ValueChanged<String>? onZoneTap;
  final ValueChanged<String> onZoneHoldStart;
  final VoidCallback onZoneHoldEnd;
  final VoidCallback onPtipoteTap;
  final VoidCallback onPtipoteHoldStart;
  final VoidCallback onPtipoteHoldEnd;
  final ValueChanged<int> onInstallationSlotTap;
  final VoidCallback onEnvironmentTap;
  final String? pendingItem;
  final String? followHoldZoneId;
  final String action;
  final String? voice;
  final String? bubbleItemId;
  final bool ptipoteHoldActive;
  final String? requestSignal;
  final bool sleeping;
  final bool crystallizing;
  final String ptipoteZoneId;
  final String phase;
  final int phaseRemainingMs;
  final int now;
  final ElevageConfig config;
  final Map<String, Map<String, int>> zoneEnvironments;

  @override
  State<_AlcoveScene> createState() => _AlcoveSceneState();
}

class _AlcoveSceneState extends State<_AlcoveScene> {
  Timer? _crystalPulseTimer;
  bool _crystalPulse = false;

  @override
  void initState() {
    super.initState();
    _crystalPulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && widget.crystallizing) {
        setState(() => _crystalPulse = !_crystalPulse);
      }
    });
  }

  @override
  void dispose() {
    _crystalPulseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = switch (widget.stage) {
      'BABY' => 38.0,
      'INTERMEDIATE' => 47.0,
      _ => 56.0,
    };
    final reactionScale = widget.reaction == 'RUSH_SHAKE'
        ? 1.14
        : widget.reaction == 'STEP_BACK'
            ? .88
            : 1.0;
    final installed = widget.slots.whereType<Map>().toList();
    return Semantics(
      label: 'Scène de l’Alcôve',
      child: Container(
        height: 252,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: <Color>[
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Stack(children: <Widget>[
          Positioned(
              left: 14,
              top: 10,
              child: Text(
                  '${widget.phase == 'DAY' ? '☀️ Jour' : '🌙 Nuit'} · ${_clockLabel(widget.phaseRemainingMs)}')),
          Positioned(
            right: 8,
            top: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onEnvironmentTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  _environmentBadge(
                      '☀️',
                      ElevagePresentation.environmentScale(
                          widget.environment['light']!)),
                  _environmentBadge(
                      '🌡️',
                      ElevagePresentation.environmentScale(
                          widget.environment['temperature']!)),
                  _environmentBadge(
                      '💧',
                      ElevagePresentation.environmentScale(
                          widget.environment['humidity']!)),
                ]),
              ),
            ),
          ),
          Positioned.fill(
            top: 42,
            bottom: 0,
            child: Row(
              children: widget.zones.asMap().entries.map((entry) {
                final zone = entry.value;
                return Expanded(
                  child: GestureDetector(
                    onLongPressStart: (_) => widget.onZoneHoldStart(zone.id),
                    onLongPressEnd: (_) => widget.onZoneHoldEnd(),
                    onLongPressCancel: widget.onZoneHoldEnd,
                    // A normal tap only matters while the player is placing
                    // an item. It no longer leaves a decorative selection
                    // filter behind when the scene has nothing to do.
                    onTap: widget.pendingItem == null
                        ? null
                        : () => widget.onZoneTap?.call(zone.id),
                    child: Stack(children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: _zoneColor(
                              context,
                              ElevagePresentation.environmentScale(
                                  widget.zoneEnvironments[zone.id]!['light']!),
                              false),
                          border: Border(
                              right: BorderSide(
                                  color: Colors.white.withValues(alpha: .32))),
                        ),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('Z${entry.key + 1}',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                      if (widget.followHoldZoneId == zone.id)
                        Center(
                            child: LongPressProgressInteraction(
                                duration: Duration(
                                    seconds:
                                        widget.config.longPressHoldSeconds))),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          ...widget.zones.asMap().entries.map((entry) {
            final index = entry.key;
            final zone = entry.value;
            final item = widget.sceneItems
                .where((placed) => placed['zoneId'] == zone.id)
                .firstOrNull;
            final alignment = <Alignment>[
              const Alignment(-.75, .42),
              const Alignment(-.24, .46),
              const Alignment(.28, .46),
              const Alignment(.76, .42),
            ][index];
            return AnimatedAlign(
              duration: const Duration(milliseconds: 350),
              alignment: alignment,
              child: Semantics(
                button: true,
                label: item == null
                    ? '${zone.label}, zone libre'
                    : '${ElevagePresentation.itemLabel(item['itemId'] as String)} posé dans ${zone.label}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: item == null
                      ? (widget.pendingItem == null
                          ? null
                          : () => widget.onZoneTap?.call(zone.id))
                      : () => widget.onSceneItemTap(item),
                  child: Container(
                    width: 46,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: item == null
                            ? Colors.black.withValues(alpha: .04)
                            : Theme.of(context).colorScheme.tertiaryContainer),
                    child: item == null
                        ? Text('${index + 1}',
                            style: const TextStyle(fontSize: 11))
                        : Icon(ElevagePresentation.itemIcon(
                            item['itemId'] as String)),
                  ),
                ),
              ),
            );
          }),
          ...widget.habitatItems.asMap().entries.map((entry) {
            final item = entry.value;
            final zoneIndex = widget.zones
                .indexWhere((zone) => zone.id == item['zoneId'] as String?);
            final safeZoneIndex = zoneIndex < 0 ? 0 : zoneIndex;
            final order = (item['positionOrder'] as num? ?? entry.key).toInt();
            final x = <double>[
              -.82,
              -.45,
              -.08,
              .30,
              .68
            ][(safeZoneIndex + order) % 5];
            return AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              alignment: Alignment(x, order.isEven ? .04 : -.06),
              child: Semantics(
                button: true,
                label: 'Objet d’habitat',
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.onHabitatItemTap(item),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: .88),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(
                        ElevagePresentation.installationIcon(
                            item['definitionId'] as String),
                        size: 18),
                  ),
                ),
              ),
            );
          }),
          ...widget.zones.asMap().entries.map((entry) {
            final index = entry.key;
            final raw = widget.slots[index];
            return AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: <Alignment>[
                const Alignment(-.75, .73),
                const Alignment(-.25, .73),
                const Alignment(.25, .73),
                const Alignment(.75, .73),
              ][index],
              child: Semantics(
                button: true,
                label: raw is Map
                    ? 'Installation de Z${index + 1}'
                    : 'Installer dans Z${index + 1}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onInstallationSlotTap(index),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: raw is Map
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Colors.black.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: .5)),
                    ),
                    child: raw is Map
                        ? Icon(
                            ElevagePresentation.installationIcon(
                                raw['definitionId'] as String),
                            size: 18)
                        : const Icon(Icons.add, size: 18),
                  ),
                ),
              ),
            );
          }),
          if (installed.isEmpty)
            const Center(child: Text('Un foyer calme, prêt à être aménagé.')),
          AnimatedAlign(
            duration: Duration(
                milliseconds: widget.action == 'FLEE_NORMAL'
                    ? (widget.config.normalMoveDurationMs / 2).round()
                    : widget.action == 'FLEE_FAST'
                        ? (widget.config.normalMoveDurationMs / 3).round()
                        : widget.action == 'MOVE_ITEM'
                            ? widget.config.runMoveDurationMs
                            : widget.config.normalMoveDurationMs),
            curve: Curves.easeInOut,
            alignment: _zoneAlignment(widget.ptipoteZoneId),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: reactionScale,
              child: Stack(clipBehavior: Clip.none, children: <Widget>[
                Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      boxShadow: const <BoxShadow>[
                        BoxShadow(blurRadius: 8, color: Colors.black26)
                      ]),
                  child: GestureDetector(
                    onLongPressStart: (_) => widget.onPtipoteHoldStart(),
                    onLongPressEnd: (_) => widget.onPtipoteHoldEnd(),
                    onLongPressCancel: widget.onPtipoteHoldEnd,
                    onTap: widget.onPtipoteTap,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 620),
                      scale: widget.crystallizing
                          ? (_crystalPulse ? 1.16 : .92)
                          : 1,
                      child: Icon(
                        widget.crystallizing
                            ? Icons.diamond_outlined
                            : _ptipoteIcon(widget.stage, widget.family),
                        size: size * .62,
                      ),
                    ),
                  ),
                ),
                if (widget.ptipoteHoldActive)
                  Positioned.fill(
                      child: IgnorePointer(
                          child: LongPressProgressInteraction(
                              duration: Duration(
                                  seconds:
                                      widget.config.longPressHoldSeconds)))),
              ]),
            ),
          ),
          if (widget.crystallizing ||
              widget.sleeping ||
              widget.requestSignal != null ||
              widget.action != 'IDLE')
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: _bubbleAlignment(widget.ptipoteZoneId),
              child: _StatusBubble(
                signal: widget.requestSignal,
                action: widget.crystallizing
                    ? 'METAMORPHOSIS'
                    : widget.sleeping
                        ? 'SLEEP'
                        : widget.action,
                voice: widget.crystallizing ? '…' : widget.voice,
                itemId: widget.bubbleItemId,
              ),
            ),
          if (widget.pendingItem != null)
            Positioned(
              bottom: 8,
              right: 12,
              child: Chip(
                  avatar:
                      Icon(ElevagePresentation.itemIcon(widget.pendingItem!)),
                  label: Text(
                      'À poser : ${ElevagePresentation.itemLabel(widget.pendingItem!)}')),
            ),
          if (widget.feedback != null)
            Positioned(
              top: 14,
              right: 14,
              left: 48,
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: .92),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: widget.feedback!.isEmpty
                        ? Icon(_reactionIcon(widget.reaction))
                        : Text(widget.feedback!)),
              ),
            ),
        ]),
      ),
    );
  }
}

IconData _reactionIcon(String? behavior) => switch (behavior) {
      'RUSH_SHAKE' => Icons.priority_high,
      'VIBRATE' => Icons.hexagon_outlined,
      'STEP_BACK' => Icons.close,
      'MOVE_ITEM' => Icons.redo,
      'PICKUP' => Icons.pan_tool_alt_outlined,
      'FLEE_WITH_ITEM' => Icons.running_with_errors_outlined,
      'OBSERVE' => Icons.more_horiz,
      _ => Icons.arrow_forward,
    };

String _sceneActionForOutcome(String behavior, String itemId) =>
    switch (behavior) {
      'RUSH_SHAKE' => 'EAT',
      'APPROACH' when ElevageDomain.structuralItems.contains(itemId) =>
        'STRUCTURAL_ABSORB',
      'APPROACH' => 'EAT',
      'VIBRATE' => 'STRUCTURAL_ABSORB',
      'STEP_BACK' => 'REJECT',
      'MOVE_ITEM' => 'MOVE_ITEM',
      'PICKUP' => 'PICKUP',
      'FLEE_WITH_ITEM' => 'FLEE_WITH_ITEM',
      'OBSERVE' => 'IGNORE',
      _ => 'IDLE',
    };

Alignment _zoneAlignment(String zoneId) => switch (zoneId) {
      'ZONE_1' => const Alignment(-.75, .18),
      'ZONE_2' => const Alignment(-.25, .18),
      'ZONE_3' => const Alignment(.25, .18),
      'ZONE_4' => const Alignment(.75, .18),
      _ => const Alignment(-.25, .18),
    };

Alignment _bubbleAlignment(String zoneId) => switch (zoneId) {
      'ZONE_1' => const Alignment(-.75, -.22),
      'ZONE_2' => const Alignment(-.25, -.22),
      'ZONE_3' => const Alignment(.25, -.22),
      'ZONE_4' => const Alignment(.75, -.22),
      _ => const Alignment(-.25, -.22),
    };

IconData _ptipoteIcon(String stage, String family) {
  if (stage == 'BABY') return Icons.egg_outlined;
  return switch (family) {
    'VEGETAL' => Icons.spa_outlined,
    'FUNGAL' => Icons.emoji_nature_outlined,
    _ => Icons.diamond_outlined,
  };
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({
    required this.signal,
    required this.action,
    required this.voice,
    required this.itemId,
  });
  final String? signal;
  final String action;
  final String? voice;
  final String? itemId;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(_actionIcon(action, 'INTERMEDIATE'), size: 17),
            if (itemId != null) ...<Widget>[
              const SizedBox(width: 3),
              Icon(ElevagePresentation.itemIcon(itemId!), size: 15),
            ],
            if (signal != null || voice != null) ...<Widget>[
              const SizedBox(width: 4),
              Flexible(
                  child: Text(
                      voice ??
                          (signal == 'Pti ?'
                              ? 'Pti ?'
                              : _requestLabel(signal!)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800))),
            ],
          ]),
        ),
      );
}

String _requestLabel(String request) => switch (request) {
      'FOOD' || 'ROOT' || 'LEAF' => 'Pti !',
      'STRUCTURAL' || 'IRON' || 'LIMESTONE' => 'Mm !',
      'CONTACT' => 'Pti !',
      'SLEEP' => 'Nnh…',
      _ => 'Pti ?',
    };

/// Shared three-second consent/attention affordance for FOLLOW and WAKE.
class LongPressProgressInteraction extends StatelessWidget {
  const LongPressProgressInteraction({super.key, required this.duration});
  final Duration duration;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 76,
        height: 76,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: duration,
          builder: (context, value, _) => CircularProgressIndicator(
            value: value,
            strokeWidth: 6,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

String _clockLabel(int remainingMs) {
  final minutes =
      max(0, remainingMs ~/ const Duration(minutes: 1).inMilliseconds);
  return '${minutes ~/ 60} h ${minutes % 60} restantes';
}

IconData _actionIcon(String? action, String stage) => switch (action) {
      'MOVE' => Icons.directions_walk_outlined,
      'NOTICE_ITEM' || 'INSPECT_ITEM' || 'CURIOUS' => Icons.visibility_outlined,
      'APPROACH_ITEM' || 'FOLLOW' => Icons.arrow_forward,
      'THINK' => Icons.question_mark,
      'IGNORE' => Icons.more_horiz,
      'LIKE' || 'CONTENT' => Icons.sentiment_satisfied_alt_outlined,
      'NEUTRAL' => Icons.sentiment_neutral_outlined,
      'RUSH_SHAKE' || 'EAT' => Icons.restaurant_outlined,
      'VIBRATE' || 'STRUCTURAL_ABSORB' => Icons.diamond_outlined,
      'RESONATE' => Icons.auto_awesome,
      'STEP_BACK' || 'REJECT' => Icons.sentiment_very_dissatisfied_outlined,
      'DISCOMFORT' => Icons.sentiment_dissatisfied_outlined,
      'IRRITATED' => Icons.sentiment_very_dissatisfied_outlined,
      'EXTREME' => Icons.sentiment_very_dissatisfied_outlined,
      'FLEE' || 'FLEE_NORMAL' => Icons.priority_high,
      'FLEE_FAST' => Icons.running_with_errors_outlined,
      'SLEEP' => Icons.bedtime_outlined,
      'WAKE' => Icons.wb_sunny_outlined,
      'OBSERVE' => Icons.question_mark,
      'CUDDLE' => Icons.favorite,
      'MOVE_ITEM' => Icons.redo,
      'PICKUP' => Icons.pan_tool_alt_outlined,
      'FLEE_WITH_ITEM' => Icons.running_with_errors_outlined,
      'REST' => Icons.weekend_outlined,
      'PLAY' => Icons.sports_handball_outlined,
      'USE_FURNITURE' => Icons.chair_outlined,
      'METAMORPHOSIS' => Icons.diamond_outlined,
      _ => stage == 'BABY' ? Icons.egg_outlined : Icons.pets,
    };

Color _zoneColor(BuildContext context, int light, bool selected) {
  // Même valeur Light = même couleur, quelle que soit la zone. Une seule
  // teinte de base permet de lire la lumière sans code couleur parallèle.
  final base = <Color>[
    const Color(0xff162B25),
    const Color(0xff315044),
    const Color(0xff587866),
    const Color(0xff86A887),
    const Color(0xffBBD4AF),
  ][light.clamp(1, 5) - 1];
  return selected
      ? Color.alphaBlend(Colors.white.withValues(alpha: .24), base)
      : base;
}

String _localComfortLabel(String comfort, String name) => switch (comfort) {
      'IDEAL' || 'GOOD' => 'Cette zone lui convient très bien.',
      'BAD' => '$name semble mal à l’aise ici.',
      'EXTREME' => '$name semble vouloir quitter cet endroit.',
      _ => 'Cette zone lui paraît neutre.',
    };

Map<String, Object> _alcoveComfort(
    Map<String, Map<String, int>> zones, ElevageConfig config, Map individual) {
  const scores = <String, int>{
    'IDEAL': 4,
    'GOOD': 3,
    'NEUTRAL': 2,
    'BAD': 1,
    'EXTREME': 0,
  };
  final total = zones.values.fold<int>(
      0,
      (sum, zone) =>
          sum +
          scores[ElevageDomain.localComfort(zone, config,
              individual: individual)]!);
  final average = total / zones.length;
  final label = switch (average) {
    >= 3.5 => 'Très adaptée',
    >= 2.5 => 'Adaptée',
    >= 1.5 => 'Mitigée',
    >= .5 => 'Peu adaptée',
    _ => 'Inadaptée',
  };
  return <String, Object>{'value': average / 4, 'label': label};
}

Future<void> _showEnvironmentPanel(BuildContext context,
    Map<String, int> average, Map<String, Map<String, int>> zones) async {
  Widget values(Map<String, int> value) => Text(
      '☀️ ${ElevagePresentation.environmentScale(value['light'] ?? 0)}/5   '
      '🌡️ ${ElevagePresentation.environmentScale(value['temperature'] ?? 0)}/5   '
      '💧 ${ElevagePresentation.environmentScale(value['humidity'] ?? 0)}/5');
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const ListTile(
                  leading: Icon(Icons.landscape_outlined),
                  title: Text('Alcôve'),
                  subtitle: Text('Moyenne des quatre zones')),
              Align(alignment: Alignment.centerLeft, child: values(average)),
              const Divider(height: 28),
              ...List<Widget>.generate(4, (index) {
                final value = zones['ZONE_${index + 1}']!;
                return ListTile(
                    title: Text('Zone ${index + 1}'), subtitle: values(value));
              }),
            ]),
          )));
}

Future<void> _showInstallationDetails(
    BuildContext context,
    ElevageConfig config,
    ElevageInstallationDefinition definition,
    Map<String, int> currentEnvironment) async {
  final recipe = config.recipes
      .where((entry) => entry.installationId == definition.id)
      .firstOrNull;
  final after = <String, int>{
    'light': currentEnvironment['light']! + definition.light,
    'temperature': currentEnvironment['temperature']! + definition.temperature,
    'humidity': currentEnvironment['humidity']! + definition.humidity,
  };
  final recipeText = recipe == null
      ? 'Recette à définir'
      : <String>[
          if (recipe.organic > 0) '${recipe.organic} Organique',
          if (recipe.mineral > 0) '${recipe.mineral} Minéral',
          ...recipe.special.entries.map((entry) =>
              '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}'),
        ].join(' · ');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Icon(ElevagePresentation.installationIcon(definition.id)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(definition.label,
                        style: Theme.of(sheetContext).textTheme.titleLarge)),
              ]),
              const SizedBox(height: 12),
              Text(definition.description),
              const SizedBox(height: 16),
              Text('Fabrication',
                  style: Theme.of(sheetContext).textTheme.titleSmall),
              Text(recipeText),
              if (definition.outputs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('Produit',
                    style: Theme.of(sheetContext).textTheme.titleSmall),
                Text(definition.outputs.entries
                    .map((entry) => ElevagePresentation.itemLabel(entry.key))
                    .join(' · ')),
              ],
              const SizedBox(height: 16),
              if (definition.category == 'STRUCTURE') ...<Widget>[
                Text('Effets Alcôve',
                    style: Theme.of(sheetContext).textTheme.titleSmall),
                Text('☀️ Lumière : ${_signed(definition.light)}\n'
                    '🌡️ Température : ${_signed(definition.temperature)}\n'
                    '💧 Humidité : ${_signed(definition.humidity)}'),
                const SizedBox(height: 16),
                Text('Impact prévisionnel',
                    style: Theme.of(sheetContext).textTheme.titleSmall),
                Text(
                    'Avant  ☀️ ${ElevagePresentation.environmentScale(currentEnvironment['light']!)}/5 · '
                    '🌡️ ${ElevagePresentation.environmentScale(currentEnvironment['temperature']!)}/5 · '
                    '💧 ${ElevagePresentation.environmentScale(currentEnvironment['humidity']!)}/5\n'
                    'Après  ☀️ ${ElevagePresentation.environmentScale(after['light']!)}/5 · '
                    '🌡️ ${ElevagePresentation.environmentScale(after['temperature']!)}/5 · '
                    '💧 ${ElevagePresentation.environmentScale(after['humidity']!)}/5'),
              ] else ...<Widget>[
                Text('Effet de bien-être',
                    style: Theme.of(sheetContext).textTheme.titleSmall),
                Text(
                    '${_signed(definition.wellbeingImpact)} lors d’une interaction positive.'),
              ],
            ]),
      ),
    ),
  );
}

String _signed(int value) => value > 0 ? '+$value' : '$value';

Future<void> _openInventory(BuildContext context, ElevageController controller,
    Map individual, void Function(String item) onPlace) async {
  var filter = 'TOUT';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, setSheetState) {
        final state = controller.state!;
        final special = state.data['inventory']['special'] as Map;
        final generic = state.data['inventory']['generic'] as Map;
        final items = <String, int>{
          ...special.map((key, value) => MapEntry(key as String, value as int)),
          'ORGANIC': (generic['organic'] as num?)?.toInt() ?? 0,
          'MINERAL': (generic['mineral'] as num?)?.toInt() ?? 0,
        }..removeWhere((_, amount) => amount <= 0);
        final stacks = <_ElevageInventoryStack>[];
        for (final entry in items.entries) {
          for (final quantity in ElevagePresentation.stackQuantities(
              entry.value, controller.config.inventoryStackSize)) {
            stacks.add(_ElevageInventoryStack(entry.key, quantity));
          }
        }
        final visible = filter == 'TOUT'
            ? stacks
            : stacks
                .where((stack) =>
                    ElevagePresentation.itemCategory(stack.itemId) == filter)
                .toList();
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .72,
            builder: (_, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Inventaire'),
                    subtitle: Text(
                        '${state.data['inventory']['bioPiles']} Bio-piles')),
                Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
                  for (final choice in const <String>[
                    'TOUT',
                    'Nourriture',
                    'Matériaux',
                    'Ressources',
                    'Friandises'
                  ])
                    ChoiceChip(
                      label: Text(choice),
                      selected: filter == choice,
                      onSelected: (_) => setSheetState(() => filter = choice),
                    ),
                ]),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text(
                              'Votre inventaire est vide. Explorez la Mini-Lisière pour trouver des objets.'))),
                if (visible.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (_, index) {
                      final stack = visible[index];
                      final canPlace = ElevageDomain.foodItems
                              .contains(stack.itemId) ||
                          ElevageDomain.treatItems.contains(stack.itemId) ||
                          ElevageDomain.structuralItems.contains(stack.itemId);
                      void select() {
                        if (!canPlace) return;
                        Navigator.of(sheetContext).pop();
                        onPlace(stack.itemId);
                      }

                      return _ElevageInventorySlot(
                        stack: stack,
                        enabled: canPlace,
                        onTap: select,
                        onLongPress: select,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _ElevageInventoryStack {
  const _ElevageInventoryStack(this.itemId, this.quantity);
  final String itemId;
  final int quantity;
}

class _ElevageInventorySlot extends StatelessWidget {
  const _ElevageInventorySlot(
      {required this.stack,
      required this.enabled,
      required this.onTap,
      required this.onLongPress});
  final _ElevageInventoryStack stack;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: .32)),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Stack(children: <Widget>[
        Center(
            child: Icon(ElevagePresentation.itemIcon(stack.itemId),
                size: 36,
                color: enabled ? Theme.of(context).colorScheme.primary : null)),
        Positioned(
            top: 6,
            right: 7,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9)),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('×${stack.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w900))))),
        Positioned(
            left: 5,
            right: 5,
            bottom: 6,
            child: Text(ElevagePresentation.itemLabel(stack.itemId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800))),
      ]),
    );
    return LongPressDraggable<String>(
      data: stack.itemId,
      feedback: Material(
          color: Colors.transparent,
          child: Icon(ElevagePresentation.itemIcon(stack.itemId), size: 48)),
      onDragEnd: (_) => onLongPress(),
      child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(16), child: tile),
    );
  }
}

Future<void> _welcome(
    BuildContext context, ElevageController controller, String alcoveId) async {
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text('Accueillir un P’TIPOTE',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: () =>
                    _nameAdoption(sheetContext, controller, alcoveId, true),
                icon: const Icon(Icons.nfc_outlined),
                label: const Text('Scanner une figurine (simulation)')),
            TextButton(
                onPressed: () =>
                    _nameAdoption(sheetContext, controller, alcoveId, false),
                child: Text(
                    'Co-élevage · ${controller.config.coRearingDurationHours ~/ 24} jours')),
            if (controller.config.devMode) ...<Widget>[
              const Divider(),
              const Text('Natures de test',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (final profile in controller.config.natureProfiles)
                OutlinedButton(
                    onPressed: () => _nameAdoption(
                        sheetContext, controller, alcoveId, false,
                        family: profile.family, nature: profile.nature),
                    child: Text('Créer ${profile.label}')),
            ],
          ])));
}

Future<void> _nameAdoption(BuildContext context, ElevageController controller,
    String alcoveId, bool physical,
    {String family = 'MINERAL', String nature = 'RESONANCE'}) async {
  final profile = controller.config.natureProfile(family, nature);
  final name = TextEditingController();
  final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(physical
                  ? 'Figurine détectée · ${profile.label}'
                  : 'Les Sourciers confient un ${profile.label}'),
              content: TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 32,
                  decoration:
                      const InputDecoration(labelText: 'Nom du P’TIPOTE')),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirmer'))
              ]));
  if (accepted == true) {
    await controller.adopt(
        alcoveId: alcoveId,
        name: name.text,
        physical: physical,
        family: family,
        nature: nature,
        physicalFigureRef: physical
            ? 'mock:${profile.id.toLowerCase()}-${controller.now}'
            : null);
    if (context.mounted) Navigator.of(context).pop();
  }
  name.dispose();
}

Future<void> _moveOut(
    BuildContext context, ElevageController controller, String alcoveId) async {
  final refund = ElevageDomain.moveOutRefund(
      controller.state!, alcoveId, controller.config);
  final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: const Text('Déménager cette Alcôve ?'),
              content: Text(
                  'Vous récupérerez ${refund['organic']} Organique et ${refund['mineral']} Minéral. Les installations et leurs stocks seront perdus.'),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Déménager'))
              ]));
  if (accepted == true) await controller.moveOut(alcoveId);
}

Future<void> _placeInstallation(BuildContext context,
    ElevageController controller, String alcoveId, int slot) async {
  final instances = controller.state!.data['installationInventory'] as Map;
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListView(shrinkWrap: true, children: <Widget>[
            const ListTile(title: Text('Placer une installation')),
            if (instances.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    'Aucune installation en réserve. Fabriquez-en une au Bio-fabricateur.'),
              ),
            ...instances.entries.map((entry) => ListTile(
                title: Text(controller.config
                        .installation(
                            (entry.value as Map)['definitionId'] as String)
                        ?.label ??
                    'Inconnue'),
                onTap: () async {
                  await controller.place(alcoveId, slot, entry.key as String);
                  if (sheetContext.mounted && controller.error == null) {
                    Navigator.pop(sheetContext);
                  }
                  if (context.mounted && controller.error == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Installation posée dans l’Alcôve.')));
                  }
                }))
          ]));
}

Future<void> _openHabitatInventory(
    BuildContext context, ElevageController controller, String alcoveId) async {
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final inventory =
            controller.state!.data['habitatInventory'] as Map<String, dynamic>;
        return SafeArea(
            child: DraggableScrollableSheet(
                expand: false,
                builder: (_, scrollController) =>
                    ListView(controller: scrollController, children: <Widget>[
                      const ListTile(
                          leading: Icon(Icons.chair_outlined),
                          title: Text('Meubles et décorations')),
                      if (inventory.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                                'Aucun objet libre. Fabriquez un meuble ou une décoration.')),
                      ...inventory.entries.map((entry) {
                        final raw = entry.value as Map;
                        final definition = controller.config
                            .installation(raw['definitionId'] as String);
                        if (definition == null) return const SizedBox.shrink();
                        return ListTile(
                            leading: Icon(ElevagePresentation.installationIcon(
                                definition.id)),
                            title: Text(definition.label),
                            subtitle: Text(definition.category == 'MEUBLE'
                                ? 'Meuble · ${definition.description}'
                                : 'Décoration · ${definition.description}'),
                            trailing: Wrap(spacing: 2, children: <Widget>[
                              for (final zone in controller.config.sceneZones)
                                IconButton(
                                    tooltip: 'Placer dans ${zone.label}',
                                    icon: Text('Z${zone.id.split('_').last}'),
                                    onPressed: () async {
                                      await controller.placeHabitatItem(
                                          alcoveId, entry.key, zone.id);
                                      if (sheetContext.mounted &&
                                          controller.error == null) {
                                        Navigator.pop(sheetContext);
                                      }
                                    })
                            ]));
                      })
                    ])));
      });
}

Future<void> _openBiofabricator(
    BuildContext context, ElevageController controller, String alcoveId) async {
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final state = controller.state!;
        var category = 'STRUCTURE';
        return StatefulBuilder(
            builder: (context, setLocal) => DraggableScrollableSheet(
                expand: false,
                builder: (_, scrollController) =>
                    ListView(controller: scrollController, children: <Widget>[
                      const ListTile(title: Text('Bio-fabricateur')),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SegmentedButton<String>(
                              segments: const <ButtonSegment<String>>[
                                ButtonSegment(
                                    value: 'STRUCTURE',
                                    label: Text('Structures')),
                                ButtonSegment(
                                    value: 'MEUBLE', label: Text('Meubles')),
                                ButtonSegment(
                                    value: 'DECORATION',
                                    label: Text('Décorations')),
                              ],
                              selected: <String>{
                                category
                              },
                              onSelectionChanged: (value) =>
                                  setLocal(() => category = value.single))),
                      ...controller.config.recipes
                          .where((recipe) =>
                              controller.config
                                  .installation(recipe.installationId)
                                  ?.category ==
                              category)
                          .map((recipe) {
                        final known = ElevageDomain.recipeKnown(state, recipe);
                        final definition = controller.config
                            .installation(recipe.installationId);
                        final environment = ElevageDomain.environment(
                            state, alcoveId, controller.config);
                        return ListTile(
                            isThreeLine: known,
                            minLeadingWidth: 28,
                            leading: Icon(definition == null
                                ? Icons.help_outline
                                : ElevagePresentation.installationIcon(
                                    definition.id)),
                            title: Text(
                                known ? recipe.label : 'Recette inconnue',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            subtitle: known
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(<String>[
                                        if (recipe.organic > 0)
                                          '${recipe.organic} Organique',
                                        if (recipe.mineral > 0)
                                          '${recipe.mineral} Minéral',
                                        ...recipe.special.entries.map((entry) =>
                                            '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}'),
                                      ].join(' · ')),
                                      if (definition != null)
                                        Text(
                                            _installationImpactSentence(
                                                definition),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic)),
                                    ],
                                  )
                                : null,
                            onTap: !known || definition == null
                                ? null
                                : () => _showInstallationDetails(sheetContext,
                                    controller.config, definition, environment),
                            trailing: known
                                ? SizedBox(
                                    width: 100,
                                    child: FilledButton(
                                        onPressed: () async {
                                          await controller.craft(recipe);
                                          if (sheetContext.mounted &&
                                              controller.error == null) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        '${recipe.label} a été bio-fabriqué.')));
                                            Navigator.pop(sheetContext);
                                          }
                                        },
                                        child: const Text('Fabriquer')))
                                : null);
                      })
                    ])));
      });
}

String _installationImpactSentence(ElevageInstallationDefinition definition) {
  if (definition.category != 'STRUCTURE') {
    return 'Apporte ${_signed(definition.wellbeingImpact)} de bien-être lors d’une interaction positive.';
  }
  final parts = <String>[];
  if (definition.light != 0) {
    parts.add(definition.light > 0 ? 'éclaire' : 'assombrit');
  }
  if (definition.temperature != 0) {
    parts.add(definition.temperature > 0 ? 'réchauffe' : 'rafraîchit');
  }
  if (definition.humidity != 0) {
    parts.add(definition.humidity > 0 ? 'humidifie' : 'assèche');
  }
  if (parts.isEmpty) return 'Modifie doucement l’ambiance de la zone.';
  return '${parts.join(', ')} la zone.';
}

Future<void> _foraging(
    BuildContext context, ElevageController controller, String id) async {
  final status =
      ElevageDomain.foragingStatus(controller.state!, id, controller.now);
  if (status == 'NONE' || status == 'COMPLETED') {
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) =>
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const ListTile(title: Text('Choisir un biome')),
              ...<String, String>{
                'FOREST': 'Forêt',
                'COAST': 'Littoral',
                'HILL': 'Colline'
              }.entries.map((entry) => ListTile(
                  title: Text(entry.value),
                  onTap: () async {
                    await controller.startForaging(id, entry.key);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  }))
            ]));
    return;
  }
  final run = (controller.state!.data['runsByIndividualId'] as Map)[id] as Map;
  if (status == 'IN_PROGRESS') {
    final remaining = max(0, (run['readyAt'] as int) - controller.now);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Exploration en cours · ${(remaining / 1000).ceil()} s')));
    }
    return;
  }
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListView(shrinkWrap: true, children: <Widget>[
            const ListTile(title: Text('Choisir une piste')),
            ...(run['points'] as List).cast<Map>().map((point) => ListTile(
                title: Text(point['label'] as String),
                onTap: () async {
                  final reward = point['reward'] as Map;
                  await controller.claimForaging(id, point['id'] as String);
                  if (sheetContext.mounted && controller.error == null) {
                    Navigator.pop(sheetContext);
                  }
                  if (context.mounted && controller.error == null) {
                    await _showForagingResult(context, reward);
                  }
                }))
          ]));
}

Future<void> _showForagingResult(BuildContext context, Map reward) async {
  final generic = reward['generic'] as Map;
  final rows = <String>[
    ...generic.entries.where((entry) => entry.value != 0).map((entry) =>
        '+${entry.value} ${ElevagePresentation.itemLabel((entry.key as String).toUpperCase())}'),
    '+1 ${ElevagePresentation.itemLabel(reward['special'] as String)}',
  ];
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: const Text('Exploration terminée'),
              content:
                  Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Text('Tu as trouvé :'),
                const SizedBox(height: 8),
                ...rows.map((row) => ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(row))),
              ]),
              actions: <Widget>[
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Retour à l’Alcôve'))
              ]));
}

Future<void> _sourcier(
  BuildContext context,
  ElevageController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final state = controller.state!;
      final piles = state.data['inventory']['bioPiles'];
      return ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            title: const Text('Sourcier'),
            subtitle: Text('$piles Bio-piles'),
          ),
          ListTile(
            title: Text(
                'Fruit fibreux · ${controller.config.fibrousFruitPrice} Bio-piles'),
            onTap: () async {
              await controller.buyTreat('FIBROUS_FRUIT');
              if (sheetContext.mounted && controller.error == null) {
                Navigator.pop(sheetContext);
              }
              if (context.mounted && controller.error == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Achat effectué.')));
              }
            },
          ),
          ListTile(
            title: Text(
                'Jelly fruité · ${controller.config.fruitJellyPrice} Bio-piles'),
            onTap: () async {
              await controller.buyTreat('FRUIT_JELLY');
              if (sheetContext.mounted && controller.error == null) {
                Navigator.pop(sheetContext);
              }
              if (context.mounted && controller.error == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Achat effectué.')));
              }
            },
          ),
          const Divider(),
          ListTile(
            title: Text(
                'Échanger ${controller.config.buybackQuantity} Organique → ${controller.config.buybackBioPiles} Bio-pile'),
            onTap: () async {
              await controller.sellGeneric('ORGANIC');
              if (context.mounted && controller.error == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Échange effectué.')));
              }
            },
          ),
          ListTile(
            title: Text(
                'Échanger ${controller.config.buybackQuantity} Minéral → ${controller.config.buybackBioPiles} Bio-pile'),
            onTap: () async {
              await controller.sellGeneric('MINERAL');
              if (context.mounted && controller.error == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Échange effectué.')));
              }
            },
          ),
        ],
      );
    },
  );
}

Future<void> _metamorphosis(
    BuildContext context, ElevageController controller, String id) async {
  var stage = 0;
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
                  title: const Text('Métamorphose Résonance'),
                  content:
                      Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    const Icon(Icons.diamond_outlined, size: 64),
                    Text('Motif ${stage + 1}/3'),
                    const Text('Le cristal pulse : TAM · TAM · … · TAM'),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () async {
                          if (stage == 2) {
                            await controller.metamorphose(id);
                            if (context.mounted) Navigator.pop(context);
                          } else {
                            setLocal(() => stage++);
                          }
                        },
                        child: const Text('Reproduire le motif'))
                  ]),
                  actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Plus tard'))
                  ])));
}

Future<int?> _numberDialog(
    BuildContext context, String label, int value) async {
  final text = TextEditingController(text: '$value');
  final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(label),
              content: TextField(
                  controller: text,
                  keyboardType: TextInputType.number,
                  autofocus: true),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, int.tryParse(text.text)),
                    child: const Text('Valider'))
              ]));
  text.dispose();
  return result;
}

const Map<String, String> _vocalizationLabels = <String, String>{
  'CURIOSITY': 'Curiosité',
  'ABSORB': 'Effort / absorption',
  'CONTENT': 'Contentement',
  'DISCOMFORT': 'Inconfort',
  'SURPRISE': 'Surprise',
  'REJECT': 'Refus',
  'CALL': 'Appel',
};

Future<String?> _textDialog(
    BuildContext context, String label, String value) async {
  final text = TextEditingController(text: value);
  final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(label),
              content: TextField(
                controller: text,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Onomatopée', hintText: 'Ex. Prr !'),
              ),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, text.text),
                    child: const Text('Valider')),
              ]));
  text.dispose();
  return result;
}
