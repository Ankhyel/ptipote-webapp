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

  Future<void> _offer(String item, bool structural) async {
    final state = widget.controller.state!;
    final individual =
        (state.data['individuals'] as Map)[widget.individualId] as Map;
    if (structural) {
      await widget.controller.offerStructural(widget.individualId, item);
    } else {
      await widget.controller.offerFood(widget.individualId, item);
    }
    if (!mounted) return;
    if (widget.controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ElevagePresentation.friendlyError(widget.controller.error))));
      return;
    }
    final reaction =
        ElevageDomain.reactionFor(item, Map<String, dynamic>.from(individual));
    final feedback = ElevagePresentation.reactionFeedback(
        reaction, individual['name'] as String);
    setState(() {
      _reaction = reaction;
      _feedback = feedback;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(feedback)));
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
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Inventaire',
              onPressed: () =>
                  _openInventory(context, controller, individual, _offer)),
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
              slots: (alcove['slots'] as List).cast<dynamic>()),
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
                leading: const Icon(Icons.landscape_outlined),
                title: Text(
                    'Lumière ${_quality(environment['light']!)} · Température ${_quality(environment['temperature']!)} · Humidité ${_quality(environment['humidity']!)}')),
            FilledButton.tonal(
                onPressed: () =>
                    controller.refreshAlcove(alcove['id'] as String),
                child: const Text('Actualiser l’Alcôve')),
          ]),
          _section(context, 'Proposer quelque chose', <Widget>[
            const Text('Choisissez un objet depuis votre inventaire.'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
                onPressed: () =>
                    _openInventory(context, controller, individual, _offer),
                icon: const Icon(Icons.card_giftcard_outlined),
                label: const Text('Ouvrir l’inventaire')),
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
          if (stage != 'BABY')
            _section(context, 'Tempérament',
                <Widget>[Text(_personalityLabel(individual))]),
        ],
      ),
    );
  }
}

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

/// Scène placeholder volontairement composée d’icônes Flutter : les futures
/// illustrations/sprites pourront remplacer cette couche sans toucher au domaine.
class _AlcoveScene extends StatefulWidget {
  const _AlcoveScene({
    required this.stage,
    required this.reaction,
    required this.feedback,
    required this.slots,
  });
  final String stage;
  final String? reaction;
  final String? feedback;
  final List<dynamic> slots;

  @override
  State<_AlcoveScene> createState() => _AlcoveSceneState();
}

class _AlcoveSceneState extends State<_AlcoveScene> {
  Timer? _wanderTimer;
  var _horizontal = -.35;
  var _up = .18;

  @override
  void initState() {
    super.initState();
    _wanderTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _horizontal = Random().nextDouble() * 1.1 - .55;
        _up = Random().nextBool() ? .12 : .22;
      });
    });
  }

  @override
  void dispose() {
    _wanderTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = switch (widget.stage) {
      'BABY' => 74.0,
      'INTERMEDIATE' => 94.0,
      _ => 112.0,
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
        height: 232,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: <Color>[
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Stack(children: <Widget>[
          const Positioned(
              left: 18,
              top: 16,
              child: Icon(Icons.dark_mode_outlined, size: 28)),
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
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeInOut,
            alignment: Alignment(_horizontal, _up),
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
                child: Icon(
                    widget.stage == 'BABY' ? Icons.egg_outlined : Icons.pets,
                    size: size * .62),
              ),
            ),
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
                    child: Text(widget.feedback!)),
              ),
            ),
        ]),
      ),
    );
  }
}

Future<void> _openInventory(
    BuildContext context,
    ElevageController controller,
    Map individual,
    Future<void> Function(String item, bool structural) onOffer) async {
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
        const categories = <String>[
          'Nourriture',
          'Friandises',
          'Matériaux',
          'Ressources'
        ];
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
                if (items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text(
                              'Votre inventaire est vide. Explorez la Mini-Lisière pour trouver des objets.'))),
                ...categories.expand((category) {
                  final entries = items.entries
                      .where((entry) =>
                          ElevagePresentation.itemCategory(entry.key) ==
                          category)
                      .toList();
                  if (entries.isEmpty) return <Widget>[];
                  return <Widget>[
                    Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(category,
                            style:
                                Theme.of(sheetContext).textTheme.titleMedium)),
                    ...entries.map((entry) {
                      final item = entry.key;
                      final canOffer = ElevageDomain.foodItems.contains(item) ||
                          ElevageDomain.treatItems.contains(item) ||
                          ElevageDomain.structuralItems.contains(item);
                      return ListTile(
                        leading: Icon(ElevagePresentation.itemIcon(item)),
                        title: Text(ElevagePresentation.itemLabel(item)),
                        trailing: canOffer
                            ? FilledButton.tonal(
                                onPressed: () async {
                                  await onOffer(
                                      item,
                                      ElevageDomain.structuralItems
                                          .contains(item));
                                  if (sheetContext.mounted) {
                                    setSheetState(() {});
                                  }
                                },
                                child: Text('Proposer ×${entry.value}'))
                            : Text('×${entry.value}'),
                      );
                    }),
                  ];
                }),
              ],
            ),
          ),
        );
      },
    ),
  );
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
                    return ListTile(
                        title: Text(known ? recipe.label : 'Recette inconnue'),
                        subtitle: known
                            ? Text(
                                '${recipe.organic} Organique · ${recipe.mineral} Minéral')
                            : null,
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
