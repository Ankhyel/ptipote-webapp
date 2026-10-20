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
    final trust = ElevageDomain.trust(state);
    final criticalNames = (state.data['individuals'] as Map)
        .values
        .whereType<Map>()
        .where((individual) =>
            (((individual['wellbeing'] as Map?)?['value'] as num?)?.toInt() ??
                60) <
            controller.config.criticalWellbeingThreshold)
        .map((individual) => individual['name'] as String? ?? 'P’TIPOTE')
        .toList(growable: false);
    final nextTrustThreshold = controller.config.alcoveRequirements
        .map((entry) => (entry['requiredContribution'] as num?)?.toInt() ?? 0)
        .where((threshold) => threshold > trust)
        .fold<int?>(
            null,
            (current, threshold) =>
                current == null || threshold < current ? threshold : current);
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.volunteer_activism_outlined),
                  title: const Text('Confiance'),
                  subtitle: Text(nextTrustThreshold == null
                      ? 'Confiance cumulée du Refuge · elle ne se dépense pas.'
                      : 'Confiance cumulée · prochain palier : $nextTrustThreshold'),
                  trailing: Text('$trust'),
                  onTap: () => _showTrustHistory(context, state),
                ),
              ),
              if (criticalNames.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: const Text('Bien-être critique'),
                    subtitle: Text(
                        '${criticalNames.join(', ')} · risque : -${controller.config.criticalWellbeingTrustPenalty} Confiance / ${controller.config.criticalWellbeingPenaltyHours} h'),
                  ),
                ),
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
                          '${controller.notifications.first['name']} a été récupéré. Les Sourciers vous remercient pour votre confiance et le P’TIPOTE était en pleine forme.',
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
                    progressState: ElevageDomain.alcoveProgressState(
                        state,
                        alcove['id'] as String,
                        controller.config,
                        controller.now),
                    requirement:
                        controller.config.requirementForAlcove(index + 1),
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
                    onBuild: (route) => controller.startAlcoveConstruction(
                        alcove['id'] as String, route),
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
    required this.progressState,
    required this.requirement,
    required this.onOpen,
    this.onMoveOut,
    required this.onBuild,
  });

  final int index;
  final int now;
  final bool occupied;
  final Map? individual;
  final String progressState;
  final Map<String, dynamic> requirement;
  final VoidCallback onOpen;
  final VoidCallback? onMoveOut;
  final Future<void> Function(String route) onBuild;

  @override
  Widget build(BuildContext context) {
    final locked = progressState != 'READY';
    final name = locked
        ? 'Verrouillée'
        : occupied
            ? individual!['name'] as String
            : 'Libre';
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
                locked
                    ? switch (progressState) {
                        'UNDER_CONSTRUCTION' => 'Chantier en cours.',
                        'AVAILABLE_TO_BUILD' => 'Prête à être construite.',
                        _ =>
                          'Confiance requise : ${requirement['requiredContribution'] ?? '—'}',
                      }
                    : occupied
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
                onPressed: locked
                    ? progressState == 'AVAILABLE_TO_BUILD'
                        ? () => showModalBottomSheet<void>(
                              context: context,
                              builder: (sheet) => SafeArea(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                    const ListTile(
                                        title: Text('Construire cette Alcôve')),
                                    ListTile(
                                        title: const Text('Alcôve clé en main'),
                                        subtitle: Text(
                                            '${requirement['turnkeyBiopileCost']} Bio-piles'),
                                        onTap: () async {
                                          await onBuild('TURNKEY');
                                          if (sheet.mounted) {
                                            Navigator.pop(sheet);
                                          }
                                        }),
                                    ListTile(
                                        title: const Text('Chantier assisté'),
                                        subtitle: Text(
                                            '${requirement['assistedBiopileCost']} Bio-piles + matériaux'),
                                        onTap: () async {
                                          await onBuild('ASSISTED');
                                          if (sheet.mounted) {
                                            Navigator.pop(sheet);
                                          }
                                        }),
                                  ])),
                            )
                        : null
                    : onOpen,
                child: Text(locked
                    ? (progressState == 'AVAILABLE_TO_BUILD'
                        ? 'Construire'
                        : 'Indisponible')
                    : occupied
                        ? 'Ouvrir l’Alcôve'
                        : 'Accueillir un P’TIPOTE'),
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
  Timer? _behaviorWatchdog;
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
  int _actionStartedAt = 0;
  int _lastZoneEnteredAt = 0;

  @override
  void initState() {
    super.initState();
    _autonomousTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      widget.controller.refreshRequest(widget.individualId);
      widget.controller.refreshExploration();
      final state = widget.controller.state;
      final individual = state == null
          ? null
          : (state.data['individuals'] as Map)[widget.individualId] as Map?;
      if (individual != null) {
        widget.controller.refreshAlcove(individual['alcoveId'] as String);
      }
      _enqueueSceneEvent(const _SceneEvent.autonomous());
    });
    _behaviorWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_autonomousInFlight || _actionStartedAt == 0) return;
      if (widget.controller.now - _actionStartedAt >
          const Duration(seconds: 20).inMilliseconds) {
        _recoverBehavior();
      }
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
      if (now - _lastZoneEnteredAt <
          const Duration(seconds: 3).inMilliseconds) {
        return;
      }
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
        _lastZoneEnteredAt = now;
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
    _behaviorWatchdog?.cancel();
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
      _actionStartedAt = widget.controller.now;
      if (zoneId != null) {
        _ptipoteZoneId = zoneId;
        _lastZoneEnteredAt = widget.controller.now;
      }
    });
  }

  void _softResetBehavior() {
    _actionQueue.clear();
    _actionRemainingMs = 0;
    _autonomousInFlight = false;
    _lastAutonomousBehavior = null;
    _bubbleTimer?.cancel();
    _feedbackTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _sceneAction = 'IDLE';
      _sceneVoice = null;
      _bubbleItemId = null;
      _reaction = null;
      _feedback = null;
      _actionStartedAt = 0;
    });
  }

  void _recoverBehavior() {
    _softResetBehavior();
    if (mounted) {
      _enqueueSceneEvent(const _SceneEvent.autonomous(direct: true));
    }
  }

  Future<void> _refreshAlcoveWithBehaviorReset(String alcoveId) async {
    _softResetBehavior();
    await widget.controller.refreshAlcove(alcoveId);
    if (mounted) {
      _enqueueSceneEvent(const _SceneEvent.autonomous(direct: true));
    }
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
    // Build the bubble from the state *after* this occurrence. The fifth
    // exposure can therefore be the first one to say its learned word rather
    // than waiting for a sixth, while the asynchronous persistence below is
    // still the single durable mutation.
    final preview = ElevageDomain.recordCommunication(
        widget.controller.state!, widget.individualId, category,
        conceptId: itemId ?? category);
    final previewIndividual =
        (preview.data['individuals'] as Map)[widget.individualId] as Map;
    final expression = ElevageDomain.communicationExpression(
        previewIndividual, category, widget.controller.config,
        precise: itemId == null ? null : ElevagePresentation.itemLabel(itemId),
        conceptId: itemId ?? category);
    _bubbleTimer?.cancel();
    setState(() {
      _sceneVoice = expression['word'] ?? expression['vocal'];
      _bubbleItemId = action == 'STRUCTURAL_ABSORB' ||
              action == 'EAT' ||
              action == 'FLEE_WITH_ITEM'
          ? itemId
          : null;
    });
    widget.controller.recordCommunication(widget.individualId, category,
        conceptId: itemId ?? category);
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

  void _showIntentExpression(String intent, Map individual) {
    final stage =
        (individual['lifecycle'] as Map?)?['stage'] as String? ?? 'BABY';
    final text = stage == 'BABY'
        ? widget.controller.config.vocalizations['CALL'] ?? 'Pti…'
        : widget.controller.config.communicationText(
            intent,
            stage == 'MATURE' ? 'MATURE' : 'JUVENILE',
            stage == 'MATURE' ? 'Je vais me reposer.' : 'repos');
    _bubbleTimer?.cancel();
    setState(() {
      _sceneVoice = '$text 💤';
      _bubbleItemId = null;
    });
    _bubbleTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _sceneVoice = null);
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
        final dayNap = ElevageDomain.nextDayNapFurniture(
            state, widget.individualId, alcoveId, now, config,
            phaseOverride: widget.controller.forcedDayNightPhase);
        if (dayNap != null) {
          await _executeDayNap(dayNap, individual);
        } else {
          final furniture = ElevageDomain.nextFurnitureActivity(
              state, widget.individualId, alcoveId, now, config);
          if (furniture != null) {
            await _executeFurnitureActivity(furniture, individual);
          }
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
        // A Juvénile first has a readable "idea" moment, then transports the
        // interesting object to a zone that suits it. BABY never reaches this
        // branch because the domain denies it scene-item carrying.
        setState(() => _sceneVoice = '!');
        await _waitSceneAction(350);
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
        final safeZone = decision.outcome.targetZoneId;
        if (safeZone != null) {
          await widget.controller
              .relocateSceneItem(alcoveId, decision.instanceId, safeZone);
        }
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
      // A failed interaction (removed target, blocked relocation, etc.) must
      // never strand the visual FSM on PICKUP/THINK/DISCOMFORT.
      if (mounted &&
          _sceneAction != 'SLEEP' &&
          _sceneAction != 'METAMORPHOSIS') {
        _setSceneAction('IDLE');
      }
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
    _showSceneExpression('DISCOMFORT', individual);
    // A normal bad zone is deliberately visible before the next move. Extreme
    // danger still escapes immediately, preserving the emergency exception.
    if (comfort == 'BAD') {
      await _waitSceneAction(const Duration(seconds: 3).inMilliseconds);
    }
    await _waitSceneAction(config.objectReactionDelayMs);
    final target = ElevageDomain.exploratoryZoneTarget(
      current,
      alcoveId,
      _ptipoteZoneId,
      individual,
      config,
      now,
      phaseOverride: widget.controller.forcedDayNightPhase,
    );
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
      if (mounted &&
          _sceneAction != 'SLEEP' &&
          _sceneAction != 'METAMORPHOSIS') {
        _setSceneAction('IDLE');
      }
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
      if (mounted &&
          _sceneAction != 'SLEEP' &&
          _sceneAction != 'METAMORPHOSIS') {
        _setSceneAction('IDLE');
      }
    }
  }

  Future<void> _executeDayNap(Map furniture, Map individual) async {
    _autonomousInFlight = true;
    try {
      final zoneId = furniture['zoneId'] as String;
      _setSceneAction('APPROACH_ITEM', zoneId: zoneId);
      await _waitSceneAction(ElevageDomain.normalMoveDurationFor(
          individual, widget.controller.config));
      _setSceneAction('REST');
      await widget.controller.useFurniture(widget.individualId,
          individual['alcoveId'] as String, furniture['instanceId'] as String);
      await widget.controller.startDayNap(widget.individualId, zoneId);
      if (!mounted || widget.controller.error != null) return;
      final updated = (widget.controller.state!.data['individuals']
          as Map)[widget.individualId] as Map;
      _setSceneAction('SLEEP', zoneId: zoneId);
      _showIntentExpression('REST_REQUEST', updated);
    } finally {
      _autonomousInFlight = false;
      if (mounted && _sceneAction != 'SLEEP') _setSceneAction('IDLE');
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
    final action = _sceneActionForOutcome(
        outcome.behavior, item['itemId'] as String,
        isStructural: outcome.consumed &&
            !ElevageDomain.canEat(individual, item['itemId'] as String,
                widget.controller.config));
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
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final alcove = (state.data['alcoves'] as List)
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
                          localEnvironment,
                          instance: raw)),
                if (definition != null &&
                    widget.controller.config
                            .modulesFor(definition.id)
                            .moduleSlots >
                        0)
                  ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('Modules'),
                      subtitle: Text(_moduleSlotSummary(raw, definition.id)),
                      onTap: () async {
                        await _openModulePicker(
                            sheetContext, alcoveId, slot, raw, definition.id);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      }),
                if ((definition?.resonanceMaterial != null ||
                        definition?.resonanceFamily != null) &&
                    ElevageDomain.canResonate(
                        individual, widget.controller.config))
                  ListTile(
                      leading: const Icon(Icons.diamond_outlined),
                      title: const Text('Entrer en résonance'),
                      subtitle: Text(definition!.resonanceMaterial == null
                          ? 'Renforce lentement la structure sans consommer la structure biologique.'
                          : 'Renforce lentement la structure via ${ElevagePresentation.itemLabel(definition.resonanceMaterial!)} sans consommer la Formation.'),
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
                                    '${ElevagePresentation.itemLabel(entry.key as String)} : ${entry.value}/${ElevageDomain.effectiveProducerOutputs(raw, definition!.id, widget.controller.config).where((output) => output.resourceId == entry.key).map((output) => output.maxLocalStock).firstOrNull ?? widget.controller.config.productionMaxStock}'),
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

  String _moduleSlotSummary(Map raw, String definitionId) {
    final profile = widget.controller.config.modulesFor(definitionId);
    final installed =
        ElevageDomain.installedModules(raw, widget.controller.config);
    final labels = installed
        .map((entry) =>
            (entry['definition'] as ElevageModuleDefinition?)?.label ??
            'Module')
        .join(' · ');
    return labels.isEmpty
        ? '${installed.length}/${profile.moduleSlots} · slot libre'
        : '${installed.length}/${profile.moduleSlots} · $labels';
  }

  Future<void> _openModulePicker(BuildContext context, String alcoveId,
      int slot, Map raw, String definitionId) async {
    final controller = widget.controller;
    final profile = controller.config.modulesFor(definitionId);
    final installed = ElevageDomain.installedModules(raw, controller.config);
    final inventory = controller.state!.data['moduleInventory'] as Map;
    final available = inventory.values.whereType<Map>().where((entry) {
      final module =
          controller.config.module(entry['moduleId'] as String? ?? '');
      return module != null &&
          module.enabled &&
          profile.allowedModuleIds.contains(module.id) &&
          module.compatibleStructures.contains(definitionId);
    }).toList(growable: false);
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
              child: ListView(shrinkWrap: true, children: <Widget>[
                ListTile(
                    title: const Text('Modules installés'),
                    subtitle:
                        Text('${installed.length}/${profile.moduleSlots}')),
                ...installed.map((entry) {
                  final definition =
                      entry['definition'] as ElevageModuleDefinition?;
                  return ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: Text(definition?.label ?? 'Module'),
                      subtitle: Text(definition?.description ?? ''),
                      trailing: const Icon(Icons.remove_circle_outline),
                      onTap: () async {
                        await controller.removeModule(
                            alcoveId, slot, entry['instanceId'] as String);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      });
                }),
                if (installed.length < profile.moduleSlots) ...<Widget>[
                  const Divider(),
                  const ListTile(title: Text('Installer un module')),
                  if (available.isEmpty)
                    const ListTile(
                        subtitle: Text('Aucun module compatible en Réserve.')),
                  ...available.map((entry) {
                    final definition = controller.config
                        .module(entry['moduleId'] as String? ?? '');
                    return ListTile(
                        leading: const Icon(Icons.add_circle_outline),
                        title: Text(definition!.label),
                        subtitle: Text(definition.description),
                        onTap: () async {
                          await controller.installModule(
                              alcoveId, slot, entry['instanceId'] as String);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        });
                  }),
                ],
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
    final rawLocalEnvironment =
        zoneEnvironments[_ptipoteZoneId] ?? const <String, int>{};
    final localEnvironment = ElevageDomain.environmentExperiencedByPtipote(
        state,
        widget.individualId,
        _ptipoteZoneId,
        rawLocalEnvironment,
        controller.config);
    final ambient = ElevageDomain.ambientEnvironmentalFeedback(
        localEnvironment, individual, controller.config);
    final environmentalNeed = ElevageDomain.expressedEnvironmentalNeed(
        localEnvironment, individual, controller.config);
    final needCooldown = ElevageDomain.environmentalNeedCooldownSeconds(
        individual, controller.config);
    final needsEnabled =
        ((controller.config.refugeProgression['ambientFeedback']
                as Map?)?['needPictogramEnabled'] as bool?) ??
            true;
    final needText = needsEnabled &&
            environmentalNeed != null &&
            (now ~/ 1000) % max(1, needCooldown) == 0
        ? ElevageDomain.environmentalNeedExpression(
            individual, environmentalNeed['need']!, controller.config)
        : null;
    final ambientVoice = ambient == null ||
            (now ~/ 1000) %
                    max(1, controller.config.babyVocalCooldownSeconds) !=
                0
        ? null
        : ambient['vocalization'];
    final alcoveComfort =
        _alcoveComfort(zoneEnvironments, controller.config, individual);
    final hunger = ElevageDomain.hunger(
        state, widget.individualId, now, controller.config);
    final satiety = ElevageDomain.satietyPercent(
        state, widget.individualId, now, controller.config);
    final hungerExpression = ElevageDomain.hungerExpression(
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
    final explorationRun =
        (state.data['exploration'] as Map?)?['activeRun'] as Map?;
    final exploration = ElevageDomain.explorationState(state);
    final playerEndurance = (exploration['stamina'] as num?)?.toInt() ?? 0;
    final explorationRemaining = explorationRun?['status'] == 'IN_PROGRESS'
        ? max(0, (explorationRun?['endsAt'] as num? ?? now).toInt() - now)
        : 0;
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
                onSceneItemDrop: (itemId, zoneId) {
                  if (!ElevageDomain.placeableSceneItems.contains(itemId)) {
                    return;
                  }
                  setState(() => _pendingPlacementItem = itemId);
                  _placeInZone(zoneId);
                },
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
                voice:
                    _sceneVoice ?? ambientVoice ?? hungerExpression?['voice'],
                bubbleItemId: _bubbleItemId,
                ptipoteHoldActive: _ptipoteHoldActive,
                requestSignal:
                    hungerExpression?['icon'] ?? request?['signal'] as String?,
                ambientSignal: ambient,
                expressedNeed: needText,
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
            _section(context, 'Météo et Eau', <Widget>[
              ListTile(
                leading: Text(
                    _weatherEmoji(
                        ElevageDomain.weatherTypeAt(now, controller.config)),
                    style: const TextStyle(fontSize: 24)),
                title: Text(_weatherLabel(
                    ElevageDomain.weatherTypeAt(now, controller.config))),
                subtitle: const Text(
                    'La météo modifie la lumière et la température locales.'),
                trailing: Text(
                    '💧 ${ElevageDomain.waterTank(state).toStringAsFixed(1)}/${controller.config.waterTankCapacity}'),
              ),
            ]),
            _section(context, 'Cuisine', <Widget>[
              ListTile(
                leading: const Icon(Icons.soup_kitchen_outlined),
                title: const Text('Préparation libre'),
                subtitle: const Text('3 ingrédients · Eau optionnelle'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCooking(context, controller, individual),
              ),
            ]),
            _section(context, 'État', <Widget>[
              ListTile(
                  leading: const Icon(Icons.restaurant_outlined),
                  title: Text(_hungerLabel(hunger)),
                  subtitle: const Text(
                      'La faim est lente et ne comporte aucune punition irréversible.')),
              if (controller.config.devMode)
                ListTile(
                    leading: const Text('🍴', style: TextStyle(fontSize: 22)),
                    title: const Text('Debug · Satiété'),
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
              _EnergySlotCard(alcove: alcove, controller: controller),
              _TrackerCard(individual: individual, controller: controller),
              if (individual['loanOffer'] is Map &&
                  (individual['loanOffer'] as Map)['selectedStructureId'] ==
                      null)
                _LoanOfferCard(
                    controller: controller,
                    individualId: widget.individualId,
                    offer: individual['loanOffer'] as Map),
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
                      _refreshAlcoveWithBehaviorReset(alcove['id'] as String),
                  child: const Text('Actualiser l’Alcôve')),
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
                  onPressed: () => _exploration(context, controller),
                  icon: const Icon(Icons.forest_outlined),
                  label: Text(explorationRun?['status'] == 'IN_PROGRESS'
                      ? 'Exploration · ⏱ ${_explorationTimer(explorationRemaining)}'
                      : explorationRun?['status'] == 'READY'
                          ? 'Exploration · terminée'
                          : 'Exploration')),
              _ExplorationEnduranceBar(
                  current: playerEndurance,
                  maximum: controller.config.explorationInt('playerStaminaMax',
                      controller.config.explorationInt('staminaMax', 10)),
                  label: 'Endurance d’exploration',
                  regenMinutes: controller.config
                      .explorationInt('playerStaminaRegenMinutes', 5)),
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
    final knowledge = ElevageDomain.knowledgeEntries(individual);
    final hypotheses = knowledge
        .where((item) => item['status'] == 'HYPOTHESIS')
        .toList(growable: false);
    final discoveries = knowledge
        .where((item) => item['status'] == 'CONFIRMED')
        .toList(growable: false);
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
                        title: Text(ElevagePresentation.knowledgeHypothesisText(
                            item, name)),
                        subtitle: Text(
                            '${item['hypothesisEvidence'] ?? 0} preuve(s) recueillie(s)')))
                    .toList()),
        _notebookSection(
            context,
            'Découvertes confirmées',
            discoveries.isEmpty
                ? const <Widget>[Text('Aucune découverte confirmée.')]
                : discoveries
                    .map((item) => ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(ElevagePresentation.knowledgeConfirmedText(
                            item, name))))
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

  void _setRefugeNumber(String key, int value) {
    final next = Map<String, dynamic>.from(config.refugeProgression)
      ..[key] = value;
    setState(() => config = config.copyWith(refugeProgression: next));
  }

  void _setRefugeNestedNumber(String section, String key, int value) {
    final next = Map<String, dynamic>.from(config.refugeProgression);
    final nested = Map<String, dynamic>.from(
        next[section] as Map? ?? const <dynamic, dynamic>{});
    nested[key] = value;
    next[section] = nested;
    setState(() => config = config.copyWith(refugeProgression: next));
  }

  void _setRefugeNestedBool(String section, String key, bool value) {
    final next = Map<String, dynamic>.from(config.refugeProgression);
    final nested = Map<String, dynamic>.from(
        next[section] as Map? ?? const <dynamic, dynamic>{});
    nested[key] = value;
    next[section] = nested;
    setState(() => config = config.copyWith(refugeProgression: next));
  }

  void _setExplorationSectorValue(String sectorId, String key, dynamic value) {
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final exploration = Map<String, dynamic>.from(
        progression['exploration'] as Map? ?? const <dynamic, dynamic>{});
    final overrides = Map<String, dynamic>.from(
        exploration['sectorOverrides'] as Map? ?? const <dynamic, dynamic>{});
    final sector = Map<String, dynamic>.from(
        overrides[sectorId] as Map? ?? const <dynamic, dynamic>{});
    sector[key] = value;
    overrides[sectorId] = sector;
    exploration['sectorOverrides'] = overrides;
    progression['exploration'] = exploration;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  void _setExplorationLootValue(
      String sectorId, List<Map<String, dynamic>> table) {
    _setExplorationSectorValue(sectorId, 'lootTable', table);
  }

  void _setAlcoveRequirement(int alcoveIndex, String key, int value) {
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final requirements = config.alcoveRequirements
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (alcoveIndex - 2 < 0 || alcoveIndex - 2 >= requirements.length) return;
    requirements[alcoveIndex - 2][key] = value;
    progression['alcoveRequirements'] = requirements;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  void _setAssistedCost(int alcoveIndex, String resourceId, int value) {
    final requirement = config.requirementForAlcove(alcoveIndex);
    final costs = Map<String, dynamic>.from(
        requirement['assistedResourceCosts'] as Map? ??
            const <dynamic, dynamic>{});
    costs[resourceId] = value;
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final requirements = config.alcoveRequirements
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    requirements[alcoveIndex - 2]['assistedResourceCosts'] = costs;
    progression['alcoveRequirements'] = requirements;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  void _setBiogeneratorRecipe(String key, int value) {
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final recipe = Map<String, dynamic>.from(
        progression['biogeneratorRecipe'] as Map? ??
            const <dynamic, dynamic>{});
    if (key == 'organic' || key == 'mineral') {
      recipe[key] = value;
    } else {
      final special = Map<String, dynamic>.from(
          recipe['special'] as Map? ?? const <dynamic, dynamic>{});
      special[key] = value;
      recipe['special'] = special;
    }
    progression['biogeneratorRecipe'] = recipe;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  int _biogeneratorRecipeCost(String key) {
    final recipe = config.refugeProgression['biogeneratorRecipe'] as Map?;
    if (key == 'organic' || key == 'mineral') {
      return (recipe?[key] as num?)?.toInt() ?? 0;
    }
    return ((recipe?['special'] as Map?)?[key] as num?)?.toInt() ?? 0;
  }

  int _typeLootBiasPercent(String family) {
    final multipliers =
        (config.explorationConfig['typeLootBiasMultipliers'] as Map?);
    return (((multipliers?[family] as num?)?.toDouble() ?? 1.5) * 100).round();
  }

  void _setTypeLootBiasPercent(String family, int percent) {
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final exploration = Map<String, dynamic>.from(
        progression['exploration'] as Map? ?? const <dynamic, dynamic>{});
    final multipliers = Map<String, dynamic>.from(
        exploration['typeLootBiasMultipliers'] as Map? ??
            const <dynamic, dynamic>{});
    multipliers[family] = percent.clamp(100, 1000) / 100;
    exploration['typeLootBiasMultipliers'] = multipliers;
    progression['exploration'] = exploration;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  void _setSatietyNumber(String key, int value) =>
      _setRefugeNestedNumber('satiety', key, value);

  int _satietyNumber(String key, int fallback) =>
      ((config.satietyConfig[key] as num?)?.toInt() ?? fallback)
          .clamp(0, 999999);

  void _setFoodSatietyValue(String itemId, int value) {
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final satiety = Map<String, dynamic>.from(
        progression['satiety'] as Map? ?? const <dynamic, dynamic>{});
    final values = Map<String, dynamic>.from(
        satiety['foodSatietyValues'] as Map? ?? const <dynamic, dynamic>{});
    values[itemId] = value.clamp(0, 100);
    satiety['foodSatietyValues'] = values;
    progression['satiety'] = satiety;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  Widget _trackerDevTools(BuildContext context) {
    final state = widget.controller.state;
    final individuals = state?.data['individuals'] as Map?;
    final activeIds = state?.data['activeIndividualIds'] as List? ?? const [];
    final active = activeIds
        .whereType<String>()
        .map((id) => individuals?[id])
        .whereType<Map>()
        .toList(growable: false);
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Outils dev Pisteur'),
      const Text('Disponibles uniquement en mode dev.'),
      ...active.map((individual) {
        final id = individual['id'] as String;
        final tracker = ElevageDomain.trackerProfession(
            individual, widget.controller.config);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${individual['name']} · ${tracker['xp']} XP'),
          subtitle: const Text('Tests XP et niveau, hors interface joueur.'),
          trailing: Wrap(spacing: 4, children: [
            TextButton(
                onPressed: () => widget.controller.addTrackerXp(id, 10),
                child: const Text('+10')),
            PopupMenuButton<int>(
              tooltip: 'Définir XP',
              onSelected: (xp) => widget.controller.setTrackerXp(id, xp),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('XP = 0')),
                PopupMenuItem(value: 100, child: Text('XP = 100')),
                PopupMenuItem(value: 200, child: Text('XP = 200')),
                PopupMenuItem(value: 300, child: Text('XP = 300')),
              ],
              child:
                  const Padding(padding: EdgeInsets.all(8), child: Text('XP')),
            ),
            PopupMenuButton<int>(
              tooltip: 'Forcer niveau',
              onSelected: (level) =>
                  widget.controller.forceTrackerLevel(id, level),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Niveau 0')),
                PopupMenuItem(value: 1, child: Text('Niveau 1')),
                PopupMenuItem(value: 2, child: Text('Niveau 2')),
                PopupMenuItem(value: 3, child: Text('Niveau 3')),
              ],
              child: const Padding(
                  padding: EdgeInsets.all(8), child: Text('Niv.')),
            ),
          ]),
        );
      }),
    ]);
  }

  Widget _satietyDevTools(BuildContext context) {
    final state = widget.controller.state;
    final individuals = state?.data['individuals'] as Map?;
    final activeIds = state?.data['activeIndividualIds'] as List? ?? const [];
    final active = activeIds
        .whereType<String>()
        .map((id) => individuals?[id])
        .whereType<Map>()
        .toList(growable: false);
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Outils dev Satiété'),
      ...active.map((individual) {
        final id = individual['id'] as String;
        final value = ElevageDomain.satietyPercent(
            state!, id, widget.controller.now, widget.controller.config);
        final hunger = ElevageDomain.hunger(
            state, id, widget.controller.now, widget.controller.config);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
              '${individual['name']} · $value/100 · ${_hungerLabel(hunger)}'),
          subtitle: Text(
              '${widget.controller.config.satietyLossPerHour((individual['lifecycle'] as Map)['stage'] as String)}/h · calculée depuis le timestamp'),
          trailing: Wrap(spacing: 4, children: [
            TextButton(
                onPressed: () => widget.controller.addSatiety(id, 10),
                child: const Text('+10')),
            TextButton(
                onPressed: () =>
                    widget.controller.simulateSatietyElapsedHours(id, 1),
                child: const Text('+1 h')),
            PopupMenuButton<int>(
              tooltip: 'Définir satiété',
              onSelected: (value) => widget.controller.setSatiety(id, value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Satiété = 0')),
                PopupMenuItem(value: 50, child: Text('Satiété = 50')),
                PopupMenuItem(value: 70, child: Text('Satiété = 70')),
                PopupMenuItem(value: 100, child: Text('Satiété = 100')),
              ],
              child: const Padding(
                  padding: EdgeInsets.all(8), child: Text('Régler')),
            ),
          ]),
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dashboard Élevage')),
        body: ListView(
            padding: const EdgeInsets.all(16),
            children: _accordionize(<Widget>[
              _heading('Preset et activation'),
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
              _heading('Refuge, Alcôves et Bio-piles'),
              _number(
                  context,
                  'Alcôves actives au départ',
                  config.startingAlcoveCount,
                  (value) => _setRefugeNumber('startingAlcoveCount', value)),
              _number(context, 'Choix de prêt juvénile', config.loanChoiceCount,
                  (value) => _setRefugeNumber('loanChoiceCount', value)),
              _number(
                  context,
                  'Restitution prêt (jours)',
                  config.loanReturnDelayDays,
                  (value) => _setRefugeNumber('loanReturnDelayDays', value)),
              _number(
                  context,
                  'Bio-piles de départ',
                  config.startingBioBatteryCount,
                  (value) =>
                      _setRefugeNumber('startingBioBatteryCount', value)),
              _number(context, 'Énergie par Bio-pile', config.bioBatteryEnergy,
                  (value) => _setRefugeNumber('bioBatteryEnergy', value)),
              _heading('Biogénérateur durable'),
              const ListTile(
                  title: Text('Construction'),
                  subtitle: Text(
                      '5 Organique · 5 Minéral · 1 Champignon · 1 Algue · 5 Sel')),
              _number(
                  context,
                  'Recette · Organique',
                  _biogeneratorRecipeCost('organic'),
                  (value) => _setBiogeneratorRecipe('organic', value)),
              _number(
                  context,
                  'Recette · Minéral',
                  _biogeneratorRecipeCost('mineral'),
                  (value) => _setBiogeneratorRecipe('mineral', value)),
              for (final itemId in <String>['MUSHROOM', 'ALGAE', 'SALT'])
                _number(
                    context,
                    'Recette · ${ElevagePresentation.itemLabel(itemId)}',
                    _biogeneratorRecipeCost(itemId),
                    (value) => _setBiogeneratorRecipe(itemId, value)),
              _number(
                  context,
                  'Batterie export · énergie locale',
                  ((config.refugeProgression['batteryExport']
                              as Map?)?['energy'] as num?)
                          ?.toInt() ??
                      100,
                  (value) =>
                      _setRefugeNestedNumber('batteryExport', 'energy', value)),
              const ListTile(
                  title: Text('Production énergétique'),
                  subtitle: Text(
                      'Cuves → cycle → Énergie locale ; aucune ressource de Réserve n’est prélevée automatiquement.')),
              _number(
                  context,
                  'Cuve Organique',
                  config.biogeneratorOrganicTankCapacity,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'organicTankCapacity', value)),
              _number(
                  context,
                  'Cuve Minéral',
                  config.biogeneratorMineralTankCapacity,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'mineralTankCapacity', value)),
              _number(
                  context,
                  'Coût Organique / cycle',
                  config.biogeneratorOrganicCost,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'organicCostPerCycle', value)),
              _number(
                  context,
                  'Coût Minéral / cycle',
                  config.biogeneratorMineralCost,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'mineralCostPerCycle', value)),
              _number(
                  context,
                  'Énergie / cycle',
                  config.biogeneratorEnergyPerCycle,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'energyPerCycle', value)),
              _number(
                  context,
                  'Stock Énergie maximum',
                  config.energyStorageMax,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'energyStorageMax', value)),
              _number(
                  context,
                  'Durée cycle (s)',
                  config.biogeneratorCycleSeconds,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'generatorCycleSeconds', value)),
              _number(
                  context,
                  'Bonus Puissance',
                  config.biogeneratorPowerEnergyBonus,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'powerEnergyBonus', value)),
              _number(
                  context,
                  'Bonus Capacité Organique',
                  config.biogeneratorCapacityOrganicBonus,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'capacityOrganicBonus', value)),
              _number(
                  context,
                  'Bonus Capacité Minéral',
                  config.biogeneratorCapacityMineralBonus,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'capacityMineralBonus', value)),
              _number(
                  context,
                  'Réduction Efficacité · Organique',
                  config.biogeneratorEfficiencyOrganicReduction,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'efficiencyOrganicReduction', value)),
              _number(
                  context,
                  'Réduction Efficacité · Minéral',
                  config.biogeneratorEfficiencyMineralReduction,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'efficiencyMineralReduction', value)),
              _number(
                  context,
                  'Coût plancher · Organique',
                  config.biogeneratorMinimumOrganicCost,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'minimumOrganicCost', value)),
              _number(
                  context,
                  'Coût plancher · Minéral',
                  config.biogeneratorMinimumMineralCost,
                  (value) => _setRefugeNestedNumber(
                      'biogenerator', 'minimumMineralCost', value)),
              _heading('Pisteur'),
              for (final level in <int>[1, 2, 3])
                _number(
                    context,
                    'XP Pisteur niveau $level',
                    config.trackerThreshold(level),
                    (value) => _setRefugeNestedNumber(
                        'tracker', 'xpForLevel$level', value)),
              for (final level in <int>[0, 1, 2, 3])
                _number(context, 'Bonus transport Pisteur $level',
                    config.trackerCarryBonus(level), (value) {
                  final tracker = Map<String, dynamic>.from(
                      config.refugeProgression['tracker'] as Map? ??
                          const <dynamic, dynamic>{});
                  final bonuses = Map<String, dynamic>.from(
                      tracker['carryBonusByLevel'] as Map? ??
                          const <dynamic, dynamic>{});
                  bonuses['$level'] = value;
                  tracker['carryBonusByLevel'] = bonuses;
                  final next =
                      Map<String, dynamic>.from(config.refugeProgression)
                        ..['tracker'] = tracker;
                  setState(
                      () => config = config.copyWith(refugeProgression: next));
                }),
              if (widget.controller.config.devMode) _trackerDevTools(context),
              _heading('Expression environnementale Bébé'),
              _number(
                  context,
                  'Amplitude tremblement (px)',
                  ((config.refugeProgression['ambientFeedback']
                              as Map?)?['shiverAmplitudePx'] as num?)
                          ?.toInt() ??
                      3,
                  (value) => _setRefugeNestedNumber(
                      'ambientFeedback', 'shiverAmplitudePx', value)),
              _number(
                  context,
                  'Vitesse tremblement (ms)',
                  ((config.refugeProgression['ambientFeedback']
                              as Map?)?['shiverSpeed'] as num?)
                          ?.toInt() ??
                      65,
                  (value) => _setRefugeNestedNumber(
                      'ambientFeedback', 'shiverSpeed', value)),
              _number(
                  context,
                  'Rafale tremblement (ms)',
                  ((config.refugeProgression['ambientFeedback']
                              as Map?)?['shiverBurstDuration'] as num?)
                          ?.toInt() ??
                      650,
                  (value) => _setRefugeNestedNumber(
                      'ambientFeedback', 'shiverBurstDuration', value)),
              _number(
                  context,
                  'Pause tremblement (ms)',
                  ((config.refugeProgression['ambientFeedback']
                              as Map?)?['shiverPauseDuration'] as num?)
                          ?.toInt() ??
                      1800,
                  (value) => _setRefugeNestedNumber(
                      'ambientFeedback', 'shiverPauseDuration', value)),
              _number(
                  context,
                  'Cooldown vocal Bébé (s)',
                  config.babyVocalCooldownSeconds,
                  (value) => _setRefugeNestedNumber(
                      'ambientFeedback', 'babyVocalCooldownSeconds', value)),
              _number(
                  context,
                  'Cooldown besoin environnemental Juvénile (s)',
                  config.juvenileEnvironmentalNeedCooldownBase,
                  (value) => _setRefugeNestedNumber('ambientFeedback',
                      'juvenileEnvironmentalNeedCooldownBase', value)),
              SwitchListTile(
                  value: ((config.refugeProgression['ambientFeedback']
                          as Map?)?['needPictogramEnabled'] as bool?) ??
                      true,
                  onChanged: (value) {
                    final ambient = Map<String, dynamic>.from(
                        config.refugeProgression['ambientFeedback'] as Map? ??
                            const <dynamic, dynamic>{})
                      ..['needPictogramEnabled'] = value;
                    setState(() => config = config.copyWith(
                        refugeProgression:
                            Map<String, dynamic>.from(config.refugeProgression)
                              ..['ambientFeedback'] = ambient));
                  },
                  title: const Text('Pictogrammes de besoin Juvénile')),
              _heading('Langage et connaissance'),
              _number(
                  context,
                  'Mot Juvénile · concept nouveau',
                  config.juvenileNewConceptWordThreshold,
                  (value) => _setRefugeNestedNumber(
                      'language', 'juvenileNewConceptWordThreshold', value)),
              _number(
                  context,
                  'Mot Juvénile · concept connu Bébé',
                  config.juvenileBabyKnownConceptWordThreshold,
                  (value) => _setRefugeNestedNumber('language',
                      'juvenileBabyKnownConceptWordThreshold', value)),
              _number(
                  context,
                  'Observations → hypothèse',
                  config.observationsForHypothesis,
                  (value) => _setRefugeNestedNumber(
                      'knowledge', 'observationsForHypothesis', value)),
              _number(
                  context,
                  'Preuves → confirmation',
                  config.evidenceForConfirmation,
                  (value) => _setRefugeNestedNumber(
                      'knowledge', 'evidenceForConfirmation', value)),
              _number(
                  context,
                  'Maturation · observations',
                  config.maturationObservationRequirement,
                  (value) => _setRefugeNestedNumber(
                      'maturation', 'observationRequirement', value)),
              _number(
                  context,
                  'Maturation · hypothèses',
                  config.maturationHypothesisRequirement,
                  (value) => _setRefugeNestedNumber(
                      'maturation', 'hypothesisRequirement', value)),
              _number(
                  context,
                  'Maturation · confirmations',
                  config.maturationConfirmationRequirement,
                  (value) => _setRefugeNestedNumber(
                      'maturation', 'confirmationRequirement', value)),
              const ListTile(
                  title: Text('Intentions de communication'),
                  subtitle: Text(
                      'L’intention reste fixe ; seuls les textes Juvénile et Mature sont modifiables.')),
              for (final entry in _communicationIntentDetails.entries)
                ListTile(
                    title: Text(entry.value.$1),
                    subtitle: Text(
                        '${entry.value.$2}\nJuvénile : ${config.communicationText(entry.key, 'JUVENILE', entry.value.$3)} · Mature : ${config.communicationText(entry.key, 'MATURE', entry.value.$4)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editCommunicationIntent(
                        context, entry.key, entry.value)),
              _heading('Tam Tam'),
              _number(
                  context,
                  'Battements',
                  config.tamTamTotalBeats,
                  (value) =>
                      _setRefugeNestedNumber('tamTam', 'totalBeats', value)),
              _number(
                  context,
                  'Battements à réussir',
                  config.tamTamRequiredSuccessfulBeats,
                  (value) => _setRefugeNestedNumber(
                      'tamTam', 'requiredSuccessfulBeats', value)),
              _number(
                  context,
                  'Intervalle (ms)',
                  config.tamTamBeatIntervalMs,
                  (value) => _setRefugeNestedNumber(
                      'tamTam', 'beatIntervalMs', value)),
              _number(
                  context,
                  'Fenêtre parfaite (ms)',
                  config.tamTamPerfectWindowMs,
                  (value) => _setRefugeNestedNumber(
                      'tamTam', 'perfectWindowMs', value)),
              _number(
                  context,
                  'Fenêtre bonne (ms)',
                  config.tamTamGoodWindowMs,
                  (value) =>
                      _setRefugeNestedNumber('tamTam', 'goodWindowMs', value)),
              _heading('Confiance du Refuge'),
              _number(
                  context,
                  'Gain · adoption',
                  config.trustGainAdoption,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainAdoption', value)),
              _number(
                  context,
                  'Gain · observation',
                  config.trustGainObservation,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainObservation', value)),
              _number(
                  context,
                  'Gain · hypothèse',
                  config.trustGainHypothesis,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainHypothesis', value)),
              _number(
                  context,
                  'Gain · découverte',
                  config.trustGainDiscovery,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainDiscovery', value)),
              _number(
                  context,
                  'Gain · passage Juvénile',
                  config.trustGainIntermediate,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainIntermediate', value)),
              _number(
                  context,
                  'Gain · passage Mature',
                  config.trustGainMature,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'trustGainMature', value)),
              _number(
                  context,
                  'Seuil bien-être critique',
                  config.criticalWellbeingThreshold,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'criticalWellbeingThreshold', value)),
              _number(
                  context,
                  'Malus critique',
                  config.criticalWellbeingTrustPenalty,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'criticalWellbeingTrustPenalty', value)),
              _number(
                  context,
                  'Période critique (heures)',
                  config.criticalWellbeingPenaltyHours,
                  (value) => _setRefugeNestedNumber(
                      'trust', 'criticalWellbeingPenaltyHours', value)),
              if (config.devMode)
                Wrap(spacing: 8, children: <Widget>[
                  OutlinedButton(
                      onPressed: () => widget.controller.addTrust(10),
                      child: const Text('+10 Confiance')),
                  OutlinedButton(
                      onPressed: () => widget.controller.setTrust(100),
                      child: const Text('Confiance 100')),
                  OutlinedButton(
                      onPressed: () => widget.controller.addTrust(-10),
                      child: const Text('-10 Confiance')),
                  if (((widget.controller.state?.data['activeIndividualIds']
                              as List?) ??
                          const <dynamic>[])
                      .isNotEmpty)
                    OutlinedButton(
                        onPressed: () {
                          final id = (widget.controller.state!
                                  .data['activeIndividualIds'] as List)
                              .first as String;
                          widget.controller
                              .simulateCriticalWellbeingTrustPeriod(id);
                        },
                        child: const Text('Simuler 24 h critique')),
                ]),
              for (var index = 2;
                  index <= config.alcoveCount;
                  index++) ...<Widget>[
                _heading('Alcôve $index · progression'),
                _number(
                    context,
                    'Seuil Confiance',
                    (config.requirementForAlcove(index)['requiredContribution']
                                as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAlcoveRequirement(
                        index, 'requiredContribution', value)),
                _number(
                    context,
                    'Clé en main · Bio-piles',
                    (config.requirementForAlcove(index)['turnkeyBiopileCost']
                                as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAlcoveRequirement(
                        index, 'turnkeyBiopileCost', value)),
                _number(
                    context,
                    'Chantier assisté · Bio-piles',
                    (config.requirementForAlcove(index)['assistedBiopileCost']
                                as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAlcoveRequirement(
                        index, 'assistedBiopileCost', value)),
                _number(
                    context,
                    'Durée chantier (s)',
                    (config.requirementForAlcove(
                                index)['constructionDurationSeconds'] as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAlcoveRequirement(
                        index, 'constructionDurationSeconds', value)),
                _number(
                    context,
                    'Chantier · Organique',
                    ((config.requirementForAlcove(
                                    index)['assistedResourceCosts']
                                as Map?)?['ORGANIC'] as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAssistedCost(index, 'ORGANIC', value)),
                _number(
                    context,
                    'Chantier · Minéral',
                    ((config.requirementForAlcove(
                                    index)['assistedResourceCosts']
                                as Map?)?['MINERAL'] as num?)
                            ?.toInt() ??
                        0,
                    (value) => _setAssistedCost(index, 'MINERAL', value)),
              ],
              _heading('Maturation, satiété et découverte'),
              Text(
                  'Bébé : ${config.babyMinimumHours} h · Intermédiaire : ${config.intermediateMinimumHours} h'),
              const Text(
                  'Satiété V2 · une jauge 0–100, sans timer par aliment.'),
              _number(context, 'Satiété initiale', config.initialSatiety,
                  (value) => _setSatietyNumber('initialSatiety', value)),
              _number(
                  context,
                  'Perte Bébé / h',
                  config.satietyLossPerHour('BABY'),
                  (value) => _setSatietyNumber('babyLossPerHour', value)),
              _number(
                  context,
                  'Perte Juvénile / h',
                  config.satietyLossPerHour('INTERMEDIATE'),
                  (value) =>
                      _setSatietyNumber('intermediateLossPerHour', value)),
              _number(
                  context,
                  'Perte Mature / h',
                  config.satietyLossPerHour('MATURE'),
                  (value) => _setSatietyNumber('matureLossPerHour', value)),
              _number(
                  context,
                  'Seuil Rassasié',
                  config.satietySatiatedThreshold,
                  (value) => _setSatietyNumber('satiatedThreshold', value)),
              _number(context, 'Seuil Faim', config.satietyHungryThreshold,
                  (value) => _setSatietyNumber('hungryThreshold', value)),
              for (final item in <String>[
                'LEAF',
                'MOSS',
                'ALGAE',
                'ROOT',
                'FRUIT',
                'MUSHROOM',
                'TREAT'
              ])
                _number(
                    context,
                    'Satiété ${item == 'TREAT' ? 'Friandise' : ElevagePresentation.itemLabel(item)}',
                    config.foodSatietyValue(item),
                    (value) => _setFoodSatietyValue(item, value)),
              _number(
                  context,
                  'Signal Bébé faim (s)',
                  _satietyNumber('babyHungrySignalCooldown', 8),
                  (value) =>
                      _setSatietyNumber('babyHungrySignalCooldown', value)),
              _number(
                  context,
                  'Signal Bébé très faim (s)',
                  _satietyNumber('babyVeryHungrySignalCooldown', 4),
                  (value) =>
                      _setSatietyNumber('babyVeryHungrySignalCooldown', value)),
              _number(
                  context,
                  'Signal Juvénile faim (s)',
                  _satietyNumber('juvenileHungrySignalCooldown', 10),
                  (value) =>
                      _setSatietyNumber('juvenileHungrySignalCooldown', value)),
              _number(
                  context,
                  'Signal Juvénile très faim (s)',
                  _satietyNumber('juvenileVeryHungrySignalCooldown', 5),
                  (value) => _setSatietyNumber(
                      'juvenileVeryHungrySignalCooldown', value)),
              if (widget.controller.config.devMode) _satietyDevTools(context),
              _heading('Cuisine et météo'),
              _number(
                  context,
                  'Portions sèches',
                  config.dryPortions,
                  (value) =>
                      _setRefugeNestedNumber('cooking', 'dryPortions', value)),
              _number(
                  context,
                  'Portions humides',
                  config.wetPortions,
                  (value) =>
                      _setRefugeNestedNumber('cooking', 'wetPortions', value)),
              _number(
                  context,
                  'Bonus sec / portion',
                  config.dryBonusPerPortion,
                  (value) => _setRefugeNestedNumber(
                      'cooking', 'dryBonusPerPortion', value)),
              _number(
                  context,
                  'Bonus humide / portion',
                  config.wetBonusPerPortion,
                  (value) => _setRefugeNestedNumber(
                      'cooking', 'wetBonusPerPortion', value)),
              _number(
                  context,
                  'Réservoir Eau',
                  config.waterTankCapacity,
                  (value) => _setRefugeNestedNumber(
                      'cooking', 'waterTankCapacity', value)),
              _number(
                  context,
                  'Bloc météo (h)',
                  config.weatherBlockHours,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'weatherBlockHours', value)),
              _number(
                  context,
                  'Poids beau temps',
                  config.weatherClearWeight,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'weatherClearWeight', value)),
              _number(
                  context,
                  'Poids petite pluie',
                  config.weatherLightRainWeight,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'weatherLightRainWeight', value)),
              _number(
                  context,
                  'Poids forte pluie',
                  config.weatherHeavyRainWeight,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'weatherHeavyRainWeight', value)),
              _number(
                  context,
                  'Eau de pluie / h',
                  config.rainWaterPerHour,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'rainWaterPerHour', value)),
              _number(
                  context,
                  'Début nuit locale',
                  config.nightStartHour,
                  (value) => _setRefugeNestedNumber(
                      'weather', 'nightStartHour', value)),
              _number(
                  context,
                  'Fin nuit locale',
                  config.nightEndHour,
                  (value) =>
                      _setRefugeNestedNumber('weather', 'nightEndHour', value)),
              _number(
                  context,
                  'Preuves suspectées',
                  config.suspectedThreshold,
                  (value) =>
                      config = config.copyWith(suspectedThreshold: value)),
              _number(
                  context,
                  'Preuves confirmées',
                  config.confirmedThreshold,
                  (value) =>
                      config = config.copyWith(confirmedThreshold: value)),
              _number(
                  context,
                  'Observation textuelle après',
                  config.observationTextThreshold,
                  (value) => config =
                      config.copyWith(observationTextThreshold: value)),
              _number(
                  context,
                  'Fenêtre de preuve (min)',
                  config.observationEvidenceCooldownMinutes,
                  (value) => config = config.copyWith(
                      observationEvidenceCooldownMinutes: value)),
              _heading('Cycle et inventaire'),
              ListTile(
                  leading: const Icon(Icons.nightlight_outlined),
                  title: const Text('Nuit locale réelle'),
                  subtitle: Text(
                      '${config.nightStartHour.toString().padLeft(2, '0')}:00 → ${config.nightEndHour.toString().padLeft(2, '0')}:00')),
              _heading('Rythmes de sommeil'),
              _number(
                  context,
                  'Végétal · sommeil nocturne (min)',
                  config.vegetalSleepMinutes,
                  (value) =>
                      config = config.copyWith(vegetalSleepMinutes: value)),
              _number(
                  context,
                  'Minéral · début du jour (min)',
                  config.mineralDaySleepMinutes,
                  (value) =>
                      config = config.copyWith(mineralDaySleepMinutes: value)),
              _number(
                  context,
                  'Minéral · fin de nuit (min)',
                  config.mineralLateNightSleepMinutes,
                  (value) => config =
                      config.copyWith(mineralLateNightSleepMinutes: value)),
              _number(
                  context,
                  'Fongique · milieu du jour (min)',
                  config.fungalMidDaySleepMinutes,
                  (value) => config =
                      config.copyWith(fungalMidDaySleepMinutes: value)),
              _number(
                  context,
                  'Fongique · transition jour/nuit (min)',
                  config.fungalTransitionSleepMinutes,
                  (value) => config =
                      config.copyWith(fungalTransitionSleepMinutes: value)),
              const ListTile(
                  title: Text('Siestes diurnes'),
                  subtitle: Text(
                      'Une pause courte nécessite un meuble de repos ; Posé a davantage d’occasions que Spontané.')),
              _number(
                  context,
                  'Durée sieste (s)',
                  config.dayNapDurationSeconds,
                  (value) => _setRefugeNestedNumber(
                      'rest', 'dayNapDurationSeconds', value)),
              _number(
                  context,
                  'Cooldown sieste (s)',
                  config.dayNapCooldownSeconds,
                  (value) => _setRefugeNestedNumber(
                      'rest', 'dayNapCooldownSeconds', value)),
              _number(
                  context,
                  'Chance sieste Posé (%)',
                  config.posedDayNapChancePercent,
                  (value) => _setRefugeNestedNumber(
                      'rest', 'posedDayNapChancePercent', value)),
              _number(
                  context,
                  'Chance sieste Spontané (%)',
                  config.spontaneousDayNapChancePercent,
                  (value) => _setRefugeNestedNumber(
                      'rest', 'spontaneousDayNapChancePercent', value)),
              _number(
                  context,
                  'Taille d’une pile',
                  config.inventoryStackSize,
                  (value) =>
                      config = config.copyWith(inventoryStackSize: value)),
              _heading('Chaîne énergétique'),
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Réserve → cuves du Biogénérateur → Énergie locale. Les réglages de production sont dans « Biogénérateur durable » ; aucune conversion directe depuis la Réserve.')),
              _heading('Séjour dans une zone'),
              _number(
                  context,
                  'Bébé · séjour neutre (s)',
                  config.baseStayBabySeconds,
                  (value) =>
                      config = config.copyWith(baseStayBabySeconds: value)),
              _number(
                  context,
                  'Intermédiaire · séjour neutre (s)',
                  config.baseStayIntermediateSeconds,
                  (value) => config =
                      config.copyWith(baseStayIntermediateSeconds: value)),
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
                  (value) => config = config.copyWith(
                      tempoSpontaneousStayModifierSeconds: value)),
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
                  (value) => config =
                      config.copyWith(badZoneStayModifierSeconds: value)),
              _number(
                  context,
                  'Zone extrême (s)',
                  config.extremeZoneStayModifierSeconds,
                  (value) => config =
                      config.copyWith(extremeZoneStayModifierSeconds: value)),
              _number(context, 'Minimum absolu (s)', config.minStaySeconds,
                  (value) => config = config.copyWith(minStaySeconds: value)),
              _number(
                  context,
                  'Gain de résonance',
                  config.resonanceGainPerUse,
                  (value) =>
                      config = config.copyWith(resonanceGainPerUse: value)),
              _heading('Exploration et installations'),
              SwitchListTile(
                  title: const Text('Exploration activée'),
                  value: config.explorationEnabled,
                  onChanged: (value) =>
                      _setRefugeNestedBool('exploration', 'enabled', value)),
              _number(
                  context,
                  'Durée Exploration (s)',
                  config.explorationInt('durationSeconds', 25),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'durationSeconds', value)),
              _number(
                  context,
                  'Slots de récolte joueur',
                  config.explorationInt('baseCarrySlots', 3),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'baseCarrySlots', value)),
              _number(
                  context,
                  'Stamina maximum',
                  config.explorationInt('playerStaminaMax', 10),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'playerStaminaMax', value)),
              _number(
                  context,
                  'Coût Stamina / sortie',
                  config.explorationInt('playerStaminaCost', 1),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'playerStaminaCost', value)),
              _number(
                  context,
                  'Régénération Stamina (min / point)',
                  config.explorationInt('playerStaminaRegenMinutes', 5),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'playerStaminaRegenMinutes', value)),
              _number(
                  context,
                  'Endurance P’TIPOTE maximum',
                  config.explorationInt('ptipoteStaminaMax', 10),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'ptipoteStaminaMax', value)),
              _number(
                  context,
                  'Coût Endurance P’TIPOTE / sortie',
                  config.explorationInt('ptipoteStaminaCostPerRun', 1),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'ptipoteStaminaCostPerRun', value)),
              _number(
                  context,
                  'Régénération Endurance P’TIPOTE (min / point)',
                  config.explorationInt('ptipoteStaminaRegenMinutes', 5),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'ptipoteStaminaRegenMinutes', value)),
              _number(
                  context,
                  'XP Pisteur / exploration accompagnée',
                  config.explorationInt('trackerXpPerExploration', 10),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'trackerXpPerExploration', value)),
              for (final family in <String>['VEGETAL', 'MINERAL', 'FUNGAL'])
                _number(
                    context,
                    'Biais loot $family (%)',
                    _typeLootBiasPercent(family),
                    (value) => _setTypeLootBiasPercent(family, value)),
              _number(
                  context,
                  'Régénération Organique / h',
                  config.explorationInt('organicRegenPerHour', 5),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'organicRegenPerHour', value)),
              _number(
                  context,
                  'Coût Organique générique (%)',
                  config.explorationInt('genericOrganicCost', 1),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'genericOrganicCost', value)),
              _number(
                  context,
                  'Coût Organique spécifique (%)',
                  config.explorationInt('specificOrganicCost', 5),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'specificOrganicCost', value)),
              _number(
                  context,
                  'Coût Minéral générique',
                  config.explorationInt('genericMineralCost', 1),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'genericMineralCost', value)),
              _number(
                  context,
                  'Coût Minéral spécifique',
                  config.explorationInt('specificMineralCost', 3),
                  (value) => _setRefugeNestedNumber(
                      'exploration', 'specificMineralCost', value)),
              const Padding(
                  padding: EdgeInsets.only(left: 16, right: 16, bottom: 4),
                  child: Text(
                      'Chaque secteur possède ses valeurs initiales, son état activé et sa table de loot configurable.')),
              ...ElevageDomain.explorationSectors.map((sector) => ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: Text(sector['label'] as String),
                    subtitle: Text(
                        '${sector['biomeId']} · Organique ${sector['organic']}% · Minéral ${sector['mineral']}'),
                    trailing: const Icon(Icons.tune),
                    onTap: () => _editExplorationSector(context, sector),
                  )),
              _number(
                  context,
                  'Intervalle de production (s)',
                  config.productionIntervalSeconds,
                  (value) => config =
                      config.copyWith(productionIntervalSeconds: value)),
              _number(
                  context,
                  'Stock local maximum',
                  config.productionMaxStock,
                  (value) =>
                      config = config.copyWith(productionMaxStock: value)),
              _heading('Producteurs biologiques'),
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Chaque sortie possède son propre rythme, stock maximal et état actif.')),
              ...config.producerOutputs.entries
                  .expand((entry) => entry.value.map((output) => ListTile(
                        title: Text(
                            '${ElevagePresentation.installationLabel(entry.key)} · ${ElevagePresentation.itemLabel(output.resourceId)}'),
                        subtitle: Text(
                            '${output.quantityPerCycle}/cycle · ${output.productionSeconds}s · stock ${output.maxLocalStock}${output.enabled ? '' : ' · désactivé'}'),
                        trailing: const Icon(Icons.tune),
                        onTap: () =>
                            _editProducerOutput(context, entry.key, output),
                      ))),
              _heading('Entretien des structures actives'),
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Les installations alimentées consomment l’Énergie locale. NONE laisse une structure passive.')),
              ...config.structureConsumptions.entries.map((entry) => ListTile(
                    title:
                        Text(ElevagePresentation.installationLabel(entry.key)),
                    subtitle: Text(_consumptionSummary(entry.value)),
                    trailing: const Icon(Icons.tune),
                    onTap: () => _editStructureConsumption(
                        context, entry.key, entry.value),
                  )),
              _heading('Modules de structure'),
              ...config.structureModules.entries.map((entry) => ListTile(
                    title:
                        Text(ElevagePresentation.installationLabel(entry.key)),
                    subtitle: Text(
                        '${entry.value.moduleSlots} slot(s) · ${entry.value.allowedModuleIds.map((id) => config.module(id)?.label ?? id).join(' · ')}'),
                    trailing: const Icon(Icons.tune),
                    onTap: () =>
                        _editModuleSlots(context, entry.key, entry.value),
                  )),
              ...config.modules.values.map((module) => ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(module.label),
                    subtitle: Text(_moduleConfigSummary(module)),
                    trailing: const Icon(Icons.tune),
                    onTap: () => _editModuleDefinition(context, module),
                  )),
              _heading('Co-élevage et Sourcier'),
              _number(
                  context,
                  'Durée co-élevage (h)',
                  config.coRearingDurationHours,
                  (value) =>
                      config = config.copyWith(coRearingDurationHours: value)),
              _number(
                  context,
                  'Prix Fruit fibreux',
                  config.fibrousFruitPrice,
                  (value) =>
                      config = config.copyWith(fibrousFruitPrice: value)),
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
                  (value) => config =
                      config.copyWith(metamorphosisToleranceMs: value)),
              _heading('Voix et onomatopées'),
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Ces textes apparaissent dans les petites bulles de communication.')),
              ..._vocalizationLabels.entries.map((entry) => ListTile(
                    title: Text(entry.value),
                    subtitle: Text(config.vocalizations[entry.key] ?? ''),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () =>
                        _editVocalization(context, entry.key, entry.value),
                  )),
              _heading('Actions'),
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
            ])),
      );

  Widget _heading(String text) => _DashboardSectionHeader(text);

  List<Widget> _accordionize(List<Widget> entries) {
    final sections = <Widget>[];
    String? title;
    var content = <Widget>[];
    void flush() {
      if (title == null) return;
      sections.add(Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
              title: Text(title),
              initiallyExpanded: false,
              children: content)));
    }

    for (final entry in entries) {
      if (entry is _DashboardSectionHeader) {
        flush();
        title = entry.title;
        content = <Widget>[];
      } else if (title != null) {
        content.add(entry);
      }
    }
    flush();
    return sections;
  }

  Future<void> _editExplorationSector(
      BuildContext context, Map<String, dynamic> base) async {
    final sectorId = base['id'] as String;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) =>
            StatefulBuilder(builder: (sheetContext, setSheetState) {
              final sector =
                  ElevageDomain.resolvedExplorationSector(base, config);
              final table = (sector['lootTable'] as List)
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList(growable: false);
              Future<void> editNumber(
                  String label, String key, int value) async {
                final next = await _numberDialog(sheetContext, label, value);
                if (next == null || !sheetContext.mounted) return;
                _setExplorationSectorValue(sectorId, key, next);
                setSheetState(() {});
              }

              return SafeArea(
                  child: DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: .72,
                      minChildSize: .4,
                      maxChildSize: .94,
                      builder: (_, scrollController) => ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              children: <Widget>[
                                ListTile(
                                    leading: const Icon(Icons.explore_outlined),
                                    title: Text(sector['label'] as String),
                                    subtitle: const Text(
                                        'Configuration persistante du secteur')),
                                SwitchListTile(
                                    title: const Text('Secteur activé'),
                                    value: sector['enabled'] != false,
                                    onChanged: (value) {
                                      _setExplorationSectorValue(
                                          sectorId, 'enabled', value);
                                      setSheetState(() {});
                                    }),
                                ListTile(
                                    title: const Text('Organique initial (%)'),
                                    trailing: Text('${sector['organic']}'),
                                    onTap: () => editNumber(
                                        'Organique initial',
                                        'initialOrganic',
                                        (sector['organic'] as num).toInt())),
                                ListTile(
                                    title: const Text('Minéral initial'),
                                    trailing: Text('${sector['mineral']}'),
                                    onTap: () => editNumber(
                                        'Minéral initial',
                                        'initialMineral',
                                        (sector['mineral'] as num).toInt())),
                                ListTile(
                                    title: const Text('Plafond Organique'),
                                    trailing: Text('${sector['maxOrganic']}'),
                                    onTap: () => editNumber(
                                        'Plafond Organique',
                                        'maxOrganic',
                                        (sector['maxOrganic'] as num).toInt())),
                                const Divider(),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('Table de loot',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700))),
                                ...table.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final loot = entry.value;
                                  return ListTile(
                                      title: Text(ElevagePresentation.itemLabel(
                                          loot['resourceId'] as String)),
                                      subtitle: Text(
                                          '${loot['resourceCategory']} · poids ${loot['weight']}'),
                                      trailing: Switch(
                                          value: loot['enabled'] != false,
                                          onChanged: (value) {
                                            final next = table
                                                .map(Map<String, dynamic>.from)
                                                .toList(growable: false);
                                            next[index]['enabled'] = value;
                                            _setExplorationLootValue(
                                                sectorId, next);
                                            setSheetState(() {});
                                          }),
                                      onTap: () async {
                                        final nextWeight = await _numberDialog(
                                            sheetContext,
                                            'Poids ${loot['resourceId']}',
                                            (loot['weight'] as num).toInt());
                                        if (nextWeight == null ||
                                            !sheetContext.mounted) {
                                          return;
                                        }
                                        final next = table
                                            .map(Map<String, dynamic>.from)
                                            .toList(growable: false);
                                        next[index]['weight'] = nextWeight;
                                        _setExplorationLootValue(
                                            sectorId, next);
                                        setSheetState(() {});
                                      });
                                }),
                              ])));
            }));
  }

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

  String _consumptionSummary(ElevageStructureConsumption consumption) {
    if (consumption.mode == 'NONE') return 'Passive';
    if (!consumption.enabled) return 'Désactivée';
    final cost = consumption.mode == 'ENERGY'
        ? '${consumption.energyCost} Énergie'
        : consumption.resourceCosts.entries
            .map((entry) =>
                '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}')
            .join(' · ');
    return '${consumption.mode} · $cost / ${consumption.consumptionIntervalSeconds}s';
  }

  String _moduleConfigSummary(ElevageModuleDefinition module) {
    final effect = module.effects.entries
        .map((entry) => '${entry.key} ${entry.value}')
        .join(' · ');
    return '${module.category} · $effect · ${module.stackable ? 'cumulable x${module.maxStacksPerStructure}' : 'unique'}${module.enabled ? '' : ' · désactivé'}';
  }

  Future<void> _editModuleSlots(BuildContext context, String structureId,
      ElevageStructureModuleProfile profile) async {
    final next = await _numberDialog(
        context,
        '${ElevagePresentation.installationLabel(structureId)} · slots',
        profile.moduleSlots);
    if (!context.mounted || next == null || next < 0) return;
    setState(() => config = config.copyWith(structureModules: {
          ...config.structureModules,
          structureId: profile.copyWith(moduleSlots: next),
        }));
  }

  Future<void> _editModuleDefinition(
      BuildContext context, ElevageModuleDefinition module) async {
    final controllers = <String, TextEditingController>{
      'organic': TextEditingController(text: '${module.organicCost}'),
      'mineral': TextEditingController(text: '${module.mineralCost}'),
      'stacks': TextEditingController(text: '${module.maxStacksPerStructure}'),
      'effect': TextEditingController(
          text: '${module.effects.values.firstOrNull ?? 0}'),
    };
    var enabled = module.enabled;
    var stackable = module.stackable;
    ElevageModuleDefinition? next;
    try {
      next = await showDialog<ElevageModuleDefinition>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setLocal) => AlertDialog(
                    title: Text(module.label),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(module.description),
                      SwitchListTile(
                          title: const Text('Activé'),
                          value: enabled,
                          onChanged: (value) =>
                              setLocal(() => enabled = value)),
                      SwitchListTile(
                          title: const Text('Cumulable'),
                          value: stackable,
                          onChanged: (value) =>
                              setLocal(() => stackable = value)),
                      for (final entry in <String, String>{
                        'organic': 'Coût Organique',
                        'mineral': 'Coût Minéral',
                        'stacks': 'Maximum par structure',
                        'effect': 'Valeur de l’effet',
                      }.entries)
                        TextField(
                            controller: controllers[entry.key],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                InputDecoration(labelText: entry.value)),
                    ])),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () {
                            final organic =
                                int.tryParse(controllers['organic']!.text);
                            final mineral =
                                int.tryParse(controllers['mineral']!.text);
                            final stacks =
                                int.tryParse(controllers['stacks']!.text);
                            final effect =
                                num.tryParse(controllers['effect']!.text);
                            if (organic == null ||
                                mineral == null ||
                                stacks == null ||
                                effect == null ||
                                organic < 0 ||
                                mineral < 0 ||
                                stacks <= 0) {
                              return;
                            }
                            Navigator.pop(
                                dialogContext,
                                module.copyWith(
                                    enabled: enabled,
                                    stackable: stackable,
                                    maxStacksPerStructure: stacks,
                                    organicCost: organic,
                                    mineralCost: mineral,
                                    effects: <String, num>{
                                      module.effects.keys.first: effect,
                                    }));
                          },
                          child: const Text('Valider')),
                    ],
                  )));
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    if (!context.mounted || next == null) return;
    setState(() => config = config.copyWith(modules: {
          ...config.modules,
          module.id: next!,
        }));
  }

  Future<void> _editStructureConsumption(BuildContext context,
      String installationId, ElevageStructureConsumption current) async {
    final isHeating = installationId == 'FOUR_BIO_ORGANIQUE';
    // Chauffage has no direct-resource fallback: its Energy comes from the
    // shared local pool, itself supplied by the battery/generator chain.
    var mode = isHeating ? 'ENERGY' : current.mode;
    var enabled = current.enabled;
    final energy = TextEditingController(text: '${current.energyCost}');
    final organic =
        TextEditingController(text: '${current.resourceCosts['ORGANIC'] ?? 0}');
    final mineral =
        TextEditingController(text: '${current.resourceCosts['MINERAL'] ?? 0}');
    final interval =
        TextEditingController(text: '${current.consumptionIntervalSeconds}');
    ElevageStructureConsumption? next;
    try {
      next = await showDialog<ElevageStructureConsumption>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setLocal) => AlertDialog(
                    title: Text(
                        '${ElevagePresentation.installationLabel(installationId)} · entretien'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: mode,
                          decoration: const InputDecoration(labelText: 'Mode'),
                          items: (isHeating
                                  ? const <String>['ENERGY']
                                  : const <String>[
                                      'NONE',
                                      'ENERGY',
                                      'DIRECT_RESOURCE',
                                      'MULTI_RESOURCE'
                                    ])
                              .map((value) => DropdownMenuItem(
                                  value: value, child: Text(value)))
                              .toList(),
                          onChanged: isHeating
                              ? null
                              : (value) =>
                                  setLocal(() => mode = value ?? mode)),
                      SwitchListTile(
                          title: const Text('Activé'),
                          value: enabled,
                          onChanged: (value) =>
                              setLocal(() => enabled = value)),
                      if (mode == 'ENERGY')
                        TextField(
                            controller: energy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Coût Énergie')),
                      if (mode == 'DIRECT_RESOURCE' || mode == 'MULTI_RESOURCE')
                        TextField(
                            controller: organic,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Coût Organique')),
                      if (mode == 'MULTI_RESOURCE')
                        TextField(
                            controller: mineral,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Coût Minéral')),
                      if (mode != 'NONE')
                        TextField(
                            controller: interval,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Intervalle (s)')),
                    ])),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () {
                            final effectiveMode = isHeating ? 'ENERGY' : mode;
                            final energyCost = int.tryParse(energy.text) ?? 0;
                            final organicCost = int.tryParse(organic.text) ?? 0;
                            final mineralCost = int.tryParse(mineral.text) ?? 0;
                            final seconds = int.tryParse(interval.text) ?? 0;
                            if (effectiveMode != 'NONE' &&
                                (seconds <= 0 ||
                                    (effectiveMode == 'ENERGY' &&
                                        energyCost <= 0) ||
                                    (effectiveMode != 'ENERGY' &&
                                        organicCost <= 0) ||
                                    (effectiveMode == 'MULTI_RESOURCE' &&
                                        mineralCost <= 0))) {
                              return;
                            }
                            Navigator.pop(
                                dialogContext,
                                ElevageStructureConsumption(
                                  mode: effectiveMode,
                                  enabled: enabled,
                                  energyCost: effectiveMode == 'ENERGY'
                                      ? energyCost
                                      : 0,
                                  resourceCosts: effectiveMode ==
                                          'DIRECT_RESOURCE'
                                      ? <String, int>{'ORGANIC': organicCost}
                                      : effectiveMode == 'MULTI_RESOURCE'
                                          ? <String, int>{
                                              'ORGANIC': organicCost,
                                              'MINERAL': mineralCost,
                                            }
                                          : const <String, int>{},
                                  consumptionIntervalSeconds:
                                      effectiveMode == 'NONE' ? 0 : seconds,
                                ));
                          },
                          child: const Text('Valider')),
                    ],
                  )));
    } finally {
      energy.dispose();
      organic.dispose();
      mineral.dispose();
      interval.dispose();
    }
    if (!context.mounted || next == null) return;
    setState(() => config = config.copyWith(structureConsumptions: {
          ...config.structureConsumptions,
          installationId: next!,
        }));
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

  Future<void> _editCommunicationIntent(BuildContext context, String intent,
      (String, String, String, String) details) async {
    final juvenile = TextEditingController(
        text: config.communicationText(intent, 'JUVENILE', details.$3));
    final mature = TextEditingController(
        text: config.communicationText(intent, 'MATURE', details.$4));
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(details.$1),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                      alignment: Alignment.centerLeft, child: Text(details.$2)),
                  TextField(
                      controller: juvenile,
                      maxLength: 32,
                      decoration: const InputDecoration(labelText: 'Juvénile')),
                  TextField(
                      controller: mature,
                      maxLength: 64,
                      decoration: const InputDecoration(labelText: 'Mature')),
                ]),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Valider')),
                ]));
    if (!context.mounted || accepted != true) return;
    final juvenileText = juvenile.text.trim();
    final matureText = mature.text.trim();
    juvenile.dispose();
    mature.dispose();
    if (juvenileText.isEmpty || matureText.isEmpty) return;
    final progression = Map<String, dynamic>.from(config.refugeProgression);
    final communication = Map<String, dynamic>.from(
        progression['communication'] as Map? ?? const <dynamic, dynamic>{});
    final values = Map<String, dynamic>.from(
        communication[intent] as Map? ?? const <dynamic, dynamic>{})
      ..['label'] = details.$1
      ..['description'] = details.$2
      ..['juvenileText'] = juvenileText
      ..['matureText'] = matureText;
    communication[intent] = values;
    progression['communication'] = communication;
    setState(() => config = config.copyWith(refugeProgression: progression));
  }

  Future<void> _editProducerOutput(BuildContext context, String installationId,
      ElevageProductionOutput output) async {
    var draft = output;
    final next = await showDialog<ElevageProductionOutput>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setLocal) => AlertDialog(
                title: Text(
                    '${ElevagePresentation.installationLabel(installationId)} · ${ElevagePresentation.itemLabel(output.resourceId)}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Production active'),
                      value: draft.enabled,
                      onChanged: (value) => setLocal(
                          () => draft = draft.copyWith(enabled: value))),
                  TextFormField(
                      initialValue: '${draft.quantityPerCycle}',
                      decoration: const InputDecoration(
                          labelText: 'Quantité par cycle'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => draft = draft.copyWith(
                          quantityPerCycle:
                              int.tryParse(value) ?? draft.quantityPerCycle)),
                  TextFormField(
                      initialValue: '${draft.productionSeconds}',
                      decoration: const InputDecoration(
                          labelText: 'Production (secondes)'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => draft = draft.copyWith(
                          productionSeconds:
                              int.tryParse(value) ?? draft.productionSeconds)),
                  TextFormField(
                      initialValue: '${draft.maxLocalStock}',
                      decoration: const InputDecoration(
                          labelText: 'Stock local maximum'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => draft = draft.copyWith(
                          maxLocalStock:
                              int.tryParse(value) ?? draft.maxLocalStock)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, draft),
                      child: const Text('Valider')),
                ],
              ),
            ));
    if (!context.mounted || next == null) return;
    final outputs = <String, List<ElevageProductionOutput>>{
      for (final entry in config.producerOutputs.entries)
        entry.key: List<ElevageProductionOutput>.from(entry.value),
    };
    outputs[installationId] = outputs[installationId]!
        .map((candidate) =>
            candidate.resourceId == next.resourceId ? next : candidate)
        .toList(growable: false);
    setState(() => config = config.copyWith(producerOutputs: outputs));
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
      'HUNGRY' => 'A faim',
      _ => 'Très faim'
    };
String _communicationLabel(String value) => switch (value) {
      'ROOT' => 'Souhaite une racine',
      'LEAF' => 'Souhaite une feuille',
      'IRON' => 'Recherche du fer',
      'FOOD' => 'A faim',
      'HUNGER' => 'A faim',
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
    required this.onSceneItemDrop,
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
    required this.ambientSignal,
    required this.expressedNeed,
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
  final void Function(String itemId, String zoneId) onSceneItemDrop;
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
  final Map<String, String>? ambientSignal;
  final String? expressedNeed;
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
  Timer? _shiverTimer;
  bool _crystalPulse = false;
  bool _shiverOffset = false;

  @override
  void initState() {
    super.initState();
    _crystalPulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && widget.crystallizing) {
        setState(() => _crystalPulse = !_crystalPulse);
      }
    });
    final feedbackConfig =
        widget.config.refugeProgression['ambientFeedback'] as Map?;
    _shiverTimer = Timer.periodic(
        Duration(
            milliseconds:
                (feedbackConfig?['shiverSpeed'] as num?)?.toInt() ?? 120), (_) {
      if (!mounted || widget.ambientSignal?['body'] != 'SHIVER') return;
      final feedback =
          widget.config.refugeProgression['ambientFeedback'] as Map?;
      final burst = (feedback?['shiverBurstDuration'] as num?)?.toInt() ?? 650;
      final pause = (feedback?['shiverPauseDuration'] as num?)?.toInt() ?? 1800;
      final elapsed = DateTime.now().millisecondsSinceEpoch % (burst + pause);
      final shiveringNow = elapsed < burst;
      setState(() => _shiverOffset = shiveringNow ? !_shiverOffset : false);
    });
  }

  @override
  void dispose() {
    _crystalPulseTimer?.cancel();
    _shiverTimer?.cancel();
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
    final feedback = widget.config.refugeProgression['ambientFeedback'] as Map?;
    final shiverAmplitude =
        (feedback?['shiverAmplitudePx'] as num?)?.toDouble() ?? 3;
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
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) => ElevageDomain
                        .placeableSceneItems
                        .contains(details.data),
                    onAcceptWithDetails: (details) =>
                        widget.onSceneItemDrop(details.data, zone.id),
                    builder: (context, candidates, _) => GestureDetector(
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
                                ElevagePresentation.environmentScale(widget
                                    .zoneEnvironments[zone.id]!['light']!),
                                candidates.isNotEmpty),
                            border: Border(
                                right: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: .32))),
                          ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('Z${entry.key + 1}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800)),
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
          if (widget.config.showProducerStockBubble)
            ...widget.slots.asMap().entries.map((entry) {
              final raw = entry.value;
              if (raw is! Map) return const SizedBox.shrink();
              final definition = widget.config
                  .installation(raw['definitionId'] as String? ?? '');
              if (definition?.productive != true) {
                return const SizedBox.shrink();
              }
              final stock = ((raw['productionState']
                      as Map?)?['availableByItemId'] as Map?) ??
                  const <dynamic, dynamic>{};
              final outputs = ElevageDomain.effectiveProducerOutputs(
                  raw, definition!.id, widget.config);
              return AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                alignment: <Alignment>[
                  const Alignment(-.75, .45),
                  const Alignment(-.25, .45),
                  const Alignment(.25, .45),
                  const Alignment(.75, .45),
                ][entry.key],
                child: _ProducerStockBubble(outputs: outputs, stock: stock),
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
            child: Transform.translate(
              offset: widget.ambientSignal?['body'] == 'SHIVER'
                  ? Offset(
                      _shiverOffset ? shiverAmplitude : -shiverAmplitude, 0)
                  : Offset.zero,
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
          ),
          if (widget.crystallizing ||
              widget.sleeping ||
              widget.requestSignal != null ||
              widget.ambientSignal != null ||
              widget.expressedNeed != null ||
              widget.action != 'IDLE')
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: _bubbleAlignment(widget.ptipoteZoneId),
              child: _StatusBubble(
                signal: widget.requestSignal ?? widget.ambientSignal?['icon'],
                action: widget.crystallizing
                    ? 'METAMORPHOSIS'
                    : widget.sleeping
                        ? 'SLEEP'
                        : widget.action,
                voice: widget.crystallizing
                    ? '…'
                    : widget.expressedNeed ?? widget.voice,
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

class _ProducerStockBubble extends StatelessWidget {
  const _ProducerStockBubble({required this.outputs, required this.stock});

  final List<ElevageProductionOutput> outputs;
  final Map stock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: outputs
                .map((output) => Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ElevagePresentation.itemIcon(output.resourceId),
                          size: 12),
                      const SizedBox(width: 2),
                      Text(
                        '${(stock[output.resourceId] as num?)?.toInt() ?? 0}/${output.maxLocalStock}',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ]))
                .toList(growable: false),
          ),
        ),
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

String _sceneActionForOutcome(String behavior, String itemId,
        {bool isStructural = false}) =>
    switch (behavior) {
      'RUSH_SHAKE' => 'EAT',
      'APPROACH' when isStructural => 'STRUCTURAL_ABSORB',
      'APPROACH' => 'EAT',
      'VIBRATE' => 'STRUCTURAL_ABSORB',
      'SNIFF' => 'INSPECT_ITEM',
      'STRUCTURAL_INTEREST' => 'THINK',
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
  // A P'TIPOTE portrait represents the individual and its biological stage,
  // never its mineral/vegetal/fungal structure icon.
  return Icons.pets_outlined;
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
                      '${signal == 'HUNGER' ? '🍽️ ' : ''}${voice ?? (signal == 'Pti ?' ? 'Pti ?' : _requestLabel(signal!))}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800))),
            ],
          ]),
        ),
      );
}

class _EnergySlotCard extends StatelessWidget {
  const _EnergySlotCard({required this.alcove, required this.controller});
  final Map alcove;
  final ElevageController controller;

  @override
  Widget build(BuildContext context) {
    if (alcove['biogeneratorSlot'] is Map) {
      return _BiogeneratorCard(alcove: alcove, controller: controller);
    }
    final battery = alcove['batterySlot'];
    final charge =
        battery is Map ? (battery['currentEnergy'] as num).toInt() : 0;
    final maxCharge =
        battery is Map ? (battery['maxEnergy'] as num).toInt() : 0;
    final stored = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    final cap = controller.config.energyStorageMax;
    return Card(
      child: ListTile(
        leading: Icon(battery is Map
            ? Icons.battery_charging_full_outlined
            : Icons.battery_unknown_outlined),
        title: const Text('Énergie'),
        subtitle: Text(battery is Map
            ? 'Bio-batterie · $charge / $maxCharge\n⚡ $stored / $cap'
            : 'Emplacement énergétique vide\n⚡ $stored / $cap'),
        isThreeLine: true,
        trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Installer une source d’énergie',
            onPressed: () => _showEnergyChoices(context, alcove, controller)),
      ),
    );
  }
}

Future<void> _showEnergyChoices(
  BuildContext context,
  Map alcove,
  ElevageController controller, {
  bool allowGenerator = true,
}) async {
  final batteries = controller.state!.data['batteryInventory'] as Map;
  final generators = controller.state!.data['biogeneratorInventory'] as Map;
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: ListView(shrinkWrap: true, children: <Widget>[
            const ListTile(
                leading: Icon(Icons.bolt_outlined),
                title: Text('Emplacement énergétique')),
            ...batteries.values.whereType<Map>().map((entry) => ListTile(
                leading: const Icon(Icons.battery_charging_full_outlined),
                title: const Text('Bio-batterie'),
                subtitle:
                    Text('${entry['currentEnergy']} / ${entry['maxEnergy']} ⚡'),
                onTap: () async {
                  await controller.insertBattery(
                      alcove['id'] as String, entry['instanceId'] as String);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                })),
            if (allowGenerator)
              ...generators.values.whereType<Map>().map((entry) => ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: const Text('Biogénérateur'),
                  subtitle: const Text('Infrastructure durable à cuves'),
                  onTap: () async {
                    await controller.installBiogenerator(
                        alcove['id'] as String, entry['instanceId'] as String);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  })),
          ])));
}

class _BiogeneratorCard extends StatelessWidget {
  const _BiogeneratorCard({required this.alcove, required this.controller});
  final Map alcove;
  final ElevageController controller;

  @override
  Widget build(BuildContext context) {
    final generator = alcove['biogeneratorSlot'];
    final inventory = controller.state!.data['biogeneratorInventory'] as Map;
    if (generator is! Map) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: const Text('Biogénérateur'),
          subtitle:
              const Text('Infrastructure durable · aucune cuve installée'),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Installer un Biogénérateur',
            onPressed: inventory.isEmpty
                ? null
                : () => _selectGenerator(context, inventory),
          ),
        ),
      );
    }
    final tanks = generator['tanks'] as Map? ?? const <dynamic, dynamic>{};
    final caps =
        ElevageDomain.biogeneratorTankCapacities(generator, controller.config);
    final profile =
        ElevageDomain.biogeneratorCycleProfile(generator, controller.config);
    final stored = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    final progress = ElevageDomain.biogeneratorCycleProgress(
        generator, alcove, controller.now, controller.config);
    final modules =
        ElevageDomain.installedModules(generator, controller.config);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Biogénérateur',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              Text('⚡ $stored / ${controller.config.energyStorageMax}'),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(child: _tank(context, 'ORGANIC', tanks, caps)),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(value: progress),
                          const Icon(Icons.bolt_outlined, size: 19),
                        ]))),
                Expanded(child: _tank(context, 'MINERAL', tanks, caps)),
              ]),
              const SizedBox(height: 6),
              Text(
                  'Production auto · cycle ${controller.config.biogeneratorCycleSeconds} s · ${profile['organic']} Organique + ${profile['mineral']} Minéral → ${profile['energy']} ⚡'),
              Text(
                  'Modules : ${modules.isEmpty ? 'aucun' : modules.map((m) => (m['definition'] as ElevageModuleDefinition?)?.label ?? 'Module').join(' · ')}'),
              TextButton.icon(
                  onPressed: () => _selectModule(context, generator, modules),
                  icon: const Icon(Icons.extension_outlined),
                  label: const Text('Modules')),
              Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                      onPressed: () => _showEnergyChoices(
                          context, alcove, controller, allowGenerator: false),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(alcove['batterySlot'] is! Map
                          ? 'Bio-batterie de secours'
                          : 'Secours inséré'))),
            ]),
      ),
    );
  }

  Widget _tank(BuildContext context, String resource, Map tanks,
      Map<String, int> capacities) {
    final key = resource.toLowerCase();
    final current = (tanks[key] as num?)?.toInt() ?? 0;
    return OutlinedButton(
      onPressed: () => _transfer(context, resource),
      child: Text(
          '${resource == 'ORGANIC' ? 'Organique' : 'Minéral'}\n$current / ${capacities[key]}',
          textAlign: TextAlign.center),
    );
  }

  void _selectGenerator(BuildContext context, Map inventory) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
            shrinkWrap: true,
            children: inventory.values
                .whereType<Map>()
                .map((entry) => ListTile(
                      leading: const Icon(Icons.memory_outlined),
                      title: const Text('Biogénérateur'),
                      onTap: () async {
                        await controller.installBiogenerator(
                            alcove['id'] as String,
                            entry['instanceId'] as String);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ))
                .toList()),
      ),
    );
  }

  void _transfer(BuildContext context, String resource) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, children: <Widget>[
        ListTile(
            title: Text(
                'Cuve ${resource == 'ORGANIC' ? 'Organique' : 'Minéral'}')),
        for (final amount in <int>[1, 5, 10])
          ListTile(
            title: Text('Transférer $amount'),
            onTap: () async {
              await controller.transferBiogeneratorFuel(
                  alcove['id'] as String, resource, amount);
              if (sheetContext.mounted && controller.error == null) {
                Navigator.pop(sheetContext);
              }
            },
          ),
      ])),
    );
  }

  void _selectModule(BuildContext context, Map generator,
      List<Map<String, dynamic>> installed) {
    final inventory = controller.state!.data['moduleInventory'] as Map;
    final available = inventory.values.whereType<Map>().where((entry) {
      final definition =
          controller.config.module(entry['moduleId'] as String? ?? '');
      return definition != null &&
          controller.config
              .modulesFor('BIOGENERATOR')
              .allowedModuleIds
              .contains(definition.id);
    }).toList();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, children: <Widget>[
        ...installed.map((entry) => ListTile(
              title: Text(
                  (entry['definition'] as ElevageModuleDefinition?)?.label ??
                      'Module'),
              trailing: const Icon(Icons.remove_circle_outline),
              onTap: () async {
                await controller.removeBiogeneratorModule(
                    alcove['id'] as String, entry['instanceId'] as String);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            )),
        if (installed.length <
            controller.config.modulesFor('BIOGENERATOR').moduleSlots)
          ...available.map((entry) {
            final definition =
                controller.config.module(entry['moduleId'] as String)!;
            return ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(definition.label),
              subtitle: Text(definition.description),
              onTap: () async {
                await controller.installBiogeneratorModule(
                    alcove['id'] as String, entry['instanceId'] as String);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            );
          }),
      ])),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.individual, required this.controller});
  final Map individual;
  final ElevageController controller;

  @override
  Widget build(BuildContext context) {
    final tracker =
        ElevageDomain.trackerProfession(individual, controller.config);
    final level = (tracker['level'] as num).toInt();
    final xp = (tracker['xp'] as num).toInt();
    final next =
        level < 3 ? controller.config.trackerThreshold(level + 1) : null;
    final endurance = ElevageDomain.explorationEndurance(
        individual, controller.now, controller.config);
    final current = (endurance['current'] as num?)?.toInt() ?? 0;
    final maximum = controller.config.explorationInt('ptipoteStaminaMax', 10);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('👣', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text('Pisteur $level',
                style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 4),
          Text(next == null
              ? '$xp XP · niveau maximum · transport +${controller.config.trackerCarryBonus(level)}'
              : '$xp / $next XP · transport +${controller.config.trackerCarryBonus(level)}'),
          const SizedBox(height: 10),
          Text('🥾 Endurance d’exploration · $current / $maximum'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: maximum == 0 ? 0 : current / maximum),
          const SizedBox(height: 3),
          Text(
              '+1 / ${controller.config.explorationInt('ptipoteStaminaRegenMinutes', 5)} min',
              style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }
}

class _LoanOfferCard extends StatelessWidget {
  const _LoanOfferCard({
    required this.controller,
    required this.individualId,
    required this.offer,
  });
  final ElevageController controller;
  final String individualId;
  final Map offer;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Prêt du Refuge',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                    'Choisissez une structure adaptée pour cette période juvénile.'),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: (offer['choices'] as List)
                        .whereType<String>()
                        .map((id) => OutlinedButton.icon(
                            icon:
                                Icon(ElevagePresentation.installationIcon(id)),
                            label:
                                Text(ElevagePresentation.installationLabel(id)),
                            onPressed: () => controller.chooseJuvenileLoan(
                                individualId, id)))
                        .toList()),
              ]),
        ),
      );
}

String _requestLabel(String request) => switch (request) {
      'HUNGER' => '🍽️',
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
      'SNIFF' => Icons.sensors_outlined,
      'STRUCTURAL_INTEREST' => Icons.auto_awesome_outlined,
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
      'COLD' => Icons.ac_unit_outlined,
      'HOT' => Icons.water_drop_outlined,
      'MORE_LIGHT' => Icons.wb_sunny_outlined,
      'LESS_LIGHT' => Icons.nights_stay_outlined,
      'DRY' => Icons.water_drop_outlined,
      'WET' => Icons.umbrella_outlined,
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
    Map<String, int> currentEnvironment,
    {Map? instance}) async {
  final recipe = config.recipes
      .where((entry) => entry.installationId == definition.id)
      .firstOrNull;
  final effective = instance == null
      ? <String, int>{
          'light': definition.light,
          'temperature': definition.temperature,
          'humidity': definition.humidity,
        }
      : ElevageDomain.effectiveEnvironmentalEffects(
          instance, definition, config);
  final after = <String, int>{
    'light': currentEnvironment['light']! + effective['light']!,
    'temperature':
        currentEnvironment['temperature']! + effective['temperature']!,
    'humidity': currentEnvironment['humidity']! + effective['humidity']!,
  };
  final recipeText = recipe == null
      ? 'Recette à définir'
      : <String>[
          if (recipe.organic > 0) '${recipe.organic} Organique',
          if (recipe.mineral > 0) '${recipe.mineral} Minéral',
          ...recipe.special.entries.map((entry) =>
              '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}'),
        ].join(' · ');
  final consumption = config.consumptionFor(definition.id);
  final active =
      instance == null || ElevageDomain.structureIsActive(instance, config);
  final maintenance =
      instance == null ? null : instance['maintenanceState'] as Map?;
  final pauseReason =
      maintenance?['reason'] as String? ?? 'Ressources insuffisantes';
  final consumptionText = switch (consumption.mode) {
    'ENERGY' =>
      '${consumption.energyCost} Énergie / ${consumption.consumptionIntervalSeconds}s',
    'DIRECT_RESOURCE' ||
    'MULTI_RESOURCE' =>
      '${consumption.resourceCosts.entries.map((entry) => '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}').join(' · ')} / ${consumption.consumptionIntervalSeconds}s',
    _ => 'Aucun entretien',
  };
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
              if (consumption.mode != 'NONE') ...<Widget>[
                const SizedBox(height: 12),
                Text(active ? 'Actif' : 'En pause',
                    style: Theme.of(sheetContext).textTheme.titleSmall),
                Text(active
                    ? 'Consomme : $consumptionText'
                    : '$pauseReason\nConsomme : $consumptionText'),
              ],
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

String _weatherLabel(String type) => switch (type) {
      'LIGHT_RAIN' => 'Petite pluie',
      'HEAVY_RAIN' => 'Forte pluie',
      _ => 'Beau temps',
    };

String _weatherEmoji(String type) => switch (type) {
      'LIGHT_RAIN' => '🌦️',
      'HEAVY_RAIN' => '🌧️',
      _ => '☀️',
    };

Future<void> _openCooking(
    BuildContext context, ElevageController controller, Map individual) async {
  final selected = <String?>[null, null, null];
  var useWater = false;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (_, setSheetState) {
            final state = controller.state!;
            final special = state.data['inventory']['special'] as Map;
            final foods = special.entries
                .where((entry) =>
                    (entry.value as num?)?.toInt() != null &&
                    (entry.value as num).toInt() > 0 &&
                    controller.config.foodSatietyValue(entry.key as String) > 0)
                .map((entry) => entry.key as String)
                .toList();
            final complete = selected.every((item) => item != null);
            final portions = useWater
                ? controller.config.wetPortions
                : controller.config.dryPortions;
            final total = selected.whereType<String>().fold<int>(
                    0,
                    (sum, item) =>
                        sum + controller.config.foodSatietyValue(item)) +
                portions *
                    (useWater
                        ? controller.config.wetBonusPerPortion
                        : controller.config.dryBonusPerPortion);
            return SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('Cuisine',
                              style:
                                  Theme.of(sheetContext).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          for (var index = 0; index < 3; index++)
                            DropdownButtonFormField<String>(
                              initialValue: selected[index],
                              decoration: InputDecoration(
                                  labelText: 'Ingrédient ${index + 1}'),
                              items: foods
                                  .map((item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(
                                          '${ElevagePresentation.itemLabel(item)} · ${special[item]}')))
                                  .toList(),
                              onChanged: (value) =>
                                  setSheetState(() => selected[index] = value),
                            ),
                          SwitchListTile(
                              value: useWater,
                              title: const Text('Ajouter de l’eau'),
                              subtitle: Text(
                                  '💧 ${ElevageDomain.waterTank(state).toStringAsFixed(1)}/${controller.config.waterTankCapacity}'),
                              onChanged: (value) =>
                                  setSheetState(() => useWater = value)),
                          ListTile(
                              title: Text('Prévision : $portions portions'),
                              subtitle: Text(
                                  'Satiété totale : $total · moyenne : ${(total / portions).toStringAsFixed(1)}')),
                          FilledButton(
                              onPressed: !complete
                                  ? null
                                  : () async {
                                      await controller.cookMeal(
                                          selected.cast<String>(), useWater);
                                      if (sheetContext.mounted) {
                                        setSheetState(() {});
                                      }
                                    },
                              child: const Text('Cuisiner')),
                          const Divider(height: 28),
                          ...ElevageDomain.cookedMeals(state)
                              .map((meal) => ListTile(
                                    leading:
                                        const Icon(Icons.restaurant_outlined),
                                    title: Text(
                                        'Plat cuisiné · ${meal['remainingPortions']}/${meal['portionCount']}'),
                                    subtitle: Text(
                                        (meal['ingredientIds'] as List)
                                            .cast<String>()
                                            .map(ElevagePresentation.itemLabel)
                                            .join(' + ')),
                                    trailing: TextButton(
                                        onPressed: () async {
                                          await controller.offerCookedMeal(
                                              individual['id'] as String,
                                              meal['instanceId'] as String);
                                          if (sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                        child: const Text('Donner')),
                                  )),
                        ])));
          }));
}

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
          'ENERGY': (generic['energy'] as num?)?.toInt() ?? 0,
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
                    title: const Text('Réserve du Refuge'),
                    subtitle: Text(
                        '${state.data['inventory']['bioPiles']} Bio-piles')),
                ListTile(
                    leading: const Icon(Icons.battery_charging_full_outlined),
                    title: const Text('Bio-piles disponibles'),
                    subtitle: Text(
                        '${(state.data['batteryInventory'] as Map).length} · alimentent une Alcôve localement')),
                if ((state.data['moduleInventory'] as Map).isNotEmpty)
                  ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('Modules'),
                      subtitle: Text((state.data['moduleInventory'] as Map)
                          .values
                          .whereType<Map>()
                          .map((entry) =>
                              controller.config
                                  .module(entry['moduleId'] as String? ?? '')
                                  ?.label ??
                              'Module')
                          .join(' · '))),
                if (items.keys.any((itemId) =>
                    controller.config.recycleRule(itemId)?.recyclable == true))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.recycling_outlined),
                      label: const Text('Recycler'),
                      onPressed: () => _showRecycler(
                          sheetContext, controller, items, setSheetState),
                    ),
                  ),
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
                              'Votre réserve est vide. Lancez une Exploration pour trouver des objets.'))),
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
                      final canPlace = ElevageDomain.placeableSceneItems
                          .contains(stack.itemId);
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

Future<void> _showRecycler(BuildContext context, ElevageController controller,
    Map<String, int> items, StateSetter refreshReserve) async {
  final recyclable = items.entries
      .where((entry) =>
          controller.config.recycleRule(entry.key)?.recyclable == true)
      .toList(growable: false);
  if (recyclable.isEmpty) return;
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const ListTile(
                  leading: Icon(Icons.recycling_outlined),
                  title: Text('Recycleur'),
                  subtitle: Text(
                      'Une ressource spécifique devient une matière générique.')),
              ...recyclable.map((entry) {
                final rule = controller.config.recycleRule(entry.key)!;
                final output = rule.recycleOutputType!;
                return ListTile(
                  leading: Icon(ElevagePresentation.itemIcon(entry.key)),
                  title: Text(ElevagePresentation.itemLabel(entry.key)),
                  subtitle: Text(
                      '${entry.value} disponible(s) · 1 → ${rule.recycleOutputQuantity} ${ElevagePresentation.itemLabel(output)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final quantity = await _numberDialog(
                        sheetContext,
                        'Recycler ${ElevagePresentation.itemLabel(entry.key)}',
                        1);
                    if (!sheetContext.mounted || quantity == null) return;
                    final safeQuantity = quantity.clamp(1, entry.value);
                    var confirmed = true;
                    if (safeQuantity > 1) {
                      confirmed = await showDialog<bool>(
                            context: sheetContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Confirmer le recyclage'),
                              content: Text(
                                  '${ElevagePresentation.itemLabel(entry.key)} ×$safeQuantity\n→ ${ElevagePresentation.itemLabel(output)} ×${safeQuantity * rule.recycleOutputQuantity}'),
                              actions: <Widget>[
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('Annuler')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('Recycler')),
                              ],
                            ),
                          ) ==
                          true;
                    }
                    if (!confirmed) return;
                    await controller.recycle(entry.key, safeQuantity);
                    if (!sheetContext.mounted) return;
                    if (controller.error != null) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                          content: Text(ElevagePresentation.friendlyError(
                              controller.error))));
                      return;
                    }
                    refreshReserve(() {});
                    Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          )));
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
    final gesture = InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: tile);
    if (!enabled) return gesture;
    return LongPressDraggable<String>(
      data: stack.itemId,
      feedback: Material(
          color: Colors.transparent,
          child: Icon(ElevagePresentation.itemIcon(stack.itemId), size: 48)),
      // Tap remains the accessibility fallback; an actual drop is accepted
      // by the scene DragTarget and never starts placement for unsupported IDs.
      onDragStarted: onLongPress,
      child: gesture,
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
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SegmentedButton<String>(
                                  segments: const <ButtonSegment<String>>[
                                    ButtonSegment(
                                        value: 'STRUCTURE',
                                        label: Text('Structures')),
                                    ButtonSegment(
                                        value: 'MEUBLE',
                                        label: Text('Meubles')),
                                    ButtonSegment(
                                        value: 'DECORATION',
                                        label: Text('Décorations')),
                                    ButtonSegment(
                                        value: 'MODULE',
                                        label: Text('Modules')),
                                    ButtonSegment(
                                        value: 'BIOGENERATOR',
                                        label: Text('Énergie')),
                                  ],
                                  selected: <String>{
                                    category
                                  },
                                  onSelectionChanged: (value) => setLocal(
                                      () => category = value.single)))),
                      if (category == 'MODULE')
                        ...controller.config.modules.values
                            .where((module) => module.enabled)
                            .map((module) => ListTile(
                                  leading: const Icon(Icons.extension_outlined),
                                  title: Text(module.label),
                                  subtitle: Text(
                                      '${module.description}\n${module.organicCost} Organique · ${module.mineralCost} Minéral',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                  isThreeLine: true,
                                  trailing: SizedBox(
                                      width: 100,
                                      child: FilledButton(
                                          onPressed: () async {
                                            await controller
                                                .craftModule(module);
                                            if (sheetContext.mounted &&
                                                controller.error == null) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(
                                                          '${module.label} a été bio-fabriqué.')));
                                              Navigator.pop(sheetContext);
                                            }
                                          },
                                          child: const Text('Fabriquer'))),
                                )),
                      if (category == 'BIOGENERATOR') ...<Widget>[
                        const ListTile(
                          leading: Icon(Icons.battery_charging_full_outlined),
                          title: Text('Bio-batterie'),
                          subtitle: Text(
                              'Source de départ et de secours, fournie par le Refuge. Elle s’installe dans l’emplacement énergétique.'),
                          isThreeLine: true,
                        ),
                        ListTile(
                          leading: const Icon(Icons.memory_outlined),
                          title: const Text('Biogénérateur'),
                          subtitle: const Text(
                              '5 Organique · 5 Minéral · 1 Champignon · 1 Algue · 5 Sel\nInfrastructure durable à cuves Organique et Minéral.'),
                          isThreeLine: true,
                          trailing: FilledButton(
                            onPressed: () async {
                              await controller.craftBiogenerator();
                              if (sheetContext.mounted &&
                                  controller.error == null) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: const Text('Créer'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.battery_saver_outlined),
                          title: const Text('Batterie exportable'),
                          subtitle: const Text(
                              '1 Organique · 1 Minéral · 100 Énergie locale\nValeur future : 10 Bio-piles.'),
                          isThreeLine: true,
                          trailing: FilledButton(
                            onPressed: () async {
                              await controller.craftBatteryExport(alcoveId);
                              if (sheetContext.mounted &&
                                  controller.error == null) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: const Text('Créer'),
                          ),
                        ),
                      ],
                      if (category == 'STRUCTURE')
                        ..._structureCatalogGroups(controller.config)
                            .entries
                            .map((group) {
                          final recipes = group.value;
                          return ExpansionTile(
                              leading: Icon(_structureCategoryIcon(group.key)),
                              title: Text(group.key),
                              children: recipes
                                  .map((recipe) => _biofabricatorRecipeTile(
                                      sheetContext: sheetContext,
                                      controller: controller,
                                      state: state,
                                      alcoveId: alcoveId,
                                      recipe: recipe))
                                  .toList(growable: false));
                        }),
                      if (category != 'MODULE' &&
                          category != 'BIOGENERATOR' &&
                          category != 'STRUCTURE')
                        ...controller.config.recipes
                            .where((recipe) =>
                                controller.config
                                    .installation(recipe.installationId)
                                    ?.category ==
                                category)
                            .map((recipe) => _biofabricatorRecipeTile(
                                sheetContext: sheetContext,
                                controller: controller,
                                state: state,
                                alcoveId: alcoveId,
                                recipe: recipe))
                    ])));
      });
}

Map<String, List<ElevageRecipe>> _structureCatalogGroups(ElevageConfig config) {
  const order = <String>[
    'Énergie',
    'Chauffage',
    'Ventilation',
    'Lumière',
    'Ombre',
    'Humidité',
    'Structuration',
    'Production',
    'Activité',
    'Autres'
  ];
  final groups = <String, List<ElevageRecipe>>{};
  for (final recipe in config.recipes) {
    final definition = config.installation(recipe.installationId);
    if (definition?.category != 'STRUCTURE') continue;
    final categories = <String>{};
    if (definition!.id == 'VENTILATION' || definition.humidity < 0) {
      categories.add('Ventilation');
    }
    if (definition.temperature > 0) categories.add('Chauffage');
    if (definition.light > 0) categories.add('Lumière');
    if (definition.light < 0) categories.add('Ombre');
    if (definition.humidity > 0) categories.add('Humidité');
    if (definition.productive) categories.add('Production');
    if (definition.resonanceFamily != null ||
        definition.id.startsWith('FORMATION_') ||
        definition.id == 'BOSQUET_SYMBIOTIQUE' ||
        definition.id == 'COLONIE_MYCELIENNE') {
      categories.add('Structuration');
    }
    if (definition.activity != null) categories.add('Activité');
    if (categories.isEmpty) categories.add('Autres');
    for (final category in categories) {
      (groups[category] ??= <ElevageRecipe>[]).add(recipe);
    }
  }
  return <String, List<ElevageRecipe>>{
    for (final category in order)
      if ((groups[category] ?? const <ElevageRecipe>[]).isNotEmpty)
        category: groups[category]!,
  };
}

IconData _structureCategoryIcon(String category) => switch (category) {
      'Énergie' => Icons.bolt_outlined,
      'Chauffage' => Icons.local_fire_department_outlined,
      'Ventilation' => Icons.air_outlined,
      'Lumière' => Icons.light_mode_outlined,
      'Ombre' => Icons.dark_mode_outlined,
      'Humidité' => Icons.water_drop_outlined,
      'Production' => Icons.agriculture_outlined,
      'Structuration' => Icons.auto_awesome_outlined,
      'Activité' => Icons.sports_esports_outlined,
      _ => Icons.widgets_outlined,
    };

Widget _biofabricatorRecipeTile({
  required BuildContext sheetContext,
  required ElevageController controller,
  required ElevageSave state,
  required String alcoveId,
  required ElevageRecipe recipe,
}) {
  final known = ElevageDomain.recipeKnown(state, recipe);
  final definition = controller.config.installation(recipe.installationId);
  final environment =
      ElevageDomain.environment(state, alcoveId, controller.config);
  return ListTile(
      isThreeLine: known,
      minLeadingWidth: 28,
      leading: Icon(definition == null
          ? Icons.help_outline
          : ElevagePresentation.installationIcon(definition.id)),
      title: Text(known ? recipe.label : 'Recette inconnue',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: known
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(<String>[
                if (recipe.organic > 0) '${recipe.organic} Organique',
                if (recipe.mineral > 0) '${recipe.mineral} Minéral',
                ...recipe.special.entries.map((entry) =>
                    '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}'),
              ].join(' · ')),
              if (definition != null)
                Text(definition.description,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              if (definition != null)
                Text(_installationMechanics(definition, controller.config),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              if (definition != null)
                Text(_installationImpactSentence(definition),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic)),
            ])
          : null,
      onTap: !known || definition == null
          ? null
          : () => _showInstallationDetails(
              sheetContext, controller.config, definition, environment),
      trailing: known
          ? SizedBox(
              width: 100,
              child: FilledButton(
                  onPressed: () async {
                    await controller.craft(recipe);
                    if (sheetContext.mounted && controller.error == null) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                          content:
                              Text('${recipe.label} a été bio-fabriqué.')));
                      Navigator.pop(sheetContext);
                    }
                  },
                  child: const Text('Fabriquer')))
          : null);
}

String _installationMechanics(
    ElevageInstallationDefinition definition, ElevageConfig config) {
  final mechanics = <String>[];
  final family = definition.resonanceFamily ??
      (definition.resonanceMaterial == null ? null : 'MINERAL');
  if (family != null) {
    mechanics.add('Résonance : $family compatible · passif');
  }
  final outputs = config.outputsFor(definition.id);
  if (outputs.isNotEmpty) {
    mechanics.add(
        'Produit : ${outputs.map((output) => '${ElevagePresentation.itemLabel(output.resourceId)} ${output.maxLocalStock}/${output.maxLocalStock} · ${output.productionSeconds}s').join(', ')}');
  }
  final consumption = config.consumptionFor(definition.id);
  if (consumption.enabled && consumption.mode != 'NONE') {
    if (consumption.mode == 'ENERGY') {
      mechanics.add(
          'Consomme : ${consumption.energyCost} Énergie / ${consumption.consumptionIntervalSeconds}s');
    } else if (consumption.resourceCosts.isNotEmpty) {
      mechanics.add(
          'Consomme : ${consumption.resourceCosts.entries.map((entry) => '${entry.value} ${ElevagePresentation.itemLabel(entry.key)}').join(' · ')} / ${consumption.consumptionIntervalSeconds}s');
    }
  }
  return mechanics.isEmpty ? 'Passif' : mechanics.join('\n');
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

String _explorationTimer(int milliseconds) {
  final seconds = max(0, milliseconds ~/ 1000);
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _ExplorationEnduranceBar extends StatelessWidget {
  const _ExplorationEnduranceBar(
      {required this.current,
      required this.maximum,
      required this.label,
      required this.regenMinutes});
  final int current;
  final int maximum;
  final String label;
  final int regenMinutes;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🥾 $label · $current / $maximum'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: maximum == 0 ? 0 : current / maximum),
        const SizedBox(height: 3),
        Text('+1 / $regenMinutes min', style: const TextStyle(fontSize: 11)),
      ]));
}

Future<void> _exploration(
    BuildContext context, ElevageController controller) async {
  await controller.refreshExploration();
  if (!context.mounted || controller.state == null) return;
  final exploration = ElevageDomain.explorationState(controller.state!);
  final run = exploration['activeRun'] as Map?;
  if (run?['status'] == 'READY') {
    await _showExplorationResult(context, controller, run!);
    return;
  }
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const ListTile(
                  leading: Icon(Icons.explore_outlined),
                  title: Text('Exploration'),
                  subtitle: Text('Choisissez un milieu depuis le Refuge.')),
              _ExplorationEnduranceBar(
                  current: (exploration['stamina'] as num?)?.toInt() ?? 0,
                  maximum: controller.config.explorationInt('playerStaminaMax',
                      controller.config.explorationInt('playerStaminaMax', 10)),
                  label: 'Joueur · Endurance d’exploration',
                  regenMinutes: controller.config
                      .explorationInt('playerStaminaRegenMinutes', 5)),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                childAspectRatio: 1.45,
                children: <Map<String, String>>[
                  <String, String>{'id': 'BASE', 'label': 'Base', 'icon': '⌂'},
                  <String, String>{
                    'id': 'FORET_HUMIDE',
                    'label': 'Forêt humide',
                    'icon': '🌲'
                  },
                  <String, String>{
                    'id': 'LITTORAL',
                    'label': 'Littoral',
                    'icon': '🌊'
                  },
                  <String, String>{
                    'id': 'COLLINE',
                    'label': 'Colline',
                    'icon': '⛰️'
                  },
                ]
                    .map((tile) => Card(
                          child: InkWell(
                            onTap: tile['id'] == 'BASE'
                                ? null
                                : () => _explorationBiome(
                                    sheetContext, controller, tile['id']!),
                            child: Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                  Text(tile['icon']!,
                                      style: const TextStyle(fontSize: 24)),
                                  const SizedBox(height: 4),
                                  Text(tile['label']!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ])),
                          ),
                        ))
                    .toList(),
              ),
              if (run?['status'] == 'IN_PROGRESS')
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Sortie en cours · ⏱ ${_explorationTimer(max(0, (run!['endsAt'] as num).toInt() - controller.now))}')),
            ]),
          )));
}

Future<void> _explorationBiome(
    BuildContext context, ElevageController controller, String biomeId) async {
  await controller.refreshExploration();
  if (!context.mounted || controller.state == null) return;
  final exploration = ElevageDomain.explorationState(controller.state!);
  final sectors = exploration['sectors'] as Map;
  final stamina = (exploration['stamina'] as num?)?.toInt() ?? 0;
  final run = exploration['activeRun'] as Map?;
  final title = switch (biomeId) {
    'FORET_HUMIDE' => 'Forêt humide',
    'LITTORAL' => 'Littoral',
    _ => 'Colline',
  };
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: ListView(shrinkWrap: true, children: <Widget>[
            ListTile(
                title: Text(title),
                subtitle: Text(
                    '🥾 Endurance $stamina/${controller.config.explorationInt('playerStaminaMax', 10)} · ${controller.config.explorationInt('baseCarrySlots', 3)} slots · +1 / ${controller.config.explorationInt('playerStaminaRegenMinutes', 5)} min')),
            ...ElevageDomain.explorationSectorsForBiome(
                    biomeId, controller.config)
                .map((definition) {
              final sector = sectors[definition['id']] as Map;
              final discovered = sector['discovered'] == true;
              final active = run?['sectorId'] == definition['id'] &&
                  run?['status'] == 'IN_PROGRESS';
              return ListTile(
                leading: Icon(discovered ? Icons.explore : Icons.help_outline),
                title: Text(discovered
                    ? definition['label'] as String
                    : 'Secteur inconnu'),
                subtitle: discovered
                    ? Text(
                        'Organique ${(sector['organic'] as num).toInt()} % · Minéral ${(sector['mineral'] as num).toInt()}${active ? ' · en cours' : ''}')
                    : const Text(
                        'Lancez une première sortie pour le découvrir.'),
                trailing: FilledButton(
                  onPressed: run != null && run['status'] != 'CLAIMED' ||
                          stamina <
                              controller.config
                                  .explorationInt('playerStaminaCost', 1)
                      ? null
                      : () async {
                          final companionId = await _pickExplorationCompanion(
                              sheetContext, controller);
                          if (!sheetContext.mounted || companionId == null) {
                            return;
                          }
                          await controller.startExploration(
                              definition['id'] as String,
                              companionPtipoteId:
                                  companionId.isEmpty ? null : companionId);
                          if (sheetContext.mounted &&
                              controller.error == null) {
                            Navigator.pop(sheetContext);
                          }
                        },
                  child: const Text('Explorer'),
                ),
              );
            }),
          ])));
}

/// Returns an empty id for a solo departure, null when the user cancels.
Future<String?> _pickExplorationCompanion(
    BuildContext context, ElevageController controller) async {
  final state = controller.state!;
  final allIds =
      state.data['activeIndividualIds'] as List? ?? const <dynamic>[];
  final individuals =
      state.data['individuals'] as Map? ?? const <dynamic, dynamic>{};
  final candidates = allIds
      .whereType<String>()
      .map((id) => individuals[id])
      .whereType<Map>()
      .toList(growable: false);
  return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
              child: ListView(shrinkWrap: true, children: <Widget>[
            const ListTile(
                leading: Icon(Icons.hiking_outlined),
                title: Text('Compagnon d’exploration'),
                subtitle: Text('Partez seul ou avec un P’TIPOTE.')),
            ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Partir seul'),
                subtitle: const Text('3 slots de récolte de base.'),
                onTap: () => Navigator.pop(sheetContext, '')),
            ...candidates.map((individual) {
              final stage = (individual['lifecycle'] as Map)['stage'] as String;
              final endurance = ElevageDomain.explorationEndurance(
                  individual, controller.now, controller.config);
              final tracker = ElevageDomain.trackerProfession(
                  individual, controller.config);
              final level = (tracker['level'] as num).toInt();
              final xp = (tracker['xp'] as num).toInt();
              final next = level < 3
                  ? controller.config.trackerThreshold(level + 1)
                  : null;
              final eligible = ElevageDomain.canAccompanyExploration(
                  individual, controller.now, controller.config);
              return ListTile(
                  enabled: eligible,
                  leading: const Icon(Icons.pets_outlined),
                  title: Text(individual['name'] as String),
                  subtitle: Text(stage == 'BABY'
                      ? 'Trop jeune pour explorer.'
                      : '${individual['family']} · $stage\n👣 Pisteur $level · ${next == null ? '$xp XP' : '$xp / $next XP'} · 🥾 ${(endurance['current'] as num).toInt()}/${controller.config.explorationInt('ptipoteStaminaMax', 10)} · Transport +${controller.config.trackerCarryBonus(level)}'),
                  isThreeLine: stage != 'BABY',
                  onTap: eligible
                      ? () => Navigator.pop(
                          sheetContext, individual['id'] as String)
                      : null);
            }),
          ])));
}

Future<void> _showExplorationResult(
    BuildContext context, ElevageController controller, Map run) async {
  final companionId = run['companionPtipoteId'] as String?;
  final companion = companionId == null
      ? null
      : (controller.state!.data['individuals'] as Map)[companionId] as Map?;
  final playerEndurance =
      (ElevageDomain.explorationState(controller.state!)['stamina'] as num?)
              ?.toInt() ??
          0;
  final companionEndurance =
      ((companion?['explorationStamina'] as Map?)?['current'] as num?)
              ?.toInt() ??
          0;
  final slots =
      (run['slots'] as num?)?.toInt() ?? (run['results'] as List).length;
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Exploration terminée'),
            content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('Résultats de vos $slots slots :'),
              if (companion != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('${companion['name']} vous a accompagné.'),
                Text(
                    '🥾 Joueur $playerEndurance/${controller.config.explorationInt('playerStaminaMax', 10)} · ${companion['name']} $companionEndurance/${controller.config.explorationInt('ptipoteStaminaMax', 10)}'),
                const Text('👣 +10 XP Pisteur'),
                if (run['trackerLevelAfter'] is num &&
                    run['trackerLevelAfter'] != run['trackerLevelBefore'])
                  Text('👣 Pisteur ${run['trackerLevelAfter']} atteint !'),
              ],
              const SizedBox(height: 8),
              ...(run['results'] as List).whereType<Map>().map((result) {
                final resource = result['resourceId'] as String? ?? 'EMPTY';
                return ListTile(
                    leading: Icon(resource == 'EMPTY'
                        ? Icons.remove_circle_outline
                        : ElevagePresentation.itemIcon(resource)),
                    title: Text(resource == 'EMPTY'
                        ? 'Aucune ressource'
                        : '${ElevagePresentation.itemLabel(resource)} ×1'));
              }),
            ]),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Plus tard')),
              FilledButton(
                  onPressed: () async {
                    await controller.claimExploration();
                    if (dialogContext.mounted && controller.error == null) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Récupérer')),
            ],
          ));
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
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!ElevageDomain.metamorphosisAvailable(
      controller.state!, id, now, controller.config)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Les observations requises ne sont pas encore réunies.')));
    return;
  }
  final individual = (controller.state!.data['individuals'] as Map)[id] as Map;
  await showDialog<void>(
      context: context,
      builder: (_) => _TamTamDialog(
          controller: controller,
          individualId: id,
          stage: (individual['lifecycle'] as Map)['stage'] as String,
          family: individual['family'] as String));
}

class _TamTamDialog extends StatefulWidget {
  const _TamTamDialog({
    required this.controller,
    required this.individualId,
    required this.stage,
    required this.family,
  });

  final ElevageController controller;
  final String individualId;
  final String stage;
  final String family;

  @override
  State<_TamTamDialog> createState() => _TamTamDialogState();
}

class _TamTamDialogState extends State<_TamTamDialog> {
  late final int _startedAt;
  Timer? _ticker;
  int _elapsedMs = 0;
  final Map<int, String> _grades = <int, String>{};
  String? _feedback;
  bool _finishing = false;

  ElevageConfig get _config => widget.controller.config;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _ticker = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted) return;
      setState(() =>
          _elapsedMs = DateTime.now().millisecondsSinceEpoch - _startedAt);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _closestBeat() {
    var closest = 0;
    var delta = 1 << 30;
    for (var index = 0; index < _config.tamTamTotalBeats; index++) {
      final next =
          (_elapsedMs - ElevageDomain.tamTamBeatTargetMs(index, _config)).abs();
      if (next < delta) {
        closest = index;
        delta = next;
      }
    }
    return closest;
  }

  Future<void> _tapBeat() async {
    if (_finishing) return;
    final beat = _closestBeat();
    if (_grades.containsKey(beat)) {
      setState(() => _feedback = 'Ce battement est déjà joué.');
      return;
    }
    final grade = ElevageDomain.tamTamTapGrade(_elapsedMs, beat, _config);
    setState(() {
      _grades[beat] = grade;
      _feedback = switch (grade) {
        'PERFECT' => 'Parfait',
        'GOOD' => 'Bien',
        _ => 'Raté',
      };
    });
    if (!ElevageDomain.tamTamSucceeded(_grades.values, _config)) return;
    setState(() => _finishing = true);
    try {
      await widget.controller.metamorphose(widget.individualId);
      if (mounted) Navigator.of(context).pop();
    } on StateError {
      if (mounted) {
        setState(() {
          _finishing = false;
          _feedback = 'Les prérequis ne sont plus réunis.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final interval = _config.tamTamBeatIntervalMs;
    final nearest = _closestBeat();
    final pulseDelta =
        (_elapsedMs - ElevageDomain.tamTamBeatTargetMs(nearest, _config)).abs();
    final pulsing = pulseDelta <= min(180, interval ~/ 3);
    final completed = _grades.values
        .where((grade) => grade == 'PERFECT' || grade == 'GOOD')
        .length;
    return AlertDialog(
      title: const Text('Métamorphose — Tam Tam'),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        AnimatedScale(
          scale: pulsing ? 1.22 : 1,
          duration: const Duration(milliseconds: 90),
          child: Icon(_ptipoteIcon(widget.stage, widget.family), size: 64),
        ),
        const SizedBox(height: 8),
        Text(
            'Reproduisez le rythme : $completed/${_config.tamTamRequiredSuccessfulBeats}'),
        const SizedBox(height: 4),
        Text(_feedback ?? 'Touchez quand le symbole grossit.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _finishing ? null : _tapBeat,
          child: Text(_finishing ? 'Métamorphose…' : 'TAM'),
        ),
      ]),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Plus tard')),
      ],
    );
  }
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

Future<void> _showTrustHistory(BuildContext context, ElevageSave state) async {
  final entries = ElevageDomain.trustHistory(state).reversed.toList();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Historique de Confiance'),
            content: SizedBox(
              width: 360,
              child: entries.isEmpty
                  ? const Text('Aucun changement de Confiance pour le moment.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        final delta = (entry['delta'] as num?)?.toInt() ?? 0;
                        final sign = delta >= 0 ? '+' : '';
                        return ListTile(
                          dense: true,
                          title: Text(entry['text'] as String? ??
                              'Mise à jour de Confiance'),
                          trailing: Text('$sign$delta'),
                        );
                      }),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Fermer')),
            ],
          ));
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

const Map<String, (String, String, String, String)>
    _communicationIntentDetails = <String, (String, String, String, String)>{
  'CALL': (
    'Demande d’attention',
    'Le P’TIPOTE souhaite attirer le joueur ou obtenir son attention.',
    'Viens',
    'Viens avec moi.',
  ),
  'DISCOMFORT': (
    'Inconfort ressenti',
    'Le P’TIPOTE exprime un malaise corporel.',
    'Aïe',
    'Je ne me sens pas bien.',
  ),
  'HUNGER': (
    'Faim',
    'Le P’TIPOTE signale que son ventre réclame.',
    'faim',
    'J’ai faim.'
  ),
  'VERY_HUNGRY': (
    'Très faim',
    'Le P’TIPOTE signale une faim plus insistante.',
    'faim !',
    'J’ai très faim.',
  ),
  'HEAT': (
    'Demande de chaleur',
    'Le P’TIPOTE voudrait davantage de chaleur.',
    'veux chaleur',
    'Je voudrais plus de chaleur.',
  ),
  'COOL': (
    'Demande de fraîcheur',
    'Le P’TIPOTE voudrait moins de chaleur.',
    'veux fraîcheur',
    'Je voudrais plus de fraîcheur.',
  ),
  'LIGHT': (
    'Demande de lumière',
    'Le P’TIPOTE voudrait davantage de lumière.',
    'veux lumière',
    'Je voudrais plus de lumière.',
  ),
  'HUMIDITY': (
    'Demande d’humidité',
    'Le P’TIPOTE voudrait davantage d’humidité.',
    'veux humidité',
    'Je voudrais plus d’humidité.',
  ),
  'SHADE': (
    'Demande d’ombre',
    'Le P’TIPOTE cherche une zone moins lumineuse.',
    'veux ombre',
    'Je voudrais davantage d’ombre.',
  ),
  'DRYNESS': (
    'Demande de sécheresse',
    'Le P’TIPOTE cherche une zone moins humide.',
    'veux sec',
    'Je voudrais un endroit plus sec.',
  ),
  'REST': (
    'Demande de repos',
    'Le P’TIPOTE cherche un moment de repos.',
    'repos',
    'J’aimerais me reposer.',
  ),
  'REST_REQUEST': (
    'Intention de repos',
    'Le P’TIPOTE veut faire une pause ou une sieste près d’un meuble de repos.',
    'repos',
    'Je vais faire une petite sieste.',
  ),
};

class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

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
