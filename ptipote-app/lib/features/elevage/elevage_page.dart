import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'elevage_config.dart';
import 'elevage_controller.dart';
import 'elevage_engine.dart';
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

class _IndividualPage extends StatelessWidget {
  const _IndividualPage(
      {required this.controller,
      required this.individualId,
      required this.onBack});
  final ElevageController controller;
  final String individualId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final individual = (state.data['individuals'] as Map)[individualId] as Map;
    final alcove = (state.data['alcoves'] as List)
        .cast<Map>()
        .firstWhere((item) => item['id'] == individual['alcoveId']);
    final environment = ElevageDomain.environment(
        state, alcove['id'] as String, controller.config);
    final hunger = ElevageDomain.hunger(state, individualId,
        DateTime.now().millisecondsSinceEpoch, controller.config);
    final communication = ElevageDomain.communication(state, individualId,
        DateTime.now().millisecondsSinceEpoch, controller.config);
    final available = ElevageDomain.metamorphosisAvailable(state, individualId,
        DateTime.now().millisecondsSinceEpoch, controller.config);
    final stage = individual['lifecycle']['stage'] as String;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: onBack),
        title: const Text('Alcôve'),
        actions: <Widget>[
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
          Center(child: _PtipotePlaceholder(stage: stage, reaction: null)),
          const SizedBox(height: 8),
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
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              ...ElevageDomain.foodItems
                  .where((item) => _special(state, item) > 0)
                  .map((item) => _offerButton(
                      context, controller, individual, item, false)),
              ...ElevageDomain.treatItems
                  .where((item) => _special(state, item) > 0)
                  .map((item) => _offerButton(
                      context, controller, individual, item, false)),
              ...ElevageDomain.structuralItems
                  .where((item) => _special(state, item) > 0)
                  .map((item) => _offerButton(
                      context, controller, individual, item, true)),
            ]),
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
                  title: Text(definition?.label ?? 'Installation inconnue'),
                  subtitle: Text(stock is Map && stock.isNotEmpty
                      ? stock.entries
                          .where((entry) => entry.value != 0)
                          .map((entry) => '${entry.key} × ${entry.value}')
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
                onPressed: () => _foraging(context, controller, individualId),
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
                    _metamorphosis(context, controller, individualId),
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
              title: const Text('Feature enabled')),
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
      IconButton(
          icon: const Icon(Icons.settings_outlined),
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
int _special(ElevageSave state, String item) =>
    ((state.data['inventory']['special'] as Map)[item] as num?)?.toInt() ?? 0;
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

class _PtipotePlaceholder extends StatelessWidget {
  const _PtipotePlaceholder({required this.stage, required this.reaction});
  final String stage;
  final String? reaction;
  @override
  Widget build(BuildContext context) => Container(
      width: stage == 'BABY'
          ? 100
          : stage == 'INTERMEDIATE'
              ? 132
              : 164,
      height: stage == 'BABY'
          ? 100
          : stage == 'INTERMEDIATE'
              ? 132
              : 164,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.secondaryContainer),
      child: Icon(stage == 'BABY' ? Icons.egg_outlined : Icons.pets, size: 64));
}

Widget _offerButton(BuildContext context, ElevageController controller,
        Map individual, String item, bool structural) =>
    FilledButton.tonal(
        onPressed: () async {
          if (structural) {
            await controller.offerStructural(individual['id'] as String, item);
          } else {
            await controller.offerFood(individual['id'] as String, item);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${ElevageDomain.reactionFor(item, Map<String, dynamic>.from(individual))} · $item')));
          }
        },
        child: Text(item));

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
            ...instances.entries.map((entry) => ListTile(
                title: Text(controller.config
                        .installation(
                            (entry.value as Map)['definitionId'] as String)
                        ?.label ??
                    'Inconnue'),
                onTap: () async {
                  await controller.place(alcoveId, slot, entry.key as String);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
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
                  await controller.claimForaging(id, point['id'] as String);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                }))
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
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            title: Text(
                'Jelly fruité · ${controller.config.fruitJellyPrice} Bio-piles'),
            onTap: () async {
              await controller.buyTreat('FRUIT_JELLY');
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
          const Divider(),
          ListTile(
            title: Text(
                'Échanger ${controller.config.buybackQuantity} Organique → ${controller.config.buybackBioPiles} Bio-pile'),
            onTap: () => controller.sellGeneric('ORGANIC'),
          ),
          ListTile(
            title: Text(
                'Échanger ${controller.config.buybackQuantity} Minéral → ${controller.config.buybackBioPiles} Bio-pile'),
            onTap: () => controller.sellGeneric('MINERAL'),
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
