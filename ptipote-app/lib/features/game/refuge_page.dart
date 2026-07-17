import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'camp_heart_config.dart';
import 'camp_generator_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'game_asset_resolver.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'waste_recycler_config.dart';
import 'zone0_game_state.dart';

class RefugePage extends StatefulWidget {
  const RefugePage({super.key});

  static const route = '/game';

  @override
  State<RefugePage> createState() => _RefugePageState();
}

class _RefugePageState extends State<RefugePage> {
  static final _campHeartState = CampHeartState.placeholder();
  static final _zone0State = Zone0GameState.instance;

  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  String? _refugeAsset;
  Timer? _missionResolutionTimer;

  static const _buildings = <_RefugeBuilding>[
    _RefugeBuilding(
      name: 'Maison',
      left: 0.50,
      top: 0.30,
      width: 0.34,
      height: 0.12,
    ),
    _RefugeBuilding(
      name: 'Kernel',
      left: 0.63,
      top: 0.50,
      width: 0.28,
      height: 0.11,
    ),
    _RefugeBuilding(
      name: 'CampHeart',
      title: 'Cœur du Camp',
      left: 0.43,
      top: 0.59,
      width: 0.38,
      height: 0.14,
    ),
    _RefugeBuilding(
      name: 'Lisiere',
      title: 'Lisière',
      left: 0.22,
      top: 0.72,
      width: 0.32,
      height: 0.11,
    ),
    _RefugeBuilding(
      name: 'Tour',
      title: 'Tour de sécurité',
      left: 0.78,
      top: 0.42,
      width: 0.32,
      height: 0.11,
    ),
    _RefugeBuilding(
      name: 'FabLab',
      title: 'La FabLab',
      left: 0.78,
      top: 0.72,
      width: 0.32,
      height: 0.11,
    ),
    _RefugeBuilding(
      name: 'Market',
      title: 'Marché',
      left: 0.18,
      top: 0.56,
      width: 0.25,
      height: 0.10,
    ),
    _RefugeBuilding(
      name: 'Nursery',
      title: 'Nurserie P’TIBUG',
      left: 0.22,
      top: 0.62,
      width: 0.30,
      height: 0.10,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _zone0State.addListener(_onZone0StateChanged);
    _missionResolutionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _zone0State.resolveDueForageMissions();
        _zone0State.resolveDueTowerMissions();
        _zone0State.resolveGenerator(
          heartLevel: _campHeartState.campHeartLevel,
        );
        _zone0State.resolveWorkshopOrder();
        _zone0State.resolveConstructionProjects();
        _zone0State.resolvePTibugProduction();
        _zone0State.resolveMarket();
        _zone0State.resolveWasteAndRecycler(
          campHeartLevel: _campHeartState.campHeartLevel,
        );
        if (mounted) setState(() {});
      },
    );
    _warmAssets();
    _zone0State.resolveDueForageMissions();
    _zone0State.resolveGenerator(
      heartLevel: _campHeartState.campHeartLevel,
    );
  }

  @override
  void dispose() {
    _missionResolutionTimer?.cancel();
    _zone0State.removeListener(_onZone0StateChanged);
    super.dispose();
  }

  void _onZone0StateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _warmAssets() async {
    await _zone0State.loadFromFirebase();
    _zone0State.resolveDueForageMissions();
    final campHeartData = await _zone0State.loadCampHeartFromFirebase();
    if (campHeartData != null) {
      _campHeartState.applyFirebaseData(campHeartData);
    }
    _zone0State.resolveGenerator(
      heartLevel: _campHeartState.campHeartLevel,
    );
    _zone0State.resolveWorkshopOrder();
    _zone0State.resolveConstructionProjects();
    _zone0State.resolvePTibugProduction();
    _zone0State.resolveMarket();
    _zone0State.resolveWasteAndRecycler(
      campHeartLevel: _campHeartState.campHeartLevel,
    );
    _zone0State.refreshKernelMissions(
      campHeartLevel: _campHeartState.campHeartLevel,
    );
    final figurines = await _figurineService.watchMyFigurines().first;
    _zone0State.recoverFigurineNeeds(figurines: figurines, tick: 1);
    _refugeAsset = await _assetResolver.resolve('Camp');
    if (mounted) setState(() {});
  }

  void _openBuilding(_RefugeBuilding building) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (building.name == 'Maison') return const _MaisonPage();
          if (building.name == 'Lisiere') {
            return LisierePage(
              gameState: _zone0State,
              campHeartLevel: _campHeartState.campHeartLevel,
            );
          }
          if (building.name == 'CampHeart') {
            return CampHeartPage(
              state: _campHeartState,
              gameState: _zone0State,
            );
          }
          if (building.name == 'FabLab') {
            return FablabPage(
              gameState: _zone0State,
              campHeartLevel: _campHeartState.campHeartLevel,
            );
          }
          if (building.name == 'Tour') {
            return SecurityTowerPage(
              gameState: _zone0State,
              figurineService: FigurineService(),
              campHeartLevel: _campHeartState.campHeartLevel,
            );
          }
          if (building.name == 'Kernel') {
            return KernelPage(
              gameState: _zone0State,
              campHeartState: _campHeartState,
            );
          }
          if (building.name == 'Market') {
            return MarketPage(
              gameState: _zone0State,
              campHeartLevel: _campHeartState.campHeartLevel,
            );
          }
          if (building.name == 'Nursery') {
            return PTibugNurseryPage(
              gameState: _zone0State,
              campHeartLevel: _campHeartState.campHeartLevel,
            );
          }
          return _GameBuildingPage(building: building);
        },
      ),
    );
  }

  void _handleBuildingTap(_RefugeBuilding building) {
    if (building.name == 'FabLab' && !_zone0State.isFablabBuilt) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => FablabConstructionSheet(gameState: _zone0State),
      );
      return;
    }
    if (building.name == 'Tour') {
      if (!_zone0State.isSecurityTowerBuilt) {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SecurityTowerConstructionSheet(
            gameState: _zone0State,
            campHeartLevel: _campHeartState.campHeartLevel,
          ),
        );
        return;
      }
      _openBuilding(building);
      return;
    }
    if (building.name == 'Market' && !_zone0State.isMarketBuilt) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _MarketConstructionSheet(
          gameState: _zone0State,
          campHeartLevel: _campHeartState.campHeartLevel,
        ),
      );
      return;
    }
    if (building.name == 'Nursery' && !_zone0State.isPlaineNurseryBuilt) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _ConstructionProjectSheet(
          gameState: _zone0State,
          targetId: 'plaineNursery',
          title: 'Nurserie P’TIBUG',
          description:
              'Installe des P’TIBUG dans la Plaine pour produire lentement des ressources.',
          campHeartLevel: _campHeartState.campHeartLevel,
          blockedReason: _campHeartState.campHeartLevel < 2
              ? 'Le Cœur du Camp doit atteindre le niveau 2.'
              : null,
        ),
      );
      return;
    }
    _openBuilding(building);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jeu')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _CampHud(
                gameState: _zone0State,
                campHeartLevel: _campHeartState.campHeartLevel,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFFDAC7A6)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (_refugeAsset != null)
                          Image.asset(
                            _refugeAsset!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                          )
                        else
                          const _MissingGameImage(screenName: 'Camp'),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x00000000),
                                Color(0x33000000),
                              ],
                            ),
                          ),
                        ),
                        ..._buildings.map(
                          (building) => _BuildingHotspot(
                            building: building,
                            campHeartState: _campHeartState,
                            notificationCount:
                                _zone0State.unreadBuildingNotificationCount(
                              building.name,
                            ),
                            gameState: _zone0State,
                            onTap: () => _handleBuildingTap(building),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Prototype dev : tape un bâtiment pour ouvrir sa page.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHud extends StatelessWidget {
  const _CampHud({
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final capacity = gameState.populationCapacityForCampHeartLevel(
      campHeartLevel,
    );
    final wellbeingColor = _wellbeingColor(gameState.campWellbeing);
    return Row(
      children: <Widget>[
        Expanded(
          child: _HudChip(
            icon: Icons.groups_2_outlined,
            label: '${gameState.currentPopulation} / $capacity',
            onTap: () => _showHudInfo(context, 'Population',
                'La communauté installée au refuge. Elle arrive par les missions du Kernel et ne dépasse jamais la capacité du Cœur du Camp.'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HudChip(
            icon: Icons.battery_charging_full_outlined,
            label: '${gameState.bioBatteries}',
            onTap: () => _showHudInfo(context, 'Bio-batteries',
                'La ressource énergétique du refuge. Le Générateur, le Marché et certaines récompenses peuvent en produire.'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HudChip(
            icon: Icons.sentiment_satisfied_alt_outlined,
            label: '${gameState.displayedCampWellbeing}%',
            color: wellbeingColor,
            onTap: () => _showHudInfo(context, 'Bien-être',
                'Le bien-être du refuge reflète sa stabilité. La Sécurité actuelle apporte ${gameState.securityWellbeingModifier >= 0 ? '+' : ''}${gameState.securityWellbeingModifier}% (${towerOperationsConfig.wellbeingBandFor(gameState.refugeSafety).label}).'),
          ),
        ),
      ],
    );
  }

  Color _wellbeingColor(int value) {
    if (value < kernelConfig.wellbeingRedThreshold) {
      return const Color(0xFFB94A48);
    }
    if (value < kernelConfig.wellbeingOrangeThreshold) {
      return const Color(0xFFD48425);
    }
    return const Color(0xFF4F7F52);
  }

  void _showHudInfo(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Text(body)
                    ]))));
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF2F241A),
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KernelPage extends StatelessWidget {
  const KernelPage({
    super.key,
    required this.gameState,
    required this.campHeartState,
  });

  final Zone0GameState gameState;
  final CampHeartState campHeartState;

  @override
  Widget build(BuildContext context) {
    gameState.refreshKernelMissions(
      campHeartLevel: campHeartState.campHeartLevel,
    );
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kernel'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Mission principale'),
              Tab(text: 'Demandes'),
              Tab(text: 'Météo'),
              Tab(text: 'Plans'),
              Tab(text: 'Progression'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              _KernelMainMissionTab(
                mission: gameState.mainKernelMission(
                  campHeartState.campHeartLevel,
                ),
                gameState: gameState,
              ),
              _KernelRequestsTab(
                missions: gameState.refugeRequests(
                  campHeartState.campHeartLevel,
                ),
                gameState: gameState,
              ),
              _KernelRequestsTab(
                missions: gameState.weatherKernelMissions(
                  campHeartState.campHeartLevel,
                ),
                gameState: gameState,
                emptyMessage: 'Aucune mission météo annoncée par la Tour.',
              ),
              _KernelPlansTab(gameState: gameState),
              _KernelProgressTab(
                gameState: gameState,
                campHeartState: campHeartState,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KernelMainMissionTab extends StatelessWidget {
  const _KernelMainMissionTab({
    required this.mission,
    required this.gameState,
  });

  final KernelMissionProgress? mission;
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    if (mission == null && !gameState.hasPendingStarterPTibugChoice) {
      return const _KernelEmptyState(
        message: 'Aucune mission principale active.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        if (gameState.hasPendingStarterPTibugChoice)
          _StarterPTibugChoiceCard(gameState: gameState),
        if (mission != null) ...<Widget>[
          if (gameState.hasPendingStarterPTibugChoice)
            const SizedBox(height: 12),
          _KernelMissionCard(mission: mission!, gameState: gameState),
        ],
      ],
    );
  }
}

class _StarterPTibugChoiceCard extends StatelessWidget {
  const _StarterPTibugChoiceCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Choisir le premier P’TIBUG',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text(
                  'Le Kernel peut stabiliser un seul Pattern de départ. Les autres se découvriront ensuite grâce aux missions ou au Sourcier.'),
              const SizedBox(height: 12),
              ...PTibugSpecies.values.map((species) {
                final config = pTibugConfig.species[species]!;
                final pattern = pTibugConfig.patterns[species]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () {
                      final result =
                          gameState.chooseStarterPTibugPattern(species);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(config.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                          Text(pattern.description),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
}

class _KernelRequestsTab extends StatelessWidget {
  const _KernelRequestsTab({
    required this.missions,
    required this.gameState,
    this.emptyMessage = 'Aucune demande du refuge.',
  });

  final List<KernelMissionProgress> missions;
  final Zone0GameState gameState;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        if (missions.isEmpty)
          _KernelEmptyState(message: emptyMessage)
        else
          ...missions.map((mission) =>
              _KernelMissionCard(mission: mission, gameState: gameState)),
      ],
    );
  }
}

class _KernelMissionCard extends StatelessWidget {
  const _KernelMissionCard({required this.mission, required this.gameState});

  final KernelMissionProgress mission;
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final config = mission.config;
    final progress =
        '${mission.progress.clamp(0, config.requiredAmount)} / ${config.requiredAmount}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    config.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                _KernelStatusPill(completed: mission.isCompleted),
              ],
            ),
            const SizedBox(height: 8),
            Text(config.description),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: config.requiredAmount <= 0
                  ? 1
                  : (mission.progress / config.requiredAmount).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 8),
            Text('Progression : $progress'),
            const SizedBox(height: 8),
            Text(
              'Récompense : +${config.populationReward} habitant(s)'
              '${config.bioBatteryReward > 0 ? ', +${config.bioBatteryReward} bio-batterie(s)' : ''}'
              '${config.resourceRewards.isNotEmpty ? ', ${_formatRewards(config.resourceRewards)}' : ''}'
              '${config.rewardPatternId != null ? ', Pattern ${config.rewardPatternId}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (mission.status == KernelMissionStatus.locked) ...<Widget>[
              const SizedBox(height: 8),
              const Text('Prérequis Kernel ou bâtiment non remplis.'),
            ],
            if (mission.status == KernelMissionStatus.active &&
                config.requestedItem != null &&
                config.requestedAmount > 0) ...<Widget>[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final result = gameState.fulfillKernelMission(config.id);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(result.message)));
                },
                child: Text(
                    'Remettre ${config.requestedAmount} ${config.requestedItem}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KernelStatusPill extends StatelessWidget {
  const _KernelStatusPill({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFE2F0DD) : const Color(0xFFFFF1CC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          completed ? 'Terminé' : 'Actif',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }
}

class _KernelPlansTab extends StatefulWidget {
  const _KernelPlansTab({required this.gameState});

  final Zone0GameState gameState;

  @override
  State<_KernelPlansTab> createState() => _KernelPlansTabState();
}

class _KernelPlansTabState extends State<_KernelPlansTab> {
  KernelPlanCategory? _category;

  @override
  Widget build(BuildContext context) {
    final plans = kernelProgressConfig.plans
        .where((plan) => _category == null || plan.category == _category)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <KernelPlanCategory?>[null, ...KernelPlanCategory.values]
              .map(
                (category) => ChoiceChip(
                  label: Text(_categoryLabel(category)),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        ...plans.map((plan) {
          final state = widget.gameState.kernelPlanState(plan);
          final visible = state != KernelPlanState.unknown;
          return Opacity(
            opacity: visible ? 1 : 0.48,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(_planIcon(plan.iconName)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            visible ? plan.title : 'Plan inconnu',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        _KernelPlanStatePill(state: state),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(visible
                        ? plan.description
                        : 'Le Kernel n’a encore rien identifié.'),
                    if (visible) ...<Widget>[
                      const SizedBox(height: 8),
                      Text('Origine : ${plan.origin}'),
                      Text('Kernel : ${plan.kernelText}'),
                    ],
                    if (state == KernelPlanState.discovered) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'Pré-requis : ${widget.gameState.kernelPlanRequirementsLabel(plan)}',
                      ),
                    ],
                    if (state == KernelPlanState.ready) ...<Widget>[
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () {
                          final result =
                              widget.gameState.activateKernelPlan(plan.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        },
                        child: const Text('Activer le Plan'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _KernelPlanStatePill extends StatelessWidget {
  const _KernelPlanStatePill({required this.state});

  final KernelPlanState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      KernelPlanState.unknown => 'Inconnu',
      KernelPlanState.discovered => 'Découvert',
      KernelPlanState.ready => 'Prêt',
      KernelPlanState.active => 'Actif',
    };
    return Text(label, style: const TextStyle(fontWeight: FontWeight.w900));
  }
}

class _KernelProgressTab extends StatelessWidget {
  const _KernelProgressTab({
    required this.gameState,
    required this.campHeartState,
  });

  final Zone0GameState gameState;
  final CampHeartState campHeartState;

  @override
  Widget build(BuildContext context) {
    final stage = campHeartState.currentStage;
    final capacity = gameState.populationCapacityForCampHeartLevel(
      campHeartState.campHeartLevel,
    );
    final next = campHeartState.nextStage;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stage.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _InfoLine(
                  label: 'Niveau du Cœur',
                  value: '${campHeartState.campHeartLevel}',
                ),
                _InfoLine(
                  label: 'Population',
                  value: '${gameState.currentPopulation} / $capacity',
                ),
                _InfoLine(
                  label: 'Bien-être',
                  value:
                      '${gameState.campWellbeing}% (${gameState.wellbeingColorLabel()})',
                ),
                _InfoLine(
                  label: 'Prochain objectif',
                  value: next == null
                      ? 'Stade maximum V1'
                      : 'Atteindre ${next.label}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _KernelXpCard(
          title: 'Confiance du Kernel',
          level: gameState.kernelTrustLevel,
          xp: gameState.kernelTrustXp,
          requiredXp: gameState.kernelTrustXpRequired,
          description: 'Le Kernel observe la continuité de vos choix.',
          next: 'De nouveaux Plans pourront être partagés.',
        ),
        ...KernelAxis.values.map(
          (axis) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _KernelXpCard(
              title: _axisLabel(axis),
              level: gameState.kernelAxisLevel(axis),
              xp: gameState.kernelAxisCurrentXp(axis),
              requiredXp: gameState.kernelAxisXpRequired(axis),
              description: _axisDescription(axis),
              next: _axisNext(axis),
            ),
          ),
        ),
      ],
    );
  }
}

class _KernelXpCard extends StatelessWidget {
  const _KernelXpCard({
    required this.title,
    required this.level,
    required this.xp,
    required this.requiredXp,
    required this.description,
    required this.next,
  });

  final String title;
  final int level;
  final int xp;
  final int requiredXp;
  final String description;
  final String next;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$title · niv. $level',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (xp / requiredXp).clamp(0, 1)),
              Text('$xp / $requiredXp XP'),
              const SizedBox(height: 8),
              Text(description),
              Text('Prochain déblocage : $next'),
            ],
          ),
        ),
      );
}

String _categoryLabel(KernelPlanCategory? category) => switch (category) {
      null => 'Tous',
      KernelPlanCategory.buildings => 'Bâtiments',
      KernelPlanCategory.workshop => 'Atelier',
      KernelPlanCategory.cuisine => 'Cuisine',
      KernelPlanCategory.ptibug => 'PTIBUG',
      KernelPlanCategory.installations => 'Installations',
    };

String _axisLabel(KernelAxis axis) => switch (axis) {
      KernelAxis.breeder => 'Éleveur',
      KernelAxis.builder => 'Bâtisseur',
      KernelAxis.restorer => 'Restaurateur',
    };

String _axisDescription(KernelAxis axis) => switch (axis) {
      KernelAxis.breeder => 'Vous prenez soin des formes de vie artificielles.',
      KernelAxis.builder =>
        'Vous consolidez les outils et les lieux du refuge.',
      KernelAxis.restorer => 'Vous restaurez un environnement plus habitable.',
    };

String _axisNext(KernelAxis axis) => switch (axis) {
      KernelAxis.breeder => 'Premier Pattern PTIBUG.',
      KernelAxis.builder => 'Nouvelles installations de refuge.',
      KernelAxis.restorer => 'Technologies de filtration.',
    };

IconData _planIcon(String iconName) => switch (iconName) {
      'chair' => Icons.chair_outlined,
      'filter' || 'cartridge' => Icons.filter_alt_outlined,
      'suit' => Icons.checkroom_outlined,
      'air' => Icons.air_outlined,
      'light' => Icons.lightbulb_outline,
      _ => Icons.memory_outlined,
    };

class _KernelEmptyState extends StatelessWidget {
  const _KernelEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _MaisonPage extends StatefulWidget {
  const _MaisonPage();

  @override
  State<_MaisonPage> createState() => _MaisonPageState();
}

class _MaisonPageState extends State<_MaisonPage>
    with SingleTickerProviderStateMixin {
  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  final _gameState = Zone0GameState.instance;
  late final AnimationController _tickController;
  Timer? _vitalityRecoveryTimer;
  int _recoveryTick = 0;
  String? _selectedFigurineId;
  String? _maisonAsset;

  @override
  void initState() {
    super.initState();
    _gameState.addListener(_onGameStateChanged);
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _vitalityRecoveryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _recoverVitalityStep(),
    );
    _loadAsset();
  }

  @override
  void dispose() {
    _vitalityRecoveryTimer?.cancel();
    _gameState.removeListener(_onGameStateChanged);
    _tickController.dispose();
    super.dispose();
  }

  void _onGameStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAsset() async {
    _maisonAsset = await _assetResolver.resolve('Maison');
    if (mounted) setState(() {});
  }

  int _vitalityFor(PtipoteFigurine figurine) {
    return _gameState.vitalityFor(figurine);
  }

  PtipoteAutoAssignmentPreference _autoPreferenceFor(
    PtipoteFigurine figurine,
  ) {
    return _gameState.autoPreferenceFor(figurine);
  }

  void _toggleFigurine(PtipoteFigurine figurine) {
    setState(() {
      _selectedFigurineId =
          _selectedFigurineId == figurine.id ? null : figurine.id;
    });
  }

  void _recoverVitalityStep() {
    if (!mounted) return;
    _recoveryTick += 1;
    _figurineService.watchMyFigurines().first.then((figurines) {
      if (!mounted) return;
      _gameState.recoverFigurineNeeds(
        figurines: figurines,
        tick: _recoveryTick,
      );
    });
  }

  void _setAutoPreference(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) {
    _gameState.setAutoPreference(figurine, preference);
    setState(() {
      _selectedFigurineId = figurine.id;
    });
  }

  void _wakeFigurine(PtipoteFigurine figurine) {
    setState(() {
      _gameState.wakeFromRest(figurine);
      _selectedFigurineId = figurine.id;
    });
  }

  void _sendToSleep(PtipoteFigurine figurine) {
    setState(() {
      _gameState.sendToSleep(figurine);
      _selectedFigurineId = figurine.id;
    });
  }

  void _cuddleFigurine(PtipoteFigurine figurine) {
    setState(() {
      _gameState.cuddle(figurine);
      _selectedFigurineId = figurine.id;
    });
  }

  void _feedFigurine(PtipoteFigurine figurine) {
    final result = _gameState.consumeSimpleMeal(figurine);
    setState(() => _selectedFigurineId = figurine.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Maison'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'P’TIPOTES', icon: Icon(Icons.pets_outlined)),
              Tab(text: 'Amélioration', icon: Icon(Icons.upgrade_outlined)),
              Tab(text: 'Infos', icon: Icon(Icons.info_outline)),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFFE7D4B2)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (_maisonAsset != null)
                        Image.asset(
                          _maisonAsset!,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x22000000),
                              Color(0x33000000),
                            ],
                          ),
                        ),
                      ),
                      _AlcoveLayer(alcoveCount: _gameState.alcoveCapacity),
                      const _FloorLayer(),
                      StreamBuilder<List<PtipoteFigurine>>(
                        stream: _figurineService.watchMyFigurines(),
                        builder: (context, snapshot) {
                          final figurines =
                              snapshot.data ?? const <PtipoteFigurine>[];
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              figurines.isEmpty) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (figurines.isEmpty) {
                            return const _RefugeEmptyState();
                          }
                          return Stack(
                            children: <Widget>[
                              _PtipoteRefugeLayer(
                                figurines: figurines,
                                animation: _tickController,
                                selectedFigurineId: _selectedFigurineId,
                                vitalityFor: _vitalityFor,
                                hungerFor: _gameState.hungerFor,
                                restFor: _gameState.restFor,
                                xpFor: _gameState.xpFor,
                                levelFor: _gameState.levelFor,
                                isOnMission: _gameState.isOnMission,
                                isAssignedToTower: _gameState.isAssignedToTower,
                                isAssignedToActiveBuilding: (figurineId) =>
                                    _gameState
                                        .isAssignedToWorkshop(figurineId) ||
                                    _gameState.isAssignedToMarket(figurineId),
                                isResting: _gameState.isResting,
                                isWaitingForBed: _gameState.isWaitingForBed,
                                isHappy: _gameState.isHappy,
                                hasIndigestion: _gameState.hasIndigestion,
                                restStateLabelFor: _gameState.restStateLabelFor,
                                moodLabelFor: _gameState.moodLabelFor,
                                recoveryRemaining:
                                    _gameState.vitalityRecoveryRemaining,
                                restRecoveryRemaining:
                                    _gameState.restRecoveryRemaining,
                                isCuddleCareActive:
                                    _gameState.isCuddleCareActive,
                                canCuddle: _gameState.canCuddle,
                                cuddleProgress:
                                    _gameState.cuddleCooldownProgress,
                                autoPreferenceFor: _autoPreferenceFor,
                                availableSimpleMeals: _gameState.resourceAmount(
                                  craftConfig.simpleMealRecipe.resultItem,
                                ),
                                alcoveCapacity: _gameState.alcoveCapacity,
                                lastCuddleAt: (figurine) =>
                                    _gameState.lastCuddleAt[figurine.id],
                                onToggleFigurine: _toggleFigurine,
                                onAutoPreferenceChanged: _setAutoPreference,
                                onWake: _wakeFigurine,
                                onSleep: _sendToSleep,
                                onCuddle: _cuddleFigurine,
                                onFeed: _feedFigurine,
                              ),
                              _MaisonUtilityButtons(
                                unreadCount: _gameState.unreadReportCount,
                                onInventory: _openInventory,
                                onMessages: _openMessages,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _HouseUpgradeTab(gameState: _gameState),
          const _BuildingInformationTab(
            title: 'Maison',
            description:
                'La Maison accueille les P’TIPOTES actifs, leurs alcôves de repos, les messages et l’inventaire du refuge. Son amélioration augmente les alcôves. Les logements des habitants sont agrégés et n’ajoutent pas directement de population.',
          ),
        ]),
      ),
    );
  }

  void _openInventory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Zone0InventorySheet(gameState: _gameState),
    );
  }

  void _openMessages() {
    _gameState.markReportsRead();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => MissionReportsSheet(gameState: _gameState),
    );
  }
}

class _HouseUpgradeTab extends StatefulWidget {
  const _HouseUpgradeTab({required this.gameState});

  final Zone0GameState gameState;

  @override
  State<_HouseUpgradeTab> createState() => _HouseUpgradeTabState();
}

class _HouseUpgradeTabState extends State<_HouseUpgradeTab> {
  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _openProject({
    required String targetId,
    required String title,
    required String description,
    String? footer,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ConstructionProjectSheet(
        gameState: widget.gameState,
        targetId: targetId,
        title: title,
        description: description,
        footer: footer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.gameState;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Maison',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Niveau ${state.houseLevel} · ${state.alcoveCapacity} alcoves actives',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: state.houseLevel >= 5
                    ? null
                    : () => _openProject(
                          targetId: 'house',
                          title: 'Ameliorer la Maison',
                          description:
                              'Une Maison plus stable ajoute des alcoves pour le repos des P’TIPOTES.',
                          footer: 'Niveau suivant : alcoves supplementaires.',
                        ),
                icon: const Icon(Icons.bedroom_parent_outlined),
                label: const Text('Amelioration'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BuildingHotspot extends StatelessWidget {
  const _BuildingHotspot({
    required this.building,
    required this.onTap,
    this.campHeartState,
    this.gameState,
    this.notificationCount = 0,
  });

  final _RefugeBuilding building;
  final VoidCallback onTap;
  final CampHeartState? campHeartState;
  final Zone0GameState? gameState;
  final int notificationCount;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment(building.left * 2 - 1, building.top * 2 - 1),
      widthFactor: building.width,
      heightFactor: building.height,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.white.withValues(alpha: 0.20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.50)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: _content(),
              ),
              if (notificationCount > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: _NotificationBadge(count: notificationCount),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (building.name == 'CampHeart' && campHeartState != null) {
      return _CampHeartHotspotContent(state: campHeartState!);
    }
    if (building.name == 'FabLab' && gameState != null) {
      return _FablabHotspotContent(gameState: gameState!);
    }
    if (building.name == 'Tour' && gameState != null) {
      return _SecurityTowerHotspotContent(
        gameState: gameState!,
        campHeartLevel: campHeartState?.campHeartLevel ?? 0,
      );
    }
    return Center(
      child: Text(
        building.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF2B2116),
          fontSize: 15,
          fontWeight: FontWeight.w900,
          shadows: <Shadow>[
            Shadow(color: Colors.white, blurRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _CampHeartHotspotContent extends StatelessWidget {
  const _CampHeartHotspotContent({required this.state});

  final CampHeartState state;

  @override
  Widget build(BuildContext context) {
    final stage = state.currentStage;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text(
            'Cœur du Camp',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF2B2116),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[Shadow(color: Colors.white, blurRadius: 10)],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${stage.label} niv. ${state.campHeartLevel}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2B2116),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: state.progressRatio,
              backgroundColor: Colors.white.withValues(alpha: 0.45),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6FA05F),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            state.isMaxLevel
                ? 'max V1'
                : '${state.vegetalizationXp} / ${state.vegetalizationXpRequired}',
            style: const TextStyle(
              color: Color(0xFF2B2116),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FablabHotspotContent extends StatelessWidget {
  const _FablabHotspotContent({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final built = gameState.isFablabBuilt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              built
                  ? Icons.precision_manufacturing_outlined
                  : Icons.construction_outlined,
              color: const Color(0xFF2B2116),
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              built
                  ? 'Cuisine ${gameState.cuisineLevel} · Atelier ${gameState.atelierLevel}'
                  : 'Fablab à bâtir',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2B2116),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                shadows: <Shadow>[Shadow(color: Colors.white, blurRadius: 10)],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              built
                  ? 'Stock ${gameState.globalStockCapacity}'
                  : '8 Org. · 4 Min.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2B2116),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityTowerHotspotContent extends StatelessWidget {
  const _SecurityTowerHotspotContent({
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final built = gameState.isSecurityTowerBuilt;
    final locked = campHeartLevel < securityTowerConfig.requiredCampHeartLevel;
    final subtitle = built
        ? 'Sécurité ${gameState.refugeSafety}/${securityTowerConfig.maxSecurity}'
        : locked
            ? 'Cœur niv. ${securityTowerConfig.requiredCampHeartLevel}'
            : '6 Org. · 8 Min.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              built
                  ? Icons.shield_outlined
                  : locked
                      ? Icons.lock_outline
                      : Icons.construction_outlined,
              color: const Color(0xFF2B2116),
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              built ? 'Tour niv. ${gameState.securityTowerLevel}' : 'Tour',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2B2116),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                shadows: <Shadow>[Shadow(color: Colors.white, blurRadius: 10)],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2B2116),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MaisonUtilityButtons extends StatelessWidget {
  const _MaisonUtilityButtons({
    required this.unreadCount,
    required this.onInventory,
    required this.onMessages,
  });

  final int unreadCount;
  final VoidCallback onInventory;
  final VoidCallback onMessages;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _RoundUtilityButton(
            icon: Icons.inventory_2_outlined,
            tooltip: 'Inventaire',
            onTap: onInventory,
          ),
          const SizedBox(height: 10),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              _RoundUtilityButton(
                icon: Icons.mark_email_unread_outlined,
                tooltip: 'Messages P’TIPOTE',
                onTap: onMessages,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: _NotificationBadge(count: unreadCount),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundUtilityButton extends StatelessWidget {
  const _RoundUtilityButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _FloorLayer extends StatelessWidget {
  const _FloorLayer();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: 1 / 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x33765A2C),
                  Color(0x66563D1E),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlcoveLayer extends StatelessWidget {
  const _AlcoveLayer({required this.alcoveCount});

  final int alcoveCount;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = math.min(4, alcoveCount);
          final alcoveWidth = constraints.maxWidth * 0.20;
          final alcoveHeight = alcoveWidth * 0.52;
          return Stack(
            children: List<Widget>.generate(alcoveCount, (index) {
              final column = index % columns;
              final row = index ~/ columns;
              final left = constraints.maxWidth *
                  (0.10 + column * (0.80 / math.max(1, columns - 1)));
              return Positioned(
                left: left,
                top: constraints.maxHeight * (0.28 + row * 0.08),
                width: alcoveWidth,
                height: alcoveHeight,
                child: CustomPaint(painter: _AlcovePainter()),
              );
            }),
          );
        },
      ),
    );
  }
}

class _PtipoteRefugeLayer extends StatefulWidget {
  const _PtipoteRefugeLayer({
    required this.figurines,
    required this.animation,
    required this.selectedFigurineId,
    required this.vitalityFor,
    required this.hungerFor,
    required this.restFor,
    required this.xpFor,
    required this.levelFor,
    required this.isOnMission,
    required this.isAssignedToTower,
    required this.isAssignedToActiveBuilding,
    required this.isResting,
    required this.isWaitingForBed,
    required this.isHappy,
    required this.hasIndigestion,
    required this.restStateLabelFor,
    required this.moodLabelFor,
    required this.recoveryRemaining,
    required this.restRecoveryRemaining,
    required this.isCuddleCareActive,
    required this.canCuddle,
    required this.cuddleProgress,
    required this.autoPreferenceFor,
    required this.availableSimpleMeals,
    required this.alcoveCapacity,
    required this.lastCuddleAt,
    required this.onToggleFigurine,
    required this.onAutoPreferenceChanged,
    required this.onWake,
    required this.onSleep,
    required this.onCuddle,
    required this.onFeed,
  });

  final List<PtipoteFigurine> figurines;
  final Animation<double> animation;
  final String? selectedFigurineId;
  final int Function(PtipoteFigurine figurine) vitalityFor;
  final int Function(PtipoteFigurine figurine) hungerFor;
  final int Function(PtipoteFigurine figurine) restFor;
  final int Function(PtipoteFigurine figurine) xpFor;
  final int Function(PtipoteFigurine figurine) levelFor;
  final bool Function(String figurineId) isOnMission;
  final bool Function(String figurineId) isAssignedToTower;
  final bool Function(String figurineId) isAssignedToActiveBuilding;
  final bool Function(PtipoteFigurine figurine) isResting;
  final bool Function(PtipoteFigurine figurine) isWaitingForBed;
  final bool Function(PtipoteFigurine figurine) isHappy;
  final bool Function(PtipoteFigurine figurine) hasIndigestion;
  final String Function(PtipoteFigurine figurine) restStateLabelFor;
  final String Function(PtipoteFigurine figurine) moodLabelFor;
  final Duration Function(PtipoteFigurine figurine) recoveryRemaining;
  final Duration Function(PtipoteFigurine figurine) restRecoveryRemaining;
  final bool Function(PtipoteFigurine figurine) isCuddleCareActive;
  final bool Function(PtipoteFigurine figurine) canCuddle;
  final double Function(PtipoteFigurine figurine) cuddleProgress;
  final PtipoteAutoAssignmentPreference Function(PtipoteFigurine figurine)
      autoPreferenceFor;
  final int availableSimpleMeals;
  final int alcoveCapacity;
  final DateTime? Function(PtipoteFigurine figurine) lastCuddleAt;
  final ValueChanged<PtipoteFigurine> onToggleFigurine;
  final void Function(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) onAutoPreferenceChanged;
  final ValueChanged<PtipoteFigurine> onWake;
  final ValueChanged<PtipoteFigurine> onSleep;
  final ValueChanged<PtipoteFigurine> onCuddle;
  final ValueChanged<PtipoteFigurine> onFeed;

  @override
  State<_PtipoteRefugeLayer> createState() => _PtipoteRefugeLayerState();
}

class _PtipoteRefugeLayerState extends State<_PtipoteRefugeLayer> {
  final _random = math.Random();
  final Map<String, _PtipoteMotion> _motions = <String, _PtipoteMotion>{};
  final Map<String, Offset> _bubbleOffsets = <String, Offset>{};
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _PtipoteRefugeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onTick);
      widget.animation.addListener(_onTick);
      _lastElapsed = Duration.zero;
    }
    _syncMotions();
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onTick);
    super.dispose();
  }

  void _syncMotions() {
    final ids = widget.figurines.map((figurine) => figurine.id).toSet();
    _motions.removeWhere((id, _) => !ids.contains(id));
    _bubbleOffsets.removeWhere((id, _) => !ids.contains(id));
    for (final figurine in widget.figurines) {
      _motions.putIfAbsent(figurine.id, _newMotion);
    }
  }

  _PtipoteMotion _newMotion() {
    return _PtipoteMotion(
      x: 0.08 + _random.nextDouble() * 0.84,
      direction: _random.nextBool() ? 1 : -1,
      speed: 0.0175 + _random.nextDouble() * 0.0125,
      moving: _random.nextBool(),
      nextDecision: 1.0 + _random.nextDouble() * 3.0,
      bounceSeed: _random.nextDouble() * math.pi * 2,
    );
  }

  void _onTick() {
    final controller = widget.animation;
    if (controller is! AnimationController) return;
    final elapsed = controller.lastElapsedDuration ?? Duration.zero;
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    var dt = (elapsed - _lastElapsed).inMilliseconds / 1000;
    _lastElapsed = elapsed;
    if (dt < 0) dt = 0.016;
    if (dt > 0.08) dt = 0.08;

    for (final figurine in widget.figurines) {
      final motion = _motions.putIfAbsent(figurine.id, _newMotion);
      if (widget.vitalityFor(figurine) <=
              ptipoteStatsConfig.minVitalityBeforeAutoRest ||
          widget.isResting(figurine)) {
        continue;
      }

      motion.nextDecision -= dt;
      if (motion.nextDecision <= 0) {
        motion.moving = _random.nextDouble() > 0.35;
        if (_random.nextBool()) motion.direction *= -1;
        motion.nextDecision = 1.4 + _random.nextDouble() * 3.2;
      }

      if (!motion.moving) continue;
      motion.x += motion.direction * motion.speed * dt;
      if (motion.x <= 0) {
        motion.x = 0;
        motion.direction = 1;
      }
      if (motion.x >= 1) {
        motion.x = 1;
        motion.direction = -1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncMotions();
    final allResting = widget.figurines
        .where(
          (figurine) =>
              !widget.isOnMission(figurine.id) &&
              !widget.isAssignedToTower(figurine.id) &&
              !widget.isAssignedToActiveBuilding(figurine.id) &&
              widget.isResting(figurine),
        )
        .toList();
    final resting = allResting.take(widget.alcoveCapacity).toList();
    final restingIds = resting.map((figurine) => figurine.id).toSet();
    final active = widget.figurines
        .where(
          (figurine) =>
              !widget.isOnMission(figurine.id) &&
              !widget.isAssignedToTower(figurine.id) &&
              !widget.isAssignedToActiveBuilding(figurine.id) &&
              (!widget.isResting(figurine) ||
                  !restingIds.contains(figurine.id)),
        )
        .toList();

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final spriteSize = (constraints.maxWidth * 0.18).clamp(56.0, 86.0);
          final usableWidth = math.max(1.0, constraints.maxWidth - spriteSize);
          final floorTopBottom = constraints.maxHeight / 3 - spriteSize * 0.70;
          final walkingBaseBottom = math.max(8.0, floorTopBottom);
          final placements = <String, _PtipotePlacement>{};
          return Stack(
            children: <Widget>[
              ...List<Widget>.generate(active.length, (index) {
                final figurine = active[index];
                final motion = _motions.putIfAbsent(figurine.id, _newMotion);
                final left = motion.x * usableWidth;
                final bounce = motion.moving
                    ? math.sin(
                          widget.animation.value * math.pi * 2 +
                              motion.bounceSeed,
                        ) *
                        0.4
                    : 0.0;
                final bottom = walkingBaseBottom + (index % 3) * 12 + bounce;
                final top = constraints.maxHeight - bottom - spriteSize;
                placements[figurine.id] = _PtipotePlacement(
                  left: left,
                  top: top,
                  isResting: false,
                );
                final needIcon = _needIconFor(figurine);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: left,
                      bottom: bottom,
                      width: spriteSize,
                      child: _PtipoteSpriteButton(
                        figurine: figurine,
                        selected: widget.selectedFigurineId == figurine.id,
                        isResting: false,
                        restRemainingLabel: '',
                        onTap: () => widget.onToggleFigurine(figurine),
                      ),
                    ),
                    if (needIcon != null || widget.isWaitingForBed(figurine))
                      Positioned(
                        left: left + spriteSize * 0.58,
                        top: top - 8,
                        child: _NeedBubble(
                          icon: widget.isWaitingForBed(figurine)
                              ? Icons.bedtime_outlined
                              : needIcon ?? Icons.bedtime_outlined,
                        ),
                      ),
                  ],
                );
              }),
              ...List<Widget>.generate(resting.length, (index) {
                final figurine = resting[index];
                final columns = math.min(4, widget.alcoveCapacity);
                final column = index % columns;
                final row = index ~/ columns;
                final alcoveCenter = constraints.maxWidth *
                    (0.20 + column * (0.60 / math.max(1, columns - 1)));
                final left = alcoveCenter - spriteSize / 2;
                final top = constraints.maxHeight * (0.26 + row * 0.08);
                placements[figurine.id] = _PtipotePlacement(
                  left: left,
                  top: top,
                  isResting: true,
                );
                final needIcon = _needIconFor(figurine);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: left,
                      top: top,
                      width: spriteSize,
                      child: _PtipoteSpriteButton(
                        figurine: figurine,
                        selected: widget.selectedFigurineId == figurine.id,
                        isResting: true,
                        restRemainingLabel: _shortDurationLabel(
                          widget.restRecoveryRemaining(figurine),
                        ),
                        onTap: () => widget.onToggleFigurine(figurine),
                      ),
                    ),
                    if (needIcon != null)
                      Positioned(
                        left: left + spriteSize * 0.58,
                        top: top - 8,
                        child: _NeedBubble(icon: needIcon),
                      ),
                  ],
                );
              }),
              if (widget.selectedFigurineId != null)
                ..._selectedBubble(
                  constraints: constraints,
                  spriteSize: spriteSize,
                  placements: placements,
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _selectedBubble({
    required BoxConstraints constraints,
    required double spriteSize,
    required Map<String, _PtipotePlacement> placements,
  }) {
    PtipoteFigurine? selected;
    for (final figurine in widget.figurines) {
      if (figurine.id == widget.selectedFigurineId) {
        selected = figurine;
        break;
      }
    }
    if (selected == null) return const <Widget>[];
    final selectedFigurine = selected;
    final placement = placements[selectedFigurine.id];
    if (placement == null) return const <Widget>[];

    const bubbleWidth = 216.0;
    final bubbleHeight = placement.isResting ? 238.0 : 202.0;
    final offset = _bubbleOffsets[selectedFigurine.id] ?? Offset.zero;
    final preferredTop = placement.isResting
        ? placement.top + 88 + offset.dy
        : placement.top - bubbleHeight - 8 + offset.dy;
    final bubbleTop = preferredTop
        .clamp(
          8.0,
          math.max(8.0, constraints.maxHeight - bubbleHeight - 8),
        )
        .toDouble();
    final preferredLeft =
        placement.left + spriteSize / 2 - bubbleWidth / 2 + offset.dx;
    final bubbleLeft = preferredLeft
        .clamp(
          8.0,
          math.max(8.0, constraints.maxWidth - bubbleWidth - 8),
        )
        .toDouble();
    var dragOrigin = Offset.zero;
    var bubbleOrigin = offset;

    return <Widget>[
      Positioned(
        left: bubbleLeft,
        top: bubbleTop,
        width: bubbleWidth,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (_) {
            dragOrigin = Offset.zero;
            bubbleOrigin = _bubbleOffsets[selectedFigurine.id] ?? Offset.zero;
          },
          onLongPressMoveUpdate: (details) {
            setState(() {
              dragOrigin = details.offsetFromOrigin;
              _bubbleOffsets[selectedFigurine.id] = bubbleOrigin + dragOrigin;
            });
          },
          child: _PtipoteInfoBubble(
            maxHeight: bubbleHeight,
            figurine: selectedFigurine,
            vitality: widget.vitalityFor(selectedFigurine),
            hunger: widget.hungerFor(selectedFigurine),
            rest: widget.restFor(selectedFigurine),
            xp: widget.xpFor(selectedFigurine),
            level: widget.levelFor(selectedFigurine),
            autoPreference: widget.autoPreferenceFor(selectedFigurine),
            isHappy: widget.isHappy(selectedFigurine),
            hasIndigestion: widget.hasIndigestion(selectedFigurine),
            restStateLabel: widget.restStateLabelFor(selectedFigurine),
            moodLabel: widget.moodLabelFor(selectedFigurine),
            recoveryRemaining: widget.recoveryRemaining(selectedFigurine),
            cuddleCareActive: widget.isCuddleCareActive(selectedFigurine),
            canCuddle: widget.canCuddle(selectedFigurine),
            cuddleProgress: widget.cuddleProgress(selectedFigurine),
            availableSimpleMeals: widget.availableSimpleMeals,
            lastCuddleAt: widget.lastCuddleAt(selectedFigurine),
            isResting: placement.isResting,
            isWaitingForBed: widget.isWaitingForBed(selectedFigurine),
            onWake: () => widget.onWake(selectedFigurine),
            onSleep: () => widget.onSleep(selectedFigurine),
            onCuddle: () => widget.onCuddle(selectedFigurine),
            onFeed: () => widget.onFeed(selectedFigurine),
            onAutoPreferenceChanged: (preference) {
              widget.onAutoPreferenceChanged(selectedFigurine, preference);
            },
          ),
        ),
      ),
    ];
  }

  IconData? _needIconFor(PtipoteFigurine figurine) {
    if (!_shouldShowNeedBubble(figurine)) return null;
    final vitality = widget.vitalityFor(figurine);
    final hunger = widget.hungerFor(figurine);
    final rest = widget.restFor(figurine);
    if (hunger > ptipoteStatsConfig.indigestionHungerThreshold) {
      return Icons.sick_outlined;
    }
    if (rest < ptipoteStatsConfig.restedThreshold) {
      return Icons.bedtime_outlined;
    }
    if (vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      return Icons.bedtime_outlined;
    }
    if (hunger <= ptipoteStatsConfig.happyHungerThreshold) {
      return Icons.restaurant_outlined;
    }
    if (!widget.isCuddleCareActive(figurine)) {
      return Icons.favorite_border;
    }
    if (vitality <= ptipoteStatsConfig.vitalityBubbleThreshold) {
      return Icons.bedtime_outlined;
    }
    if (hunger <= ptipoteStatsConfig.hungerBubbleThreshold) {
      return Icons.restaurant_outlined;
    }
    return null;
  }

  bool _shouldShowNeedBubble(PtipoteFigurine figurine) {
    final minInterval = ptipoteStatsConfig.needBubbleMinIntervalMinutes * 60;
    final maxInterval = ptipoteStatsConfig.needBubbleMaxIntervalMinutes * 60;
    final span = math.max(1, maxInterval - minInterval);
    final seed = figurine.id.hashCode.abs();
    final interval = minInterval + seed % span;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final phase = (nowSeconds + seed) % math.max(1, interval);
    return phase < ptipoteStatsConfig.needBubbleDisplayDurationSeconds;
  }
}

class _NeedBubble extends StatelessWidget {
  const _NeedBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _PtipotePlacement {
  const _PtipotePlacement({
    required this.left,
    required this.top,
    required this.isResting,
  });

  final double left;
  final double top;
  final bool isResting;
}

class _PtipoteMotion {
  _PtipoteMotion({
    required this.x,
    required this.direction,
    required this.speed,
    required this.moving,
    required this.nextDecision,
    required this.bounceSeed,
  });

  double x;
  int direction;
  double speed;
  bool moving;
  double nextDecision;
  double bounceSeed;
}

class _PtipoteSpriteButton extends StatefulWidget {
  const _PtipoteSpriteButton({
    required this.figurine,
    required this.selected,
    required this.isResting,
    required this.restRemainingLabel,
    required this.onTap,
  });

  final PtipoteFigurine figurine;
  final bool selected;
  final bool isResting;
  final String restRemainingLabel;
  final VoidCallback onTap;

  @override
  State<_PtipoteSpriteButton> createState() => _PtipoteSpriteButtonState();
}

class _PtipoteSpriteButtonState extends State<_PtipoteSpriteButton> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          _PtipoteSprite(figurine: widget.figurine),
          if (widget.isResting)
            Positioned(
              bottom: -18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    widget.restRemainingLabel,
                    style: const TextStyle(
                      color: Color(0xFF2B2116),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PtipoteSprite extends StatefulWidget {
  const _PtipoteSprite({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  State<_PtipoteSprite> createState() => _PtipoteSpriteState();
}

class _PtipoteSpriteState extends State<_PtipoteSprite> {
  static const _baseUrl = 'https://app.ptipotes.com/img';
  static const _extensions = <String>['png', 'webp', 'jpg', 'jpeg'];
  static final Map<String, String> _resolvedImageCache = <String, String>{};
  final _figurineService = FigurineService();
  late List<String> _candidates;
  int _index = 0;
  bool _savedResolvedPath = false;

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates();
  }

  @override
  void didUpdateWidget(covariant _PtipoteSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figurine.type != widget.figurine.type ||
        oldWidget.figurine.species != widget.figurine.species ||
        oldWidget.figurine.imagePath != widget.figurine.imagePath) {
      _candidates = _buildCandidates();
      _index = 0;
      _savedResolvedPath = false;
    }
  }

  List<String> _buildCandidates() {
    final cached = _resolvedImageCache[widget.figurine.id];
    final saved = widget.figurine.imagePath;
    final names = <String>{
      widget.figurine.type.trim(),
      widget.figurine.species.trim(),
    }..removeWhere((value) => value.isEmpty || value == '-');

    final urls = <String>[];
    if (cached != null && cached.isNotEmpty) urls.add(cached);
    if (saved.isNotEmpty) urls.add(saved);
    for (final name in names) {
      for (final ext in _extensions) {
        urls.add('$_baseUrl/${Uri.encodeComponent(name)}.$ext');
      }
    }
    urls.add('$_baseUrl/bplaceholder.png');
    return urls.toSet().toList();
  }

  void _rememberResolvedPath(String url) {
    if (_savedResolvedPath || url.contains('bplaceholder')) return;
    _savedResolvedPath = true;
    _resolvedImageCache[widget.figurine.id] = url;
    unawaited(_figurineService.cacheMyFigurineImagePath(
      figurine: widget.figurine,
      imagePath: url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final url = _candidates[_index.clamp(0, _candidates.length - 1)];
    return SizedBox(
      height: 82,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _rememberResolvedPath(url);
            });
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          if (_index < _candidates.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _index += 1);
            });
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return const Icon(Icons.image_not_supported, size: 38);
        },
      ),
    );
  }
}

class _PtipoteInfoBubble extends StatelessWidget {
  const _PtipoteInfoBubble({
    required this.maxHeight,
    required this.figurine,
    required this.vitality,
    required this.hunger,
    required this.rest,
    required this.xp,
    required this.level,
    required this.autoPreference,
    required this.isHappy,
    required this.hasIndigestion,
    required this.restStateLabel,
    required this.moodLabel,
    required this.recoveryRemaining,
    required this.cuddleCareActive,
    required this.canCuddle,
    required this.cuddleProgress,
    required this.availableSimpleMeals,
    required this.lastCuddleAt,
    required this.isResting,
    required this.isWaitingForBed,
    required this.onWake,
    required this.onSleep,
    required this.onCuddle,
    required this.onFeed,
    required this.onAutoPreferenceChanged,
  });

  final double maxHeight;
  final PtipoteFigurine figurine;
  final int vitality;
  final int hunger;
  final int rest;
  final int xp;
  final int level;
  final PtipoteAutoAssignmentPreference autoPreference;
  final bool isHappy;
  final bool hasIndigestion;
  final String restStateLabel;
  final String moodLabel;
  final Duration recoveryRemaining;
  final bool cuddleCareActive;
  final bool canCuddle;
  final double cuddleProgress;
  final int availableSimpleMeals;
  final DateTime? lastCuddleAt;
  final bool isResting;
  final bool isWaitingForBed;
  final VoidCallback onWake;
  final VoidCallback onSleep;
  final VoidCallback onCuddle;
  final VoidCallback onFeed;
  final ValueChanged<PtipoteAutoAssignmentPreference> onAutoPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: 216,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        figurine.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      'Lvl $level',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _PtipoteQuickStats(
                  moodLabel: moodLabel,
                  vitality: vitality,
                  hunger: hunger,
                  rest: rest,
                  restStateLabel: restStateLabel,
                  hasIndigestion: hasIndigestion,
                  recoveryRemaining: recoveryRemaining,
                ),
                if (isWaitingForBed) ...<Widget>[
                  const SizedBox(height: 6),
                  const Text(
                    'En attente d’une alcôve libre.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _CompactActionButton(
                        onPressed: isResting ? onWake : onSleep,
                        icon: isResting
                            ? Icons.wb_sunny_outlined
                            : Icons.bedtime_outlined,
                        label: isResting ? 'Réveil' : 'Dodo',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CooldownActionButton(
                        progress: cuddleProgress,
                        enabled: canCuddle,
                        onPressed: onCuddle,
                        icon: Icons.favorite_border,
                        label: 'Câlin',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactActionButton(
                        onPressed: availableSimpleMeals > 0 ? onFeed : null,
                        icon: Icons.restaurant_outlined,
                        label: 'Repas',
                      ),
                    ),
                  ],
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Détails',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    children: <Widget>[
                      _InfoLine(label: 'Espèce', value: figurine.species),
                      _InfoLine(label: 'Type', value: figurine.type),
                      _InfoLine(
                          label: 'Enveloppe', value: figurine.envelopeLabel),
                      _InfoLine(
                        label: 'XP',
                        value:
                            '$xp/${ptipoteStatsConfig.xpRequiredForNextLevel(level)}',
                      ),
                      _InfoLine(
                        label: 'Vitalité',
                        value: '$vitality/${figurine.maxVitality}',
                      ),
                      _InfoLine(
                        label: 'Faim',
                        value:
                            '$hunger/${ptipoteStatsConfig.maxHunger}${hasIndigestion ? ' · indigestion' : ''}',
                      ),
                      _InfoLine(
                        label: 'Repos',
                        value:
                            '$rest/${ptipoteStatsConfig.maxRest} · $restStateLabel',
                      ),
                      _InfoLine(
                        label: 'Bonheur',
                        value: moodLabel,
                      ),
                      _InfoLine(
                        label: 'Câlin',
                        value: lastCuddleAt == null
                            ? 'jamais'
                            : cuddleCareActive
                                ? 'actif · ${_relativeCuddleLabel(lastCuddleAt!)}'
                                : 'à renouveler',
                      ),
                      _InfoLine(
                        label: 'Récupération',
                        value: _recoveryLabel(recoveryRemaining),
                      ),
                      _InfoLine(
                        label: 'État',
                        value: _stateLabel(figurine, vitality),
                      ),
                      _InfoLine(
                        label: 'Auto',
                        value: _preferenceLabel(autoPreference),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: PtipoteAutoAssignmentPreference.values
                            .map((preference) {
                          return ChoiceChip(
                            label: Text(_shortPreferenceLabel(preference)),
                            selected: autoPreference == preference,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                onAutoPreferenceChanged(preference),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tour/Marché préparés : fallback Maison pour cette V1.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _stateLabel(PtipoteFigurine figurine, int currentVitality) {
    if (currentVitality <= 0) return 'épuisé';
    if (currentVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      return 'repos';
    }
    return figurine.behaviorStateLabel;
  }

  String _preferenceLabel(PtipoteAutoAssignmentPreference preference) {
    return switch (preference) {
      PtipoteAutoAssignmentPreference.home => 'Maison',
      PtipoteAutoAssignmentPreference.tower => 'Tour bientôt',
      PtipoteAutoAssignmentPreference.market => 'Marché bientôt',
    };
  }

  String _shortPreferenceLabel(PtipoteAutoAssignmentPreference preference) {
    return switch (preference) {
      PtipoteAutoAssignmentPreference.home => 'Maison',
      PtipoteAutoAssignmentPreference.tower => 'Tour',
      PtipoteAutoAssignmentPreference.market => 'Marché',
    };
  }

  String _relativeCuddleLabel(DateTime date) {
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return 'à l’instant';
    if (elapsed.inHours < 1) return 'il y a ${elapsed.inMinutes} min';
    return 'il y a ${elapsed.inHours} h';
  }

  String _recoveryLabel(Duration duration) {
    if (duration == Duration.zero) return 'Vitalité maximale';
    return _shortDurationLabel(duration);
  }
}

class _PtipoteQuickStats extends StatelessWidget {
  const _PtipoteQuickStats({
    required this.moodLabel,
    required this.vitality,
    required this.hunger,
    required this.rest,
    required this.restStateLabel,
    required this.hasIndigestion,
    required this.recoveryRemaining,
  });

  final String moodLabel;
  final int vitality;
  final int hunger;
  final int rest;
  final String restStateLabel;
  final bool hasIndigestion;
  final Duration recoveryRemaining;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _QuickStatChip(
              emoji: _moodEmoji(moodLabel),
              color: _moodColor(context, moodLabel),
            ),
            _QuickStatChip(
              icon: _batteryIcon(vitality),
              label: '$vitality',
              color: _vitalityColor(context, vitality),
            ),
            _QuickStatChip(
              icon: hasIndigestion
                  ? Icons.sick_outlined
                  : Icons.restaurant_outlined,
              label: '$hunger',
              color: hasIndigestion
                  ? Theme.of(context).colorScheme.error
                  : _hungerColor(context, hunger),
            ),
            _QuickStatChip(
              emoji: _restEmoji(restStateLabel),
              color: _restColor(context, rest),
            ),
            _QuickStatChip(
              icon: Icons.timer_outlined,
              label: _shortDurationLabel(recoveryRemaining),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  String _moodEmoji(String mood) {
    return switch (mood) {
      'Heureux' => '🤩',
      'Bien' => '🙂',
      _ => '😟',
    };
  }

  Color _moodColor(BuildContext context, String mood) {
    return switch (mood) {
      'Heureux' => const Color(0xFF2E9B57),
      'Bien' => const Color(0xFFE2952D),
      _ => Theme.of(context).colorScheme.error,
    };
  }

  IconData _batteryIcon(int value) {
    if (value < 40) return Icons.battery_1_bar_outlined;
    if (value < 60) return Icons.battery_2_bar_outlined;
    return Icons.battery_full_outlined;
  }

  Color _vitalityColor(BuildContext context, int value) {
    if (value < 40) return Theme.of(context).colorScheme.error;
    if (value < 60) return const Color(0xFFE2952D);
    return const Color(0xFF2E9B57);
  }

  Color _hungerColor(BuildContext context, int value) {
    if (value > ptipoteStatsConfig.indigestionHungerThreshold) {
      return Theme.of(context).colorScheme.error;
    }
    if (value < 40) return Theme.of(context).colorScheme.error;
    if (value < 60) return const Color(0xFFE2952D);
    return const Color(0xFF2E9B57);
  }

  String _restEmoji(String label) {
    return switch (label) {
      'Bien reposé' => '🤩',
      'Reposé' => '😴',
      'Fatigué' => '😪',
      _ => '🥱',
    };
  }

  Color _restColor(BuildContext context, int value) {
    if (value < ptipoteStatsConfig.tiredThreshold) {
      return Theme.of(context).colorScheme.error;
    }
    if (value < ptipoteStatsConfig.restedThreshold) {
      return const Color(0xFFE2952D);
    }
    return const Color(0xFF2E9B57);
  }
}

class _QuickStatChip extends StatelessWidget {
  const _QuickStatChip({
    this.icon,
    this.emoji,
    this.label = '',
    required this.color,
  });

  final IconData? icon;
  final String? emoji;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (emoji != null)
          Text(
            emoji!,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          )
        else if (icon != null)
          Icon(icon, size: 16, color: color),
        if (label.isNotEmpty) ...<Widget>[
          const SizedBox(width: 2),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

String _shortDurationLabel(Duration duration) {
  if (duration == Duration.zero) return 'max';
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h$minutes';
  }
  return '${duration.inMinutes}m';
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 16),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _CooldownActionButton extends StatelessWidget {
  const _CooldownActionButton({
    required this.progress,
    required this.enabled,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final double progress;
  final bool enabled;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled
                    ? colorScheme.secondaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: TextButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: enabled
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefugeEmptyState extends StatelessWidget {
  const _RefugeEmptyState();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Aucun P’TIPOTE dans le refuge pour le moment.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlcovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 2);
    canvas.drawArc(rect, 3.14159, 3.14159, true, paint);
    canvas.drawArc(rect, 3.14159, 3.14159, false, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Zone0InventorySheet extends StatelessWidget {
  const Zone0InventorySheet({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final stacks = gameState.inventory;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: <Widget>[
          Text(
            'Inventaire global',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Stock ${gameState.inventoryUsedAmount}/${gameState.globalStockCapacity} · ${stacks.length}/${gameState.inventorySlotLimit} slots',
          ),
          const SizedBox(height: 12),
          _FirebaseSyncStatus(gameState: gameState),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children:
                List<Widget>.generate(gameState.inventorySlotLimit, (index) {
              final stack = index < stacks.length ? stacks[index] : null;
              return _InventorySlot(stack: stack);
            }),
          ),
        ],
      ),
    );
  }
}

class _FirebaseSyncStatus extends StatelessWidget {
  const _FirebaseSyncStatus({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final error = gameState.lastFirebaseError;
    final color = error == null
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    final lastSync = gameState.lastFirebaseSyncAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              gameState.isFirebaseSyncing
                  ? Icons.sync
                  : error == null
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error == null
                    ? '${gameState.firebaseSyncLabel}${lastSync == null ? '' : ' · ${_formatTime(lastSync)}'}'
                    : '${gameState.firebaseSyncLabel} · $error',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _InventorySlot extends StatelessWidget {
  const _InventorySlot({required this.stack});

  final Zone0InventoryStack? stack;

  @override
  Widget build(BuildContext context) {
    final filled = stack != null;
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: filled
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
          ),
          boxShadow: filled
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Icon(
                _resourceIcon(stack?.resource),
                size: 36,
                color: filled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.28),
              ),
            ),
            if (filled)
              Positioned(
                right: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      '${stack!.amount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            if (filled)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  stack!.resource,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _resourceIcon(String? resource) {
  return switch (resource) {
    'Organique' => Icons.eco_outlined,
    'Débris' || 'Debris' => Icons.construction_outlined,
    'Déchets' || 'Dechets' => Icons.delete_sweep_outlined,
    'Minéral' || 'Mineral' => Icons.diamond_outlined,
    'Énergie' || 'Energie' => Icons.bolt_outlined,
    'Repas' || 'Repas simple' => Icons.restaurant_outlined,
    'Filtre' || 'Cartouche de filtration' => Icons.filter_alt_outlined,
    'Tenue ombragée' => Icons.checkroom_outlined,
    'Meuble simple' => Icons.chair_outlined,
    'Ventilation Termite' => Icons.air_outlined,
    'Lumière solaire' => Icons.lightbulb_outline,
    _ => Icons.inventory_2_outlined,
  };
}

String _ptipoteActivityUnavailableReason(
  Zone0GameState gameState,
  PtipoteFigurine figurine,
) {
  final vitality = gameState.vitalityFor(figurine);
  if (gameState.isOnMission(figurine.id)) return 'en mission';
  if (gameState.isResting(figurine)) return 'au repos';
  if (gameState.isAssignedToTower(figurine.id)) return 'à la Tour';
  if (gameState.isAssignedToWorkshop(figurine.id)) return 'à l’Atelier';
  if (gameState.isAssignedToMarket(figurine.id)) return 'au Marché';
  if (vitality < ptipoteStatsConfig.minimumMissionVitality) {
    return 'trop fatigué';
  }
  return 'indisponible';
}

Future<PtipoteFigurine?> _pickPtipoteForActivity({
  required BuildContext context,
  required Zone0GameState gameState,
  required List<PtipoteFigurine> figurines,
  required String title,
}) {
  return showModalBottomSheet<PtipoteFigurine>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (figurines.isEmpty)
              const Text('Aucun P’TIPOTE trouvé.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: figurines.map((figurine) {
                  final selectable = !gameState.isBusy(figurine) &&
                      gameState.vitalityFor(figurine) >=
                          ptipoteStatsConfig.minimumMissionVitality;
                  final suffix = selectable
                      ? 'V${gameState.vitalityFor(figurine)}'
                      : _ptipoteActivityUnavailableReason(gameState, figurine);
                  return ChoiceChip(
                    label: Text('${figurine.displayName} · $suffix'),
                    selected: false,
                    onSelected: selectable
                        ? (_) => Navigator.of(context).pop(figurine)
                        : null,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    ),
  );
}

class MissionReportsSheet extends StatelessWidget {
  const MissionReportsSheet({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final reports = gameState.reports.reversed.toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: <Widget>[
          Text(
            'Messages P’TIPOTE',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            const _SheetEmptyState(text: 'Aucun rapport de mission.')
          else
            ...reports.map(
              (report) => Dismissible(
                key: ValueKey(report.id),
                direction: DismissDirection.endToStart,
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 18),
                      child: Icon(Icons.delete_outline, color: Colors.white),
                    ),
                  ),
                ),
                onDismissed: (_) => gameState.deleteReport(report.id),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${report.figurineName} revient de ${report.biomeLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Durée ${report.durationLabel} · ${report.intensityLabel}',
                        ),
                        Text('Récolte : ${_formatRewards(report.rewards)}'),
                        Text(
                          'XP : +${report.xpGain}${report.leveledUp ? ' · niveau ${report.levelAfter}' : ''}',
                        ),
                        if (report.baseRiskPercent > 0 ||
                            report.realRiskPercent > 0) ...<Widget>[
                          Text(
                            'Sécurité au lancement : ${report.securityAtLaunch}',
                          ),
                          Text('Danger initial : ${report.baseRiskPercent}%'),
                          Text(
                              'Réduction Tour : -${report.securityReduction}%'),
                          Text('Danger réel : ${report.realRiskPercent}%'),
                        ],
                        Text('Incident : ${report.incidentLabel}'),
                        Text('Vitalité restante : ${report.vitalityRemaining}'),
                        Text('Faim restante : ${report.hungerRemaining}'),
                        Text('Bonheur au retour : ${report.moodLabel}'),
                        if (report.finalStateLabel.isNotEmpty)
                          Text(report.finalStateLabel),
                        if (report.inventoryFull)
                          const Text(
                            'Inventaire plein : le surplus est perdu.',
                          ),
                        const SizedBox(height: 4),
                        Text(
                          report.completedAt
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetEmptyState extends StatelessWidget {
  const _SheetEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class LisierePage extends StatefulWidget {
  const LisierePage(
      {super.key, required this.gameState, required this.campHeartLevel});

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  State<LisierePage> createState() => _LisierePageState();
}

class _LisierePageState extends State<LisierePage> {
  final _figurineService = FigurineService();
  ForageBiome _biome = ForageBiome.plaineRiche;
  ForageDuration _duration = ForageDuration.oneHour;
  ForageIntensity _intensity = ForageIntensity.normal;
  final Set<String> _selectedFigurineIds = <String>{};

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_onGameStateChanged);
    widget.gameState.resolveDueForageMissions();
    widget.gameState.resolveDueTowerMissions();
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_onGameStateChanged);
    super.dispose();
  }

  void _onGameStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final unlockedBiomes =
        ForageBiome.values.where(widget.gameState.isBiomeUnlocked).toList();
    return DefaultTabController(
      length: 1 + unlockedBiomes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lisière proche'),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              const Tab(text: 'Récolte'),
              ...unlockedBiomes.map((biome) =>
                  Tab(text: lisiereForageConfig.biomes[biome]!.label)),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[
          SafeArea(
              child: StreamBuilder<List<PtipoteFigurine>>(
            stream: _figurineService.watchMyFigurines(),
            builder: (context, snapshot) {
              final figurines = snapshot.data ?? const <PtipoteFigurine>[];
              _selectedFigurineIds.removeWhere((id) {
                return figurines.any(
                  (figurine) =>
                      figurine.id == id &&
                      (widget.gameState.isBusy(figurine) ||
                          widget.gameState.vitalityFor(figurine) <
                              ptipoteStatsConfig.minimumMissionVitality),
                );
              });
              final selectedFigurines = figurines
                  .where(
                      (figurine) => _selectedFigurineIds.contains(figurine.id))
                  .toList();
              final estimates = <PtipoteFigurine, ForageEstimate>{
                for (final figurine in selectedFigurines)
                  figurine: _estimate(figurine),
              };
              final groupEstimate = estimates.isEmpty
                  ? null
                  : ForageGroupEstimate.fromEstimates(estimates.values);
              final inventoryOverflow = groupEstimate == null
                  ? 0
                  : math.max(
                      0,
                      groupEstimate.totalRewards -
                          widget.gameState
                              .inventoryFreeCapacityFor(groupEstimate.rewards),
                    );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _ForageChoiceCard(
                    title: 'Biome',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ForageBiome.values
                          .where(widget.gameState.isBiomeUnlocked)
                          .map((biome) {
                        final config = lisiereForageConfig.biomes[biome]!;
                        return ChoiceChip(
                          label: Text(config.label),
                          selected: _biome == biome,
                          onSelected: (_) => setState(() => _biome = biome),
                        );
                      }).toList(),
                    ),
                  ),
                  _ForageChoiceCard(
                    title: 'P’TIPOTE',
                    child: figurines.isEmpty
                        ? const Text('Aucun P’TIPOTE disponible.')
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: figurines.map((figurine) {
                              final vitality =
                                  widget.gameState.vitalityFor(figurine);
                              final onMission =
                                  widget.gameState.isOnMission(figurine.id);
                              final resting =
                                  widget.gameState.isResting(figurine);
                              final busy = widget.gameState.isBusy(figurine);
                              final tooTired = vitality <
                                  ptipoteStatsConfig.minimumMissionVitality;
                              final suffix = onMission
                                  ? ' · mission'
                                  : resting
                                      ? ' · repos'
                                      : tooTired
                                          ? ' · trop fatigué'
                                          : '';
                              return ChoiceChip(
                                label: Text(
                                  '${figurine.displayName} · V$vitality$suffix',
                                ),
                                selected:
                                    _selectedFigurineIds.contains(figurine.id),
                                onSelected: busy || tooTired
                                    ? null
                                    : (_) => setState(() {
                                          if (_selectedFigurineIds
                                              .contains(figurine.id)) {
                                            _selectedFigurineIds
                                                .remove(figurine.id);
                                          } else {
                                            _selectedFigurineIds
                                                .add(figurine.id);
                                          }
                                        }),
                              );
                            }).toList(),
                          ),
                  ),
                  _ForageChoiceCard(
                    title: 'Durée',
                    child: Wrap(
                      spacing: 8,
                      children: ForageDuration.values.map((duration) {
                        final config = lisiereForageConfig.durations[duration]!;
                        final real = config.realDuration(
                          lisiereForageConfig.forageTimeScale,
                        );
                        return ChoiceChip(
                          label: Text(
                              '${config.label} (${real.inMinutes} min test)'),
                          selected: _duration == duration,
                          onSelected: (_) =>
                              setState(() => _duration = duration),
                        );
                      }).toList(),
                    ),
                  ),
                  _ForageChoiceCard(
                    title: 'Intensité',
                    child: Wrap(
                      spacing: 8,
                      children: ForageIntensity.values.map((intensity) {
                        return ChoiceChip(
                          label: Text(lisiereForageConfig
                              .intensities[intensity]!.label),
                          selected: _intensity == intensity,
                          onSelected: (_) =>
                              setState(() => _intensity = intensity),
                        );
                      }).toList(),
                    ),
                  ),
                  if (groupEstimate != null)
                    _ForageEstimateCard(
                      estimate: groupEstimate,
                      selectedCount: selectedFigurines.length,
                    ),
                  const SizedBox(height: 12),
                  if (inventoryOverflow > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Attention : les gains potentiels dépassent le stock disponible. Environ $inventoryOverflow ressource(s) seront perdues si rien n’est rangé.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (groupEstimate != null &&
                      groupEstimate.restWarningLabels.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        groupEstimate.restWarningLabels.length == 1
                            ? '${groupEstimate.restWarningLabels.first} risque de revenir très fatigué et ira directement se coucher.'
                            : '${groupEstimate.restWarningLabels.join(', ')} risquent de revenir très fatigués et iront directement se coucher.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: groupEstimate?.canLaunch == true
                        ? () => _launchMissions(estimates)
                        : null,
                    icon: const Icon(Icons.forest_outlined),
                    label: Text(
                      selectedFigurines.length <= 1
                          ? 'Envoyer récolter'
                          : 'Envoyer ${selectedFigurines.length} P’TIPOTES',
                    ),
                  ),
                  if (groupEstimate != null && !groupEstimate.canLaunch)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Un ou plusieurs P’TIPOTES sont trop fatigués pour partir.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _ActiveMissionsCard(gameState: widget.gameState),
                ],
              );
            },
          )),
          ...unlockedBiomes.map((biome) => _BiomeBuildingsTab(
                gameState: widget.gameState,
                biome: biome,
                campHeartLevel: widget.campHeartLevel,
              )),
        ]),
      ),
    );
  }

  ForageEstimate _estimate(PtipoteFigurine figurine) {
    final rewards = _calculateRewards(figurine);
    final duration = lisiereForageConfig.durations[_duration]!;
    final intensity = lisiereForageConfig.intensities[_intensity]!;
    final cost =
        (duration.baseVitalityCost * intensity.vitalityMultiplier).round();
    final baseRiskPercent = _baseRiskPercent();
    final securityAtLaunch =
        widget.gameState.biomeSecurity[_biome]?.localSecurity ?? 0;
    final securityReduction = _securityReduction();
    final riskPercent = _riskPercent(figurine);
    final vitality = widget.gameState.vitalityFor(figurine);
    return ForageEstimate(
      rewards: rewards,
      vitalityCost: cost,
      xpGain: _xpGain(figurine),
      figurineName: figurine.displayName,
      finalVitality: math.max(0, vitality - cost),
      riskPercent: riskPercent,
      riskLabel: _riskLabel(riskPercent),
      baseRiskPercent: baseRiskPercent,
      securityAtLaunch: securityAtLaunch,
      securityReduction: securityReduction,
      possibleHazards: _possibleHazards(),
      zoneFatigueLabel: intensity.zoneFatigueLabel,
      canLaunch: vitality >= ptipoteStatsConfig.minimumMissionVitality &&
          !_isLongMissionRefused(figurine) &&
          !widget.gameState.isBusy(figurine),
    );
  }

  int _xpGain(PtipoteFigurine figurine) {
    final base = lisiereForageConfig.xpGainByDuration[_duration] ?? 8;
    final intensity =
        lisiereForageConfig.intensityXpMultiplier[_intensity] ?? 1;
    var modifier = 1 + figurine.xpGainBonus;
    final restState = widget.gameState.restStateFor(figurine);
    if (restState == PtipoteRestState.wellRested) {
      modifier += ptipoteStatsConfig.wellRestedXpBonus;
    } else if (restState == PtipoteRestState.tired ||
        restState == PtipoteRestState.exhausted) {
      modifier -= ptipoteStatsConfig.tiredXpPenalty;
    }
    if (widget.gameState.hasIndigestion(figurine)) {
      modifier -= ptipoteStatsConfig.indigestionXpPenalty;
    }
    final withBonus = base * intensity * math.max(0.1, modifier);
    return math.max(1, withBonus.round());
  }

  Map<String, int> _calculateRewards(PtipoteFigurine figurine) {
    final biome = lisiereForageConfig.biomes[_biome]!;
    final duration = lisiereForageConfig.durations[_duration]!;
    final intensity = lisiereForageConfig.intensities[_intensity]!;
    final rewards = <String, int>{};
    for (final entry in biome.baseRewards.entries) {
      var value =
          entry.value * duration.theoreticalHours * intensity.rewardMultiplier;
      final restState = widget.gameState.restStateFor(figurine);
      if (restState == PtipoteRestState.wellRested) {
        value *= 1 + ptipoteStatsConfig.wellRestedRewardBonus;
      } else if (restState == PtipoteRestState.tired ||
          restState == PtipoteRestState.exhausted) {
        value *= 1 - ptipoteStatsConfig.tiredRewardPenalty;
      }
      if (_biome == ForageBiome.plaineRiche &&
          figurine.elementType == PtipoteElementType.vegetal &&
          entry.key == 'Organique') {
        value *= 1.10;
      }
      if (_biome == ForageBiome.bassinMineral &&
          figurine.elementType == PtipoteElementType.mineral &&
          entry.key == 'Minéral') {
        value *= 1.10;
      }
      if (_biome == ForageBiome.sousBois &&
          figurine.elementType == PtipoteElementType.fungal &&
          entry.key == 'Organique') {
        value *= 1.10;
      }
      rewards[entry.key] = math.max(0, value.round());
    }
    return rewards;
  }

  int _riskPercent(PtipoteFigurine figurine) {
    var risk = _baseRiskPercent() - _securityReduction();
    if (_biome == ForageBiome.plaineRiche &&
        figurine.elementType == PtipoteElementType.vegetal) {
      risk -= 2;
    }
    if (_biome == ForageBiome.bassinMineral &&
        figurine.elementType == PtipoteElementType.mineral) {
      risk -= 2;
    }
    if (_biome == ForageBiome.sousBois &&
        figurine.elementType == PtipoteElementType.fungal) {
      risk -= 2;
    }
    if (widget.gameState.restStateFor(figurine) == PtipoteRestState.exhausted) {
      risk += 10;
    }
    return math.max(lisiereForageConfig.minimumMissionRisk, risk);
  }

  bool _isLongMissionRefused(PtipoteFigurine figurine) {
    final exhausted =
        widget.gameState.restStateFor(figurine) == PtipoteRestState.exhausted;
    final longMission = _duration == ForageDuration.sixHours ||
        _duration == ForageDuration.tenHours;
    return exhausted && longMission;
  }

  int _baseRiskPercent() {
    final biome = lisiereForageConfig.biomes[_biome]!;
    final intensity = lisiereForageConfig.intensities[_intensity]!;
    return biome.baseRiskPercent + intensity.riskModifierPercent;
  }

  int _securityReduction() {
    final localSecurity =
        widget.gameState.biomeSecurity[_biome]?.localSecurity ?? 0;
    return (localSecurity *
            towerOperationsConfig.maximumLocalRiskReductionPercent /
            100)
        .round();
  }

  List<String> _possibleHazards() {
    final biome = lisiereForageConfig.biomes[_biome]!;
    return biome.hazards.map(_hazardLabel).toList();
  }

  String _hazardLabel(ForageHazard hazard) {
    return switch (hazard) {
      ForageHazard.pollution => 'Pollution',
      ForageHazard.droneErrant => 'Drone errant',
      ForageHazard.climatDifficile => 'Climat difficile',
      ForageHazard.terrainInstable => 'Terrain instable',
      ForageHazard.none => 'Aucun',
    };
  }

  String _riskLabel(int risk) {
    if (risk <= 14) return 'Très sûr';
    if (risk <= 24) return 'Sûr';
    if (risk <= 39) return 'Incertain';
    if (risk <= 54) return 'Risqué';
    return 'Très risqué';
  }

  void _launchMissions(Map<PtipoteFigurine, ForageEstimate> estimates) {
    final launchable = estimates.entries
        .where((entry) => entry.value.canLaunch)
        .map((entry) => entry.key)
        .toList();
    if (launchable.isEmpty) return;
    final groupEstimate = ForageGroupEstimate.fromEstimates(
      launchable.map((figurine) => estimates[figurine]!),
    );
    widget.gameState.startForageMission(
      figurines: launchable,
      biome: _biome,
      duration: _duration,
      intensity: _intensity,
      expectedRewards: groupEstimate.rewards,
      vitalityCostByMember: <String, int>{
        for (final figurine in launchable)
          figurine.id: estimates[figurine]!.vitalityCost,
      },
      riskPercent: groupEstimate.riskPercent,
      riskLabel: groupEstimate.riskLabel,
      baseRiskPercent: groupEstimate.baseRiskPercent,
      securityAtLaunch: groupEstimate.securityAtLaunch,
      securityReduction: groupEstimate.securityReduction,
      xpGainByMember: <String, int>{
        for (final figurine in launchable)
          figurine.id: estimates[figurine]!.xpGain,
      },
    );
    _selectedFigurineIds.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launchable.length <= 1
              ? '1 P’TIPOTE part en Lisière.'
              : '${launchable.length} P’TIPOTES partent en équipe.',
        ),
      ),
    );
  }
}

class ForageEstimate {
  const ForageEstimate({
    required this.rewards,
    required this.vitalityCost,
    required this.xpGain,
    required this.figurineName,
    required this.finalVitality,
    required this.riskPercent,
    required this.riskLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.possibleHazards,
    required this.zoneFatigueLabel,
    required this.canLaunch,
  });

  final Map<String, int> rewards;
  final int vitalityCost;
  final int xpGain;
  final String figurineName;
  final int finalVitality;
  final int riskPercent;
  final String riskLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final List<String> possibleHazards;
  final String zoneFatigueLabel;
  final bool canLaunch;

  int get totalRewards {
    return rewards.values.fold(0, (total, amount) => total + amount);
  }
}

class ForageGroupEstimate {
  ForageGroupEstimate({
    required this.rewards,
    required this.vitalityCost,
    required this.xpGain,
    required this.restWarningLabels,
    required this.riskPercent,
    required this.riskLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.possibleHazards,
    required this.zoneFatigueLabel,
    required this.canLaunch,
  });

  factory ForageGroupEstimate.fromEstimates(
    Iterable<ForageEstimate> estimates,
  ) {
    final list = estimates.toList();
    final rewards = <String, int>{};
    var vitalityCost = 0;
    var xpGain = 0;
    final restWarningLabels = <String>[];
    var riskPercent = 0;
    var riskLabel = 'Très sûr';
    var baseRiskPercent = 0;
    var securityAtLaunch = 0;
    var securityReduction = 0;
    final possibleHazards = <String>{};
    var zoneFatigueLabel = 'faible';
    var canLaunch = list.isNotEmpty;

    for (final estimate in list) {
      vitalityCost += estimate.vitalityCost;
      xpGain += estimate.xpGain;
      if (estimate.finalVitality <=
          ptipoteStatsConfig.minVitalityBeforeAutoRest) {
        restWarningLabels.add(estimate.figurineName);
      }
      canLaunch = canLaunch && estimate.canLaunch;
      if (estimate.riskPercent >= riskPercent) {
        riskPercent = estimate.riskPercent;
        riskLabel = estimate.riskLabel;
        baseRiskPercent = estimate.baseRiskPercent;
        securityAtLaunch = estimate.securityAtLaunch;
        securityReduction = estimate.securityReduction;
      }
      possibleHazards.addAll(estimate.possibleHazards);
      zoneFatigueLabel = estimate.zoneFatigueLabel;
      for (final entry in estimate.rewards.entries) {
        rewards[entry.key] = (rewards[entry.key] ?? 0) + entry.value;
      }
    }

    return ForageGroupEstimate(
      rewards: rewards,
      vitalityCost: vitalityCost,
      xpGain: xpGain,
      restWarningLabels: restWarningLabels,
      riskPercent: riskPercent,
      riskLabel: riskLabel,
      baseRiskPercent: baseRiskPercent,
      securityAtLaunch: securityAtLaunch,
      securityReduction: securityReduction,
      possibleHazards: possibleHazards.toList(),
      zoneFatigueLabel: zoneFatigueLabel,
      canLaunch: canLaunch,
    );
  }

  final Map<String, int> rewards;
  final int vitalityCost;
  final int xpGain;
  final List<String> restWarningLabels;
  final int riskPercent;
  final String riskLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final List<String> possibleHazards;
  final String zoneFatigueLabel;
  final bool canLaunch;

  int get totalRewards {
    return rewards.values.fold(0, (total, amount) => total + amount);
  }
}

class _BiomeBuildingsTab extends StatelessWidget {
  const _BiomeBuildingsTab(
      {required this.gameState,
      required this.biome,
      required this.campHeartLevel});
  final Zone0GameState gameState;
  final ForageBiome biome;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final label = lisiereForageConfig.biomes[biome]!.label;
    if (biome != ForageBiome.plaineRiche) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
            'Les bâtiments de $label seront révélés avec les prochains Plans du Kernel.',
            textAlign: TextAlign.center),
      ));
    }
    final built = gameState.plaineNurseryLevel > 0;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Nurserie P’TIBUG',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(built
                    ? 'Construite · niveau ${gameState.plaineNurseryLevel}'
                    : 'La végétalisation de la Plaine doit être stabilisée avant de développer la nurserie.'),
                const SizedBox(height: 10),
                if (!built)
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => _ConstructionProjectSheet(
                        gameState: gameState,
                        targetId: 'plaineNursery',
                        title: 'Construire la Nurserie P’TIBUG',
                        description:
                            'La Nurserie a besoin d’une Plaine végétalisée et de matériaux réservés.',
                        footer:
                            'Les prérequis et ressources du chantier sont affichés ici.',
                      ),
                    ),
                    icon: const Icon(Icons.pets_outlined),
                    label: const Text('Voir les prérequis'),
                  )
                else
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PTibugNurseryPage(
                          gameState: gameState, campHeartLevel: campHeartLevel),
                    )),
                    child: const Text('Ouvrir la Nurserie'),
                  ),
              ]),
        )),
      ]),
    );
  }
}

class _ForageChoiceCard extends StatelessWidget {
  const _ForageChoiceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ForageEstimateCard extends StatelessWidget {
  const _ForageEstimateCard({
    required this.estimate,
    required this.selectedCount,
  });

  final ForageGroupEstimate estimate;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Estimation',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Groupe : $selectedCount P’TIPOTE(s)'),
            Text('Gain : ${_formatRewards(estimate.rewards)}'),
            Text('Vitalité consommée : ${estimate.vitalityCost}'),
            Text('XP gagnée : ${estimate.xpGain} total'),
            Text('Sécurité locale : ${estimate.securityAtLaunch}%'),
            Text('Danger du biome : ${estimate.baseRiskPercent}%'),
            Text('Réduction Tour : -${estimate.securityReduction}%'),
            Text(
              'Danger réel : ${estimate.riskPercent}% — ${estimate.riskLabel}',
            ),
            Text(
              'Événements possibles : ${estimate.possibleHazards.isEmpty ? 'aucun' : estimate.possibleHazards.join(', ')}',
            ),
            Text('Fatigue de zone prévue : ${estimate.zoneFatigueLabel}'),
          ],
        ),
      ),
    );
  }
}

class _ActiveMissionsCard extends StatelessWidget {
  const _ActiveMissionsCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final active = gameState.missions
        .where((mission) => mission.status == ForageMissionStatus.active)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Missions en cours',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (active.isEmpty)
              const Text('Aucune mission en cours.')
            else
              ...active.map((mission) {
                final biome = lisiereForageConfig.biomes[mission.biome]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${mission.figurineName} · ${biome.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_countdownLabel(mission.endTime)),
                      TextButton.icon(
                        onPressed: () => _confirmEmergencyReturn(
                          context,
                          mission,
                        ),
                        icon: const Icon(Icons.keyboard_return_outlined),
                        label: const Text('Retour'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEmergencyReturn(
    BuildContext context,
    ForageMission mission,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retour d’urgence'),
        content: const Text(
          'Attention les P’TIPOTES rentrent en urgence. Un malus de +5% sur les événements sera appliqué.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final result = gameState.emergencyReturnForageMission(mission.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }
}

String _formatRewards(Map<String, int> rewards) {
  if (rewards.isEmpty) return 'aucune';
  return rewards.entries
      .where((entry) => entry.value > 0)
      .map((entry) => '+${entry.value} ${entry.key}')
      .join(', ');
}

class CampHeartState extends ChangeNotifier {
  CampHeartState({
    required this.campHeartLevel,
    required this.vegetalizationXp,
    required this.totalVegetalizationInvested,
  });

  factory CampHeartState.placeholder() {
    return CampHeartState(
      campHeartLevel: 1,
      vegetalizationXp: 0,
      totalVegetalizationInvested: 0,
    );
  }

  int campHeartLevel;
  int vegetalizationXp;
  int totalVegetalizationInvested;

  CampHeartStageConfig get currentStage {
    return campHeartConfig.stageForLevel(campHeartLevel);
  }

  CampStage get campStage => currentStage.stage;

  CampHeartStageConfig? get nextStage {
    return campHeartConfig.nextStageForLevel(campHeartLevel);
  }

  int? get organicRequiredForNextLevel {
    return currentStage.organicRequiredForNextLevel;
  }

  // Legacy state key and existing widgets still use this progress name.
  int? get vegetalizationXpRequired => organicRequiredForNextLevel;

  bool get isMaxLevel => organicRequiredForNextLevel == null;

  double get progressRatio {
    final required = organicRequiredForNextLevel;
    if (required == null) return 1;
    return (vegetalizationXp / required).clamp(0, 1);
  }

  int get activePtipoteComfortLimit {
    return currentStage.activePtipoteComfortLimit;
  }

  int? get populationMin => currentStage.populationMin;

  int? get populationMax => currentStage.populationMax;

  int get refugeHappinessBonus => currentStage.refugeHappinessBonus;

  bool canDepositOrganic(Zone0GameState gameState) {
    return !isMaxLevel && gameState.resourceAmount('Organique') > 0;
  }

  String depositOrganic(int requestedAmount, Zone0GameState gameState) {
    if (isMaxLevel) return 'Le Cœur du Camp est au niveau max V1.';
    final amount = gameState.removeResource('Organique', requestedAmount);
    if (amount <= 0) return 'Stock Organique vide dans la Maison.';

    vegetalizationXp += amount;
    totalVegetalizationInvested += amount;

    String? levelUpMessage;
    while (!isMaxLevel) {
      final required = organicRequiredForNextLevel!;
      if (vegetalizationXp < required) break;
      vegetalizationXp -= required;
      campHeartLevel =
          math.min(campHeartLevel + 1, campHeartConfig.stages.length);
      levelUpMessage =
          'Le Cœur du Camp grandit. Le camp devient ${currentStage.label}.';
    }

    notifyListeners();
    unawaited(gameState.saveCampHeartToFirebase(toFirebaseData()));
    return levelUpMessage ?? '+$amount Organique investi.';
  }

  void applyFirebaseData(Map<String, dynamic> data) {
    campHeartLevel = _readInt(data['campHeartLevel'], fallback: campHeartLevel)
        .clamp(1, campHeartConfig.stages.length);
    vegetalizationXp =
        _readInt(data['vegetalizationXp'], fallback: vegetalizationXp);
    totalVegetalizationInvested = _readInt(
      data['totalVegetalizationInvested'],
      fallback: totalVegetalizationInvested,
    );
    notifyListeners();
  }

  Map<String, dynamic> toFirebaseData() {
    return <String, dynamic>{
      'campHeartLevel': campHeartLevel,
      'campStage': campStage.name,
      'vegetalizationXp': vegetalizationXp,
      'vegetalizationXpRequired': vegetalizationXpRequired,
      'totalVegetalizationInvested': totalVegetalizationInvested,
      'activePtipoteComfortLimit': activePtipoteComfortLimit,
      'populationMin': populationMin,
      'populationMax': populationMax,
      'refugeHappinessBonus': refugeHappinessBonus,
    };
  }

  int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}

class CampHeartPage extends StatefulWidget {
  const CampHeartPage({
    super.key,
    required this.state,
    required this.gameState,
  });

  final CampHeartState state;
  final Zone0GameState gameState;

  @override
  State<CampHeartPage> createState() => _CampHeartPageState();
}

class _CampHousingTab extends StatelessWidget {
  const _CampHousingTab({required this.gameState});

  final Zone0GameState gameState;

  void _showStatInfo(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = gameState.constructionProjects['housing'];
    final activity = math.max(0, gameState.currentPopulation * 10);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Text('Habitation',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
              'Le Cœur organise la communauté. Touchez une statistique pour comprendre son rôle.'),
          const SizedBox(height: 14),
          _HabitationStatCard(
            icon: Icons.groups_outlined,
            title: 'Population',
            value:
                '${gameState.currentPopulation} / ${gameState.housingCapacity}',
            onTap: () => _showStatInfo(context, 'Population',
                'Les habitants arrivent grâce aux missions du Kernel. Le Cœur fixe la capacité générale du refuge.'),
          ),
          _HabitationStatCard(
            icon: Icons.sentiment_satisfied_alt_outlined,
            title: 'Bien-être',
            value: '${gameState.campWellbeing}%',
            subtitle: gameState.housingWellbeingPenalty > 0
                ? 'Logements : -${gameState.housingWellbeingPenalty}'
                : 'Aucun malus de logement',
            onTap: () => _showStatInfo(context, 'Bien-être',
                'Le bien-être reflète la stabilité du refuge. Les habitants sans logement appliquent un malus jusqu’à la fin d’un chantier de logement.'),
          ),
          _HabitationStatCard(
            icon: Icons.hub_outlined,
            title: 'Activité locale',
            value: '$activity%',
            subtitle: 'Préparée pour le Marché',
            onTap: () => _showStatInfo(context, 'Activité locale',
                'Cette valeur agrégée représentera plus tard la vitalité du refuge et les opportunités du Marché.'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Logements',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                      '${gameState.housingUnits} unité(s) · ${gameState.unhousedPopulation} habitant(s) sans logement'),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => _ConstructionProjectSheet(
                        gameState: gameState,
                        targetId: 'housing',
                        title: 'Construire un logement',
                        description:
                            'Un logement accueille trois habitants. Les matériaux sont posés avant le chantier.',
                        footer: 'Capacité : +3 habitants à la fin des travaux.',
                      ),
                    ),
                    icon: const Icon(Icons.home_work_outlined),
                    label: const Text('Construire un logement'),
                  ),
                  if (project != null &&
                      project.completedAt != null &&
                      gameState.communityConstructionThanks?.sourceProjectId !=
                          project.projectId) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        final result = gameState
                            .thankResidentsForHousing(project.projectId);
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)));
                      },
                      child: const Text('Remercier les habitants'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitationStatCard extends StatelessWidget {
  const _HabitationStatCard(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onTap,
      this.subtitle});
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: <Widget>[
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (subtitle != null) Text(subtitle!),
                  ])),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );
}

class _CampHeartPageState extends State<CampHeartPage> {
  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_onGameStateChanged);
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_onGameStateChanged);
    super.dispose();
  }

  void _onGameStateChanged() {
    if (mounted) setState(() {});
  }

  void _deposit(int amount) {
    final message = widget.state.depositOrganic(amount, widget.gameState);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final stage = state.currentStage;
    final nextStage = state.nextStage;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cœur du Camp'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Végétalisation', icon: Icon(Icons.eco_outlined)),
              Tab(text: 'Générateur', icon: Icon(Icons.battery_charging_full)),
              Tab(text: 'Habitation', icon: Icon(Icons.home_work_outlined)),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _CampHeartHero(state: state),
                  const SizedBox(height: 12),
                  _CampHeartProgressCard(state: state),
                  const SizedBox(height: 12),
                  _CampHeartDepositCard(
                    state: state,
                    gameState: widget.gameState,
                    onDeposit: _deposit,
                  ),
                  const SizedBox(height: 12),
                  _CampHeartStageCard(
                    title: nextStage == null
                        ? 'Niveau max V1'
                        : 'Prochain palier : ${nextStage.label}',
                    items: nextStage?.unlocks ?? stage.unlocks,
                    footer: nextStage == null
                        ? 'Les prochains systèmes de Petite ville seront définis plus tard.'
                        : 'Déblocages affichés comme données V1, branchés progressivement.',
                  ),
                  const SizedBox(height: 12),
                  _CampHeartStatsCard(stage: stage),
                  const SizedBox(height: 12),
                  _CampHeartStageCard(
                    title: 'Effets du stade ${stage.label}',
                    items: stage.effects,
                    footer:
                        'Population, bonheur refuge et activité locale sont préparés; le Marché les lira plus tard.',
                  ),
                  const SizedBox(height: 12),
                  const _CampHeartPendingCard(),
                ],
              ),
              _CampGeneratorView(
                gameState: widget.gameState,
                heartLevel: state.campHeartLevel,
              ),
              _CampHousingTab(gameState: widget.gameState),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampGeneratorView extends StatelessWidget {
  const _CampGeneratorView({required this.gameState, required this.heartLevel});

  final Zone0GameState gameState;
  final int heartLevel;

  String _remainingLabel() {
    final remaining = gameState.generatorRemaining(heartLevel);
    if (remaining == null) return 'En attente de ressources';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    Widget resourceCard(String resource, int stored, int capacity) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('$resource : $stored / $capacity',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('Maison : ${gameState.resourceAmount(resource)}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: <int>[1, 5, 10, 9999].map((amount) {
                  return OutlinedButton(
                    onPressed: () {
                      final result = gameState.transferToGenerator(
                        resource: resource,
                        amount: amount,
                        heartLevel: heartLevel,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)));
                    },
                    child: Text(amount == 9999 ? 'Max' : '+$amount'),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Bio-réacteur niveau $heartLevel',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(
            '5 Organique + 1 Minéral → 1 Bio-batterie toutes les ${campGeneratorConfig.cycleMinutes(heartLevel)} min.'),
        const SizedBox(height: 12),
        resourceCard('Organique', gameState.generatorOrganic,
            gameState.generatorOrganicCapacity(heartLevel)),
        resourceCard('Minéral', gameState.generatorMineral,
            gameState.generatorMineralCapacity(heartLevel)),
        Card(
          child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(_remainingLabel()),
            subtitle: Text(
                'Production totale : ${gameState.generatorTotalProduced} · Bio-batteries : ${gameState.bioBatteries}'),
          ),
        ),
      ],
    );
  }
}

class _CampHeartHero extends StatelessWidget {
  const _CampHeartHero({required this.state});

  final CampHeartState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: <Color>[
                    Color(0xFFE7FFD6),
                    Color(0xFF8CBF69),
                    Color(0xFF5A6F3C),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF8CBF69).withValues(alpha: 0.35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.energy_savings_leaf_outlined,
                size: 52,
                color: Color(0xFF24311D),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Cœur du Camp',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le Cœur du Camp enrichit le sol et aide le refuge à devenir habitable.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHeartProgressCard extends StatelessWidget {
  const _CampHeartProgressCard({required this.state});

  final CampHeartState state;

  @override
  Widget build(BuildContext context) {
    final required = state.vegetalizationXpRequired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Stade : ${state.currentStage.label}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text('Cœur niveau ${state.campHeartLevel}'),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 12,
              value: state.progressRatio,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text(
              required == null
                  ? 'Végétalisation : niveau max V1'
                  : 'Végétalisation : ${state.vegetalizationXp} / $required',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Total investi : ${state.totalVegetalizationInvested} Organique',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHeartDepositCard extends StatelessWidget {
  const _CampHeartDepositCard({
    required this.state,
    required this.gameState,
    required this.onDeposit,
  });

  final CampHeartState state;
  final Zone0GameState gameState;
  final ValueChanged<int> onDeposit;

  @override
  Widget build(BuildContext context) {
    final maxAmount = gameState.resourceAmount('Organique');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ajouter de l’Organique',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Stock Organique Maison : $maxAmount',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le Cœur consomme maintenant le stock global rangé dans la Maison.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _DepositButton(
                    amount: 1, stock: maxAmount, onDeposit: onDeposit),
                _DepositButton(
                    amount: 5, stock: maxAmount, onDeposit: onDeposit),
                _DepositButton(
                    amount: 10, stock: maxAmount, onDeposit: onDeposit),
                FilledButton.tonal(
                  onPressed: state.canDepositOrganic(gameState)
                      ? () => onDeposit(maxAmount)
                      : null,
                  child: const Text('Max'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositButton extends StatelessWidget {
  const _DepositButton({
    required this.amount,
    required this.stock,
    required this.onDeposit,
  });

  final int amount;
  final int stock;
  final ValueChanged<int> onDeposit;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: stock >= amount ? () => onDeposit(amount) : null,
      child: Text('+$amount'),
    );
  }
}

class _CampHeartStageCard extends StatelessWidget {
  const _CampHeartStageCard({
    required this.title,
    required this.items,
    required this.footer,
  });

  final String title;
  final List<String> items;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...items.take(7).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('• '),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            Text(
              footer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHeartStatsCard extends StatelessWidget {
  const _CampHeartStatsCard({required this.stage});

  final CampHeartStageConfig stage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _InfoLine(label: 'Population', value: stage.populationLabel),
            _InfoLine(
              label: 'P’TIPOTES confort',
              value: '${stage.activePtipoteComfortLimit}',
            ),
            _InfoLine(
              label: 'Bonheur refuge',
              value: '+${stage.refugeHappinessBonus}',
            ),
            _InfoLine(
              label: 'Activité locale',
              value: 'x${stage.localActivityModifier.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHeartPendingCard extends StatelessWidget {
  const _CampHeartPendingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'À venir : Marché, Tour, Lisière lointaine, bonheur global du refuge et limite effective des P’TIPOTES actifs.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _GameBuildingPage extends StatelessWidget {
  const _GameBuildingPage({required this.building});

  final _RefugeBuilding building;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(building.title)),
      body: SafeArea(
        child: _BuildingPlaceholder(
          icon: building.icon,
          title: building.title,
          description: building.description,
          actions: building.name == 'Kernel'
              ? <Widget>[
                  FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Scan NFC réel à brancher ici.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.egg_alt_outlined),
                    label: const Text('Scanner une figurine'),
                  ),
                ]
              : const <Widget>[],
        ),
      ),
    );
  }
}

class SecurityTowerConstructionSheet extends StatelessWidget {
  const SecurityTowerConstructionSheet({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final levelOk =
        campHeartLevel >= securityTowerConfig.requiredCampHeartLevel;
    return _ConstructionProjectSheet(
      gameState: gameState,
      targetId: 'securityTower',
      title: 'Tour de sécurité',
      description:
          'La Tour surveille les abords du refuge et réduit les risques lors des sorties en Lisière.',
      campHeartLevel: campHeartLevel,
      blockedReason: levelOk
          ? null
          : 'Le Cœur du Camp doit atteindre le niveau ${securityTowerConfig.requiredCampHeartLevel}.',
      footer:
          'Niveau 1 : ${securityTowerConfig.level1Slots} P’TIPOTE affecté · +${securityTowerConfig.securityGainForLevel(1)} sécurité par tick.',
    );
  }
}

class SecurityTowerPage extends StatefulWidget {
  const SecurityTowerPage({
    super.key,
    required this.gameState,
    required this.figurineService,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final FigurineService figurineService;
  final int campHeartLevel;

  @override
  State<SecurityTowerPage> createState() => _SecurityTowerPageState();
}

class _SecurityTowerPageState extends State<SecurityTowerPage> {
  Timer? _towerTimer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_onGameStateChanged);
    widget.gameState.resolveDueForageMissions();
    _towerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _tickTower(),
    );
    _tickTower();
  }

  @override
  void dispose() {
    _towerTimer?.cancel();
    widget.gameState.removeListener(_onGameStateChanged);
    super.dispose();
  }

  void _onGameStateChanged() {
    if (mounted) setState(() {});
  }

  void _tickTower() {
    _tick += 1;
    widget.figurineService.watchMyFigurines().first.then((figurines) {
      if (!mounted) return;
      widget.gameState.resolveDueTowerMissions();
      widget.gameState.recoverFigurineNeeds(figurines: figurines, tick: _tick);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Tour de sécurité'),
            bottom: const TabBar(tabs: <Widget>[
              Tab(text: 'Surveillance'),
              Tab(text: 'Exploration'),
              Tab(text: 'Météo'),
              Tab(text: 'Amélioration'),
              Tab(text: 'Infos'),
            ])),
        body: TabBarView(children: <Widget>[
          SafeArea(
            child: StreamBuilder<List<PtipoteFigurine>>(
              stream: widget.figurineService.watchMyFigurines(),
              builder: (context, snapshot) {
                final figurines = snapshot.data ?? const <PtipoteFigurine>[];
                final activeTowerMissions = widget.gameState.towerMissions
                    .where((mission) =>
                        mission.status == TowerMissionStatus.active)
                    .toList();
                final available = figurines
                    .where(
                      (figurine) =>
                          !widget.gameState.isUnavailableForTower(figurine) &&
                          widget.gameState.vitalityFor(figurine) >=
                              ptipoteStatsConfig.minimumMissionVitality,
                    )
                    .toList();
                final unavailable = figurines
                    .where((figurine) => !available.contains(figurine))
                    .toList();
                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Tour niveau ${widget.gameState.securityTowerLevel}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            _InfoLine(
                              label: 'Sécurité',
                              value:
                                  '${widget.gameState.refugeSafety}/${securityTowerConfig.maxSecurity}',
                            ),
                            _InfoLine(
                              label: 'Slots',
                              value:
                                  '${activeTowerMissions.length}/${widget.gameState.securityTowerSlots}',
                            ),
                            _InfoLine(
                              label: 'Contribution',
                              value:
                                  '+${securityTowerConfig.securityGainForLevel(widget.gameState.securityTowerLevel)} sécurité / ${securityTowerConfig.tickMinutes} min',
                            ),
                            _InfoLine(
                              label: 'Coût',
                              value:
                                  '-${securityTowerConfig.vitalityCostPerTick} Vitalité / tick',
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: widget.gameState
                                          .towerManualRechargeRemaining() ==
                                      Duration.zero
                                  ? () {
                                      final result = widget.gameState
                                          .manuallyRechargeTower();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(result.message)));
                                    }
                                  : null,
                              icon: const Icon(
                                  Icons.electrical_services_outlined),
                              label: Text(widget.gameState
                                          .towerManualRechargeRemaining() ==
                                      Duration.zero
                                  ? 'Recharger les balises (+${securityTowerConfig.manualRechargeGainForLevel(widget.gameState.securityTowerLevel)})'
                                  : 'Recharge dans ${widget.gameState.towerManualRechargeRemaining().inMinutes + 1} min'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'P’TIPOTES affectés',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            if (activeTowerMissions.isEmpty)
                              const Text('Aucun P’TIPOTE ne surveille la Tour.')
                            else
                              ...activeTowerMissions.map(
                                (mission) => _TowerFigurineRow(
                                  name: mission.figurineName,
                                  subtitle:
                                      '${_towerPlanLabel(mission.plan)} · ${_countdownLabel(mission.endTime)} · +${mission.securityGain} sécurité',
                                  action: TextButton(
                                    onPressed: () {
                                      widget.gameState
                                          .removeFromTower(mission.figurineId);
                                    },
                                    child: const Text('Retour'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Affecter',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            if (activeTowerMissions.length >=
                                widget.gameState.securityTowerSlots)
                              const Text('Slot de Tour occupé.')
                            else if (available.isEmpty) ...<Widget>[
                              const Text('Aucun P’TIPOTE disponible.'),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(),
                                ),
                              if (unavailable.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 10),
                                ...unavailable.map(
                                  (figurine) => _TowerFigurineRow(
                                    name: figurine.displayName,
                                    subtitle: _towerUnavailableReason(figurine),
                                    action: const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ] else
                              FilledButton.icon(
                                onPressed: () => _chooseTowerMission(figurines),
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Choisir un P’TIPOTE'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _TowerExplorationTab(
              gameState: widget.gameState,
              figurineService: widget.figurineService),
          _TowerWeatherTab(gameState: widget.gameState),
          _BuildingUpgradeTab(
            gameState: widget.gameState,
            targetId: 'securityTower',
            title: 'Améliorer la Tour',
            description:
                'La Tour reste active pendant les travaux. Le nouveau nombre de slots sera appliqué à la fin.',
            currentEffects: <String>[
              '${widget.gameState.securityTowerSlots} slot(s) de surveillance',
              '+${securityTowerConfig.securityGainForLevel(widget.gameState.securityTowerLevel)} sécurité par tick',
            ],
            nextEffects: <String>[
              '${securityTowerConfig.slotsForLevel(widget.gameState.securityTowerLevel + 1)} slot(s) de surveillance',
              '+${securityTowerConfig.securityGainForLevel(widget.gameState.securityTowerLevel + 1)} sécurité par tick',
              'Les rondes en cours ne sont pas interrompues.',
            ],
            campHeartLevel: widget.campHeartLevel,
          ),
          const _BuildingInformationTab(
            title: 'Tour de sécurité',
            description:
                'La Tour organise les rondes, sécurise les biomes et prépare la météo. Les P’TIPOTES affectés restent indisponibles pendant leur ronde.',
          ),
        ]),
      ),
    );
  }

  String _towerUnavailableReason(PtipoteFigurine figurine) {
    final vitality = widget.gameState.vitalityFor(figurine);
    if (widget.gameState.isAssignedToTower(figurine.id)) {
      return 'Déjà affecté · Vitalité $vitality/100';
    }
    if (widget.gameState.isOnMission(figurine.id)) {
      return 'En mission · Vitalité $vitality/100';
    }
    if (vitality < ptipoteStatsConfig.minimumMissionVitality) {
      return 'Trop fatigué · Vitalité $vitality/100';
    }
    return 'Indisponible · Vitalité $vitality/100';
  }

  Future<void> _chooseTowerMission(List<PtipoteFigurine> figurines) async {
    final figurine = await _pickPtipoteForActivity(
      context: context,
      gameState: widget.gameState,
      figurines: figurines,
      title: 'Affecter à la Tour',
    );
    if (figurine == null || !mounted) return;
    final plan = await showModalBottomSheet<TowerMissionPlan>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <TowerMissionPlan>[
            TowerMissionPlan.oneHour,
            TowerMissionPlan.twoHours,
            TowerMissionPlan.fourHours,
            TowerMissionPlan.eightHours,
            TowerMissionPlan.until25Vitality,
          ]
              .map(
                (plan) => ListTile(
                  title: Text(_towerPlanLabel(plan)),
                  subtitle: Text(plan == TowerMissionPlan.until25Vitality
                      ? '${figurine.displayName} rentrera puis ira dormir.'
                      : '${figurine.displayName} surveillera les abords.'),
                  onTap: () => Navigator.of(context).pop(plan),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (plan == null || !mounted) return;
    final result = widget.gameState.startTowerMission(
      figurine: figurine,
      plan: plan,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  String _towerPlanLabel(TowerMissionPlan plan) {
    return switch (plan) {
      TowerMissionPlan.oneHour => '1h',
      TowerMissionPlan.twoHours => '2h',
      TowerMissionPlan.fourHours => '4h',
      TowerMissionPlan.eightHours => '8h',
      TowerMissionPlan.threeHours => '3h',
      TowerMissionPlan.sixHours => '6h',
      TowerMissionPlan.tenHours => '10h',
      TowerMissionPlan.until25Vitality => 'Jusqu’à 25% puis dodo',
    };
  }
}

class _TowerExplorationTab extends StatelessWidget {
  const _TowerExplorationTab(
      {required this.gameState, required this.figurineService});
  final Zone0GameState gameState;
  final FigurineService figurineService;

  @override
  Widget build(BuildContext context) => SafeArea(
          child: StreamBuilder<List<PtipoteFigurine>>(
        stream: figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          final available = (snapshot.data ?? const <PtipoteFigurine>[])
              .where((item) =>
                  !gameState.isBusy(item) &&
                  gameState.vitalityFor(item) >=
                      ptipoteStatsConfig.minimumMissionVitality)
              .toList();
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'Carte des abords. Chaque exploration demande ${towerOperationsConfig.biomeRevealSecurityThreshold}% de sécurité moyenne sur les biomes adjacents.'))),
            const SizedBox(height: 10),
            _ExplorationMap3x3(gameState: gameState),
            const SizedBox(height: 12),
            Wrap(
                spacing: 10,
                runSpacing: 10,
                children: ForageBiome.values.map((biome) {
                  final state = gameState.biomeSecurity[biome]!;
                  final label = lisiereForageConfig.biomes[biome]!.label;
                  final unlocked = gameState.isBiomeUnlocked(biome);
                  final exploring = gameState.isBiomeExploring(biome);
                  final adjacentSecurity =
                      gameState.adjacentBiomeSecurityFor(biome);
                  final enabled = adjacentSecurity >=
                          towerOperationsConfig.biomeRevealSecurityThreshold &&
                      !unlocked &&
                      !exploring &&
                      available.isNotEmpty;
                  return SizedBox(
                    width: 160,
                    child: Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(unlocked
                                      ? Icons.travel_explore
                                      : Icons.lock_outline),
                                  const SizedBox(height: 6),
                                  Text(label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  Text(unlocked
                                      ? 'Disponible en Lisière'
                                      : exploring
                                          ? 'Exploration en cours'
                                          : adjacentSecurity >=
                                                  towerOperationsConfig
                                                      .biomeRevealSecurityThreshold
                                              ? 'À explorer'
                                              : 'Sécurité voisine insuffisante'),
                                  if (!unlocked)
                                    Text(
                                        'Sécurité voisine : $adjacentSecurity% / ${towerOperationsConfig.biomeRevealSecurityThreshold}%'),
                                  Text(
                                      'Danger potentiel : ${lisiereForageConfig.biomes[biome]!.baseRiskPercent}%'),
                                  if (!unlocked) ...<Widget>[
                                    Text(
                                        'Exploration : ${state.explorationProgress}% / 100%'),
                                    LinearProgressIndicator(
                                      value: state.explorationProgress / 100,
                                    ),
                                  ],
                                  if (state.explorationProgress >= 30)
                                    Text(_biomeResourceHints(
                                      biome,
                                      detailLevel:
                                          state.explorationProgress >= 70
                                              ? 2
                                              : state.explorationProgress >= 50
                                                  ? 1
                                                  : 0,
                                    )),
                                  if (unlocked) ...<Widget>[
                                    Text(
                                        'Réduction de danger : -${_localRiskReduction(state.localSecurity)}%'),
                                    Text(
                                        'Sécurisation : ${state.localSecurity}% / 100%'),
                                    LinearProgressIndicator(
                                      value: state.localSecurity / 100,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                  if (enabled)
                                    FilledButton(
                                        onPressed: () async {
                                          final figurine =
                                              await _pickPtipoteForActivity(
                                                  context: context,
                                                  gameState: gameState,
                                                  figurines: available,
                                                  title: 'Explorer $label');
                                          if (figurine != null &&
                                              context.mounted) {
                                            final hours =
                                                await _pickExplorationDuration(
                                                    context);
                                            if (hours == null ||
                                                !context.mounted) {
                                              return;
                                            }
                                            final result =
                                                gameState.startBiomeExploration(
                                                    biome: biome,
                                                    figurines: <PtipoteFigurine>[
                                                      figurine
                                                    ],
                                                    durationHours: hours);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content:
                                                        Text(result.message)));
                                          }
                                        },
                                        child: const Text('Explorer')),
                                  if (exploring)
                                    Text(_explorationReturn(gameState, biome)),
                                  if (unlocked && available.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        final figurine =
                                            await _pickPtipoteForActivity(
                                                context: context,
                                                gameState: gameState,
                                                figurines: available,
                                                title: 'Sécuriser $label');
                                        if (figurine != null &&
                                            context.mounted) {
                                          final plan =
                                              await _pickPatrolPlan(context);
                                          if (plan == null ||
                                              !context.mounted) {
                                            return;
                                          }
                                          final result =
                                              gameState.startBiomePatrol(
                                            biome: biome,
                                            figurine: figurine,
                                            plan: plan,
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content:
                                                      Text(result.message)));
                                        }
                                      },
                                      icon: const Icon(Icons.shield_outlined),
                                      label: const Text('Sécuriser'),
                                    ),
                                ]))),
                  );
                }).toList()),
          ]);
        },
      ));
}

class _ExplorationMap3x3 extends StatelessWidget {
  const _ExplorationMap3x3({required this.gameState});
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    // Topology is deliberately stable: the Camp stays at the bottom centre.
    const cells = <ForageBiome?>[
      ForageBiome.colline,
      null,
      ForageBiome.bassinMineral,
      null,
      ForageBiome.plaineRiche,
      ForageBiome.sousBois,
      null,
      null,
      null,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        if (index == 7) {
          return const _ExplorationMapCell(
              label: 'Camp', icon: Icons.home_outlined, active: true);
        }
        final biome = cells[index];
        if (biome == null) return const SizedBox.shrink();
        final state = gameState.biomeSecurity[biome]!;
        return _ExplorationMapCell(
          label: lisiereForageConfig.biomes[biome]!.label,
          icon: gameState.isBiomeUnlocked(biome)
              ? Icons.travel_explore
              : Icons.lock_outline,
          active: gameState.isBiomeUnlocked(biome),
          progress: state.explorationProgress,
        );
      },
    );
  }
}

class _ExplorationMapCell extends StatelessWidget {
  const _ExplorationMapCell(
      {required this.label,
      required this.icon,
      required this.active,
      this.progress});
  final String label;
  final IconData icon;
  final bool active;
  final int? progress;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 18),
                const SizedBox(height: 3),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
                if (progress != null && progress! > 0)
                  Text('$progress%', style: const TextStyle(fontSize: 10)),
              ]),
        ),
      );
}

class _TowerWeatherTab extends StatelessWidget {
  const _TowerWeatherTab({required this.gameState});
  final Zone0GameState gameState;
  @override
  Widget build(BuildContext context) {
    final alerts = gameState.weatherAlerts;
    return SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(alerts.isEmpty
                  ? 'Aucun événement météo annoncé. La Tour préviendra le refuge avant les prochaines perturbations.'
                  : 'Événements annoncés'))),
      ...alerts.map((alert) {
        final config = towerOperationsConfig.weatherEvents
            .firstWhere((item) => item.type == alert.type);
        return Card(
            child: ListTile(
                title: Text(config.label),
                subtitle: Text(
                    '${config.description}\nPréparation : ${config.preparationAmount} ${config.preparationItem}'),
                trailing: alert.preparationCompleted
                    ? const Text('Préparé')
                    : FilledButton(
                        onPressed: () {
                          final result =
                              gameState.fulfillWeatherPreparation(alert);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        },
                        child: const Text('Fournir'),
                      )));
      }),
    ]));
  }
}

String _biomeResourceHints(ForageBiome biome, {required int detailLevel}) {
  final rewards = lisiereForageConfig.biomes[biome]!.baseRewards;
  String strength(String resource) {
    final amount = rewards[resource] ?? 0;
    if (detailLevel == 0) return '';
    if (detailLevel == 2) return ' $amount';
    return amount >= 4
        ? ' ++'
        : amount >= 2
            ? ' +'
            : ' -';
  }

  return '🌿${strength('Organique')}  ⛏️${strength('Minéral')}';
}

String _explorationReturn(Zone0GameState state, ForageBiome biome) {
  final mission = state.explorationMissions
      .firstWhere((item) => item.biome == biome && item.isActive);
  return _countdownLabel(mission.endTime);
}

String _countdownLabel(DateTime endTime) {
  final remaining = endTime.difference(DateTime.now());
  if (remaining <= Duration.zero) return 'Retour imminent';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  final seconds = remaining.inSeconds.remainder(60);
  if (hours > 0) {
    return 'Temps restant : $hours h ${minutes.toString().padLeft(2, '0')}';
  }
  if (minutes > 0) return 'Temps restant : $minutes min';
  return 'Temps restant : ${seconds}s';
}

Future<int?> _pickExplorationDuration(BuildContext context) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
            const Text('Durée de reconnaissance',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const Text(
                '10 h d’exploration au total. Chaque heure apporte 10% de progression.'),
            ...<int>[1, 2, 4, 8].map((hours) => ListTile(
                title: Text('${hours}h de mission'),
                subtitle: Text('+${hours * 10}% exploration'),
                onTap: () => Navigator.of(context).pop(hours))),
          ])),
    );

Future<TowerMissionPlan?> _pickPatrolPlan(BuildContext context) =>
    showModalBottomSheet<TowerMissionPlan>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            const Text('Durée de sécurisation',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const Text(
                '8 h au total permettent de sécuriser entièrement un biome.'),
            ...<TowerMissionPlan>[
              TowerMissionPlan.oneHour,
              TowerMissionPlan.twoHours,
              TowerMissionPlan.fourHours,
              TowerMissionPlan.eightHours,
            ].map((plan) => ListTile(
                  title: Text(_towerPlanLabelForPicker(plan)),
                  subtitle: Text('+${_patrolSecurityGain(plan)}% au retour'),
                  onTap: () => Navigator.of(context).pop(plan),
                )),
          ],
        ),
      ),
    );

String _towerPlanLabelForPicker(TowerMissionPlan plan) => switch (plan) {
      TowerMissionPlan.oneHour => '1h',
      TowerMissionPlan.twoHours => '2h',
      TowerMissionPlan.fourHours => '4h',
      TowerMissionPlan.eightHours => '8h',
      TowerMissionPlan.threeHours => '3h',
      TowerMissionPlan.sixHours => '6h',
      TowerMissionPlan.tenHours => '10h',
      TowerMissionPlan.until25Vitality => 'Jusqu’à 25%',
    };

int _patrolSecurityGain(TowerMissionPlan plan) => switch (plan) {
      TowerMissionPlan.oneHour => 13,
      TowerMissionPlan.twoHours => 25,
      TowerMissionPlan.fourHours => 50,
      TowerMissionPlan.eightHours => 100,
      TowerMissionPlan.threeHours => 38,
      TowerMissionPlan.sixHours => 75,
      TowerMissionPlan.tenHours => 100,
      TowerMissionPlan.until25Vitality => 0,
    };

int _localRiskReduction(int localSecurity) => (localSecurity.clamp(0, 100) *
        towerOperationsConfig.maximumLocalRiskReductionPercent /
        100)
    .round();

class _TowerFigurineRow extends StatelessWidget {
  const _TowerFigurineRow({
    required this.name,
    required this.subtitle,
    required this.action,
  });

  final String name;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          action,
        ],
      ),
    );
  }
}

class FablabConstructionSheet extends StatelessWidget {
  const FablabConstructionSheet({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    return _ConstructionProjectSheet(
      gameState: gameState,
      targetId: 'fablab',
      title: 'Fablab',
      description:
          'Le Fablab permet au refuge de cuisiner, fabriquer et recycler progressivement ses ressources.',
      footer:
          'Atelier niveau 1 : +${fablabConfig.stockCapacityBonusPerFablabLevel} unités de stock.',
    );
  }
}

void _showFablabUnitProject(
  BuildContext context, {
  required Zone0GameState gameState,
  required String targetId,
  required String title,
  required String description,
}) {
  _showBuildingProject(
    context,
    gameState: gameState,
    targetId: targetId,
    title: title,
    description: description,
  );
}

void _showBuildingProject(
  BuildContext context, {
  required Zone0GameState gameState,
  required String targetId,
  required String title,
  required String description,
  int? campHeartLevel,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConstructionProjectSheet(
      gameState: gameState,
      targetId: targetId,
      title: title,
      description: description,
      campHeartLevel: campHeartLevel,
    ),
  );
}

class _BuildingUpgradeTab extends StatelessWidget {
  const _BuildingUpgradeTab({
    required this.gameState,
    required this.targetId,
    required this.title,
    required this.description,
    required this.currentEffects,
    required this.nextEffects,
    this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final String targetId;
  final String title;
  final String description;
  final List<String> currentEffects;
  final List<String> nextEffects;
  final int? campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final project = gameState.projectFor(targetId);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(description),
                  const SizedBox(height: 14),
                  const Text('Effets actuels',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  ...currentEffects.map(Text.new),
                  const SizedBox(height: 10),
                  const Text('Niveau suivant',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  ...nextEffects.map(Text.new),
                  if (project.isInProgress) ...<Widget>[
                    const SizedBox(height: 12),
                    Text('Travaux : ${_countdownLabel(project.endsAt!)}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed:
                        project.state == ConstructionProjectState.maxLevel
                            ? null
                            : () => _showBuildingProject(
                                  context,
                                  gameState: gameState,
                                  targetId: targetId,
                                  title: title,
                                  description: description,
                                  campHeartLevel: campHeartLevel,
                                ),
                    icon: const Icon(Icons.upgrade_outlined),
                    label: Text(
                        project.state == ConstructionProjectState.maxLevel
                            ? 'Niveau maximum'
                            : 'Préparer l’amélioration'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingInformationTab extends StatelessWidget {
  const _BuildingInformationTab({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(description),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ConstructionProjectSheet extends StatefulWidget {
  const _ConstructionProjectSheet({
    required this.gameState,
    required this.targetId,
    required this.title,
    required this.description,
    this.footer,
    this.blockedReason,
    this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final String targetId;
  final String title;
  final String description;
  final String? footer;
  final String? blockedReason;
  final int? campHeartLevel;

  @override
  State<_ConstructionProjectSheet> createState() =>
      _ConstructionProjectSheetState();
}

class _ConstructionProjectSheetState extends State<_ConstructionProjectSheet> {
  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.gameState.projectFor(widget.targetId);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(widget.description),
          if (widget.blockedReason != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(widget.blockedReason!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 14),
          if (project.state == ConstructionProjectState.maxLevel)
            const Text(
              'Niveau maximum atteint.',
              style: TextStyle(fontWeight: FontWeight.w900),
            )
          else if (project.isInProgress)
            Text(_countdownLabel(project.endsAt!),
                style: const TextStyle(fontWeight: FontWeight.w900))
          else
            ...project.requirements.entries
                .map((entry) => Row(children: <Widget>[
                      Expanded(
                        child: Text(
                          '${entry.key} : ${project.depositedMaterials[entry.key] ?? 0} / ${entry.value}',
                        ),
                      ),
                      TextButton(
                        onPressed: widget.blockedReason == null &&
                                project.missingFor(entry.key) > 0
                            ? () => widget.gameState.depositProjectMaterial(
                                widget.targetId, entry.key, 1)
                            : null,
                        child: const Text('+1'),
                      ),
                      TextButton(
                        onPressed: widget.blockedReason == null &&
                                project.missingFor(entry.key) > 0
                            ? () => widget.gameState.depositProjectMaterial(
                                widget.targetId, entry.key, 5)
                            : null,
                        child: const Text('+5'),
                      ),
                      TextButton(
                        onPressed: widget.blockedReason == null &&
                                project.missingFor(entry.key) > 0
                            ? () => widget.gameState.depositProjectMaterial(
                                  widget.targetId,
                                  entry.key,
                                  project.missingFor(entry.key),
                                )
                            : null,
                        child: const Text('Max'),
                      ),
                      IconButton(
                        tooltip: 'Récupérer',
                        onPressed:
                            (project.depositedMaterials[entry.key] ?? 0) > 0
                                ? () => widget.gameState
                                    .withdrawProjectMaterial(
                                        widget.targetId, entry.key)
                                : null,
                        icon: const Icon(Icons.undo),
                      ),
                    ])),
          if (widget.footer != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(widget.footer!,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.blockedReason == null &&
                    project.isReady &&
                    !project.isInProgress &&
                    project.state != ConstructionProjectState.maxLevel
                ? () {
                    final result = widget.gameState.startConstructionProject(
                      widget.targetId,
                      campHeartLevel: widget.campHeartLevel,
                    );
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(result.message)));
                  }
                : null,
            icon: const Icon(Icons.construction_outlined),
            label: Text(project.isInProgress
                ? 'Travaux en cours'
                : project.state == ConstructionProjectState.maxLevel
                    ? 'Niveau maximum'
                    : 'Commencer les travaux'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ]),
      ),
    );
  }
}

class _MarketConstructionSheet extends StatelessWidget {
  const _MarketConstructionSheet(
      {required this.gameState, required this.campHeartLevel});
  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final missingRequirements = <String>[
      if (campHeartLevel < marketConfig.requiredCampHeartLevel)
        'Le Cœur du Camp doit atteindre le niveau ${marketConfig.requiredCampHeartLevel}.',
      if (gameState.currentPopulation < marketConfig.requiredPopulation)
        'Population requise : ${marketConfig.requiredPopulation}.',
    ];
    return _ConstructionProjectSheet(
      gameState: gameState,
      targetId: 'market',
      title: 'Marché',
      description: 'Trois emplacements de vente. Fonctionne sans P’TIPOTE.',
      campHeartLevel: campHeartLevel,
      blockedReason:
          missingRequirements.isEmpty ? null : missingRequirements.join('\n'),
      footer:
          'Population : ${gameState.currentPopulation} / ${marketConfig.requiredPopulation} requise.',
    );
  }
}

class MarketPage extends StatefulWidget {
  const MarketPage({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
  });
  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final FigurineService _figurineService = FigurineService();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    _timer = Timer.periodic(
        const Duration(seconds: 5), (_) => widget.gameState.resolveMarket());
    widget.gameState.resolveMarket();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marché')),
      body: SafeArea(
        child: StreamBuilder<List<PtipoteFigurine>>(
          stream: _figurineService.watchMyFigurines(),
          builder: (context, snapshot) {
            final figurines = snapshot.data ?? const <PtipoteFigurine>[];
            return ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                    'Marché niveau ${widget.gameState.marketLevel}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(
                                    'Population ${widget.gameState.currentPopulation} · Bien-être ${widget.gameState.campWellbeing}%'),
                                Text(
                                    'Bio-batteries gagnées : ${widget.gameState.marketBioBatteriesEarned}'),
                                Text(widget.gameState
                                            .marketAssignedPtipoteName ==
                                        null
                                    ? 'Mode automatique'
                                    : 'Aidé par ${widget.gameState.marketAssignedPtipoteName}'),
                                Text(widget.gameState.marketSaleRemaining() ==
                                        null
                                    ? 'Prochaine vente : stock vide'
                                    : 'Prochaine vente : ${widget.gameState.marketSaleRemaining()!.inMinutes}m ${widget.gameState.marketSaleRemaining()!.inSeconds.remainder(60).toString().padLeft(2, '0')}s'),
                                Wrap(
                                  spacing: 8,
                                  children: <Widget>[
                                    OutlinedButton.icon(
                                      onPressed: () => _showBuildingProject(
                                        context,
                                        gameState: widget.gameState,
                                        targetId: 'market',
                                        title: 'Améliorer le Marché',
                                        description:
                                            'Le Marché reste ouvert pendant les travaux. Les nouveaux emplacements seront ajoutés à la fin.',
                                        campHeartLevel: widget.campHeartLevel,
                                      ),
                                      icon: const Icon(Icons.upgrade_outlined),
                                      label: const Text('Amélioration'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          showModalBottomSheet<void>(
                                        context: context,
                                        builder: (_) =>
                                            const _BuildingInformationTab(
                                          title: 'Marché',
                                          description:
                                              'Le Marché vend automatiquement le stock confié. Un P’TIPOTE accélère les ventes et peut traiter les demandes des habitants.',
                                        ),
                                      ),
                                      icon: const Icon(Icons.info_outline),
                                      label: const Text('Infos'),
                                    ),
                                  ],
                                ),
                                if (widget.gameState.marketAssignedPtipoteId !=
                                    null)
                                  OutlinedButton(
                                      onPressed: () =>
                                          widget.gameState.removeFromMarket(),
                                      child: const Text('Faire rentrer'))
                                else
                                  FilledButton.icon(
                                    onPressed: () async {
                                      final figurine =
                                          await _pickPtipoteForActivity(
                                        context: context,
                                        gameState: widget.gameState,
                                        figurines: figurines,
                                        title: 'Affecter au Marché',
                                      );
                                      if (figurine == null ||
                                          !context.mounted) {
                                        return;
                                      }
                                      _message(widget.gameState
                                          .assignToMarket(figurine)
                                          .message);
                                    },
                                    icon: const Icon(Icons.person_add_alt_1),
                                    label: const Text('Affecter un P’TIPOTE'),
                                  ),
                              ]))),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('Sourcier du savoir',
                              style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          if (!widget.gameState.isMerchantAvailable)
                            FilledButton(
                              onPressed: widget.gameState.openMerchant,
                              child: const Text('Appeler le Sourcier'),
                            )
                          else ...<Widget>[
                            Text(
                                'Présent encore ${widget.gameState.merchantAvailableUntil!.difference(DateTime.now()).inHours + 1}h'),
                            ...widget.gameState.merchantOffers.map(
                              (offer) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.25)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(offer.planName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          Text('${offer.price} Bio-batteries'),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                              width: double.infinity,
                                              child: offer.purchased
                                                  ? const OutlinedButton(
                                                      onPressed: null,
                                                      child: Text('Acheté'))
                                                  : FilledButton(
                                                      onPressed: () => _message(
                                                          widget.gameState
                                                              .buyMerchantOffer(
                                                                  offer)
                                                              .message),
                                                      child: const Text(
                                                          'Acheter'))),
                                        ]),
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                                onPressed: () => _message(
                                    'Le Sourcier reviendra plus tard.'),
                                child: const Text('Plus tard')),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Stock de vente (${widget.gameState.marketStock.length}/${widget.gameState.marketSlotLimit})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List<Widget>.generate(
                      widget.gameState.marketSlotLimit,
                      (index) {
                        final stack =
                            index < widget.gameState.marketStock.length
                                ? widget.gameState.marketStock[index]
                                : null;
                        return _MarketStockSlot(
                          stack: stack,
                          onTap: () => _editMarketSlot(stack?.resource),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  const Text('Demandes des habitants',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  if (widget.gameState.marketAssignedPtipoteId == null)
                    const Text(
                        'Un P’TIPOTE doit être présent pour noter et livrer les demandes.'),
                  ...widget.gameState.marketRequests.map((request) => ListTile(
                        title: Text(
                            '${request.requestedQuantity} ${request.requestedItemId}'),
                        subtitle: Text(request.status ==
                                MarketRequestStatus.completed
                            ? 'Livrée'
                            : 'Retour client : ${request.customerReturnTime.hour.toString().padLeft(2, '0')}:${request.customerReturnTime.minute.toString().padLeft(2, '0')}'),
                        trailing: Text('+${request.rewardBioBattery} 🔋'),
                      )),
                ]);
          },
        ),
      ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _editMarketSlot(String? initialResource) async {
    final resources = marketConfig.saleValues.keys
        .where((resource) =>
            widget.gameState.resourceAmount(resource) > 0 ||
            resource == initialResource)
        .toList();
    if (resources.isEmpty) {
      _message('Aucun objet vendable dans le stock Maison.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            Text(initialResource ?? 'Ajouter au Marché',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...resources.map((resource) => ListTile(
                  leading: Icon(_resourceIcon(resource)),
                  title: Text(resource),
                  subtitle: Text(
                    'Maison : ${widget.gameState.resourceAmount(resource)} · '
                    '${widget.gameState.isEquipmentResource(resource) ? 'équipement : 1 par case' : '10 par case'}',
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: <int>[1, 5, 10]
                        .map((amount) => TextButton(
                              onPressed: () {
                                final result = widget.gameState
                                    .transferToMarket(resource, amount);
                                _message(result.message);
                                if (result.success) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              child: Text('+$amount'),
                            ))
                        .toList(),
                  ),
                )),
            if (initialResource != null) ...<Widget>[
              const Divider(),
              OutlinedButton.icon(
                onPressed: () {
                  _message(widget.gameState
                      .returnMarketStock(initialResource)
                      .message);
                  Navigator.of(sheetContext).pop();
                },
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Rendre à la Maison'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarketStockSlot extends StatelessWidget {
  const _MarketStockSlot({required this.stack, required this.onTap});

  final Zone0InventoryStack? stack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = stack != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: filled
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
          ),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Icon(
                filled ? _resourceIcon(stack!.resource) : Icons.add,
                size: 34,
                color: filled ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
            if (filled)
              Positioned(
                top: 8,
                right: 8,
                child: Text('${stack!.amount}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            if (filled)
              Positioned(
                left: 6,
                right: 6,
                bottom: 7,
                child: Text(stack!.resource,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}

class PTibugNurseryPage extends StatefulWidget {
  const PTibugNurseryPage(
      {super.key, required this.gameState, required this.campHeartLevel});
  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  State<PTibugNurseryPage> createState() => _PTibugNurseryPageState();
}

class _PTibugNurseryPageState extends State<PTibugNurseryPage> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 10),
        (_) => widget.gameState.resolvePTibugProduction());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Nurserie P’TIBUG'),
            bottom: const TabBar(isScrollable: true, tabs: <Widget>[
              Tab(text: 'Aperçu'),
              Tab(text: 'Créer'),
              Tab(text: 'Collection'),
              Tab(text: 'Données'),
              Tab(text: 'Amélioration')
            ])),
        body: TabBarView(children: <Widget>[
          _overview(),
          _creation(),
          _collection(),
          _dataAndModules(),
          _BuildingUpgradeTab(
              gameState: widget.gameState,
              targetId: 'plaineNursery',
              title: 'Améliorer la Nurserie',
              description:
                  'Ajoute des slots P’TIBUG et des emplacements de modules.',
              currentEffects: <String>[
                '${widget.gameState.pTibugActiveSlots} slot(s) actif(s)',
                '${pTibugConfig.moduleSlotsForLevel(widget.gameState.plaineNurseryLevel)} module(s) par P’TIBUG'
              ],
              nextEffects: <String>[
                '${pTibugConfig.slotsForLevel(widget.gameState.plaineNurseryLevel + 1)} slot(s) actif(s)',
                '${pTibugConfig.moduleSlotsForLevel(widget.gameState.plaineNurseryLevel + 1)} module(s) par P’TIBUG'
              ],
              campHeartLevel: widget.campHeartLevel),
        ]),
      ),
    );
  }

  Widget _overview() {
    final total = widget.gameState.pTibugs
        .fold<int>(0, (sum, bug) => sum + bug.storedAmount);
    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                        'Nurserie niveau ${widget.gameState.plaineNurseryLevel}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 20)),
                    Text(
                        '${widget.gameState.pTibugs.where((bug) => bug.assignedSlotIndex != null).length}/${widget.gameState.pTibugActiveSlots} P’TIBUG actifs'),
                    Text('Production en réserve : $total ressources'),
                    const SizedBox(height: 8),
                    FilledButton(
                        onPressed: total == 0
                            ? null
                            : () => _message(widget.gameState
                                .collectPTibugProduction()
                                .message),
                        child: const Text('Récupérer la production')),
                  ]))),
      if (widget.gameState.pTibugCreationOrder?.isActive == true)
        Card(
            child: ListTile(
                title: const Text('Création en cours'),
                subtitle: Text(
                    'Fin dans ${_countdownLabel(widget.gameState.pTibugCreationOrder!.endsAt)}'))),
    ]);
  }

  Widget _creation() =>
      ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('Patterns P’TIBUG',
            style: TextStyle(fontWeight: FontWeight.w900)),
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
              'Les Patterns se découvrent et s’activent depuis le Kernel.'),
        ),
        ...PTibugSpecies.values.map((species) {
          final config = pTibugConfig.species[species]!;
          final pattern = pTibugConfig.patterns[species]!;
          final state = widget.gameState.pTibugPatternState(species);
          final isActive = state == KernelPlanState.active;
          return Card(
              child: ListTile(
                  title: Text('Pattern ${config.displayName}'),
                  subtitle: Text(isActive
                      ? '${config.creationCost.entries.map((e) => '${e.value} ${e.key}').join(' · ')} · ${config.creationEnergyCost} Énergie · ${config.creationMinutes} min'
                      : '${pattern.description}\nKernel : ${_patternStateLabel(state)}'),
                  isThreeLine: !isActive,
                  trailing: isActive
                      ? FilledButton(
                          onPressed:
                              widget.gameState.pTibugCreationOrder?.isActive ==
                                      true
                                  ? null
                                  : () => _message(widget.gameState
                                      .startPTibugCreation(species)
                                      .message),
                          child: const Text('Créer'))
                      : const Icon(Icons.lock_outline)));
        }),
      ]);

  String _patternStateLabel(KernelPlanState state) => switch (state) {
        KernelPlanState.unknown => 'Pattern inconnu',
        KernelPlanState.discovered => 'Plan découvert',
        KernelPlanState.ready => 'À activer dans le Kernel',
        KernelPlanState.active => 'Actif',
      };

  Widget _collection() =>
      ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('Collection', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('Tape un P’TIBUG pour consulter et ajuster son équipement.'),
        const SizedBox(height: 10),
        if (widget.gameState.pTibugs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Aucun P’TIBUG créé pour le moment.'),
          ),
        ...widget.gameState.pTibugs.map((bug) => Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showPTibugLoadout(bug),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        CircleAvatar(
                          child: Icon(_speciesIcon(bug.species)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(bug.displayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 17)),
                        ),
                        Text('Niv. ${bug.level}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          '${pTibugConfig.species[bug.species]!.displayName} · ${bug.styleVariant}'),
                      Text(
                          'XP ${bug.xp} · Réserve ${bug.storedAmount}/${pTibugConfig.carryingCapacity}'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                        _LoadoutPill(
                          icon: Icons.auto_awesome_outlined,
                          label: _traitLabel(bug.traitDataId),
                          color: _traitColor(_traitFor(bug)?.grade),
                        ),
                        ...List<Widget>.generate(
                          pTibugConfig.moduleSlotsForLevel(
                              widget.gameState.plaineNurseryLevel),
                          (index) {
                            final module = index < bug.equippedModules.length
                                ? bug.equippedModules[index]
                                : null;
                            return _LoadoutPill(
                              icon: module == null
                                  ? Icons.add_circle_outline
                                  : _moduleIcon(module),
                              label: module == null
                                  ? 'Module libre'
                                  : _moduleTitle(module),
                              color: module == null
                                  ? Theme.of(context).colorScheme.outline
                                  : Theme.of(context).colorScheme.secondary,
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(bug.assignedSlotIndex == null
                          ? 'En réserve'
                          : 'Production active · prochain cycle ${bug.nextProductionAt == null ? 'à lancer' : _countdownLabel(bug.nextProductionAt!)}'),
                      const SizedBox(height: 8),
                      bug.assignedSlotIndex == null
                          ? FilledButton.icon(
                              onPressed: () => _message(widget.gameState
                                  .assignPTibugSlot(bug, _firstFreeSlot())
                                  .message),
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: const Text('Installer en production'))
                          : OutlinedButton.icon(
                              onPressed: () => _message(widget.gameState
                                  .removePTibugSlot(bug)
                                  .message),
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Retirer de la production')),
                    ],
                  ),
                ),
              ),
            )),
      ]);

  Widget _dataAndModules() {
    final traits = widget.gameState.pTibugTraitData;
    final unlockedModules = widget.gameState.unlockedPTibugModules;
    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      const Text('Données de traits',
          style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text(
          'Les Données attribuées restent visibles ici. Deux Données identiques non équipées peuvent être fusionnées.'),
      const SizedBox(height: 10),
      if (traits.isEmpty)
        const Card(child: ListTile(title: Text('Aucune Donnée disponible.'))),
      ...traits.map((trait) {
        final owner = widget.gameState.pTibugs
            .where((bug) => bug.traitDataId == trait.id)
            .firstOrNull;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _traitColor(trait.grade).withValues(alpha: 0.16),
              child: Icon(Icons.auto_awesome, color: _traitColor(trait.grade)),
            ),
            title: Text(
                '${_traitTitle(trait.type)} · ${_traitGradeTitle(trait.grade)}'),
            subtitle: Text(owner == null
                ? _traitDescription(trait)
                : '${_traitDescription(trait)}\nÉquipée par ${owner.displayName}'),
            isThreeLine: owner != null,
          ),
        );
      }),
      const SizedBox(height: 8),
      ..._fusionActions(),
      const SizedBox(height: 18),
      const Text('Modules', style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(
          '${unlockedModules.length}/${PTibugModuleType.values.length} Modules déverrouillés'),
      const SizedBox(height: 10),
      ...PTibugModuleType.values.map((module) {
        final unlocked = unlockedModules.contains(module);
        return Opacity(
          opacity: unlocked ? 1 : 0.48,
          child: Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_moduleIcon(module))),
              title: Text(_moduleTitle(module)),
              subtitle: Text(unlocked
                  ? _moduleDescription(module)
                  : 'Module verrouillé · à obtenir plus tard.'),
              trailing: Icon(
                  unlocked ? Icons.check_circle_outline : Icons.lock_outline),
            ),
          ),
        );
      }),
    ]);
  }

  List<Widget> _fusionActions() {
    final available = widget.gameState.pTibugTraitData
        .where((data) =>
            !widget.gameState.pTibugs.any((bug) => bug.traitDataId == data.id))
        .toList();
    final widgets = <Widget>[];
    for (final trait in available) {
      final partner = available
          .where((item) =>
              item.id != trait.id &&
              item.type == trait.type &&
              item.grade == trait.grade)
          .firstOrNull;
      if (partner == null ||
          trait.grade == PTibugTraitGrade.avance ||
          widgets.isNotEmpty) {
        continue;
      }
      widgets.add(OutlinedButton.icon(
        onPressed: () => _message(
            widget.gameState.fusePTibugTraitData(trait, partner).message),
        icon: const Icon(Icons.merge_type_outlined),
        label: Text(
            'Fusionner 2 ${_traitTitle(trait.type)} ${_traitGradeTitle(trait.grade)}'),
      ));
    }
    return widgets;
  }

  Future<void> _showPTibugLoadout(PTibug bug) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          final availableTraits = widget.gameState.pTibugTraitData.where(
              (data) => !widget.gameState.pTibugs.any(
                  (item) => item.id != bug.id && item.traitDataId == data.id));
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              builder: (_, controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                children: <Widget>[
                  Text(bug.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(
                      '${pTibugConfig.species[bug.species]!.displayName} · niveau ${bug.level}'),
                  const SizedBox(height: 18),
                  const Text('Donnée équipée',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  ...availableTraits.map((trait) => ListTile(
                        leading: Icon(Icons.auto_awesome,
                            color: _traitColor(trait.grade)),
                        title: Text(
                            '${_traitTitle(trait.type)} · ${_traitGradeTitle(trait.grade)}'),
                        subtitle: Text(_traitDescription(trait)),
                        trailing: trait.id == bug.traitDataId
                            ? const Icon(Icons.check_circle)
                            : TextButton(
                                onPressed: () {
                                  _message(widget.gameState
                                      .equipPTibugTrait(bug, trait)
                                      .message);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Équiper')),
                      )),
                  const Divider(height: 28),
                  Text(
                      'Modules (${bug.equippedModules.length}/${pTibugConfig.moduleSlotsForLevel(widget.gameState.plaineNurseryLevel)})',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  ...PTibugModuleType.values.map((module) {
                    final unlocked =
                        widget.gameState.unlockedPTibugModules.contains(module);
                    final equipped = bug.hasModule(module);
                    return ListTile(
                      leading: Icon(_moduleIcon(module)),
                      title: Text(_moduleTitle(module)),
                      subtitle: Text(
                          unlocked ? _moduleDescription(module) : 'Verrouillé'),
                      trailing: equipped
                          ? const Icon(Icons.check_circle)
                          : unlocked
                              ? TextButton(
                                  onPressed: () {
                                    _message(widget.gameState
                                        .equipPTibugModule(bug, module)
                                        .message);
                                    Navigator.of(sheetContext).pop();
                                  },
                                  child: const Text('Équiper'))
                              : const Icon(Icons.lock_outline),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );

  PTibugTraitData? _traitFor(PTibug bug) => widget.gameState.pTibugTraitData
      .where((trait) => trait.id == bug.traitDataId)
      .firstOrNull;

  IconData _speciesIcon(PTibugSpecies species) => switch (species) {
        PTibugSpecies.scarabe => Icons.shield_outlined,
        PTibugSpecies.hyme => Icons.hive_outlined,
        PTibugSpecies.arac => Icons.hub_outlined,
      };

  IconData _moduleIcon(PTibugModuleType module) => switch (module) {
        PTibugModuleType.ailes => Icons.air_outlined,
        PTibugModuleType.pinces => Icons.content_cut_outlined,
        PTibugModuleType.reservoir => Icons.inventory_2_outlined,
      };

  String _moduleTitle(PTibugModuleType module) => switch (module) {
        PTibugModuleType.ailes => 'Ailes',
        PTibugModuleType.pinces => 'Pinces',
        PTibugModuleType.reservoir => 'Réservoir',
      };

  String _moduleDescription(PTibugModuleType module) => switch (module) {
        PTibugModuleType.ailes =>
          '-${(pTibugConfig.wingsCycleReduction * 100).round()} % de durée de cycle.',
        PTibugModuleType.pinces =>
          '+${pTibugConfig.clawProductionBonus} ressource selon l’espèce.',
        PTibugModuleType.reservoir =>
          '+${pTibugConfig.reservoirCapacityBonus} de capacité de réserve.',
      };

  String _traitTitle(PTibugTraitType type) => switch (type) {
        PTibugTraitType.pollinisateur => 'Pollinisateur',
        PTibugTraitType.mineur => 'Mineur',
        PTibugTraitType.decomposeur => 'Décomposeur',
      };

  String _traitGradeTitle(PTibugTraitGrade grade) => switch (grade) {
        PTibugTraitGrade.commun => 'Commun',
        PTibugTraitGrade.rare => 'Rare',
        PTibugTraitGrade.avance => 'Avancé',
      };

  Color _traitColor(PTibugTraitGrade? grade) => switch (grade) {
        PTibugTraitGrade.commun => const Color(0xFF5D8D71),
        PTibugTraitGrade.rare => const Color(0xFF4977A6),
        PTibugTraitGrade.avance => const Color(0xFF8C5AA2),
        null => const Color(0xFF817D66),
      };

  String _traitDescription(PTibugTraitData trait) {
    final value = pTibugConfig.traitMultiplier(trait.grade);
    return switch (trait.type) {
      PTibugTraitType.pollinisateur => '+$value Organique par cycle.',
      PTibugTraitType.mineur => '+$value Minéral par cycle.',
      PTibugTraitType.decomposeur =>
        '+$value Organique et +$value Mycélium par cycle.',
    };
  }

  int _firstFreeSlot() {
    for (var i = 0; i < widget.gameState.pTibugActiveSlots; i += 1) {
      if (!widget.gameState.pTibugs.any((bug) => bug.assignedSlotIndex == i)) {
        return i;
      }
    }
    return -1;
  }

  String _traitLabel(String? id) {
    final trait = widget.gameState.pTibugTraitData
        .where((item) => item.id == id)
        .firstOrNull;
    return trait == null
        ? 'Donnée libre'
        : '${_traitTitle(trait.type)} · ${_traitGradeTitle(trait.grade)}';
  }
}

class _LoadoutPill extends StatelessWidget {
  const _LoadoutPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class FablabPage extends StatelessWidget {
  const FablabPage({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fablab'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Cuisine', icon: Icon(Icons.soup_kitchen_outlined)),
              Tab(text: 'Atelier', icon: Icon(Icons.construction_outlined)),
              Tab(text: 'Recycleur', icon: Icon(Icons.recycling_outlined)),
              Tab(text: 'Amélioration', icon: Icon(Icons.upgrade_outlined)),
              Tab(text: 'Infos', icon: Icon(Icons.info_outline)),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              FablabCuisineView(gameState: gameState),
              campHeartLevel >= fablabConfig.atelierUnlockCampHeartLevel
                  ? FablabWorkshopView(gameState: gameState)
                  : _BuildingPlaceholder(
                      icon: Icons.lock_outline,
                      title: 'Atelier',
                      description:
                          'Débloqué au Cœur du Camp niveau ${fablabConfig.atelierUnlockCampHeartLevel}.',
                    ),
              gameState.isRecyclerUnlocked(campHeartLevel)
                  ? FablabRecyclerView(
                      gameState: gameState,
                      campHeartLevel: campHeartLevel,
                    )
                  : _BuildingPlaceholder(
                      icon: Icons.recycling_outlined,
                      title: 'Recycleur',
                      description:
                          'Débloqué au Cœur du Camp niveau ${fablabConfig.recyclerUnlockCampHeartLevel}. Niveau actuel : $campHeartLevel.',
                    ),
              _FablabUpgradeOverview(
                gameState: gameState,
                campHeartLevel: campHeartLevel,
              ),
              const _BuildingInformationTab(
                title: 'Fablab',
                description:
                    'Le Fablab regroupe trois unités indépendantes : Cuisine, Atelier et Recycleur. Chaque unité possède sa propre fonction, son niveau et son projet d’amélioration. Le Fablab ne possède pas de niveau moyen.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FablabUpgradeOverview extends StatelessWidget {
  const _FablabUpgradeOverview({
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Text(
            'Amélioration du Fablab',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les unités progressent séparément. Les projets en cours ne bloquent pas leur fonctionnement au niveau actuel.',
          ),
          const SizedBox(height: 14),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'cuisine',
            title: 'Cuisine',
            level: gameState.cuisineLevel,
            description:
                'Augmente les emplacements de préparation et prépare les recettes futures.',
            nextEffect:
                'Prochain niveau : ${gameState.kitchenSlots + 1} emplacement(s) P’TIPOTE.',
          ),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'atelier',
            title: 'Atelier',
            level: gameState.atelierLevel,
            description:
                'Augmente le stock global et les emplacements de craft P’TIPOTE.',
            nextEffect:
                'Prochain niveau : stock ${gameState.globalStockCapacity + fablabConfig.stockCapacityBonusPerFablabLevel}.',
          ),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'recycler',
            title: 'Recycleur',
            level: gameState.recyclerLevel,
            description: 'Réduit les déchets requis et raccourcit les cycles.',
            nextEffect: campHeartLevel >=
                    fablabConfig.recyclerUnlockCampHeartLevel
                ? 'Prochain niveau : traitement plus efficace.'
                : 'Débloqué au Cœur du Camp niveau ${fablabConfig.recyclerUnlockCampHeartLevel}.',
            enabled:
                campHeartLevel >= fablabConfig.recyclerUnlockCampHeartLevel,
          ),
        ],
      ),
    );
  }
}

class _FablabUnitUpgradeCard extends StatelessWidget {
  const _FablabUnitUpgradeCard({
    required this.gameState,
    required this.targetId,
    required this.title,
    required this.level,
    required this.description,
    required this.nextEffect,
    this.enabled = true,
  });

  final Zone0GameState gameState;
  final String targetId;
  final String title;
  final int level;
  final String description;
  final String nextEffect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final project = gameState.projectFor(targetId);
    final isMaxLevel = project.state == ConstructionProjectState.maxLevel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$title niveau $level',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(description),
            const SizedBox(height: 6),
            Text(nextEffect),
            if (project.isInProgress) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Travaux : ${_countdownLabel(project.endsAt!)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: !enabled || isMaxLevel
                  ? null
                  : () => _showFablabUnitProject(
                        context,
                        gameState: gameState,
                        targetId: targetId,
                        title: 'Améliorer $title',
                        description: description,
                      ),
              icon: const Icon(Icons.upgrade_outlined),
              label: Text(isMaxLevel ? 'Niveau maximum' : 'Préparer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FablabEnergyCard extends StatelessWidget {
  const _FablabEnergyCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Alimenter le Fablab',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                  '⚡ ${gameState.energyUnits} énergie · ${gameState.bioBatteries} bio-batterie(s)'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: gameState.bioBatteries <= 0
                    ? null
                    : () {
                        final result = gameState.openBioBattery();
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)));
                      },
                icon: const Icon(Icons.bolt_outlined),
                label: Text(
                    'Ouvrir 1 bio-batterie (+${wasteRecyclerConfig.energyUnitsPerBioBattery} énergie)'),
              ),
            ],
          ),
        ),
      );
}

class FablabRecyclerView extends StatelessWidget {
  const FablabRecyclerView({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final needed = gameState.recyclerWasteRequired;
    final running = gameState.recyclerCycleStartedAt != null;
    final remaining = running
        ? gameState.recyclerCycleStartedAt!
            .add(Duration(
                minutes:
                    wasteRecyclerConfig.cycleMinutes(gameState.recyclerLevel)))
            .difference(DateTime.now())
        : null;
    final transferable = gameState.resourceAmount('Déchets');
    final cycles = gameState.recyclerWasteTank ~/ needed;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _FablabEnergyCard(gameState: gameState),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Recycleur niveau ${gameState.recyclerLevel}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                      '$needed Déchets → ${wasteRecyclerConfig.outputResourcesPerCycle} ressources'),
                  Text(
                      '${wasteRecyclerConfig.cycleMinutes(gameState.recyclerLevel)} min par cycle · ${wasteRecyclerConfig.energyCostPerCycle} Énergie'),
                ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Cuve d’entrée',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Text(
                      'Déchets : ${gameState.recyclerWasteTank}/${gameState.recyclerTankCapacity} · $cycles cycle(s) possible(s)'),
                  Text('Inventaire : $transferable Déchet(s)'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    ...<int>[1, 5, 10].map((amount) => OutlinedButton(
                        onPressed: transferable == 0
                            ? null
                            : () {
                                final result =
                                    gameState.transferWasteToRecycler(
                                        amount, campHeartLevel);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(result.message)));
                              },
                        child: Text('+$amount'))),
                    FilledButton(
                        onPressed: transferable == 0
                            ? null
                            : () {
                                final result =
                                    gameState.transferWasteToRecycler(
                                        transferable, campHeartLevel);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(result.message)));
                              },
                        child: const Text('Max')),
                  ]),
                ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Production',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Text(running
                      ? 'Recyclage en cours · ${math.max(0, remaining!.inMinutes)} min restantes'
                      : gameState.recyclerOutputAmount >=
                              gameState.recyclerOutputCapacity
                          ? 'Stock de sortie plein'
                          : gameState.recyclerOutputAmount > 0
                              ? 'Production prête'
                              : gameState.recyclerWasteTank < needed
                                  ? 'En attente de Déchets'
                                  : gameState.energyUnits <
                                          wasteRecyclerConfig.energyCostPerCycle
                                      ? 'En attente d’Énergie'
                                      : 'En attente'),
                  if (running)
                    LinearProgressIndicator(
                        value: (1 -
                                remaining!.inSeconds /
                                    Duration(
                                            minutes: wasteRecyclerConfig
                                                .cycleMinutes(
                                                    gameState.recyclerLevel))
                                        .inSeconds)
                            .clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                      'Sortie : ${gameState.recyclerOutputOrganic} Organique · ${gameState.recyclerOutputMineral} Minéral'),
                  FilledButton(
                    onPressed: gameState.recyclerOutputAmount == 0
                        ? null
                        : () {
                            final result = gameState.retrieveRecyclerOutput();
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)));
                          },
                    child: const Text('Récupérer la production'),
                  ),
                ]),
          ),
        ),
      ],
    );
  }
}

class FablabWorkshopView extends StatefulWidget {
  const FablabWorkshopView({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  State<FablabWorkshopView> createState() => _FablabWorkshopViewState();
}

class _FablabWorkshopViewState extends State<FablabWorkshopView> {
  final FigurineService _figurineService = FigurineService();
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    widget.gameState.resolveWorkshopOrder();
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _remaining(WorkshopCraftOrder order) {
    final seconds = math.max(
        0, order.nextCompletionTime.difference(DateTime.now()).inSeconds);
    return '${seconds ~/ 60}m ${seconds.remainder(60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.gameState.activeWorkshopOrders;
    return StreamBuilder<List<PtipoteFigurine>>(
      stream: _figurineService.watchMyFigurines(),
      builder: (context, snapshot) {
        final figurines = snapshot.data ?? const <PtipoteFigurine>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _FablabEnergyCard(gameState: widget.gameState),
            const SizedBox(height: 12),
            Text('Atelier',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            Text(
              'Atelier niv. ${widget.gameState.atelierLevel} · '
              '${widget.gameState.activePtipoteWorkshopOrders}/${widget.gameState.workshopSlots} emplacement(s) P’TIPOTE · '
              '${widget.gameState.activeManualWorkshopOrders}/1 créneau manuel. Chaque niveau ajoute un emplacement P’TIPOTE.',
            ),
            const SizedBox(height: 12),
            ...orders.map((order) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                              craftConfig.recipes
                                  .firstWhere(
                                    (recipe) => recipe.id == order.recipeId,
                                    orElse: () =>
                                        defaultCraftConfig.simpleMealRecipe,
                                  )
                                  .displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                          Text(
                              '${order.completedQuantity} / ${order.requestedQuantity} · prochaine unité ${_remaining(order)}'),
                          Text(order.assignedPtipoteName == null
                              ? 'Mode manuel'
                              : 'Avec ${order.assignedPtipoteName}'),
                          OutlinedButton(
                              onPressed: () => widget.gameState
                                  .cancelWorkshopOrder(order.id),
                              child: const Text('Annuler')),
                        ]),
                  ),
                )),
            if (widget.gameState.activeManualWorkshopOrders < 1 ||
                widget.gameState.activePtipoteWorkshopOrders <
                    widget.gameState.workshopSlots) ...<Widget>[
              SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 5, label: Text('5')),
                    ButtonSegment(value: 10, label: Text('10')),
                  ],
                  selected: <int>{
                    _quantity
                  },
                  onSelectionChanged: (value) =>
                      setState(() => _quantity = value.first)),
              const SizedBox(height: 10),
              ...craftConfig.recipes
                  .where(
                      (recipe) => recipe.craftSection == CraftSection.atelier)
                  .where(widget.gameState.isWorkshopRecipeActive)
                  .map((recipe) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(recipe.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(
                                    'Pattern Kernel · ${recipe.durationMinutes} min/unité'),
                                Text(recipe.ingredients.entries
                                    .map((e) =>
                                        '${e.value * _quantity} ${e.key}')
                                    .join(' + ')),
                                FilledButton(
                                    onPressed: widget.gameState
                                                    .activeManualWorkshopOrders <
                                                1 &&
                                            widget.gameState.energyUnits >= 1
                                        ? () => _start(recipe, null)
                                        : null,
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text('Lancer manuellement'),
                                        Text('utilise 1 unité d’énergie',
                                            style: TextStyle(fontSize: 11)),
                                      ],
                                    )),
                                OutlinedButton.icon(
                                  onPressed: widget.gameState
                                              .activePtipoteWorkshopOrders <
                                          widget.gameState.workshopSlots
                                      ? () async {
                                          final figurine =
                                              await _pickPtipoteForActivity(
                                            context: context,
                                            gameState: widget.gameState,
                                            figurines: figurines,
                                            title:
                                                'Confier ${recipe.displayName}',
                                          );
                                          if (figurine != null &&
                                              context.mounted) {
                                            _start(recipe, figurine);
                                          }
                                        }
                                      : null,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Confier à un P’TIPOTE'),
                                ),
                              ]),
                        ),
                      )),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Créneau manuel et emplacements P’TIPOTE occupés.'),
              ),
          ],
        );
      },
    );
  }

  void _start(CraftRecipe recipe, PtipoteFigurine? figurine) {
    final result = widget.gameState.startWorkshopOrder(
        recipe: recipe, quantity: _quantity, figurine: figurine);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }
}

class FablabCuisineView extends StatefulWidget {
  const FablabCuisineView({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  State<FablabCuisineView> createState() => _FablabCuisineViewState();
}

class _FablabCuisineViewState extends State<FablabCuisineView> {
  final FigurineService _figurineService = FigurineService();
  String? _lastResult;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    widget.gameState.resolveWorkshopOrder();
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PtipoteFigurine>>(
      stream: _figurineService.watchMyFigurines(),
      builder: (context, snapshot) {
        final figurines = snapshot.data ?? const <PtipoteFigurine>[];
        final orders = widget.gameState.activeKitchenOrders;
        return ListView(padding: const EdgeInsets.all(18), children: <Widget>[
          _FablabEnergyCard(gameState: widget.gameState),
          const SizedBox(height: 12),
          Text('Cuisine niveau ${widget.gameState.cuisineLevel}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Eau disponible gratuitement. ${widget.gameState.activePtipoteKitchenOrders}/${widget.gameState.kitchenSlots} emplacement(s) P’TIPOTE · ${widget.gameState.activeManualKitchenOrders}/1 créneau manuel.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <int>[1, 5, 10]
                .map((quantity) => ChoiceChip(
                      label: Text('x$quantity'),
                      selected: _quantity == quantity,
                      onSelected: (_) => setState(() => _quantity = quantity),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          ...orders.map((order) => Card(
                child: ListTile(
                  title: Text(craftConfig.recipes
                      .firstWhere((recipe) => recipe.id == order.recipeId)
                      .displayName),
                  subtitle: Text(
                    '${order.completedQuantity}/${order.requestedQuantity} · ${_countdownLabel(order.nextCompletionTime)}\n${order.assignedPtipoteName == null ? 'Mode manuel' : 'Avec ${order.assignedPtipoteName}'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Annuler',
                    onPressed: () =>
                        widget.gameState.cancelWorkshopOrder(order.id),
                    icon: const Icon(Icons.close),
                  ),
                ),
              )),
          ...craftConfig.recipes
              .where((recipe) => recipe.craftSection == CraftSection.cuisine)
              .map((recipe) => _CuisineRecipeCard(
                    recipe: recipe,
                    gameState: widget.gameState,
                    quantity: _quantity,
                    canPrepare: widget.gameState.hasResources(recipe.ingredients
                            .map((key, value) =>
                                MapEntry(key, value * _quantity))) &&
                        widget.gameState.hasInventoryCapacityFor(
                          <String, int>{
                            recipe.resultItem: recipe.resultAmount * _quantity
                          },
                        ),
                    manualAvailable:
                        widget.gameState.activeManualKitchenOrders < 1,
                    ptipoteAvailable:
                        widget.gameState.activePtipoteKitchenOrders <
                            widget.gameState.kitchenSlots,
                    onPrepare: () => _start(recipe, null),
                    onAssign: () async {
                      final figurine = await _pickPtipoteForActivity(
                        context: context,
                        gameState: widget.gameState,
                        figurines: figurines,
                        title: 'Confier ${recipe.displayName}',
                      );
                      if (figurine != null && context.mounted) {
                        _start(recipe, figurine);
                      }
                    },
                  )),
          if (_lastResult != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_lastResult!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ]);
      },
    );
  }

  void _start(CraftRecipe recipe, PtipoteFigurine? figurine) {
    final result = widget.gameState.startKitchenOrder(
      recipe: recipe,
      quantity: _quantity,
      figurine: figurine,
    );
    setState(() => _lastResult = result.message);
  }
}

class _CuisineRecipeCard extends StatelessWidget {
  const _CuisineRecipeCard({
    required this.recipe,
    required this.gameState,
    required this.quantity,
    required this.canPrepare,
    required this.manualAvailable,
    required this.ptipoteAvailable,
    required this.onPrepare,
    required this.onAssign,
  });

  final CraftRecipe recipe;
  final Zone0GameState gameState;
  final int quantity;
  final bool canPrepare;
  final bool manualAvailable;
  final bool ptipoteAvailable;
  final VoidCallback onPrepare;
  final Future<void> Function() onAssign;

  @override
  Widget build(BuildContext context) {
    final costs =
        recipe.ingredients.map((key, value) => MapEntry(key, value * quantity));
    final output = <String, int>{
      recipe.resultItem: recipe.resultAmount * quantity
    };
    final missingLabel = !gameState.hasResources(costs)
        ? gameState.missingResourcesLabel(costs)
        : 'Inventaire plein : impossible de ranger ${recipe.resultItem}.';
    final ingredientText =
        costs.entries.map((entry) => '${entry.value} ${entry.key}').join(' + ');
    final contextText = recipe.contextIngredients.entries
        .map((entry) => '${entry.value} ${entry.key}')
        .join(' + ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${recipe.displayName} · Cuisine niv. ${recipe.cuisineLevel}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _RecipeSlot(
                    label: 'Ingrédients',
                    value: ingredientText,
                    icon: Icons.eco_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RecipeSlot(
                    label: 'Cuisine',
                    value: contextText.isEmpty ? 'Aucun' : contextText,
                    icon: Icons.water_drop_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
                'Résultat : ${recipe.resultAmount * quantity} ${recipe.resultItem}'),
            Text(
              'Type : ${recipe.foodType.name} · faim +${recipe.hungerRestore} · vitalité +${recipe.vitalityRestore}',
            ),
            Text('Stock Organique : ${gameState.resourceAmount('Organique')}'),
            if (!canPrepare) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                gameState.hasInventoryCapacityFor(output)
                    ? missingLabel
                    : 'Inventaire plein : impossible de ranger ${recipe.resultItem}.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  canPrepare && manualAvailable && gameState.energyUnits >= 1
                      ? onPrepare
                      : null,
              icon: Icon(
                recipe.foodType == FoodType.drink
                    ? Icons.local_drink_outlined
                    : Icons.restaurant_outlined,
              ),
              label: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Lancer manuellement'),
                  Text('utilise 1 unité d’énergie',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: canPrepare && ptipoteAvailable ? onAssign : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Confier à un P’TIPOTE'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeSlot extends StatelessWidget {
  const _RecipeSlot({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Icon(icon),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(value, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BuildingPlaceholder extends StatelessWidget {
  const _BuildingPlaceholder({
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(icon, size: 58),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                ),
                if (actions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  ...actions,
                ],
                const SizedBox(height: 18),
                const Text(
                  'Page de base créée. Le gameplay sera branché dans une étape suivante.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MissingGameImage extends StatelessWidget {
  const _MissingGameImage({required this.screenName});

  final String screenName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Image manquante : $screenName',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RefugeBuilding {
  const _RefugeBuilding({
    required this.name,
    String? title,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : title = title ?? name;

  final String name;
  final String title;
  final double left;
  final double top;
  final double width;
  final double height;

  IconData get icon {
    return switch (name) {
      'Maison' => Icons.bedroom_baby_outlined,
      'Kernel' => Icons.device_hub_outlined,
      'CampHeart' => Icons.energy_savings_leaf_outlined,
      'Lisiere' => Icons.forest_outlined,
      'Tour' => Icons.shield_outlined,
      'FabLab' => Icons.precision_manufacturing_outlined,
      _ => Icons.place_outlined,
    };
  }

  String get description {
    return switch (name) {
      'Maison' => 'Accueil des P’TIPOTES, repos, chambres et soins.',
      'Kernel' => 'Centre du refuge : scan, messages système et plans futurs.',
      'CampHeart' =>
        'Bio-réacteur organique du refuge : végétalisation, habitabilité et progression du camp.',
      'Lisiere' => 'Exploration future des biomes proches et lointains.',
      'Tour' => 'Sécurité, stabilité et protection future du refuge.',
      'FabLab' => 'Accès aux espaces Atelier et Cuisine.',
      _ => 'Écran placeholder prêt à recevoir ses futures fonctions.',
    };
  }
}
