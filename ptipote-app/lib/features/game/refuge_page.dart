import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/figurine_service.dart';
import '../../services/notification_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_image.dart';
import '../nfc/nfc_page.dart';
import '../figurines/ptipote_stats_config.dart';
import 'camp_heart_config.dart';
import 'camp_generator_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'game_asset_resolver.dart';
import 'housing_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'ptibug_valuation_service.dart';
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

class _RefugePageState extends State<RefugePage> with WidgetsBindingObserver {
  static final _campHeartState = CampHeartState.placeholder();
  static final _zone0State = Zone0GameState.instance;

  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  String? _refugeAsset;
  Timer? _missionResolutionTimer;
  bool _simulationStarted = false;
  bool _energyWarning600Dismissed = false;
  bool _energyWarning699Dismissed = false;

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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zone0State.addListener(_onZone0StateChanged);
    unawaited(_warmAssets());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_flushZone0State());
    _missionResolutionTimer?.cancel();
    _zone0State.removeListener(_onZone0StateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushZone0State());
    }
  }

  void _onZone0StateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _warmAssets() async {
    await _zone0State.loadFromFirebase();
    if (!mounted || !_zone0State.hasLoadedFromFirebase) return;

    // The Camp Heart level affects several offline resolvers. Restore it
    // before resolving any mission or production state from the saved game.
    final campHeartData = await _zone0State.loadCampHeartFromFirebase();
    if (campHeartData != null) {
      _campHeartState.applyFirebaseData(campHeartData);
    }
    if (!mounted) return;

    _zone0State.resolveDueForageMissions();
    _zone0State.resolveDueTowerMissions();
    _zone0State.resolveGenerator(heartLevel: _campHeartState.campHeartLevel);
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
    if (!mounted) return;
    _startSimulationTimer();
    setState(() {});
  }

  void _startSimulationTimer() {
    if (_simulationStarted || !_zone0State.hasLoadedFromFirebase) return;
    _simulationStarted = true;
    _missionResolutionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _zone0State.resolveDueForageMissions();
      _zone0State.resolveDueTowerMissions();
      _zone0State.resolveGenerator(heartLevel: _campHeartState.campHeartLevel);
      _zone0State.resolveWorkshopOrder();
      _zone0State.resolveConstructionProjects();
      _zone0State.resolvePTibugProduction();
      _zone0State.resolveMarket();
      _zone0State.resolveWasteAndRecycler(
        campHeartLevel: _campHeartState.campHeartLevel,
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _flushZone0State() async {
    if (!_zone0State.hasLoadedFromFirebase) return;
    await _zone0State.saveAllToFirebase();
    await _zone0State.saveCampHeartToFirebase(_campHeartState.toFirebaseData());
    await _zone0State.flushFirebaseWrites();
  }

  void _openBuilding(_RefugeBuilding building) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (building.name == 'Maison') return const _MaisonPage();
          if (building.name == 'Lisiere') {
            return LisierePage(
              gameState: _zone0State,
              campHeartState: _campHeartState,
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
              campHeartState: _campHeartState,
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
          campHeartState: _campHeartState,
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
            if (_zone0State.bioBatteries >= 699 && !_energyWarning699Dismissed)
              _EnergyStorageWarning(
                message:
                    'Attention : à partir de là, l’énergie provenant des Cœurs d’énergie descellés en trop sera perdue.',
                onClose: () =>
                    setState(() => _energyWarning699Dismissed = true),
              )
            else if (_zone0State.bioBatteries >= 600 &&
                !_energyWarning600Dismissed)
              _EnergyStorageWarning(
                message:
                    'Attention : limite presque atteinte. Crée un Cœur d’énergie à l’Atelier avant de ne plus pouvoir en stocker.',
                onClose: () =>
                    setState(() => _energyWarning600Dismissed = true),
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
                            notificationCount: _zone0State
                                    .unreadBuildingNotificationCount(
                                  building.name,
                                ) +
                                (building.name == 'Kernel'
                                    ? _zone0State
                                        .unreadKernelMissionNotificationCount(
                                        _campHeartState.campHeartLevel,
                                      )
                                    : 0),
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

class _EnergyStorageWarning extends StatelessWidget {
  const _EnergyStorageWarning({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4CB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC99719)),
          ),
          child: Row(children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child:
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFC99719)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
          ]),
        ),
      );
}

class _CampHud extends StatelessWidget {
  const _CampHud({required this.gameState, required this.campHeartLevel});

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
            onTap: () => _showHudInfo(
              context,
              'Population',
              'La communauté installée au refuge. Elle arrive par les missions du Kernel et ne dépasse jamais la capacité du Cœur du Camp.',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _HudChip(
            icon: Icons.battery_charging_full_outlined,
            color: const Color(0xFF2878C9),
            richLabel: _energyHudLabel(gameState),
            onTap: () => _showHudInfo(
              context,
              'Bio-batteries et bio-piles',
              'Les bio-batteries (bleu) alimentent le refuge. Les bio-piles (jaune) sont la monnaie fine du Marché : 10 bio-piles sont automatiquement converties en 1 bio-batterie.',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HudChip(
            icon: Icons.sentiment_satisfied_alt_outlined,
            label: '${gameState.displayedCampWellbeing}%',
            color: wellbeingColor,
            onTap: () => _showHudInfo(
              context,
              'Bien-être',
              'Le bien-être du refuge reflète sa stabilité. La Sécurité actuelle apporte ${gameState.securityWellbeingModifier >= 0 ? '+' : ''}${gameState.securityWellbeingModifier}% (${towerOperationsConfig.wellbeingBandFor(gameState.refugeSafety).label}).',
            ),
          ),
        ),
      ],
    );
  }

  InlineSpan _energyHudLabel(Zone0GameState state) {
    const batteryBlue = Color(0xFF2878C9);
    const pileYellow = Color(0xFFC99719);
    final batteries = state.bioBatteries;
    final piles = state.bioPiles;
    // A fine amount alone reads as a pile ("5"), never as an artificial
    // decimal ("0,5"). Once a whole battery exists, the decimal stays clear.
    if (batteries <= 0) {
      return TextSpan(
        text: '$piles',
        style: const TextStyle(color: pileYellow, fontWeight: FontWeight.w900),
      );
    }
    return TextSpan(children: <InlineSpan>[
      TextSpan(
        text: '$batteries',
        style: const TextStyle(color: batteryBlue, fontWeight: FontWeight.w900),
      ),
      if (piles > 0) ...<InlineSpan>[
        const TextSpan(text: ','),
        TextSpan(
          text: '$piles',
          style:
              const TextStyle(color: pileYellow, fontWeight: FontWeight.w900),
        ),
      ],
    ]);
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
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(body),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.icon,
    this.label,
    this.richLabel,
    this.color = const Color(0xFF2F241A),
    this.onTap,
  });

  final IconData icon;
  final String? label;
  final InlineSpan? richLabel;
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
                child: richLabel == null
                    ? Text(
                        label ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w900),
                      )
                    : Text.rich(richLabel!, overflow: TextOverflow.ellipsis),
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
    this.initialTabIndex = 0,
  });

  final Zone0GameState gameState;
  final CampHeartState campHeartState;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    gameState.refreshKernelMissions(
      campHeartLevel: campHeartState.campHeartLevel,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gameState.markKernelMissionsViewed(campHeartState.campHeartLevel);
      unawaited(
        NotificationService().markTypesAsRead(<String>{'kernel_mission'}),
      );
    });
    final mainMission = gameState.mainKernelMission(
      campHeartState.campHeartLevel,
    );
    final requests = gameState.refugeRequests(campHeartState.campHeartLevel);
    final mainCount = mainMission?.status == KernelMissionStatus.active ? 1 : 0;
    final requestCount = requests
        .where((mission) => mission.status == KernelMissionStatus.active)
        .length;
    return DefaultTabController(
      length: 4,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kernel'),
          actions: <Widget>[
            _MailboxButton(
              tooltip: 'Messages Kernel',
              unreadCount: gameState.unreadReportCountForMailbox(
                Zone0MessageMailbox.kernel,
              ),
              onPressed: () {
                gameState.markReportsRead(mailbox: Zone0MessageMailbox.kernel);
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => MissionReportsSheet(
                    gameState: gameState,
                    mailbox: Zone0MessageMailbox.kernel,
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              const Tab(text: 'Progression'),
              Tab(
                child: _KernelTabLabel(
                  label: 'Mission principale',
                  count: mainCount,
                ),
              ),
              Tab(
                child: _KernelTabLabel(label: 'Demandes', count: requestCount),
              ),
              const Tab(text: 'Plans'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              _KernelProgressTab(
                gameState: gameState,
                campHeartState: campHeartState,
              ),
              _KernelMainMissionTab(mission: mainMission, gameState: gameState),
              _KernelRequestsTab(missions: requests, gameState: gameState),
              _KernelPlansTab(gameState: gameState),
            ],
          ),
        ),
      ),
    );
  }
}

class _KernelTabLabel extends StatelessWidget {
  const _KernelTabLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label),
          if (count > 0) ...<Widget>[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      );
}

class _MailboxButton extends StatelessWidget {
  const _MailboxButton({
    required this.tooltip,
    required this.unreadCount,
    required this.onPressed,
  });

  final String tooltip;
  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          IconButton(
            tooltip: tooltip,
            icon: const Icon(Icons.mail_outline),
            onPressed: onPressed,
          ),
          if (unreadCount > 0)
            Positioned(
              top: 7,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  child: Text(
                    '$unreadCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

class _KernelMainMissionTab extends StatelessWidget {
  const _KernelMainMissionTab({required this.mission, required this.gameState});

  final KernelMissionProgress? mission;
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    if (mission == null) {
      return const _KernelEmptyState(
        message: 'Aucune mission principale active.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        _KernelMissionCard(mission: mission!, gameState: gameState),
      ],
    );
  }
}

class _KernelRequestsTab extends StatelessWidget {
  const _KernelRequestsTab({
    required this.missions,
    required this.gameState,
  });

  final List<KernelMissionProgress> missions;
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        if (missions.isEmpty)
          const _KernelEmptyState(message: 'Aucune demande du refuge.')
        else
          ...missions.map(
            (mission) =>
                _KernelMissionCard(mission: mission, gameState: gameState),
          ),
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
    final card = Card(
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(result.message)));
                },
                child: Text(
                  'Remettre ${config.requestedAmount} ${config.requestedItem}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mission.isCompleted) return card;
    return Dismissible(
      key: ValueKey<String>('kernel-mission-${config.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      onDismissed: (_) => gameState.dismissCompletedKernelMission(config.id),
      child: card,
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
    final pTibugPatterns = pTibugConfig.researchPatterns.values
        .where(
          (pattern) =>
              (_category == null || _category == KernelPlanCategory.ptibug) &&
              widget.gameState.pTibugResearchPatternVisibility(pattern) > 0,
        )
        .toList(growable: false);
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
          final visibility = widget.gameState.kernelPlanVisibility(plan);
          if (visibility == 0) return const SizedBox.shrink();
          final visible = visibility >= 2;
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
                            visible ? plan.title : 'Pattern non identifié',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (visible) _KernelPlanStatePill(state: state),
                      ],
                    ),
                    if (visible) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(plan.description),
                    ],
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
                      if (plan.dataRequirements.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Données requises : ${widget.gameState.kernelPlanDataRequirementsLabel(plan)}',
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () {
                            final result = widget.gameState
                                .investKernelPlanDataAutomatically(plan.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.message)),
                            );
                          },
                          child: const Text('Investir les données disponibles'),
                        ),
                      ],
                    ],
                    if (state == KernelPlanState.ready) ...<Widget>[
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () {
                          final result = widget.gameState.activateKernelPlan(
                            plan.id,
                          );
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
        ...pTibugPatterns.map(
          (pattern) => _PTibugKernelPatternCard(
            gameState: widget.gameState,
            pattern: pattern,
          ),
        ),
      ],
    );
  }
}

class _PTibugKernelPatternCard extends StatelessWidget {
  const _PTibugKernelPatternCard({
    required this.gameState,
    required this.pattern,
  });

  final Zone0GameState gameState;
  final PTibugResearchPatternConfig pattern;

  @override
  Widget build(BuildContext context) {
    final visibility = gameState.pTibugResearchPatternVisibility(pattern);
    final progress = gameState.pTibugPatternProgress[pattern.id];
    final discovered =
        progress != null && progress.state != PTibugPatternState.unknown;
    final active = gameState.isPTibugPatternActive(pattern.id);
    final canEvolve = pattern.category == PTibugPatternCategory.trait &&
        (progress?.masteryLevel ?? 0) < pattern.masteryCosts.length;
    final canInvest = discovered && (!active || canEvolve);
    final nextCost = pattern.masteryCosts[(progress?.masteryLevel ?? 0) + 1] ??
        const <PTibugDataFamily, int>{};
    final identified = visibility >= 2;

    return Opacity(
      opacity: identified ? 1 : 0.48,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    active
                        ? Icons.check_circle_outline
                        : discovered
                            ? Icons.science_outlined
                            : Icons.lock_outline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      identified
                          ? pattern.displayName
                          : 'Pattern non identifié',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (identified)
                    Text(
                      active
                          ? 'Actif'
                          : discovered
                              ? 'Découvert'
                              : 'Inconnu',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                ],
              ),
              if (identified) ...<Widget>[
                const SizedBox(height: 10),
                Text(pattern.description),
                const SizedBox(height: 8),
                Text(
                  'Pré-requis : ${gameState.pTibugResearchPatternRequirementsLabel(pattern)}',
                ),
                if (discovered && nextCost.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Données requises : ${nextCost.entries.map((entry) => '${_kernelDataFamilyLabel(entry.key)} ${entry.value}').join(' · ')}',
                  ),
                ],
                if (canInvest) ...<Widget>[
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () {
                      final result = gameState
                          .completePTibugPatternAutomatically(pattern.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    },
                    child: Text(
                      active
                          ? 'Investir pour le niveau suivant'
                          : 'Investir les données disponibles',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
        const SizedBox(height: 12),
        _KernelDataCellsCard(gameState: gameState),
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

class _KernelDataCellsCard extends StatelessWidget {
  const _KernelDataCellsCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final unopened = gameState.pTibugDataCells
        .where((cell) => !cell.isOpened)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Cellules de données',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (unopened.isNotEmpty)
                  Chip(label: Text('${unopened.length} à analyser')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              unopened.isEmpty
                  ? 'Aucune cellule non analysée. Les missions de Lisière peuvent en rapporter.'
                  : 'Analysez les cellules trouvées en Lisière pour alimenter les recherches P\'TIBUG.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: PTibugDataFamily.values
                  .map(
                    (family) => Chip(
                      label: Text(
                        '${_kernelDataFamilyLabel(family)} ${gameState.pTibugDataReserve[family] ?? 0}',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (unopened.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (sheetContext) => _KernelDataCellsSheet(
                    gameState: gameState,
                    onCellOpened: () {
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Analyser les cellules'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KernelDataCellsSheet extends StatefulWidget {
  const _KernelDataCellsSheet({
    required this.gameState,
    required this.onCellOpened,
  });

  final Zone0GameState gameState;
  final VoidCallback onCellOpened;

  @override
  State<_KernelDataCellsSheet> createState() => _KernelDataCellsSheetState();
}

class _KernelDataCellsSheetState extends State<_KernelDataCellsSheet> {
  @override
  Widget build(BuildContext context) {
    final cells = widget.gameState.pTibugDataCells
        .where((cell) => !cell.isOpened)
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Cellules à analyser',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Chaque cellule contient cinq entrées de données. L\'analyse les transfère définitivement dans la réserve du Kernel.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: cells.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final cell = cells[index];
                    final total = cell.entries.fold<int>(
                      0,
                      (sum, entry) => sum + entry.value(pTibugConfig),
                    );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.memory_outlined),
                      title: Text(cell.displayName),
                      subtitle: Text(
                        '${cell.isNeutralCell ? 'Neutre' : _kernelDataFamilyLabel(cell.dominantFamily!)} · 5 données · valeur $total',
                      ),
                      trailing: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final confirmed = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => _KernelDataCellRevealSheet(
                              cell: cell,
                            ),
                          );
                          if (!mounted || confirmed != true) return;
                          final result = widget.gameState.openPTibugDataCell(
                            cell.id,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                          if (result.success) widget.onCellOpened();
                        },
                        child: const Text('Ouvrir'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KernelDataCellRevealSheet extends StatefulWidget {
  const _KernelDataCellRevealSheet({required this.cell});

  final PTibugDataCell cell;

  @override
  State<_KernelDataCellRevealSheet> createState() =>
      _KernelDataCellRevealSheetState();
}

class _KernelDataCellRevealSheetState
    extends State<_KernelDataCellRevealSheet> {
  Timer? _timer;
  int _revealedEntries = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || _revealedEntries >= widget.cell.entries.length) {
        timer.cancel();
        return;
      }
      setState(() => _revealedEntries += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _revealAll() {
    _timer?.cancel();
    setState(() => _revealedEntries = widget.cell.entries.length);
  }

  @override
  Widget build(BuildContext context) {
    final complete = _revealedEntries >= widget.cell.entries.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Analyse de ${widget.cell.displayName}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le Kernel révèle les cinq entrées avant leur ajout définitif à la réserve.',
            ),
            const SizedBox(height: 14),
            ...widget.cell.entries.asMap().entries.map((item) {
              final entry = item.value;
              final visible = item.key < _revealedEntries;
              return Card(
                child: ListTile(
                  leading: Icon(
                    visible ? Icons.memory_outlined : Icons.lock_outline,
                  ),
                  title: Text(
                    visible
                        ? _kernelDataFamilyLabel(entry.family)
                        : 'Entrée en cours d’analyse',
                  ),
                  trailing: visible
                      ? Text(
                          '+${entry.value(pTibugConfig)} · ${_kernelDataQualityLabel(entry.quality)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )
                      : const SizedBox.shrink(),
                ),
              );
            }),
            const SizedBox(height: 12),
            if (!complete)
              OutlinedButton.icon(
                onPressed: _revealAll,
                icon: const Icon(Icons.fast_forward_outlined),
                label: const Text('Tout révéler'),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    complete ? () => Navigator.of(context).pop(true) : null,
                child: Text(
                  complete
                      ? 'Ajouter au Kernel'
                      : 'Analyse $_revealedEntries / ${widget.cell.entries.length}',
                ),
              ),
            ),
          ],
        ),
      ),
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
              Text(
                '$title · niv. $level',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
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

String _kernelDataFamilyLabel(PTibugDataFamily family) => switch (family) {
      PTibugDataFamily.organique => 'Organique',
      PTibugDataFamily.minerale => 'Minérale',
      PTibugDataFamily.mycelienne => 'Mycélienne',
      PTibugDataFamily.toxine => 'Toxine',
      PTibugDataFamily.biomimetisme => 'Biomimétisme',
      PTibugDataFamily.energie => 'Énergie',
      PTibugDataFamily.comportementInsectoide => 'Insectoïde',
    };

String _kernelDataQualityLabel(PTibugDataQuality quality) => switch (quality) {
      PTibugDataQuality.common => 'Commune',
      PTibugDataQuality.sought => 'Recherchée',
      PTibugDataQuality.rare => 'Rare',
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
  late final TabController _tabs;
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
    _tabs = TabController(length: 4, vsync: this);
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
    _tabs.dispose();
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

  PtipoteAutoAssignmentPreference _autoPreferenceFor(PtipoteFigurine figurine) {
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
    unawaited(_selectFoodForFigurine(figurine));
  }

  Future<void> _selectFoodForFigurine(PtipoteFigurine figurine) async {
    final recipes = _gameState.availableConsumableRecipes;
    if (recipes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun repas ou boisson disponible.')),
      );
      return;
    }
    final recipe = await showModalBottomSheet<CraftRecipe>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            Text(
              'Donner à ${figurine.displayName}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...recipes.map(
              (item) => ListTile(
                leading: const Icon(Icons.restaurant_outlined),
                title: Text(item.resultItem),
                subtitle: Text(
                  'Stock ${_gameState.resourceAmount(item.resultItem)} · faim +${item.hungerRestore} · vitalité +${item.vitalityRestore}',
                ),
                onTap: () => Navigator.of(context).pop(item),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || recipe == null) return;
    final result = _gameState.consumeConsumable(figurine, recipe);
    setState(() => _selectedFigurineId = figurine.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maison'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'P’TIPOTES', icon: Icon(Icons.pets_outlined)),
            Tab(text: 'Couveuse', icon: Icon(Icons.egg_alt_outlined)),
            Tab(text: 'Amélioration', icon: Icon(Icons.upgrade_outlined)),
            Tab(text: 'Infos', icon: Icon(Icons.info_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
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
                          _gameState.ensureNurseryAdmissions(figurines);
                          final admitted = figurines
                              .where(
                                (figurine) => !_gameState.isInNursery(figurine),
                              )
                              .toList();
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              figurines.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (admitted.isEmpty) {
                            return const _RefugeEmptyState();
                          }
                          return Stack(
                            children: <Widget>[
                              _PtipoteRefugeLayer(
                                figurines: admitted,
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
                                    _gameState.isAssignedToWorkshop(
                                      figurineId,
                                    ) ||
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
                                availableSimpleMeals: _gameState
                                    .availableConsumableRecipes.length,
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
                                unreadCount:
                                    _gameState.unreadReportCountForMailbox(
                                  Zone0MessageMailbox.companions,
                                ),
                                onInventory: _openInventory,
                                onMessages: _openMessages,
                                onDashboard: _openPtipoteDashboard,
                                onBatteryChest: _openBatteryChest,
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
          _MaisonNurseryTab(
            gameState: _gameState,
            onHatched: () => _tabs.animateTo(0),
          ),
          _HouseUpgradeTab(gameState: _gameState),
          const _BuildingInformationTab(
            title: 'Maison',
            description:
                'La Maison accueille les P’TIPOTES actifs, leurs alcôves de repos, les messages et l’inventaire du refuge. Son amélioration augmente les alcôves. Les logements des habitants sont agrégés et n’ajoutent pas directement de population.',
          ),
        ],
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
    _gameState.markReportsRead(mailbox: Zone0MessageMailbox.companions);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => MissionReportsSheet(
        gameState: _gameState,
        mailbox: Zone0MessageMailbox.companions,
      ),
    );
  }

  void _openPtipoteDashboard() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StreamBuilder<List<PtipoteFigurine>>(
        stream: _figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          final figurines = snapshot.data ?? const <PtipoteFigurine>[];
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: <Widget>[
                Text(
                  'Tableau des P\'TIPOTES',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                if (figurines.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Aucun P’TIPOTE dans la Maison.'),
                    ),
                  )
                else
                  ...figurines.map(
                    (figurine) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PtipoteDashboardCard(
                        figurine: figurine,
                        hunger: _gameState.hungerFor(figurine),
                        rest: _gameState.restFor(figurine),
                        energy: _gameState.vitalityFor(figurine),
                        activity: _ptipoteActivityLabel(figurine),
                        countdown: _ptipoteActivityCountdown(figurine),
                        onRename: () => _renameFromDashboard(figurine),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _renameFromDashboard(PtipoteFigurine figurine) async {
    final controller = TextEditingController(text: figurine.displayName);
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Renommer ${figurine.displayName}'),
              content: TextField(
                  controller: controller, autofocus: true, maxLength: 24),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('Enregistrer'))
              ],
            ));
    if (!mounted || value == null || value.trim().isEmpty) return;
    try {
      await _figurineService.renameMyFigurine(
          figurine: figurine, nickname: value);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _openBatteryChest() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: _BatteryChestDashboardCard(gameState: _gameState))),
      );

  String _ptipoteActivityLabel(PtipoteFigurine figurine) {
    final tower = _gameState.towerMissions
        .where(
          (mission) =>
              mission.figurineId == figurine.id &&
              mission.status == TowerMissionStatus.active,
        )
        .firstOrNull;
    if (tower != null) {
      return tower.patrolBiome == null
          ? 'Ronde dans le camp'
          : 'Ronde : ${lisiereForageConfig.biomes[tower.patrolBiome]!.label}';
    }
    final forage = _gameState.missions
        .where(
          (mission) =>
              mission.memberIds.contains(figurine.id) &&
              mission.status == ForageMissionStatus.active,
        )
        .firstOrNull;
    if (forage != null) {
      return 'Lisière : ${lisiereForageConfig.biomes[forage.biome]!.label}';
    }
    final order = _gameState.activeWorkshopOrders
        .where((item) => item.assignedPtipoteId == figurine.id)
        .firstOrNull;
    if (order != null) return 'Craft en cours';
    if (_gameState.isAssignedToMarket(figurine.id)) return 'Affecté au Marché';
    if (_gameState.isResting(figurine)) return 'Repos en alcôve';
    if (_gameState.isInNursery(figurine)) return 'En attente dans la Couveuse';
    return 'Disponible à la Maison';
  }

  String _ptipoteActivityCountdown(PtipoteFigurine figurine) {
    final endsAt = <DateTime?>[
      _gameState.towerMissions
          .where(
            (mission) =>
                mission.figurineId == figurine.id &&
                mission.status == TowerMissionStatus.active,
          )
          .firstOrNull
          ?.endTime,
      _gameState.missions
          .where(
            (mission) =>
                mission.memberIds.contains(figurine.id) &&
                mission.status == ForageMissionStatus.active,
          )
          .firstOrNull
          ?.endTime,
      _gameState.activeWorkshopOrders
          .where((item) => item.assignedPtipoteId == figurine.id)
          .firstOrNull
          ?.nextCompletionTime,
    ].whereType<DateTime>().firstOrNull;
    return endsAt == null ? '' : _countdownLabel(endsAt);
  }
}

class _MaisonNurseryTab extends StatelessWidget {
  const _MaisonNurseryTab({required this.gameState, required this.onHatched});

  final Zone0GameState gameState;
  final VoidCallback onHatched;

  @override
  Widget build(BuildContext context) {
    final figurineService = FigurineService();
    return SafeArea(
      child: StreamBuilder<List<PtipoteFigurine>>(
        stream: figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          final figurines = snapshot.data ?? const <PtipoteFigurine>[];
          gameState.ensureNurseryAdmissions(figurines);
          final eggs = figurines
              .where((figurine) => gameState.isInNursery(figurine))
              .toList();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                'Couveuse',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Les P’TIPOTES en attente d’une alcôve reposent ici sous forme d’œuf.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NfcPage()),
                ),
                icon: const Icon(Icons.nfc),
                label: const Text('Scanner un P’TIPOTE'),
              ),
              const SizedBox(height: 18),
              if (eggs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Aucun œuf en attente. Les prochains scans apparaîtront ici si la Maison est pleine.',
                    ),
                  ),
                )
              else
                ...eggs.map(
                  (figurine) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.egg_alt_outlined, size: 54),
                          const SizedBox(height: 8),
                          Text(
                            figurine.displayName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(figurine.type, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          if (gameState.canHatchFromNursery(figurine))
                            FilledButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => _EggHatchDialog(
                                  figurine: figurine,
                                  gameState: gameState,
                                  onFinished: onHatched,
                                ),
                              ),
                              child: const Text('Faire éclore'),
                            )
                          else
                            Text(
                              'Une alcôve libre est nécessaire (${gameState.hatchedPtipoteIds.length}/${gameState.alcoveCapacity}).',
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.egg_alt_outlined, size: 54),
                      const SizedBox(height: 8),
                      const Text(
                        'Œuf de démonstration',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Text(
                        'Teste les trois rythmes sans faire éclore un P’TIPOTE réel.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _EggHatchDialog(
                            gameState: gameState,
                            isPractice: true,
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Tester l’éclosion'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EggHatchDialog extends StatefulWidget {
  const _EggHatchDialog({
    this.figurine,
    required this.gameState,
    this.onFinished,
    this.isPractice = false,
  });

  final PtipoteFigurine? figurine;
  final Zone0GameState gameState;
  final VoidCallback? onFinished;
  final bool isPractice;

  @override
  State<_EggHatchDialog> createState() => _EggHatchDialogState();
}

class _EggHatchDialogState extends State<_EggHatchDialog> {
  static const _rhythmOffsets = <List<int>>[
    <int>[0, 550, 1100, 1650],
    <int>[0, 450, 900, 1500, 2050],
    <int>[0, 600, 1100, 1700, 2200, 2750],
  ];
  static const _tapTolerance = Duration(milliseconds: 1250);
  final List<Timer> _previewTimers = <Timer>[];
  final List<DateTime> _tapTimes = <DateTime>[];
  int _stage = 0;
  int _taps = 0;
  int _previewBeat = -1;
  bool _isPulsing = false;
  bool _hatched = false;
  String? _feedback;

  String get _displayName => widget.figurine?.displayName ?? 'Œuf de test';
  String get _type => widget.figurine?.type ?? 'Démonstration';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPreview());
  }

  @override
  void dispose() {
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _playPreview() {
    if (_hatched) return;
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _previewTimers.clear();
    setState(() {
      _previewBeat = -1;
      _isPulsing = false;
      _feedback = null;
    });
    for (var beat = 0; beat < _rhythmOffsets[_stage].length; beat += 1) {
      _previewTimers.add(
        Timer(Duration(milliseconds: _rhythmOffsets[_stage][beat]), () {
          _showPreviewBeat(beat);
        }),
      );
    }
  }

  void _showPreviewBeat(int beat) {
    if (!mounted) return;
    setState(() {
      _previewBeat = beat;
      _isPulsing = true;
    });
    Timer(const Duration(milliseconds: 90), () {
      if (mounted && _previewBeat == beat) {
        setState(() => _isPulsing = false);
      }
    });
  }

  void _tap() {
    if (_hatched) return;
    final now = DateTime.now();
    if (_tapTimes.isNotEmpty) {
      final beatIndex = _tapTimes.length;
      final expectedGap = Duration(
        milliseconds: _rhythmOffsets[_stage][beatIndex] -
            _rhythmOffsets[_stage][beatIndex - 1],
      );
      final actualGap = now.difference(_tapTimes.last);
      final drift = (actualGap - expectedGap).abs();
      if (drift > _tapTolerance) {
        setState(() {
          _tapTimes.clear();
          _taps = 0;
          _feedback =
              'Le rythme ne correspond pas encore. Observe puis réessaie.';
        });
        _playPreview();
        return;
      }
    }
    _tapTimes.add(now);
    setState(() => _taps = _tapTimes.length);
    if (_taps < _rhythmOffsets[_stage].length) return;
    if (_stage == _rhythmOffsets.length - 1) {
      for (final timer in _previewTimers) {
        timer.cancel();
      }
      if (!widget.isPractice && widget.figurine != null) {
        widget.gameState.hatchFromNursery(widget.figurine!);
      }
      unawaited(HapticFeedback.mediumImpact());
      setState(() => _hatched = true);
      return;
    }
    setState(() {
      _stage += 1;
      _taps = 0;
      _tapTimes.clear();
    });
    _playPreview();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          _hatched
              ? widget.isPractice
                  ? 'Test terminé'
                  : 'Bienvenue $_displayName'
              : 'L’œuf réagit',
        ),
        content: GestureDetector(
          onTap: _tap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: _isPulsing ? 1.22 : 1,
                child: Icon(
                  _hatched ? Icons.auto_awesome : Icons.egg_alt_outlined,
                  size: 84,
                  color: _hatched ? Colors.amber : null,
                ),
              ),
              const SizedBox(height: 12),
              if (_hatched) ...[
                Text(
                  _displayName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(_type),
              ] else ...[
                const Text('Observe les pulsations, puis tape en rythme.'),
                const SizedBox(height: 8),
                Text('$_taps / ${_rhythmOffsets[_stage].length} tapotements'),
                if (_feedback != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(_feedback!, textAlign: TextAlign.center),
                ],
                TextButton.icon(
                  onPressed: _playPreview,
                  icon: const Icon(Icons.replay),
                  label: const Text('Revoir le rythme'),
                ),
              ],
            ],
          ),
        ),
        actions: _hatched
            ? [
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onFinished?.call();
                  },
                  child: Text(
                    widget.isPractice
                        ? 'Fermer le test'
                        : 'Faire un câlin à $_displayName',
                  ),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Plus tard'),
                ),
              ],
      );
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

  @override
  Widget build(BuildContext context) {
    final state = widget.gameState;
    final project = state.projectFor('house');
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Niveau ${state.houseLevel} · ${state.alcoveCapacity} alcoves actives',
              ),
              const SizedBox(height: 12),
              _BuildingViabilityCard(gameState: state, buildingId: 'house'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Niveau suivant : ${project.currentLevel}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ajoute des alcôves : ${state.alcoveCapacity} → ${housingConfig.alcovesForHouseLevel(project.currentLevel)}.',
                      ),
                      const SizedBox(height: 12),
                      if (project.isInProgress)
                        Text('Travaux : ${_countdownLabel(project.endsAt!)}')
                      else if (project.state ==
                          ConstructionProjectState.maxLevel)
                        const Text('Niveau maximum atteint.')
                      else ...[
                        ...project.requirements.entries.map(
                          (entry) => _ConstructionMaterialProgress(
                            resource: entry.key,
                            deposited:
                                project.depositedMaterials[entry.key] ?? 0,
                            required: entry.value,
                            enabled: true,
                            onDeposit: (amount) => state.depositProjectMaterial(
                              'house',
                              entry.key,
                              amount,
                            ),
                            onWithdraw: () => state.withdrawProjectMaterial(
                              'house',
                              entry.key,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: project.isReady
                              ? () => state.startConstructionProject('house')
                              : null,
                          icon: const Icon(Icons.construction_outlined),
                          label: const Text('Commencer les travaux'),
                        ),
                      ],
                    ],
                  ),
                ),
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
          shadows: <Shadow>[Shadow(color: Colors.white, blurRadius: 10)],
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

class _PtipoteDashboardCard extends StatelessWidget {
  const _PtipoteDashboardCard({
    required this.figurine,
    required this.hunger,
    required this.rest,
    required this.energy,
    required this.activity,
    required this.countdown,
    required this.onRename,
  });

  final PtipoteFigurine figurine;
  final int hunger;
  final int rest;
  final int energy;
  final String activity;
  final String countdown;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final xpRequired = math.max(1, figurine.xpRequiredForNextLevel);
    final xpProgress = (figurine.xpValue / xpRequired).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 132,
                  child: PtipoteImage(
                    type: figurine.type,
                    species: figurine.species,
                    height: 132,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _PtipoteIdentityField(
                        label: 'Espèce',
                        value: figurine.species,
                      ),
                      const SizedBox(height: 8),
                      _PtipoteIdentityField(
                        label: 'Type',
                        value: figurine.type,
                      ),
                      const SizedBox(height: 8),
                      _PtipoteIdentityField(
                        label: 'Surnom',
                        value: figurine.displayName,
                        trailing: IconButton(
                          tooltip: 'Modifier le surnom',
                          onPressed: figurine.canRename ? onRename : null,
                          icon: const Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PtipoteIdentityField(
              label: 'Éleveur',
              value: figurine.ownerName,
            ),
            const SizedBox(height: 14),
            Text(
              'Niveau ${figurine.levelValue}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: xpProgress,
                minHeight: 11,
                backgroundColor: const Color(0xFFE8D9BD),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${figurine.xpValue} / $xpRequired XP',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Divider(height: 28),
            Row(
              children: <Widget>[
                const Icon(Icons.pets_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (countdown.isNotEmpty)
                  Text(
                    countdown,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _PtipoteStatusChip(
                    icon: Icons.restaurant_outlined, label: 'Faim $hunger'),
                _PtipoteStatusChip(
                    icon: Icons.bedtime_outlined, label: 'Sommeil $rest'),
                _PtipoteStatusChip(
                    icon: Icons.bolt_outlined, label: 'Énergie $energy'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PtipoteIdentityField extends StatelessWidget {
  const _PtipoteIdentityField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0D1B5)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class _PtipoteStatusChip extends StatelessWidget {
  const _PtipoteStatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF4),
          border: Border.all(color: const Color(0xFFE0D1B5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _BatteryChestDashboardCard extends StatelessWidget {
  const _BatteryChestDashboardCard({required this.gameState});
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final nextCost = gameState.protectedBatteryChestNextUpgradeCost;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(children: <Widget>[
                    Icon(Icons.lock_outline),
                    SizedBox(width: 8),
                    Text('Coffre à Bio-batteries',
                        style: TextStyle(fontWeight: FontWeight.w900))
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      'Protégées : ${gameState.protectedBioBatteryCount}/${gameState.protectedBatteryChestCapacity} · Exposées : ${gameState.exposedBioBatteryCount} · Total : ${gameState.bioBatteries}'),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (gameState.protectedBioBatteryCount /
                              math.max(
                                1,
                                gameState.protectedBatteryChestCapacity,
                              ))
                          .clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: const Color(0xFFE8D9BD),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Remplissage du coffre protégé',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                      'Niveau ${gameState.protectedBatteryChestLevel}/${campHeartConfig.communityProjects.protectedBatteryUpgradeMaxLevel} · +${campHeartConfig.communityProjects.protectedBatteryCapacityPerUpgrade} par amélioration.'),
                  if (gameState.energyCoreStorageSlots > 0) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                        'Cœurs d’énergie : ${gameState.storedEnergyCores}/${gameState.energyCoreStorageSlots}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: List<Widget>.generate(
                          gameState.energyCoreStorageSlots, (index) {
                        final filled = index < gameState.storedEnergyCores;
                        return OutlinedButton.icon(
                          onPressed: !filled
                              ? null
                              : () => showModalBottomSheet<void>(
                                    context: context,
                                    builder: (sheetContext) => SafeArea(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: <Widget>[
                                            const Icon(
                                              Icons
                                                  .battery_charging_full_outlined,
                                              size: 42,
                                              color: Color(0xFF2878C9),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'Cœur d’énergie scellé',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Contient 300 Bio-batteries. Il ne peut être descellé que lorsque le stock est à 699 ou moins.',
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 14),
                                            FilledButton.icon(
                                              onPressed: () {
                                                final result = gameState
                                                    .unsealStoredEnergyCore();
                                                Navigator.of(sheetContext)
                                                    .pop();
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(result.message),
                                                ));
                                              },
                                              icon: const Icon(
                                                  Icons.lock_open_outlined),
                                              label: const Text('Desceller'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                          icon: Icon(filled
                              ? Icons.battery_full_outlined
                              : Icons.add_box_outlined),
                          label:
                              Text(filled ? 'Desceller' : 'Emplacement libre'),
                        );
                      }),
                    ),
                    if (gameState.availableEnergyCoreStorageSlots > 0)
                      TextButton.icon(
                        onPressed: () => ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                                content:
                                    Text(gameState.storeEnergyCore().message))),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Ranger un Cœur d’énergie'),
                      ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: nextCost == null
                        ? null
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  gameState
                                      .upgradeProtectedBatteryChest()
                                      .message,
                                ),
                              ),
                            ),
                    child: Text(
                      nextCost == null
                          ? 'Niveau maximal'
                          : 'Améliorer ($nextCost Minéral)',
                    ),
                  ),
                ])));
  }
}

class _MaisonUtilityButtons extends StatelessWidget {
  const _MaisonUtilityButtons({
    required this.unreadCount,
    required this.onInventory,
    required this.onMessages,
    required this.onDashboard,
    required this.onBatteryChest,
  });

  final int unreadCount;
  final VoidCallback onInventory;
  final VoidCallback onMessages;
  final VoidCallback onDashboard;
  final VoidCallback onBatteryChest;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _RoundUtilityButton(
            icon: Icons.dashboard_outlined,
            tooltip: 'Tableau des P’TIPOTES',
            onTap: onDashboard,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RoundUtilityButton(
                icon: Icons.lock_outline,
                tooltip: 'Coffre à Bio-batteries',
                onTap: onBatteryChest,
              ),
              const SizedBox(height: 10),
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
          child: SizedBox(width: 48, height: 48, child: Icon(icon)),
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
                colors: <Color>[Color(0x33765A2C), Color(0x66563D1E)],
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
        .clamp(8.0, math.max(8.0, constraints.maxHeight - bubbleHeight - 8))
        .toDouble();
    final preferredLeft =
        placement.left + spriteSize / 2 - bubbleWidth / 2 + offset.dx;
    final bubbleLeft = preferredLeft
        .clamp(8.0, math.max(8.0, constraints.maxWidth - bubbleWidth - 8))
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
    unawaited(
      _figurineService.cacheMyFigurineImagePath(
        figurine: widget.figurine,
        imagePath: url,
      ),
    );
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
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
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
                        label: 'Enveloppe',
                        value: figurine.envelopeLabel,
                      ),
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
                      _InfoLine(label: 'Bonheur', value: moodLabel),
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
                        children: PtipoteAutoAssignmentPreference.values.map((
                          preference,
                        ) {
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
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
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

class Zone0InventorySheet extends StatefulWidget {
  const Zone0InventorySheet({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  State<Zone0InventorySheet> createState() => _Zone0InventorySheetState();
}

class _Zone0InventorySheetState extends State<Zone0InventorySheet> {
  final FigurineService _figurineService = FigurineService();

  Future<void> _selectConsumableTarget(CraftRecipe recipe) async {
    final figurines = await _figurineService.watchMyFigurines().first;
    final available = figurines
        .where((figurine) => !widget.gameState.isOnMission(figurine.id))
        .toList();
    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun P’TIPOTE disponible.')),
      );
      return;
    }
    final target = await showModalBottomSheet<PtipoteFigurine>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Donner ${recipe.resultItem}',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text('Choisis un P’TIPOTE compatible.'),
            const SizedBox(height: 12),
            ...available.map(
              (figurine) => ListTile(
                leading: const Icon(Icons.pets_outlined),
                title: Text(figurine.displayName),
                subtitle: Text(
                  'Vitalité ${widget.gameState.vitalityFor(figurine)}/${ptipoteStatsConfig.maxVitality} · faim ${widget.gameState.hungerFor(figurine)}',
                ),
                onTap: () => Navigator.of(sheetContext).pop(figurine),
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final result = widget.gameState.consumeConsumable(target, recipe);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.gameState,
      builder: (context, _) {
        final stacks = widget.gameState.inventory;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: <Widget>[
              Text(
                'Inventaire global',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Stock ${widget.gameState.inventoryUsedAmount}/${widget.gameState.globalStockCapacity} · ${stacks.length}/${widget.gameState.inventorySlotLimit} slots',
              ),
              const SizedBox(height: 12),
              _FirebaseSyncStatus(gameState: widget.gameState),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: List<Widget>.generate(
                  widget.gameState.inventorySlotLimit,
                  (index) {
                    final stack = index < stacks.length ? stacks[index] : null;
                    final recipe = stack == null
                        ? null
                        : widget.gameState.consumableRecipeForItem(
                            stack.resource,
                          );
                    return _InventorySlot(
                      stack: stack,
                      onTap: recipe == null
                          ? null
                          : () => unawaited(_selectConsumableTarget(recipe)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
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
  const _InventorySlot({required this.stack, this.onTap});

  final Zone0InventoryStack? stack;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = stack != null;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
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
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.32),
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
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.28),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
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
    'Boisson tonique' => Icons.local_drink_outlined,
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
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
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
  const MissionReportsSheet({
    super.key,
    required this.gameState,
    required this.mailbox,
  });

  final Zone0GameState gameState;
  final Zone0MessageMailbox mailbox;

  @override
  Widget build(BuildContext context) {
    final reports = gameState.reports
        .where((report) => report.mailbox == mailbox)
        .toList()
        .reversed
        .toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: <Widget>[
          Text(
            _title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (reports.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => gameState.deleteReports(mailbox: mailbox),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Tout supprimer'),
              ),
            ),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            _SheetEmptyState(text: _emptyLabel)
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
                          _subjectFor(report),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text('Concerné : ${_concernedFor(report)}'),
                        const SizedBox(height: 2),
                        Text(_summaryFor(report)),
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

  String get _title => switch (mailbox) {
        Zone0MessageMailbox.companions => 'Messages P’TIPOTE & P’TIBUG',
        Zone0MessageMailbox.kernel => 'Messages Kernel',
        Zone0MessageMailbox.fablab => 'Messages Fablab',
      };

  String get _emptyLabel => switch (mailbox) {
        Zone0MessageMailbox.companions => 'Aucun message P’TIPOTE ou P’TIBUG.',
        Zone0MessageMailbox.kernel => 'Aucun message du Kernel.',
        Zone0MessageMailbox.fablab => 'Aucune fin de craft.',
      };

  String _subjectFor(PtipoteMissionReport report) {
    if (report.subject?.trim().isNotEmpty ?? false) return report.subject!;
    if (report.sourceBuildingId == 'securityTower') return 'Retour de ronde';
    if (report.biomeLabel != 'Zone 0') return 'Retour de mission Lisière';
    return 'Message du refuge';
  }

  String _concernedFor(PtipoteMissionReport report) {
    if (report.concerned?.trim().isNotEmpty ?? false) return report.concerned!;
    return report.figurineName;
  }

  String _summaryFor(PtipoteMissionReport report) {
    if (report.summary?.trim().isNotEmpty ?? false) return report.summary!;
    if (report.finalStateLabel.isNotEmpty) return report.finalStateLabel;
    return report.incidentLabel == 'aucun'
        ? 'Activité terminée.'
        : 'Événement : ${report.incidentLabel}.';
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
  const LisierePage({
    super.key,
    required this.gameState,
    required this.campHeartState,
  });

  final Zone0GameState gameState;
  final CampHeartState campHeartState;

  @override
  State<LisierePage> createState() => _LisierePageState();
}

class _LisierePageState extends State<LisierePage> {
  final _figurineService = FigurineService();
  ForageBiome _biome = ForageBiome.plaineRiche;
  ForageDuration _duration = ForageDuration.oneHour;
  ForageIntensity _intensity = ForageIntensity.normal;
  ForageMissionType _missionType = ForageMissionType.harvest;
  final Set<String> _selectedFigurineIds = <String>{};

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_onGameStateChanged);
    widget.campHeartState.addListener(_onGameStateChanged);
    widget.gameState.resolveDueForageMissions();
    widget.gameState.resolveDueTowerMissions();
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_onGameStateChanged);
    widget.campHeartState.removeListener(_onGameStateChanged);
    super.dispose();
  }

  void _onGameStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lisière proche'),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              const Tab(text: 'Missions'),
              const Tab(text: 'P’TIBUG'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
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
                        (figurine) =>
                            _selectedFigurineIds.contains(figurine.id),
                      )
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
                              widget.gameState.inventoryFreeCapacityFor(
                                groupEstimate.rewards,
                              ),
                        );
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _ForageChoiceCard(
                        title: 'Type de mission',
                        child: Wrap(
                          spacing: 8,
                          children: ForageMissionType.values.map((type) {
                            final config =
                                lisiereForageConfig.missionTypes[type]!;
                            return ChoiceChip(
                              label: Text(config.label),
                              selected: _missionType == type,
                              onSelected: (_) =>
                                  setState(() => _missionType = type),
                            );
                          }).toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _missionType == ForageMissionType.research
                              ? 'Explorer le biome pour découvrir des Cellules de données. Aucun Organique ni Minéral n’est récolté.'
                              : 'Prélever les ressources naturelles du biome.',
                        ),
                      ),
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
                      const SizedBox(height: 12),
                      _BiomeBiomassCard(
                        gameState: widget.gameState,
                        biome: _biome,
                      ),
                      _ForageChoiceCard(
                        title: 'P’TIPOTE',
                        child: figurines.isEmpty
                            ? const Text('Aucun P’TIPOTE disponible.')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: figurines.map((figurine) {
                                  final vitality = widget.gameState.vitalityFor(
                                    figurine,
                                  );
                                  final onMission =
                                      widget.gameState.isOnMission(figurine.id);
                                  final resting = widget.gameState.isResting(
                                    figurine,
                                  );
                                  final busy = widget.gameState.isBusy(
                                    figurine,
                                  );
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
                                    selected: _selectedFigurineIds.contains(
                                      figurine.id,
                                    ),
                                    onSelected: busy || tooTired
                                        ? null
                                        : (_) => setState(() {
                                              if (_selectedFigurineIds.contains(
                                                figurine.id,
                                              )) {
                                                _selectedFigurineIds.remove(
                                                  figurine.id,
                                                );
                                              } else {
                                                _selectedFigurineIds.add(
                                                  figurine.id,
                                                );
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
                            final config =
                                lisiereForageConfig.durations[duration]!;
                            final real = config.realDuration(
                              lisiereForageConfig.forageTimeScale,
                            );
                            return ChoiceChip(
                              label: Text(
                                '${config.label} (${real.inMinutes} min test)',
                              ),
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
                          children: ForageIntensity.values
                              .where((intensity) =>
                                  intensity != ForageIntensity.doux)
                              .map((intensity) {
                            final config =
                                lisiereForageConfig.intensities[intensity]!;
                            return ChoiceChip(
                              label: Text(
                                '${config.label} · vitesse x${(1 / config.timeMultiplier).toStringAsFixed(2)}',
                              ),
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
                          gameState: widget.gameState,
                          biome: _biome,
                          duration: _duration,
                          intensity: _intensity,
                          missionType: _missionType,
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
                              ? 'Lancer ${_missionType == ForageMissionType.research ? 'la recherche' : 'la récolte'}'
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
              ),
            ),
            _PTibugTerritoryTab(
              gameState: widget.gameState,
              campHeartState: widget.campHeartState,
            ),
          ],
        ),
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
    final typeConfig = lisiereForageConfig.missionTypes[_missionType]!;
    if (_missionType == ForageMissionType.research) {
      final waste = (typeConfig.wastePerHour *
              duration.theoreticalHours *
              intensity.rewardMultiplier)
          .round();
      return waste <= 0
          ? const <String, int>{}
          : <String, int>{'Déchets': waste};
    }
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
    final wasteReward = widget.gameState.estimatedBiomeWasteReward(
      biome: _biome,
      theoreticalHours: duration.theoreticalHours,
      rewardMultiplier: intensity.rewardMultiplier,
    );
    if (wasteReward > 0) {
      rewards['Déchets'] = wasteReward;
    }
    return widget.gameState.biomassAdjustedNaturalRewards(_biome, rewards);
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
      type: _missionType,
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

class _PTibugTerritoryTab extends StatefulWidget {
  const _PTibugTerritoryTab({
    required this.gameState,
    required this.campHeartState,
  });

  final Zone0GameState gameState;
  final CampHeartState campHeartState;

  @override
  State<_PTibugTerritoryTab> createState() => _PTibugTerritoryTabState();
}

class _PTibugTerritoryTabState extends State<_PTibugTerritoryTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _autoScrollForDrag(DragUpdateDetails details) {
    if (!_scrollController.hasClients) return;
    final height = MediaQuery.sizeOf(context).height;
    const edge = 110.0;
    final y = details.globalPosition.dy;
    final direction = y < edge ? -1.0 : (y > height - edge ? 1.0 : 0.0);
    if (direction == 0) return;
    final position = _scrollController.position;
    final next = (position.pixels + direction * 26).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final gameState = widget.gameState;
    final campHeartState = widget.campHeartState;
    final biomes = ForageBiome.values.where(gameState.isBiomeUnlocked).toList();
    final plaine =
        biomes.where((biome) => biome == ForageBiome.plaineRiche).firstOrNull;
    final otherBiomes =
        biomes.where((biome) => biome != ForageBiome.plaineRiche);
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Territoire P’TIBUG',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const SizedBox(height: 4),
        const Text(
            'Gérez les affectations, les stocks locaux et chaque production individuelle.'),
        const SizedBox(height: 12),
        if (plaine != null)
          _PTibugTerritoryBiomeCard(
            gameState: gameState,
            biome: plaine,
            building: gameState.plaineNurseryTerritory,
            campHeartState: campHeartState,
            onDragUpdate: _autoScrollForDrag,
          ),
        ...otherBiomes.map(
          (biome) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _PTibugTerritoryBiomeCard(
              gameState: gameState,
              biome: biome,
              building:
                  gameState.territoryBuildingForId('refuge-${biome.name}'),
              campHeartState: campHeartState,
              onDragUpdate: _autoScrollForDrag,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text('P’TIBUG inactifs',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 6),
        DragTarget<PTibug>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) => _message(
            context,
            gameState.setPTibugInactive(details.data).message,
          ),
          builder: (context, candidates, _) {
            final inactive = gameState.pTibugs
                .where((bug) => bug.assignedBuildingId == null)
                .toList(growable: false);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: candidates.isEmpty
                    ? null
                    : Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .08),
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: .35)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: inactive.isEmpty
                    ? const Text(
                        'Aucun P’TIBUG inactif. Glissez un P’TIBUG ici pour le désaffecter.')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: inactive
                            .map((bug) => _PTibugTerritoryBugCard(
                                  gameState: gameState,
                                  bug: bug,
                                  building: null,
                                  onDragUpdate: _autoScrollForDrag,
                                ))
                            .toList(),
                      ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _PTibugTerritoryBiomeCard extends StatelessWidget {
  const _PTibugTerritoryBiomeCard({
    required this.gameState,
    required this.biome,
    required this.building,
    required this.campHeartState,
    this.onDragUpdate,
  });

  final Zone0GameState gameState;
  final ForageBiome biome;
  final PTibugTerritoryBuilding? building;
  final CampHeartState campHeartState;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final config = lisiereForageConfig.biomes[biome]!;
    final biomass = gameState.biomassFor(biome);
    final visual = gameState.biomassVisualStateFor(biome);
    final activeBuilding = building?.isBuilt == true ? building : null;
    if (activeBuilding == null) {
      if (biome == ForageBiome.plaineRiche) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(config.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 19)),
                  Text(
                      '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.biomeSecurity[biome]?.localSecurity ?? 0}%'),
                  const SizedBox(height: 8),
                  const Text(
                      'La Plaine accueille uniquement la Nurserie principale.'),
                ]),
          ),
        );
      }
      final targetId = gameState.refugeTerritoryId(biome);
      final project = gameState.projectFor(targetId);
      final requirements = project.requirements;
      final batteries = gameState.projectBioBatteryRequirement(targetId);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(config.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 19)),
              Text(
                  '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.biomeSecurity[biome]?.localSecurity ?? 0}%'),
              if (gameState.activeGlobalWeatherEvent case final weather?)
                Text(
                  weather.type == TowerWeatherType.calm
                      ? '🌤️ Temps calme · ce biome ne subit aucun malus.'
                      : weather.isBiomeAffected(biome)
                          ? '${switch (weather.type) {
                              TowerWeatherType.toxicCloud => '☁️ Nuage toxique',
                              TowerWeatherType.heatWave => '☀️ Forte chaleur',
                              TowerWeatherType.heavyRain => '🌧️ Pluie intense',
                              TowerWeatherType.calm => '🌤️ Temps calme'
                            }} · ${switch (weather.intensity) {
                              GlobalWeatherIntensity.calm => 'Calme',
                              GlobalWeatherIntensity.moderate => 'Modérée',
                              GlobalWeatherIntensity.strong => 'Forte',
                              GlobalWeatherIntensity.severe => 'Sévère'
                            }} · impact ${weather.impactFor(biome).localImpactLevel == 'high' ? 'élevé' : weather.impactFor(biome).localImpactLevel == 'medium' ? 'moyen' : 'faible'}'
                          : 'Météo globale active · ce biome n’est pas touché.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 10),
              const SizedBox(height: 10),
              const Text('🏕️ Refuge P’TIBUG',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text(project.isInProgress
                  ? 'En construction · fin ${project.endsAt == null ? 'prochainement' : _countdownLabel(project.endsAt!)}'
                  : 'Non construit · capacité future : ${pTibugConfig.territory.refugeCapacityForLevel(1)} P’TIBUG'),
              const SizedBox(height: 6),
              const Text(
                  'Construisez un Refuge pour accueillir des P’TIBUG et produire les ressources locales de ce biome.'),
              const SizedBox(height: 8),
              Text(
                  'Organique : ${project.depositedMaterials['Organique'] ?? 0} / ${requirements['Organique'] ?? 0}'),
              Text(
                  'Minéral : ${project.depositedMaterials['Minéral'] ?? 0} / ${requirements['Minéral'] ?? 0}'),
              Text(
                  'Bio-batteries : ${project.depositedBioBatteries} / $batteries'),
              const SizedBox(height: 8),
              if (!project.isInProgress)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ...(<String>['Organique', 'Minéral']
                        .map((resource) => OutlinedButton(
                              onPressed: (project.missingFor(resource) <= 0 ||
                                      gameState.resourceAmount(resource) <= 0)
                                  ? null
                                  : () => _message(
                                      context,
                                      gameState
                                          .depositProjectMaterial(
                                              targetId, resource, 1)
                                          .message),
                              child: Text('+1 $resource'),
                            ))),
                    OutlinedButton(
                      onPressed: project.depositedBioBatteries >= batteries ||
                              gameState.bioBatteries <= 0
                          ? null
                          : () => _message(
                              context,
                              gameState
                                  .depositProjectBioBattery(targetId)
                                  .message),
                      child: const Text('+1 Bio-batterie'),
                    ),
                    FilledButton.icon(
                      onPressed: project.isReady &&
                              project.depositedBioBatteries >= batteries
                          ? () => _message(
                              context,
                              gameState
                                  .startConstructionProject(targetId)
                                  .message)
                          : null,
                      icon: const Icon(Icons.construction_outlined),
                      label: const Text('Commencer les travaux'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    final residents = gameState.pTibugsForTerritory(activeBuilding.id);
    final weather = gameState.activeGlobalWeatherEvent;
    final isWeatherAffected = weather != null && weather.isBiomeAffected(biome);
    final exposedPTibugs = residents
        .where((bug) => gameState.pTibugWeatherMalusPercentFor(bug) > 0)
        .length;
    final weatherLabel = weather == null
        ? null
        : switch (weather.type) {
            TowerWeatherType.calm => '🌤️ Temps calme',
            TowerWeatherType.toxicCloud => '☁️ Nuage toxique',
            TowerWeatherType.heatWave => '☀️ Forte chaleur',
            TowerWeatherType.heavyRain => '🌧️ Pluie intense',
          };
    final capacity = gameState.pTibugTerritoryCapacity(activeBuilding);
    final consumption =
        gameState.pTibugTerritoryDailyConsumption(activeBuilding);
    final production = <String, int>{};
    for (final bug in residents) {
      gameState.pTibugProductionFor(bug).forEach(
            (resource, amount) =>
                production[resource] = (production[resource] ?? 0) + amount,
          );
    }
    return DragTarget<PTibug>(
      onWillAcceptWithDetails: (details) =>
          residents.length < capacity ||
          details.data.assignedBuildingId == activeBuilding.id,
      onAcceptWithDetails: (details) => _message(
        context,
        gameState
            .assignPTibugToTerritory(details.data, activeBuilding.id)
            .message,
      ),
      builder: (context, candidates, _) => Card(
        color: candidates.isEmpty
            ? null
            : Theme.of(context).colorScheme.primary.withValues(alpha: .06),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                      child: Text(config.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 19))),
                  Text(
                      activeBuilding.kind == PTibugTerritoryKind.nursery
                          ? 'Nurserie'
                          : 'Refuge',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              Text(
                  '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.biomeSecurity[biome]?.localSecurity ?? 0}%'),
              if (weatherLabel != null)
                Text(
                  isWeatherAffected
                      ? '$weatherLabel · malus local P’TIBUG jusqu’à -${residents.isEmpty ? 0 : residents.map(gameState.pTibugWeatherMalusPercentFor).reduce(math.max)}% · $exposedPTibugs/${residents.length} non protégé(s)'
                      : '$weatherLabel · ce biome n’est pas touché.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 8),
              _BuildingViabilityCard(
                gameState: gameState,
                buildingId: activeBuilding.id,
              ),
              const SizedBox(height: 10),
              Text(
                  'Niveau ${activeBuilding.level} · ${residents.length}/$capacity P’TIBUG actifs',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (gameState.isTerritoryUnderConstruction(activeBuilding))
                const Text(
                    'Travaux en cours : production et consommations suspendues.',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Color(0xff8A3B24))),
              Text(
                  'Production locale : ${production.isEmpty ? 'Aucune' : production.entries.map((entry) => '${entry.value} ${entry.key}').join(' · ')}'),
              const SizedBox(height: 8),
              _PTibugTerritoryStockSummary(
                  building: activeBuilding, consumption: consumption),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showTransferSheet(context, activeBuilding),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Alimenter'),
                  ),
                  FilledButton.icon(
                    onPressed: gameState.bioBatteries <= 0
                        ? null
                        : () => _message(
                            context,
                            gameState
                                .openBioBatteryForPTibugTerritory(
                                    activeBuilding.id)
                                .message),
                    icon: const Icon(Icons.battery_charging_full_outlined),
                    label: const Text('Ouvrir une Bio-batterie'),
                  ),
                  if (activeBuilding.kind == PTibugTerritoryKind.nursery)
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PTibugNurseryPage(
                          gameState: gameState,
                          campHeartLevel: campHeartState.campHeartLevel,
                          campHeartState: campHeartState,
                        ),
                      )),
                      icon: const Icon(Icons.home_work_outlined),
                      label: const Text('Entrer dans la Nurserie'),
                    ),
                  if (activeBuilding.kind == PTibugTerritoryKind.refuge)
                    OutlinedButton.icon(
                      onPressed: activeBuilding.level >=
                              pTibugConfig.territory.refugeMaximumLevel
                          ? null
                          : () =>
                              _showRefugeUpgradeSheet(context, activeBuilding),
                      icon: const Icon(Icons.upgrade_outlined),
                      label: const Text('Améliorer'),
                    ),
                ],
              ),
              if (residents.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: residents
                      .map((bug) => _PTibugTerritoryBugCard(
                          gameState: gameState,
                          bug: bug,
                          building: activeBuilding,
                          onDragUpdate: onDragUpdate))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTransferSheet(
          BuildContext context, PTibugTerritoryBuilding building) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Alimenter les stocks locaux',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...(<String>['Organique', 'Minéral'].map(
                  (resource) => Wrap(
                    spacing: 8,
                    children: const <int>[1, 5, 10]
                        .map((amount) => OutlinedButton(
                              onPressed:
                                  gameState.resourceAmount(resource) < amount
                                      ? null
                                      : () {
                                          final result = gameState
                                              .transferResourcesToPTibugTerritory(
                                            territoryId: building.id,
                                            resources: <String, int>{
                                              resource: amount
                                            },
                                          );
                                          Navigator.of(sheetContext).pop();
                                          _message(context, result.message);
                                        },
                              child: Text('+$amount $resource'),
                            ))
                        .toList(),
                  ),
                )),
              ],
            ),
          ),
        ),
      );

  Future<void> _showRefugeUpgradeSheet(
    BuildContext context,
    PTibugTerritoryBuilding building,
  ) async {
    final project = gameState.projectFor(building.id);
    final batteries = gameState.projectBioBatteryRequirement(building.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Améliorer le Refuge · niveau ${project.targetLevel}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...(<String>['Organique', 'Minéral'].map((resource) => Text(
                    '$resource : ${project.depositedMaterials[resource] ?? 0} / ${project.requirements[resource] ?? 0}'))),
                Text(
                    'Bio-batteries : ${project.depositedBioBatteries} / $batteries'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: <Widget>[
                  ...(<String>['Organique', 'Minéral'].map((resource) =>
                      OutlinedButton(
                          onPressed: project.missingFor(resource) <= 0 ||
                                  gameState.resourceAmount(resource) <= 0
                              ? null
                              : () {
                                  _message(
                                      context,
                                      gameState
                                          .depositProjectMaterial(
                                              building.id, resource, 1)
                                          .message);
                                  Navigator.of(sheetContext).pop();
                                },
                          child: Text('+1 $resource')))),
                  OutlinedButton(
                      onPressed: project.depositedBioBatteries >= batteries ||
                              gameState.bioBatteries <= 0
                          ? null
                          : () {
                              _message(
                                  context,
                                  gameState
                                      .depositProjectBioBattery(building.id)
                                      .message);
                              Navigator.of(sheetContext).pop();
                            },
                      child: const Text('+1 Bio-batterie')),
                ]),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: project.isReady &&
                            project.depositedBioBatteries >= batteries
                        ? () {
                            final result =
                                gameState.startConstructionProject(building.id);
                            Navigator.of(sheetContext).pop();
                            _message(context, result.message);
                          }
                        : null,
                    child: const Text('Commencer les travaux')),
              ]),
        ),
      ),
    );
  }

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _BuildingViabilityCard extends StatelessWidget {
  const _BuildingViabilityCard({
    required this.gameState,
    required this.buildingId,
  });

  final Zone0GameState gameState;
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    final state = gameState.viabilityForBuilding(buildingId);
    final config = towerOperationsConfig.buildingViability;
    final disabled = state.isDisabled;
    final degraded = state.isDegraded(config.degradedThreshold);
    final status = disabled
        ? 'Hors service'
        : degraded
            ? 'Dégradé'
            : 'Normal';
    final color = disabled
        ? const Color(0xffA1392C)
        : degraded
            ? const Color(0xff8A6B17)
            : const Color(0xff54724A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Viabilité : ${state.current}/${state.maximum}% · $status',
                style: TextStyle(fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 5),
            LinearProgressIndicator(
                value: state.current / state.maximum, color: color),
            if (degraded) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                  'Fonctionnement dégradé : temps et coûts de craft +${config.degradedCraftTimePercent} %.')
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
              if (disabled)
                FilledButton(
                  onPressed: () => _showRestartDialog(context),
                  child: const Text('Remettre en marche'),
                ),
              if (state.current < state.maximum && !disabled)
                OutlinedButton(
                  onPressed: () => _showMessage(
                      context, gameState.repairBuilding(buildingId).message),
                  child: const Text('Réparer'),
                ),
              OutlinedButton(
                onPressed: () => _showInstallations(context),
                child: Text(
                    'Installations ${state.installedStructuralProtections.length}/${gameState.structuralProtectionSlotsFor(buildingId)}'),
              ),
            ]),
          ]),
    );
  }

  void _showRestartDialog(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bâtiment hors service'),
          content: Text(
              'La remise en marche restaure ${towerOperationsConfig.buildingViability.restartViability}% de Viabilité. Le diagnostic prototype valide trois connexions, sans consommer de ressources.'),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fermer')),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showMessage(context,
                    gameState.restartBuildingByMiniGame(buildingId).message);
              },
              child: const Text('Mini-jeu : valider les connexions'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showMessage(context,
                    gameState.restartBuildingByPayment(buildingId).message);
              },
              child: const Text('Payer la remise en marche'),
            ),
          ],
        ),
      );

  void _showInstallations(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text('Installations structurelles',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 8),
            const Text(
                'Chaque niveau du bâtiment ouvre un emplacement. Les réductions de dégâts sont plafonnées à 70 %.'),
            _StructuralInstallationSlots(
              gameState: gameState,
              buildingId: buildingId,
              onMessage: (message) => _showMessage(context, message),
            ),
          ],
        ),
      );

  void _showMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _StructuralInstallationSlots extends StatelessWidget {
  const _StructuralInstallationSlots(
      {required this.gameState,
      required this.buildingId,
      required this.onMessage});
  final Zone0GameState gameState;
  final String buildingId;
  final ValueChanged<String> onMessage;

  String _label(StructuralProtectionType type) => switch (type) {
        StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
        StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
        StructuralProtectionType.filtration => 'Installation filtrante',
      };

  @override
  Widget build(BuildContext context) {
    final state = gameState.viabilityForBuilding(buildingId);
    final slots = gameState.structuralProtectionSlotsFor(buildingId);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.25,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10),
      itemCount: slots,
      itemBuilder: (context, index) {
        final installed = index < state.installedStructuralProtections.length
            ? state.installedStructuralProtections[index]
            : null;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (installed != null) {
              onMessage(gameState
                  .removeStructuralProtection(buildingId, installed)
                  .message);
              return;
            }
            final type = await showModalBottomSheet<StructuralProtectionType>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                  child: ListView(
                      shrinkWrap: true,
                      children: StructuralProtectionType.values
                          .map((type) => ListTile(
                                enabled:
                                    gameState.resourceAmount(_label(type)) > 0,
                                title: Text(_label(type)),
                                subtitle: Text(
                                    'Stock : ${gameState.resourceAmount(_label(type))}'),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: () => Navigator.pop(context, type),
                              ))
                          .toList())),
            );
            if (type != null)
              onMessage(gameState
                  .installStructuralProtection(buildingId, type)
                  .message);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(14)),
            child: Center(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(installed == null ? '+' : _label(installed),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: installed == null ? 30 : 13)))),
          ),
        );
      },
    );
  }
}

class _PTibugTerritoryStockSummary extends StatelessWidget {
  const _PTibugTerritoryStockSummary(
      {required this.building, required this.consumption});
  final PTibugTerritoryBuilding building;
  final PTibugTerritoryConsumption consumption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
              'Organique : ${building.resourceAmount('Organique')} · -${consumption.organicPerDay}/jour'),
          Text(
              'Minéral : ${building.resourceAmount('Minéral')} · -${consumption.mineralPerDay}/jour'),
          Text(
              'Énergie : ${building.localEnergy} · -${consumption.energyPerDay}/jour'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
              value: (building.localEnergy /
                      math.max(10, consumption.energyPerDay * 2))
                  .clamp(0.0, 1.0)),
        ],
      );
}

bool _hasSmartSensor(PTibug bug) =>
    bug.biologicalTraitId == 'capteurIntelligent' ||
    bug.secondTraitId == 'capteurIntelligent';

class _PTibugTerritoryBugCard extends StatelessWidget {
  const _PTibugTerritoryBugCard(
      {required this.gameState,
      required this.bug,
      required this.building,
      this.onDragUpdate});
  final Zone0GameState gameState;
  final PTibug bug;
  final PTibugTerritoryBuilding? building;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final inactive =
        bug.assignedBuildingId == null || bug.inactiveReason != null;
    final weather = gameState.pTibugWeatherFor(bug);
    final weatherLabel = switch (weather) {
      TowerWeatherType.calm => '🌤️ Temps calme',
      TowerWeatherType.toxicCloud => '☁️ Nuage toxique · Filtreur requis',
      TowerWeatherType.heatWave => '☀️ Forte chaleur · Réflecteur requis',
      TowerWeatherType.heavyRain => '🌧️ Pluie intense · Étanchéité requise',
      null => null,
    };
    final card = Card(
      child: SizedBox(
        width: 170,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Opacity(
            opacity: inactive ? .58 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InkWell(
                  onTap: () => _showDetails(context),
                  child: Row(children: <Widget>[
                    CircleAvatar(
                      child: Icon(_territorySpeciesIcon(bug.species)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(bug.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900))),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(
                    '${pTibugConfig.species[bug.species]!.displayName} · niv. ${bug.level}'),
                Text(inactive ? (bug.inactiveReason ?? 'Inactif') : 'Actif'),
                Text(
                    'Production : ${bug.storedAmount}/${gameState.pTibugCapacityFor(bug)}'),
                if (_hasSmartSensor(bug))
                  Text(
                      'Cellules : ${bug.storedDataCells.length}/${pTibugConfig.territory.dataCellStorageCapacity}'),
                if (weatherLabel != null)
                  Text(weatherLabel,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: bug.storedAmount == 0 &&
                          bug.storedDataCells.isEmpty
                      ? null
                      : () => _message(context,
                          gameState.collectPTibugProductionFor(bug).message),
                  child: const Text('Récolter'),
                ),
                TextButton(
                  onPressed: () => _showAssign(context),
                  child: const Text('Affecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return LongPressDraggable<PTibug>(
      data: bug,
      onDragUpdate: onDragUpdate,
      feedback: Material(
          color: Colors.transparent, child: SizedBox(width: 170, child: card)),
      childWhenDragging: Opacity(opacity: .3, child: card),
      child: card,
    );
  }

  Future<void> _showAssign(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final destinations = gameState.activePTibugTerritories;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                const ListTile(title: Text('Affecter ce P’TIBUG')),
                ...destinations.map((destination) {
                  final current =
                      gameState.pTibugsForTerritory(destination.id).length;
                  final capacity =
                      gameState.pTibugTerritoryCapacity(destination);
                  final available = current < capacity ||
                      bug.assignedBuildingId == destination.id;
                  return ListTile(
                    enabled: available,
                    title: Text(destination.kind == PTibugTerritoryKind.nursery
                        ? 'Nurserie · Plaine'
                        : 'Refuge · ${lisiereForageConfig.biomes[destination.biome]!.label}'),
                    subtitle: Text('$current/$capacity emplacement(s)'),
                    onTap: !available
                        ? null
                        : () {
                            final result = gameState.assignPTibugToTerritory(
                                bug, destination.id);
                            Navigator.of(sheetContext).pop();
                            _message(context, result.message);
                          },
                  );
                }),
                ListTile(
                  title: const Text('P’TIBUG inactifs'),
                  subtitle: const Text('Ne produit ni ne consomme.'),
                  onTap: () {
                    final result = gameState.setPTibugInactive(bug);
                    Navigator.of(sheetContext).pop();
                    _message(context, result.message);
                  },
                ),
              ],
            ),
          );
        },
      );

  Future<void> _showDetails(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) {
          final consumption = gameState.pTibugDailyConsumptionFor(bug);
          return SafeArea(
              child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(bug.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 20)),
                  Text(
                      '${pTibugConfig.species[bug.species]!.displayName} · niveau ${bug.level}'),
                  Text(
                      'Biome : ${lisiereForageConfig.biomes[bug.refugeBiome]!.label}'),
                  Text(
                      'Production : ${gameState.pTibugProductionFor(bug).entries.map((entry) => '${entry.value} ${entry.key}').join(' · ')}'),
                  Text(
                      'Stock matériel : ${bug.storedAmount}/${gameState.pTibugCapacityFor(bug)}'),
                  const SizedBox(height: 8),
                  const Text('Consommation réelle sur 24 h',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Text(
                      'Organique : ${consumption['Organique']!.toStringAsFixed(1)}'),
                  Text(
                      'Minéral : ${consumption['Minéral']!.toStringAsFixed(1)}'),
                  Text(
                      'Énergie : ${consumption['Énergie']!.toStringAsFixed(1)}'),
                  if (_hasSmartSensor(bug))
                    Text(
                        'Cellules : ${bug.storedDataCells.length}/${pTibugConfig.territory.dataCellStorageCapacity}'),
                  Text(
                      'État : ${bug.inactiveReason ?? (bug.assignedBuildingId == null ? 'Inactif' : 'Actif')}'),
                ]),
          ));
        },
      );

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

IconData _territorySpeciesIcon(PTibugSpecies species) => switch (species) {
      PTibugSpecies.scarabe => Icons.shield_outlined,
      PTibugSpecies.hyme => Icons.hive_outlined,
      PTibugSpecies.arac => Icons.hub_outlined,
    };

class _BiomeBuildingsTab extends StatelessWidget {
  const _BiomeBuildingsTab({
    required this.gameState,
    required this.biome,
    required this.campHeartState,
  });
  final Zone0GameState gameState;
  final ForageBiome biome;
  final CampHeartState campHeartState;

  @override
  Widget build(BuildContext context) {
    final campHeartLevel = campHeartState.campHeartLevel;
    final label = lisiereForageConfig.biomes[biome]!.label;
    if (biome != ForageBiome.plaineRiche) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Les bâtiments de $label seront révélés avec les prochains Plans du Kernel.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final built = gameState.plaineNurseryLevel > 0;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Nurserie P’TIBUG',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    built
                        ? 'Construite · niveau ${gameState.plaineNurseryLevel}'
                        : 'Prérequis : Cœur du Camp niveau 2 (niveau actuel : $campHeartLevel).',
                  ),
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
                          campHeartLevel: campHeartLevel,
                          campHeartState: campHeartState,
                          footer: campHeartLevel < 2
                              ? 'Niveau actuel du Cœur : $campHeartLevel / 2.'
                              : 'Les matériaux peuvent être déposés progressivement.',
                        ),
                      ),
                      icon: const Icon(Icons.pets_outlined),
                      label: const Text('Préparer la construction'),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PTibugNurseryPage(
                            gameState: gameState,
                            campHeartLevel: campHeartLevel,
                            campHeartState: campHeartState,
                          ),
                        ),
                      ),
                      child: const Text('Ouvrir la Nurserie'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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

class _BiomeBiomassCard extends StatelessWidget {
  const _BiomeBiomassCard({required this.gameState, required this.biome});

  final Zone0GameState gameState;
  final ForageBiome biome;

  @override
  Widget build(BuildContext context) {
    final biomass = gameState.biomassFor(biome);
    final visual = gameState.biomassVisualStateFor(biome);
    final maximum = lisiereForageConfig.biomass.maximumPercent;
    final cost = gameState.biomassRevitalizeCost(biome);
    final multiplier = gameState.biomassResourceMultiplierFor(biome);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(visual.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Biomasse · ${visual.label}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text('$biomass%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: maximum <= 0 ? 0 : biomass / maximum),
            const SizedBox(height: 8),
            Text(
              'Rendement naturel : x${multiplier.toStringAsFixed(2)} · Production P’TIBUG locale : x${gameState.biomassPTibugMultiplierFor(biome).toStringAsFixed(2)}',
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: biomass >= maximum
                  ? null
                  : () {
                      final result = gameState.revitalizeBiome(biome);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    },
              icon: const Icon(Icons.eco_outlined),
              label: Text(
                'Revigorer · ${cost['Organique']} Organique · ${cost['Minéral']} Minéral',
              ),
            ),
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
    required this.gameState,
    required this.biome,
    required this.duration,
    required this.intensity,
    required this.missionType,
  });

  final ForageGroupEstimate estimate;
  final int selectedCount;
  final Zone0GameState gameState;
  final ForageBiome biome;
  final ForageDuration duration;
  final ForageIntensity intensity;
  final ForageMissionType missionType;

  @override
  Widget build(BuildContext context) {
    final durationConfig = lisiereForageConfig.durations[duration]!;
    final wasteLevel = gameState.wasteLevelFor(biome);
    final wasteMaximum = lisiereForageConfig.wasteLevelMax;
    final wasteMultiplier = gameState.wasteMultiplierFor(biome);
    final wasteHoursPerLevel =
        lisiereForageConfig.biomes[biome]!.wasteHoursPerLevelRegeneration;
    final organicBonus = gameState.organicBonusForBiome(biome);
    final biomass = gameState.biomassFor(biome);
    final biomassState = gameState.biomassVisualStateFor(biome);
    final typeConfig = lisiereForageConfig.missionTypes[missionType]!;
    final cellCount =
        (pTibugConfig.maxCellsForMissionHours(durationConfig.theoreticalHours) *
                typeConfig.maximumCellsMultiplier)
            .ceil();
    final cellChanceLabel = missionType == ForageMissionType.research
        ? '$cellCount tentative${cellCount > 1 ? 's' : ''} de Cellule selon le biome'
        : 'Cellules occasionnelles (${(typeConfig.cellChanceMultiplier * 100).round()} % des chances habituelles)';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Estimation',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text('Groupe : $selectedCount P’TIPOTE(s)'),
            Text('Gain : ${_formatRewards(estimate.rewards)}'),
            Text(
              'Vigueur : ${biomassState.icon} ${biomassState.label} · $biomass%${missionType == ForageMissionType.harvest ? ' · rendement x${gameState.biomassResourceMultiplierFor(biome).toStringAsFixed(2)}' : ''}',
            ),
            Text(
              'Coût de Vigueur estimé : -${gameState.biomassMissionConsumptionFor(intensity, missionType, theoreticalHours: durationConfig.theoreticalHours)}% · après mission ${math.max(0, biomass - gameState.biomassMissionConsumptionFor(intensity, missionType, theoreticalHours: durationConfig.theoreticalHours))}%',
            ),
            Text('Cellules de données : $cellChanceLabel'),
            Text(
              'Déchets du biome : $wasteLevel / $wasteMaximum · '
              'x${wasteMultiplier.toStringAsFixed(2)}',
            ),
            if (wasteHoursPerLevel > 0)
              Text(
                'Remplissage : +1 Déchet / '
                '${wasteHoursPerLevel.toStringAsFixed(wasteHoursPerLevel == wasteHoursPerLevel.roundToDouble() ? 0 : 1)} h',
              ),
            if (organicBonus > 0)
              Text(
                'Biome assaini : +${(organicBonus * 100).round()} % Organique',
                style: const TextStyle(
                  color: Color(0xff4B8E55),
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (wasteLevel <= 0)
              const Text(
                  'Le biome ne contient actuellement aucun Déchet récupérable.')
            else
              const Text(
                  'Déchets récupérables : gain estimé inclus dans la mission.'),
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
            const Text(
              'Missions en cours',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
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
                          '${mission.type == ForageMissionType.research ? '🔎 Recherche' : '🪵 Récolte'} · ${mission.figurineName} · ${biome.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_countdownLabel(mission.endTime)),
                      TextButton.icon(
                        onPressed: () =>
                            _confirmEmergencyReturn(context, mission),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
      campHeartLevel = math.min(
        campHeartLevel + 1,
        campHeartConfig.stages.length,
      );
      levelUpMessage =
          'Le Cœur du Camp grandit. Le camp devient ${currentStage.label}.';
    }

    notifyListeners();
    unawaited(gameState.saveCampHeartToFirebase(toFirebaseData()));
    return levelUpMessage ?? '+$amount Organique investi.';
  }

  void applyFirebaseData(Map<String, dynamic> data) {
    campHeartLevel = _readInt(
      data['campHeartLevel'],
      fallback: campHeartLevel,
    ).clamp(1, campHeartConfig.stages.length);
    vegetalizationXp = _readInt(
      data['vegetalizationXp'],
      fallback: vegetalizationXp,
    );
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
  const _CampHousingTab({
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

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
          Text(
            'Habitation',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Le Cœur organise la communauté. Touchez une statistique pour comprendre son rôle.',
          ),
          const SizedBox(height: 14),
          _HabitationStatCard(
            icon: Icons.groups_outlined,
            title: 'Population',
            value:
                '${gameState.currentPopulation} / ${gameState.populationCapacityForCampHeartLevel(campHeartLevel)}',
            onTap: () => _showStatInfo(
              context,
              'Population',
              'Les habitants arrivent grâce aux missions du Kernel. Le Cœur fixe la capacité générale du refuge.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.home_work_outlined,
            title: 'Logements actuels',
            value: '${gameState.housingUnits}',
            subtitle:
                '${housingConfig.residentsPerHousingUnit} habitants par logement',
            onTap: () => _showStatInfo(
              context,
              'Logements',
              'Chaque logement ajoute ${housingConfig.residentsPerHousingUnit} places habitables.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.meeting_room_outlined,
            title: 'Places de logement',
            value: '${gameState.housingCapacity}',
            subtitle:
                '${gameState.unhousedPopulation} habitant(s) sans logement',
            onTap: () => _showStatInfo(
              context,
              'Places de logement',
              'Les habitants sans logement correspondent à la population moins les places disponibles.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.sentiment_satisfied_alt_outlined,
            title: 'Bien-être',
            value: '${gameState.residentHappiness}%',
            subtitle: 'Moyenne des habitants actifs',
            onTap: () => _showStatInfo(
              context,
              'Bien-être',
              'Le bien-être reflète la stabilité du refuge. Les habitants sans logement appliquent un malus jusqu’à la fin d’un chantier de logement.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.hub_outlined,
            title: 'Activité locale',
            value: '$activity%',
            subtitle: 'Préparée pour le Marché',
            onTap: () => _showStatInfo(
              context,
              'Activité locale',
              'Cette valeur agrégée représentera plus tard la vitalité du refuge et les opportunités du Marché.',
            ),
          ),
          const SizedBox(height: 12),
          if (gameState.residentHouses.isNotEmpty) ...<Widget>[
            Text('Maisons',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...gameState.residentHouses.map((house) => Card(
                  child: ListTile(
                    leading: Icon(house.currentViability == 0
                        ? Icons.home_work_outlined
                        : house.currentViability < 50
                            ? Icons.home_repair_service_outlined
                            : Icons.home_outlined),
                    title: Text(house.displayName),
                    subtitle: Text(
                        '${house.residentIds.length}/${house.capacity} habitant(s) · Viabilité ${house.currentViability}%${house.currentViability < 50 ? ' · bonheur -${housingConfig.houseViabilityDamageHappinessPercent}%' : ''}'),
                    trailing: house.currentViability < house.maximumViability
                        ? OutlinedButton(
                            onPressed: () {
                              final result =
                                  gameState.repairResidentHouse(house.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(result.message)));
                            },
                            child: const Text('Réparer'),
                          )
                        : const Text('Bon état'),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(20),
                        children: <Widget>[
                          Text(
                              '${house.displayName} · protections ${house.installedStructuralProtections.length}/${housingConfig.houseProtectionSlots}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 8),
                          for (final type in StructuralProtectionType.values)
                            ListTile(
                              title: Text(switch (type) {
                                StructuralProtectionType.ventilationTermite =>
                                  'Ventilation Termite',
                                StructuralProtectionType.chloroCanaux =>
                                  'Chloro-canaux',
                                StructuralProtectionType.filtration =>
                                  'Installation filtrante'
                              }),
                              trailing: FilledButton(
                                onPressed: () {
                                  final result = gameState
                                      .installHouseProtection(house.id, type);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(result.message)));
                                },
                                child: const Text('Installer'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 12),
          ],
          if (gameState.residents.isNotEmpty) ...<Widget>[
            Text('Habitants',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...gameState.residents
                .where((resident) => resident.isActive)
                .map((resident) {
              final house = gameState.residentHouseForId(resident.houseId);
              final damaged = house != null && house.currentViability < 50;
              return Card(
                  child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(resident.displayName),
                subtitle: Text(
                    '${house?.displayName ?? 'Sans logement'}${damaged ? ' · Maison endommagée : -${housingConfig.houseViabilityDamageHappinessPercent}%' : ''}'),
                trailing: Text('${gameState.residentHappinessFor(resident)}%',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ));
            }),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Logements',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${gameState.housingUnits} unité(s) · ${gameState.unhousedPopulation} habitant(s) sans logement',
                  ),
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
                        final result = gameState.thankResidentsForHousing(
                          project.projectId,
                        );
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.message)));
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
  const _HabitationStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });
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
            child: Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (subtitle != null) Text(subtitle!),
                    ],
                  ),
                ),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              Tab(text: 'Habitation', icon: Icon(Icons.home_work_outlined)),
              Tab(text: 'Générateur', icon: Icon(Icons.battery_charging_full)),
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
                  _CommunityProjectsCard(
                    gameState: widget.gameState,
                    heartLevel: state.campHeartLevel,
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
              _CampHousingTab(
                gameState: widget.gameState,
                campHeartLevel: state.campHeartLevel,
              ),
              _CampGeneratorView(
                gameState: widget.gameState,
                heartLevel: state.campHeartLevel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityProjectsCard extends StatelessWidget {
  const _CommunityProjectsCard(
      {required this.gameState, required this.heartLevel});

  final Zone0GameState gameState;
  final int heartLevel;

  @override
  Widget build(BuildContext context) {
    final config = campHeartConfig.communityProjects;
    final active = gameState.activeCommunityProject;
    final incident = gameState.lastWeatherStockIncident;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Grands chantiers',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                'Choix : ${gameState.communityProjectChoicesUsed}/${gameState.communityProjectChoiceLimit} · Un chantier actif à la fois.'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Coffre à Bio-batteries'),
              subtitle: Text(
                  '${gameState.protectedBioBatteryCount}/${gameState.protectedBatteryChestCapacity} protégées · ${gameState.exposedBioBatteryCount} exposée(s). Total HUD inchangé : ${gameState.bioBatteries}.'),
            ),
            if (incident != null)
              Text(
                  'Dernière intempérie : ${incident.wasteCreated} Déchet(s) créés, ${incident.batteriesLost} Bio-batterie(s) exposée(s) perdue(s).'),
            const Divider(),
            for (final definition in config.projects)
              _CommunityProjectTile(
                gameState: gameState,
                definition: definition,
                isActive: active?.definition.id == definition.id,
              ),
          ],
        ),
      ),
    );
  }
}

class _CommunityProjectTile extends StatelessWidget {
  const _CommunityProjectTile(
      {required this.gameState,
      required this.definition,
      required this.isActive});

  final Zone0GameState gameState;
  final CommunityProjectDefinition definition;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final project = gameState.communityProjects[definition.id];
    final progress = project == null
        ? 0.0
        : (project.currentContributionPoints /
                definition.requiredContributionPoints)
            .clamp(0.0, 1.0);
    final isComplete = project?.status == CommunityProjectStatus.completed;
    final accessible = gameState.canSelectCommunityProject(definition);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                    child: Text(definition.label,
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Text(isComplete ? 'Terminé' : 'Niv. ${definition.tier}'),
              ]),
              Text(definition.description),
              Text(
                  'Protection globale : +${definition.globalProtectionPercent}% · ${definition.materialCosts.entries.map((entry) => '${entry.value} ${entry.key}').join(' · ')}'),
              if (project != null) ...<Widget>[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
                Text(
                    '${project.currentContributionPoints}/${definition.requiredContributionPoints} contributions'),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                if (project == null && accessible)
                  OutlinedButton(
                      onPressed: () => _show(
                          context,
                          gameState
                              .selectCommunityProject(definition.id)
                              .message),
                      child: const Text('Choisir')),
                if (project != null && !isComplete && !isActive)
                  OutlinedButton(
                      onPressed: () => _show(
                          context,
                          gameState
                              .activateCommunityProject(definition.id)
                              .message),
                      child: const Text('Commencer')),
                if (isActive) ...<Widget>[
                  for (final cost in definition.materialCosts.entries)
                    OutlinedButton(
                        onPressed: () => _show(
                            context,
                            gameState
                                .depositCommunityProjectMaterial(
                                    definition.id, cost.key, 1)
                                .message),
                        child: Text('+1 ${cost.key}')),
                  FilledButton(
                      onPressed: () => _show(context,
                          gameState.contributeToCommunityProject().message),
                      child: const Text('Contribuer')),
                ],
              ]),
              if (project == null && !accessible && !isComplete)
                const Text(
                    'Niveau du Cœur, prérequis ou choix disponible requis.'),
            ]),
      ),
    );
  }

  void _show(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
    Widget resourceGauge({
      required String resource,
      required int stored,
      required int capacity,
      required Color color,
    }) {
      final ratio = capacity == 0 ? 0.0 : (stored / capacity).clamp(0.0, 1.0);
      return Expanded(
        child: Column(
          children: <Widget>[
            Text(
              resource,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 168,
              width: 56,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: color.withValues(alpha: .14),
                      border: Border.all(color: color.withValues(alpha: .55)),
                    ),
                  ),
                  FractionallySizedBox(
                    heightFactor: ratio,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '$stored/$capacity',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Maison : ${gameState.resourceAmount(resource)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 2,
              children: <int>[1, 5, 10, 9999]
                  .map(
                    (amount) => TextButton(
                      onPressed: () {
                        final result = gameState.transferToGenerator(
                          resource: resource,
                          amount: amount,
                          heartLevel: heartLevel,
                        );
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.message)));
                      },
                      child: Text(amount == 9999 ? 'Max' : '+$amount'),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    }

    final active = gameState.generatorCycleStartedAt != null;
    final organicCapacity = gameState.generatorOrganicCapacity(heartLevel);
    final mineralCapacity = gameState.generatorMineralCapacity(heartLevel);
    final paliers = math.min(
      gameState.generatorOrganic ~/ campGeneratorConfig.organicCostPerCycle,
      gameState.generatorMineral ~/ campGeneratorConfig.mineralCostPerCycle,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Bio-réacteur niveau $heartLevel',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          '5 Organique + 1 Minéral → 1 Bio-batterie toutes les ${campGeneratorConfig.cycleMinutes(heartLevel)} min.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                resourceGauge(
                  resource: 'Organique',
                  stored: gameState.generatorOrganic,
                  capacity: organicCapacity,
                  color: Colors.green,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: Column(
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 94,
                        height: 94,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? Colors.green : Colors.grey,
                          boxShadow: active
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: .45),
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                        child: const Icon(
                          Icons.battery_charging_full_outlined,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        active ? 'Production' : 'En attente',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '$paliers palier(s) prêt(s)',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                resourceGauge(
                  resource: 'Minéral',
                  stored: gameState.generatorMineral,
                  capacity: mineralCapacity,
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(_remainingLabel()),
            subtitle: Text(
              'Production totale : ${gameState.generatorTotalProduced} · Bio-batteries : ${gameState.bioBatteries}',
            ),
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
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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
              'Végétaliser le Cœur',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Stock Organique Maison : $maxAmount',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: maxAmount <= 0
                  ? null
                  : () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => _CampHeartOrganicDepositSheet(
                          stock: maxAmount,
                          onConfirm: onDeposit,
                        ),
                      ),
              child: Container(
                height: 112,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 36),
                    Text('Ajouter de l’Organique'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampHeartOrganicDepositSheet extends StatefulWidget {
  const _CampHeartOrganicDepositSheet({
    required this.stock,
    required this.onConfirm,
  });

  final int stock;
  final ValueChanged<int> onConfirm;

  @override
  State<_CampHeartOrganicDepositSheet> createState() =>
      _CampHeartOrganicDepositSheetState();
}

class _CampHeartOrganicDepositSheetState
    extends State<_CampHeartOrganicDepositSheet> {
  int _selected = 0;

  void _add(int amount) => setState(() {
        _selected = math.min(widget.stock, _selected + amount);
      });

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ajouter au Cœur',
                style: Theme.of(
                  context,
                )
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.eco_outlined),
                title: const Text('Organique'),
                subtitle: Text('Maison : ${widget.stock}'),
                trailing: Text('$_selected / ${widget.stock}'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: () => _add(1), child: const Text('+1')),
                  TextButton(onPressed: () => _add(5), child: const Text('+5')),
                  TextButton(
                      onPressed: () => _add(10), child: const Text('+10')),
                  TextButton(
                    onPressed: () => setState(() => _selected = widget.stock),
                    child: const Text('Max'),
                  ),
                  IconButton(
                    tooltip: 'Retirer la sélection',
                    onPressed: _selected == 0
                        ? null
                        : () => setState(() => _selected = 0),
                    icon: const Icon(Icons.undo),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _selected == 0
                    ? null
                    : () {
                        widget.onConfirm(_selected);
                        Navigator.of(context).pop();
                      },
                child: const Text('Investir dans le Cœur'),
              ),
            ],
          ),
        ),
      );
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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
            Text(footer, style: Theme.of(context).textTheme.bodySmall),
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
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Surveillance'),
              Tab(text: 'Exploration'),
              Tab(text: 'Météo'),
              Tab(text: 'Amélioration'),
              Tab(text: 'Infos'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            SafeArea(
              child: StreamBuilder<List<PtipoteFigurine>>(
                stream: widget.figurineService.watchMyFigurines(),
                builder: (context, snapshot) {
                  final figurines = snapshot.data ?? const <PtipoteFigurine>[];
                  final activeTowerMissions = widget.gameState.towerMissions
                      .where(
                        (mission) =>
                            mission.status == TowerMissionStatus.active,
                      )
                      .toList();
                  final campPatrols = activeTowerMissions
                      .where((mission) => mission.patrolBiome == null)
                      .toList();
                  final biomePatrols = activeTowerMissions
                      .where((mission) => mission.patrolBiome != null)
                      .toList();
                  final explorations = widget.gameState.explorationMissions
                      .where((mission) => mission.isActive)
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(result.message),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.electrical_services_outlined,
                                ),
                                label: Text(
                                  widget.gameState
                                              .towerManualRechargeRemaining() ==
                                          Duration.zero
                                      ? 'Recharger les balises (+${securityTowerConfig.manualRechargeGainForLevel(widget.gameState.securityTowerLevel)})'
                                      : 'Recharge dans ${widget.gameState.towerManualRechargeRemaining().inMinutes + 1} min',
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
                                'Opérations en cours',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 10),
                              _TowerOperationGroup(
                                title: 'Ronde dans le camp',
                                emptyLabel: 'Aucune ronde dans le camp.',
                                missions: campPatrols,
                                onReturn: widget.gameState.removeFromTower,
                              ),
                              const Divider(height: 22),
                              _TowerOperationGroup(
                                title: 'Ronde dans les biomes',
                                emptyLabel: 'Aucune ronde locale.',
                                missions: biomePatrols,
                                onReturn: widget.gameState.removeFromTower,
                              ),
                              const Divider(height: 22),
                              Text(
                                'Exploration (${explorations.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (explorations.isEmpty)
                                const Text('Aucune exploration en cours.')
                              else
                                ...explorations.map(
                                  (mission) => Text(
                                    '${lisiereForageConfig.biomes[mission.biome]!.label} · ${_countdownLabel(mission.endTime)}',
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
                                      subtitle: _towerUnavailableReason(
                                        figurine,
                                      ),
                                      action: const SizedBox.shrink(),
                                    ),
                                  ),
                                ],
                              ] else
                                FilledButton.icon(
                                  onPressed: () =>
                                      _chooseTowerMission(figurines),
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
              figurineService: widget.figurineService,
            ),
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
          ],
        ),
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
                  subtitle: Text(
                    plan == TowerMissionPlan.until25Vitality
                        ? '${figurine.displayName} rentrera puis ira dormir.'
                        : '${figurine.displayName} surveillera les abords.',
                  ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
  const _TowerExplorationTab({
    required this.gameState,
    required this.figurineService,
  });
  final Zone0GameState gameState;
  final FigurineService figurineService;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: StreamBuilder<List<PtipoteFigurine>>(
          stream: figurineService.watchMyFigurines(),
          builder: (context, snapshot) {
            final available = (snapshot.data ?? const <PtipoteFigurine>[])
                .where(
                  (item) =>
                      !gameState.isBusy(item) &&
                      gameState.vitalityFor(item) >=
                          ptipoteStatsConfig.minimumMissionVitality,
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Carte des abords. Chaque exploration demande ${towerOperationsConfig.biomeRevealSecurityThreshold}% de sécurité moyenne sur les biomes adjacents.',
                    ),
                  ),
                ),
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
                    final adjacentSecurity = gameState.adjacentBiomeSecurityFor(
                      biome,
                    );
                    final enabled = adjacentSecurity >=
                            towerOperationsConfig
                                .biomeRevealSecurityThreshold &&
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
                              Icon(
                                unlocked
                                    ? Icons.travel_explore
                                    : Icons.lock_outline,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              Text(
                                unlocked
                                    ? 'Disponible en Lisière'
                                    : exploring
                                        ? 'Exploration en cours'
                                        : adjacentSecurity >=
                                                towerOperationsConfig
                                                    .biomeRevealSecurityThreshold
                                            ? 'À explorer'
                                            : 'Sécurité voisine insuffisante',
                              ),
                              if (!unlocked)
                                Text(
                                  'Sécurité voisine : $adjacentSecurity% / ${towerOperationsConfig.biomeRevealSecurityThreshold}%',
                                ),
                              Text(
                                'Danger potentiel : ${lisiereForageConfig.biomes[biome]!.baseRiskPercent}%',
                              ),
                              Text(
                                'Biomasse : ${gameState.biomassVisualStateFor(biome).icon} ${gameState.biomassVisualStateFor(biome).label} · ${gameState.biomassFor(biome)}%',
                              ),
                              if (!unlocked) ...<Widget>[
                                Text(
                                  'Exploration : ${state.explorationProgress}% / 100%',
                                ),
                                LinearProgressIndicator(
                                  value: state.explorationProgress / 100,
                                ),
                              ],
                              if (state.explorationProgress >= 30)
                                Text(
                                  _biomeResourceHints(
                                    biome,
                                    detailLevel: state.explorationProgress >= 70
                                        ? 2
                                        : state.explorationProgress >= 50
                                            ? 1
                                            : 0,
                                  ),
                                ),
                              if (unlocked) ...<Widget>[
                                Text(
                                  'Réduction de danger : -${_localRiskReduction(state.localSecurity)}%',
                                ),
                                Text(
                                  'Sécurisation : ${state.localSecurity}% / 100%',
                                ),
                                LinearProgressIndicator(
                                  value: state.localSecurity / 100,
                                  color: Theme.of(context).colorScheme.primary,
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
                                      title: 'Explorer $label',
                                    );
                                    if (figurine != null && context.mounted) {
                                      final hours =
                                          await _pickExplorationDuration(
                                        context,
                                      );
                                      if (hours == null || !context.mounted) {
                                        return;
                                      }
                                      final result =
                                          gameState.startBiomeExploration(
                                        biome: biome,
                                        figurines: <PtipoteFigurine>[figurine],
                                        durationHours: hours,
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                    }
                                  },
                                  child: const Text('Explorer'),
                                ),
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
                                      title: 'Sécuriser $label',
                                    );
                                    if (figurine != null && context.mounted) {
                                      final plan =
                                          await _pickPatrolPlan(context);
                                      if (plan == null || !context.mounted) {
                                        return;
                                      }
                                      final result = gameState.startBiomePatrol(
                                        biome: biome,
                                        figurine: figurine,
                                        plan: plan,
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.shield_outlined),
                                  label: const Text('Sécuriser'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      );
}

class _ExplorationMap3x3 extends StatelessWidget {
  const _ExplorationMap3x3({required this.gameState});
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    // Topology is deliberately stable: the Camp stays at the bottom centre.
    const cells = <ForageBiome?>[
      null,
      ForageBiome.sousBois,
      null,
      ForageBiome.colline,
      ForageBiome.plaineRiche,
      null,
      ForageBiome.bassinMineral,
      null,
      null,
    ];
    const futureLabels = <int, String>{
      0: 'Montagne',
      2: 'Savane',
      5: 'Mangrove',
      8: 'Littoral',
    };
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
            label: 'Camp',
            icon: Icons.home_outlined,
            active: true,
          );
        }
        final biome = cells[index];
        if (biome == null) {
          return _ExplorationMapCell(
            label:
                '${futureLabels[index] ?? 'Zone inconnue'}\nBientôt disponible',
            icon: Icons.lock_outline,
            active: false,
          );
        }
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
  const _ExplorationMapCell({
    required this.label,
    required this.icon,
    required this.active,
    this.progress,
  });
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
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              if (progress != null && progress! > 0)
                Text('$progress%', style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
}

class _TowerWeatherTab extends StatelessWidget {
  const _TowerWeatherTab({required this.gameState});
  final Zone0GameState gameState;
  @override
  Widget build(BuildContext context) {
    final active = gameState.activeGlobalWeatherEvent;
    String label(TowerWeatherType type) => switch (type) {
          TowerWeatherType.calm => '🌤️ Temps calme',
          TowerWeatherType.toxicCloud => '☁️ Nuage toxique',
          TowerWeatherType.heatWave => '☀️ Forte chaleur',
          TowerWeatherType.heavyRain => '🌧️ Pluie intense',
        };
    String intensity(GlobalWeatherIntensity value) => switch (value) {
          GlobalWeatherIntensity.calm => 'Calme',
          GlobalWeatherIntensity.moderate => 'Modérée',
          GlobalWeatherIntensity.strong => 'Forte',
          GlobalWeatherIntensity.severe => 'Sévère',
        };
    String biomes(GlobalWeatherEvent event) => event.affectedBiomes
        .where((impact) => impact.isAffected)
        .map((impact) =>
            '${lisiereForageConfig.biomes[impact.biome]!.label} · ${impact.localImpactLevel == 'high' ? 'élevé' : impact.localImpactLevel == 'medium' ? 'moyen' : 'faible'}')
        .join(', ');
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Météo actuelle',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(active == null
                      ? 'Prévisions en cours.'
                      : '${label(active.type)} · ${intensity(active.intensity)}'),
                  if (active != null) ...<Widget>[
                    Text('Temps restant : ${_countdownLabel(active.endsAt)}'),
                    Text(active.type == TowerWeatherType.calm
                        ? 'Conditions calmes sur la Zone 0.'
                        : 'Biomes touchés : ${biomes(active)}'),
                  ],
                ],
              ),
            ),
          ),
          if (active != null) ...<Widget>[
            const SizedBox(height: 10),
            _WeatherPreparationCard(gameState: gameState, event: active),
          ],
        ],
      ),
    );
  }
}

class _WeatherPreparationCard extends StatelessWidget {
  const _WeatherPreparationCard({required this.gameState, required this.event});
  final Zone0GameState gameState;
  final GlobalWeatherEvent event;

  @override
  Widget build(BuildContext context) {
    final structural = switch (event.type) {
      TowerWeatherType.heatWave => 'Ventilation Termite',
      TowerWeatherType.heavyRain => 'Chloro-canaux',
      TowerWeatherType.toxicCloud => 'Installation filtrante',
      TowerWeatherType.calm => 'Aucune structure nécessaire',
    };
    final module = switch (event.type) {
      TowerWeatherType.heatWave => 'Réflecteur',
      TowerWeatherType.heavyRain => 'Étanchéité',
      TowerWeatherType.toxicCloud => 'Filtreur (Trait P’TIBUG)',
      TowerWeatherType.calm => 'Aucun module requis',
    };
    final projects = campHeartConfig.communityProjects.projects
        .where((project) => project.weatherType == event.type.name)
        .map((project) => project.label)
        .join(' → ');
    final requests =
        marketConfig.weatherRequestItems[event.type.name] ?? const <String>[];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Préparations recommandées',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Text('Bâtiments : $structural.'),
                  if (projects.isNotEmpty)
                    Text('Grands chantiers : $projects.'),
                  Text('P’TIBUG : $module.'),
                  if (requests.isNotEmpty)
                    Text(
                        'Demandes possibles au Marché : ${requests.join(', ')}.'),
                ])));
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
  final mission = state.explorationMissions.firstWhere(
    (item) => item.biome == biome && item.isActive,
  );
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

String _merchantRemainingLabel(Zone0GameState state) {
  final endTime = state.merchantAvailableUntil;
  if (endTime == null) return 'Retour imminent';
  final remaining = endTime.difference(DateTime.now());
  if (remaining <= Duration.zero) return 'Retour imminent';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  if (hours > 0) return '$hours h ${minutes.toString().padLeft(2, '0')} min';
  return '${math.max(1, minutes)} min';
}

String _merchantArrivalLabel(Zone0GameState state) {
  final next = state.merchantNextArrivalAt;
  if (next == null) return 'Le Sourcier organise sa prochaine visite.';
  final remaining = next.difference(DateTime.now());
  if (remaining <= Duration.zero) return 'Le Sourcier arrive.';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  final countdown = hours > 0
      ? '$hours h ${minutes.toString().padLeft(2, '0')} min'
      : '${math.max(1, minutes)} min';
  if (state.hasPendingMerchantCall) {
    return 'Appel transmis. Le Sourcier arrive dans $countdown.';
  }
  return 'Prochaine visite dans $countdown. '
      '${state.merchantVisitsRemaining} passage(s) restant(s) aujourd’hui.';
}

Future<int?> _pickExplorationDuration(
  BuildContext context,
) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            const Text(
              'Durée de reconnaissance',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const Text(
              '10 h d’exploration au total. Chaque heure apporte 10% de progression.',
            ),
            ...<int>[1, 2, 4, 8].map(
              (hours) => ListTile(
                title: Text('${hours}h de mission'),
                subtitle: Text('+${hours * 10}% exploration'),
                onTap: () => Navigator.of(context).pop(hours),
              ),
            ),
          ],
        ),
      ),
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
            const Text(
              'Durée de sécurisation',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const Text(
              '8 h au total permettent de sécuriser entièrement un biome.',
            ),
            ...<TowerMissionPlan>[
              TowerMissionPlan.oneHour,
              TowerMissionPlan.twoHours,
              TowerMissionPlan.fourHours,
              TowerMissionPlan.eightHours,
            ].map(
              (plan) => ListTile(
                title: Text(_towerPlanLabelForPicker(plan)),
                subtitle: Text('+${_patrolSecurityGain(plan)}% au retour'),
                onTap: () => Navigator.of(context).pop(plan),
              ),
            ),
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

class _TowerOperationGroup extends StatelessWidget {
  const _TowerOperationGroup({
    required this.title,
    required this.emptyLabel,
    required this.missions,
    required this.onReturn,
  });

  final String title;
  final String emptyLabel;
  final List<TowerMission> missions;
  final ValueChanged<String> onReturn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (missions.isEmpty)
          Text(emptyLabel)
        else
          ...missions.map(
            (mission) => _TowerFigurineRow(
              name: mission.figurineName,
              subtitle:
                  '${mission.patrolBiome == null ? 'Camp' : lisiereForageConfig.biomes[mission.patrolBiome]!.label} · ${_countdownLabel(mission.endTime)} · +${mission.securityGain} sécurité',
              action: TextButton(
                onPressed: () => onReturn(mission.figurineId),
                child: const Text('Retour'),
              ),
            ),
          ),
      ],
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
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(description),
                  const SizedBox(height: 14),
                  const Text(
                    'Effets actuels',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  ...currentEffects.map(Text.new),
                  const SizedBox(height: 10),
                  const Text(
                    'Niveau suivant',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  ...nextEffects.map(Text.new),
                  if (project.isInProgress) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Travaux : ${_countdownLabel(project.endsAt!)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
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
                          : 'Préparer l’amélioration',
                    ),
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
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
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
    this.campHeartState,
  });

  final Zone0GameState gameState;
  final String targetId;
  final String title;
  final String description;
  final String? footer;
  final String? blockedReason;
  final int? campHeartLevel;
  final CampHeartState? campHeartState;

  @override
  State<_ConstructionProjectSheet> createState() =>
      _ConstructionProjectSheetState();
}

class _ConstructionProjectSheetState extends State<_ConstructionProjectSheet> {
  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    widget.campHeartState?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.gameState.removeListener(_changed);
    widget.campHeartState?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.gameState.projectFor(widget.targetId);
    final campHeartLevel =
        widget.campHeartState?.campHeartLevel ?? widget.campHeartLevel ?? 0;
    final blockedReason = _resolvedBlockedReason(campHeartLevel);
    final footer = _resolvedFooter(campHeartLevel);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(widget.description),
            if (blockedReason != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                blockedReason,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (project.state == ConstructionProjectState.maxLevel)
              const Text(
                'Niveau maximum atteint.',
                style: TextStyle(fontWeight: FontWeight.w900),
              )
            else if (project.isInProgress)
              Text(
                _countdownLabel(project.endsAt!),
                style: const TextStyle(fontWeight: FontWeight.w900),
              )
            else
              ...project.requirements.entries.map(
                (entry) => _ConstructionMaterialProgress(
                  resource: entry.key,
                  deposited: project.depositedMaterials[entry.key] ?? 0,
                  required: entry.value,
                  // Le prerequis du Coeur bloque le lancement, pas la
                  // preparation progressive des materiaux.
                  enabled: project.canEditMaterials,
                  onDeposit: (amount) =>
                      widget.gameState.depositProjectMaterial(
                    widget.targetId,
                    entry.key,
                    amount,
                  ),
                  onWithdraw: () => widget.gameState.withdrawProjectMaterial(
                    widget.targetId,
                    entry.key,
                  ),
                ),
              ),
            if (footer != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                footer,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: blockedReason == null &&
                      project.isReady &&
                      !project.isInProgress &&
                      project.state != ConstructionProjectState.maxLevel
                  ? () {
                      final result = widget.gameState.startConstructionProject(
                        widget.targetId,
                        campHeartLevel: campHeartLevel,
                      );
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(result.message)));
                    }
                  : null,
              icon: const Icon(Icons.construction_outlined),
              label: Text(
                project.isInProgress
                    ? 'Travaux en cours'
                    : project.state == ConstructionProjectState.maxLevel
                        ? 'Niveau maximum'
                        : 'Commencer les travaux',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolvedBlockedReason(int campHeartLevel) {
    if (widget.targetId == 'plaineNursery') {
      return campHeartLevel < 2
          ? 'Le Cœur du Camp doit atteindre le niveau 2 pour commencer les travaux de la Nurserie.'
          : null;
    }
    return widget.blockedReason;
  }

  String? _resolvedFooter(int campHeartLevel) {
    if (widget.targetId == 'plaineNursery') {
      return campHeartLevel < 2
          ? 'Vous pouvez préparer les matériaux maintenant. Les travaux pourront être lancés à partir du niveau 2 du Coeur ($campHeartLevel / 2).'
          : 'Les materiaux peuvent etre deposes progressivement.';
    }
    return widget.footer;
  }
}

class _ConstructionMaterialProgress extends StatelessWidget {
  const _ConstructionMaterialProgress({
    required this.resource,
    required this.deposited,
    required this.required,
    required this.enabled,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final String resource;
  final int deposited;
  final int required;
  final bool enabled;
  final ValueChanged<int> onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final missing = math.max(0, required - deposited);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(resource, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value:
                        required == 0 ? 1 : (deposited / required).clamp(0, 1),
                    minHeight: 30,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
                Text(
                  '$deposited / $required',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              TextButton(
                onPressed: enabled && missing > 0 ? () => onDeposit(1) : null,
                child: const Text('+1'),
              ),
              TextButton(
                onPressed: enabled && missing > 0 ? () => onDeposit(5) : null,
                child: const Text('+5'),
              ),
              TextButton(
                onPressed:
                    enabled && missing > 0 ? () => onDeposit(missing) : null,
                child: const Text('Max'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Récupérer les matériaux',
                onPressed: deposited > 0 ? onWithdraw : null,
                icon: const Icon(Icons.undo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarketConstructionSheet extends StatelessWidget {
  const _MarketConstructionSheet({
    required this.gameState,
    required this.campHeartLevel,
  });
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
  final Map<MerchantOffer, int> _merchantQuantities = <MerchantOffer, int>{};
  final List<String> _constructionActions = <String>[];
  Timer? _timer;
  Timer? _constructionNoticeTimer;
  int _marketTab = 0;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        widget.gameState.resolveMarket();
        if (mounted) setState(() {});
      },
    );
    widget.gameState.resolveMarket();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _constructionNoticeTimer?.cancel();
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _recordConstructionAction(String message) {
    _constructionActions.add(message);
    if (_constructionActions.length > 8) _constructionActions.removeAt(0);
    _constructionNoticeTimer?.cancel();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Construction : ${_constructionActions.join(' · ')}'),
      duration: const Duration(seconds: 10),
    ));
    _constructionNoticeTimer = Timer(const Duration(minutes: 1), () {
      _constructionActions.clear();
    });
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
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Population ${widget.gameState.currentPopulation} · Bien-être ${widget.gameState.campWellbeing}%',
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showMarketActivityDetails(context),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.insights_outlined, size: 18),
                                const SizedBox(width: 5),
                                Text(
                                    'Activité économique : ${widget.gameState.marketEconomicActivityPercent}%'),
                                const SizedBox(width: 3),
                                const Icon(Icons.info_outline, size: 16),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          'Bio-batteries gagnées : ${widget.gameState.marketBioBatteriesEarned}',
                        ),
                        Text(
                          widget.gameState.marketAssignedPtipoteName == null
                              ? 'Mode automatique'
                              : 'Aidé par ${widget.gameState.marketAssignedPtipoteName}',
                        ),
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
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (_) => const _BuildingInformationTab(
                                  title: 'Marché',
                                  description:
                                      'Chaque vente répond à une demande habitant visible dans cette page. Le stock ne déclenche jamais de vente seul. Le Point info accueille un P’TIPOTE pour soutenir les futurs magasins spécialisés.',
                                ),
                              ),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Infos'),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _confirmMarketShopReset,
                          icon: const Icon(Icons.restart_alt_outlined),
                          label: const Text('Réinitialiser mes boutiques'),
                        ),
                        if (widget.gameState.marketAssignedPtipoteId != null)
                          if (figurines
                                  .where((figurine) =>
                                      figurine.id ==
                                      widget.gameState.marketAssignedPtipoteId)
                                  .firstOrNull
                              case final assigned?)
                            Card(
                              margin: const EdgeInsets.only(top: 10),
                              child: ListTile(
                                leading: SizedBox(
                                  width: 46,
                                  child: PtipoteImage(
                                    type: assigned.type,
                                    species: assigned.species,
                                    height: 46,
                                  ),
                                ),
                                title: Text(assigned.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                subtitle: Text(
                                  'Niv. ${assigned.level} · faim ${widget.gameState.hungerFor(assigned)} · repos ${widget.gameState.restFor(assigned)}',
                                ),
                                trailing: assigned.levelValue >= 2
                                    ? OutlinedButton(
                                        onPressed: _showMarketRestockRules,
                                        child: const Text('Réappro'),
                                      )
                                    : null,
                              ),
                            )
                          else
                            OutlinedButton(
                              onPressed: () =>
                                  widget.gameState.removeFromMarket(),
                              child: const Text('Faire rentrer'),
                            )
                        else
                          FilledButton.icon(
                            onPressed: () async {
                              final figurine = await _pickPtipoteForActivity(
                                context: context,
                                gameState: widget.gameState,
                                figurines: figurines,
                                title: 'Affecter au Point info',
                              );
                              if (figurine == null || !context.mounted) {
                                return;
                              }
                              _message(
                                widget.gameState
                                    .assignToMarket(figurine)
                                    .message,
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Affecter au Point info'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.gameState.marketLevel >= 2)
                  SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.storefront_outlined),
                          label: Text('Vente')),
                      ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.menu_book_outlined),
                          label: Text('Livre des demandes')),
                    ],
                    selected: <int>{_marketTab},
                    onSelectionChanged: (value) =>
                        setState(() => _marketTab = value.first),
                  ),
                if (widget.gameState.marketLevel >= 2)
                  const SizedBox(height: 10),
                if (_marketTab == 1) _marketRequestBook(),
                if (_marketTab == 0) ...<Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Sourcier du savoir',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                              'Confiance : ${widget.gameState.sourcierConfidence}/100'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: widget.gameState.sourcierConfidence / 100,
                          ),
                          if (widget.gameState.marketLevel >= 2) ...<Widget>[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _showSourcierLicenses,
                              icon:
                                  const Icon(Icons.workspace_premium_outlined),
                              label: Text(
                                  'Licences commerciales (${widget.gameState.activeMarketLicenses.length}/${marketConfig.licenseSlotsForLevel(widget.gameState.marketLevel)})'),
                            ),
                          ],
                          if (!widget
                              .gameState.isMerchantAvailable) ...<Widget>[
                            Text(
                              _merchantArrivalLabel(widget.gameState),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    widget.gameState.hasPendingMerchantCall ||
                                            widget.gameState
                                                    .merchantVisitsRemaining <=
                                                0 ||
                                            widget.gameState.bioBatteries <
                                                towerOperationsConfig
                                                    .merchantCallBatteryCost
                                        ? null
                                        : () => _message(
                                              widget.gameState
                                                  .requestMerchantVisit()
                                                  .message,
                                            ),
                                icon: const Icon(
                                    Icons.record_voice_over_outlined),
                                label: Text(
                                  'Appeler le Sourcier '
                                  '(${towerOperationsConfig.merchantCallBatteryCost} bio-batterie)',
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Arrivée aléatoire entre 5 et 15 min.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ] else ...<Widget>[
                            Text(
                              'Présent encore ${_merchantRemainingLabel(widget.gameState)}',
                            ),
                            ...widget.gameState.merchantOffers.map(
                              (offer) {
                                final requirement = widget.gameState
                                    .merchantOfferRequirementLabel(offer);
                                final isWorkshopProduct = offer.kind ==
                                    MerchantOfferKind.workshopItem;
                                final quantityMaximum = math.max(
                                  1,
                                  offer.remainingItemAmount,
                                );
                                final selectedQuantity = isWorkshopProduct
                                    ? (_merchantQuantities[offer] ?? 1)
                                        .clamp(1, quantityMaximum)
                                        .toInt()
                                    : 1;
                                final totalPrice = offer.priceForQuantity(
                                  selectedQuantity,
                                );
                                final offerTitle = isWorkshopProduct
                                    ? offer.itemName ??
                                        offer.planName.replaceFirst('Plan ', '')
                                    : offer.planName;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.25),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            offerTitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isWorkshopProduct
                                                ? '$totalPrice Bio-batteries · ${offer.price} / unité'
                                                : '$totalPrice Bio-batteries',
                                          ),
                                          if (isWorkshopProduct) ...<Widget>[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: <Widget>[
                                                IconButton.outlined(
                                                  onPressed: offer
                                                              .isUnavailable ||
                                                          selectedQuantity <= 1
                                                      ? null
                                                      : () => setState(() {
                                                            _merchantQuantities[
                                                                    offer] =
                                                                selectedQuantity -
                                                                    1;
                                                          }),
                                                  icon: const Icon(
                                                    Icons.chevron_left,
                                                  ),
                                                  tooltip: 'Retirer une unité',
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    'Quantité : $selectedQuantity (${offer.remainingItemAmount} disponible${offer.remainingItemAmount > 1 ? 's' : ''})',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                IconButton.outlined(
                                                  onPressed: offer
                                                              .isUnavailable ||
                                                          selectedQuantity >=
                                                              offer
                                                                  .remainingItemAmount
                                                      ? null
                                                      : () => setState(() {
                                                            _merchantQuantities[
                                                                    offer] =
                                                                selectedQuantity +
                                                                    1;
                                                          }),
                                                  icon: const Icon(
                                                    Icons.chevron_right,
                                                  ),
                                                  tooltip: 'Ajouter une unité',
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (requirement != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                '($requirement)',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: offer.isUnavailable
                                                ? const OutlinedButton(
                                                    onPressed: null,
                                                    child: Text('Épuisé'),
                                                  )
                                                : FilledButton(
                                                    onPressed: () => _message(
                                                      widget.gameState
                                                          .buyMerchantOffer(
                                                            offer,
                                                            quantity:
                                                                selectedQuantity,
                                                          )
                                                          .message,
                                                    ),
                                                    child: Text(
                                                      isWorkshopProduct
                                                          ? 'Acheter $selectedQuantity'
                                                          : 'Acheter',
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            TextButton(
                              onPressed: () => _message(
                                widget.gameState
                                    .finishMerchantTransaction()
                                    .message,
                              ),
                              child: const Text('Terminer la transaction'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sourcierContractsSection(),
                  if (widget.gameState.marketContracts.isNotEmpty)
                    const SizedBox(height: 10),
                  // Compatibilité de rendu : le Distributeur principal est
                  // désormais affiché dans la carte de sa boutique unique.
                  if (widget.gameState.marketShopCount == 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                                'Boutique principale · Distributeur automatique',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                            if (!widget.gameState.marketDistributor
                                .isBuilt) ...<Widget>[
                              const SizedBox(height: 8),
                              const Text(
                                'Type de Distributeur',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              SegmentedButton<MarketDistributorType>(
                                segments: MarketDistributorType.values
                                    .map(
                                      (type) =>
                                          ButtonSegment<MarketDistributorType>(
                                        value: type,
                                        label: Text(type.label),
                                      ),
                                    )
                                    .toList(growable: false),
                                selected: <MarketDistributorType>{
                                  widget.gameState.marketDistributor.type,
                                },
                                onSelectionChanged: (selection) => _message(
                                  widget.gameState
                                      .setMarketDistributorType(
                                        selection.first,
                                      )
                                      .message,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(widget.gameState.marketDistributor.type
                                  .stockDescription),
                              const SizedBox(height: 8),
                              Text(widget
                                      .gameState.isMarketDistributorReadyToBuild
                                  ? 'Matériaux complets · prêt à démarrer'
                                  : 'Construction : ${marketConfig.distributorConstructionCost.entries.map((entry) => '${entry.key} ${widget.gameState.marketDistributor.constructionDeposits[entry.key] ?? 0}/${entry.value}').join(' · ')}'),
                              ...marketConfig.distributorConstructionCost.keys
                                  .map(
                                (resource) => Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    Text(resource,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    ...const <int>[1, 5, 10]
                                        .map((amount) => OutlinedButton(
                                              onPressed: () {
                                                final result = widget.gameState
                                                    .depositMarketDistributorMaterial(
                                                        resource, amount);
                                                if (result.success)
                                                  _recordConstructionAction(
                                                      result.message);
                                              },
                                              child: Text('+$amount'),
                                            )),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: widget.gameState
                                        .isMarketDistributorReadyToBuild
                                    ? () => _message(widget.gameState
                                        .startMarketDistributorConstruction()
                                        .message)
                                    : null,
                                child: const Text('Commencer les travaux'),
                              ),
                            ] else ...<Widget>[
                              Text(
                                  'Niveau ${widget.gameState.marketDistributor.level} · ${widget.gameState.marketDistributor.isBroken ? 'En panne' : widget.gameState.marketDistributor.energy <= 0 ? 'Sans Énergie' : 'Opérationnel'}'),
                              if (widget.gameState.marketDistributor
                                      .repairEndsAt !=
                                  null) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                    'Réparation par ${widget.gameState.marketDistributor.repairStartedBy == 'ptipote' ? 'le P’TIPOTE' : 'le joueur'} · ${_countdownLabel(widget.gameState.marketDistributor.repairEndsAt!)}'),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                    value: _repairProgress(widget.gameState
                                        .marketDistributor.repairEndsAt!)),
                              ],
                              Text(
                                'Type : ${widget.gameState.marketDistributor.type.label}',
                              ),
                              Text(widget.gameState.marketDistributor.type
                                  .stockDescription),
                              Text(
                                  'Énergie : ${widget.gameState.marketDistributor.energy}/${marketConfig.distributorEnergyCapacity}'),
                              Row(children: <Widget>[
                                Expanded(
                                    child: OutlinedButton(
                                  onPressed: () => _message(widget.gameState
                                      .openBioBatteryForMarketDistributor()
                                      .message),
                                  child: const Text('Ouvrir une Bio-batterie'),
                                )),
                                if (widget.gameState.marketDistributor
                                    .isBroken) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: FilledButton(
                                    onPressed: () => _message(widget.gameState
                                        .repairMarketDistributor()
                                        .message),
                                    child: const Text('Réparer'),
                                  )),
                                ],
                              ]),
                              const SizedBox(height: 10),
                              Text(
                                'Stock du Distributeur (${widget.gameState.marketDistributor.stock.length}/${widget.gameState.marketDistributorSlotLimit})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GridView.count(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: List<Widget>.generate(
                                  widget.gameState.marketDistributorSlotLimit,
                                  (index) {
                                    final stack = index <
                                            widget.gameState.marketDistributor
                                                .stock.length
                                        ? widget.gameState.marketDistributor
                                            .stock[index]
                                        : null;
                                    return _MarketStockSlot(
                                      stack: stack,
                                      onTap: () =>
                                          _editMarketDistributorSlot(stack),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _activeMarketRequestsSection(),
                  const SizedBox(height: 12),
                  _marketShopsSection(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  double _repairProgress(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now()).inSeconds;
    // Une jauge décroissante reste lisible même après un retour hors ligne.
    return (remaining / (30 * 60)).clamp(0.0, 1.0).toDouble();
  }

  String _ptipoteAgeLabel(PtipoteFigurine figurine) {
    final days = DateTime.now().difference(figurine.createdAt).inDays;
    return days <= 0 ? 'moins d’un jour' : '$days jour${days > 1 ? 's' : ''}';
  }

  Future<void> _confirmMarketShopReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Réinitialiser les boutiques ?'),
        content: const Text(
          'Les boutiques et distributeurs actuels seront supprimés. Leurs stocks seront d’abord rendus à la Maison dans la limite de capacité.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _message(widget.gameState.resetMarketShops().message);
    }
  }

  Future<void> _showMarketRestockRules() async {
    final resources = marketConfig.saleValues.keys.toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: <Widget>[
            const Text('Ordres de réapprovisionnement',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
              'Active les produits autorisés. Le nombre indique le minimum que la Maison doit conserver avant un futur réapprovisionnement automatique.',
            ),
            const SizedBox(height: 12),
            ...resources.map((resource) {
              final enabled =
                  widget.gameState.marketRestockEnabledItems.contains(resource);
              final minimum =
                  widget.gameState.marketRestockMinimums[resource] ?? 0;
              return Card(
                child: ListTile(
                  leading: Checkbox(
                    value: enabled,
                    onChanged: (value) {
                      widget.gameState.setMarketRestockRule(resource,
                          enabled: value ?? false, minimumToKeep: minimum);
                      (sheetContext as Element).markNeedsBuild();
                    },
                  ),
                  title: Text(resource),
                  subtitle: Text(
                      'Maison : ${widget.gameState.resourceAmount(resource)}'),
                  trailing: SizedBox(
                    width: 118,
                    child: Row(children: <Widget>[
                      IconButton(
                        onPressed: minimum <= 0
                            ? null
                            : () {
                                widget.gameState.setMarketRestockRule(resource,
                                    enabled: true, minimumToKeep: minimum - 1);
                                (sheetContext as Element).markNeedsBuild();
                              },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$minimum'),
                      IconButton(
                        onPressed: () {
                          widget.gameState.setMarketRestockRule(resource,
                              enabled: true, minimumToKeep: minimum + 1);
                          (sheetContext as Element).markNeedsBuild();
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// The selling view only shows live requests. The completed/expired history
  /// remains in the separate Book tab, while this section stays visible even
  /// when every sale slot is empty.
  Widget _activeMarketRequestsSection() {
    final now = DateTime.now();
    final requests = widget.gameState.marketRequests
        .where((request) => request.isOpen)
        .toList()
      ..sort((a, b) => a.customerReturnTime.compareTo(b.customerReturnTime));
    if (requests.isEmpty) {
      final nextAt = widget.gameState.marketNextRequestAt;
      final remaining = nextAt == null ? Duration.zero : nextAt.difference(now);
      final minutes = remaining.isNegative ? 0 : remaining.inMinutes;
      final seconds = remaining.isNegative ? 0 : remaining.inSeconds % 60;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Demandes habitantes',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                'Prochaine demande dans ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.',
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(value: 0),
              const SizedBox(height: 6),
              const Text('Le stock n’influence pas l’arrivée des demandes.'),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Demandes habitantes en attente',
            style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ...requests.map((request) {
          final totalSeconds = request.customerReturnTime
              .difference(request.createdAt)
              .inSeconds
              .clamp(1, 1 << 30)
              .toInt();
          final remaining = request.customerReturnTime.difference(now);
          final remainingSeconds =
              remaining.isNegative ? 0 : remaining.inSeconds;
          final progress =
              (remainingSeconds / totalSeconds).clamp(0.0, 1.0).toDouble();
          final minutes = remainingSeconds ~/ 60;
          final seconds = remainingSeconds % 60;
          final available = widget.gameState.marketShopStockAmount(
            request.shopId,
            request.requestedItemId,
          );
          final canSell = available >= request.requestedQuantity;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '${request.requestedQuantity} ${request.requestedItemId}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Client : ${request.customerName ?? 'Habitant non identifié'}'),
                  Text(
                      'Temps restant : ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 7),
                  Text(
                      'Stock boutique : $available/${request.requestedQuantity}'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: canSell
                        ? () => _message(
                              widget.gameState
                                  .sellMarketRequest(request)
                                  .message,
                            )
                        : null,
                    child: Text(canSell
                        ? 'Vendre · +${request.rewardBioPiles} bio-pile(s)'
                        : 'Stock insuffisant'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _marketShopsSection() {
    const labels = <String, String>{
      'restaurant': 'Restaurant',
      'home': 'Magasin du foyer',
      'equipment': 'Magasin d’équipement',
      'ptibug': 'Magasin P’TIBUG',
      'general': 'Ancien magasin généraliste',
      'ameublement': 'Ancien magasin du foyer',
    };
    final slots = widget.gameState.marketShopLimit;
    final shops = widget.gameState.marketShops
        .where((shop) => !shop.isPrimary)
        .toList(growable: false);
    final availableFirstShop = widget.gameState.marketLevel >= 2 &&
        !widget.gameState.firstFreeShopClaimed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Boutiques du Marché',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
                '${widget.gameState.marketShopCount}/$slots boutique(s) construite(s).'),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text(
                  'Boutique principale · ${labels[widget.gameState.primaryMarketShopSpecialization] ?? 'Fournitures'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  'Niveau ${widget.gameState.primaryMarketShopLevel} · ${widget.gameState.marketStock.length}/${widget.gameState.marketShopStockLimit(Zone0GameState.primaryMarketShopId)} piles · prix -${marketConfig.baseStorePricePenaltyPercent}%'),
              trailing: widget.gameState.primaryMarketShopLevel < 2
                  ? TextButton(
                      onPressed: () => _message(widget.gameState
                          .upgradeMarketShop(Zone0GameState.primaryMarketShopId)
                          .message),
                      child: const Text('Améliorer'),
                    )
                  : const Text('Max.'),
            ),
            _marketShopStockGrid(Zone0GameState.primaryMarketShopId),
            const SizedBox(height: 8),
            _shopDistributorCard(Zone0GameState.primaryMarketShopId),
            if (!widget.gameState.primaryMarketShopChosen)
              FilledButton.icon(
                onPressed: _showPrimaryShopPicker,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Choisir le type de la première boutique'),
              ),
            const Divider(),
            ...shops.map((shop) => Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(labels[shop.specialization] ?? 'Magasin',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          'Niveau ${shop.level} · ${shop.stock.length}/${shop.stockSlots} piles · gain +${marketConfig.specializedShopGainBonusPercent}%'),
                      trailing: shop.level < 2
                          ? TextButton(
                              onPressed: () => _message(widget.gameState
                                  .upgradeMarketShop(shop.id)
                                  .message),
                              child: const Text('Améliorer'),
                            )
                          : const Text('Max.'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _editMarketShopSlot(shop.id),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text(
                            'Gérer le stock (${shop.stock.length}/${shop.stockSlots})'),
                      ),
                    ),
                    _marketShopStockGrid(shop.id),
                    if (shop.specialization == 'ptibug')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "P’TIBUG de base disponibles : "
                          "Scarabé ${widget.gameState.marketShopStockAmount(shop.id, 'P’TIBUG Scarabé')} · "
                          "Hyme ${widget.gameState.marketShopStockAmount(shop.id, 'P’TIBUG Hyme')} · "
                          "Arac ${widget.gameState.marketShopStockAmount(shop.id, 'P’TIBUG Arac')}",
                        ),
                      ),
                    const SizedBox(height: 8),
                    _shopDistributorCard(shop.id),
                    const Divider(),
                  ],
                )),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(
                  math.max(0, slots - widget.gameState.marketShopCount),
                  (index) {
                if (availableFirstShop && index == 0) {
                  return OutlinedButton.icon(
                    onPressed: () => _showFirstShopPicker(),
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Construire le premier magasin'),
                  );
                }
                return OutlinedButton.icon(
                  onPressed: () => _showAdditionalShopPicker(),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Construire un magasin'),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketShopStockGrid(String shopId) {
    final stock = widget.gameState.marketStockForShop(shopId) ??
        const <Zone0InventoryStack>[];
    final limit = widget.gameState.marketShopStockLimit(shopId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 6),
        Text('Stock du magasin (${stock.length}/$limit)',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List<Widget>.generate(limit, (index) {
            final stack = index < stock.length ? stock[index] : null;
            return _MarketStockSlot(
              stack: stack,
              onTap: () => _editMarketShopSlot(shopId),
            );
          }),
        ),
      ],
    );
  }

  Widget _shopDistributorCard(String shopId) {
    final distributor = widget.gameState.marketDistributorForShop(shopId);
    if (distributor == null || !distributor.isBuilt) {
      return OutlinedButton.icon(
        onPressed: () => _showDistributorBuildSheet(shopId),
        icon: const Icon(Icons.precision_manufacturing_outlined),
        label: const Text('Construire le distributeur'),
      );
    }
    final limit = widget.gameState.distributorSlotsForShop(shopId);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Distributeur · niveau ${distributor.level}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(distributor.isBroken
                  ? 'En panne'
                  : 'Énergie : ${distributor.energy}/${marketConfig.distributorEnergyCapacity}'),
              if (distributor.repairEndsAt != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                    'Réparation · ${_countdownLabel(distributor.repairEndsAt!)}'),
                LinearProgressIndicator(
                    value: _repairProgress(distributor.repairEndsAt!)),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                OutlinedButton(
                  onPressed: () => _message(widget.gameState
                      .openBioBatteryForMarketDistributor(shopId: shopId)
                      .message),
                  child: const Text('Ouvrir une Bio-batterie'),
                ),
                if (distributor.isBroken)
                  FilledButton(
                    onPressed: () => _message(widget.gameState
                        .repairMarketDistributor(shopId: shopId)
                        .message),
                    child: const Text('Réparer'),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('Stock distributeur (${distributor.stock.length}/$limit)',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: List<Widget>.generate(
                    limit,
                    (index) => _MarketStockSlot(
                          stack: index < distributor.stock.length
                              ? distributor.stock[index]
                              : null,
                          onTap: () => _editMarketDistributorSlotForShop(
                              shopId,
                              index < distributor.stock.length
                                  ? distributor.stock[index]
                                  : null),
                        )),
              ),
            ]),
      ),
    );
  }

  Future<void> _showPrimaryShopPicker() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Text('Première boutique',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Text(
                  'Ce choix définit les produits que la boutique peut vendre.'),
              for (final entry in const <String, String>{
                'restaurant': 'Restaurant',
                'home': 'Magasin du foyer',
                'equipment': 'Magasin d’équipement',
                'ptibug': 'Magasin P’TIBUG'
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () {
                    final result =
                        widget.gameState.choosePrimaryMarketShop(entry.key);
                    _message(result.message);
                    if (result.success) Navigator.of(sheetContext).pop();
                  },
                ),
            ]),
          ),
        ),
      );

  Future<void> _editMarketShopSlot(String shopId) async {
    final stock = widget.gameState.marketStockForShop(shopId);
    if (stock == null) return;
    final resources = marketConfig.saleValues.keys
        .where((resource) =>
            widget.gameState.marketShopAccepts(shopId, resource) &&
            widget.gameState.resourceAmount(resource) > 0)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            const Text('Stock du magasin',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ...resources.map((resource) => ListTile(
                  title: Text(resource),
                  subtitle: Text(
                      'Maison : ${widget.gameState.resourceAmount(resource)}'),
                  trailing: Wrap(
                    spacing: 2,
                    children: <int>[1, 5, 10]
                        .map((amount) => TextButton(
                              onPressed: () {
                                final result = widget.gameState
                                    .transferToMarketShop(
                                        shopId, resource, amount);
                                _message(result.message);
                                if (result.success)
                                  Navigator.of(sheetContext).pop();
                              },
                              child: Text('+$amount'),
                            ))
                        .toList(),
                  ),
                )),
            if (stock.isNotEmpty) const Divider(),
            ...stock.map((stack) => ListTile(
                  title: Text('${stack.amount} ${stack.resource}'),
                  trailing: TextButton(
                    onPressed: () {
                      _message(widget.gameState
                          .returnMarketShopStock(shopId, stack)
                          .message);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Rendre'),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _showDistributorBuildSheet(String shopId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final distributor =
            widget.gameState.prepareMarketDistributorForShop(shopId);
        final ready =
            widget.gameState.isMarketDistributorReadyToBuildFor(shopId);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: <Widget>[
              const Text('Construire le distributeur',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                  'Coût : ${marketConfig.distributorConstructionBioBatteries} bio-batteries.'),
              ...marketConfig.distributorConstructionCost.entries
                  .map((entry) => Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                              '${entry.key} : ${distributor.constructionDeposits[entry.key] ?? 0}/${entry.value}'),
                          ...const <int>[1, 5, 10]
                              .map((amount) => OutlinedButton(
                                    onPressed: () {
                                      final result = widget.gameState
                                          .depositMarketDistributorMaterial(
                                              entry.key, amount,
                                              shopId: shopId);
                                      _message(result.message);
                                      if (result.success)
                                        Navigator.of(sheetContext).pop();
                                    },
                                    child: Text('+$amount'),
                                  )),
                        ],
                      )),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: ready
                    ? () {
                        final result = widget.gameState
                            .startMarketDistributorConstruction(shopId: shopId);
                        _message(result.message);
                        if (result.success) Navigator.of(sheetContext).pop();
                      }
                    : null,
                child: const Text('Commencer les travaux'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAdditionalShopPicker() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Text('Nouveau magasin',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              for (final entry in const <String, String>{
                'restaurant': 'Restaurant',
                'home': 'Magasin du foyer',
                'equipment': 'Magasin d’équipement',
                'ptibug': 'Magasin P’TIBUG'
              }.entries)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(entry.value),
                  onTap: () {
                    final result = widget.gameState.buildMarketShop(entry.key);
                    _message(result.message);
                    if (result.success) Navigator.of(sheetContext).pop();
                  },
                ),
            ]),
          ),
        ),
      );

  Future<void> _showFirstShopPicker() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Premier magasin spécialisé',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text('Choisissez la spécialisation du magasin offert.'),
                const SizedBox(height: 8),
                for (final entry in const <String, String>{
                  'restaurant': 'Restaurant',
                  'home': 'Magasin du foyer',
                  'equipment': 'Magasin d’équipement',
                  'ptibug': 'Magasin P’TIBUG',
                }.entries)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(entry.value),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final result =
                          widget.gameState.claimFirstMarketShop(entry.key);
                      _message(result.message);
                      if (result.success) Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _marketRequestBook() {
    final entries = widget.gameState.marketRequestLog.reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.gameState.marketLevel >= 3
                  ? 'Registre automatique · dernières 24 h'
                  : 'Livre des demandes · dernières 24 h',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (widget.gameState.marketLevel == 2 &&
                widget.gameState.marketAssignedPtipoteId == null)
              const Text(
                  'Un P’TIPOTE doit être affecté au Marché pour noter les nouvelles demandes.'),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Aucune demande enregistrée sur les dernières 24 heures.'),
              ),
            ...entries.map((entry) {
              final created =
                  '${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}';
              final deadlineMinutes =
                  entry.deadline.difference(entry.createdAt).inMinutes;
              final status = switch (entry.status) {
                MarketRequestStatus.completed => 'Répondue',
                MarketRequestStatus.expired => 'Expirée',
                _ => 'En attente',
              };
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.requestedQuantity == 0
                    ? entry.requestedItemId
                    : '${entry.requestedQuantity} ${entry.requestedItemId} · $status'),
                subtitle: Text(
                  '$created · délai $deadlineMinutes min · ${entry.customerName ?? 'Habitant non identifié'}'
                  '${entry.status == MarketRequestStatus.completed ? ' · ${entry.responder?.label ?? 'Vente'} · gain +${entry.rewardBioBatteries} bio-pile(s) 🟡' : ''}',
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showMarketActivityDetails(BuildContext context) {
    final config = marketConfig;
    final wellbeing = (widget.gameState.campWellbeing.clamp(0, 100) /
            100 *
            config.economicActivityWellbeingMaxPercent)
        .round();
    final heart = math.min(config.economicActivityHeartLevelCapPercent,
        widget.campHeartLevel * config.economicActivityHeartLevelPercent);
    final market = math.min(
        config.economicActivityMarketLevelCapPercent,
        widget.gameState.marketLevel *
            config.economicActivityMarketLevelPercent);
    final weather = widget.gameState.activeGlobalWeatherEvent == null
        ? 0
        : config.economicActivityWeatherPercent[
                widget.gameState.activeGlobalWeatherEvent!.intensity.name] ??
            0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Activité économique',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                  'Bien-être : +$wellbeing% / ${config.economicActivityWellbeingMaxPercent}%'),
              Text(
                  'Cœur du camp : +$heart% / ${config.economicActivityHeartLevelCapPercent}%'),
              Text(
                  'Marché : +$market% / ${config.economicActivityMarketLevelCapPercent}%'),
              Text('Météo : +$weather%'),
              const SizedBox(height: 8),
              Text(
                  'Total : ${widget.gameState.marketEconomicActivityPercent}% · à 100 %, la fréquence des demandes est doublée.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourcierContractsSection() {
    final contracts = widget.gameState.marketContracts
        .where((contract) =>
            contract.status == MarketContractStatus.offered ||
            contract.status == MarketContractStatus.accepted)
        .toList();
    if (contracts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Contrats du Sourcier',
            style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ...contracts.map((contract) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      contract.requestedItems.entries
                          .map((entry) => '${entry.value} ${entry.key}')
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        'Paiement de base : ${contract.rewardBioBatteries} bio-batterie(s)'),
                    Text(
                        'Confiance : ${widget.gameState.sourcierConfidence}/100 · paiement prévu ${(contract.rewardBioBatteries * widget.gameState.sourcierConfidencePaymentMultiplier).floor()}'),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: contract.status == MarketContractStatus.offered
                          ? () => _message(widget.gameState
                              .acceptMarketContract(contract)
                              .message)
                          : () => _message(widget.gameState
                              .deliverMarketContract(contract)
                              .message),
                      child: Text(
                          contract.status == MarketContractStatus.offered
                              ? 'Accepter'
                              : 'Livrer'),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _showSourcierLicenses() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final slots =
              marketConfig.licenseSlotsForLevel(widget.gameState.marketLevel);
          const names = <String, String>{
            'materials': 'Matériaux',
            'atelier': 'Fournitures',
            'structure': 'Meubles et structures',
            'ptibug': 'P’TIBUG',
          };
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
                Text('Licences du Sourcier',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                    '$slots slot${slots > 1 ? 's' : ''} disponible${slots > 1 ? 's' : ''} · 80 % des futurs contrats sont orientés par les licences.'),
                const SizedBox(height: 8),
                ...names.entries.map((entry) {
                  final active =
                      widget.gameState.activeMarketLicenses.contains(entry.key);
                  final full =
                      widget.gameState.activeMarketLicenses.length >= slots;
                  final cost = active
                      ? 0
                      : full
                          ? marketConfig.licenseCostBioBatteries +
                              marketConfig.licenseChangeCostBioBatteries
                          : marketConfig.licenseCostBioBatteries;
                  return ListTile(
                    title: Text(entry.value),
                    subtitle: Text(active
                        ? 'Active'
                        : full
                            ? 'Remplace une licence · $cost bio-batteries'
                            : '$cost bio-batteries'),
                    trailing: active
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.add_circle_outline),
                    onTap: active
                        ? null
                        : () {
                            final result =
                                widget.gameState.setMarketLicense(entry.key);
                            _message(result.message);
                            if (result.success)
                              Navigator.of(sheetContext).pop();
                          },
                  );
                }),
              ],
            ),
          );
        },
      );

  void _message(String value) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));

  Future<void> _editMarketSlot(Zone0InventoryStack? initialStack) async {
    final initialResource = initialStack?.resource;
    final resources = marketConfig.saleValues.keys
        .where(
          (resource) =>
              widget.gameState.resourceAmount(resource) > 0 ||
              resource == initialResource,
        )
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
            Text(
              initialResource ?? 'Ajouter au Marché',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...resources.map(
              (resource) => ListTile(
                leading: Icon(_resourceIcon(resource)),
                title: Text(resource),
                subtitle: Text(
                  'Maison : ${widget.gameState.resourceAmount(resource)} · '
                  '${widget.gameState.isEquipmentResource(resource) ? 'équipement : 1 par case' : '10 par case'}',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: <int>[1, 5, 10]
                      .map(
                        (amount) => TextButton(
                          onPressed: () {
                            final result = widget.gameState.transferToMarket(
                              resource,
                              amount,
                            );
                            _message(result.message);
                            if (result.success) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: Text('+$amount'),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            if (initialResource != null) ...<Widget>[
              const Divider(),
              OutlinedButton.icon(
                onPressed: () {
                  _message(
                    widget.gameState.returnMarketStock(initialStack!).message,
                  );
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

  Future<void> _editMarketDistributorSlot(
    Zone0InventoryStack? initialStack,
  ) =>
      _editMarketDistributorSlotForShop(
        Zone0GameState.primaryMarketShopId,
        initialStack,
      );

  Future<void> _editMarketDistributorSlotForShop(
    String shopId,
    Zone0InventoryStack? initialStack,
  ) async {
    final initialResource = initialStack?.resource;
    final distributor = widget.gameState.marketDistributorForShop(shopId);
    if (distributor == null) return;
    final resources = marketConfig.saleValues.keys
        .where(
          (resource) =>
              widget.gameState.marketShopAccepts(shopId, resource) &&
              (widget.gameState.resourceAmount(resource) > 0 ||
                  resource == initialResource),
        )
        .toList(growable: false);
    if (resources.isEmpty) {
      _message('Aucun produit compatible dans le stock Maison.');
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
            Text(
              initialResource ?? 'Ajouter au Distributeur',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
                'Type ${distributor.type.label} · ${distributor.type.stockDescription}'),
            const SizedBox(height: 8),
            ...resources.map(
              (resource) => ListTile(
                leading: Icon(_resourceIcon(resource)),
                title: Text(resource),
                subtitle: Text(
                  'Maison : ${widget.gameState.resourceAmount(resource)} · '
                  '${widget.gameState.isEquipmentResource(resource) ? 'équipement : 1 par case' : '10 par case'}',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: <int>[1, 5, 10]
                      .map(
                        (amount) => TextButton(
                          onPressed: () {
                            final result = widget.gameState
                                .transferToMarketDistributor(resource, amount,
                                    shopId: shopId);
                            _message(result.message);
                            if (result.success) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: Text('+$amount'),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            if (initialStack != null) ...<Widget>[
              const Divider(),
              OutlinedButton.icon(
                onPressed: () {
                  _message(
                    widget.gameState
                        .returnMarketDistributorStock(initialStack,
                            shopId: shopId)
                        .message,
                  );
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
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.32),
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
                child: Text(
                  '${stack!.amount}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            if (filled)
              Positioned(
                left: 6,
                right: 6,
                bottom: 7,
                child: Text(
                  stack!.resource,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
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

class _StarterPTibugChoiceOption extends StatefulWidget {
  const _StarterPTibugChoiceOption({
    required this.species,
    required this.title,
    required this.description,
    required this.onSelected,
  });

  final PTibugSpecies species;
  final String title;
  final String description;
  final VoidCallback onSelected;

  @override
  State<_StarterPTibugChoiceOption> createState() =>
      _StarterPTibugChoiceOptionState();
}

class _StarterPTibugChoiceOptionState extends State<_StarterPTibugChoiceOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  Color get _color => switch (widget.species) {
        PTibugSpecies.scarabe => const Color(0xFF71889B),
        PTibugSpecies.hyme => const Color(0xFFE0B53F),
        PTibugSpecies.arac => const Color(0xFFC65A5A),
      };

  IconData get _icon => switch (widget.species) {
        PTibugSpecies.scarabe => Icons.shield_outlined,
        PTibugSpecies.hyme => Icons.hive_outlined,
        PTibugSpecies.arac => Icons.hub_outlined,
      };

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.onSelected,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  child: Icon(_icon, size: 29),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(widget.description),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: _color),
            ],
          ),
        ),
      ),
    );
  }
}

class PTibugNurseryPage extends StatefulWidget {
  const PTibugNurseryPage({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
    required this.campHeartState,
  });
  final Zone0GameState gameState;
  final int campHeartLevel;
  final CampHeartState campHeartState;

  @override
  State<PTibugNurseryPage> createState() => _PTibugNurseryPageState();
}

class _PTibugNurseryPageState extends State<PTibugNurseryPage> {
  Timer? _timer;
  bool _starterChoiceDialogVisible = false;

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_changed);
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => widget.gameState.resolvePTibugProduction(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStarterChoiceIfNeeded();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.gameState.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    _showStarterChoiceIfNeeded();
  }

  Future<void> _showStarterChoiceIfNeeded() async {
    if (!mounted ||
        _starterChoiceDialogVisible ||
        !widget.gameState.hasPendingStarterPTibugChoice) {
      return;
    }
    _starterChoiceDialogVisible = true;
    final species = await showDialog<PTibugSpecies>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choisis ton premier P’TIBUG'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: PTibugSpecies.values
                  .map(
                    (species) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StarterPTibugChoiceOption(
                        species: species,
                        title: pTibugConfig.species[species]!.displayName,
                        description:
                            pTibugConfig.patterns[species]!.description,
                        onSelected: () =>
                            Navigator.of(dialogContext).pop(species),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    if (!mounted || species == null) {
      _starterChoiceDialogVisible = false;
      return;
    }

    final result = widget.gameState.chooseStarterPTibugPattern(species);
    if (!result.success) {
      _starterChoiceDialogVisible = false;
      _message(result.message);
      return;
    }

    final openPlans = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${pTibugConfig.species[species]!.displayName} choisi'),
        content: const Text(
          'Le Pattern est maintenant prêt dans les Plans du Kernel. Les autres espèces seront découvertes plus tard grâce au Kernel ou au Sourcier du savoir. Active ce Pattern avant de créer ton premier P’TIBUG.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ouvrir les Plans'),
          ),
        ],
      ),
    );
    _starterChoiceDialogVisible = false;
    if (!mounted || openPlans != true) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KernelPage(
          gameState: widget.gameState,
          campHeartState: widget.campHeartState,
          initialTabIndex: 3,
        ),
      ),
    );
  }

  void _message(String message) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nurserie P’TIBUG'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Aperçu'),
              Tab(text: 'Collection'),
              Tab(text: 'Créer'),
              Tab(text: 'Données'),
              Tab(text: 'Amélioration'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _overview(),
            _collection(),
            _creation(),
            _dataAndModules(),
            _improvement(),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    final nursery = widget.gameState.plaineNurseryTerritory;
    final producing = widget.gameState.pTibugsForTerritory(nursery.id);
    final consumption =
        widget.gameState.pTibugTerritoryDailyConsumption(nursery);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Nurserie niveau ${widget.gameState.plaineNurseryLevel}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  '${producing.length}/${widget.gameState.pTibugTerritoryCapacity(nursery)} P’TIBUG actifs',
                ),
                Text(
                    'Niveau maximum : ${pTibugConfig.territory.nurseryMaximumLevel} · capacité ${widget.gameState.pTibugTerritoryCapacity(nursery)}'),
                Text(
                    'Organique local : ${nursery.resourceAmount('Organique')} · -${consumption.organicPerDay}/jour'),
                Text(
                    'Minéral local : ${nursery.resourceAmount('Minéral')} · -${consumption.mineralPerDay}/jour'),
                Text(
                    'Énergie locale : ${nursery.localEnergy} · -${consumption.energyPerDay}/jour'),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                    value: (nursery.localEnergy /
                            math.max(10, consumption.energyPerDay * 2))
                        .clamp(0.0, 1.0)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                      onPressed: () => _showNurseryTransfer(nursery),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Alimenter')),
                  FilledButton.icon(
                      onPressed: widget.gameState.bioBatteries <= 0
                          ? null
                          : () => _message(widget.gameState
                              .openBioBatteryForPTibugTerritory(nursery.id)
                              .message),
                      icon: const Icon(Icons.battery_charging_full_outlined),
                      label: const Text('Ouvrir une Bio-batterie')),
                ]),
                const Text(
                    'Chaque P’TIBUG conserve sa production jusqu’à sa récolte.'),
              ],
            ),
          ),
        ),
        if (widget.gameState.pTibugArmatures.any((item) => item.isCrafting))
          _armatureInProgressCard(),
        if (producing.isNotEmpty) ...<Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              'P’TIBUG en production',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          ...producing.map(_productionOverviewCard),
        ],
        ...producing.where(widget.gameState.canEvolvePTibug).map(
              (bug) => Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text('Faire évoluer ${bug.displayName}'),
                  subtitle: const Text(
                      'Conserve niveau, Trait I, Modules et identité. Débloque le second Trait.'),
                  trailing: FilledButton(
                    onPressed: () => _chooseTankForEvolution(bug),
                    child: const Text('Évoluer'),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _chooseTankForEvolution(PTibug bug) async {
    final tankId =
        await _pickFreeCultivationTank('Choisir une cuve pour l’Évolution');
    if (tankId == null || !mounted) return;
    _message(widget.gameState
        .startPTibugEvolution(bug: bug, tankId: tankId)
        .message);
  }

  Widget _improvement() => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              children: <Widget>[
                _moduleCapacityUpgradeCard(),
                const SizedBox(height: 10),
                _BuildingViabilityCard(
                  gameState: widget.gameState,
                  buildingId: Zone0GameState.plaineNurseryTerritoryId,
                ),
              ],
            ),
          ),
          Expanded(
            child: _BuildingUpgradeTab(
              gameState: widget.gameState,
              targetId: 'plaineNursery',
              title: 'Améliorer la Nurserie',
              description:
                  'Ajoute des emplacements P’TIBUG. La capacité des Modules est une amélioration globale, réglée ci-dessus.',
              currentEffects: <String>[
                '${widget.gameState.pTibugActiveSlots} slot(s) actif(s)',
                '${widget.gameState.maxModulesPerPTibug} module(s) par P’TIBUG',
              ],
              nextEffects: <String>[
                '${pTibugConfig.slotsForLevel(widget.gameState.plaineNurseryLevel + 1)} slot(s) actif(s)',
                'Capacité Modules globale inchangée',
              ],
              campHeartLevel: widget.campHeartLevel,
            ),
          ),
        ],
      );

  Widget _moduleCapacityUpgradeCard() {
    final config = pTibugConfig.moduleCapacity;
    final next = widget.gameState.pTibugModuleCapacityLevel + 1;
    final maximum = next > config.maximumUpgrades;
    final materials =
        config.materialCostsByLevel[next] ?? const <String, int>{};
    final data =
        config.dataCostsByLevel[next] ?? const <PTibugDataFamily, int>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                  'Capacité globale des Modules : ${widget.gameState.maxModulesPerPTibug}/${config.capacityForLevel(config.maximumUpgrades)}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(maximum
                  ? 'Niveau maximum atteint.'
                  : 'Prochain niveau : ${config.capacityForLevel(next)} Modules par P’TIBUG.'),
              if (!maximum)
                Text(
                    'Matériaux : ${materials.entries.map((entry) => '${entry.key} ${entry.value}/${widget.gameState.resourceAmount(entry.key)}').join(' · ')}\nBio-batteries : ${config.bioBatteryCostsByLevel[next] ?? 0}/${widget.gameState.bioBatteries}\nDonnées : ${data.entries.map((entry) => '${entry.key.name} ${entry.value}/${widget.gameState.pTibugDataReserve[entry.key] ?? 0}').join(' · ')}'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: maximum ? null : _confirmModuleCapacityUpgrade,
                child: const Text('Lancer l’amélioration'),
              ),
            ]),
      ),
    );
  }

  Future<void> _confirmModuleCapacityUpgrade() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Améliorer la capacité des Modules ?'),
        content: const Text(
            'Les matériaux, Bio-batteries et données affichés seront consommés une seule fois. Cette amélioration est globale pour tous les P’TIBUG.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _message(widget.gameState.upgradePTibugModuleCapacity().message);
    }
  }

  Future<void> _showNurseryTransfer(PTibugTerritoryBuilding building) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                const SizedBox(
                  width: double.infinity,
                  child: Text('Alimenter la Nurserie',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                ...(<String>['Organique', 'Minéral'].expand(
                  (resource) => const <int>[1, 5, 10].map(
                    (amount) => OutlinedButton(
                      onPressed:
                          widget.gameState.resourceAmount(resource) < amount
                              ? null
                              : () {
                                  final result = widget.gameState
                                      .transferResourcesToPTibugTerritory(
                                    territoryId: building.id,
                                    resources: <String, int>{resource: amount},
                                  );
                                  Navigator.of(sheetContext).pop();
                                  _message(result.message);
                                },
                      child: Text('+$amount $resource'),
                    ),
                  ),
                )),
              ],
            ),
          ),
        ),
      );

  Widget _armatureInProgressCard() {
    final order =
        widget.gameState.pTibugArmatures.firstWhere((item) => item.isCrafting);
    final config = pTibugConfig.species[order.species]!;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_speciesIcon(order.species))),
        title: Text('Armature ${config.displayName} en fabrication'),
        subtitle: Text('Fin dans ${_countdownLabel(order.completesAt)}'),
      ),
    );
  }

  Widget _productionOverviewCard(PTibug bug) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  CircleAvatar(
                      radius: 28, child: Icon(_speciesIcon(bug.species))),
                  Positioned(
                    right: -12,
                    top: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${bug.storedAmount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.gameState.pTibugBiologicalNameFor(bug),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                        'Réserve : ${bug.storedAmount}/${widget.gameState.pTibugCapacityFor(bug)}'),
                    Text(
                      bug.nextProductionAt == null
                          ? 'Cycle en attente'
                          : _countdownLabel(bug.nextProductionAt!),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: bug.storedAmount == 0
                          ? null
                          : () => _message(
                                widget.gameState
                                    .collectPTibugProductionFor(bug)
                                    .message,
                              ),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Récolter'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _creation() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Patterns P’TIBUG',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              'Les Patterns se découvrent et s’activent depuis le Kernel.',
            ),
          ),
          ...PTibugSpecies.values.map((species) {
            final config = pTibugConfig.species[species]!;
            final pattern = pTibugConfig.patterns[species]!;
            final state = widget.gameState.pTibugPatternState(species);
            final researchPatternId = 'ptibug-species-${species.name}';
            final researchActive = widget.gameState.isPTibugPatternActive(
              researchPatternId,
            );
            final isActive = state == KernelPlanState.active || researchActive;
            final organicCost = config.creationCost['Organique'] ?? 0;
            final mineralCost = config.creationCost['Minéral'] ?? 0;
            final organicStock = widget.gameState.resourceAmount('Organique');
            final mineralStock = widget.gameState.resourceAmount('Minéral');
            final batteryStock = widget.gameState.bioBatteries;
            final creationRequirements = <String, int>{
              ...config.creationCost,
              'Bio-batteries': config.creationBioBatteryCost,
            };
            final maxCreatable = _maxProductionCount(
              creationRequirements,
              (resourceId) => resourceId == 'Bio-batteries'
                  ? batteryStock
                  : widget.gameState.resourceAmount(resourceId),
            );
            final canCreate = isActive &&
                maxCreatable > 0 &&
                !widget.gameState.pTibugArmatures
                    .any((item) => item.isCrafting);
            return _ProductionRecipeCard(
              title: 'Pattern ${config.displayName}',
              leadingIcon: _speciesIcon(species),
              trailingIcon:
                  isActive ? Icons.check_circle_outline : Icons.lock_outline,
              description: pattern.description,
              slots: <_ProductionSlotData>[
                _ProductionSlotData(
                  icon: Icons.eco_outlined,
                  label: 'Matériaux',
                  value:
                      'Organique : $organicCost / $organicStock\nMinéral : $mineralCost / $mineralStock',
                ),
                _ProductionSlotData(
                  icon: Icons.battery_charging_full_outlined,
                  label: 'Bio-batteries',
                  value: '${config.creationBioBatteryCost} / $batteryStock',
                ),
              ],
              details: <String>[
                'Résultat : 1 Armature ${config.displayName}',
                'Temps de fabrication : ${pTibugConfig.cultivation.armatureMinutes ~/ 60} h',
                'Créations possibles avec le stock : $maxCreatable',
              ],
              prerequisiteLabel: isActive
                  ? 'Pré-requis : Pattern actif dans le Kernel'
                  : 'Pré-requis : ${researchActive ? 'Pattern scientifique actif' : _patternStateLabel(state)}',
              prerequisiteMet: isActive,
              primaryActionLabel: 'Fabriquer une Armature',
              primaryActionIcon: Icons.auto_awesome_outlined,
              primaryActionEnabled: canCreate,
              onPrimaryAction: () => _message(
                  widget.gameState.startPTibugCreation(species).message),
            );
          }),
          const SizedBox(height: 18),
          const Text('Armatures disponibles',
              style: TextStyle(fontWeight: FontWeight.w900)),
          if (!widget.gameState.pTibugArmatures.any((item) => item.isCompleted))
            const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 8),
                child: Text(
                    'Une Armature terminée pourra être placée dans une cuve.')),
          ...widget.gameState.pTibugArmatures
              .where((item) => item.isCompleted)
              .map((armature) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          child: Icon(_speciesIcon(armature.species))),
                      title: Text(
                          '${pTibugConfig.species[armature.species]!.displayName} · Armature prête'),
                      subtitle: Text(
                          'Fabriquée le ${armature.createdAt.day}/${armature.createdAt.month}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (tankId) => _message(widget.gameState
                            .startPTibugCultivation(
                                armatureId: armature.id, tankId: tankId)
                            .message),
                        itemBuilder: (_) => widget
                            .gameState.builtCultivationTanks
                            .where((tank) => tank.currentOperationId == null)
                            .map((tank) => PopupMenuItem(
                                value: tank.id,
                                child: Text(
                                    'Placer en cuve ${tank.slotIndex + 1}')))
                            .toList(),
                        child: const DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(
                              side: BorderSide(color: Color(0xff817D66)),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text('Placer en cuve'),
                          ),
                        ),
                      ),
                    ),
                  )),
          const SizedBox(height: 18),
          const Text('Cuves de Cultivation',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                  'Les réserves sont locales à chaque cuve. Une Bio-batterie fournit 10 Énergies.')),
          ...List<Widget>.generate(widget.gameState.cultivationTankSlotCount,
              (index) {
            final tank =
                widget.gameState.cultivationTankForId('ptibug-tank-$index');
            return tank == null
                ? const SizedBox.shrink()
                : _cultivationTankCard(tank);
          }),
        ],
      );

  Widget _cultivationTankCard(PTibugCultivationTank tank) {
    final operation = widget.gameState.cultivationOperationForTank(tank.id);
    final species = operation?.species;
    final config = pTibugConfig.cultivation;
    final built = tank.isBuilt;
    final constructReady =
        widget.gameState.cultivationTankConstructionReady(tank);
    final operationLabel = operation == null
        ? null
        : _cultivationOperationTitle(operation).split(' · ').first;
    final label = switch (tank.status) {
      PTibugCultivationTankStatus.unbuilt => 'Non construite',
      PTibugCultivationTankStatus.underConstruction => 'En construction',
      PTibugCultivationTankStatus.available => 'Disponible',
      PTibugCultivationTankStatus.active =>
        '${operationLabel ?? 'Opération'} active',
      PTibugCultivationTankStatus.pausedMissingResources => 'En pause',
      PTibugCultivationTankStatus.completed =>
        '${operationLabel ?? 'Opération'} terminée',
    };
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Cuve ${tank.slotIndex + 1} · $label',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            if (!built &&
                tank.status !=
                    PTibugCultivationTankStatus.underConstruction) ...<Widget>[
              Text(
                  'Construction : ${config.tankConstructionCost.entries.map((entry) => '${entry.key} ${tank.constructionDeposits[entry.key] ?? 0}/${entry.value}').join(' · ')} · Bio-batteries ${tank.constructionDeposits['Bio-batteries'] ?? 0}/${config.tankConstructionBioBatteries}'),
              Wrap(spacing: 6, children: <Widget>[
                ...<String>['Organique', 'Minéral'].map((resource) =>
                    OutlinedButton(
                        onPressed: () => _message(widget.gameState
                            .depositCultivationTankConstruction(
                                tankId: tank.id,
                                resources: <String, int>{resource: 1}).message),
                        child: Text('+$resource'))),
                OutlinedButton(
                    onPressed: () => _message(widget.gameState
                        .depositCultivationTankConstruction(
                            tankId: tank.id,
                            resources: const <String, int>{},
                            bioBatteriesAmount: 1)
                        .message),
                    child: const Text('+ Bio-batterie')),
              ]),
              FilledButton(
                  onPressed: constructReady
                      ? () => _message(widget.gameState
                          .startCultivationTankConstruction(tank.id)
                          .message)
                      : null,
                  child: const Text('Commencer les travaux')),
            ] else if (tank.status ==
                PTibugCultivationTankStatus.underConstruction)
              Text(
                  'Fin dans ${tank.constructionEndsAt == null ? '—' : _countdownLabel(tank.constructionEndsAt!)}')
            else if (operation == null)
              const Text(
                  'Place une Armature, infuse un Trait ou fais évoluer un P’TIBUG.')
            else ...<Widget>[
              Text(_cultivationOperationTitle(operation),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  '${pTibugConfig.species[species]!.displayName} · ${operation.activeSecondsCompleted ~/ 3600} h / ${operation.activeSecondsRequired ~/ 3600} h'),
              LinearProgressIndicator(
                  value: (operation.activeSecondsCompleted /
                          math.max(1, operation.activeSecondsRequired))
                      .clamp(0.0, 1.0)),
              Text(
                  'Organique : ${tank.organicStored.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Organique').toStringAsFixed(1)} h) · Minéral : ${tank.mineralStored.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Minéral').toStringAsFixed(1)} h) · Énergie : ${tank.energyStored.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Énergie').toStringAsFixed(1)} h)'),
              if (operation.pauseReason != null)
                Text('Pause : ${operation.pauseReason}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (operation.reservedDataCells.isNotEmpty)
                Text(
                    'Cellules réservées : ${operation.reservedDataCells.entries.map((entry) => '${_dataFamilyTitle(entry.key)} ${entry.value}').join(' · ')}'),
              Wrap(spacing: 6, children: <Widget>[
                OutlinedButton(
                    onPressed: () => _message(widget.gameState
                        .addCultivationTankResources(
                            tankId: tank.id, resource: 'Organique', amount: 5)
                        .message),
                    child: const Text('+5 Organique')),
                OutlinedButton(
                    onPressed: () => _message(widget.gameState
                        .addCultivationTankResources(
                            tankId: tank.id, resource: 'Minéral', amount: 5)
                        .message),
                    child: const Text('+5 Minéral')),
                OutlinedButton(
                    onPressed: () => _message(widget.gameState
                        .openBioBatteryForCultivationTank(tank.id)
                        .message),
                    child: const Text('Ouvrir une Bio-batterie')),
                if (operation.status == PTibugCultivationOperationStatus.active)
                  FilledButton(
                      onPressed: () => _message(widget.gameState
                          .applyCultivationTap(tank.id)
                          .message),
                      child: Text(
                          'Tapoter (+${pTibugConfig.cultivation.tapBonusFor(operation.type)} min)')),
                if (operation.isCompleted)
                  FilledButton(
                      onPressed: () =>
                          _completeCultivationTank(tank.id, operation),
                      child: Text(_cultivationCompletionAction(operation))),
                if (!operation.isCompleted)
                  TextButton(
                      onPressed: () => _message(widget.gameState
                          .cancelPTibugCultivation(tank.id)
                          .message),
                      child: const Text('Annuler')),
              ]),
            ],
          ]),
    ));
  }

  Future<void> _completeCultivationTank(
    String tankId,
    PTibugCultivationOperation operation,
  ) async {
    final result = widget.gameState.openCultivationTank(tankId);
    _message(result.message);
    if (!result.success ||
        operation.type != PTibugCultivationOperationType.cultivation ||
        operation.resultPtibugId == null ||
        !mounted) {
      return;
    }
    final bug = widget.gameState.pTibugs
        .where((item) => item.id == operation.resultPtibugId)
        .firstOrNull;
    if (bug == null) return;
    await _renamePTibug(bug, context);
  }

  String _cultivationOperationTitle(PTibugCultivationOperation operation) {
    final target = operation.targetPtibugId == null
        ? null
        : widget.gameState.pTibugs
            .where((bug) => bug.id == operation.targetPtibugId)
            .firstOrNull;
    return switch (operation.type) {
      PTibugCultivationOperationType.cultivation =>
        'Cultivation d’un nouveau P’TIBUG',
      PTibugCultivationOperationType.traitInfusion =>
        'Infusion · ${target?.displayName ?? 'P’TIBUG'} · ${pTibugConfig.traitDefinitionFor(operation.targetTraitId ?? '')?.displayName ?? operation.targetTraitId ?? 'Trait'} rang ${operation.targetTraitRank ?? 1}',
      PTibugCultivationOperationType.evolution =>
        'Évolution · ${target?.displayName ?? 'P’TIBUG'}',
    };
  }

  String _cultivationCompletionAction(PTibugCultivationOperation operation) =>
      switch (operation.type) {
        PTibugCultivationOperationType.cultivation => 'Ouvrir la cuve',
        PTibugCultivationOperationType.traitInfusion => 'Terminer l’Infusion',
        PTibugCultivationOperationType.evolution => 'Achever l’Évolution',
      };

  String _cultivationStatusFor(PTibug bug) {
    final operation = widget.gameState.cultivationOperationForPTibug(bug.id);
    if (operation == null) return 'opération en préparation';
    final remaining = math.max(
        0, operation.activeSecondsRequired - operation.activeSecondsCompleted);
    return '${_cultivationOperationTitle(operation)} · ${remaining ~/ 3600} h actives restantes';
  }

  String _patternStateLabel(KernelPlanState state) => switch (state) {
        KernelPlanState.unknown => 'Pattern inconnu',
        KernelPlanState.discovered => 'Plan découvert',
        KernelPlanState.ready => 'À activer dans le Kernel',
        KernelPlanState.active => 'Actif',
      };

  Widget _collection() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Collection',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text(
              'Tape un P’TIBUG pour consulter et ajuster son équipement.'),
          const SizedBox(height: 10),
          if (widget.gameState.pTibugs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Aucun P’TIBUG créé pour le moment.'),
            ),
          ...widget.gameState.pTibugs.map(
            (bug) => Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showPTibugLoadout(bug),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          CircleAvatar(child: Icon(_speciesIcon(bug.species))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.gameState.pTibugBiologicalNameFor(bug),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          Text(
                            'Niv. ${bug.level}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${pTibugConfig.species[bug.species]!.displayName} · ${bug.styleVariant}',
                      ),
                      Text(
                        'XP ${bug.xp} · Réserve ${bug.storedAmount}/${widget.gameState.pTibugCapacityFor(bug)}',
                      ),
                      if (_hasSmartSensor(bug))
                        Text(
                          'Cellules : ${bug.storedDataCells.length}/${pTibugConfig.territory.dataCellStorageCapacity}',
                        ),
                      const SizedBox(height: 8),
                      if (bug.biologicalTraitId != null)
                        _LoadoutPill(
                          icon: Icons.biotech_outlined,
                          label:
                              '${pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!)?.displayName ?? bug.biologicalTraitId} ${bug.biologicalTraitLevel}',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      if (bug.biologicalTraitId != null)
                        const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          _LoadoutPill(
                            icon: Icons.auto_awesome_outlined,
                            label: _traitLabel(bug.traitDataId),
                            color: _traitColor(
                              _traitFor(bug)?.grade,
                              _traitFor(bug),
                            ),
                          ),
                          ...List<Widget>.generate(
                            widget.gameState.maxModulesPerPTibug,
                            (index) {
                              final equippedInstances =
                                  widget.gameState.pTibugModuleInstances
                                      .where(
                                        (instance) =>
                                            instance.equippedPTibugId == bug.id,
                                      )
                                      .toList();
                              final moduleInstance =
                                  index < equippedInstances.length
                                      ? equippedInstances[index]
                                      : null;
                              final module = index < bug.equippedModules.length
                                  ? bug.equippedModules[index]
                                  : null;
                              return _LoadoutPill(
                                icon: moduleInstance == null && module == null
                                    ? Icons.add_circle_outline
                                    : _moduleIcon(
                                        moduleInstance?.type ?? module!),
                                label: moduleInstance != null
                                    ? '${_moduleTitle(moduleInstance.type)} ${moduleInstance.qualityLevel}'
                                    : module == null
                                        ? 'Module libre'
                                        : _moduleTitle(module),
                                color: moduleInstance == null && module == null
                                    ? Theme.of(context).colorScheme.outline
                                    : Theme.of(context).colorScheme.secondary,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.gameState.isPTibugInCultivation(bug)
                            ? 'En cuve · ${_cultivationStatusFor(bug)}'
                            : bug.assignedBuildingId == null
                                ? 'Inactif · ${bug.inactiveReason ?? 'en attente d’affectation'}'
                                : '${widget.gameState.territoryBuildingForId(bug.assignedBuildingId)?.kind == PTibugTerritoryKind.nursery ? 'Nurserie de la Plaine' : 'Refuge'} · ${bug.inactiveReason ?? (bug.nextProductionAt == null ? 'cycle en attente' : 'prochain cycle ${_countdownLabel(bug.nextProductionAt!)}')}',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            bug.storedAmount == 0 && bug.storedDataCells.isEmpty
                                ? null
                                : () => _message(
                                      widget.gameState
                                          .collectPTibugProductionFor(bug)
                                          .message,
                                    ),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Récolter'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: widget.gameState.isPTibugInCultivation(bug)
                            ? null
                            : () => _showTerritoryAssignment(bug),
                        icon: const Icon(Icons.swap_horiz_outlined),
                        label: const Text('Affecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Future<void> _showTerritoryAssignment(PTibug bug) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final destinations = widget.gameState.activePTibugTerritories;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                const ListTile(title: Text('Choisir une affectation')),
                ...destinations.map((building) {
                  final used = widget.gameState
                      .pTibugsForTerritory(building.id)
                      .where((item) => item.id != bug.id)
                      .length;
                  final capacity =
                      widget.gameState.pTibugTerritoryCapacity(building);
                  return ListTile(
                    enabled: used < capacity,
                    title: Text(building.kind == PTibugTerritoryKind.nursery
                        ? 'Nurserie · Plaine'
                        : 'Refuge · ${lisiereForageConfig.biomes[building.biome]!.label}'),
                    subtitle: Text('$used/$capacity emplacement(s) occupé(s)'),
                    onTap: used >= capacity
                        ? null
                        : () {
                            final result = widget.gameState
                                .assignPTibugToTerritory(bug, building.id);
                            Navigator.of(sheetContext).pop();
                            _message(result.message);
                          },
                  );
                }),
                ListTile(
                  title: const Text('P’TIBUG inactifs'),
                  subtitle: const Text('Ne produit ni ne consomme.'),
                  onTap: () {
                    final result = widget.gameState.setPTibugInactive(bug);
                    Navigator.of(sheetContext).pop();
                    _message(result.message);
                  },
                ),
              ],
            ),
          );
        },
      );

  Widget _dataAndModules() {
    final traits = widget.gameState.pTibugTraitData;
    final moduleInstances = widget.gameState.pTibugModuleInstances;
    final capsules = widget.gameState.pTibugCapsules;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _KernelDataCellsCard(gameState: widget.gameState),
        const SizedBox(height: 18),
        const SizedBox(height: 18),
        const Text(
          'Traits biologiques permanents',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Un seul Trait peut transformer durablement chaque P’TIBUG.',
        ),
        const SizedBox(height: 10),
        ...pTibugConfig.activeTraitDefinitions.map((definition) {
          final patternId = 'ptibug-trait-${definition.id}';
          final active = widget.gameState.isPTibugPatternActive(patternId);
          final progress = widget.gameState.pTibugPatternProgress[patternId];
          final masteryLevel = ((progress?.masteryLevel ?? 0).clamp(
            0,
            definition.maxLevel,
          ));
          final candidates = widget.gameState.pTibugs.where((bug) {
            final targetLevel = widget.gameState.nextPTibugTraitLevelFor(
              bug,
              definition.id,
            );
            return targetLevel != null && targetLevel <= masteryLevel;
          }).toList();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${definition.displayName} · maîtrise $masteryLevel/${definition.maxLevel}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(definition.description),
                  const SizedBox(height: 8),
                  Text(
                    active
                        ? 'Chaque rang est infusé dans une cuve. Les Cellules du rang cible sont réservées au lancement ; Organique, Minéral et Énergie sont consommés progressivement.'
                        : 'Pattern à découvrir et maîtriser dans le Kernel.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: active && candidates.isNotEmpty
                        ? () => _pickPTibugForPermanentTrait(definition.id)
                        : null,
                    icon: const Icon(Icons.biotech_outlined),
                    label: Text(
                      candidates.isEmpty
                          ? 'Aucun P’TIBUG compatible'
                          : 'Appliquer à un P’TIBUG',
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        const Text(
          'Modules fabriqués',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        if (moduleInstances.isEmpty)
          const Card(child: ListTile(title: Text('Aucun Module fabriqué.'))),
        ...moduleInstances.map((instance) {
          final owner = widget.gameState.pTibugs
              .where((bug) => bug.id == instance.equippedPTibugId)
              .firstOrNull;
          return Card(
            child: ListTile(
              leading: Icon(_moduleIcon(instance.type)),
              title: Text(
                  '${_moduleTitle(instance.type)} niveau ${instance.qualityLevel}'),
              subtitle: Text(
                owner == null
                    ? 'Disponible'
                    : 'Équipé par ${widget.gameState.pTibugBiologicalNameFor(owner)}',
              ),
              trailing: owner == null
                  ? TextButton(
                      onPressed: () => _pickPTibugForModule(instance.id),
                      child: const Text('Équiper'),
                    )
                  : TextButton(
                      onPressed: () => _message(
                        widget.gameState
                            .unequipPTibugModuleInstance(
                              bug: owner,
                              moduleInstanceId: instance.id,
                            )
                            .message,
                      ),
                      child: const Text('Retirer'),
                    ),
            ),
          );
        }),
        if (_firstFusionPair() case final pair?)
          OutlinedButton.icon(
            onPressed: () => _message(
              widget.gameState
                  .fusePTibugModuleInstances(
                      firstId: pair.$1.id, secondId: pair.$2.id)
                  .message,
            ),
            icon: const Icon(Icons.merge_type_outlined),
            label: Text(
              'Fusionner 2 ${_moduleTitle(pair.$1.type)} niveau ${pair.$1.qualityLevel}',
            ),
          ),
        const SizedBox(height: 18),
        const Text('Capsules P’TIBUG',
            style: TextStyle(fontWeight: FontWeight.w900)),
        if (capsules.isEmpty)
          const Card(
              child: ListTile(title: Text('Aucune Capsule disponible.'))),
        ...capsules.map(
          (capsule) => Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(capsule.displayName),
              subtitle: Text('Niveau ${capsule.level} · origine conservée'),
              trailing: TextButton(
                onPressed: () => _message(
                  widget.gameState.decapsulatePTibug(capsule.id).message,
                ),
                child: const Text('Décapsuler'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Données de traits',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Les Données attribuées restent visibles ici. Deux Données identiques non équipées peuvent être fusionnées.',
        ),
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
                backgroundColor: _traitColor(
                  trait.grade,
                  trait,
                ).withValues(alpha: 0.16),
                child: Icon(
                  Icons.auto_awesome,
                  color: _traitColor(trait.grade, trait),
                ),
              ),
              title: Text(
                '${_traitTitle(trait)} · ${_traitGradeTitle(trait.grade)}',
              ),
              subtitle: Text(
                owner == null
                    ? _traitDescription(trait)
                    : '${_traitDescription(trait)}\nÉquipée par ${owner.displayName}',
              ),
              isThreeLine: owner != null,
            ),
          );
        }),
        const SizedBox(height: 8),
        ..._fusionActions(),
      ],
    );
  }

  Future<void> _pickPTibugForPermanentTrait(String traitId) async {
    final definition = pTibugConfig.traitDefinitionFor(traitId);
    if (definition == null) {
      return;
    }
    final patternId = 'ptibug-trait-$traitId';
    final masteryLevel =
        widget.gameState.pTibugPatternProgress[patternId]?.masteryLevel ?? 0;
    final candidates = widget.gameState.pTibugs.where((bug) {
      final targetLevel = widget.gameState.nextPTibugTraitLevelFor(
        bug,
        traitId,
      );
      return targetLevel != null && targetLevel <= masteryLevel;
    }).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            const Text(
              'Choisir un P’TIBUG',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...candidates.map((bug) {
              final targetLevel = widget.gameState.nextPTibugTraitLevelFor(
                bug,
                traitId,
              )!;
              final dataCost = definition.dataCostForLevel(targetLevel);
              final hours = pTibugConfig.cultivation.traitInfusionHours;
              final organic = ((pTibugConfig
                              .cultivation.organicPerActiveHour[bug.species] ??
                          0) *
                      pTibugConfig.cultivation.activeHours *
                      pTibugConfig.cultivation.traitMaterialCostCoefficient)
                  .ceil();
              final mineral = ((pTibugConfig
                              .cultivation.mineralPerActiveHour[bug.species] ??
                          0) *
                      pTibugConfig.cultivation.activeHours *
                      pTibugConfig.cultivation.traitMaterialCostCoefficient)
                  .ceil();
              final energy =
                  ((pTibugConfig.cultivation.energyPerActiveHour[bug.species] ??
                              0) *
                          pTibugConfig.cultivation.activeHours *
                          pTibugConfig.cultivation.traitEnergyCostCoefficient)
                      .ceil();
              return ListTile(
                leading: Icon(_speciesIcon(bug.species)),
                title: Text(widget.gameState.pTibugBiologicalNameFor(bug)),
                subtitle: Text(
                  'Vers ${definition.displayName} niveau $targetLevel\n'
                  'Infusion : $hours h actives · autonomie cible 8 h\n'
                  'Cellules : ${_dataCostLabel(dataCost)}\n'
                  'Consommation estimée : $organic Organique · $mineral Minéral · $energy Énergie',
                ),
                isThreeLine: true,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final tankId = await _pickFreeCultivationTank(
                    'Choisir une cuve pour l’Infusion',
                  );
                  if (tankId == null || !mounted) return;
                  _message(widget.gameState
                      .startPTibugTraitInfusion(
                        bug: bug,
                        traitId: traitId,
                        tankId: tankId,
                      )
                      .message);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickFreeCultivationTank(String title) {
    final tanks = widget.gameState.builtCultivationTanks
        .where((tank) => tank.currentOperationId == null)
        .toList();
    if (tanks.isEmpty) {
      _message('Aucune cuve libre dans la Nurserie.');
      return Future<String?>.value(null);
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(title: Text(title)),
            ...tanks.map((tank) => ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text('Cuve ${tank.slotIndex + 1}'),
                  subtitle:
                      const Text('Réserves locales, autonomie cible : 8 h.'),
                  onTap: () => Navigator.of(sheetContext).pop(tank.id),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPTibugForModule(String moduleInstanceId) async {
    final candidates = widget.gameState.pTibugs.where((bug) {
      final equippedModules = widget.gameState.pTibugModuleInstances
          .where((item) => item.equippedPTibugId == bug.id)
          .length;
      return equippedModules < widget.gameState.maxModulesPerPTibug;
    }).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            const Text(
              'Équiper un P’TIBUG',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...candidates.map(
              (bug) {
                final equippedModules = widget.gameState.pTibugModuleInstances
                    .where((item) => item.equippedPTibugId == bug.id)
                    .length;
                return ListTile(
                  leading: Icon(_speciesIcon(bug.species)),
                  title: Text(widget.gameState.pTibugBiologicalNameFor(bug)),
                  subtitle: Text(
                    '$equippedModules/${widget.gameState.maxModulesPerPTibug} slots occupés',
                  ),
                  onTap: () {
                    final result = widget.gameState.equipPTibugModuleInstance(
                      bug: bug,
                      moduleInstanceId: moduleInstanceId,
                    );
                    Navigator.of(sheetContext).pop();
                    _message(result.message);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  (PTibugModuleInstance, PTibugModuleInstance)? _firstFusionPair() {
    final available = widget.gameState.pTibugModuleInstances
        .where((item) =>
            !item.isEquipped && item.qualityLevel < pTibugConfig.moduleMaxLevel)
        .toList();
    for (final first in available) {
      final second = available
          .where(
            (item) =>
                item.id != first.id &&
                item.type == first.type &&
                item.qualityLevel == first.qualityLevel,
          )
          .firstOrNull;
      if (second != null) return (first, second);
    }
    return null;
  }

  String _dataCostLabel(Map<PTibugDataFamily, int> cost) => cost.entries
      .map((entry) =>
          '${_dataFamilyTitle(entry.key)} : ${entry.value} / ${widget.gameState.pTibugDataReserve[entry.key] ?? 0}')
      .join(' · ');

  String _resourceCostLabel(Map<String, int> cost) => cost.entries
      .map((entry) =>
          '${entry.key} : ${entry.value} / ${widget.gameState.resourceAmount(entry.key)}')
      .join(' · ');

  String _dataFamilyTitle(PTibugDataFamily family) => switch (family) {
        PTibugDataFamily.organique => 'Organique',
        PTibugDataFamily.minerale => 'Minérale',
        PTibugDataFamily.mycelienne => 'Mycélienne',
        PTibugDataFamily.toxine => 'Toxine',
        PTibugDataFamily.biomimetisme => 'Biomimétisme',
        PTibugDataFamily.energie => 'Énergie',
        PTibugDataFamily.comportementInsectoide => 'Comportement insectoïde',
      };

  List<Widget> _fusionActions() {
    final available = widget.gameState.pTibugTraitData
        .where(
          (data) => !widget.gameState.pTibugs.any(
            (bug) => bug.traitDataId == data.id,
          ),
        )
        .toList();
    final widgets = <Widget>[];
    for (final trait in available) {
      final partner = available
          .where(
            (item) =>
                item.id != trait.id &&
                item.definitionId == trait.definitionId &&
                item.grade == trait.grade,
          )
          .firstOrNull;
      if (partner == null ||
          trait.grade == PTibugTraitGrade.avance ||
          widgets.isNotEmpty) {
        continue;
      }
      widgets.add(
        OutlinedButton.icon(
          onPressed: () => _message(
            widget.gameState.fusePTibugTraitData(trait, partner).message,
          ),
          icon: const Icon(Icons.merge_type_outlined),
          label: Text(
            'Fusionner 2 ${_traitTitle(trait)} ${_traitGradeTitle(trait.grade)}',
          ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _showPTibugLoadout(PTibug bug) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final equippedInstances = widget.gameState.pTibugModuleInstances
            .where((instance) => instance.equippedPTibugId == bug.id)
            .toList();
        final availableInstances = widget.gameState.pTibugModuleInstances
            .where((instance) => !instance.isEquipped)
            .toList();
        final slots = widget.gameState.maxModulesPerPTibug;
        final trait = bug.biologicalTraitId == null
            ? null
            : pTibugConfig.traitDefinitionFor(bug.biologicalTraitId!);
        final secondTrait = bug.secondTraitId == null
            ? null
            : pTibugConfig.traitDefinitionFor(bug.secondTraitId!);
        final valuation = widget.gameState.pTibugValuationFor(bug);
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.76,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (_, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              children: <Widget>[
                Text(
                  widget.gameState.pTibugBiologicalNameFor(bug),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  '${pTibugConfig.species[bug.species]!.displayName} · niveau ${bug.level}',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _renamePTibug(bug, sheetContext),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Renommer'),
                  ),
                ),
                Text(
                  'XP ${bug.xp}/${pTibugConfig.progression.xpForNextLevel(bug.level)} · rendement ${((pTibugConfig.progression.yieldMultiplierForLevel(bug.level)) * 100).round()}% · énergie de base ${pTibugConfig.progression.baseEnergyPerDayForLevel(bug.level)}/jour',
                ),
                Text(
                  widget.gameState.isPTibugInCultivation(bug)
                      ? 'En cuve · ${_cultivationStatusFor(bug)}'
                      : bug.isRenewed
                          ? 'Évolué · second Trait ${bug.secondTraitId == null ? 'à choisir' : '${bug.secondTraitId} niveau ${bug.secondTraitLevel}'}'
                          : bug.level >= 3 && bug.biologicalTraitLevel >= 3
                              ? 'Évolution disponible dans la Nurserie.'
                              : bug.level >= 3
                                  ? 'Niveau 3 atteint : premier Trait III requis avant Évolution.'
                                  : 'Niveau ${bug.level} : Trait principal ${bug.level} disponible.',
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Certification et valeur',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text('${valuation.total} Bio-batteries estimées.'),
                        Text(
                          'Pattern : ${valuation.baseValue} · niveaux : ${valuation.levelValue} · Traits : ${valuation.traitValue} · Modules : ${valuation.moduleValue}',
                        ),
                        const Text(
                          'Cette valeur est indicative. Le paiement dépend d’une demande ou d’un contrat.',
                        ),
                        if (widget.gameState.pTibugCertificationBlocker(bug) !=
                            null)
                          Text(
                            widget.gameState.pTibugCertificationBlocker(bug)!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        if (widget.gameState
                            .eligiblePTibugContractsFor(bug)
                            .isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _choosePTibugContractSale(bug, sheetContext),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Prévisualiser la Capsule'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Détails du calcul',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text(
                            'Production finale : ${widget.gameState.pTibugProductionFor(bug).entries.map((entry) => '${entry.value} ${entry.key}').join(' · ')}'),
                        Text(
                            'Vigueur : ${(widget.gameState.biomassPTibugMultiplierFor(bug.refugeBiome) * 100).round()}% · bonus niveau : +${((pTibugConfig.progression.yieldMultiplierForLevel(bug.level) - 1) * 100).round()}%'),
                        Text(
                            'Capteur : ${widget.gameState.pTibugWeatherFor(bug) == null ? 'aucun malus météo' : 'météo active, protection vérifiée au cycle'}'),
                        if (_hasSmartSensor(bug))
                          Text(
                              'Cellules : ${bug.storedDataCells.length}/${pTibugConfig.territory.dataCellStorageCapacity} · chance ${bug.biologicalTraitId == 'capteurIntelligent' ? pTibugConfig.weather.sensorChanceByLevel[bug.biologicalTraitLevel] ?? 0 : pTibugConfig.weather.sensorChanceByLevel[bug.secondTraitLevel] ?? 0}%'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Trait biologique',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          trait == null
                              ? 'Aucun Trait permanent.'
                              : '${trait.displayName} niveau ${bug.biologicalTraitLevel}\n${trait.description}',
                        ),
                        if (bug.isRenewed) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            secondTrait == null
                                ? 'Second Trait : à choisir, à partir du niveau 4.'
                                : 'Second Trait : ${secondTrait.displayName} niveau ${bug.secondTraitLevel}\n${secondTrait.description}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Modules (${equippedInstances.length}/$slots)',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                if (equippedInstances.isEmpty)
                  const Text('Aucun Module récent équipé.'),
                ...equippedInstances.map(
                  (instance) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_moduleIcon(instance.type)),
                    title: Text(
                      '${_moduleTitle(instance.type)} niveau ${instance.qualityLevel}',
                    ),
                    subtitle: Text(_moduleDescription(instance.type)),
                    trailing: TextButton(
                      onPressed: () => _message(
                        widget.gameState
                            .unequipPTibugModuleInstance(
                              bug: bug,
                              moduleInstanceId: instance.id,
                            )
                            .message,
                      ),
                      child: const Text('Retirer'),
                    ),
                  ),
                ),
                if (availableInstances.isNotEmpty &&
                    equippedInstances.length < slots)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _pickPTibugForModule(availableInstances.first.id);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Équiper un Module disponible'),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Les Capsules P’TIBUG certifiées sont préparées uniquement pour une demande habitante ou un contrat du Sourcier.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _renamePTibug(PTibug bug, BuildContext sheetContext) async {
    final controller = TextEditingController(text: bug.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Renommer ${bug.displayName}'),
        content: TextField(
          controller: controller,
          maxLength: pTibugConfig.valuation.maximumNameLength,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom personnel'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    _message(widget.gameState.renamePTibug(bug, name).message);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  }

  Future<void> _choosePTibugContractSale(
    PTibug bug,
    BuildContext sheetContext,
  ) async {
    final contract = widget.gameState.eligiblePTibugContractsFor(bug).first;
    final valuation = widget.gameState.pTibugValuationFor(bug);
    final payment = PTibugValuationService(pTibugConfig.valuation).paymentFor(
      valuation,
      sourcierContract: true,
      bonusMultiplier: widget.gameState.sourcierConfidencePaymentMultiplier,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Capsule P’TIBUG certifiée'),
        content: Text(
          '${bug.displayName} · ${pTibugConfig.species[bug.species]!.displayName} niveau ${bug.level}\n'
          'Valeur estimée : ${valuation.total} Bio-batteries\n'
          'Paiement du contrat : $payment Bio-batteries\n\n'
          'Cette vente retire définitivement le P’TIBUG et ses Modules installés de votre collection.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmer la vente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result =
        widget.gameState.deliverCertifiedPTibugContract(bug, contract);
    if (result.success && sheetContext.mounted)
      Navigator.of(sheetContext).pop();
    _message(result.message);
  }

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
        PTibugModuleType.reflecteur => Icons.wb_sunny_outlined,
        PTibugModuleType.etancheite => Icons.water_drop_outlined,
      };

  String _moduleTitle(PTibugModuleType module) => switch (module) {
        PTibugModuleType.ailes => 'Ailes',
        PTibugModuleType.pinces => 'Pinces',
        PTibugModuleType.reservoir => 'Réservoir',
        PTibugModuleType.reflecteur => 'Réflecteur',
        PTibugModuleType.etancheite => 'Étanchéité',
      };

  String _moduleDescription(PTibugModuleType module) => switch (module) {
        PTibugModuleType.ailes =>
          '-${(pTibugConfig.wingsCycleReduction * 100).round()} % de durée de cycle.',
        PTibugModuleType.pinces =>
          '+${pTibugConfig.clawProductionBonus} ressource selon l’espèce.',
        PTibugModuleType.reservoir =>
          '+${pTibugConfig.reservoirCapacityBonus} de capacité de réserve.',
        PTibugModuleType.reflecteur => 'Annule le malus de Forte chaleur.',
        PTibugModuleType.etancheite => 'Annule le malus de Pluie intense.',
      };

  PTibugTraitDefinition? _traitDefinition(PTibugTraitData trait) =>
      pTibugConfig.traitDefinitionFor(trait.definitionId);

  String _traitTitle(PTibugTraitData trait) =>
      _traitDefinition(trait)?.displayName ?? trait.definitionId;

  String _traitGradeTitle(PTibugTraitGrade grade) => switch (grade) {
        PTibugTraitGrade.commun => 'Commun',
        PTibugTraitGrade.rare => 'Rare',
        PTibugTraitGrade.avance => 'Avancé',
      };

  Color _traitColor(PTibugTraitGrade? grade, [PTibugTraitData? trait]) {
    final hex = trait == null ? null : _traitDefinition(trait)?.colorHex;
    final parsed = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
    if (parsed != null) return Color(0xFF000000 | parsed);
    return switch (grade) {
      PTibugTraitGrade.commun => const Color(0xFF5D8D71),
      PTibugTraitGrade.rare => const Color(0xFF4977A6),
      PTibugTraitGrade.avance => const Color(0xFF8C5AA2),
      null => const Color(0xFF817D66),
    };
  }

  String _traitDescription(PTibugTraitData trait) {
    final definition = _traitDefinition(trait);
    if (definition == null) return 'Trait inconnu : ${trait.definitionId}.';
    final effects = definition
        .productionFor(trait.grade)
        .entries
        .where((entry) => entry.value != 0)
        .map((entry) => '+${entry.value} ${entry.key}')
        .join(' · ');
    return effects.isEmpty ? definition.description : '$effects par cycle.';
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
        : '${_traitTitle(trait)} · ${_traitGradeTitle(trait.grade)}';
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
          actions: <Widget>[
            _MailboxButton(
              tooltip: 'Messages Fablab',
              unreadCount: gameState.unreadReportCountForMailbox(
                Zone0MessageMailbox.fablab,
              ),
              onPressed: () {
                gameState.markReportsRead(mailbox: Zone0MessageMailbox.fablab);
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => MissionReportsSheet(
                    gameState: gameState,
                    mailbox: Zone0MessageMailbox.fablab,
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Inventaire global',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => Zone0InventorySheet(gameState: gameState),
              ),
            ),
          ],
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les unités progressent séparément. Les projets en cours ne bloquent pas leur fonctionnement au niveau actuel.',
          ),
          const SizedBox(height: 14),
          _BuildingViabilityCard(gameState: gameState, buildingId: 'atelier'),
          const SizedBox(height: 10),
          _BuildingViabilityCard(gameState: gameState, buildingId: 'cuisine'),
          const SizedBox(height: 10),
          _BuildingViabilityCard(gameState: gameState, buildingId: 'recycler'),
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
  Widget build(BuildContext context) {
    final capacity = math.max(
      wasteRecyclerConfig.energyUnitsPerBioBattery,
      ((gameState.energyUnits + 9) ~/ 10) * 10,
    );
    final level = (gameState.energyUnits / capacity).clamp(0.0, 1.0);
    final color = level <= .3 ? Colors.orange : Colors.lightBlue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Alimenter le Fablab',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '⚡ ${gameState.energyUnits} énergie · ${gameState.bioBatteries} bio-batterie(s)',
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: level,
                minHeight: 12,
                color: color,
                backgroundColor: color.withValues(alpha: .18),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: gameState.bioBatteries <= 0
                  ? null
                  : () {
                      final result = gameState.openBioBattery();
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(result.message)));
                    },
              icon: const Icon(Icons.bolt_outlined),
              label: Text(
                'Ouvrir 1 bio-batterie (+${wasteRecyclerConfig.energyUnitsPerBioBattery} énergie)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FablabQuantitySelector extends StatelessWidget {
  const _FablabQuantitySelector({
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        segments: const <ButtonSegment<int>>[
          ButtonSegment(value: 1, label: Text('x1')),
          ButtonSegment(value: 5, label: Text('x5')),
          ButtonSegment(value: 10, label: Text('x10')),
        ],
        selected: <int>{quantity},
        onSelectionChanged: (selected) => onChanged(selected.first),
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
            .add(
              Duration(
                minutes: wasteRecyclerConfig.cycleMinutes(
                  gameState.recyclerLevel,
                ),
              ),
            )
            .difference(DateTime.now())
        : null;
    final transferable = gameState.resourceAmount('Déchets');
    final cycles = gameState.recyclerWasteTank ~/ needed;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _FablabEnergyCard(gameState: gameState),
        const SizedBox(height: 12),
        _FablabActiveCraftsPanel(gameState: gameState),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Recycleur niveau ${gameState.recyclerLevel}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '$needed Déchets → ${wasteRecyclerConfig.outputResourcesPerCycle} ressources',
                ),
                Text(
                  '${wasteRecyclerConfig.cycleMinutes(gameState.recyclerLevel)} min par cycle · ${wasteRecyclerConfig.energyCostPerCycle} Énergie',
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 94,
                  height: 220,
                  child: Column(
                    children: <Widget>[
                      const Text(
                        'Cuve',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: const Color(
                                  0xFF7A4A2D,
                                ).withValues(alpha: .15),
                                border: Border.all(
                                  color: const Color(0xFF7A4A2D),
                                ),
                              ),
                            ),
                            FractionallySizedBox(
                              heightFactor: (gameState.recyclerWasteTank /
                                      gameState.recyclerTankCapacity)
                                  .clamp(0.0, 1.0),
                              widthFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7A4A2D),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                            Center(
                              child: Text(
                                '${gameState.recyclerWasteTank}/${gameState.recyclerTankCapacity}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$cycles × $needed',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Déchets',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('Inventaire : $transferable'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: <Widget>[
                          ...<int>[1, 5, 10].map(
                            (amount) => OutlinedButton(
                              onPressed: transferable == 0
                                  ? null
                                  : () {
                                      final result =
                                          gameState.transferWasteToRecycler(
                                        amount,
                                        campHeartLevel,
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                    },
                              child: Text('+$amount'),
                            ),
                          ),
                          FilledButton(
                            onPressed: transferable == 0
                                ? null
                                : () {
                                    final result =
                                        gameState.transferWasteToRecycler(
                                      transferable,
                                      campHeartLevel,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(result.message)),
                                    );
                                  },
                            child: const Text('Max'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$needed Déchets = ${wasteRecyclerConfig.outputResourcesPerCycle} ressources',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Production',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  running
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
                                      : 'En attente',
                ),
                if (running)
                  LinearProgressIndicator(
                    value: (1 -
                            remaining!.inSeconds /
                                Duration(
                                  minutes: wasteRecyclerConfig.cycleMinutes(
                                    gameState.recyclerLevel,
                                  ),
                                ).inSeconds)
                        .clamp(0, 1),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Sortie : ${gameState.recyclerOutputOrganic} Organique · ${gameState.recyclerOutputMineral} Minéral',
                ),
                FilledButton(
                  onPressed: gameState.recyclerOutputAmount == 0
                      ? null
                      : () {
                          final result = gameState.retrieveRecyclerOutput();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        },
                  child: const Text('Récupérer la production'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Same live production summary on every Fablab unit. The current tab never
/// filters this list: a player can therefore see a Cuisine, Atelier, module or
/// Recycleur task without having to switch tabs.
class _FablabActiveCraftsPanel extends StatelessWidget {
  const _FablabActiveCraftsPanel({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final orders = gameState.activeWorkshopOrders;
    final moduleOrders = gameState.activePTibugModuleCraftOrders;
    final recyclerStartedAt = gameState.recyclerCycleStartedAt;
    final count = orders.length +
        moduleOrders.length +
        (recyclerStartedAt == null ? 0 : 1);
    if (count == 0) return const SizedBox.shrink();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text(
          'Crafts en cours ($count)',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle:
            const Text('Ouvrir pour suivre toutes les fabrications du Fablab.'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: <Widget>[
          ...orders.map(
            (order) => _FablabActiveCraftCard.workshopOrder(
              gameState: gameState,
              order: order,
            ),
          ),
          ...moduleOrders.map(
            (moduleOrder) => _FablabActiveCraftCard.moduleOrder(
              moduleOrder: moduleOrder,
            ),
          ),
          if (recyclerStartedAt != null)
            _FablabActiveCraftCard.recycler(
              startedAt: recyclerStartedAt,
              level: gameState.recyclerLevel,
            ),
        ],
      ),
    );
  }
}

class _FablabActiveCraftCard extends StatelessWidget {
  const _FablabActiveCraftCard._({
    required this.title,
    required this.location,
    required this.locationColor,
    required this.details,
    required this.progress,
    required this.remaining,
    this.onCancel,
  });

  factory _FablabActiveCraftCard.workshopOrder({
    required Zone0GameState gameState,
    required WorkshopCraftOrder order,
  }) {
    final recipe = craftConfig.recipes.firstWhere(
      (item) => item.id == order.recipeId,
      orElse: () => defaultCraftConfig.simpleMealRecipe,
    );
    final isKitchen = order.area == WorkshopOrderArea.kitchen;
    final secondsLeft = math.max(
      0,
      order.nextCompletionTime.difference(DateTime.now()).inSeconds,
    );
    final unitProgress = (1 - secondsLeft / order.unitDurationSeconds).clamp(
      0.0,
      1.0,
    );
    final progress = ((order.completedQuantity + unitProgress) /
            math.max(1, order.requestedQuantity))
        .clamp(0.0, 1.0);
    return _FablabActiveCraftCard._(
      title: recipe.displayName,
      location: isKitchen ? 'Cuisine' : 'Atelier',
      locationColor: isKitchen ? Colors.deepOrange : Colors.indigo,
      details:
          '${order.completedQuantity} / ${order.requestedQuantity} · ${order.assignedPtipoteName == null ? 'Mode manuel' : 'Avec ${order.assignedPtipoteName}'}',
      progress: progress,
      remaining: _durationLabel(Duration(seconds: secondsLeft)),
      onCancel: () => gameState.cancelWorkshopOrder(order.id),
    );
  }

  factory _FablabActiveCraftCard.moduleOrder({
    required PTibugModuleCraftOrder moduleOrder,
  }) {
    final remaining = moduleOrder.endsAt.difference(DateTime.now());
    final total = moduleOrder.endsAt.difference(moduleOrder.startedAt);
    return _FablabActiveCraftCard._(
      title: '${moduleOrder.moduleType.displayName} · Module P’TIBUG',
      location: 'Atelier',
      locationColor: Colors.indigo,
      details: moduleOrder.assignedPtipoteName == null
          ? 'Fabrication manuelle d’un module pour la Nurserie.'
          : 'Avec ${moduleOrder.assignedPtipoteName}.',
      progress: (1 - remaining.inSeconds / math.max(1, total.inSeconds)).clamp(
        0.0,
        1.0,
      ),
      remaining: _durationLabel(remaining),
    );
  }

  factory _FablabActiveCraftCard.recycler({
    required DateTime startedAt,
    required int level,
  }) {
    final total = Duration(minutes: wasteRecyclerConfig.cycleMinutes(level));
    final remaining = startedAt.add(total).difference(DateTime.now());
    return _FablabActiveCraftCard._(
      title: 'Traitement des déchets',
      location: 'Recycleur',
      locationColor: Colors.teal,
      details: 'Conversion de Déchets en Organique et Minéral.',
      progress: (1 - remaining.inSeconds / math.max(1, total.inSeconds)).clamp(
        0.0,
        1.0,
      ),
      remaining: _durationLabel(remaining),
    );
  }

  final String title;
  final String location;
  final Color locationColor;
  final String details;
  final double progress;
  final String remaining;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: .25),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      location,
                      style: TextStyle(
                        color: locationColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(details),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: locationColor,
                    backgroundColor: locationColor.withValues(alpha: .18),
                  ),
                ),
                const SizedBox(height: 5),
                Text('Temps restant : $remaining'),
                if (onCancel != null) ...<Widget>[
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Annuler'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

String _durationLabel(Duration duration) {
  final seconds = math.max(0, duration.inSeconds);
  return '${seconds ~/ 60}m ${seconds.remainder(60).toString().padLeft(2, '0')}s';
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PtipoteFigurine>>(
      stream: _figurineService.watchMyFigurines(),
      builder: (context, snapshot) {
        final figurines = snapshot.data ?? const <PtipoteFigurine>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _FablabEnergyCard(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FablabActiveCraftsPanel(gameState: widget.gameState),
            const SizedBox(height: 12),
            Text(
              'Atelier',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              'Atelier niv. ${widget.gameState.atelierLevel} · '
              '${widget.gameState.activePtipoteWorkshopOrders}/${widget.gameState.workshopSlots} emplacement(s) P’TIPOTE · '
              '${widget.gameState.activeManualWorkshopOrders}/1 créneau manuel. Chaque niveau ajoute un emplacement P’TIPOTE.',
            ),
            const SizedBox(height: 12),
            if (widget.gameState.activeManualWorkshopOrders < 1 ||
                widget.gameState.activePtipoteWorkshopOrders <
                    widget.gameState.workshopSlots) ...<Widget>[
              _FablabQuantitySelector(
                quantity: _quantity,
                onChanged: (value) => setState(() => _quantity = value),
              ),
              const SizedBox(height: 10),
              ...craftConfig.recipes
                  .where(
                    (recipe) => recipe.craftSection == CraftSection.atelier,
                  )
                  .where(widget.gameState.isWorkshopRecipeActive)
                  .map(
                    (recipe) => _WorkshopRecipeCard(
                      recipe: recipe,
                      gameState: widget.gameState,
                      quantity: _quantity,
                      manualAvailable:
                          widget.gameState.activeManualWorkshopOrders < 1,
                      ptipoteAvailable:
                          widget.gameState.activePtipoteWorkshopOrders <
                              widget.gameState.workshopSlots,
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
                    ),
                  ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Créneau manuel et emplacements P’TIPOTE occupés.'),
              ),
            const SizedBox(height: 18),
            const Text(
              'Modules P’TIBUG',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Les Modules sont fabriqués ici, puis stockés, équipés ou fusionnés dans la Nurserie.',
            ),
            ...PTibugModuleType.values.map(
              (module) => _PTibugModuleAtelierCard(
                gameState: widget.gameState,
                module: module,
                figurines: figurines,
              ),
            ),
          ],
        );
      },
    );
  }

  void _start(CraftRecipe recipe, PtipoteFigurine? figurine) {
    final result = widget.gameState.startWorkshopOrder(
      recipe: recipe,
      quantity: _quantity,
      figurine: figurine,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
        return ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            _FablabEnergyCard(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FablabActiveCraftsPanel(gameState: widget.gameState),
            const SizedBox(height: 12),
            Text(
              'Cuisine niveau ${widget.gameState.cuisineLevel}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Eau disponible gratuitement. ${widget.gameState.activePtipoteKitchenOrders}/${widget.gameState.kitchenSlots} emplacement(s) P’TIPOTE · ${widget.gameState.activeManualKitchenOrders}/1 créneau manuel.',
            ),
            const SizedBox(height: 12),
            _FablabQuantitySelector(
              quantity: _quantity,
              onChanged: (value) => setState(() => _quantity = value),
            ),
            const SizedBox(height: 12),
            ...craftConfig.recipes
                .where((recipe) => recipe.craftSection == CraftSection.cuisine)
                .map(
                  (recipe) => _CuisineRecipeCard(
                    recipe: recipe,
                    gameState: widget.gameState,
                    quantity: _quantity,
                    canPrepare: widget.gameState.hasResources(
                          recipe.ingredients.map(
                            (key, value) => MapEntry(key, value * _quantity),
                          ),
                        ) &&
                        widget.gameState.hasInventoryCapacityFor(<String, int>{
                          recipe.resultItem: recipe.resultAmount * _quantity,
                        }),
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
                  ),
                ),
            if (_lastResult != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _lastResult!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        );
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

class _PTibugModuleAtelierCard extends StatelessWidget {
  const _PTibugModuleAtelierCard({
    required this.gameState,
    required this.module,
    required this.figurines,
  });

  final Zone0GameState gameState;
  final PTibugModuleType module;
  final List<PtipoteFigurine> figurines;

  @override
  Widget build(BuildContext context) {
    final patternActive = gameState.isPTibugPatternActive(
      'ptibug-module-${module.name}',
    );
    final cost = pTibugConfig.moduleCraftCostFor(module);
    final energy = pTibugConfig.moduleCraftEnergyFor(module);
    final hasMaterials = gameState.hasResources(cost);
    final manualAvailable = gameState.activeManualWorkshopOrders < 1;
    final ptipoteAvailable =
        gameState.activePtipoteWorkshopOrders < gameState.workshopSlots;
    final hasEnergy = gameState.energyUnits >= energy + 1;
    final canCraft =
        patternActive && manualAvailable && hasMaterials && hasEnergy;
    final ingredientText = cost.entries
        .map(
          (entry) =>
              '${entry.key} : ${entry.value} / ${gameState.resourceAmount(entry.key)}',
        )
        .join('\n');
    final icon = switch (module) {
      PTibugModuleType.ailes => Icons.air_outlined,
      PTibugModuleType.pinces => Icons.content_cut_outlined,
      PTibugModuleType.reservoir => Icons.inventory_2_outlined,
      PTibugModuleType.reflecteur => Icons.wb_sunny_outlined,
      PTibugModuleType.etancheite => Icons.water_drop_outlined,
    };
    return _ProductionRecipeCard(
      title: '${module.displayName} · Atelier',
      leadingIcon: icon,
      description:
          'Module fabriqué à l’Atelier, puis équipé ou fusionné dans la Nurserie.',
      slots: <_ProductionSlotData>[
        _ProductionSlotData(
          label: 'Ingrédients',
          value: ingredientText,
          icon: Icons.eco_outlined,
        ),
        _ProductionSlotData(
          label: 'Atelier',
          value:
              'Énergie module : $energy\nLancement manuel : +1\nDisponible : ${gameState.energyUnits}\nTemps : ${pTibugConfig.moduleCraftMinutesFor(module)} min',
          icon: Icons.precision_manufacturing_outlined,
        ),
      ],
      details: <String>[
        'Modules possibles avec le stock : ${_maxProductionCount(cost, gameState.resourceAmount)}',
      ],
      prerequisiteLabel: patternActive
          ? 'Pattern Kernel actif'
          : 'Pré-requis : Pattern Kernel actif',
      prerequisiteMet: patternActive,
      unavailableLabel: !patternActive
          ? null
          : !manualAvailable
              ? 'Créneau manuel de l’Atelier occupé.'
              : !hasMaterials
                  ? gameState.missingResourcesLabel(cost)
                  : !hasEnergy
                      ? 'Énergie insuffisante.'
                      : null,
      primaryActionLabel: 'Fabriquer',
      primaryActionHint: 'utilise ${energy + 1} unité(s) d’énergie',
      primaryActionIcon: Icons.precision_manufacturing_outlined,
      primaryActionEnabled: canCraft,
      onPrimaryAction: () {
        final result = gameState.startPTibugModuleCraft(module);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      },
      secondaryActionLabel: 'Confier à un P’TIPOTE',
      secondaryActionEnabled: patternActive &&
          ptipoteAvailable &&
          hasMaterials &&
          gameState.energyUnits >= energy,
      onSecondaryAction: () async {
        final figurine = await _pickPtipoteForActivity(
          context: context,
          gameState: gameState,
          figurines: figurines,
          title: 'Confier ${module.displayName}',
        );
        if (figurine != null && context.mounted) {
          final result =
              gameState.startPTibugModuleCraft(module, figurine: figurine);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result.message)));
        }
      },
    );
  }
}

class _WorkshopRecipeCard extends StatelessWidget {
  const _WorkshopRecipeCard({
    required this.recipe,
    required this.gameState,
    required this.quantity,
    required this.manualAvailable,
    required this.ptipoteAvailable,
    required this.onPrepare,
    required this.onAssign,
  });

  final CraftRecipe recipe;
  final Zone0GameState gameState;
  final int quantity;
  final bool manualAvailable;
  final bool ptipoteAvailable;
  final VoidCallback onPrepare;
  final Future<void> Function() onAssign;

  @override
  Widget build(BuildContext context) => _CraftProductionRecipeCard(
        recipe: recipe,
        gameState: gameState,
        quantity: quantity,
        sectionLabel: 'Atelier',
        sectionLevel: gameState.atelierLevel,
        showConsumableEffects: false,
        manualAvailable: manualAvailable,
        ptipoteAvailable: ptipoteAvailable,
        onPrepare: onPrepare,
        onAssign: onAssign,
      );
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
  Widget build(BuildContext context) => _CraftProductionRecipeCard(
        recipe: recipe,
        gameState: gameState,
        quantity: quantity,
        sectionLabel: 'Cuisine',
        sectionLevel: gameState.cuisineLevel,
        showConsumableEffects: true,
        manualAvailable: manualAvailable,
        ptipoteAvailable: ptipoteAvailable,
        onPrepare: onPrepare,
        onAssign: onAssign,
      );
}

class _CraftProductionRecipeCard extends StatelessWidget {
  const _CraftProductionRecipeCard({
    required this.recipe,
    required this.gameState,
    required this.quantity,
    required this.sectionLabel,
    required this.sectionLevel,
    required this.showConsumableEffects,
    required this.manualAvailable,
    required this.ptipoteAvailable,
    required this.onPrepare,
    required this.onAssign,
  });

  final CraftRecipe recipe;
  final Zone0GameState gameState;
  final int quantity;
  final String sectionLabel;
  final int sectionLevel;
  final bool showConsumableEffects;
  final bool manualAvailable;
  final bool ptipoteAvailable;
  final VoidCallback onPrepare;
  final Future<void> Function() onAssign;

  @override
  Widget build(BuildContext context) {
    final costs = recipe.ingredients.map(
      (key, value) => MapEntry(key, value * quantity),
    );
    final output = <String, int>{
      recipe.resultItem: recipe.resultAmount * quantity,
    };
    final hasResources = gameState.hasResources(costs);
    final hasCapacity = gameState.hasInventoryCapacityFor(output);
    final bioBatteryCost = recipe.bioBatteryCost * quantity;
    final hasBioBatteries = gameState.bioBatteries >= bioBatteryCost;
    final canPrepare = hasResources && hasCapacity && hasBioBatteries;
    final maxCreatable = _maxProductionCount(
      recipe.ingredients,
      gameState.resourceAmount,
    );
    final ingredientText = costs.entries
        .map(
          (entry) =>
              '${entry.key} : ${entry.value} / ${gameState.resourceAmount(entry.key)}',
        )
        .join('\n');
    final contextText = recipe.contextIngredients.entries
        .map((entry) => '${entry.value} ${entry.key}')
        .join(' + ');
    final outputDetails = <String>[
      'Résultat : ${recipe.resultAmount * quantity} ${recipe.resultItem}',
      'Créations possibles avec le stock : $maxCreatable',
      'Temps : ${recipe.durationMinutes} min/unité',
    ];
    if (showConsumableEffects) {
      outputDetails.add(
        'Consommable · faim +${recipe.hungerRestore} · vitalité +${recipe.vitalityRestore}',
      );
    }
    return _ProductionRecipeCard(
      title: '${recipe.displayName} · $sectionLabel niv. $sectionLevel',
      leadingIcon: sectionLabel == 'Atelier'
          ? Icons.handyman_outlined
          : Icons.restaurant_outlined,
      description: 'Pattern Kernel requis pour cette fabrication.',
      slots: <_ProductionSlotData>[
        _ProductionSlotData(
          label: 'Ingrédients',
          value: ingredientText,
          icon: Icons.eco_outlined,
        ),
        _ProductionSlotData(
          label: sectionLabel,
          value: contextText.isEmpty ? 'Aucun élément contextuel' : contextText,
          icon: sectionLabel == 'Cuisine'
              ? Icons.water_drop_outlined
              : Icons.precision_manufacturing_outlined,
        ),
      ],
      details: outputDetails,
      highlightedDetails: bioBatteryCost <= 0
          ? const <InlineSpan>[]
          : <InlineSpan>[
              const TextSpan(text: 'Coût énergétique : '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  Icons.battery_charging_full_outlined,
                  size: 17,
                  color: const Color(0xFF2878C9),
                ),
              ),
              TextSpan(
                text: ' $bioBatteryCost Bio-batteries',
                style: const TextStyle(
                  color: Color(0xFF2878C9),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
      prerequisiteLabel: 'Pré-requis : Pattern Kernel actif',
      prerequisiteMet: true,
      unavailableLabel: !canPrepare
          ? hasCapacity
              ? !hasResources
                  ? gameState.missingResourcesLabel(costs)
                  : !hasBioBatteries
                      ? '$bioBatteryCost Bio-batteries requises.'
                      : null
              : 'Inventaire plein : impossible de ranger ${recipe.resultItem}.'
          : null,
      primaryActionLabel: 'Lancer manuellement',
      primaryActionHint: 'utilise 1 unité d’énergie',
      primaryActionIcon: sectionLabel == 'Cuisine'
          ? Icons.restaurant_outlined
          : Icons.handyman_outlined,
      primaryActionEnabled:
          canPrepare && manualAvailable && gameState.energyUnits >= 1,
      onPrimaryAction: onPrepare,
      secondaryActionLabel: 'Confier à un P’TIPOTE',
      secondaryActionIcon: Icons.person_add_alt_1,
      secondaryActionEnabled: canPrepare && ptipoteAvailable,
      onSecondaryAction: onAssign,
    );
  }
}

class _ProductionRecipeCard extends StatelessWidget {
  const _ProductionRecipeCard({
    required this.title,
    required this.leadingIcon,
    required this.slots,
    required this.details,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.primaryActionEnabled,
    required this.onPrimaryAction,
    this.trailingIcon,
    this.description,
    this.prerequisiteLabel,
    this.prerequisiteMet = true,
    this.unavailableLabel,
    this.primaryActionHint,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.secondaryActionEnabled = false,
    this.onSecondaryAction,
    this.highlightedDetails = const <InlineSpan>[],
  });

  final String title;
  final IconData leadingIcon;
  final IconData? trailingIcon;
  final String? description;
  final List<_ProductionSlotData> slots;
  final List<String> details;
  final String? prerequisiteLabel;
  final bool prerequisiteMet;
  final String? unavailableLabel;
  final String primaryActionLabel;
  final String? primaryActionHint;
  final IconData primaryActionIcon;
  final bool primaryActionEnabled;
  final VoidCallback onPrimaryAction;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final bool secondaryActionEnabled;
  final Future<void> Function()? onSecondaryAction;
  final List<InlineSpan> highlightedDetails;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(leadingIcon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (trailingIcon != null) Icon(trailingIcon),
                ],
              ),
              if (description != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(description!),
              ],
              if (slots.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: slots
                        .map(
                          (slot) => SizedBox(
                            width: (constraints.maxWidth - 10) / 2,
                            child: _RecipeSlot(
                              label: slot.label,
                              value: slot.value,
                              icon: slot.icon,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (details.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                ...details.map(Text.new),
              ],
              if (highlightedDetails.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: highlightedDetails)),
              ],
              if (prerequisiteLabel != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  prerequisiteLabel!,
                  style: TextStyle(
                    color: prerequisiteMet
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (unavailableLabel != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  unavailableLabel!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: primaryActionEnabled ? onPrimaryAction : null,
                icon: Icon(primaryActionIcon),
                label: primaryActionHint == null
                    ? Text(primaryActionLabel)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(primaryActionLabel),
                          Text(
                            primaryActionHint!,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
              ),
              if (secondaryActionLabel != null) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: secondaryActionEnabled && onSecondaryAction != null
                      ? onSecondaryAction
                      : null,
                  icon: Icon(secondaryActionIcon),
                  label: Text(secondaryActionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class _ProductionSlotData {
  const _ProductionSlotData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

int _maxProductionCount(
  Map<String, int> requirements,
  int Function(String resourceId) stockFor,
) {
  int? possible;
  for (final entry in requirements.entries) {
    if (entry.value <= 0) continue;
    final value = stockFor(entry.key) ~/ entry.value;
    possible = possible == null ? value : math.min(possible, value);
  }
  return possible ?? 0;
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                Text(description, textAlign: TextAlign.center),
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
