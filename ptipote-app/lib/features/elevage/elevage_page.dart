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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Icon(Icons.pets_outlined, size: 76),
              const SizedBox(height: 20),
              Text('P’TIPOTE Élevage',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                  'Une Alcôve vous attend. Commencez une partie locale sur cet appareil.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: controller.initialize,
                  child: const Text('Commencer P’TIPOTE Élevage')),
            ]),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Les Alcôves',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
              'Accueillez, observez et aménagez un espace pour chaque P’TIPOTE.'),
          if (controller.notifications.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 16),
          ...alcoves.map((alcove) {
            final occupant = alcove['occupantIndividualId'] as String?;
            final individual = occupant == null
                ? null
                : (state.data['individuals'] as Map)[occupant] as Map?;
            final occupied = individual != null &&
                (state.data['activeIndividualIds'] as List).contains(occupant);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: occupied
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            Text('${individual['name']}',
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(
                                'Minéral · Résonance · ${_stageLabel(individual['lifecycle']['stage'] as String)}'),
                            Text(individual['ownership']['mode'] == 'PHYSICAL'
                                ? 'Figurine'
                                : _coRemaining(individual['ownership'] as Map)),
                            const SizedBox(height: 10),
                            FilledButton(
                                onPressed: () => onOpenIndividual(occupant!),
                                child: const Text('Ouvrir l’Alcôve')),
                          ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            Text('Alcôve ${alcove['id']}',
                                style: Theme.of(context).textTheme.titleLarge),
                            const Text('Libre'),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () => _welcome(
                                  context, controller, alcove['id'] as String),
                              icon: const Icon(Icons.add_home_outlined),
                              label: const Text('Accueillir un P’TIPOTE'),
                            ),
                            if ((alcove['slots'] as List)
                                .any((slot) => slot != null))
                              TextButton(
                                onPressed: () => _moveOut(context, controller,
                                    alcove['id'] as String),
                                child: const Text('Déménager'),
                              ),
                          ]),
              ),
            );
          }),
        ],
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

  @override
  void initState() {
    super.initState();
    _autonomousTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _runAutonomousCycle();
    });
    _idleTimer = Timer.periodic(
        Duration(seconds: widget.controller.config.idlePauseSeconds), (_) {
      if (!mounted || _autonomousInFlight) return;
      final zones = widget.controller.config.sceneZones;
      final index = zones.indexWhere((zone) => zone.id == _ptipoteZoneId);
      setState(() {
        _ptipoteZoneId = zones[(index + 1) % zones.length].id;
        _sceneAction = 'IDLE';
      });
    });
    Future<void>.delayed(
        Duration(milliseconds: widget.controller.config.objectReactionDelayMs),
        () => _runAutonomousCycle(playerTriggered: true));
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
    super.dispose();
  }

  void _setSceneAction(String action, {String? zoneId}) {
    if (!mounted) return;
    setState(() {
      _sceneAction = action;
      if (zoneId != null) _ptipoteZoneId = zoneId;
    });
  }

  Future<void> _runAutonomousCycle({bool playerTriggered = false}) async {
    if (!mounted || _autonomousInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
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
    final alcoveId = individual['alcoveId'] as String;
    final decision = ElevageDomain.nextAutonomousSceneDecision(
        state, widget.individualId, alcoveId, now, config,
        lastBehavior: playerTriggered ? null : _lastAutonomousBehavior,
        phaseOverride: widget.controller.forcedDayNightPhase);
    if (decision == null) return;
    final target = ElevageDomain.sceneItems(state, alcoveId)
        .firstWhere((item) => item['instanceId'] == decision.instanceId);
    _autonomousInFlight = true;
    final targetZone = decision.zoneId;
    try {
      _setSceneAction('NOTICE_ITEM');
      await Future<void>.delayed(
          Duration(milliseconds: config.objectReactionDelayMs));
      _setSceneAction('APPROACH_ITEM', zoneId: targetZone);
      await Future<void>.delayed(
          Duration(milliseconds: config.normalMoveDurationMs));
      _setSceneAction('INSPECT_ITEM');
      await Future<void>.delayed(
          Duration(milliseconds: config.objectReactionDelayMs));
      _setSceneAction('THINK');
      await Future<void>.delayed(
          Duration(milliseconds: config.objectReactionDelayMs));
      if (decision.outcome.behavior == 'MOVE_ITEM') {
        // L'objet est désiré, mais la zone elle-même gêne le Résonance : le
        // signal d'inconfort précède une course visible vers un meilleur coin.
        _setSceneAction('DISCOMFORT');
        await Future<void>.delayed(
            Duration(milliseconds: config.objectReactionDelayMs));
        _setSceneAction('MOVE_ITEM', zoneId: decision.outcome.targetZoneId);
        await Future<void>.delayed(
            Duration(milliseconds: config.runMoveDurationMs));
      }
      await _interactSceneItem(target, automatic: true);
      _lastAutonomousAt = DateTime.now().millisecondsSinceEpoch;
      _lastAutonomousBehavior = decision.outcome.behavior;
      await Future<void>.delayed(const Duration(milliseconds: 900));
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
    _runAutonomousCycle(playerTriggered: true);
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
    _setSceneAction(_sceneActionForOutcome(outcome.behavior));
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

  Future<void> _followZone(String zoneId) async {
    _setSceneAction('FOLLOW', zoneId: zoneId);
    await widget.controller.follow(widget.individualId, zoneId);
    if (!mounted || widget.controller.error != null) return;
    _showSceneFeedback('', reaction: 'FOLLOW');
    await Future<void>.delayed(
        Duration(milliseconds: widget.controller.config.normalMoveDurationMs));
    _setSceneAction('IDLE');
  }

  Future<void> _cuddle() async {
    _setSceneAction('CUDDLE');
    await widget.controller.cuddle(widget.individualId);
    if (!mounted || widget.controller.error != null) return;
    _showSceneFeedback('', reaction: 'CUDDLE');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _setSceneAction('IDLE');
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    final alcove = (state.data['alcoves'] as List)
        .cast<Map>()
        .firstWhere((item) => item['id'] == individual['alcoveId']);
    final environment = ElevageDomain.environment(
        state, alcove['id'] as String, controller.config);
    final hunger = ElevageDomain.hunger(state, widget.individualId,
        DateTime.now().millisecondsSinceEpoch, controller.config);
    final satiety = ElevageDomain.satietyPercent(state, widget.individualId,
        DateTime.now().millisecondsSinceEpoch, controller.config);
    final communication = ElevageDomain.communication(
        state,
        widget.individualId,
        DateTime.now().millisecondsSinceEpoch,
        controller.config);
    final available = ElevageDomain.metamorphosisAvailable(
        state,
        widget.individualId,
        DateTime.now().millisecondsSinceEpoch,
        controller.config);
    final stage = individual['lifecycle']['stage'] as String;
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _AlcoveScene(
              stage: stage,
              reaction: _reaction,
              feedback: _feedback,
              slots: (alcove['slots'] as List).cast<dynamic>(),
              environment: environment,
              sceneItems:
                  ElevageDomain.sceneItems(state, alcove['id'] as String),
              zones: controller.config.sceneZones,
              onSceneItemTap: (item) => _openSceneItemActions(item),
              onZoneTap: (zoneId) => _pendingPlacementItem == null
                  ? _followZone(zoneId)
                  : _placeInZone(zoneId),
              onPtipoteTap: _cuddle,
              pendingItem: _pendingPlacementItem,
              action: _sceneAction,
              ptipoteZoneId: _ptipoteZoneId,
              phase: controller
                  .dayNightPhase(DateTime.now().millisecondsSinceEpoch),
              phaseRemainingMs: ElevageDomain.dayNightRemainingMs(
                  DateTime.now().millisecondsSinceEpoch, controller.config,
                  phaseOverride: controller.forcedDayNightPhase),
              now: DateTime.now().millisecondsSinceEpoch,
              config: controller.config,
              zoneEnvironments: <String, Map<String, int>>{
                for (final zone in controller.config.sceneZones)
                  zone.id: ElevageDomain.zoneEnvironment(
                      state, alcove['id'] as String, zone.id, controller.config,
                      now: DateTime.now().millisecondsSinceEpoch,
                      phaseOverride: controller.forcedDayNightPhase),
              }),
          const SizedBox(height: 12),
          Center(
              child: Text('${individual['name']}',
                  style: Theme.of(context).textTheme.headlineMedium)),
          Center(child: Text('Minéral · Résonance · ${_stageLabel(stage)}')),
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
            ListTile(
                leading: const Icon(Icons.landscape_outlined),
                title: Text(
                    'Lumière ${_quality(environment['light']!)} · Température ${_quality(environment['temperature']!)} · Humidité ${_quality(environment['humidity']!)}')),
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
            ...List<Widget>.generate((alcove['slots'] as List).length, (index) {
              final raw = (alcove['slots'] as List)[index];
              if (raw is Map) {
                final definition = controller.config
                    .installation(raw['definitionId'] as String);
                final stock = raw['productionState']?['availableByItemId'];
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
                      : () => _showInstallationDetails(
                          context, controller.config, definition, environment),
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
              subtitle: Text(
                  '${recipe.organic} Organique · ${recipe.mineral} Minéral'),
              onTap: () => _editRecipe(context, recipe))),
          _heading('Métamorphose'),
          _number(
              context,
              'Tolérance rythmique (ms)',
              config.metamorphosisToleranceMs,
              (value) =>
                  config = config.copyWith(metamorphosisToleranceMs: value)),
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
  Future<void> _editRecipe(BuildContext context, ElevageRecipe recipe) async {
    final organic = await _numberDialog(
        context, '${recipe.label} · Organique', recipe.organic);
    if (organic == null) return;
    if (!context.mounted) return;
    final mineral = await _numberDialog(
        context, '${recipe.label} · Minéral', recipe.mineral);
    if (!context.mounted || mineral == null) return;
    setState(() => config = config.copyWith(
        recipes: config.recipes
            .map((item) => item.id == recipe.id
                ? item.copyWith(organic: organic, mineral: mineral)
                : item)
            .toList()));
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
    AppBar(title: const Text('P’TIPOTE Élevage'), actions: <Widget>[
      if (controller.config.devMode)
        IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Réglages de test',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ElevageDashboardPage(controller: controller))))
    ]);
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
String _hungerLabel(String value) => switch (value) {
      'SATIATED' => 'Rassasié',
      'NORMAL' => 'Bien',
      'HUNGRY' => 'A faim',
      _ => 'Très faim'
    };
String _quality(int value) => value <= -2
    ? 'faible'
    : value >= 2
        ? 'élevée'
        : 'équilibrée';
String _communicationLabel(String value) => switch (value) {
      'ROOT' => 'Souhaite une racine',
      'LEAF' => 'Souhaite une feuille',
      'IRON' => 'Recherche du fer',
      'FOOD' => 'A faim',
      _ => 'Besoin minéral'
    };
String _coRemaining(Map ownership) {
  final remaining =
      ((ownership['expiresAt'] as int) - DateTime.now().millisecondsSinceEpoch)
          .clamp(0, 999999999);
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
    required this.reaction,
    required this.feedback,
    required this.slots,
    required this.environment,
    required this.sceneItems,
    required this.zones,
    required this.onSceneItemTap,
    required this.onZoneTap,
    required this.onPtipoteTap,
    required this.pendingItem,
    required this.action,
    required this.ptipoteZoneId,
    required this.phase,
    required this.phaseRemainingMs,
    required this.now,
    required this.config,
    required this.zoneEnvironments,
  });
  final String stage;
  final String? reaction;
  final String? feedback;
  final List<dynamic> slots;
  final Map<String, int> environment;
  final List<Map<String, dynamic>> sceneItems;
  final List<ElevageSceneZone> zones;
  final ValueChanged<Map> onSceneItemTap;
  final ValueChanged<String> onZoneTap;
  final VoidCallback onPtipoteTap;
  final String? pendingItem;
  final String action;
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
  String _selectedZoneId = 'ZONE_1';

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
            left: 14,
            right: 14,
            top: 10,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
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
          Positioned.fill(
            top: 42,
            bottom: 0,
            child: Row(
              children: widget.zones.asMap().entries.map((entry) {
                final zone = entry.value;
                final selected = _selectedZoneId == zone.id;
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedZoneId = zone.id);
                      final item = widget.sceneItems
                          .where((placed) => placed['zoneId'] == zone.id)
                          .firstOrNull;
                      if (item == null) widget.onZoneTap(zone.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: _zoneColor(
                            context, entry.key, widget.phase, selected),
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
                      ? () => widget.onZoneTap(zone.id)
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
          if (installed.isEmpty)
            const Center(child: Text('Un foyer calme, prêt à être aménagé.')),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 8,
              children: installed
                  .map((raw) => Tooltip(
                      message: ElevagePresentation.installationLabel(
                          raw['definitionId'] as String),
                      child: Icon(ElevagePresentation.installationIcon(
                          raw['definitionId'] as String))))
                  .toList(),
            ),
          ),
          AnimatedAlign(
            duration: Duration(
                milliseconds:
                    widget.action == 'FLEE' || widget.action == 'MOVE_ITEM'
                        ? widget.config.runMoveDurationMs
                        : widget.config.normalMoveDurationMs),
            curve: Curves.easeInOut,
            alignment: _zoneAlignment(widget.ptipoteZoneId),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: reactionScale,
              child: Container(
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
                  onLongPress: widget.onPtipoteTap,
                  onTap: widget.onPtipoteTap,
                  child: Icon(_actionIcon(widget.action, widget.stage),
                      size: size * .62),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 8,
            child: _zoneHud(widget.zoneEnvironments[_selectedZoneId] ??
                const <String, int>{
                  'light': 0,
                  'temperature': 0,
                  'humidity': 0
                }),
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
      'OBSERVE' => Icons.more_horiz,
      _ => Icons.arrow_forward,
    };

String _sceneActionForOutcome(String behavior) => switch (behavior) {
      'RUSH_SHAKE' || 'APPROACH' => 'EAT',
      'VIBRATE' => 'STRUCTURAL_ABSORB',
      'STEP_BACK' => 'REJECT',
      'MOVE_ITEM' => 'MOVE_ITEM',
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

String _clockLabel(int remainingMs) {
  final minutes =
      max(0, remainingMs ~/ const Duration(minutes: 1).inMilliseconds);
  return '${minutes ~/ 60} h ${minutes % 60} restantes';
}

IconData _actionIcon(String? action, String stage) => switch (action) {
      'MOVE' => Icons.directions_walk_outlined,
      'NOTICE_ITEM' || 'INSPECT_ITEM' || 'CURIOUS' => Icons.visibility_outlined,
      'APPROACH_ITEM' || 'FOLLOW' => Icons.arrow_forward,
      'THINK' || 'IGNORE' => Icons.more_horiz,
      'RUSH_SHAKE' || 'EAT' => Icons.restaurant_outlined,
      'VIBRATE' || 'STRUCTURAL_ABSORB' => Icons.diamond_outlined,
      'STEP_BACK' || 'REJECT' => Icons.sentiment_very_dissatisfied_outlined,
      'DISCOMFORT' => Icons.sentiment_dissatisfied_outlined,
      'FLEE' => Icons.priority_high,
      'SLEEP' => Icons.bedtime_outlined,
      'OBSERVE' => Icons.question_mark,
      'CUDDLE' => Icons.favorite,
      'MOVE_ITEM' => Icons.redo,
      'METAMORPHOSIS' => Icons.egg_outlined,
      _ => stage == 'BABY' ? Icons.egg_outlined : Icons.pets,
    };

Color _zoneColor(BuildContext context, int index, String phase, bool selected) {
  // Une même teinte vivante : seuls lumière et saturation distinguent les
  // zones, pour que le joueur lise l'expérience plutôt qu'un code couleur.
  final day = <Color>[
    const Color(0xff315C49),
    const Color(0xff4F7B58),
    const Color(0xff719A62),
    const Color(0xffA8BF72)
  ];
  final night = <Color>[
    const Color(0xff142922),
    const Color(0xff1B362A),
    const Color(0xff294735),
    const Color(0xff688451)
  ];
  final base = (phase == 'DAY' ? day : night)[index];
  return selected
      ? Color.alphaBlend(Colors.white.withValues(alpha: .24), base)
      : base;
}

Widget _zoneHud(Map<String, int> environment) => DecoratedBox(
    decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10)),
    child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
            '☀️ ${ElevagePresentation.environmentScale(environment['light'] ?? 0)}/5  '
            '🌡️ ${ElevagePresentation.environmentScale(environment['temperature'] ?? 0)}/5  '
            '💧 ${ElevagePresentation.environmentScale(environment['humidity'] ?? 0)}/5',
            style: const TextStyle(fontSize: 10, color: Colors.white))));

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
                    'Co-élevage · ${controller.config.coRearingDurationHours ~/ 24} jours'))
          ])));
}

Future<void> _nameAdoption(BuildContext context, ElevageController controller,
    String alcoveId, bool physical) async {
  final name = TextEditingController();
  final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(physical
                  ? 'Figurine détectée · Minéral Résonance'
                  : 'Les Sourciers confient un Résonance aléatoire'),
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
        physicalFigureRef: physical
            ? 'mock:mineral-resonance-${DateTime.now().millisecondsSinceEpoch}'
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

Future<void> _openBiofabricator(
    BuildContext context, ElevageController controller, String alcoveId) async {
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final state = controller.state!;
        return DraggableScrollableSheet(
            expand: false,
            builder: (_, scrollController) =>
                ListView(controller: scrollController, children: <Widget>[
                  const ListTile(title: Text('Bio-fabricateur')),
                  ...controller.config.recipes.map((recipe) {
                    final known = ElevageDomain.recipeKnown(state, recipe);
                    final definition =
                        controller.config.installation(recipe.installationId);
                    final environment = ElevageDomain.environment(
                        state, alcoveId, controller.config);
                    return ListTile(
                        leading: Icon(definition == null
                            ? Icons.help_outline
                            : ElevagePresentation.installationIcon(
                                definition.id)),
                        title: Text(known ? recipe.label : 'Recette inconnue'),
                        subtitle: known
                            ? Text(
                                '${recipe.organic} Organique · ${recipe.mineral} Minéral')
                            : null,
                        onTap: !known || definition == null
                            ? null
                            : () => _showInstallationDetails(sheetContext,
                                controller.config, definition, environment),
                        trailing: known
                            ? FilledButton(
                                onPressed: () async {
                                  await controller.craft(recipe);
                                  if (sheetContext.mounted &&
                                      controller.error == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '${recipe.label} a été bio-fabriqué.')));
                                    Navigator.pop(sheetContext);
                                  }
                                },
                                child: const Text('Fabriquer'))
                            : null);
                  })
                ]));
      });
}

Future<void> _foraging(
    BuildContext context, ElevageController controller, String id) async {
  final status = ElevageDomain.foragingStatus(
      controller.state!, id, DateTime.now().millisecondsSinceEpoch);
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
    final remaining =
        max(0, (run['readyAt'] as int) - DateTime.now().millisecondsSinceEpoch);
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
                    const Icon(Icons.auto_awesome, size: 64),
                    Text('Motif ${stage + 1}/3'),
                    const Text('TAM · TAM · … · TAM'),
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
