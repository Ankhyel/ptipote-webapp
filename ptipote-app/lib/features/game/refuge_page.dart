import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/figurine_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_profile_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/co_breeding.dart';
import '../figurines/ptipote_image.dart';
import '../nfc/nfc_page.dart';
import '../figurines/ptipote_stats_config.dart';
import '../figurines/ptipote_daily_life.dart';
import '../figurines/ptipote_v2.dart';
import 'camp_heart_config.dart';
import 'camp_generator_config.dart';
import 'community_roles_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'fablab_v2.dart';
import 'game_asset_resolver.dart';
import 'housing_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'logistics_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'ptibug_valuation_service.dart';
import 'resident_economy_config.dart';
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

class _CultivationMatrixSelectionDialog extends StatefulWidget {
  const _CultivationMatrixSelectionDialog({required this.matrices});
  final List<PTibugAspectMatrix> matrices;
  @override
  State<_CultivationMatrixSelectionDialog> createState() =>
      _CultivationMatrixSelectionDialogState();
}

class _CultivationMatrixSelectionDialogState
    extends State<_CultivationMatrixSelectionDialog> {
  final Set<String> _selected = <String>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Aspect de la Cultivation'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text(
                'Choisissez jusqu’à deux Matrices. Deux copies du même aspect créent un clone ; deux aspects différents mélangent chaque caractéristique à 50 %. Une seule Matrice mélange chaque caractéristique avec de l’aléatoire.'),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.matrices
                    .map(
                      (matrix) => _AspectMatrixPresentation(
                        matrix: matrix,
                        selected: _selected.contains(matrix.id),
                        onTap: () => setState(() {
                          if (_selected.contains(matrix.id)) {
                            _selected.remove(matrix.id);
                          } else if (_selected.length < 2) {
                            _selected.add(matrix.id);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ]),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, const <String>[]),
              child: const Text('Sans Matrice')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: Text(_selected.isEmpty
                  ? 'Valider'
                  : 'Utiliser ${_selected.length} Matrice(s)')),
        ],
      );
}

class _RefugePageState extends State<RefugePage> with WidgetsBindingObserver {
  static final _campHeartState = CampHeartState.placeholder();
  static final _zone0State = Zone0GameState.instance;

  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  final _profileService = UserProfileService();
  String? _refugeAsset;
  Timer? _missionResolutionTimer;
  bool _simulationStarted = false;
  bool _energyWarning600Dismissed = false;
  bool _energyWarning699Dismissed = false;
  String _buildLabel = 'Version…';

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
      name: 'Logistics',
      title: 'Logistique',
      left: 0.56,
      top: 0.76,
      width: 0.28,
      height: 0.10,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zone0State.addListener(_onZone0StateChanged);
    unawaited(_warmAssets());
    unawaited(_loadBuildInfo());
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

  Future<void> _loadBuildInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _buildLabel = 'v${info.version} · build ${info.buildNumber}';
      });
    } on Object {
      // The label is a diagnostic aid only. Keep the screen usable on a
      // platform where package metadata is unavailable (for example a test).
      if (mounted) setState(() => _buildLabel = 'Version indisponible');
    }
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
    _zone0State.resolveResidentDomesticGeneration();
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
    final physical = await _figurineService.watchMyFigurines().first;
    _zone0State.recoverFigurineNeeds(
      figurines: _zone0State.ptipotesWithNeeds(physical),
      tick: 1,
    );
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
      _zone0State.resolveResidentDomesticGeneration();
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
          if (building.name == 'Logistics') {
            return LogisticsPage(
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
    if (building.name == 'Logistics' && !_zone0State.isLogisticsBuilt) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _ConstructionProjectSheet(
          gameState: _zone0State,
          targetId: 'logistics',
          title: 'Bâtiment Logistique',
          description: 'Centralise les travaux, la maintenance et les Kits.',
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
              'Installe des P’TIBUG dans la Savane tropicale pour produire lentement des ressources.',
          campHeartLevel: _campHeartState.campHeartLevel,
          campHeartState: _campHeartState,
        ),
      );
      return;
    }
    _openBuilding(building);
  }

  Future<void> _confirmDeveloperReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repartir de zéro ?'),
        content: const Text(
          'Les bâtiments, ressources et la progression Zone 0 seront remis au camp initial. Les P’TIPOTES sont conservés, mais leurs XP, faim, sommeil et vitalité repartent à zéro.',
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
    if (confirmed != true || !mounted) return;
    final result = _zone0State.developerResetZone0Progress();
    // Le niveau 1 représente le camp de départ dans la configuration du
    // Cœur : le bâtiment existe, sans déblocage ni progression investie.
    _campHeartState
      ..campHeartLevel = 1
      ..vegetalizationXp = 0
      ..totalVegetalizationInvested = 0;
    await _flushZone0State();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jeu')),
      floatingActionButton: StreamBuilder<UserProfile?>(
        stream: _profileService.watchMyProfile(),
        builder: (context, snapshot) {
          if (snapshot.data?.canSeeDiagnostics != true) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.small(
            onPressed: _confirmDeveloperReset,
            tooltip: 'Repartir de zéro',
            child: const Icon(Icons.restart_alt),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: _CampHud(
                    gameState: _zone0State,
                    campHeartLevel: _campHeartState.campHeartLevel,
                  ),
                ),
                if (_zone0State.bioBatteries >= 699 &&
                    !_energyWarning699Dismissed)
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
                        decoration:
                            const BoxDecoration(color: Color(0xFFDAC7A6)),
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
                            if (_zone0State.isTowerWeatherUnlocked)
                              Positioned(
                                top: 12,
                                left: 12,
                                child:
                                    _CampWeatherBadge(gameState: _zone0State),
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
            Positioned(
              right: 12,
              bottom: 8,
              child: IgnorePointer(
                child: Text(
                  _buildLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF6B6256),
                        fontSize: 9,
                      ),
                ),
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
    return Column(children: <Widget>[
      Row(children: <Widget>[
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
          child: _HudChip(
            icon: Icons.battery_charging_full_outlined,
            color: const Color(0xFF2878C9),
            richLabel: _energyHudLabel(gameState),
            onTap: () => _showHudInfo(
              context,
              'Bio-batteries et bio-piles',
              'Les bio-batteries (bleu) alimentent le refuge. Les bio-piles (jaune) sont la monnaie fine du Marché : 100 bio-piles sont automatiquement converties en 1 bio-batterie.',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HudChip(
            emoji: _wellbeingEmoji(gameState.displayedCampWellbeing),
            label: '${gameState.displayedCampWellbeing}%',
            color: wellbeingColor,
            onTap: () => _showHudInfo(
              context,
              'Bien-être',
              'Le bien-être du refuge reflète sa stabilité. La Sécurité actuelle apporte ${gameState.securityWellbeingModifier >= 0 ? '+' : ''}${gameState.securityWellbeingModifier}% (${towerOperationsConfig.wellbeingBandFor(gameState.refugeSafety).label}).',
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: <Widget>[
        for (final resource in <({String name, IconData icon, Color color})>[
          (
            name: 'Organique',
            icon: Icons.eco_outlined,
            color: const Color(0xFF4F7F52)
          ),
          (
            name: 'Minéral',
            icon: Icons.terrain_outlined,
            color: const Color(0xFF7A6753)
          ),
          (
            name: 'Déchets',
            icon: Icons.delete_sweep_outlined,
            color: const Color(0xFF8A5A42)
          ),
          (
            name: 'Mycélium',
            icon: Icons.spa_outlined,
            color: const Color(0xFF7452A0)
          ),
        ]) ...<Widget>[
          Expanded(
              child: _HudChip(
                  icon: resource.icon,
                  color: resource.color,
                  label: '${gameState.resourceAmount(resource.name)}',
                  onTap: () => _showHudInfo(context, resource.name,
                      'Stock ${resource.name} disponible dans l’inventaire du refuge.'))),
          if (resource.name != 'Mycélium') const SizedBox(width: 5),
        ],
      ]),
      const SizedBox(height: 6),
      _HudChip(
        icon: Icons.inventory_2_outlined,
        label:
            '${gameState.inventoryUsedAmount} / ${gameState.globalStockCapacity}',
        onTap: () => _showHudInfo(context, 'Stockage',
            '${gameState.inventoryUsedAmount} ressources utilisées sur ${gameState.globalStockCapacity}. Les emplacements se remplissent par piles.'),
      ),
    ]);
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

  String _wellbeingEmoji(int value) {
    if (value >= 100) return '🤩';
    if (value >= 90) return '😁';
    if (value >= 70) return '🙂';
    if (value >= 50) return '😐';
    if (value >= 30) return '😠';
    return '🤬';
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

class _CampWeatherBadge extends StatelessWidget {
  const _CampWeatherBadge({required this.gameState});

  final Zone0GameState gameState;

  String get _emoji => switch (gameState.activeGlobalWeatherEvent?.type) {
        TowerWeatherType.toxicCloud => '☁️',
        TowerWeatherType.heatWave => '☀️',
        TowerWeatherType.heavyRain => '🌧️',
        _ => '🌤️',
      };

  String get _timeLeft {
    final endsAt = gameState.activeGlobalWeatherEvent?.endsAt;
    if (endsAt == null) return '—';
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return '0 min';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0
        ? '${hours} h ${minutes.toString().padLeft(2, '0')}'
        : '$minutes min';
  }

  void _showDetails(BuildContext context) {
    final weather = gameState.activeGlobalWeatherEvent;
    final title = weather == null || weather.type == TowerWeatherType.calm
        ? 'Météo calme'
        : gameState.towerWeatherHudLabel;
    final intensity = weather == null
        ? 'Calme'
        : switch (weather.intensity) {
            GlobalWeatherIntensity.moderate => 'Modérée',
            GlobalWeatherIntensity.strong => 'Forte',
            GlobalWeatherIntensity.severe => 'Sévère',
            GlobalWeatherIntensity.calm => 'Calme',
          };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(_emoji, style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Intensité : $intensity'),
            Text('Temps restant : $_timeLeft'),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetails(context),
          borderRadius: BorderRadius.circular(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFDFDF9F0),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8B8153), width: 1.4),
              ),
              child: Text(_emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xEDEDE4CF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_timeLeft,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    this.icon,
    this.emoji,
    this.label,
    this.richLabel,
    this.color = const Color(0xFF2F241A),
    this.onTap,
  });

  final IconData? icon;
  final String? emoji;
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
              if (emoji != null)
                Text(emoji!, style: const TextStyle(fontSize: 17))
              else if (icon != null)
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
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[gameState, campHeartState]),
      builder: (context, _) {
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
        final requests =
            gameState.refugeRequests(campHeartState.campHeartLevel);
        final mainCount =
            mainMission?.status == KernelMissionStatus.active ? 1 : 0;
        return DefaultTabController(
          length: 3,
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
                    gameState.markReportsRead(
                        mailbox: Zone0MessageMailbox.kernel);
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
                      label: 'Missions',
                      count: mainCount +
                          requests
                              .where((mission) =>
                                  mission.status == KernelMissionStatus.active)
                              .length,
                    ),
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
                  _KernelMainMissionTab(
                    mission: mainMission,
                    requests: requests,
                    gameState: gameState,
                  ),
                  _KernelPlansTab(gameState: gameState),
                ],
              ),
            ),
          ),
        );
      },
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
  const _KernelMainMissionTab({
    required this.mission,
    required this.requests,
    required this.gameState,
  });

  final KernelMissionProgress? mission;
  final List<KernelMissionProgress> requests;
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        if (mission != null)
          _KernelMissionCard(mission: mission!, gameState: gameState)
        else
          const _KernelEmptyState(message: 'Aucune mission active.'),
        if (requests.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Text('Missions du refuge',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...requests.map(
            (item) => _KernelMissionCard(mission: item, gameState: gameState),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Arrivées',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (gameState.residentArrivalCandidates.isEmpty)
                  Text(
                      'Aucune arrivée à examiner. Les futures candidatures apparaîtront ici.')
                else
                  ...gameState.residentArrivalCandidates.map(
                    (candidate) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(candidate.displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            Text(
                                '${candidate.originText} · ${candidate.arrivalReasonText}'),
                            if (candidate.shortStoryText.isNotEmpty)
                              Text(candidate.shortStoryText),
                            Text(
                                'Passion : ${candidate.primaryPassionId} · logement : ${candidate.requiredHousingCapacity} place(s) · ${candidate.status.name}'),
                            if (candidate.status ==
                                    ResidentArrivalStatus.arrivalScheduled &&
                                candidate.arrivalScheduledAt !=
                                    null) ...<Widget>[
                              const SizedBox(height: 8),
                              Builder(builder: (_) {
                                final started =
                                    candidate.acceptedAt ?? candidate.createdAt;
                                final total = candidate.arrivalScheduledAt!
                                    .difference(started)
                                    .inMilliseconds;
                                final elapsed = DateTime.now()
                                    .difference(started)
                                    .inMilliseconds;
                                final progress = total <= 0
                                    ? 1.0
                                    : (elapsed / total).clamp(0.0, 1.0);
                                final remaining = candidate.arrivalScheduledAt!
                                    .difference(DateTime.now());
                                final hours = math.max(0, remaining.inHours);
                                final minutes = math.max(
                                    0, remaining.inMinutes.remainder(60));
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                        'Trajet en cours · ${hours} h ${minutes} min restantes',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(value: progress),
                                  ],
                                );
                              }),
                            ],
                            if (candidate.requestedConditions.isNotEmpty)
                              Text(
                                  'Conditions : ${candidate.requestedConditions.join(' · ')}'),
                            if (<ResidentArrivalStatus>{
                              ResidentArrivalStatus.available,
                              ResidentArrivalStatus.postponed
                            }.contains(candidate.status))
                              Wrap(spacing: 6, children: <Widget>[
                                TextButton(
                                    onPressed: () => ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(SnackBar(
                                            content: Text(gameState
                                                .acceptResidentArrivalCandidate(
                                                    candidate.id)
                                                .message))),
                                    child: const Text('Accepter')),
                                TextButton(
                                    onPressed: () => ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(SnackBar(
                                            content: Text(gameState
                                                .postponeResidentArrivalCandidate(
                                                    candidate.id)
                                                .message))),
                                    child: const Text('Reporter')),
                                TextButton(
                                    onPressed: () => ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(SnackBar(
                                            content: Text(gameState
                                                .rejectResidentArrivalCandidate(
                                                    candidate.id)
                                                .message))),
                                    child: const Text('Refuser')),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
                    'Capsules de données',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              gameState.researchUnlocked
                  ? 'Les missions de la Tour donnent des Capsules à ouvrir. Leur tirage aléatoire rejoint ensuite cette réserve.'
                  : 'La Tour de recherche doit être débloquée avant toute découverte de Capsule.',
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
                'Capsules à ouvrir',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Chaque Capsule révèle cinq entrées de Données lors de son ouverture. Elles rejoignent ensuite définitivement la réserve du Kernel.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: cells.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final cell = cells[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.memory_outlined),
                      title: Text(cell.displayName),
                      subtitle: Text(
                        '${cell.isNeutralCell ? 'Neutre' : _kernelDataFamilyLabel(cell.dominantFamily!)} · 5 données · tirage à l’ouverture',
                      ),
                      trailing: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final prepared = widget.gameState
                              .preparePTibugDataCellOpening(cell.id);
                          if (!prepared.success || !mounted) return;
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
      KernelPlanCategory.furniture => 'Meubles',
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
    _tabs = TabController(length: 6, vsync: this);
    _vitalityRecoveryTimer = Timer.periodic(
      // Two simulation ticks represent one real minute.  The needs resolver
      // deliberately uses that cadence (see `* 2` in recoverFigurineNeeds),
      // so a one-second timer made the displayed minutes thirty times too
      // fast while the Maison was open.
      const Duration(seconds: 30),
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
    _figurineService.watchMyFigurines().first.then((physical) {
      if (!mounted) return;
      // Keep the Co-élevage dashboard live even when its dedicated page is
      // closed: the profile card has its own departure countdown.
      _gameState.resolveCoBreedingSessions();
      _gameState.recoverFigurineNeeds(
        figurines: _gameState.ptipotesWithNeeds(physical),
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
            Tab(text: 'Activités', icon: Icon(Icons.directions_walk)),
            Tab(text: 'Amélioration', icon: Icon(Icons.upgrade_outlined)),
            Tab(text: 'Générateur', icon: Icon(Icons.battery_charging_full)),
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
                          final physical =
                              snapshot.data ?? const <PtipoteFigurine>[];
                          _gameState.ensureNurseryAdmissions(physical);
                          final figurines = _gameState.allPtipotes(physical);
                          final admitted = figurines
                              .where(
                                (figurine) => !_gameState.isInNursery(figurine),
                              )
                              .toList();
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              physical.isEmpty) {
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
          _MaisonTrainingTab(
            gameState: _gameState,
            figurineService: _figurineService,
          ),
          _HouseUpgradeTab(gameState: _gameState),
          _CampGeneratorView(
            gameState: _gameState,
            heartLevel: _gameState.generatorDisplayLevel,
          ),
          const _BuildingInformationTab(
            title: 'Maison',
            description:
                'La Maison accueille les P’TIPOTES actifs, leurs alcôves de repos, les messages, l’inventaire et le Bio-générateur du joueur. Son amélioration augmente les alcôves. Les logements des habitants sont séparés et n’ajoutent pas directement de population.',
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
          final physical = snapshot.data ?? const <PtipoteFigurine>[];
          final figurines = _gameState.allPtipotes(physical);
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
                        xp: _gameState.xpFor(figurine),
                        level: _gameState.levelFor(figurine),
                        hunger: _gameState.hungerFor(figurine),
                        rest: _gameState.restFor(figurine),
                        energy: _gameState.vitalityFor(figurine),
                        energyMax: _gameState.energyMaxFor(figurine),
                        hungerMax: _gameState.hungerMaxFor(figurine),
                        happiness: _gameState.happinessFor(figurine),
                        attachment: _gameState.attachmentFor(figurine),
                        attachmentLevel: _gameState
                            .ptipoteV2ProfileFor(figurine)
                            .attachmentLevel,
                        happinessBreakdown:
                            _gameState.happinessBreakdownFor(figurine),
                        jobLevels: _gameState.ptipoteJobLevels(figurine),
                        activity: _ptipoteActivityLabel(figurine),
                        countdown: _coBreedingCountdown(figurine) ??
                            _ptipoteActivityCountdown(figurine),
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

  /// Co-élevage takes precedence over a task countdown on the companion
  /// dashboard: it is the only countdown that determines a future departure.
  /// The detail intentionally becomes finer during the final three days.
  String? _coBreedingCountdown(PtipoteFigurine figurine) {
    final session = _gameState.coBreedingSessionFor(figurine.id);
    if (session == null) return null;
    if (session.departurePending) return '🧳 Prêt à partir';
    final remaining = Duration(seconds: session.remainingSeconds);
    if (remaining <= Duration.zero) return '🧳 Prêt à partir';
    final hours = remaining.inHours;
    if (hours > 72) {
      return 'Co-élevage · ${remaining.inDays} j ${hours.remainder(24)} h';
    }
    if (hours > 48) {
      return '⏳ J-3 · ${hours} h';
    }
    if (hours > 24) {
      final roundedMinutes = (remaining.inMinutes ~/ 30) * 30;
      return '⏳ J-2 · ${roundedMinutes ~/ 60} h ${roundedMinutes % 60} min';
    }
    final roundedMinutes = (remaining.inMinutes ~/ 10) * 10;
    return '⏳ J-1 · ${roundedMinutes ~/ 60} h ${roundedMinutes % 60} min';
  }
}

class _MaisonTrainingTab extends StatelessWidget {
  const _MaisonTrainingTab(
      {required this.gameState, required this.figurineService});
  final Zone0GameState gameState;
  final FigurineService figurineService;

  Future<void> _selectPtipote(BuildContext context, String activity) async {
    final all = await figurineService.watchMyFigurines().first;
    final available = gameState
        .ptipotesAvailableForActivities(all)
        .where((ptipote) =>
            activity != 'movement' ||
            gameState.vitalityFor(ptipote) >=
                ptipoteDailyLifeConfig.trainingEnergyCost)
        .toList();
    if (!context.mounted) return;
    final figurine = await showModalBottomSheet<PtipoteFigurine>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: <Widget>[
            Text('Choisir un P’TIPOTE',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (available.isEmpty)
              ListTile(
                title: const Text('Aucun P’TIPOTE disponible dans la Maison.'),
                subtitle: activity == 'movement'
                    ? Text(
                        'L’entraînement demande ${ptipoteDailyLifeConfig.trainingEnergyCost} énergie.')
                    : null,
              ),
            ...available.map((ptipote) => ListTile(
                  leading: PtipoteImage(
                      type: ptipote.type, species: ptipote.species, height: 42),
                  title: Text(ptipote.displayName),
                  subtitle: Text('Niveau ${gameState.levelFor(ptipote)}'),
                  onTap: () => Navigator.pop(sheetContext, ptipote),
                )),
          ],
        ),
      ),
    );
    if (figurine == null || !context.mounted) return;
    final page = switch (activity) {
      'movement' =>
        _MovementTrainingPage(gameState: gameState, figurine: figurine),
      'hide' => _WalkMiniGamePage(
          gameState: gameState, figurine: figurine, catchMe: false),
      _ => _WalkMiniGamePage(
          gameState: gameState, figurine: figurine, catchMe: true),
    };
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _activityCard(BuildContext context,
          {required IconData icon,
          required String title,
          required String subtitle,
          required String activity}) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _selectPtipote(context, activity),
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
        Text('Activités',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Text('Entraînement',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        _activityCard(context,
            icon: Icons.sports_martial_arts,
            title: 'Entraînement au mouvement',
            subtitle: 'XP +20 Attachement si réussi',
            activity: 'movement'),
        const SizedBox(height: 16),
        Text('Promenade',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        _activityCard(context,
            icon: Icons.search,
            title: 'Cache-cache',
            subtitle: '+30 Attachement',
            activity: 'hide'),
        _activityCard(context,
            icon: Icons.directions_run,
            title: 'Attrape-moi si tu peux',
            subtitle: '+30 Attachement',
            activity: 'catch'),
      ]));
}

enum _MovementDirection { up, down, left, right }

Future<void> _showActivityReward(
  BuildContext context,
  PtipoteFigurine figurine, {
  required int xp,
  required double attachment,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activité terminée'),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          PtipoteImage(
              type: figurine.type, species: figurine.species, height: 92),
          const SizedBox(height: 8),
          Text(figurine.displayName,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          if (xp > 0) Text('+$xp XP'),
          Text('+${attachment.toStringAsFixed(0)} Attachement'),
        ]),
        actions: <Widget>[
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continuer'))
        ],
      ),
    );

class _MovementTrainingPage extends StatefulWidget {
  const _MovementTrainingPage(
      {required this.gameState, required this.figurine});
  final Zone0GameState gameState;
  final PtipoteFigurine figurine;
  @override
  State<_MovementTrainingPage> createState() => _MovementTrainingPageState();
}

class _MovementTrainingPageState extends State<_MovementTrainingPage> {
  final math.Random _random = math.Random();
  Timer? _travelTimer;
  _MovementDirection? _expected;
  int _lives = 3;
  int _completed = 0;
  double _travel = 0;
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  @override
  void dispose() {
    _travelTimer?.cancel();
    super.dispose();
  }

  void _next() {
    if (!mounted || _finished) return;
    _travelTimer?.cancel();
    setState(() {
      _expected = _MovementDirection.values[_random.nextInt(4)];
      _travel = 0;
    });
    // Un indicateur traverse l'écran en environ cinq secondes. La fenêtre de
    // réussite est la bande centrale qui couvre un cinquième de sa largeur.
    const ticks = 100;
    _travelTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _finished) return timer.cancel();
      setState(() => _travel = math.min(1, _travel + 1 / ticks));
      if (_travel >= 1) {
        timer.cancel();
        _mistake();
      }
    });
  }

  void _input(_MovementDirection direction) {
    if (_expected == null || _finished) return;
    const centerStart = .4;
    const centerEnd = .6;
    if (direction != _expected ||
        _travel < centerStart ||
        _travel > centerEnd) {
      _mistake();
      return;
    }
    _travelTimer?.cancel();
    setState(() {
      _expected = null;
      _completed += 1;
    });
    if (_completed >= ptipoteDailyLifeConfig.movementSequenceLength) {
      _finished = true;
      widget.gameState.completePtipoteTraining(widget.figurine);
      _showActivityReward(
        context,
        widget.figurine,
        xp: ptipoteDailyLifeConfig.movementXpPerLevel *
            widget.gameState
                .ptipoteV2ProfileFor(widget.figurine)
                .trainingGameLevel,
        attachment: ptipoteDailyLifeConfig.trainingAttachmentGain,
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _next();
  }

  void _mistake() {
    _travelTimer?.cancel();
    if (!mounted || _finished) return;
    setState(() {
      _expected = null;
      _lives -= 1;
    });
    if (_lives <= 0) {
      _finished = true;
      return;
    }
    _next();
  }

  IconData _icon(_MovementDirection direction) => switch (direction) {
        _MovementDirection.up => Icons.keyboard_arrow_up,
        _MovementDirection.down => Icons.keyboard_arrow_down,
        _MovementDirection.left => Icons.keyboard_arrow_left,
        _MovementDirection.right => Icons.keyboard_arrow_right
      };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Mouvement')),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                        'Vies : $_lives · $_completed / ${ptipoteDailyLifeConfig.movementSequenceLength}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 24),
                    LayoutBuilder(builder: (context, constraints) {
                      final left = (1 - _travel) * (constraints.maxWidth - 42);
                      return SizedBox(
                        height: 90,
                        child: Stack(children: <Widget>[
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: constraints.maxWidth / 5,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: .12),
                                border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          if (_expected != null)
                            Positioned(
                              left: left,
                              top: 18,
                              child: Icon(_icon(_expected!),
                                  size: 48,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                        ]),
                      );
                    }),
                    const SizedBox(height: 20),
                    _directionPad(),
                    if (_finished && _lives <= 0) ...<Widget>[
                      const SizedBox(height: 24),
                      const Text('Pas cette fois. Aucune récompense.'),
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Retour'))
                    ],
                  ]))));

  Widget _directionPad() =>
      Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        _directionButton(_MovementDirection.up),
        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _directionButton(_MovementDirection.left),
          const SizedBox(width: 62, height: 62),
          _directionButton(_MovementDirection.right),
        ]),
        _directionButton(_MovementDirection.down),
      ]);

  Widget _directionButton(_MovementDirection direction) => IconButton.filled(
        iconSize: 40,
        onPressed: _finished ? null : () => _input(direction),
        icon: Icon(_icon(direction)),
      );
}

class _WalkMiniGamePage extends StatefulWidget {
  const _WalkMiniGamePage({
    required this.gameState,
    required this.figurine,
    required this.catchMe,
  });
  final Zone0GameState gameState;
  final PtipoteFigurine figurine;
  final bool catchMe;
  @override
  State<_WalkMiniGamePage> createState() => _WalkMiniGamePageState();
}

class _WalkMiniGamePageState extends State<_WalkMiniGamePage> {
  final math.Random _random = math.Random();
  late final bool _catchMe = widget.catchMe;
  late int _target = _random.nextInt(5);
  Timer? _roundTimer;
  Timer? _catchTimer;
  int _points = 0;
  bool _betweenRounds = false;
  double _catchSize = .5;

  @override
  void initState() {
    super.initState();
    if (_catchMe) {
      _startCatchMe();
    } else {
      _startHideRound();
    }
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    _catchTimer?.cancel();
    super.dispose();
  }

  void _startHideRound() {
    _roundTimer?.cancel();
    _roundTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _betweenRounds) return;
      setState(() => _target = _random.nextInt(5));
      _startHideRound();
    });
  }

  void _foundHideTarget() {
    _roundTimer?.cancel();
    setState(() {
      _points += 1;
      _betweenRounds = true;
    });
    if (_points >= 3) {
      _win();
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      setState(() {
        _betweenRounds = false;
        _target = _random.nextInt(5);
      });
      _startHideRound();
    });
  }

  void _startCatchMe() {
    _catchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _catchSize -= .02);
      if (_catchSize < .1) {
        _catchTimer?.cancel();
      }
    });
  }

  void _catchBoost() {
    if (_catchSize < .1 || _catchSize > .8) return;
    setState(() => _catchSize = math.min(1, _catchSize + .01));
    if (_catchSize > .8) _win();
  }

  void _win() {
    widget.gameState.completePtipoteWalk(widget.figurine);
    _showActivityReward(context, widget.figurine,
            xp: 0, attachment: ptipoteDailyLifeConfig.walkAttachmentGain)
        .then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_catchMe ? 'Attrape-moi' : 'Cache-cache')),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                        _catchMe
                            ? 'Attrape ${widget.figurine.displayName} au bon endroit !'
                            : 'Où se cache ${widget.figurine.displayName} ?',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_catchMe) _catchMeBoard() else _hideAndSeekBoard(),
                    const SizedBox(height: 18),
                    const Text('Aucune pénalité : essaie à nouveau.'),
                  ]))));

  Widget _hideAndSeekBoard() => ColoredBox(
        color: _betweenRounds ? Colors.black : Colors.transparent,
        child: Wrap(
          spacing: 12,
          runSpacing: 14,
          alignment: WrapAlignment.center,
          children: List<Widget>.generate(5, (index) {
            final sizes = <double>[86, 112, 74, 102, 92];
            return InkWell(
              onTap: _betweenRounds
                  ? null
                  : () {
                      if (index == _target) {
                        _foundHideTarget();
                      } else {
                        setState(() => _target = _random.nextInt(5));
                      }
                    },
              child: Container(
                width: sizes[index],
                height: sizes[index],
                decoration: BoxDecoration(
                    color: const Color(0xffE8E5DC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all()),
                child: index == _target && !_betweenRounds
                    ? PtipoteImage(
                        type: widget.figurine.type,
                        species: widget.figurine.species,
                        height: sizes[index] - 16)
                    : const Icon(Icons.crop_square_outlined, size: 36),
              ),
            );
          }),
        ),
      );

  Widget _catchMeBoard() => Column(children: <Widget>[
        SizedBox(
            height: 160,
            child: Center(
                child: _catchSize < .1
                    ? const Text('Trop loin ! Réessaie sans pénalité.')
                    : Transform.scale(
                        scale: _catchSize,
                        child: PtipoteImage(
                            type: widget.figurine.type,
                            species: widget.figurine.species,
                            height: 150)))),
        const SizedBox(height: 26),
        FilledButton.icon(
            onPressed: _catchSize < .1 ? null : _catchBoost,
            icon: const Icon(Icons.front_hand_outlined),
            label: const Text('Attrape-moi !')),
      ]);
}

class _MaisonNurseryTab extends StatefulWidget {
  const _MaisonNurseryTab({required this.gameState, required this.onHatched});

  final Zone0GameState gameState;
  final VoidCallback onHatched;

  @override
  State<_MaisonNurseryTab> createState() => _MaisonNurseryTabState();
}

class _MaisonNurseryTabState extends State<_MaisonNurseryTab> {
  bool _departureQueueOpen = false;

  Zone0GameState get gameState => widget.gameState;
  VoidCallback get onHatched => widget.onHatched;

  Future<void> _openDepartureQueue(BuildContext context) async {
    if (_departureQueueOpen) return;
    _departureQueueOpen = true;
    try {
      await _runDepartureQueue(context);
    } finally {
      if (mounted) {
        setState(() => _departureQueueOpen = false);
      }
    }
  }

  void _scheduleDepartureQueue(BuildContext context) {
    if (_departureQueueOpen || gameState.pendingCoBreedingDepartures.isEmpty) {
      return;
    }
    _departureQueueOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _runDepartureQueue(context);
      } finally {
        if (mounted) {
          setState(() => _departureQueueOpen = false);
        }
      }
    });
  }

  Future<void> _runDepartureQueue(BuildContext context) async {
    while (context.mounted) {
      final session = gameState.prepareNextCoBreedingDeparture();
      if (session == null) return;
      final profile = gameState.ptipoteV2Profiles[session.ptipoteId];
      if (profile == null) return;
      final name = profile.displayName.isNotEmpty
          ? profile.displayName
          : profile.systemName;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Un départ se prépare'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 130,
                child: PtipoteImage(
                  type: profile.typeId.name,
                  species: profile.natureId,
                  visualAssetKey:
                      profile.isProtocol ? profile.visualAssetKey : '',
                  height: 130,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$name a fini sa croissance ici.\nIl s’en va aider d’autres camps.\nIl vous remercie pour votre accueil.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('L’accompagner'),
            ),
          ],
        ),
      );
      if (accepted != true || !context.mounted) return;
      final reward = gameState.finalizeCoBreedingDeparture(session.sessionId);
      if (reward == null) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Co-élevage terminé'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                  'Bonus XP ${_ptipoteTypeName(reward.typeId)} · +${reward.ptipoteXpAmount} XP'),
              Text('Éleveur · +${reward.breederXpAmount} XP'),
              Text('Kernel · +${reward.kernelTrustAmount} Confiance'),
              const SizedBox(height: 8),
              const Text(
                  'Le Bonus XP reste dans l’inventaire jusqu’au choix d’un P’TIPOTE possédé du même Type.'),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Récupérer'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final figurineService = FigurineService();
    return SafeArea(
      child: StreamBuilder<List<PtipoteFigurine>>(
        stream: figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          final physical = snapshot.data ?? const <PtipoteFigurine>[];
          gameState.ensureNurseryAdmissions(physical);
          gameState.resolveCoBreedingSessions();
          _scheduleDepartureQueue(context);
          final figurines = gameState.allPtipotes(physical);
          final eggs = figurines
              .where((figurine) => gameState.isInNursery(figurine))
              .toList();
          for (final figurine in eggs) {
            gameState.resumeInterruptedPtipoteArrival(figurine);
          }
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
                'Tout nouveau P’TIPOTE attend ici sous forme d’œuf avant son rituel d’accueil.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NfcPage()),
                ),
                icon: const Icon(Icons.nfc),
                label: const Text('Scanner un P’TIPOTE'),
              ),
              if (gameState.shouldShowInitialPtipoteChoice(physical)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showInitialCoBreedingChoice(
                    context,
                    gameState,
                  ),
                  icon: const Icon(Icons.egg_alt_outlined),
                  label: const Text('Co-élever un P’TIPOTE'),
                ),
              ],
              if (gameState.isCoBreedingIntroMissionAvailable(physical)) ...[
                const SizedBox(height: 14),
                _CoBreedingIntroCard(gameState: gameState),
              ] else if (gameState.coBreedingUnlocked) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CoBreedingPage(gameState: gameState),
                    ),
                  ),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Ouvrir le Co-élevage'),
                ),
              ],
              const SizedBox(height: 18),
              if (gameState.pendingCoBreedingDepartures.isNotEmpty) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.waving_hand_outlined),
                    title: Text(
                      '${gameState.pendingCoBreedingDepartures.length} départ(s) de Co-élevage en attente',
                    ),
                    subtitle: const Text('Les accompagner depuis la Maison.'),
                    trailing: FilledButton(
                      onPressed: () => _openDepartureQueue(context),
                      child: const Text('Accompagner'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (eggs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Couveuse vide. Les prochains P’TIPOTES arriveront ici avant de rejoindre le refuge.',
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
                          Icon(
                            Icons.egg_alt_outlined,
                            size: 54,
                            color: _eggColor(
                              gameState.ptipoteV2ProfileFor(figurine).typeId,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Œuf en attente',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            gameState
                                        .ptipoteV2ProfileFor(figurine)
                                        .acquisitionOrigin ==
                                    PtipoteAcquisitionOrigin.coBreeding
                                ? 'Co-élevage'
                                : 'Figurine',
                            textAlign: TextAlign.center,
                          ),
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
                              child: const Text('Tapoter l’œuf'),
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

Future<void> _showInitialCoBreedingChoice(
  BuildContext context,
  Zone0GameState gameState,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Choisir un premier Type',
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('Ce premier Co-élevage est gratuit.'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PtipoteTypeId.values.map((type) {
                final label = switch (type) {
                  PtipoteTypeId.vegetal => 'Végétal',
                  PtipoteTypeId.mineral => 'Minéral',
                  PtipoteTypeId.mycelial => 'Mycélien',
                };
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _eggColor(type),
                  ),
                  onPressed: () {
                    final result = gameState.startInitialCoBreeding(type);
                    if (!result.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Co-élevage'),
                        content: const Text(
                          'Ce P’TIPOTE vous est confié temporairement. Aidez-le à grandir : il restera au maximum 7 jours et pourra repartir plus tôt au niveau 7.',
                        ),
                        actions: <Widget>[
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Voir la Couveuse'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.egg_alt_outlined),
                  label: Text(label),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CoBreedingIntroCard extends StatelessWidget {
  const _CoBreedingIntroCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Mission Kernel · Co-élevage',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Un P’TIPOTE cherche un éleveur pour terminer sa croissance avant de rejoindre un autre camp ou une ville.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  gameState.acceptCoBreedingIntroMission();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CoBreedingPage(gameState: gameState),
                    ),
                  );
                },
                child: const Text('Accepter la mission'),
              ),
              TextButton(
                onPressed: gameState.dismissCoBreedingIntroMission,
                child: const Text('Plus tard'),
              ),
            ],
          ),
        ),
      );
}

class _CoBreedingPage extends StatefulWidget {
  const _CoBreedingPage({required this.gameState});

  final Zone0GameState gameState;

  @override
  State<_CoBreedingPage> createState() => _CoBreedingPageState();
}

class _CoBreedingPageState extends State<_CoBreedingPage> {
  Zone0GameState get gameState => widget.gameState;
  CoBreedingOffer? _offer;
  Timer? _selectionTimer;

  @override
  void initState() {
    super.initState();
    // Resolve once at page entry, never from build. Mutating a ChangeNotifier
    // while its AnimatedBuilder is building can create a recursive rebuild on
    // iOS exactly when an offer is accepted.
    gameState.resolveCoBreedingSessions();
    _offer = gameState.ensureCoBreedingOffer();
    _selectionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    super.dispose();
  }

  void _showResult(Zone0ActionResult result) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      setState(() => _offer = gameState.coBreedingOffer);
    }
  }

  String _remaining(Duration duration) {
    if (duration <= Duration.zero) return 'Prêt à repartir';
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    return days > 0 ? '$days j $hours h restantes' : '$hours h restantes';
  }

  String _typeLabel(PtipoteTypeId type) => switch (type) {
        PtipoteTypeId.vegetal => 'Végétal',
        PtipoteTypeId.mineral => 'Minéral',
        PtipoteTypeId.mycelial => 'Mycélien',
      };

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    final now = DateTime.now();
    final selectionCooldown = gameState.coBreedingSelectionCooldownRemaining(
      now: now,
    );
    final canSelect = !gameState.isCoBreedingCapacityReached &&
        selectionCooldown == Duration.zero;
    final eligibleProtocols = gameState.ptipoteV2Profiles.values
        .where((profile) => gameState.isEligibleForEnvelope(profile.ptipoteId))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Co-élevage')),
      body: AnimatedBuilder(
        animation: gameState,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            Text(
              'P’TIPOTES EN CO-ÉLEVAGE',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
                '${gameState.activeCoBredCount} / ${gameState.coBreedingCapacity}'),
            if (selectionCooldown > Duration.zero)
              Text(
                'Nouvel accueil possible dans ${_remaining(selectionCooldown)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text('P’TIPOTE DISPONIBLE',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    if (offer == null)
                      const Text('Indisponible actuellement.')
                    else ...<Widget>[
                      Icon(Icons.egg_alt_outlined,
                          color: _eggColor(offer.typeId), size: 52),
                      Text(
                          'Type ${_typeLabel(offer.typeId)} · ${offer.generation == PtipoteGeneration.protocol ? 'Protocole' : 'Vestige'}'),
                      Text(
                          'Nouvelle proposition dans ${_remaining(offer.expiresAt.difference(now))}'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: canSelect
                            ? () =>
                                _showResult(gameState.acceptCoBreedingOffer())
                            : null,
                        child: Text(gameState.isCoBreedingCapacityReached
                            ? 'Capacité atteinte'
                            : selectionCooldown > Duration.zero
                                ? 'Attente 24 h'
                                : 'Accueillir en Co-élevage'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Card(
              color: eligibleProtocols.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: eligibleProtocols.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('ENVELOPPE DISPONIBLE'),
                        subtitle: Text(
                            'Débloqué avec un P’TIPOTE Protocole en Co-élevage niveau 3 sans Enveloppe.'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: eligibleProtocols.map((profile) {
                          final name = profile.displayName.isNotEmpty
                              ? profile.displayName
                              : profile.systemName;
                          final envelopeOffer = gameState
                              .ensureCoBreedingEnvelopeOffer(profile.ptipoteId);
                          final compatible =
                              gameState.availableCoBreedingEnvelopeTemplatesFor(
                                  profile.ptipoteId);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text('ENVELOPPE DISPONIBLE · $name',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(
                                    'Niveau ${gameState.levelForId(profile.ptipoteId)} · offre compatible gratuite'),
                                if (envelopeOffer != null)
                                  FilledButton(
                                    onPressed: () => _showResult(
                                        gameState.acceptFreeCoBreedingEnvelope(
                                            profile.ptipoteId)),
                                    child: Text(
                                        'Accueillir ${protocolEnvelopeDefinitionForId(envelopeOffer.envelopeId)?.displayName ?? envelopeOffer.envelopeId} gratuitement'),
                                  ),
                                const SizedBox(height: 4),
                                const Text(
                                    'Choisir exactement · 6 Bio-batteries'),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: compatible
                                      .map((envelope) => OutlinedButton(
                                            onPressed: () => _showResult(gameState
                                                .chooseExactCoBreedingEnvelope(
                                                    profile.ptipoteId,
                                                    envelope.envelopeId)),
                                            child: Text(envelope.displayName),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            if (gameState.activeCoBreedingSessions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              const Text('Sessions actives',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              ...gameState.activeCoBreedingSessions.map((session) {
                final profile = gameState.ptipoteV2Profiles[session.ptipoteId];
                final label = profile?.displayName.isNotEmpty == true
                    ? profile!.displayName
                    : profile?.systemName ?? 'P’TIPOTE';
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.egg_alt_outlined,
                        color: _eggColor(session.typeId)),
                    title: Text(label),
                    subtitle: Text(session.departurePending
                        ? 'Prêt à repartir'
                        : _protocolSessionDetails(profile, session)),
                    trailing: Text(
                        'Niv. ${gameState.levelOverrides[session.ptipoteId] ?? 1}'),
                  ),
                );
              }),
            ],
            if (gameState.breederLevel >= 3) ...<Widget>[
              const SizedBox(height: 18),
              const Text('Choisir un Type',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const Text(
                  '5 Bio-batteries · sélection aléatoire dans le Type choisi.'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PtipoteTypeId.values
                    .map((type) => OutlinedButton.icon(
                          onPressed: canSelect
                              ? () => _showResult(
                                    gameState.chooseCoBreedingType(type),
                                  )
                              : null,
                          icon: Icon(Icons.egg_alt_outlined,
                              color: _eggColor(type)),
                          label: Text(_typeLabel(type)),
                        ))
                    .toList(),
              ),
            ],
            if (gameState.breederLevel >= 4) ...<Widget>[
              const SizedBox(height: 18),
              const Text('Catalogue',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const Text('Choisir exactement un P’TIPOTE · 8 Bio-batteries.'),
              _catalogue(
                  'VESTIGES',
                  gameState.availableCoBreedingTemplates(
                      generation: PtipoteGeneration.vestige),
                  canSelect),
              _catalogue(
                  'PROTOCOLES',
                  gameState.availableCoBreedingTemplates(
                      generation: PtipoteGeneration.protocol),
                  canSelect),
            ],
          ],
        ),
      ),
    );
  }

  String _protocolSessionDetails(
    PtipoteV2Profile? profile,
    CoBreedingSession session,
  ) {
    final remaining = _remaining(Duration(seconds: session.remainingSeconds));
    if (profile == null || !profile.isProtocol) {
      return 'Co-élevage · $remaining';
    }
    final v2 = ptipoteStatsConfig.v2;
    final envelope = profile.envelopeId;
    if (envelope == null) {
      return 'Protocole · Noyau seul · efficacité 50 % · $remaining';
    }
    final symbiosis = profile.envelopeSymbiosis;
    final efficiency = (profile.effectiveProtocolEfficiency(v2) * 100).round();
    final state = symbiosis?.maxLevelReached == true
        ? 'Symbiose complète'
        : 'Symbiose ${(symbiosis?.symbiosisProgressPercent ?? 0).toStringAsFixed(1)} %';
    final envelopeName =
        protocolEnvelopeDefinitionForId(envelope)?.displayName ?? envelope;
    return 'Protocole · $envelopeName · $state · efficacité $efficiency % · $remaining';
  }

  Widget _catalogue(
    String title,
    List<CoBreedingTemplate> templates,
    bool canSelect,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          ...templates.map((template) => Card(
                child: ListTile(
                  leading: Icon(Icons.egg_alt_outlined,
                      color: _eggColor(template.typeId)),
                  title: Text(template.systemName),
                  subtitle: Text(
                    template.generation == PtipoteGeneration.protocol
                        ? '${_typeLabel(template.typeId)} · Noyau'
                        : _typeLabel(template.typeId),
                  ),
                  trailing: TextButton(
                    onPressed: canSelect
                        ? () => _showResult(gameState
                            .chooseExactCoBreedingPtipote(template.templateId))
                        : null,
                    child: const Text('8 piles'),
                  ),
                ),
              )),
        ],
      );
}

Color _eggColor(PtipoteTypeId type) {
  final raw = PtipoteArrivalService.eggColorHex(type, ptipoteStatsConfig.v2)
      .replaceFirst('#', '');
  final parsed = int.tryParse(raw, radix: 16);
  return parsed == null ? Colors.amber : Color(0xFF000000 | parsed);
}

String _ptipoteTypeName(PtipoteTypeId type) => switch (type) {
      PtipoteTypeId.vegetal => 'Végétal',
      PtipoteTypeId.mineral => 'Minéral',
      PtipoteTypeId.mycelial => 'Mycélien',
    };

const List<List<int>> _rhythmTapPatterns = <List<int>>[
  <int>[0, 600, 1200],
  <int>[0, 550, 1100, 1650],
  <int>[0, 450, 900, 1500, 2050],
  <int>[0, 600, 1100, 1700, 2200, 2750],
];

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
  final List<Timer> _previewTimers = <Timer>[];
  final List<DateTime> _tapTimes = <DateTime>[];
  int _previewBeat = -1;
  bool _isPulsing = false;
  bool _resolved = false;
  String? _feedback;
  late final TextEditingController _nameController;

  PtipoteV2Profile? get _profile => widget.figurine == null
      ? null
      : widget.gameState.ptipoteV2ProfileFor(widget.figurine!);

  List<int> get _rhythm => _profile?.rhythmPattern.isNotEmpty == true
      ? _profile!.rhythmPattern
      : _rhythmTapPatterns[1];

  Duration get _tapTolerance => Duration(
        milliseconds: ptipoteStatsConfig.v2.rhythmTimingToleranceMs,
      );

  bool get _isHatched => _profile?.arrivalState == PtipoteArrivalState.hatched;
  bool get _isNaming => _profile?.arrivalState == PtipoteArrivalState.naming;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _profile?.systemName ?? '',
    );
    if (!widget.isPractice && widget.figurine != null) {
      widget.gameState.preparePtipoteArrivalRhythm(widget.figurine!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPreview());
  }

  @override
  void dispose() {
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _nameController.dispose();
    super.dispose();
  }

  void _playPreview() {
    if (_resolved || _isHatched || _isNaming) return;
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _previewTimers.clear();
    setState(() {
      _previewBeat = -1;
      _isPulsing = false;
      _feedback = null;
    });
    for (var beat = 0; beat < _rhythm.length; beat += 1) {
      _previewTimers.add(
        Timer(Duration(milliseconds: _rhythm[beat]), () {
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
    if (_resolved || _isHatched || _isNaming) return;
    if (!widget.isPractice && widget.figurine != null) {
      widget.gameState.beginPtipoteArrivalRhythm(widget.figurine!);
    }
    final now = DateTime.now();
    if (_tapTimes.isNotEmpty) {
      final beatIndex = _tapTimes.length;
      final expectedGap = Duration(
        milliseconds: _rhythm[beatIndex] - _rhythm[beatIndex - 1],
      );
      final actualGap = now.difference(_tapTimes.last);
      final drift = (actualGap - expectedGap).abs();
      if (drift > _tapTolerance) {
        setState(() {
          _tapTimes.clear();
          _feedback =
              'Le rythme ne correspond pas encore. Observe puis réessaie.';
        });
        if (!widget.isPractice && widget.figurine != null) {
          widget.gameState.failPtipoteArrivalRhythm(widget.figurine!);
        }
        _playPreview();
        return;
      }
    }
    _tapTimes.add(now);
    if (_tapTimes.length < _rhythm.length) {
      setState(() {});
      return;
    }
    _resolved = true;
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    if (!widget.isPractice && widget.figurine != null) {
      widget.gameState.hatchPtipoteArrival(widget.figurine!);
    }
    if (ptipoteStatsConfig.v2.rhythmHapticEnabled) {
      unawaited(HapticFeedback.mediumImpact());
    }
    setState(() {});
  }

  Future<void> _completeNaming({required bool keepSystemName}) async {
    final figurine = widget.figurine;
    if (figurine == null) {
      Navigator.of(context).pop();
      return;
    }
    final systemName = _profile?.systemName ?? figurine.displayName;
    final selectedName = keepSystemName ? systemName : _nameController.text;
    final finalName =
        selectedName.trim().isEmpty ? systemName : selectedName.trim();
    try {
      if (finalName != figurine.displayName &&
          figurine.canRename &&
          !figurine.tagUid.startsWith('co-breeding-')) {
        await FigurineService().renameMyFigurine(
          figurine: figurine,
          nickname: finalName,
        );
      }
      if (!mounted) return;
      widget.gameState.completePtipoteArrival(figurine, finalName);
      Navigator.of(context).pop();
      widget.onFinished?.call();
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _feedback = 'Le nom n’a pas pu être enregistré. Réessaie.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(
          _isHatched || _isNaming
              ? widget.isPractice
                  ? 'Test terminé'
                  : 'L’œuf a éclos'
              : 'L’œuf réagit',
        ),
        content: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: GestureDetector(
            onTap: _tap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _isPulsing ? 1.22 : 1,
                  child: Icon(
                    _isHatched || _isNaming
                        ? Icons.auto_awesome
                        : Icons.egg_alt_outlined,
                    size: 84,
                    color: _isHatched || _isNaming
                        ? Colors.amber
                        : _profile == null
                            ? null
                            : _eggColor(_profile!.typeId),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isHatched || _isNaming) ...[
                  // The keyboard must never hide the field where the player
                  // names the newborn P'TIPOTE. Keep the visual for revelation,
                  // then give naming the full dialog height.
                  if (!_isNaming &&
                      !widget.isPractice &&
                      widget.figurine != null)
                    SizedBox(
                      height: 116,
                      child: PtipoteImage(
                        type: widget.figurine!.type,
                        species: widget.figurine!.species,
                        visualAssetKey: _profile!.isProtocol
                            ? _profile!.visualAssetKey
                            : '',
                        height: 116,
                      ),
                    ),
                  if (!widget.isPractice && _profile != null) ...[
                    Text(
                      _profile!.typeId == PtipoteTypeId.vegetal
                          ? 'Type Végétal'
                          : _profile!.typeId == PtipoteTypeId.mineral
                              ? 'Type Minéral'
                              : 'Type Mycélien',
                    ),
                    Text('Nature : ${_profile!.natureId}'),
                    Text(
                      _profile!.isProtocol ? 'Protocole' : 'Vestige',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (_isNaming) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nom du P’TIPOTE',
                      ),
                    ),
                  ],
                ] else ...[
                  const Text('Observe les pulsations, puis tape en rythme.'),
                  const SizedBox(height: 8),
                  Text('${_tapTimes.length} / ${_rhythm.length} tapotements'),
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
        ),
        actions: _isHatched
            ? [
                FilledButton(
                  onPressed: () {
                    if (widget.isPractice || widget.figurine == null) {
                      Navigator.of(context).pop();
                    } else {
                      widget.gameState
                          .beginPtipoteArrivalNaming(widget.figurine!);
                      setState(() {});
                    }
                  },
                  child: Text(
                    widget.isPractice ? 'Fermer le test' : 'Nommer ce P’TIPOTE',
                  ),
                ),
              ]
            : _isNaming
                ? [
                    TextButton(
                      onPressed: () => _completeNaming(keepSystemName: true),
                      child: const Text('Garder ce nom'),
                    ),
                    FilledButton(
                      onPressed: () => _completeNaming(keepSystemName: false),
                      child: const Text('Confirmer'),
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

/// Shared rhythmic tap challenge used by eggs and active P’TIBUG tanks.
class _RhythmTapDialog extends StatefulWidget {
  const _RhythmTapDialog({
    required this.tapCount,
    required this.title,
    required this.onValidated,
  });

  final int tapCount;
  final String title;
  final VoidCallback onValidated;

  @override
  State<_RhythmTapDialog> createState() => _RhythmTapDialogState();
}

class _RhythmTapDialogState extends State<_RhythmTapDialog> {
  static const _tapTolerance = Duration(milliseconds: 1250);
  final List<Timer> _previewTimers = <Timer>[];
  final List<DateTime> _tapTimes = <DateTime>[];
  int _previewBeat = -1;
  bool _isPulsing = false;
  bool _validated = false;
  String? _feedback;

  List<int> get _rhythm =>
      _rhythmTapPatterns[(widget.tapCount.clamp(3, 6) - 3) as int];

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
    if (_validated) return;
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _previewTimers.clear();
    setState(() {
      _previewBeat = -1;
      _isPulsing = false;
      _feedback = null;
    });
    for (var beat = 0; beat < _rhythm.length; beat += 1) {
      _previewTimers.add(Timer(Duration(milliseconds: _rhythm[beat]), () {
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
      }));
    }
  }

  void _tap() {
    if (_validated) return;
    final now = DateTime.now();
    if (_tapTimes.isNotEmpty) {
      final index = _tapTimes.length;
      final expectedGap = Duration(
        milliseconds: _rhythm[index] - _rhythm[index - 1],
      );
      if ((now.difference(_tapTimes.last) - expectedGap).abs() >
          _tapTolerance) {
        setState(() {
          _tapTimes.clear();
          _feedback = 'Le rythme ne correspond pas encore. Réessaie.';
        });
        _playPreview();
        return;
      }
    }
    _tapTimes.add(now);
    if (_tapTimes.length < _rhythm.length) {
      setState(() {});
      return;
    }
    widget.onValidated();
    setState(() => _validated = true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_validated ? 'Rythme validé' : widget.title),
        content: GestureDetector(
          onTap: _tap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: _isPulsing ? 1.22 : 1,
                child: Icon(
                  _validated ? Icons.auto_awesome : Icons.water_drop_outlined,
                  size: 84,
                  color: _validated ? Colors.amber : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(_validated
                  ? 'Le bonus de temps a été appliqué à la cuve.'
                  : 'Observe les pulsations, puis tape en rythme.'),
              const SizedBox(height: 8),
              if (!_validated)
                Text('${_tapTimes.length} / ${_rhythm.length} tapotements'),
              if (_feedback != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(_feedback!, textAlign: TextAlign.center),
              ],
              if (!_validated)
                TextButton.icon(
                  onPressed: _playPreview,
                  icon: const Icon(Icons.replay),
                  label: const Text('Revoir le rythme'),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_validated ? 'Fermer' : 'Plus tard'),
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
              Text('Meubles intérieurs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      )),
              const Text(
                  'Installez librement les meubles depuis le stock de la Maison.'),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: const <String>[
                  'Meuble simple',
                  'Lumière solaire',
                  'Jardin bioponique',
                  'Bassin thermal',
                ].map((item) {
                  final installed = state.ptipoteHomeFurnitureItems
                      .where((value) => value == item)
                      .length;
                  final stock = state.resourceAmount(item);
                  return OutlinedButton(
                    onPressed: stock <= 0
                        ? null
                        : () {
                            final result =
                                state.installPtipoteHomeFurniture(item);
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)));
                          },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(Icons.add_circle_outline),
                        const SizedBox(height: 4),
                        Text(item, textAlign: TextAlign.center),
                        Text('$installed installé(s) · stock $stock',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  );
                }).toList(),
              ),
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
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            isScrollControlled: true,
                            builder: (_) => _ConstructionProjectSheet(
                              gameState: state,
                              targetId: 'house',
                              title: 'Améliorer la Maison',
                              description:
                                  'Choisissez une construction automatisée ou un Constructeur.',
                            ),
                          ),
                          icon: const Icon(Icons.construction_outlined),
                          label: const Text('Choisir le chantier'),
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
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: _viabilityBuildingId == null ? 0 : 22,
              child: Material(
                color: Colors.white.withValues(alpha: 0.20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.50)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onTap,
                  child: _content(),
                ),
              ),
            ),
            if (_viabilityBuildingId case final buildingId?)
              Positioned(
                left: 10,
                right: 10,
                bottom: 0,
                child: _MapViabilityBar(
                  state: gameState!.viabilityForBuilding(buildingId),
                  compact: true,
                ),
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

  String? get _viabilityBuildingId => switch (building.name) {
        'Maison' => 'house',
        'CampHeart' => 'campHeart',
        'Tour' => 'securityTower',
        'FabLab' => 'fablab',
        'Market' => 'market',
        'Logistics' => 'logistics',
        _ => null,
      };
}

class _MapViabilityBar extends StatelessWidget {
  const _MapViabilityBar({required this.state, this.compact = false});

  final BuildingViabilityState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ratio = (state.current / math.max(1, state.maximum)).clamp(0.0, 1.0);
    final color = ratio < .1
        ? const Color(0xFFB3261E)
        : ratio < .5
            ? Color.lerp(
                const Color(0xFFB3261E), const Color(0xFFE3B64A), ratio * 2)!
            : Color.lerp(const Color(0xFFE3B64A), const Color(0xFF8FAA58),
                (ratio - .5) * 2)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: ratio,
            backgroundColor: Colors.white.withValues(alpha: .68),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'Viabilité ${state.current}/${state.maximum}',
            style: const TextStyle(
              color: Color(0xFF2B2116),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              shadows: <Shadow>[Shadow(color: Colors.white, blurRadius: 6)],
            ),
          ),
        ],
      ],
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
    required this.xp,
    required this.level,
    required this.hunger,
    required this.rest,
    required this.energy,
    required this.energyMax,
    required this.hungerMax,
    required this.happiness,
    required this.attachment,
    required this.attachmentLevel,
    required this.happinessBreakdown,
    required this.jobLevels,
    required this.activity,
    required this.countdown,
    required this.onRename,
  });

  final PtipoteFigurine figurine;
  final int xp;
  final int level;
  final int hunger;
  final int rest;
  final int energy;
  final int energyMax;
  final int hungerMax;
  final double happiness;
  final double attachment;
  final int attachmentLevel;
  final PtipoteHappinessBreakdown happinessBreakdown;
  final Map<String, int> jobLevels;
  final String activity;
  final String countdown;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final xpRequired =
        math.max(1, ptipoteStatsConfig.xpRequiredForNextLevel(level));
    final xpProgress = (xp / xpRequired).clamp(0.0, 1.0);
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
                        label: 'Nature',
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
              'Niveau $level',
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
              '$xp / $xpRequired XP',
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
                    icon: Icons.restaurant_outlined,
                    label: 'Faim $hunger/$hungerMax'),
                _PtipoteStatusChip(
                    icon: Icons.bedtime_outlined, label: 'Sommeil $rest'),
                _PtipoteStatusChip(
                    icon: Icons.bolt_outlined,
                    label: 'Énergie $energy/$energyMax'),
              ],
            ),
            const SizedBox(height: 12),
            _PtipoteGauge(label: 'Énergie', value: energy, max: energyMax),
            _PtipoteGauge(label: 'Faim', value: hunger, max: hungerMax),
            _PtipoteGauge(label: 'Sommeil', value: rest, max: 100),
            _PtipoteGauge(
              label: 'Attachement · N$attachmentLevel',
              value: attachment,
              max: 50,
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showHappinessDetail(context),
              child:
                  _PtipoteGauge(label: 'Bonheur', value: happiness, max: 100),
            ),
            if (jobLevels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('MÉTIERS',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: jobLevels.entries
                    .map((entry) => Chip(
                          label:
                              Text('${_jobLabel(entry.key)} N${entry.value}'),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showHappinessDetail(BuildContext context) {
    final data = happinessBreakdown;
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
                Text('BONHEUR ${happiness.toStringAsFixed(1)} / 100',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(
                    'BESOINS MATÉRIELS ${data.material.toStringAsFixed(1)} / 30'),
                Text(
                    'Mobilier +${data.furniture.toStringAsFixed(1)} · Compagnie +${data.company.toStringAsFixed(1)} · Foyer +${data.homeLevel.toStringAsFixed(1)}'),
                const SizedBox(height: 8),
                Text('BESOINS VITAUX ${data.vital.toStringAsFixed(1)} / 20'),
                Text(
                    'Faim +${data.hunger.toStringAsFixed(1)} · Sommeil +${data.sleep.toStringAsFixed(1)}'),
                const SizedBox(height: 8),
                Text('ATTACHEMENT ${data.attachment.toStringAsFixed(1)} / 50'),
                Builder(builder: (_) {
                  final level = attachmentLevel;
                  final reduction = (level *
                          ptipoteDailyLifeConfig.attachmentLevelDecayReduction *
                          100)
                      .round();
                  final required =
                      ptipoteDailyLifeConfig.attachmentHoursForNextLevel(level);
                  return Text(
                    'Niveau $level · décroissance -${ptipoteDailyLifeConfig.attachmentDecayPerHour * (1 - level * ptipoteDailyLifeConfig.attachmentLevelDecayReduction)}/h'
                    '${reduction > 0 ? ' ($reduction % réduit)' : ''}'
                    '${required > 0 ? ' · ${required} h à 70 % minimum pour le niveau suivant' : ' · niveau maximum'}',
                  );
                }),
              ]),
        ),
      ),
    );
  }

  String _jobLabel(String id) => switch (id) {
        'artisan' => 'Artisan',
        'vendor' => 'Vendeur',
        'constructor' => 'Constructeur',
        _ => id,
      };
}

class _PtipoteGauge extends StatelessWidget {
  const _PtipoteGauge(
      {required this.label, required this.value, required this.max});
  final String label;
  final num value;
  final num max;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                  '$label ${value.toStringAsFixed(value is int ? 0 : 1)} / ${max.toStringAsFixed(max is int ? 0 : 1)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                      value:
                          max <= 0 ? 0 : (value / max).clamp(0, 1).toDouble(),
                      minHeight: 8)),
            ]),
      );
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
                      _InfoLine(label: 'Nature', value: figurine.species),
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

  Future<void> _selectCoBreedingXpTarget(CoBreedingXpReward reward) async {
    final physical = await _figurineService.watchMyFigurines().first;
    final available =
        widget.gameState.eligibleTargetsForCoBreedingXpReward(reward, physical);
    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun P’TIPOTE possédé compatible actuellement.'),
      ));
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
              'Bonus XP ${_ptipoteTypeName(reward.compatibleTypeId)}',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text('+${reward.xpAmount} XP · P’TIPOTE possédé de même Type.'),
            const SizedBox(height: 12),
            ...available.map(
              (figurine) => ListTile(
                leading: const Icon(Icons.pets_outlined),
                title: Text(figurine.displayName),
                subtitle: Text(_ptipoteTypeName(
                    widget.gameState.ptipoteV2ProfileFor(figurine).typeId)),
                onTap: () => Navigator.of(sheetContext).pop(figurine),
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final result = widget.gameState.consumeCoBreedingXpReward(
      reward.itemId,
      target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _selectConsumableTarget(CraftRecipe recipe) async {
    final physical = await _figurineService.watchMyFigurines().first;
    final available = widget.gameState
        .ptipotesAvailableForActivities(physical)
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
              if (widget.gameState.coBreedingXpRewards
                  .where((reward) => !reward.isConsumed)
                  .isNotEmpty) ...<Widget>[
                const Text('Bonus de Co-élevage',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...widget.gameState.coBreedingXpRewards
                    .where((reward) => !reward.isConsumed)
                    .map(
                      (reward) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(
                            'Bonus XP ${_ptipoteTypeName(reward.compatibleTypeId)}',
                          ),
                          subtitle: Text(
                            '+${reward.xpAmount} XP · P’TIPOTE possédé de même Type',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(
                            _selectCoBreedingXpTarget(reward),
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
              ],
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

class _ResidentInventorySlot extends StatelessWidget {
  const _ResidentInventorySlot({this.item});

  final ResidentOwnedItem? item;

  @override
  Widget build(BuildContext context) {
    final filled = item != null;
    final durability = item?.currentDurability;
    final maxDurability = item?.maxDurability;
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: filled
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .46),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .32),
          ),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Icon(
                filled ? _resourceIcon(item!.itemDefinitionId) : Icons.add,
                size: 34,
                color: filled ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
            if (filled && item!.quantity > 1)
              Positioned(
                top: 7,
                right: 8,
                child: Text('×${item!.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            if (filled)
              Positioned(
                left: 6,
                right: 6,
                bottom: durability == null ? 7 : 19,
                child: Text(
                  item!.itemDefinitionId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            if (durability != null && maxDurability != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: maxDurability == 0 ? 0 : durability / maxDurability,
                    minHeight: 6,
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
    'Filtre' ||
    'Cartouche de filtration' ||
    'Filtre personnel' =>
      Icons.filter_alt_outlined,
    'Tenue ombragée' ||
    'Tenue anti-pluie' ||
    'Tenue filtrante' =>
      Icons.checkroom_outlined,
    'Couche imperméabilisante' => Icons.water_drop_outlined,
    'Réflecteur thermique' => Icons.wb_sunny_outlined,
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
  _PtipoteActionKind action = _PtipoteActionKind.craft,
}) {
  return showModalBottomSheet<PtipoteFigurine>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .42,
      maxChildSize: .94,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
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
              ...figurines.map((figurine) {
                final selectable = !gameState.isBusy(figurine) &&
                    gameState.vitalityFor(figurine) >=
                        ptipoteStatsConfig.minimumMissionVitality;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.pets_outlined),
                    title: Text(figurine.displayName),
                    subtitle: Text(
                      selectable
                          ? _ptipoteActionBonusLabel(
                              gameState,
                              figurine,
                              action,
                            )
                          : _ptipoteActivityUnavailableReason(
                              gameState,
                              figurine,
                            ),
                    ),
                    trailing: selectable
                        ? const Icon(Icons.chevron_right)
                        : const Icon(Icons.block_outlined),
                    onTap: selectable
                        ? () => Navigator.of(context).pop(figurine)
                        : null,
                  ),
                );
              }),
          ],
        ),
      ),
    ),
  );
}

/// Shared Lisière-style group picker used by Research. It deliberately uses
/// the same availability and bonus rules as activity selection, while keeping
/// the minimum group size at one.
Future<List<PtipoteFigurine>?> _pickPtipoteGroupForResearch({
  required BuildContext context,
  required Zone0GameState gameState,
  required List<PtipoteFigurine> figurines,
}) {
  final selectedIds = <String>{};
  return showModalBottomSheet<List<PtipoteFigurine>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          minChildSize: .42,
          maxChildSize: .94,
          builder: (context, controller) => SafeArea(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
                Text(
                  'Envoyer en Recherche',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text('Sélectionnez au moins un P’TIPOTE disponible.'),
                const SizedBox(height: 12),
                ...figurines.map((figurine) {
                  final selectable = !gameState.isBusy(figurine) &&
                      gameState.vitalityFor(figurine) >=
                          ptipoteStatsConfig.minimumMissionVitality;
                  final selected = selectedIds.contains(figurine.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: selected,
                      enabled: selectable,
                      secondary: const Icon(Icons.pets_outlined),
                      title: Text(figurine.displayName),
                      subtitle: Text(
                        selectable
                            ? _ptipoteActionBonusLabel(
                                gameState,
                                figurine,
                                _PtipoteActionKind.harvest,
                              )
                            : _ptipoteActivityUnavailableReason(
                                gameState,
                                figurine,
                              ),
                      ),
                      onChanged: !selectable
                          ? null
                          : (value) => setSheetState(() {
                                if (value ?? false) {
                                  selectedIds.add(figurine.id);
                                } else {
                                  selectedIds.remove(figurine.id);
                                }
                              }),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                            figurines
                                .where((item) => selectedIds.contains(item.id))
                                .toList(growable: false),
                          ),
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text('Lancer avec ${selectedIds.length} P’TIPOTE(s)'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<PtipoteFigurine?> _pickPermanentFabLabWorker({
  required BuildContext context,
  required Zone0GameState gameState,
  required List<PtipoteFigurine> figurines,
  required FabLabRoom room,
}) {
  final workers = figurines
      .where((figurine) =>
          gameState.permanentWorkersFor(room).contains(figurine.id))
      .toList();
  return showModalBottomSheet<PtipoteFigurine>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .62,
      minChildSize: .35,
      maxChildSize: .9,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            Text(
              'Choisir un poste permanent',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (workers.isEmpty)
              const Text(
                  'Aucun P’TIPOTE permanent n’est affecté à cette salle.')
            else
              ...workers.map(
                (figurine) => ListTile(
                  leading: const Icon(Icons.pets_outlined),
                  title: Text(figurine.displayName),
                  subtitle:
                      const Text('Restera dans la salle après cet ordre.'),
                  onTap: () => Navigator.of(context).pop(figurine),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

enum _PtipoteActionKind { harvest, craft, security, commerce }

String _percent(double value) => '${(value * 100).round()} %';

/// A single, contextual summary for every P’TIPOTE picker. This reads the
/// modifier service, not widget-specific approximations, so the displayed
/// choice always matches the bonus applied when the activity starts.
String _ptipoteActionBonusLabel(
  Zone0GameState gameState,
  PtipoteFigurine figurine,
  _PtipoteActionKind action, {
  int groupCount = 1,
}) {
  final modifiers = gameState.modifiersFor(
    figurine,
    eligibleGroupPtipoteCount: groupCount,
  );
  final labels = <String>[];
  switch (action) {
    case _PtipoteActionKind.harvest:
      final gather = modifiers.gather;
      if (gather.organic != 0)
        labels.add('Organique +${_percent(gather.organic)}');
      if (gather.mineral != 0)
        labels.add('Minéral +${_percent(gather.mineral)}');
      if (gather.waste != 0) labels.add('Déchets +${_percent(gather.waste)}');
      if (gather.mycelium != 0)
        labels.add('Mycélium +${_percent(gather.mycelium)}');
      if (gather.genericGather != 0) {
        labels.add('Récolte +${_percent(gather.genericGather)}');
      }
      break;
    case _PtipoteActionKind.craft:
      if (modifiers.craftBonus != 0) {
        labels.add('Craft +${_percent(modifiers.craftBonus)}');
      }
      break;
    case _PtipoteActionKind.security:
      if (modifiers.missionSecurityBonus != 0) {
        labels.add('Sécurité +${_percent(modifiers.missionSecurityBonus)}');
      }
      if (modifiers.towerDefenseBonus != 0) {
        labels.add('Défense Tour +${_percent(modifiers.towerDefenseBonus)}');
      }
      if (modifiers.droneDefenseBonus != 0) {
        labels.add('Drones +${_percent(modifiers.droneDefenseBonus)}');
      }
      break;
    case _PtipoteActionKind.commerce:
      if (modifiers.commerceBonus != 0) {
        labels.add('Vente +${_percent(modifiers.commerceBonus)}');
      }
      break;
  }
  return labels.isEmpty
      ? 'Aucun bonus direct pour cette action.'
      : 'Bonus : ${labels.join(' · ')}';
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
        Zone0MessageMailbox.lisiere => 'Historique des bâtiments',
      };

  String get _emptyLabel => switch (mailbox) {
        Zone0MessageMailbox.companions => 'Aucun message P’TIPOTE ou P’TIBUG.',
        Zone0MessageMailbox.kernel => 'Aucun message du Kernel.',
        Zone0MessageMailbox.fablab => 'Aucune fin de craft.',
        Zone0MessageMailbox.lisiere =>
          'Aucune récolte ou amélioration récente.',
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lisière proche'),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              const Tab(text: 'Missions'),
              const Tab(text: 'P’TIBUG'),
              const Tab(text: 'Bâtiment'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            SafeArea(
              child: StreamBuilder<List<PtipoteFigurine>>(
                stream: _figurineService.watchMyFigurines(),
                builder: (context, snapshot) {
                  final figurines =
                      widget.gameState.ptipotesAvailableForActivities(
                    snapshot.data ?? const <PtipoteFigurine>[],
                  );
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
                      // The current expeditions are the first thing to see
                      // when opening the Lisière. Resident posts stay at the
                      // bottom, after the mission setup.
                      _ActiveMissionsCard(gameState: widget.gameState),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: const Text(
                          'Prélever les ressources naturelles du biome. Les Capsules de données se recherchent depuis la Tour de recherche.',
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
                                    label: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '${figurine.displayName} · V$vitality$suffix',
                                        ),
                                        if (suffix.isEmpty)
                                          Text(
                                            _ptipoteActionBonusLabel(
                                              widget.gameState,
                                              figurine,
                                              _PtipoteActionKind.harvest,
                                              groupCount: math.max(
                                                1,
                                                _selectedFigurineIds.contains(
                                                  figurine.id,
                                                )
                                                    ? selectedFigurines.length
                                                    : selectedFigurines.length +
                                                        1,
                                              ),
                                            ),
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                      ],
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
                      _CommunityBuildingPosts(
                        gameState: widget.gameState,
                        roles: const <CommunityRoleType>[
                          CommunityRoleType.lisiereObserver,
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            _PTibugTerritoryTab(
              gameState: widget.gameState,
              campHeartState: widget.campHeartState,
            ),
            _LisiereBuildingsTab(gameState: widget.gameState),
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
    final securityAtLaunch = widget.gameState.effectiveBiomeSecurityFor(_biome);
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
    final naturalMycelium = lisiereForageConfig
            .myceliumExploration.yieldByRichness[biome.myceliumRichness] ??
        0;
    if (naturalMycelium > 0) {
      var mycelium = naturalMycelium *
          duration.theoreticalHours *
          intensity.rewardMultiplier;
      final restState = widget.gameState.restStateFor(figurine);
      if (restState == PtipoteRestState.wellRested) {
        mycelium *= 1 + ptipoteStatsConfig.wellRestedRewardBonus;
      } else if (restState == PtipoteRestState.tired ||
          restState == PtipoteRestState.exhausted) {
        mycelium *= 1 - ptipoteStatsConfig.tiredRewardPenalty;
      }
      if (figurine.elementType == PtipoteElementType.fungal) {
        mycelium *=
            1 + lisiereForageConfig.myceliumExploration.mycelialTypeGatherBonus;
      }
      rewards['Mycélium'] = math.max(0, mycelium.round());
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
    final localSecurity = widget.gameState.effectiveBiomeSecurityFor(_biome);
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

class _LisiereBuildingsTab extends StatefulWidget {
  const _LisiereBuildingsTab({
    required this.gameState,
    this.initialBiome,
    this.showBiomeDetail = false,
  });
  final Zone0GameState gameState;
  final ForageBiome? initialBiome;
  final bool showBiomeDetail;
  @override
  State<_LisiereBuildingsTab> createState() => _LisiereBuildingsTabState();
}

class _LisiereBuildingsTabState extends State<_LisiereBuildingsTab> {
  late ForageBiome biome;

  @override
  void initState() {
    super.initState();
    biome = widget.initialBiome ?? ForageBiome.plaineRiche;
  }

  void _openBiome(ForageBiome selectedBiome) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LisiereBuildingsTab(
          gameState: widget.gameState,
          initialBiome: selectedBiome,
          showBiomeDetail: true,
        ),
      ),
    );
  }

  void _editSecondaryModules(BuildContext context, Zone0GameState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          String label(BiomeSecondaryModuleType type) => switch (type) {
                BiomeSecondaryModuleType.security =>
                  'Stabilisation sécuritaire',
                BiomeSecondaryModuleType.research => 'Veille scientifique',
                BiomeSecondaryModuleType.weatherProtection =>
                  'Protection météorologique',
              };
          String effect(BiomeSecondaryModuleType type, int level) {
            final synergy = lisiereForageConfig
                .territoryBuildings.biofermenter.biomeSynergy;
            return switch (type) {
              BiomeSecondaryModuleType.security =>
                'Sécurité minimum ${synergy.securityFloors[level] ?? 0}',
              BiomeSecondaryModuleType.research =>
                'Recherche locale minimum ${synergy.researchFloors[level] ?? 0}',
              BiomeSecondaryModuleType.weatherProtection =>
                '-${((synergy.weatherDamageReductions[level] ?? 0) * 100).round()} % dégâts météo physiques',
            };
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Modules secondaires',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text(
                      'Deux emplacements maximum. Chaque niveau est construit séparément ; défaites un module pour libérer un emplacement.',
                    ),
                    const SizedBox(height: 12),
                    for (final type in BiomeSecondaryModuleType.values)
                      Builder(builder: (context) {
                        final level =
                            state.biomeSecondaryModuleLevel(biome, type);
                        final project = state.projectFor(
                          state.biomeSecondaryModuleTargetId(biome, type),
                        );
                        final nextLabel = level == 0
                            ? 'Installer'
                            : level >= 3
                                ? 'Niveau maximum'
                                : 'Améliorer N${level + 1}';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(label(type),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(level == 0
                                    ? 'Non installé'
                                    : 'N$level · ${effect(type, level)}'),
                                if (project.isInProgress) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text('Travaux en cours',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    FilledButton.icon(
                                      onPressed:
                                          level >= 3 || project.isInProgress
                                              ? null
                                              : () => _showBuildingProject(
                                                    sheetContext,
                                                    gameState: state,
                                                    targetId: state
                                                        .biomeSecondaryModuleTargetId(
                                                      biome,
                                                      type,
                                                    ),
                                                    title: label(type),
                                                    description:
                                                        'Module secondaire du bâtiment territorial.',
                                                  ),
                                      icon: const Icon(Icons.upgrade_outlined),
                                      label: Text(nextLabel),
                                    ),
                                    if (level > 0)
                                      OutlinedButton(
                                        onPressed: () {
                                          final result =
                                              state.removeBiomeSecondaryModule(
                                            biome,
                                            type,
                                          );
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(SnackBar(
                                                  content:
                                                      Text(result.message)));
                                          setSheetState(() {});
                                          setState(() {});
                                        },
                                        child: const Text('Défaire'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showBiomeDetail) {
      return _LisiereBuildingsMap(
        gameState: widget.gameState,
        onOpen: _openBiome,
      );
    }
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 250) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Retour à la carte Bâtiment',
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Bâtiment · ${lisiereForageConfig.biomes[biome]!.label}'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Historique du bâtiment',
              icon: const Icon(Icons.mail_outline),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => MissionReportsSheet(
                  gameState: widget.gameState,
                  mailbox: Zone0MessageMailbox.lisiere,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(child: _buildDetail(context)),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final state = widget.gameState;
    final zone = state.territoryZone(biome);
    final config = lisiereForageConfig.territoryBuildings.biofermenter;
    final built = zone.buildingId == 'biofermenter';
    final bioTarget = state.biofermenterTargetId(biome);
    final forestTarget = state.edibleForestTargetId(biome);
    final networkTarget = state.mycelialNetworkTargetId(biome);
    final calciumTarget = state.calciumBasinTargetId(biome);
    final bioProject = state.projectFor(bioTarget);
    final forestProject = state.projectFor(forestTarget);
    final networkProject = state.projectFor(networkTarget);
    final calciumProject = state.projectFor(calciumTarget);
    final label = lisiereForageConfig.biomes[biome]!.label;
    final organicReserveCapacity =
        state.biofermenterOrganicReserveCapacity(biome);
    final synergy = config.biomeSynergy;
    final secondaryModules = zone.secondaryModules.entries
        .where((entry) => entry.value > 0)
        .map((entry) => '${switch (entry.key) {
              'security' => 'Sécurité',
              'research' => 'Veille scientifique',
              'weatherProtection' => 'Protection météo',
              _ => entry.key,
            }} N${entry.value}')
        .join(' · ');
    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Text('Bâtiment territorial',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('Cet emplacement appartient à cette zone uniquement.'),
      const SizedBox(height: 12),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18)),
                    Text(zone.terrainTags.contains('mineralBasin')
                        ? 'Terrain : Bassin minéral'
                        : 'Terrain : normal'),
                    const Divider(),
                    if (!built) ...<Widget>[
                      const Text(
                          'Emplacement libre · Biofermenteur mycélien compatible.'),
                      Text(
                          'Durée : ${config.constructionMinutesByLevel[1]} min'),
                      FilledButton.icon(
                          onPressed: () {
                            _showBuildingProject(context,
                                gameState: state,
                                targetId: bioTarget,
                                title: 'Biofermenteur mycélien',
                                description:
                                    'Produit de l’Organique passivement dans $label.');
                          },
                          icon: const Icon(Icons.eco_outlined),
                          label: Text(bioProject.isInProgress
                              ? 'Travaux : ${_countdownLabel(bioProject.endsAt!)}'
                              : 'Construire le Biofermenteur')),
                    ] else ...<Widget>[
                      Text(
                          'Biofermenteur mycélien · niveau ${zone.buildingLevel}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(
                        'Module principal : ${zone.mycelialNetworkInstalled ? 'Réseau mycélien N${zone.mycelialNetworkModuleLevel}' : zone.edibleForestInstalled ? 'Forêt comestible N${zone.edibleForestModuleLevel}' : zone.calciumBasinInstalled ? 'Bassin minéral N${zone.calciumBasinModuleLevel}' : 'aucun'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Modules secondaires (${zone.secondaryModules.length}/${synergy.secondarySlotCount}) : ${secondaryModules.isEmpty ? 'aucun' : secondaryModules}',
                      ),
                      TextButton.icon(
                        onPressed: () => _editSecondaryModules(context, state),
                        icon: const Icon(Icons.tune_outlined),
                        label: const Text('Configurer les modules secondaires'),
                      ),
                      const SizedBox(height: 8),
                      _BuildingViabilityCard(
                        gameState: state,
                        buildingId: bioTarget,
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'Production passive : ${state.biofermenterOrganicPerDay(biome).toStringAsFixed(1)} Organique/jour'),
                      const SizedBox(height: 4),
                      Text(
                        'Réserve organique : ${zone.organicReserve}/$organicReserveCapacity',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 9,
                          value: organicReserveCapacity == 0
                              ? 0
                              : (zone.organicReserve / organicReserveCapacity)
                                  .clamp(0, 1),
                          color: Colors.green.shade700,
                          backgroundColor: Colors.green.shade100,
                        ),
                      ),
                      Text(
                          'Forêt comestible : ${zone.edibleForestInstalled ? 'Base ${config.passiveOrganicPerDayByLevel[zone.buildingLevel] ?? 0}/j · ${state.activePollinatorsForBiofermenter(biome)} Pollinisateur(s) × +${synergy.ptibugBonusPerDay.toStringAsFixed(0)} · N${zone.edibleForestModuleLevel}' : 'non installée'}'),
                      Text(
                          'Réseau mycélien : ${zone.mycelialNetworkInstalled ? 'Base ${config.baseMyceliumPerDay.toStringAsFixed(0)}/j · ${state.activeMycelialPTibugsForBiofermenter(biome)} P’TIBUG mycéliens × +${synergy.ptibugBonusPerDay.toStringAsFixed(0)} · N${zone.mycelialNetworkModuleLevel}' : 'non installé'}'),
                      if (zone.mycelialNetworkInstalled) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                            'Réserve mycélienne : ${zone.myceliumReserve}/${state.biofermenterMyceliumReserveCapacity(biome)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            minHeight: 9,
                            value: state.biofermenterMyceliumReserveCapacity(
                                        biome) ==
                                    0
                                ? 0
                                : (zone.myceliumReserve /
                                        state
                                            .biofermenterMyceliumReserveCapacity(
                                                biome))
                                    .clamp(0, 1),
                            color: Colors.purple.shade500,
                            backgroundColor: Colors.purple.shade100,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: <Widget>[
                        OutlinedButton(
                            onPressed: zone.buildingLevel >= 4
                                ? null
                                : () {
                                    _showBuildingProject(context,
                                        gameState: state,
                                        targetId: bioTarget,
                                        title: 'Biofermenteur mycélien',
                                        description:
                                            'Amélioration niveau ${zone.buildingLevel + 1} · ${config.constructionMinutesByLevel[zone.buildingLevel + 1]} min.');
                                  },
                            child: Text(bioProject.isInProgress
                                ? 'Travaux : ${_countdownLabel(bioProject.endsAt!)}'
                                : 'Améliorer')),
                        OutlinedButton(
                            onPressed: zone.edibleForestModuleLevel >= 3 ||
                                    (zone.mycelialNetworkInstalled &&
                                        !zone.edibleForestInstalled)
                                ? null
                                : () {
                                    _showBuildingProject(context,
                                        gameState: state,
                                        targetId: forestTarget,
                                        title: 'Forêt comestible',
                                        description:
                                            'Module principal niveau ${zone.edibleForestModuleLevel + 1} · ${config.edibleForestConstructionMinutes} min.');
                                  },
                            child: Text(forestProject.isInProgress
                                ? 'Travaux : ${_countdownLabel(forestProject.endsAt!)}'
                                : zone.edibleForestInstalled
                                    ? 'Améliorer Forêt comestible'
                                    : 'Installer Forêt comestible')),
                        OutlinedButton(
                            onPressed: zone.mycelialNetworkModuleLevel >= 3 ||
                                    (zone.edibleForestInstalled &&
                                        !zone.mycelialNetworkInstalled) ||
                                    !config.mycelialNetworkEnabled
                                ? null
                                : () {
                                    _showBuildingProject(context,
                                        gameState: state,
                                        targetId: networkTarget,
                                        title: 'Réseau mycélien',
                                        description:
                                            'Module principal niveau ${zone.mycelialNetworkModuleLevel + 1} · ${config.mycelialNetworkConstructionMinutes} min.');
                                  },
                            child: Text(networkProject.isInProgress
                                ? 'Travaux : ${_countdownLabel(networkProject.endsAt!)}'
                                : zone.mycelialNetworkInstalled
                                    ? 'Améliorer Réseau mycélien'
                                    : 'Installer Réseau mycélien')),
                        OutlinedButton.icon(
                          onPressed: zone.organicReserve <= 0
                              ? null
                              : () {
                                  final result =
                                      state.retrieveBiofermenterOrganic(biome);
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                },
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(
                            'Récolter l’Organique (${zone.organicReserve})',
                          ),
                        ),
                        if (zone.mycelialNetworkInstalled)
                          OutlinedButton.icon(
                            onPressed: zone.myceliumReserve <= 0
                                ? null
                                : () {
                                    final result = state
                                        .retrieveBiofermenterMycelium(biome);
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(result.message)));
                                  },
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(
                                'Récolter le Mycélium (${zone.myceliumReserve})'),
                          ),
                        if (state.canInstallCalciumBasin(biome) &&
                            zone.calciumBasinModuleLevel < 3)
                          OutlinedButton(
                            onPressed: () => _showBuildingProject(
                              context,
                              gameState: state,
                              targetId: calciumTarget,
                              title: 'Bassin minéral',
                              description:
                                  'Module principal niveau ${zone.calciumBasinModuleLevel + 1} : produit du Minéral avec de l’eau de pluie.',
                            ),
                            child: Text(calciumProject.isInProgress
                                ? 'Travaux : ${_countdownLabel(calciumProject.endsAt!)}'
                                : zone.calciumBasinInstalled
                                    ? 'Améliorer Bassin minéral'
                                    : 'Installer Bassin minéral'),
                          ),
                      ]),
                      if (zone.calciumBasinInstalled) ...<Widget>[
                        const SizedBox(height: 16),
                        const Text('Bassin minéral',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text(
                            'Base ${state.mineralBasinBaseProductionPerDay(biome).toStringAsFixed(0)}/j · ${state.activeCalciumMinerPTibugsForBiofermenter(biome)} Mineur(s) × +${synergy.ptibugBonusPerDay.toStringAsFixed(0)} · module N${zone.calciumBasinModuleLevel}'),
                        Text(
                            'Production finale : ${state.mineralBasinProductionPerDay(biome).toStringAsFixed(1)} Minéral/j · consomme ${state.mineralBasinOrganicConsumptionPerDay(biome).toStringAsFixed(1)} Organique et ${state.mineralBasinWaterConsumptionPerDay(biome).toStringAsFixed(1)} Eau/j.'),
                        Text(
                            'Substrat minéral fixe : ${zone.lithocultureMineralTank}/${state.lithocultureTankCapacity(biome)} · il n’est jamais consommé.'),
                        Row(children: <Widget>[
                          Expanded(
                              child: _BiofermenterTank(
                            label: 'Eau',
                            icon: Icons.water_drop_outlined,
                            value: zone.calciumWaterTank,
                            capacity: state.calciumWaterCapacity(biome),
                            color: Colors.blue,
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _BiofermenterTank(
                            label: 'Organique',
                            icon: Icons.eco_outlined,
                            value: zone.calciumOrganicTank,
                            capacity: state.calciumOrganicCapacity(biome),
                            color: Colors.green,
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _BiofermenterTank(
                            label: 'Réserve minéral',
                            icon: Icons.diamond_outlined,
                            value: zone.calciumMineralReserve,
                            capacity:
                                state.calciumMineralReserveCapacity(biome),
                            color: Colors.grey,
                          )),
                        ]),
                        Wrap(spacing: 8, children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () {
                              final result =
                                  state.transferMineralToBasinSubstrate(
                                biome,
                                1,
                              );
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('1 Minéral au substrat'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              final result =
                                  state.transferOrganicToCalciumBasin(biome, 1);
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(result.message)));
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('1 Organique'),
                          ),
                          OutlinedButton.icon(
                            onPressed: zone.calciumMineralReserve <= 0
                                ? null
                                : () {
                                    final result = state
                                        .retrieveCalciumBasinMineral(biome);
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(result.message)));
                                  },
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Récolter le Minéral'),
                          ),
                        ]),
                      ],
                    ],
                  ]))),
    ]);
  }
}

class _BiofermenterTank extends StatelessWidget {
  const _BiofermenterTank({
    required this.label,
    required this.icon,
    required this.value,
    required this.capacity,
    required this.color,
  });

  final String label;
  final IconData icon;
  final int value;
  final int capacity;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        Text('$label\n$value/$capacity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Stack(alignment: Alignment.center, children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              minHeight: 28,
              value: capacity <= 0 ? 0 : (value / capacity).clamp(0, 1),
              color: color,
              backgroundColor: color.withValues(alpha: .16),
            ),
          ),
          Icon(icon, size: 17, color: Colors.white),
        ]),
      ]);
}

class _CompactViabilityBar extends StatelessWidget {
  const _CompactViabilityBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: value.clamp(0, 1),
            color: Colors.green.shade700,
            backgroundColor: Colors.grey.shade300,
          ),
        ),
      );
}

class _LisiereBuildingsMap extends StatelessWidget {
  const _LisiereBuildingsMap({
    required this.gameState,
    required this.onOpen,
  });

  final Zone0GameState gameState;
  final ValueChanged<ForageBiome> onOpen;

  @override
  Widget build(BuildContext context) {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Bâtiments de Lisière',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const SizedBox(height: 4),
        const Text(
          'Chaque biome possède un emplacement territorial. Touchez une zone pour consulter ou construire son bâtiment.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: .78,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
              ),
              itemCount: cells.length,
              itemBuilder: (context, index) {
                final biome = cells[index];
                if (biome == null) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }
                final unlocked = gameState.isBiomeUnlocked(biome);
                final zone = gameState.territoryZone(biome);
                final built = zone.buildingId != null;
                final label = lisiereForageConfig.biomes[biome]!.label;
                return Material(
                  color: unlocked
                      ? Theme.of(context).colorScheme.surfaceContainerLow
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(children: <Widget>[
                    InkWell(
                      // La tuile informe seulement : l'entrée est volontairement
                      // séparée afin d'éviter toute ouverture accidentelle.
                      onTap: null,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (built)
                              IconButton(
                                tooltip: 'Récolter',
                                visualDensity: VisualDensity.compact,
                                onPressed: zone.organicReserve <= 0
                                    ? null
                                    : () {
                                        final result = gameState
                                            .retrieveBiofermenterOrganic(biome);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(result.message)),
                                        );
                                      },
                                icon: const Icon(Icons.inventory_2_outlined),
                              ),
                            Icon(
                              unlocked
                                  ? built
                                      ? Icons.factory_outlined
                                      : Icons.add_home_work_outlined
                                  : Icons.lock_outline,
                              color: built
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              !unlocked
                                  ? 'Bientôt disponible'
                                  : built
                                      ? 'Biofermenteur niv. ${zone.buildingLevel}'
                                      : 'Emplacement libre',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (built &&
                                (zone.mycelialNetworkInstalled ||
                                    zone.edibleForestInstalled ||
                                    zone.calciumBasinInstalled))
                              Text(
                                zone.mycelialNetworkInstalled
                                    ? 'Réseau mycélien'
                                    : zone.edibleForestInstalled
                                        ? 'Forêt comestible'
                                        : 'Bassin minéral',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 8, fontWeight: FontWeight.w700),
                              ),
                            if (built)
                              _CompactViabilityBar(
                                value: gameState
                                        .viabilityForBuilding(
                                          gameState.biofermenterTargetId(biome),
                                        )
                                        .current /
                                    gameState
                                        .viabilityForBuilding(
                                          gameState.biofermenterTargetId(biome),
                                        )
                                        .maximum,
                              ),
                            if (built)
                              TextButton(
                                onPressed: () => onOpen(biome),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  minimumSize: const Size(0, 28),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: const Text('Entrer'),
                              ),
                            if (unlocked &&
                                zone.terrainTags.contains('mineralBasin'))
                              const Text(
                                'Bassin minéral',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 9),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (built)
                      Positioned(
                        top: 5,
                        left: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: Text(
                              '${zone.organicReserve}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
        ),
      ],
    );
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

  Future<void> _openCollectionDetail(PTibug bug) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PTibugNurseryPage(
            gameState: widget.gameState,
            campHeartLevel: widget.campHeartState.campHeartLevel,
            campHeartState: widget.campHeartState,
            initialTabIndex: 1,
            initialPTibugDetailId: bug.id,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final gameState = widget.gameState;
    final campHeartState = widget.campHeartState;
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
        FilledButton.icon(
          onPressed: gameState.plaineNurseryTerritory.isBuilt
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PTibugNurseryPage(
                      gameState: gameState,
                      campHeartLevel: campHeartState.campHeartLevel,
                      campHeartState: campHeartState,
                    ),
                  ))
              : null,
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('Entrer dans la Nurserie'),
        ),
        const SizedBox(height: 12),
        _PTibugTerritoryMap(
          gameState: gameState,
          onOpen: _openTerritorySquare,
          onAssign: _confirmMapAssignment,
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

  void _message(BuildContext context, String message) {
    final normalized = message.toLowerCase();
    if (!normalized.contains('insuffisant') &&
        !normalized.contains('manque') &&
        !normalized.contains('pas assez') &&
        !normalized.contains('impossible')) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTerritorySquare(ForageBiome biome) async {
    final building = biome == ForageBiome.plaineRiche
        ? widget.gameState.plaineNurseryTerritory
        : widget.gameState.territoryBuildingForId('refuge-${biome.name}');
    if (biome == ForageBiome.plaineRiche && building?.isBuilt != true) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _ConstructionProjectSheet(
          gameState: widget.gameState,
          targetId: 'plaineNursery',
          title: 'Nurserie P’TIBUG',
          description:
              'Installe des P’TIBUG dans la Savane tropicale pour produire lentement des ressources.',
          campHeartLevel: widget.campHeartState.campHeartLevel,
          campHeartState: widget.campHeartState,
        ),
      );
      return;
    }
    if (biome == ForageBiome.plaineRiche && building?.isBuilt == true) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PTibugNurseryPage(
          gameState: widget.gameState,
          campHeartLevel: widget.campHeartState.campHeartLevel,
          campHeartState: widget.campHeartState,
        ),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PTibugRefugePage(
        gameState: widget.gameState,
        biome: biome,
        building: building,
        campHeartState: widget.campHeartState,
        onShowDetails: _openCollectionDetail,
      ),
    ));
  }

  Future<void> _confirmMapAssignment(PTibug bug, ForageBiome biome) async {
    final building = biome == ForageBiome.plaineRiche
        ? widget.gameState.plaineNurseryTerritory
        : widget.gameState.territoryBuildingForId('refuge-${biome.name}');
    if (building?.isBuilt != true) return;
    final targetLabel = biome == ForageBiome.plaineRiche
        ? 'la Nurserie'
        : 'le refuge ${lisiereForageConfig.biomes[biome]!.label}';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Affecter ce P’TIBUG ?'),
        content: Text(
          'Voulez-vous affecter ${bug.displayName} de l’espèce ${widget.gameState.pTibugSpeciesNameFor(bug)} à $targetLabel ?',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Oui')),
        ],
      ),
    );
    if (accepted == true && mounted) {
      _message(context,
          widget.gameState.assignPTibugToTerritory(bug, building!.id).message);
    }
  }
}

class _PTibugRefugePage extends StatelessWidget {
  const _PTibugRefugePage({
    required this.gameState,
    required this.biome,
    required this.building,
    required this.campHeartState,
    required this.onShowDetails,
  });

  final Zone0GameState gameState;
  final ForageBiome biome;
  final PTibugTerritoryBuilding? building;
  final CampHeartState campHeartState;
  final ValueChanged<PTibug> onShowDetails;

  @override
  Widget build(BuildContext context) {
    final label = lisiereForageConfig.biomes[biome]!.label;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 250) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Retour à la carte P’TIBUG',
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Refuge · $label'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _PTibugTerritoryBiomeCard(
                gameState: gameState,
                biome: biome,
                building: building,
                campHeartState: campHeartState,
                onShowDetails: onShowDetails,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PTibugTerritoryMap extends StatelessWidget {
  const _PTibugTerritoryMap({
    required this.gameState,
    required this.onOpen,
    required this.onAssign,
  });

  final Zone0GameState gameState;
  final ValueChanged<ForageBiome> onOpen;
  final Future<void> Function(PTibug bug, ForageBiome biome) onAssign;

  @override
  Widget build(BuildContext context) {
    // Same stable 3×3 geography as the Tour exploration map.
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: .95,
            crossAxisSpacing: 7,
            mainAxisSpacing: 7,
          ),
          itemCount: cells.length,
          itemBuilder: (context, index) {
            final biome = cells[index];
            if (biome == null) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }
            final unlocked = gameState.isBiomeUnlocked(biome);
            final building = biome == ForageBiome.plaineRiche
                ? gameState.plaineNurseryTerritory
                : gameState.territoryBuildingForId('refuge-${biome.name}');
            return _PTibugTerritoryMapCell(
              gameState: gameState,
              biome: biome,
              building: building,
              unlocked: unlocked,
              onOpen: () => onOpen(biome),
              onAssign: (bug) => onAssign(bug, biome),
            );
          },
        ),
      ),
    );
  }
}

class _PTibugTerritoryMapCell extends StatelessWidget {
  const _PTibugTerritoryMapCell({
    required this.gameState,
    required this.biome,
    required this.building,
    required this.unlocked,
    required this.onOpen,
    required this.onAssign,
  });

  final Zone0GameState gameState;
  final ForageBiome biome;
  final PTibugTerritoryBuilding? building;
  final bool unlocked;
  final VoidCallback onOpen;
  final ValueChanged<PTibug> onAssign;

  @override
  Widget build(BuildContext context) {
    final built = building?.isBuilt == true;
    final label = lisiereForageConfig.biomes[biome]!.label;
    final viability =
        built ? gameState.viabilityForBuilding(building!.id) : null;
    final activeCount =
        built ? gameState.pTibugsForTerritory(building!.id).length : 0;
    final capacity = built ? gameState.pTibugTerritoryCapacity(building!) : 0;
    return DragTarget<PTibug>(
      onWillAcceptWithDetails: (_) => unlocked && built,
      onAcceptWithDetails: (details) => onAssign(details.data),
      builder: (context, candidates, _) => Material(
        color: candidates.isNotEmpty
            ? Theme.of(context).colorScheme.primaryContainer
            : unlocked
                ? Theme.of(context).colorScheme.surfaceContainerLow
                : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: unlocked ? onOpen : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  !unlocked
                      ? Icons.lock_outline
                      : built
                          ? Icons.home_work_outlined
                          : Icons.add_home_work_outlined,
                  color: built ? Theme.of(context).colorScheme.primary : null,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w900),
                ),
                if (unlocked)
                  Text(
                    built
                        ? biome == ForageBiome.plaineRiche
                            ? 'Nurserie'
                            : 'Refuge'
                        : biome == ForageBiome.plaineRiche
                            ? 'Construire la Nurserie'
                            : 'Construire un Refuge',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                if (viability != null) ...<Widget>[
                  const SizedBox(height: 4),
                  _MapViabilityBar(state: viability),
                  Text(
                    '$activeCount/$capacity P’TIBUG',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PTibugTerritoryBiomeCard extends StatelessWidget {
  const _PTibugTerritoryBiomeCard({
    required this.gameState,
    required this.biome,
    required this.building,
    required this.campHeartState,
    this.onDragUpdate,
    this.onShowDetails,
  });

  final Zone0GameState gameState;
  final ForageBiome biome;
  final PTibugTerritoryBuilding? building;
  final CampHeartState campHeartState;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<PTibug>? onShowDetails;

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
                      '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.effectiveBiomeSecurityFor(biome)}%'),
                  const SizedBox(height: 8),
                  const Text(
                      'La Savane tropicale accueille uniquement la Nurserie principale.'),
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
                  '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.effectiveBiomeSecurityFor(biome)}%'),
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
                  '${visual.icon} ${visual.label} · $biomass% · sécurité ${gameState.effectiveBiomeSecurityFor(biome)}%'),
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
                gameState: gameState,
                building: activeBuilding,
                consumption: consumption,
              ),
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
                    label: Text(
                      'Ouvrir une Bio-batterie (+${gameState.energyFromBioBatteryForBuildingLevel(activeBuilding.level)} énergie)',
                    ),
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
                          onDragUpdate: onDragUpdate,
                          onShowDetails: onShowDetails))
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
  ) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ConstructionProjectSheet(
          gameState: gameState,
          targetId: building.id,
          title:
              'Améliorer le Refuge · niveau ${gameState.projectFor(building.id).targetLevel}',
          description:
              'Déposez les ressources progressivement. La fenêtre reste ouverte entre chaque dépôt.',
        ),
      );

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
                  onPressed: () => _showRepairOptions(context),
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

  void _showRepairOptions(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Réparer le bâtiment'),
          content: const Text(
            'Choisissez d’abord la quantité de Viabilité à restaurer. Vous pourrez ensuite payer normalement ou intervenir vous-même.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _showRepairChoices(context);
              },
              child: const Text('Choisir la réparation'),
            ),
          ],
        ),
      );

  void _showRepairChoices(BuildContext context) {
    final missing = gameState.viabilityForBuilding(buildingId).maximum -
        gameState.viabilityForBuilding(buildingId).current;
    final choices = <int>{10, 20, 30, 50, 100, missing}
        .where((gain) => gain > 0)
        .map((gain) => ((gain / 10).ceil() * 10).clamp(10, 100))
        .toList()
      ..sort();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(children: <Widget>[
                const Text('Réparer le bâtiment',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text(
                    'Le mini-jeu restaure toujours 20 % de Viabilité sans consommer de coût.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final attempt =
                        gameState.beginInteractiveRepair(buildingId, gain: 20);
                    if (attempt == null) {
                      _showMessage(
                          context, 'Réparation interactive indisponible.');
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    _openRepairMiniGame(context, attempt);
                  },
                  icon: const Icon(Icons.handyman_outlined),
                  label: const Text('Réparer soi-même · +20 %'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final result = gameState.repairBuildingWithKit(buildingId);
                    if (result.success) Navigator.of(sheetContext).pop();
                    _showMessage(context, result.message);
                  },
                  icon: const Icon(Icons.handyman_outlined),
                  label: const Text('Utiliser un Kit de réparation · +15 %'),
                ),
                const SizedBox(height: 8),
                Expanded(
                    child: ListView(
                        children: choices.map((gain) {
                  final cost = gameState.buildingRepairCosts(buildingId, gain);
                  final compactCost =
                      '${cost['Organique'] ?? 0} O. / ${cost['Minéral'] ?? 0} M. ${(cost['Bio-batteries'] ?? 0) + (cost['Bio-piles'] ?? 0) / 100.0 == 0 ? '0' : ((cost['Bio-batteries'] ?? 0) + (cost['Bio-piles'] ?? 0) / 100.0).toStringAsFixed(2).replaceAll('.', ',')} Bat.';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () {
                        final result =
                            gameState.repairBuilding(buildingId, gain: gain);
                        if (result.success) Navigator.of(sheetContext).pop();
                        _showMessage(context, result.message);
                      },
                      child: Text('Faire réparer · +$gain %\n$compactCost',
                          textAlign: TextAlign.center),
                    ),
                  );
                }).toList())),
              ]),
            )),
      ),
    );
  }

  void _openRepairMiniGame(
          BuildContext context, RepairMiniGameAttempt attempt) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _RepairMiniGameSheet(gameState: gameState, attempt: attempt),
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

class _RepairMiniGameSheet extends StatelessWidget {
  const _RepairMiniGameSheet({required this.gameState, required this.attempt});
  final Zone0GameState gameState;
  final RepairMiniGameAttempt attempt;

  Zone0ActionResult _complete() =>
      gameState.completeInteractiveRepair(attempt.id);

  @override
  Widget build(BuildContext context) {
    final child = switch (attempt.gameType) {
      RepairMiniGameType.pipes => _PipeRepairGameSheet(
          onSolved: _complete,
          seed: attempt.seed,
          difficulty: towerOperationsConfig.buildingViability.repairMiniGames
              .pipesForLevel(attempt.buildingLevel)),
      RepairMiniGameType.colorMatch => _ColorMatchRepairGame(
          seed: attempt.seed,
          difficulty: towerOperationsConfig.buildingViability.repairMiniGames
              .colorMatchForLevel(attempt.buildingLevel),
          onSolved: _complete,
        ),
      RepairMiniGameType.waterSort => _WaterSortRepairGame(
          seed: attempt.seed,
          difficulty: towerOperationsConfig.buildingViability.repairMiniGames
              .waterSortForLevel(attempt.buildingLevel),
          onSolved: _complete,
        ),
    };
    return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: <Widget>[
            Expanded(
                child: Text(
                    '${attempt.repairGain}% de Viabilité · niveau ${attempt.buildingLevel}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            TextButton(
                onPressed: () {
                  gameState.cancelInteractiveRepair(attempt.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Quitter')),
          ])),
      child,
    ]));
  }
}

void _openSharedRepairMiniGame(BuildContext context, Zone0GameState gameState,
        RepairMiniGameAttempt attempt) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _RepairMiniGameSheet(gameState: gameState, attempt: attempt),
    );

class _ColorMatchRepairGame extends StatefulWidget {
  const _ColorMatchRepairGame(
      {required this.seed, required this.difficulty, required this.onSolved});
  final int seed;
  final Map<String, int> difficulty;
  final Zone0ActionResult Function() onSolved;
  @override
  State<_ColorMatchRepairGame> createState() => _ColorMatchRepairGameState();
}

class _ColorMatchRepairGameState extends State<_ColorMatchRepairGame> {
  static const _colors = <Color>[
    Color(0xffC84A45),
    Color(0xff3877C8),
    Color(0xffD5A726),
    Color(0xff54724A),
    Color(0xff8E5DB5),
    Color(0xffD2763E),
    Color(0xff3A9C9C)
  ];
  late List<int> _sockets;
  late List<bool> _visible;
  final Map<int, int> _connections = <int, int>{};
  int? _selectedCable;
  bool _done = false;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final r = math.Random(widget.seed);
    final total = (widget.difficulty['totalColors'] ?? 5).clamp(5, 8);
    final hidden = (widget.difficulty['hiddenColors'] ?? 2).clamp(0, total);
    // The match is the cable identity, not its display color. At level five
    // two cables may share a color, but each still has exactly one socket.
    _sockets = List<int>.generate(total, (i) => i)..shuffle(r);
    _visible = List<bool>.generate(total, (i) => i < total - hidden);
    _connections.clear();
    _selectedCable = null;
    _done = false;
  }

  void _connect(int socket) {
    if (_done) return;
    setState(() {
      final cable = _selectedCable;
      if (cable == null) return;
      // A correct cable remains visibly selected and energized once connected.
      // An incorrect socket still clears the selection so the player can try
      // another cable without accidentally replacing an established link.
      if (cable != _sockets[socket]) {
        _selectedCable = null;
        return;
      }
      _connections.remove(cable);
      _connections.removeWhere((_, target) => target == socket);
      _connections[cable] = socket;
      _selectedCable = cable;
      if (_connections.length == _sockets.length) {
        if (_connections.entries
            .every((entry) => entry.key == _sockets[entry.value])) {
          final result = widget.onSolved();
          _done = result.success;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result.message)));
          if (result.success) Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Text('Raccorder les câbles',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text(
            'Sélectionnez un câble puis sa prise. Certaines couleurs sont masquées : trouvez leurs correspondances par élimination.'),
        const SizedBox(height: 14),
        Row(children: <Widget>[
          Expanded(
              child: Column(
                  children: List<Widget>.generate(
                      _sockets.length,
                      (i) => OutlinedButton(
                            onPressed: _connections.containsKey(i)
                                ? null
                                : () => setState(() => _selectedCable = i),
                            style: OutlinedButton.styleFrom(
                                backgroundColor: _selectedCable == i ||
                                        _connections.containsKey(i)
                                    ? _colors[i % _colors.length]
                                        .withValues(alpha: .2)
                                    : null,
                                side: BorderSide(
                                  color: _connections.containsKey(i)
                                      ? Colors.blue
                                      : _colors[i % _colors.length],
                                  width: _connections.containsKey(i) ? 3 : 1,
                                )),
                            child: Text('Câble ${i + 1}',
                                style: TextStyle(
                                    color: _colors[i % _colors.length])),
                          )))),
          const Icon(Icons.compare_arrows),
          Expanded(
              child: Column(
                  children: List<Widget>.generate(
                      _sockets.length,
                      (i) => OutlinedButton(
                            onPressed: () => _connect(i),
                            style: OutlinedButton.styleFrom(
                                backgroundColor: _connections.containsValue(i)
                                    ? _colors[_sockets[i] % _colors.length]
                                        .withValues(alpha: .2)
                                    : _visible[i]
                                        ? _colors[_sockets[i] % _colors.length]
                                            .withValues(alpha: .15)
                                        : null,
                                side: BorderSide(
                                  color: _connections.containsValue(i)
                                      ? Colors.blue
                                      : _visible[i]
                                          ? _colors[
                                              _sockets[i] % _colors.length]
                                          : const Color(0xff807A68),
                                  width: _connections.containsValue(i) ? 3 : 1,
                                )),
                            child: Text(
                                _visible[i] ? 'Prise ${i + 1}' : 'Prise ?',
                                style: TextStyle(
                                    color: _visible[i]
                                        ? _colors[_sockets[i] % _colors.length]
                                        : null)),
                          )))),
        ]),
        TextButton(
            onPressed: () => setState(_reset),
            child: const Text('Recommencer')),
      ]));
}

class _WaterSortRepairGame extends StatefulWidget {
  const _WaterSortRepairGame(
      {required this.seed, required this.difficulty, required this.onSolved});
  final int seed;
  final Map<String, int> difficulty;
  final Zone0ActionResult Function() onSolved;
  @override
  State<_WaterSortRepairGame> createState() => _WaterSortRepairGameState();
}

class _WaterSortRepairGameState extends State<_WaterSortRepairGame> {
  static const _colors = <Color>[
    Color(0xffC84A45),
    Color(0xff3877C8),
    Color(0xffD5A726),
    Color(0xff54724A),
    Color(0xff8E5DB5)
  ];
  late int count;
  late List<List<int>> bottles;
  int? selected;
  bool done = false;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    count = widget.difficulty['colorCount'] ?? 3;
    // Chaque couleur doit exister exactement quatre fois. Le mélange n'est
    // retenu que s'il est résoluble : un shuffle visuel seul pouvait produire
    // des parties impossibles à terminer.
    final seed = widget.seed + DateTime.now().microsecondsSinceEpoch;
    List<List<int>>? puzzle;
    for (var attempt = 0; attempt < 40 && puzzle == null; attempt++) {
      final random = math.Random(seed + attempt * 7919);
      final layers = <int>[
        for (var color = 0; color < count; color++)
          ...List<int>.filled(4, color),
      ]..shuffle(random);
      final candidate = <List<int>>[
        for (var index = 0; index < count; index++)
          layers.sublist(index * 4, index * 4 + 4),
        <int>[],
        <int>[],
      ];
      if (_isSolvable(candidate)) puzzle = candidate;
    }
    // Configuration de repli connue et équilibrée. Elle conserve toujours
    // quatre couches par couleur, même si le contrôle DEV détecte un échec.
    bottles = puzzle ??
        <List<int>>[
          for (var bottle = 0; bottle < count; bottle++)
            List<int>.generate(4, (layer) => (bottle + layer) % count),
          <int>[],
          <int>[],
        ];
    selected = null;
    done = false;
  }

  bool _isSolvable(List<List<int>> initial) {
    final seen = <String>{};
    var visited = 0;
    bool search(List<List<int>> state) {
      if (state.where((bottle) => bottle.isNotEmpty).every((bottle) =>
          bottle.length == 4 && bottle.every((v) => v == bottle.first))) {
        return true;
      }
      if (++visited > 70000) return false;
      final key = state.map((bottle) => bottle.join()).join('|');
      if (!seen.add(key)) return false;
      for (var from = 0; from < state.length; from++) {
        final source = state[from];
        if (source.isEmpty) continue;
        final color = source.last;
        var run = 0;
        for (var i = source.length - 1; i >= 0 && source[i] == color; i--) {
          run++;
        }
        for (var to = 0; to < state.length; to++) {
          if (to == from) continue;
          final target = state[to];
          if (target.length == 4) {
            continue;
          }
          final moved = math.min(run, 4 - target.length);
          if (moved == 0) continue;
          final next = state.map((bottle) => List<int>.from(bottle)).toList();
          for (var i = 0; i < moved; i++) {
            next[to].add(next[from].removeLast());
          }
          if (search(next)) return true;
        }
      }
      return false;
    }

    return search(initial.map((bottle) => List<int>.from(bottle)).toList());
  }

  bool get solved => bottles
      .where((b) => b.isNotEmpty)
      .every((b) => b.length == 4 && b.every((x) => x == b.first));
  void tap(int index) {
    setState(() {
      if (selected == null) {
        if (bottles[index].isNotEmpty) selected = index;
        return;
      }
      final source = bottles[selected!];
      final target = bottles[index];
      if (index == selected) {
        selected = null;
        return;
      }
      if (target.length == 4) {
        selected = null;
        return;
      }
      final color = source.last;
      var run = 0;
      for (var i = source.length - 1; i >= 0 && source[i] == color; i--) run++;
      final moved = math.min(run, 4 - target.length);
      for (var i = 0; i < moved; i++) target.add(source.removeLast());
      selected = null;
      if (solved && !done) {
        final result = widget.onSolved();
        done = result.success;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
        if (result.success) Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Text('Fioles',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
              'Versez une fiole vers toute fiole non pleine. Les couches identiques au sommet restent versées ensemble.'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List<Widget>.generate(
              bottles.length,
              (index) => GestureDetector(
                onTap: () => tap(index),
                child: Container(
                  width: 46,
                  height: 130,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected == index
                          ? Colors.blue
                          : const Color(0xff807A68),
                      width: selected == index ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    // La dernière couche de la liste est le sommet : elle est
                    // aussi dessinée en haut de la pile visible.
                    children: bottles[index]
                        .reversed
                        .map((color) => Container(
                              height: 28,
                              width: 42,
                              color: _colors[color % _colors.length],
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          TextButton(
              onPressed: () => setState(_reset),
              child: const Text('Recommencer')),
        ]),
      );
}

/// Prototype de canalisations réutilisé pour les réparations interactives.
class _PipeRepairGameSheet extends StatefulWidget {
  const _PipeRepairGameSheet(
      {required this.onSolved, required this.seed, required this.difficulty});

  final Zone0ActionResult Function() onSolved;
  final int seed;
  final Map<String, int> difficulty;

  @override
  State<_PipeRepairGameSheet> createState() => _PipeRepairGameSheetState();
}

class _PipeRepairGameSheetState extends State<_PipeRepairGameSheet> {
  static const Color _circuitColor = Color(0xff54724A);
  late int _size;
  late List<int?> _board;
  late List<int> _reserve;
  late List<int> _rotations;
  late int _entryIndex;
  late int _entrySide;
  late int _exitIndex;
  late int _exitSide;
  int? _selectedReserve;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _size = (widget.difficulty['gridWidth'] ?? 3).clamp(3, 5);
    _board = List<int?>.filled(_size * _size, null);
    _rotations = List<int>.filled(_size * _size, 0);
    final random = math.Random(widget.seed);
    final endpoints = _endpointsFor(random);
    _entryIndex = endpoints.$1;
    _entrySide = endpoints.$2;
    _exitIndex = endpoints.$3;
    _exitSide = endpoints.$4;
    final amount = widget.difficulty['availablePieces'] ?? 16;
    final mandatory = _solutionPieceKinds();
    _reserve = <int>[...mandatory];
    while (_reserve.length < amount) {
      // Straight, 90° elbow (both left/right orientations are available via
      // rotation), and T pieces. Keep a deliberately mixed reserve.
      _reserve.add(random.nextInt(4));
    }
    _reserve.shuffle(random);
  }

  /// (index, side) pairs use 0=N, 1=E, 2=S, 3=W.  The side is the opening
  /// from the board tile to the exterior. The arrow is rendered outward, so
  /// its rear always touches the tile as requested.
  (int, int, int, int) _endpointsFor(math.Random random) {
    final candidates = <(int, int)>[];
    for (var index = 0; index < _size * _size; index++) {
      final row = index ~/ _size;
      final col = index % _size;
      if (row == 0) candidates.add((index, 0));
      if (col == _size - 1) candidates.add((index, 1));
      if (row == _size - 1) candidates.add((index, 2));
      if (col == 0) candidates.add((index, 3));
    }
    final entry = candidates[random.nextInt(candidates.length)];
    var exit = candidates[random.nextInt(candidates.length)];
    while (exit.$1 == entry.$1 || _manhattan(exit.$1, entry.$1) < 2) {
      exit = candidates[random.nextInt(candidates.length)];
    }
    return (entry.$1, entry.$2, exit.$1, exit.$2);
  }

  int _manhattan(int first, int second) =>
      ((first ~/ _size) - (second ~/ _size)).abs() +
      ((first % _size) - (second % _size)).abs();

  List<int> _solutionPieceKinds() {
    // A concrete Manhattan route guarantees that the reserve contains a
    // solution without revealing it to the player.
    final path = <int>[_entryIndex];
    var row = _entryIndex ~/ _size;
    var col = _entryIndex % _size;
    final targetRow = _exitIndex ~/ _size;
    final targetCol = _exitIndex % _size;
    while (col != targetCol) {
      col += col < targetCol ? 1 : -1;
      path.add(row * _size + col);
    }
    while (row != targetRow) {
      row += row < targetRow ? 1 : -1;
      path.add(row * _size + col);
    }
    return List<int>.generate(path.length, (i) {
      final sides = <int>{
        i == 0 ? _entrySide : _sideBetween(path[i], path[i - 1]),
        i == path.length - 1 ? _exitSide : _sideBetween(path[i], path[i + 1]),
      };
      return (sides.contains(0) && sides.contains(2)) ||
              (sides.contains(1) && sides.contains(3))
          ? 0
          : 1;
    });
  }

  int _sideBetween(int from, int to) {
    final delta = to - from;
    if (delta == -_size) return 0;
    if (delta == 1) return 1;
    if (delta == _size) return 2;
    return 3;
  }

  Set<int> _pipeConnections(int index) {
    final piece = _board[index];
    if (piece == null) return const <int>{};
    final base = switch (piece) {
      0 => const <int>{0, 2},
      1 => const <int>{0, 1},
      2 => const <int>{0, 1, 3},
      _ => const <int>{0, 3},
    };
    return base.map((side) => (side + _rotations[index]) % 4).toSet();
  }

  bool get _pipeSolved {
    if (!_pipeConnections(_entryIndex).contains(_entrySide)) return false;
    final pending = <int>[_entryIndex];
    final visited = <int>{_entryIndex};
    while (pending.isNotEmpty) {
      final index = pending.removeLast();
      final connections = _pipeConnections(index);
      if (index == _exitIndex && connections.contains(_exitSide)) return true;
      final row = index ~/ _size;
      final column = index % _size;
      for (final side in connections) {
        final nextRow = row + const <int>[-1, 0, 1, 0][side];
        final nextColumn = column + const <int>[0, 1, 0, -1][side];
        if (nextRow < 0 ||
            nextRow >= _size ||
            nextColumn < 0 ||
            nextColumn >= _size) {
          continue;
        }
        final next = nextRow * _size + nextColumn;
        if (_pipeConnections(next).contains((side + 2) % 4) &&
            visited.add(next)) {
          pending.add(next);
        }
      }
    }
    return false;
  }

  bool get _solved => _pipeSolved;

  Set<int> get _energizedPipes {
    if (!_pipeConnections(_entryIndex).contains(_entrySide)) return <int>{};
    final pending = <int>[_entryIndex];
    final visited = <int>{_entryIndex};
    while (pending.isNotEmpty) {
      final index = pending.removeLast();
      final row = index ~/ _size;
      final col = index % _size;
      for (final side in _pipeConnections(index)) {
        final nextRow = row + const <int>[-1, 0, 1, 0][side];
        final nextCol = col + const <int>[0, 1, 0, -1][side];
        if (nextRow < 0 || nextRow >= _size || nextCol < 0 || nextCol >= _size)
          continue;
        final next = nextRow * _size + nextCol;
        if (_pipeConnections(next).contains((side + 2) % 4) &&
            visited.add(next)) pending.add(next);
      }
    }
    return visited;
  }

  void _finishRepair() {
    final result = widget.onSolved();
    setState(() => _completed = result.success);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text('Raccorder les tuyaux',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
                'Choisis un tuyau dans la réserve, pose-le sur une case libre, puis tourne-le. Une pièce posée ne peut plus être déplacée.'),
            const SizedBox(height: 16),
            _pipeBoard(),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _solved && !_completed ? _finishRepair : null,
              icon: const Icon(Icons.build_circle_outlined),
              label: Text(
                  _completed ? 'Réparation terminée' : 'Valider le circuit'),
            ),
          ]),
        ),
      );

  Widget _pipeBoard() => LayoutBuilder(
        builder: (context, constraints) {
          // Keep space around the grid so the inlet and outlet remain visible,
          // including on a level 3 puzzle (5 x 5) on a narrow phone.
          final gridWidth = math.min(
            _size * 70.0,
            math.max(180.0, constraints.maxWidth - 52),
          );
          final tileExtent = (gridWidth - ((_size - 1) * 5)) / _size;
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(26),
                child: SizedBox(
                  width: gridWidth,
                  child: Stack(clipBehavior: Clip.none, children: <Widget>[
                    GridView.count(
                      crossAxisCount: _size,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                      children: List<Widget>.generate(_size * _size, _pipeTile),
                    ),
                    ...<_EndpointMarker>[
                      _EndpointMarker(
                          index: _entryIndex, side: _entrySide, input: true),
                      _EndpointMarker(
                          index: _exitIndex, side: _exitSide, input: false),
                    ].map((marker) => _endpointMarker(marker, tileExtent)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Réserve de tuyaux'),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: List<Widget>.generate(
                    _reserve.length,
                    (index) => InkWell(
                          onTap: () => setState(() => _selectedReserve = index),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _selectedReserve == index
                                  ? _circuitColor.withValues(alpha: .22)
                                  : const Color(0xffE8E5DC),
                              border: Border.all(color: _circuitColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _PipeGlyph(
                              connections: switch (_reserve[index]) {
                                0 => const <int>{0, 2},
                                1 => const <int>{0, 1},
                                2 => const <int>{0, 1, 3},
                                _ => const <int>{0, 3},
                              },
                              color: _circuitColor,
                            ),
                          ),
                        )),
              ),
            ],
          );
        },
      );

  Widget _endpointMarker(_EndpointMarker marker, double tileExtent) {
    final row = marker.index ~/ _size;
    final col = marker.index % _size;
    // Entrée : la flèche vient de l'extérieur vers la case. Sortie : elle
    // quitte la case. Le sens n'est jamais confondu avec une connexion.
    final outward = switch (marker.side) {
      0 => Icons.arrow_upward,
      1 => Icons.arrow_forward,
      2 => Icons.arrow_downward,
      _ => Icons.arrow_back,
    };
    final icon = marker.input
        ? switch (marker.side) {
            0 => Icons.arrow_downward,
            1 => Icons.arrow_back,
            2 => Icons.arrow_upward,
            _ => Icons.arrow_forward,
          }
        : outward;
    return Positioned(
      left: col * (tileExtent + 5) +
          (marker.side == 3
              ? -27
              : marker.side == 1
                  ? tileExtent + 2
                  : (tileExtent - 25) / 2),
      top: row * (tileExtent + 5) +
          (marker.side == 0
              ? -27
              : marker.side == 2
                  ? tileExtent + 2
                  : (tileExtent - 25) / 2),
      child: Icon(icon, color: _circuitColor, size: 25),
    );
  }

  Widget _pipeTile(int index) {
    final piece = _board[index];
    final energized = _energizedPipes.contains(index);
    return InkWell(
      onTap: () => setState(() {
        if (piece == null && _selectedReserve != null) {
          _board[index] = _reserve.removeAt(_selectedReserve!);
          _selectedReserve = null;
        } else if (piece != null)
          _rotations[index] = (_rotations[index] + 1) % 4;
      }),
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: energized
                ? Colors.blue.withValues(alpha: .18)
                : const Color(0xffE8E5DC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: energized ? Colors.blue : const Color(0xff807A68),
                width: energized ? 3 : 1),
          ),
          child: piece == null
              ? const Icon(Icons.add, color: Color(0xff807A68))
              : _PipeGlyph(
                  connections: _pipeConnections(index),
                  color: energized ? Colors.blue : _circuitColor,
                ),
        ),
      ),
    );
  }
}

class _EndpointMarker {
  const _EndpointMarker(
      {required this.index, required this.side, required this.input});
  final int index;
  final int side;
  final bool input;
}

/// Rendu géométrique : les branches sortent uniquement dans les directions
/// réellement connectées. Il remplace les icônes ambiguës à doubles flèches.
class _PipeGlyph extends StatelessWidget {
  const _PipeGlyph({required this.connections, required this.color});
  final Set<int> connections;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PipeGlyphPainter(connections, color),
        child: const SizedBox.expand(),
      );
}

class _PipeGlyphPainter extends CustomPainter {
  const _PipeGlyphPainter(this.connections, this.color);
  final Set<int> connections;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(3, size.shortestSide * .085)
      ..strokeCap = StrokeCap.round;
    for (final side in connections) {
      final end = switch (side) {
        0 => Offset(center.dx, size.height * .18),
        1 => Offset(size.width * .82, center.dy),
        2 => Offset(center.dx, size.height * .82),
        _ => Offset(size.width * .18, center.dy),
      };
      canvas.drawLine(center, end, paint);
    }
    canvas.drawCircle(center, paint.strokeWidth / 2, paint);
  }

  @override
  bool shouldRepaint(covariant _PipeGlyphPainter oldDelegate) =>
      oldDelegate.connections != connections || oldDelegate.color != color;
}

class _StructuralInstallationSlots extends StatelessWidget {
  const _StructuralInstallationSlots(
      {required this.gameState,
      required this.buildingId,
      required this.onMessage});
  final Zone0GameState gameState;
  final String buildingId;
  final ValueChanged<String> onMessage;

  /// Extend this map for a future installation with a consumable reserve.
  /// The slot will automatically appear directly below its installation grid.
  static const Map<StructuralProtectionType, String> _consumableByInstallation =
      <StructuralProtectionType, String>{
    StructuralProtectionType.filtration: 'Cartouche de filtration',
  };

  String _label(StructuralProtectionType type) => switch (type) {
        StructuralProtectionType.ventilationTermite => 'Ventilation Termite',
        StructuralProtectionType.chloroCanaux => 'Chloro-canaux',
        StructuralProtectionType.filtration => 'Installation filtrante',
      };

  @override
  Widget build(BuildContext context) {
    final state = gameState.viabilityForBuilding(buildingId);
    final slots = gameState.structuralProtectionSlotsFor(buildingId);
    final consumableInstallations = _consumableByInstallation.entries.where(
      (entry) => state.installedStructuralProtections.contains(entry.key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.25,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10),
          itemCount: slots,
          itemBuilder: (context, index) {
            final installed =
                index < state.installedStructuralProtections.length
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
                final type =
                    await showModalBottomSheet<StructuralProtectionType>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                      child: ListView(
                          shrinkWrap: true,
                          children: StructuralProtectionType.values
                              .map((type) => ListTile(
                                    enabled:
                                        gameState.resourceAmount(_label(type)) >
                                            0,
                                    title: Text(_label(type)),
                                    subtitle: Text(
                                        'Stock : ${gameState.resourceAmount(_label(type))}'),
                                    trailing:
                                        const Icon(Icons.add_circle_outline),
                                    onTap: () => Navigator.pop(context, type),
                                  ))
                              .toList())),
                );
                if (type != null) {
                  onMessage(
                    gameState
                        .installStructuralProtection(buildingId, type)
                        .message,
                  );
                }
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
        ),
        for (final entry in consumableInstallations) ...<Widget>[
          const SizedBox(height: 12),
          _StructuralConsumableSlot(
            itemName: entry.value,
            stored: state.structuralConsumables[entry.value] ?? 0,
            stock: gameState.resourceAmount(entry.value),
            onAdd: (quantity) => onMessage(
              gameState
                  .addStructuralConsumableToBuilding(
                    buildingId,
                    requiredInstallation: entry.key,
                    itemName: entry.value,
                    quantity: quantity,
                  )
                  .message,
            ),
          ),
        ],
      ],
    );
  }
}

/// Generic consumable reserve shown beneath an installation.  Other
/// installations can reuse this slot when they gain a consumable later.
class _StructuralConsumableSlot extends StatelessWidget {
  const _StructuralConsumableSlot({
    required this.itemName,
    required this.stored,
    required this.stock,
    required this.onAdd,
  });

  final String itemName;
  final int stored;
  final int stock;
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Consommable',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('$itemName · réserve : $stored'),
              Text('Inventaire : $stock'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <int>[1, 5, 10]
                    .map((quantity) => OutlinedButton(
                          onPressed:
                              stock >= quantity ? () => onAdd(quantity) : null,
                          child: Text('+$quantity'),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );
}

class _PTibugTerritoryStockSummary extends StatelessWidget {
  const _PTibugTerritoryStockSummary(
      {required this.gameState,
      required this.building,
      required this.consumption});
  final Zone0GameState gameState;
  final PTibugTerritoryBuilding building;
  final PTibugTerritoryConsumption consumption;

  @override
  Widget build(BuildContext context) {
    final autonomyDays = gameState.pTibugTerritoryAutonomyDays(building);
    final label = building.kind == PTibugTerritoryKind.nursery
        ? 'La Nurserie'
        : 'Le Refuge';
    final autonomyLabel = autonomyDays.isInfinite
        ? '$label peut fonctionner sans consommation locale.'
        : autonomyDays < 1
            ? '$label va cesser de fonctionner bientôt.'
            : '$label peut fonctionner pendant ${autonomyDays.floor()} jour${autonomyDays.floor() == 1 ? '' : 's'}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
            'Organique : ${building.resourceAmount('Organique')}/${consumption.organicPerDay} (par jour)'),
        Text(
            'Minéral : ${building.resourceAmount('Minéral')}/${consumption.mineralPerDay} (par jour)'),
        Text(
            'Énergie : ${building.localEnergy}/${consumption.energyPerDay} (par jour)'),
        const SizedBox(height: 4),
        Text(autonomyLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color:
                  autonomyDays < 1 ? Theme.of(context).colorScheme.error : null,
            )),
        const SizedBox(height: 4),
        LinearProgressIndicator(
            value: (building.localEnergy /
                    math.max(10, consumption.energyPerDay * 2))
                .clamp(0.0, 1.0)),
      ],
    );
  }
}

bool _hasSmartSensor(PTibug bug) =>
    bug.biologicalTraitId == 'capteurIntelligent' ||
    bug.secondTraitId == 'capteurIntelligent';

class _PTibugTerritoryBugCard extends StatelessWidget {
  const _PTibugTerritoryBugCard(
      {required this.gameState,
      required this.bug,
      required this.building,
      this.onDragUpdate,
      this.onShowDetails});
  final Zone0GameState gameState;
  final PTibug bug;
  final PTibugTerritoryBuilding? building;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<PTibug>? onShowDetails;

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
                  onTap: () => onShowDetails?.call(bug),
                  child: Row(children: <Widget>[
                    CircleAvatar(
                      backgroundColor:
                          _pTibugPrimaryColor(bug).withValues(alpha: .18),
                      child: Icon(_territorySpeciesIcon(bug.species),
                          color: _pTibugPrimaryColor(bug)),
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
                    '${gameState.pTibugTerritoryIdentityFor(bug)} · niv. ${bug.level}'),
                Text('Aspect : ${gameState.pTibugAppearanceLabelFor(bug)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10)),
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
                  onPressed: gameState.isPTibugInCultivation(bug)
                      ? () => _exitCultivation(context)
                      : () => _showAssign(context),
                  child: Text(gameState.isPTibugInCultivation(bug)
                      ? 'Sortir de cuve'
                      : 'Affecter'),
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
                        ? 'Nurserie · Savane tropicale'
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

  void _exitCultivation(BuildContext context) {
    final operation = gameState.cultivationOperationForPTibug(bug.id);
    if (operation == null) return;
    _message(
        context, gameState.cancelPTibugCultivation(operation.tankId).message);
  }

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

IconData _territorySpeciesIcon(PTibugSpecies species) => switch (species) {
      PTibugSpecies.scarabe => Icons.shield_outlined,
      PTibugSpecies.hyme => Icons.hive_outlined,
      PTibugSpecies.arac => Icons.hub_outlined,
    };

Color _pTibugPrimaryColor(PTibug bug) {
  return _pTibugColorFromHex(bug.primaryColorHex);
}

Color _pTibugColorFromHex(String? colorHex,
    {Color fallback = const Color(0xFF7C7850)}) {
  final raw = (colorHex ?? '').replaceFirst('#', '');
  if (raw.length != 6) return fallback;
  return Color(0xFF000000 | int.parse(raw, radix: 16));
}

IconData _pTibugMotifIcon(String? motifId) => switch (motifId) {
      'Rayé' => Icons.format_line_spacing_outlined,
      'Irisé' => Icons.auto_awesome_outlined,
      'Pointillé' => Icons.scatter_plot_outlined,
      _ => Icons.texture_outlined,
    };

IconData _pTibugAnimationIcon(String? animationName) => switch (animationName) {
      'Volant' => Icons.flight_outlined,
      'Terrier' => Icons.terrain_outlined,
      'Cornu' => Icons.emoji_nature_outlined,
      'Briseur' => Icons.hardware_outlined,
      'Sauteuse' => Icons.north_east_outlined,
      'Tisseuse' => Icons.hub_outlined,
      _ => Icons.motion_photos_on_outlined,
    };

IconData _matrixSpeciesIcon(PTibugSpecies species) => switch (species) {
      PTibugSpecies.scarabe => Icons.shield_outlined,
      PTibugSpecies.hyme => Icons.hive_outlined,
      PTibugSpecies.arac => Icons.hub_outlined,
    };

/// Présentation unique d'une Matrice : inventaire, création et Cultivation
/// montrent ainsi les mêmes informations physiques, pas un simple nom texte.
class _AspectMatrixPresentation extends StatelessWidget {
  const _AspectMatrixPresentation({
    required this.matrix,
    this.selected = false,
    this.onTap,
  });

  final PTibugAspectMatrix matrix;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = _pTibugColorFromHex(matrix.primaryColorHex);
    final isDark = matrix.primaryColorHex?.toUpperCase() == '#1E1E1E';
    final species = pTibugConfig.species[matrix.species]!.displayName;
    final labels = <Widget>[
      _matrixBadge(
        primary,
        'Couleur ${_matrixColorName(matrix.primaryColorHex)}',
      ),
      if (matrix.motifId != null && matrix.motifId!.isNotEmpty)
        _matrixIconBadge(
            _pTibugMotifIcon(matrix.motifId), 'Motif ${matrix.motifId}'),
      if (matrix.motifId != null && matrix.motifColorHex != null)
        _matrixBadge(
          _pTibugColorFromHex(matrix.motifColorHex),
          'Motif ${_matrixColorName(matrix.motifColorHex)}',
        ),
      if (matrix.animationName != null && matrix.animationName!.isNotEmpty)
        _matrixIconBadge(
          _pTibugAnimationIcon(matrix.animationName),
          matrix.animationName!,
        ),
    ];
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 23,
                backgroundColor: primary,
                foregroundColor: isDark ? Colors.white : Colors.black87,
                child: Icon(_matrixSpeciesIcon(matrix.species)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Matrice $species',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('Source : ${matrix.sourceDisplayName}'),
                    const SizedBox(height: 5),
                    Wrap(spacing: 8, runSpacing: 4, children: labels),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: Colors.blue),
              if (!selected && onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _matrixBadge(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );

Widget _matrixIconBadge(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );

String _matrixColorName(String? colorHex) => switch (colorHex?.toUpperCase()) {
      '#1E1E1E' => 'Noir',
      '#FFFFFF' => 'Blanc',
      '#D94B4B' => 'Rouge',
      '#4A90E2' => 'Bleu',
      '#F2C94C' => 'Jaune',
      '#F2994A' => 'Orange',
      '#9B51E0' => 'Violet',
      '#6FCF97' => 'Vert',
      _ => colorHex ?? 'inconnue',
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
          if (false)
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
                                'La Nurserie a besoin d’une Savane tropicale végétalisée et de matériaux réservés.',
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
    final cooldown = gameState.biomassRevitalizeCooldownRemaining(biome);
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
              onPressed: biomass >= maximum || cooldown > Duration.zero
                  ? null
                  : () {
                      final result = gameState.revitalizeBiome(biome);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    },
              icon: const Icon(Icons.eco_outlined),
              label: Text(
                cooldown > Duration.zero
                    ? 'Dispositif en recharge · ${cooldown.inHours}h ${cooldown.inMinutes.remainder(60).toString().padLeft(2, '0')}'
                    : 'Utiliser un dispositif · +${lisiereForageConfig.biomass.revitalizeGain}%',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Le Dispositif de régénération se fabrique à l’Atelier : 10 Organique · 10 Minéral · 10 Mycélium. Un seul usage par biome toutes les 24 h.',
              style: TextStyle(fontSize: 12),
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
            const Text(
              'Capsules de données : disponibles uniquement depuis la Tour de recherche.',
            ),
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
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showMissionDetails(context, mission),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.forest_outlined, size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${mission.type == ForageMissionType.research ? '🔎 Recherche' : '🪵 Récolte'} · ${mission.memberNames.join(', ')} · ${biome.label}',
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
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showMissionDetails(BuildContext context, ForageMission mission) {
    final biome = lisiereForageConfig.biomes[mission.biome]!;
    final duration = lisiereForageConfig.durations[mission.duration]!;
    final intensity = lisiereForageConfig.intensities[mission.intensity]!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    mission.type == ForageMissionType.research
                        ? 'Mission de recherche'
                        : 'Mission de récolte',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text('Biome : ${biome.label}'),
                Text('P’TIPOTES : ${mission.memberNames.join(', ')}'),
                Text(
                    'Temps restant : ${_countdownLabel(mission.endTime)} · durée ${duration.label}'),
                Text('Intensité : ${intensity.label}'),
                const SizedBox(height: 8),
                Text(
                    'Gain potentiel : ${_formatRewards(mission.expectedRewards)}'),
                Text('XP prévue : +${mission.xpGain}'),
                Text('Risque : ${mission.riskPercent}% · ${mission.riskLabel}'),
                Text(
                    'Sécurité au départ : ${mission.securityAtLaunch}% · réduction Tour -${mission.securityReduction}%'),
                Text(
                    'Coût de vitalité : ${mission.vitalityCostByMember.values.isEmpty ? mission.vitalityCost : mission.vitalityCostByMember.values.reduce(math.max)}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _confirmEmergencyReturn(context, mission);
                  },
                  icon: const Icon(Icons.keyboard_return_outlined),
                  label: const Text('Retour d’urgence'),
                ),
              ]),
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

  String _residentWellbeingEmoji(Zone0Resident resident) {
    final value = gameState.residentHappinessFor(resident);
    if (value >= 100) return '🤩';
    if (value >= 90) return '😁';
    if (value >= 70) return '🙂';
    if (value >= 50) return '😐';
    if (value >= 30) return '😠';
    return '🤬';
  }

  Widget _residentWellbeingValue(Zone0Resident resident) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(_residentWellbeingEmoji(resident),
              style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 4),
          Text('${gameState.residentHappinessFor(resident)}%',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      );

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

  void _showResidentSheet(BuildContext context, Zone0Resident resident) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: <Widget>[
              Text(resident.displayName,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text('Statut : ${switch (resident.status) {
                ResidentStatus.active => 'Actif',
                ResidentStatus.awaitingHousing => 'En attente de logement',
                ResidentStatus.arriving => 'En arrivée',
                ResidentStatus.inactive => 'Inactif',
                ResidentStatus.archived => 'Archivé',
              }}'),
              Text(
                  'Bonheur : ${_residentWellbeingEmoji(resident)} ${gameState.residentHappinessFor(resident)}% · ${gameState.formatInternalPileBalance(resident.internalPileBalance)}'),
              const SizedBox(height: 14),
              const Text('Besoins',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Repas : ${resident.needsState.mealsConsumed}/${resident.needsState.mealsRequired} · ${switch (resident.needsState.nutritionStatus) {
                  ResidentNutritionStatus.nourri => 'Nourri',
                  ResidentNutritionStatus.partiellementNourri =>
                    'Partiellement nourri',
                  ResidentNutritionStatus.nonNourri => 'Non nourri',
                }}',
              ),
              if (resident.needsState.missingWeatherProtectionTypes.isNotEmpty)
                Text(
                    'Météo : protection manquante — ${resident.needsState.missingWeatherProtectionTypes.join(', ')}'),
              OutlinedButton.icon(
                onPressed: () {
                  final result = gameState.giveResidentFinishedItem(
                    residentId: resident.id,
                    itemName: 'Repas simple',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.message)),
                  );
                },
                icon: const Icon(Icons.restaurant_outlined),
                label: const Text('Donner un repas simple'),
              ),
              const SizedBox(height: 10),
              const Text('Envie et vestiaire',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Envie : ${switch (resident.primaryDesireId) {
                'sweetTooth' => 'Bouche sucrée',
                'fashion' => 'Aime la sape',
                'comfort' => 'Aime le confort',
                'tools' => 'Aime les outils',
                _ => 'À déterminer',
              }} · ${resident.needsState.desireSatisfied ? 'satisfaite' : 'non satisfaite'}'),
              const SizedBox(height: 8),
              Text(
                'Inventaire : ${resident.ownedItems.length}/${math.max(gameState.residentInventorySlotsFor(resident), resident.ownedItems.length)} cases',
              ),
              if (resident.inventorySlotBonus < 3)
                OutlinedButton.icon(
                  onPressed: () {
                    final result =
                        gameState.expandResidentInventory(resident.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.message)),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Agrandir gratuitement (+3 cases)'),
                ),
              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: List<Widget>.generate(
                  math.max(
                    gameState.residentInventorySlotsFor(resident),
                    resident.ownedItems.length,
                  ),
                  (index) => _ResidentInventorySlot(
                    item: index < resident.ownedItems.length
                        ? resident.ownedItems[index]
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Économie',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Solde : ${gameState.formatInternalPileBalance(resident.internalPileBalance)} · ${gameState.residentEconomicStateLabel(resident)}',
              ),
              Text(
                'Revenu domestique récent : ${resident.recentDomesticIncomePiles} pile(s) · dépenses : ${resident.recentSpendingPiles} pile(s).',
              ),
              if (gameState.residentUncoveredNeeds.any((need) =>
                  need.residentId == resident.id && need.resolvedAt == null))
                Text(
                    'Besoins économiques en attente : ${gameState.residentUncoveredNeeds.where((need) => need.residentId == resident.id && need.resolvedAt == null).map((need) => need.itemDefinitionId).toSet().join(', ')}'),
              const SizedBox(height: 10),
              const Text('Historique récent',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              ...gameState
                  .economicHistoryForResident(resident.id)
                  .toList()
                  .reversed
                  .take(4)
                  .map((transaction) => Text(
                      '${transaction.itemDefinitionId ?? 'Énergie domestique'} · ${transaction.grossAmountPiles} pile(s)')),
              const SizedBox(height: 10),
              const Text('Passion et rôle communautaire',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                  'Passion : ${gameState.residentPassionLabel(ResidentPassion.values.firstWhere((passion) => passion.name == resident.primaryPassionId, orElse: () => ResidentPassion.cooking))}'),
              if (gameState.communityRoleForResident(resident.id)
                  case final role?)
                Text(
                  '${gameState.communityRoleLabel(role.roleType)} · ${switch (role.status) {
                    CommunityRoleStatus.active => 'Actif',
                    CommunityRoleStatus.paused => 'En pause',
                    CommunityRoleStatus.unavailable => 'Indisponible',
                    CommunityRoleStatus.awaitingBuilding => 'Bâtiment requis',
                    CommunityRoleStatus.awaitingResources =>
                      'Ressources requises',
                    CommunityRoleStatus.archived => 'Archivé',
                  }} · production ${role.dailyOutput}',
                )
              else
                const Text('Passion actuellement inoccupée.'),
              if (resident.primaryPassionId ==
                  ResidentPassion.livingObservation.name)
                Text(
                  'P’TIBUG certifiés : ${resident.ownedCertifiedPtibugIds.length}/${communityRolesConfig.residentPtibugMaximum} · ${gameState.canResidentRequestCertifiedPtibug(resident) ? 'éligible à une future demande' : 'aucune demande possible actuellement'}',
                ),
              Wrap(
                spacing: 8,
                children: gameState
                    .compatibleCommunityRolesFor(resident)
                    .map(
                      (role) => OutlinedButton(
                        onPressed: () {
                          final result = gameState.assignResidentCommunityRole(
                            residentId: resident.id,
                            roleType: role,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        },
                        child: Text(gameState.communityRoleLabel(role)),
                      ),
                    )
                    .toList(),
              ),
              if (gameState.communityRoleForResident(resident.id) != null)
                TextButton.icon(
                  onPressed: () {
                    final result =
                        gameState.removeResidentCommunityRole(resident.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.message)),
                    );
                  },
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Retirer du rôle'),
                ),
              const SizedBox(height: 10),
              const Text('Bonheur',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              ...gameState.residentHappinessBreakdown(resident).entries.map(
                    (entry) => Text(
                        '${entry.key} : ${entry.value >= 0 ? '+' : ''}${entry.value}'),
                  ),
              const SizedBox(height: 10),
              const Text('Vision du refuge',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              if (gameState.residentVisionFor(resident.id) case final vision?)
                Text(
                    '${gameState.communityProjectDefinition(vision.projectId)?.label ?? vision.projectId} · ${vision.status.name}${vision.persistentBonus > 0 ? ' · +${vision.persistentBonus} bonheur' : ''}')
              else
                const Text(
                    'Une vision apparaîtra quand un grand chantier sera accessible.'),
              const SizedBox(height: 14),
              const Text('Logement',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              ...gameState.residentHouses.map(
                (house) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(resident.houseId == house.id
                      ? Icons.home
                      : Icons.home_outlined),
                  title: Text(house.displayName),
                  subtitle: Text(
                    '${house.residentIds.length}/${house.capacity} occupant(s) · Viabilité ${house.currentViability}%',
                  ),
                  trailing: resident.houseId == house.id
                      ? const Text('Actuelle')
                      : TextButton(
                          onPressed: house.residentIds.length >= house.capacity
                              ? null
                              : () {
                                  final result = gameState.moveResidentToHouse(
                                    residentId: resident.id,
                                    targetHouseId: house.id,
                                  );
                                  Navigator.of(sheetContext).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                },
                          child: const Text('Déplacer'),
                        ),
                ),
              ),
              if (resident.houseId != null)
                OutlinedButton.icon(
                  onPressed: () {
                    final result = gameState.moveResidentToHouse(
                      residentId: resident.id,
                      targetHouseId: null,
                    );
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.message)),
                    );
                  },
                  icon: const Icon(Icons.logout_outlined),
                  label: const Text('Retirer du logement'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _residentAlertIcons(Zone0Resident resident) => <Widget>[
        if (gameState.communityRoleForResident(resident.id) == null)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: Icon(Icons.handyman_outlined, size: 17),
          )
        else if (resident.needsState.nutritionStatus ==
            ResidentNutritionStatus.nonNourri)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: Text('🍽️', style: TextStyle(fontSize: 15)),
          ),
        if (gameState.refugeSafety < 30)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('🥺', style: TextStyle(fontSize: 15)),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final project = gameState.constructionProjects['housing'];
    final activity = math.max(0, gameState.currentPopulation * 10);
    final activeResidents = gameState.residents
        .where((resident) => resident.isActive)
        .toList(growable: false);
    final nourishedResidents = activeResidents
        .where((resident) =>
            resident.needsState.nutritionStatus ==
            ResidentNutritionStatus.nourri)
        .length;
    final unprotectedResidents = activeResidents
        .where((resident) =>
            resident.needsState.missingWeatherProtectionTypes.isNotEmpty)
        .length;
    final community = gameState.communityCoverage;
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
          _HabitationStatCard(
            icon: Icons.restaurant_outlined,
            title: 'Besoins du jour',
            value: '$nourishedResidents/${activeResidents.length} nourri(s)',
            subtitle: unprotectedResidents == 0
                ? 'Tous protégés pour la météo annoncée'
                : '$unprotectedResidents habitant(s) sans protection météo',
            onTap: () => _showStatInfo(
              context,
              'Besoins des habitants',
              'Chaque habitant consomme deux repas finis par jour. Les protections personnelles sont vérifiées dès l’annonce de la météo et s’usent une fois par événement.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.volunteer_activism_outlined,
            title: 'Activités des habitants',
            value: '${community.activeRoles} rôle(s) actif(s)',
            subtitle:
                '${community.pausedRoles} en pause · repas ${community.foodCoverageCapacity} · sécurité +${community.securityProducedToday} · météo +${gameState.communityWeatherForecastSupport}',
            onTap: () => _showStatInfo(
              context,
              'Couverture communautaire',
              'Les habitants occupent des slots distincts des P’TIPOTES. Les rôles produisent lentement avec des intrants physiques : cuisine, fabrication, comptoir, observation, sécurité ou météo.',
            ),
          ),
          _HabitationStatCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Économie des habitants',
            value:
                '${gameState.residentHouses.fold<int>(0, (sum, house) => sum + house.recentEnergyProducedPiles)} piles produites',
            subtitle:
                '${gameState.residentEconomicTransactions.where((transaction) => transaction.type == ResidentEconomicTransactionType.residentPurchase || transaction.type == ResidentEconomicTransactionType.playerSaleToResident).length} achat(s) · ${gameState.residentUncoveredNeeds.where((need) => need.resolvedAt == null).length} besoin(s) non couvert(s)',
            onTap: () => _showStatInfo(
              context,
              'Économie interne',
              'Les maisons produisent des bio-piles, puis les répartissent équitablement entre leurs occupants. Les habitants achètent seulement des produits finis : les besoins sans produit, magasin ou budget restent visibles pour le futur Marché.',
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Postes communautaires',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text(
                      'Un carré gris est libre. Lorsqu’un habitant passionné est affecté, son poste devient vert : touche-le pour ouvrir sa fiche.'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CommunityRoleType.values.expand((roleType) {
                      final buildingId = switch (roleType) {
                        CommunityRoleType.kitchenCook => 'cuisine',
                        CommunityRoleType.fablabMaker => 'atelier',
                        CommunityRoleType.marketCounter => 'market',
                        CommunityRoleType.lisiereObserver => 'lisiere',
                        CommunityRoleType.securityWatch ||
                        CommunityRoleType.weatherWatch =>
                          'securityTower',
                      };
                      return List<Widget>.generate(
                        gameState.communityRoleSlotCount(roleType),
                        (index) {
                          final slotId = 'resident-$index';
                          final assignment = gameState.communityRoleAssignments
                              .where((entry) =>
                                  entry.status !=
                                      CommunityRoleStatus.archived &&
                                  entry.buildingId == buildingId &&
                                  entry.slotId == slotId)
                              .firstOrNull;
                          final resident = assignment == null
                              ? null
                              : gameState.residents
                                  .where((entry) =>
                                      entry.id == assignment.residentId)
                                  .firstOrNull;
                          final occupied = resident != null;
                          return SizedBox(
                            width: 118,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: resident == null
                                  ? null
                                  : () => _showResidentSheet(context, resident),
                              child: Ink(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: occupied
                                      ? Colors.green.withValues(alpha: 0.18)
                                      : Colors.grey.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(occupied
                                        ? Icons.person
                                        : Icons.person_outline),
                                    const SizedBox(height: 4),
                                    Text(gameState.communityRoleLabel(roleType),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 11)),
                                    Text(resident?.displayName ?? 'Libre',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          if (false &&
              gameState.communityRoleAssignments.any((role) =>
                  role.status != CommunityRoleStatus.archived)) ...<Widget>[
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Rôles en cours',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    ...gameState.communityRoleAssignments
                        .where((role) =>
                            role.status != CommunityRoleStatus.archived)
                        .map((role) {
                      final resident = gameState.residents
                          .where((item) => item.id == role.residentId)
                          .firstOrNull;
                      final status = switch (role.status) {
                        CommunityRoleStatus.active => 'Actif',
                        CommunityRoleStatus.paused => 'En pause',
                        CommunityRoleStatus.unavailable => 'Indisponible',
                        CommunityRoleStatus.awaitingBuilding =>
                          'Bâtiment requis',
                        CommunityRoleStatus.awaitingResources =>
                          'Ressources requises',
                        CommunityRoleStatus.archived => 'Archivé',
                      };
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                            '${resident?.displayName ?? 'Habitant'} · ${gameState.communityRoleLabel(role.roleType)}'),
                        subtitle:
                            Text('$status · production ${role.dailyOutput}'),
                        onTap: resident == null
                            ? null
                            : () => _showResidentSheet(context, resident),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (gameState.residentHouses.isNotEmpty) ...<Widget>[
            Text('Maisons',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...gameState.residentHouses.map((house) {
              final residents = gameState.residents
                  .where((resident) =>
                      resident.isActive && resident.houseId == house.id)
                  .toList(growable: false);
              return Card(
                child: Column(children: <Widget>[
                  ListTile(
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
                              showModalBottomSheet<int>(
                                context: context,
                                showDragHandle: true,
                                builder: (sheetContext) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        const Text('Réparer la maison',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 18)),
                                        const Text(
                                            'Les matériaux réparent 10 % par tranche. Un Kit de réparation restaure 15 %. La Viabilité reste plafonnée à 100 %.'),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: <Widget>[
                                            FilledButton.icon(
                                              onPressed: () {
                                                final result = gameState
                                                    .repairResidentHouseWithKit(
                                                        house.id);
                                                if (result.success) {
                                                  Navigator.of(sheetContext)
                                                      .pop();
                                                }
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(
                                                            result.message)));
                                              },
                                              icon: const Icon(
                                                  Icons.handyman_outlined),
                                              label: const Text('Kit · +15 %'),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: () {
                                                final attempt = gameState
                                                    .beginInteractiveRepair(
                                                        'resident-house:${house.id}',
                                                        gain: 20);
                                                if (attempt == null) return;
                                                Navigator.of(sheetContext)
                                                    .pop();
                                                _openSharedRepairMiniGame(
                                                    context,
                                                    gameState,
                                                    attempt);
                                              },
                                              icon: const Icon(Icons.tune),
                                              label: const Text(
                                                  'Réparer soi-même · +20 %'),
                                            ),
                                            ...<int>[10, 20, 30].map((gain) {
                                              final cost = gameState
                                                  .buildingRepairCostsForLevel(
                                                1,
                                                gain,
                                              );
                                              final costLabel = gameState
                                                  .buildingRepairCostLabel(
                                                cost,
                                              );
                                              return FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(sheetContext)
                                                        .pop(gain),
                                                child: Text(
                                                    '+$gain % · $costLabel'),
                                              );
                                            }).toList(),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ).then((gain) {
                                if (gain == null || !context.mounted) return;
                                final result = gameState.repairResidentHouse(
                                  house.id,
                                  gain: gain,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(result.message)),
                                );
                              });
                            },
                            child: const Text('Réparer'),
                          )
                        : const Text('Bon état'),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (sheetContext) => SafeArea(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.sizeOf(sheetContext).height * .72,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            children: <Widget>[
                              Text(
                                '${house.displayName} · protections ${house.installedStructuralProtections.length}/${house.weatherProtectionSlots}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 18),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Mobilier : ${house.installedFurnitureItems.length}/${house.furnitureSlots} · Générateur domestique : ${house.baseGeneratorInstalled ? 'actif' : 'absent'}',
                              ),
                              const SizedBox(height: 10),
                              const Text('Intérieur',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              Text(
                                residents.isEmpty
                                    ? 'Aucun occupant à satisfaire.'
                                    : 'Profils : ${residents.map((resident) => switch (resident.interiorProfileId) {
                                          'technique' => 'Technique',
                                          'esthete' => 'Esthète',
                                          _ => 'Simple'
                                        }).toSet().join(' · ')}',
                              ),
                              Text(
                                residents.isEmpty
                                    ? ''
                                    : 'Satisfaction : ${residents.where((resident) => resident.needsState.interiorSatisfied).length}/${residents.length} occupant(s)',
                              ),
                              if (house.installedFurnitureItems.isNotEmpty)
                                Text(
                                    'Installés : ${house.installedFurnitureItems.join(', ')}'),
                              const SizedBox(height: 10),
                              Text(
                                'Installations : ${house.installedInstallationItems.length}/${house.installationSlots - 1} · réserve cartouches',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              GridView.count(
                                crossAxisCount: 4,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: List<Widget>.generate(
                                  house.installationSlots,
                                  (index) {
                                    final isCartridgeSlot =
                                        index == house.installationSlots - 1;
                                    final item = isCartridgeSlot
                                        ? 'Cartouche de filtration'
                                        : index <
                                                house.installedInstallationItems
                                                    .length
                                            ? house.installedInstallationItems[
                                                index]
                                            : null;
                                    final amount = isCartridgeSlot
                                        ? house.structuralConsumables[
                                                'Cartouche de filtration'] ??
                                            0
                                        : item == null
                                            ? 0
                                            : 1;
                                    return _InventorySlot(
                                      stack: item == null || amount <= 0
                                          ? null
                                          : Zone0InventoryStack(
                                              resource: item, amount: amount),
                                    );
                                  },
                                ),
                              ),
                              const Text(
                                '3 installations et 1 réserve de cartouches de filtration.',
                                style: TextStyle(fontSize: 11),
                              ),
                              if (house.householdInventory.entries
                                  .any((entry) =>
                                      entry.value > 0 &&
                                      <String>{
                                        'Ventilation Termite',
                                        'Chloro-canaux',
                                        'Installation filtrante',
                                        'Second générateur domestique'
                                      }.contains(entry.key)))
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: house.householdInventory.entries
                                      .where((entry) =>
                                          entry.value > 0 &&
                                          <String>{
                                            'Ventilation Termite',
                                            'Chloro-canaux',
                                            'Installation filtrante',
                                            'Second générateur domestique'
                                          }.contains(entry.key))
                                      .map((entry) => OutlinedButton(
                                            onPressed: () {
                                              final result = gameState
                                                  .installResidentHouseInstallation(
                                                houseId: house.id,
                                                itemName: entry.key,
                                              );
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content:
                                                        Text(result.message)),
                                              );
                                            },
                                            child:
                                                Text('Installer ${entry.key}'),
                                          ))
                                      .toList(),
                                ),
                              const SizedBox(height: 10),
                              const Text('Inventaire du foyer',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              GridView.count(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: List<Widget>.generate(
                                  math.max(
                                      3, house.householdInventory.length + 1),
                                  (index) {
                                    final entries = house
                                        .householdInventory.entries
                                        .where((entry) => entry.value > 0)
                                        .toList();
                                    final entry = index < entries.length
                                        ? entries[index]
                                        : null;
                                    return _InventorySlot(
                                      stack: entry == null
                                          ? null
                                          : Zone0InventoryStack(
                                              resource: entry.key,
                                              amount: entry.value,
                                            ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                  'Les achats et installations du foyer sont réalisés par ses habitants selon leurs priorités.'),
                              Text(
                                'Compte commun : ${gameState.formatInternalPileBalance(house.householdPileBalance)} · Second générateur : ${house.additionalGeneratorInstalled ? 'installé' : '${house.additionalGeneratorSlots} emplacement libre'}',
                              ),
                              Text(
                                  'Autonomie : ${house.lastAutonomyDecision ?? 'en attente de la prochaine résolution'}'),
                              if (gameState.householdRepairFor(house.id)
                                  case final repair?)
                                Text(
                                    'Réparation ${repair.isPlayerRepair ? 'joueur' : 'habitante'} : ${repair.status.name} · fin prévue ${repair.endsAt.day}/${repair.endsAt.month} ${repair.endsAt.hour}h'),
                              const SizedBox(height: 10),
                              const Text('Énergie domestique',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              Text(
                                'Production : ${housingConfig.domesticGeneratorPilesPerHour}${house.additionalGeneratorInstalled ? ' + ${residentEconomyConfig.secondGeneratorBonusPercent}%' : ''} piles/h · revenu 24 h : ${house.recentEnergyProducedPiles} pile(s).',
                              ),
                              Text(
                                'Distribution : toutes les ${residentEconomyConfig.householdDistributionMinutes} min · reste commun ${house.householdPileBalance} pile(s).',
                              ),
                              if (house.currentViability <
                                  house.maximumViability)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    final result = gameState
                                        .startPlayerHouseRepair(house.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(result.message)),
                                    );
                                  },
                                  icon: const Icon(Icons.handyman_outlined),
                                  label: const Text(
                                      'Réparation rapide du joueur (+10%)'),
                                ),
                              const SizedBox(height: 12),
                              if (residents.isNotEmpty) ...<Widget>[
                                const Text('Occupants',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900)),
                                for (final resident in residents)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.person_outline),
                                    title: Row(children: <Widget>[
                                      Flexible(
                                          child: Text(resident.displayName)),
                                      ..._residentAlertIcons(resident),
                                    ]),
                                    subtitle: Text(
                                      '${gameState.residentHappinessFor(resident)}% bonheur · ${resident.needsState.mealsConsumed}/${resident.needsState.mealsRequired} repas · ${resident.needsState.interiorSatisfied ? 'intérieur satisfait' : 'intérieur insuffisant'}',
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (residents.isNotEmpty) const Divider(height: 1),
                  ...residents.map((resident) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Row(children: <Widget>[
                          Flexible(child: Text(resident.displayName)),
                          ..._residentAlertIcons(resident),
                        ]),
                        subtitle: house.currentViability < 50
                            ? Text(
                                'Maison endommagée : -${housingConfig.houseViabilityDamageHappinessPercent}% bonheur · ${gameState.formatInternalPileBalance(resident.internalPileBalance)}')
                            : Text(gameState.formatInternalPileBalance(
                                resident.internalPileBalance)),
                        trailing: _residentWellbeingValue(resident),
                        onTap: () => _showResidentSheet(context, resident),
                      )),
                ]),
              );
            }),
            const SizedBox(height: 12),
          ],
          if (gameState.residents.any((resident) =>
              resident.isActive && resident.houseId == null)) ...<Widget>[
            Text('Habitants',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...gameState.residents
                .where(
                    (resident) => resident.isActive && resident.houseId == null)
                .map((resident) {
              final house = gameState.residentHouseForId(resident.houseId);
              final damaged = house != null && house.currentViability < 50;
              return Card(
                  child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Row(children: <Widget>[
                  Flexible(child: Text(resident.displayName)),
                  ..._residentAlertIcons(resident),
                ]),
                subtitle: Text(
                    '${house?.displayName ?? 'Sans logement'} · ${gameState.formatInternalPileBalance(resident.internalPileBalance)}${damaged ? ' · Maison endommagée : -${housingConfig.houseViabilityDamageHappinessPercent}%' : ''}'),
                trailing: _residentWellbeingValue(resident),
                onTap: () => _showResidentSheet(context, resident),
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

class _CommunityBuildingPosts extends StatelessWidget {
  const _CommunityBuildingPosts({
    required this.gameState,
    required this.roles,
    this.onResidentTap,
  });

  final Zone0GameState gameState;
  final List<CommunityRoleType> roles;
  final ValueChanged<Zone0Resident>? onResidentTap;

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[];
    for (final role in roles) {
      for (var index = 0;
          index < gameState.communityRoleSlotCount(role);
          index++) {
        final assignment = gameState.communityRoleAssignments
            .where((entry) =>
                entry.status != CommunityRoleStatus.archived &&
                entry.roleType == role &&
                entry.slotId == 'resident-$index')
            .firstOrNull;
        final resident = assignment == null
            ? null
            : gameState.residents
                .where((entry) => entry.id == assignment.residentId)
                .firstOrNull;
        slots.add(InkWell(
          onTap: resident == null
              ? null
              : () {
                  if (onResidentTap != null) {
                    onResidentTap!(resident);
                  } else {
                    _showCommunityResidentDetails(context, gameState, resident);
                  }
                },
          child: Ink(
            width: 118,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: resident == null
                  ? Colors.grey.withValues(alpha: .16)
                  : Colors.green.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(resident == null ? Icons.person_outline : Icons.person),
              Text(gameState.communityRoleLabel(role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
              Text(resident?.displayName ?? 'Libre',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ));
      }
    }
    if (slots.isEmpty) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Habitants affectés',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: slots),
                ])));
  }
}

void _showCommunityResidentDetails(
  BuildContext context,
  Zone0GameState gameState,
  Zone0Resident resident,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(resident.displayName,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                  'Passion : ${gameState.residentPassionLabel(gameState.compatibleCommunityRolesFor(resident).isEmpty ? ResidentPassion.cooking : gameState.compatibleCommunityRolesFor(resident).first == CommunityRoleType.kitchenCook ? ResidentPassion.cooking : gameState.compatibleCommunityRolesFor(resident).first == CommunityRoleType.fablabMaker ? ResidentPassion.crafting : gameState.compatibleCommunityRolesFor(resident).first == CommunityRoleType.marketCounter ? ResidentPassion.trading : gameState.compatibleCommunityRolesFor(resident).first == CommunityRoleType.lisiereObserver ? ResidentPassion.livingObservation : ResidentPassion.watching)}'),
              Text('Bonheur : ${gameState.residentHappinessFor(resident)}%'),
              Text(
                  'Repas : ${resident.needsState.mealsConsumed}/${resident.needsState.mealsRequired}'),
            ]),
      ),
    ),
  );
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
              Tab(text: 'Refuge', icon: Icon(Icons.eco_outlined)),
              Tab(text: 'Habitation', icon: Icon(Icons.home_work_outlined)),
              Tab(text: 'Avis', icon: Icon(Icons.forum_outlined)),
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
                  _BuildingViabilityCard(
                    gameState: widget.gameState,
                    buildingId: 'campHeart',
                  ),
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
              ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  const Text('Avis du refuge',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(height: 8),
                  Text(
                      '${widget.gameState.currentPopulation} habitant(s) · ${widget.gameState.availableResidentHousingPlaces} logement(s) libre(s) · ${widget.gameState.activeResidentArrivalCandidates.length} candidature(s) active(s).'),
                  const SizedBox(height: 12),
                  if (widget.gameState.residentVisionSupportCounts.isEmpty)
                    const Text(
                        'Les visions apparaîtront dès qu’un grand chantier accessible pourra être soutenu.')
                  else
                    ...widget.gameState.residentVisionSupportCounts.entries
                        .map((entry) => ListTile(
                              leading: const Icon(Icons.forum_outlined),
                              title: Text(widget.gameState
                                      .communityProjectDefinition(entry.key)
                                      ?.label ??
                                  entry.key),
                              trailing: Text('${entry.value} soutien(s)'),
                            )),
                  const SizedBox(height: 8),
                  const Text(
                      'Ces soutiens éclairent le choix des grands chantiers sans le contraindre.',
                      style: TextStyle(color: Colors.black54)),
                ],
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
                  'Dernière intempérie : ${incident.organicLost} Organique transformé en Déchets, ${incident.batteriesLost} Bio-batterie(s) exposée(s) perdue(s).'),
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
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tour de sécurité'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Surveillance'),
              Tab(text: 'Exploration'),
              Tab(text: 'Recherche'),
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
                  final figurines =
                      widget.gameState.ptipotesAvailableForActivities(
                    snapshot.data ?? const <PtipoteFigurine>[],
                  );
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
                      _BuildingViabilityCard(
                        gameState: widget.gameState,
                        buildingId: 'securityTower',
                      ),
                      const SizedBox(height: 12),
                      _CommunityBuildingPosts(
                        gameState: widget.gameState,
                        roles: const <CommunityRoleType>[
                          CommunityRoleType.securityWatch,
                          CommunityRoleType.weatherWatch,
                        ],
                      ),
                      const SizedBox(height: 12),
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
            _TowerResearchTab(
              gameState: widget.gameState,
              campHeartLevel: widget.campHeartLevel,
              figurineService: widget.figurineService,
            ),
            _TowerWeatherTab(
              gameState: widget.gameState,
              campHeartLevel: widget.campHeartLevel,
            ),
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
      action: _PtipoteActionKind.security,
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
            final available = gameState
                .ptipotesAvailableForActivities(
                  snapshot.data ?? const <PtipoteFigurine>[],
                )
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
                                  'Réduction de danger : -${_localRiskReduction(gameState.effectiveBiomeSecurityFor(biome))}%',
                                ),
                                Text(
                                  'Sécurisation : ${gameState.effectiveBiomeSecurityFor(biome)}% / 100%',
                                ),
                                LinearProgressIndicator(
                                  value: gameState
                                          .effectiveBiomeSecurityFor(biome) /
                                      100,
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
                                      action: _PtipoteActionKind.harvest,
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
                                      action: _PtipoteActionKind.security,
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
      0: 'Haut Refuge',
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

class _TowerResearchTab extends StatelessWidget {
  const _TowerResearchTab({
    required this.gameState,
    required this.campHeartLevel,
    required this.figurineService,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;
  final FigurineService figurineService;

  @override
  Widget build(BuildContext context) {
    if (!gameState.isTowerResearchUnlocked) {
      return _BuildingUpgradeTab(
        gameState: gameState,
        targetId: 'towerResearchModule',
        title: 'Débloquer la Tour de recherche',
        description:
            'Elle permet d’envoyer des P’TIPOTES en mission afin de récupérer des Capsules de données selon la météo actuelle.',
        currentEffects: const <String>[
          'Recherche de données : verrouillée',
        ],
        nextEffects: const <String>[
          'Chances par famille de données',
          'Influence de la météo sur les recherches de Lisière',
        ],
        campHeartLevel: campHeartLevel,
      );
    }
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
                  const Text('Recherche de capsules de données',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                    'Touchez un biome, choisissez au moins un P’TIPOTE, puis lancez une mission. Les Capsules de données rejoignent directement le Kernel au retour.',
                  ),
                  const SizedBox(height: 6),
                  const Text('Les connaissances locales perdent 2% par jour.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TowerResearchMap3x3(
            gameState: gameState,
            figurineService: figurineService,
          ),
          const SizedBox(height: 12),
          ...ForageBiome.values
              .where(gameState.isBiomeUnlocked)
              .map((biome) => _TowerResearchBiomeSummary(
                    gameState: gameState,
                    biome: biome,
                    onTap: () => _showTowerResearchBiomeSheet(
                      context,
                      gameState: gameState,
                      biome: biome,
                      figurineService: figurineService,
                    ),
                  )),
        ],
      ),
    );
  }
}

class _TowerResearchMap3x3 extends StatelessWidget {
  const _TowerResearchMap3x3({
    required this.gameState,
    required this.figurineService,
  });
  final Zone0GameState gameState;
  final FigurineService figurineService;

  @override
  Widget build(BuildContext context) {
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
      0: 'Haut Refuge',
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
          return const _ResearchMapCell(
            label: 'Camp',
            icon: Icons.home_outlined,
            enabled: false,
          );
        }
        final biome = cells[index];
        if (biome == null) {
          return _ResearchMapCell(
            label:
                '${futureLabels[index] ?? 'Zone inconnue'}\nBientôt disponible',
            icon: Icons.lock_outline,
            enabled: false,
          );
        }
        final unlocked = gameState.isBiomeUnlocked(biome);
        final activeEndsAt = gameState.activeResearchEndsAtFor(biome);
        return _ResearchMapCell(
          label: lisiereForageConfig.biomes[biome]!.label,
          icon: activeEndsAt == null
              ? Icons.manage_search_outlined
              : Icons.hourglass_top,
          enabled: unlocked,
          progress: gameState.biomeResearchProgressFor(biome),
          subtitle: activeEndsAt == null ? null : _countdownLabel(activeEndsAt),
          onTap: unlocked
              ? () => _showTowerResearchBiomeSheet(
                    context,
                    gameState: gameState,
                    biome: biome,
                    figurineService: figurineService,
                  )
              : null,
        );
      },
    );
  }
}

class _ResearchMapCell extends StatelessWidget {
  const _ResearchMapCell({
    required this.label,
    required this.icon,
    required this.enabled,
    this.progress,
    this.subtitle,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final int? progress;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: enabled
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
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
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
                if (progress != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text('$progress%', style: const TextStyle(fontSize: 10)),
                ],
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ),
      );
}

class _TowerResearchBiomeSummary extends StatelessWidget {
  const _TowerResearchBiomeSummary({
    required this.gameState,
    required this.biome,
    required this.onTap,
  });

  final Zone0GameState gameState;
  final ForageBiome biome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = gameState.biomeResearchProgressFor(biome);
    final activeEndsAt = gameState.activeResearchEndsAtFor(biome);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.manage_search_outlined),
        title: Text(lisiereForageConfig.biomes[biome]!.label,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(activeEndsAt == null
            ? 'Connaissances : $progress%'
            : 'Recherche en cours · retour ${_countdownLabel(activeEndsAt)}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

Future<void> _showTowerResearchBiomeSheet(
  BuildContext context, {
  required Zone0GameState gameState,
  required ForageBiome biome,
  required FigurineService figurineService,
}) async {
  final progress = gameState.biomeResearchProgressFor(biome);
  final config = towerOperationsConfig.research;
  final activeEndsAt = gameState.activeResearchEndsAtFor(biome);
  final families = gameState
      .towerResearchFamilyWeightsFor(biome)
      .entries
      .where((entry) => entry.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  String chances(Map<int, int> values, int count) => List<String>.generate(
        count,
        (index) => '${index + 1}e : ${values[index + 1] ?? 0}%',
      ).join(' · ');
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(lisiereForageConfig.biomes[biome]!.label,
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    )),
            const SizedBox(height: 8),
            Text('Connaissances locales : $progress%'),
            LinearProgressIndicator(value: progress / 100),
            if (gameState.capsuleDiscoveryMultiplierFor(biome) < 1)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Sous 50 % de connaissances, les chances de trouver des Capsules sont divisées par deux.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(height: 14),
            if (progress >= config.cellChanceRevealPercent) ...<Widget>[
              const Text('Chances de trouver des Capsules',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text(
                  'Recherche : ${chances(config.researchCellChanceByOrdinal, 5)}'),
              const SizedBox(height: 12),
            ] else
              const Text(
                  'À 25%, les chances de trouver des Capsules seront révélées.'),
            if (progress >= config.valueChanceRevealPercent) ...<Widget>[
              const Text('Quantité de Données des Capsules',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text(
                  'Recherche : valeur 5–6 : 100% · 7–8 : ${config.researchValueSevenEightChance}% · 9 : ${config.researchValueNineChance}%'),
              const SizedBox(height: 12),
            ] else
              const Text('À 50%, les probabilités de valeur seront révélées.'),
            if (progress >= config.familyRevealPercent) ...<Widget>[
              const Text('Types de Capsules du biome',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: families
                    .map((entry) => Chip(
                          label: Text(progress >= config.fullRevealPercent
                              ? '${_kernelDataFamilyLabel(entry.key)} ${entry.value}%'
                              : _kernelDataFamilyLabel(entry.key)),
                        ))
                    .toList(),
              ),
              if (progress < config.fullRevealPercent)
                Text(
                    'À ${config.fullRevealPercent}%, les pourcentages par type seront révélés.'),
              const SizedBox(height: 12),
            ] else
              Text(
                  'À ${config.familyRevealPercent}%, les types de Capsules seront révélés.'),
            if (activeEndsAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    'Recherche en cours · retour ${_countdownLabel(activeEndsAt)}'),
              )
            else ...<Widget>[
              const SizedBox(height: 16),
              const Text('Lancer une recherche',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <ForageDuration>[
                  ForageDuration.oneHour,
                  ForageDuration.twoHours,
                  ForageDuration.sixHours,
                  ForageDuration.tenHours,
                ]
                    .map((duration) => FilledButton.tonal(
                          onPressed: () async {
                            final figurines =
                                await figurineService.watchMyFigurines().first;
                            if (!context.mounted) return;
                            final selected = await _pickPtipoteGroupForResearch(
                              context: context,
                              gameState: gameState,
                              figurines: gameState
                                  .ptipotesAvailableForActivities(figurines),
                            );
                            if (selected == null ||
                                selected.isEmpty ||
                                !context.mounted) {
                              return;
                            }
                            try {
                              gameState.startTowerResearchMission(
                                figurines: selected,
                                biome: biome,
                                duration: duration,
                                intensity: ForageIntensity.normal,
                              );
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${selected.map((item) => item.displayName).join(', ')} part${selected.length > 1 ? 'ent' : ''} en Recherche.',
                                  ),
                                ),
                              );
                            } on StateError catch (error) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                          },
                          child: Text(
                            '${lisiereForageConfig.durations[duration]!.label} · +${lisiereForageConfig.durations[duration]!.theoreticalHours * config.progressPerHour}%',
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _TowerWeatherTab extends StatelessWidget {
  const _TowerWeatherTab({
    required this.gameState,
    required this.campHeartLevel,
  });
  final Zone0GameState gameState;
  final int campHeartLevel;
  @override
  Widget build(BuildContext context) {
    if (!gameState.isTowerWeatherUnlocked) {
      return _BuildingUpgradeTab(
        gameState: gameState,
        targetId: 'towerWeatherModule',
        title: 'Débloquer la Tour météo',
        description:
            'Elle active les prévisions, les alertes météo et l’indicateur météo du HUD.',
        currentEffects: const <String>['Météo : verrouillée'],
        nextEffects: const <String>[
          'Prévisions météo et alertes',
          'Météo actuelle affichée dans le HUD',
        ],
        campHeartLevel: campHeartLevel,
      );
    }
    final active = gameState.activeGlobalWeatherEvent;
    final upcoming = gameState.nextGlobalWeatherEvent;
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Prochaine météo',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(upcoming == null
                      ? 'Prévision en cours de calcul.'
                      : '${label(upcoming.type)} · ${intensity(upcoming.intensity)}'),
                  if (upcoming != null)
                    Text(upcoming.type == TowerWeatherType.calm
                        ? 'Conditions calmes prévues sur la Zone 0.'
                        : 'Biomes touchés : ${biomes(upcoming)}'),
                ],
              ),
            ),
          ),
          if (upcoming != null) ...<Widget>[
            const SizedBox(height: 10),
            _WeatherPreparationCard(gameState: gameState, event: upcoming),
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
    final uses = gameState.weatherProtectionUsesFor(event.intensity);
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
                  if (uses > 0)
                    Text(
                      '${event.intensity == GlobalWeatherIntensity.moderate ? 'Météo normale' : event.intensity == GlobalWeatherIntensity.strong ? 'Météo moyenne' : 'Météo forte'} : les consommables de protection subiront $uses utilisation${uses > 1 ? 's' : ''}.',
                    ),
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
          'FabLab niveau 1 : ${fablabConfig.fablabStorageForLevel(1)} unités de stockage global.',
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
  final FigurineService _figurineService = FigurineService();
  PtipoteFigurine? _constructor;
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
    final requiredData = widget.gameState.projectRequiredData(
      widget.targetId,
      targetLevel: project.targetLevel,
    );
    final dataIssue = widget.gameState.projectDataRequirementIssue(
      widget.targetId,
      targetLevel: project.targetLevel,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.title,
                style: Theme.of(
                  context,
                )
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
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
              if (widget.gameState
                      .projectBioBatteryRequirement(widget.targetId) >
                  0)
                _ConstructionMaterialProgress(
                  resource: 'Bio-batteries',
                  deposited: project.depositedBioBatteries,
                  required: widget.gameState
                      .projectBioBatteryRequirement(widget.targetId),
                  enabled: project.canEditMaterials,
                  onDeposit: (amount) =>
                      widget.gameState.depositProjectBioBattery(
                    widget.targetId,
                    amount: amount,
                  ),
                  onWithdraw: () {},
                  showWithdraw: false,
                ),
              if (requiredData.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('DONNÉES',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                ...requiredData.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_kernelDataFamilyLabel(entry.key)} ${widget.gameState.pTibugDataReserve[entry.key] ?? 0} / ${entry.value}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: (widget.gameState.pTibugDataReserve[entry.key] ??
                                    0) >=
                                entry.value
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
                if (dataIssue != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      dataIssue,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
              if (footer != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  footer,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
              if (!project.isInProgress &&
                  project.state !=
                      ConstructionProjectState.maxLevel) ...<Widget>[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('MODE DE CONSTRUCTION',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 4),
                Text(_constructor == null
                    ? 'Sans P’TIPOTE · Énergie ${project.unattendedEnergyCostSnapshot > 0 ? project.unattendedEnergyCostSnapshot : widget.gameState.projectUnattendedEnergyCost(widget.targetId, targetLevel: project.targetLevel)}'
                    : 'Avec ${_constructor!.displayName} · matériaux -20 % · énergie 0'),
                StreamBuilder<List<PtipoteFigurine>>(
                  stream: _figurineService.watchMyFigurines(),
                  builder: (context, snapshot) => Wrap(
                    spacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () {
                          final result = widget.gameState
                              .configureProjectConstructionMode(
                                  widget.targetId);
                          if (result.success)
                            setState(() => _constructor = null);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.message)));
                        },
                        child: const Text('Sans P’TIPOTE'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final figurine = await _pickPtipoteForActivity(
                            context: context,
                            gameState: widget.gameState,
                            figurines:
                                widget.gameState.ptipotesAvailableForActivities(
                              snapshot.data ?? const <PtipoteFigurine>[],
                            ),
                            title: 'Choisir un Constructeur',
                          );
                          if (figurine == null || !mounted) return;
                          final result =
                              widget.gameState.configureProjectConstructionMode(
                            widget.targetId,
                            constructor: figurine,
                          );
                          if (result.success)
                            setState(() => _constructor = figurine);
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)));
                        },
                        icon: const Icon(Icons.pets_outlined),
                        label: const Text('Avec P’TIPOTE'),
                      ),
                    ],
                  ),
                ),
                if (_constructor != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Constructeur N${widget.gameState.constructorLevelFor(_constructor!)} · Niveau ${widget.gameState.levelFor(_constructor!)} · durée -${(widget.gameState.getConstructorTimeReduction(_constructor!) * 100).round()} %',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: blockedReason == null &&
                        project.isReady &&
                        dataIssue == null &&
                        !project.isInProgress &&
                        project.state != ConstructionProjectState.maxLevel
                    ? () {
                        final result =
                            widget.gameState.startConstructionProject(
                          widget.targetId,
                          campHeartLevel: campHeartLevel,
                          constructor: _constructor,
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
    this.showWithdraw = true,
  });

  final String resource;
  final int deposited;
  final int required;
  final bool enabled;
  final ValueChanged<int> onDeposit;
  final VoidCallback onWithdraw;
  final bool showWithdraw;

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
              if (showWithdraw)
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

/// V1 of the Logistics screen deliberately stays a central board: no vehicle,
/// routing or transport simulation is introduced here.
class LogisticsPage extends StatelessWidget {
  const LogisticsPage({
    super.key,
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) {
    final figurineService = FigurineService();
    return Scaffold(
      appBar: AppBar(title: Text('Logistique · N${gameState.logisticsLevel}')),
      body: StreamBuilder<List<PtipoteFigurine>>(
        stream: figurineService.watchMyFigurines(),
        builder: (context, snapshot) => AnimatedBuilder(
          animation: gameState,
          builder: (context, _) {
            final allFigurines = snapshot.data ?? const <PtipoteFigurine>[];
            final all = gameState.ptipotesAvailableForActivities(allFigurines);
            String ptipoteName(String id) =>
                allFigurines
                    .where((figurine) => figurine.id == id)
                    .map((figurine) => figurine.displayName)
                    .firstOrNull ??
                'P’TIPOTE';
            final projectEntries = gameState.constructionProjects.values
                .where((item) => item.isInProgress)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('BÂTIMENT LOGISTIQUE',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text(
                            '+${gameState.logisticsStorageCapacity} stockage camp'),
                        Text(
                            'Kits Logistique : ${gameState.logisticsRepairKitStored} / ${gameState.logisticsRepairKitCapacity}'),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  gameState.depositLogisticsRepairKits(),
                              child: const Text('+ Kit'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  gameState.withdrawLogisticsRepairKits(),
                              child: const Text('Retirer'),
                            ),
                          ],
                        ),
                        Text(
                            'Maintenance : ${gameState.logisticsMaintenancePtipoteIds.length} / ${gameState.logisticsPtipoteSlotCapacity}'),
                        const SizedBox(height: 8),
                        Text(
                            'Réparation automatique sous ${gameState.logisticsAutoRepairThreshold}%'),
                        Slider(
                          value:
                              gameState.logisticsAutoRepairThreshold.toDouble(),
                          min:
                              logisticsConfig.minimumRepairThreshold.toDouble(),
                          max:
                              logisticsConfig.maximumRepairThreshold.toDouble(),
                          divisions: logisticsConfig.maximumRepairThreshold -
                              logisticsConfig.minimumRepairThreshold,
                          label: '${gameState.logisticsAutoRepairThreshold}%',
                          onChanged: (value) => gameState
                              .setLogisticsAutoRepairThreshold(value.round()),
                        ),
                        if (gameState.logisticsMaintenancePtipoteIds.length <
                            gameState.logisticsPtipoteSlotCapacity)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final selected = await _pickPtipoteForActivity(
                                context: context,
                                gameState: gameState,
                                figurines: all,
                                title: 'Affecter à la Maintenance',
                              );
                              if (selected == null || !context.mounted) return;
                              final result = gameState
                                  .assignLogisticsMaintenance(selected);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Affecter à la Maintenance'),
                          ),
                        if (gameState.logisticsMaintenancePtipoteIds.isNotEmpty)
                          ...gameState.logisticsMaintenancePtipoteIds.map(
                            (id) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.build_circle_outlined),
                              title: Text(ptipoteName(id)),
                              subtitle: const Text('Poste de maintenance'),
                              trailing: TextButton(
                                onPressed: () {
                                  final result =
                                      gameState.removeLogisticsMaintenance(id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                },
                                child: const Text('Rentrer'),
                              ),
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
                        const Text('TRAVAUX EN COURS',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        if (projectEntries.isEmpty)
                          const Text('Aucun chantier en cours.')
                        else
                          ...projectEntries.map((project) => ListTile(
                                dense: true,
                                leading:
                                    const Icon(Icons.construction_outlined),
                                title: Text(project.targetType),
                                subtitle: Text(
                                  '${project.assignedPtipoteName ?? 'Automatisé'} · fin ${_countdownLabel(project.endsAt!)}',
                                ),
                              )),
                        ...gameState.logisticsMaintenanceJobs
                            .where((job) => !job.completed)
                            .map((job) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.build_outlined),
                                  title: Text('Réparation · ${job.buildingId}'),
                                  subtitle: Text(
                                    '${ptipoteName(job.ptipoteId)} · fin ${_countdownLabel(job.endsAt)}',
                                  ),
                                )),
                      ],
                    ),
                  ),
                ),
                if (gameState.logisticsQueueEnabled)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'LISTE CONSTRUCTION · ${gameState.logisticsConstructionQueue.length}/${gameState.logisticsQueueCapacity}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                              'Jusqu’à ${gameState.logisticsParallelConstructionCapacity} chantier(s) Logistique simultané(s).'),
                          const Text(
                              'Les ordres bloqués restent visibles et ne sont jamais sautés.'),
                          ...gameState.logisticsConstructionQueue.map(
                            (entry) => ListTile(
                              dense: true,
                              title: Text(
                                  '${entry.targetType} · N${entry.targetLevel}'),
                              subtitle: Text(
                                '${entry.constructorPtipoteName ?? 'Automatisé'} · '
                                '${entry.status == LogisticsQueueStatus.blocked ? 'En attente de ressources, Données ou prérequis' : 'En attente'}',
                              ),
                              trailing: Wrap(
                                spacing: 0,
                                children: <Widget>[
                                  IconButton(
                                    tooltip: 'Monter',
                                    onPressed: gameState
                                                .logisticsConstructionQueue
                                                .first
                                                .id ==
                                            entry.id
                                        ? null
                                        : () => gameState
                                            .moveLogisticsConstructionQueueEntry(
                                                entry.id, -1),
                                    icon:
                                        const Icon(Icons.arrow_upward_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Descendre',
                                    onPressed: gameState
                                                .logisticsConstructionQueue
                                                .last
                                                .id ==
                                            entry.id
                                        ? null
                                        : () => gameState
                                            .moveLogisticsConstructionQueueEntry(
                                                entry.id, 1),
                                    icon: const Icon(
                                        Icons.arrow_downward_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Retirer',
                                    onPressed: () => gameState
                                        .removeLogisticsConstructionQueueEntry(
                                            entry.id),
                                    icon: const Icon(Icons.close_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ...gameState.constructionProjects.values
                              .where((project) =>
                                  !project.isInProgress &&
                                  project.isReady &&
                                  !gameState.logisticsConstructionQueue.any(
                                    (entry) =>
                                        entry.targetId == project.targetId,
                                  ))
                              .map(
                                (project) => TextButton.icon(
                                  onPressed: () {
                                    final result =
                                        gameState.queueConstructionProject(
                                            project.targetId);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(result.message)),
                                    );
                                  },
                                  icon: const Icon(Icons.playlist_add_outlined),
                                  label: Text('Ajouter ${project.targetType}'),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                if (gameState.logisticsLevel < 4)
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => _ConstructionProjectSheet(
                        gameState: gameState,
                        targetId: 'logistics',
                        title: 'Améliorer le Logistique',
                        description:
                            'Augmente le stockage et les capacités de maintenance.',
                        campHeartLevel: campHeartLevel,
                      ),
                    ),
                    icon: const Icon(Icons.upgrade_outlined),
                    label: const Text('Améliorer'),
                  ),
              ],
            );
          },
        ),
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
            final figurines = widget.gameState.ptipotesAvailableForActivities(
              snapshot.data ?? const <PtipoteFigurine>[],
            );
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
                        if (!widget.gameState.isMarketInformationPointUnlocked)
                          Text(
                            'Zone centrale : niveau ${marketConfig.informationPointLevel} requis.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        TextButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (_) => const _BuildingInformationTab(
                              title: 'Marché',
                              description:
                                  'Chaque vente répond à une demande habitant visible dans cette page. Le stock ne déclenche jamais de vente seul. La Zone centrale accueille un P’TIPOTE pour soutenir l’ensemble des magasins.',
                            ),
                          ),
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Infos'),
                        ),
                        if (widget.gameState.isMarketInformationPointUnlocked)
                          _marketCentralCapabilities(),
                        if (widget.gameState.isMarketInformationPointUnlocked)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text('Emplacement P’TIPOTE central',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        if (widget.gameState.isMarketInformationPointUnlocked &&
                            widget.gameState.marketAssignedPtipoteId != null)
                          if (figurines
                                  .where((figurine) =>
                                      figurine.id ==
                                      widget.gameState.marketAssignedPtipoteId)
                                  .firstOrNull
                              case final assigned?)
                            Builder(
                              builder: (context) {
                                final assignedLevel =
                                    widget.gameState.levelFor(assigned);
                                return Card(
                                  margin: const EdgeInsets.only(top: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(children: <Widget>[
                                      Expanded(
                                        flex: 4,
                                        child: Row(children: <Widget>[
                                          SizedBox(
                                              width: 46,
                                              child: PtipoteImage(
                                                  type: assigned.type,
                                                  species: assigned.species,
                                                  height: 46)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Text(assigned.displayName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900))),
                                        ]),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                            'Niv. $assignedLevel\nFaim ${widget.gameState.hungerFor(assigned)}\nRepos ${widget.gameState.restFor(assigned)}',
                                            maxLines: 3),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: <Widget>[
                                              OutlinedButton(
                                                onPressed: assignedLevel >= 2
                                                    ? _showMarketRestockRules
                                                    : null,
                                                child: Text(assignedLevel >= 2
                                                    ? 'Gestion appro'
                                                    : 'Appro · niv. 2'),
                                              ),
                                              TextButton(
                                                onPressed: () => _message(widget
                                                    .gameState
                                                    .removeFromMarket()
                                                    .message),
                                                child:
                                                    const Text('Faire rentrer'),
                                              ),
                                              if (widget.gameState
                                                      .hasMarketTeamwork &&
                                                  widget.gameState
                                                          .marketSecondaryAssignedPtipoteId ==
                                                      null)
                                                TextButton(
                                                  onPressed: () async {
                                                    final figurine =
                                                        await _pickPtipoteForActivity(
                                                      context: context,
                                                      gameState:
                                                          widget.gameState,
                                                      figurines: figurines,
                                                      title:
                                                          'Affecter à la Zone centrale',
                                                      action: _PtipoteActionKind
                                                          .commerce,
                                                    );
                                                    if (figurine == null ||
                                                        !context.mounted) {
                                                      return;
                                                    }
                                                    _message(widget.gameState
                                                        .assignToMarket(
                                                            figurine)
                                                        .message);
                                                  },
                                                  child: const Text(
                                                      'Ajouter un équipier'),
                                                ),
                                            ]),
                                      ),
                                    ]),
                                  ),
                                );
                              },
                            )
                          else
                            OutlinedButton(
                              onPressed: () => _message(
                                  widget.gameState.removeFromMarket().message),
                              child: const Text('Faire rentrer'),
                            )
                        else if (widget
                            .gameState.isMarketInformationPointUnlocked)
                          FilledButton.icon(
                            onPressed: () async {
                              final figurine = await _pickPtipoteForActivity(
                                context: context,
                                gameState: widget.gameState,
                                figurines: figurines,
                                title: 'Affecter à la Zone centrale',
                                action: _PtipoteActionKind.commerce,
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
                            label: const Text('Affecter à la Zone centrale'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    const ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.storefront_outlined),
                        label: Text('Vente')),
                    const ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.construction_outlined),
                        label: Text('Gestion')),
                    ButtonSegment(
                        value: 2,
                        enabled: widget.gameState.isMarketRequestBookUnlocked,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('Demandes')),
                  ],
                  selected: <int>{_marketTab},
                  onSelectionChanged: (value) =>
                      setState(() => _marketTab = value.first),
                ),
                const SizedBox(height: 10),
                if (_marketTab == 1) _marketManagementTab(),
                if (_marketTab == 2) _marketRequestBook(),
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
                  if (widget
                      .gameState.savedMerchantOffers.isNotEmpty) ...<Widget>[
                    _savedMerchantOffersDropdown(),
                    const SizedBox(height: 10),
                  ],
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
                                  child: Text(
                                    'Ouvrir une Bio-batterie (+${widget.gameState.energyFromBioBatteryForBuildingLevel(widget.gameState.marketDistributor.level)} énergie)',
                                  ),
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
                                      label: stack == null
                                          ? null
                                          : widget.gameState
                                              .marketInventoryDisplayLabel(
                                                  stack),
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
                  _marketShopsSection(figurines),
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
      enableDrag: true,
      isDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Ordres de réapprovisionnement',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
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

  /// Les capacités de la Zone centrale sont visibles avant son emplacement
  /// P'TIPOTE : le niveau débloque leur accès, leur construction détaillée
  /// reste regroupée dans l'onglet Gestion.
  Widget _marketCentralCapabilities() {
    final level = widget.gameState.marketLevel;
    final capabilities = <String>['Vente centrale'];
    if (level >= 2) {
      capabilities.addAll(<String>[
        'Distributeurs',
        'Réparation',
        'Recharge',
      ]);
    }
    if (level >= 3) {
      capabilities.addAll(<String>[
        'Logistique',
        'Optimisation logistique',
        'Local technique',
      ]);
    }
    if (level >= 4) {
      capabilities.addAll(<String>[
        'Assistant commerçant',
        'Travail d’équipe',
        'Bio-logiciel technique',
        'Merchandising',
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Zone centrale · capacités déverrouillées',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: capabilities
                .map((label) => Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(label),
                    ))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _marketManagementTab() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Bâtiment et installations',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _BuildingViabilityCard(
                    gameState: widget.gameState,
                    buildingId: 'market',
                  ),
                  const SizedBox(height: 10),
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
                    label: const Text('Améliorer le Marché'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Réparation et installations structurelles se gèrent ici.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _marketCentralUpgradesCard(),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Gestion des boutiques',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text(
                    'La réinitialisation rend les stocks à la Maison dans la limite de capacité avant de retirer les boutiques.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _confirmMarketShopReset,
                    icon: const Icon(Icons.restart_alt_outlined),
                    label: const Text('Réinitialiser mes boutiques'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _marketCentralUpgradesCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Améliorations de la Zone centrale',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                'Une amélioration s’ajoute à la même Zone centrale : elle ne crée ni bâtiment ni poste supplémentaire, sauf Travail d’équipe.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              ...MarketCentralUpgrade.values.map((upgrade) {
                final installed =
                    widget.gameState.hasMarketCentralUpgrade(upgrade);
                final available =
                    widget.gameState.marketLevel >= upgrade.requiredMarketLevel;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(installed
                      ? Icons.check_circle_outline
                      : Icons.build_outlined),
                  title: Text(upgrade.label),
                  subtitle: Text(installed
                      ? 'Installée'
                      : available
                          ? 'Disponible au niveau actuel'
                          : 'Marché niveau ${upgrade.requiredMarketLevel} requis'),
                  trailing: installed
                      ? const Text('Actif')
                      : OutlinedButton(
                          onPressed: available
                              ? () => _message(widget.gameState
                                  .buildMarketCentralUpgrade(upgrade)
                                  .message)
                              : null,
                          child: const Text('Installer'),
                        ),
                );
              }),
            ],
          ),
        ),
      );

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

  Widget _marketShopsSection(List<PtipoteFigurine> figurines) {
    const labels = <String, String>{
      'restaurant': 'Restaurant',
      'home': 'Magasin du foyer',
      'equipment': 'Magasin d’équipement',
      'ptibug': 'Magasin P’TIBUG',
      'wholesale': 'Grossiste',
      'general': 'Ancien magasin généraliste',
      'ameublement': 'Ancien magasin du foyer',
    };
    final slots = widget.gameState.marketShopLimit;
    final shops = widget.gameState.marketShops
        .where((shop) => !shop.isPrimary)
        .toList(growable: false);
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
            _CommunityBuildingPosts(
              gameState: widget.gameState,
              roles: const <CommunityRoleType>[
                CommunityRoleType.marketCounter,
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '${widget.gameState.marketShopCount}/$slots boutique(s) construite(s).'),
            ...widget.gameState.unlockedMarketShopSlots
                .where((slot) =>
                    slot.status == MarketShopSlotStatus.vacant ||
                    slot.status == MarketShopSlotStatus.pendingResidentClaim)
                .map((slot) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(slot.status ==
                              MarketShopSlotStatus.pendingResidentClaim
                          ? 'Emplacement réservé par un habitant'
                          : 'Emplacement vacant'),
                      subtitle: Text(slot.status ==
                              MarketShopSlotStatus.pendingResidentClaim
                          ? 'Installation annoncée : ${slot.claimFinalizationAt == null ? 'prochainement' : _countdownLabel(slot.claimFinalizationAt!)}'
                          : 'Vacant depuis ${slot.vacantSince == null ? 'maintenant' : '${DateTime.now().difference(slot.vacantSince!).inDays} jour(s)'}'),
                    )),
            const SizedBox(height: 10),
            if (widget.gameState.marketShopConstructionOrder case final order?)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.construction_outlined),
                  title: Text(order.isInProgress
                      ? (order.targetShopId == null
                          ? 'Magasin en construction'
                          : 'Amélioration en cours')
                      : (order.targetShopId == null
                          ? 'Magasin à préparer'
                          : 'Amélioration à préparer')),
                  subtitle: Text(order.isInProgress
                      ? 'Fin : ${order.endsAt == null ? 'prochainement' : _countdownLabel(order.endsAt!)}'
                      : 'Dépôts : Organique ${order.deposits['Organique'] ?? 0}/${order.requirements['Organique'] ?? 0} · Minéral ${order.deposits['Minéral'] ?? 0}/${order.requirements['Minéral'] ?? 0} · Bio-batteries ${order.depositedBioBatteries}/${order.requiredBioBatteries}'),
                  trailing: TextButton(
                    onPressed: _showMarketShopConstructionSheet,
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            if (widget.gameState.residentCommunityShopConstructionOrder
                case final communityOrder?)
              Card(
                color: const Color(0xffc7a746).withValues(alpha: .18),
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined,
                      color: Color(0xff9c7b14)),
                  title: const Text('Magasin communautaire autorisé'),
                  subtitle: Text(
                      '${labels[communityOrder.specialization] ?? communityOrder.specialization} · construction dans ${communityOrder.endsAt == null ? '2 jours' : _countdownLabel(communityOrder.endsAt!)}. Le chantier sera annulé si le manque est résolu.'),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text(
                  'Magasin - ${labels[widget.gameState.primaryMarketShopSpecialization] ?? 'Fournitures'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  'Niveau ${widget.gameState.primaryMarketShopLevel} · ${widget.gameState.marketStock.length}/${widget.gameState.marketShopStockLimit(Zone0GameState.primaryMarketShopId)} piles${widget.gameState.primaryMarketShopChosen ? '' : ' · prix -${marketConfig.baseStorePricePenaltyPercent}%'}'),
              trailing: widget.gameState.primaryMarketShopLevel < 2
                  ? TextButton(
                      onPressed: () {
                        final result = widget.gameState
                            .prepareMarketShopUpgrade(
                                Zone0GameState.primaryMarketShopId);
                        _message(result.message);
                        if (result.success) _showMarketShopConstructionSheet();
                      },
                      child: const Text('Améliorer'),
                    )
                  : const Text('Max.'),
            ),
            _marketShopSellerCard(
                Zone0GameState.primaryMarketShopId, figurines),
            _marketShopStockGrid(Zone0GameState.primaryMarketShopId),
            const SizedBox(height: 8),
            _shopDistributorCard(Zone0GameState.primaryMarketShopId),
            if (!widget.gameState.primaryMarketShopChosen)
              FilledButton.icon(
                onPressed: _showPrimaryShopPicker,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Construire un magasin'),
              ),
            const Divider(),
            ...shops.map((shop) => Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      tileColor: shop.emergencyPink
                          ? const Color(0xffc7a746).withValues(alpha: .18)
                          : null,
                      leading: Icon(Icons.storefront_outlined,
                          color: shop.emergencyPink
                              ? const Color(0xff9c7b14)
                              : null),
                      title: Text(
                          shop.ownershipType ==
                                  MarketShopOwnershipType.residentCommunity
                              ? 'Magasin de ${widget.gameState.residents.where((resident) => resident.id == shop.ownerResidentId).firstOrNull?.displayName ?? 'la communauté'} - ${labels[shop.specialization] ?? 'Magasin'}'
                              : 'Magasin - ${labels[shop.specialization] ?? 'Magasin'}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${shop.ownershipType == MarketShopOwnershipType.residentCommunity ? (shop.emergencyPink ? 'Comptoir communautaire · ventes toutes les 10 min par ligne de production' : 'Commerce habitant · ${widget.gameState.residents.where((resident) => resident.id == shop.ownerResidentId).firstOrNull?.displayName ?? 'sans responsable'} · distribution par ligne de production') : 'Joueur · niveau ${shop.level} · ${shop.stock.length}/${shop.stockSlots} piles'}'),
                      trailing: shop.emergencyPink
                          ? const Text('Communautaire')
                          : shop.level < 2
                              ? TextButton(
                                  onPressed: () {
                                    final result = widget.gameState
                                        .prepareMarketShopUpgrade(shop.id);
                                    _message(result.message);
                                    if (result.success) {
                                      _showMarketShopConstructionSheet();
                                    }
                                  },
                                  child: const Text('Améliorer'),
                                )
                              : const Text('Max.'),
                    ),
                    if (shop.ownershipType !=
                        MarketShopOwnershipType.residentCommunity) ...<Widget>[
                      _marketShopSellerCard(shop.id, figurines),
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
                      const SizedBox(height: 8),
                      _shopDistributorCard(shop.id),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                            'Sans stock ni distributeur : une demande compatible est distribuée toutes les 10 min lorsque la ligne habitante est complète.'),
                      ),
                    const Divider(),
                  ],
                )),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(
                  math.max(0, slots - widget.gameState.marketShopCount),
                  (index) {
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

  Widget _marketShopSellerCard(
    String shopId,
    List<PtipoteFigurine> figurines,
  ) {
    final sellerId = widget.gameState.marketStoreAssignedPtipoteIds[shopId];
    final sellerName = widget.gameState.marketStoreAssignedPtipoteNames[shopId];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: sellerId == null
          ? OutlinedButton.icon(
              onPressed: () async {
                final figurine = await _pickPtipoteForActivity(
                  context: context,
                  gameState: widget.gameState,
                  figurines: figurines,
                  title: 'Affecter un vendeur',
                  action: _PtipoteActionKind.commerce,
                );
                if (figurine == null || !mounted) return;
                _message(widget.gameState
                    .assignToMarketShop(shopId, figurine)
                    .message);
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(
                  'Affecter un vendeur · réponse ${marketConfig.storeSellerResponseMinutes} min'),
            )
          : ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text('Vendeur : ${sellerName ?? 'P’TIPOTE'}'),
              subtitle: Text(
                  'Poste permanent · réponse ${marketConfig.storeSellerResponseMinutes} min'),
              trailing: TextButton(
                onPressed: () => _message(
                    widget.gameState.removeFromMarketShop(shopId).message),
                child: const Text('Faire rentrer'),
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
              label: stack == null
                  ? null
                  : widget.gameState.marketInventoryDisplayLabel(stack),
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
      final endsAt = distributor?.constructionEndsAt;
      return OutlinedButton.icon(
        onPressed: () => _showDistributorBuildSheet(shopId),
        icon: const Icon(Icons.precision_manufacturing_outlined),
        label: Text(endsAt == null
            ? 'Construire le distributeur'
            : 'Distributeur en construction · ${_countdownLabel(endsAt)}'),
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
              if (distributor.upgradeEndsAt != null)
                Text(
                    'Amélioration en cours · ${_countdownLabel(distributor.upgradeEndsAt!)}'),
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
                  child: Text(
                    'Ouvrir une Bio-batterie (+${widget.gameState.energyFromBioBatteryForBuildingLevel(distributor.level)} énergie)',
                  ),
                ),
                if (distributor.isBroken)
                  FilledButton(
                    onPressed: () => _message(widget.gameState
                        .repairMarketDistributor(shopId: shopId)
                        .message),
                    child: const Text('Réparer'),
                  ),
                if (distributor.level < 3 && distributor.upgradeEndsAt == null)
                  OutlinedButton(
                    onPressed: () => _message(widget.gameState
                        .upgradeMarketDistributor(shopId: shopId)
                        .message),
                    child: Text(
                      'Améliorer · ${marketConfig.distributorConstructionCost.entries.map((entry) => '${entry.value * (distributor.level + 1)} ${entry.key}').join(' · ')}',
                    ),
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
                          label: index < distributor.stock.length
                              ? widget.gameState.marketInventoryDisplayLabel(
                                  distributor.stock[index])
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
              const Text('Construire un magasin',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Text(
                  'Choisissez la spécialisation du magasin à construire.'),
              for (final entry in const <String, String>{
                'restaurant': 'Restaurant',
                'home': 'Magasin du foyer',
                'equipment': 'Magasin d’équipement',
                'wholesale': 'Grossiste',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () {
                    final result = widget.gameState
                        .prepareMarketShopConstruction(entry.key,
                            primary: true);
                    _message(result.message);
                    if (result.success) {
                      Navigator.of(sheetContext).pop();
                      _showMarketShopConstructionSheet();
                    }
                  },
                ),
            ]),
          ),
        ),
      );

  Future<void> _editMarketShopSlot(String shopId) async {
    final stock = widget.gameState.marketStockForShop(shopId);
    if (stock == null) return;
    final resources = widget.gameState.marketTransferableItemsForShop(shopId);
    final matrices = widget.gameState.nurseryMarketMatricesForShop(shopId);
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
                    resource.startsWith('Capsule P’TIBUG ') ||
                            resource.startsWith('Matrice ')
                        ? 'Nurserie : ${widget.gameState.nurseryMarketInventoryAmount(resource)}'
                        : 'Maison : ${widget.gameState.resourceAmount(resource)}',
                  ),
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
            if (matrices.isNotEmpty) ...<Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: Text('Matrices d’aspect',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              ...matrices.map((matrix) => ListTile(
                    leading: const Icon(Icons.auto_awesome_motion_outlined),
                    title: Text(
                      'Matrice ${pTibugConfig.species[matrix.species]!.displayName} · ${matrix.sourceDisplayName}',
                    ),
                    subtitle: const Text('Objet unique · Nurserie'),
                    trailing: TextButton(
                      onPressed: () {
                        final result =
                            widget.gameState.transferNurseryMatrixToMarketShop(
                          shopId,
                          matrix.id,
                        );
                        _message(result.message);
                        if (result.success) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: const Text('Ajouter'),
                    ),
                  )),
            ],
            if (widget.gameState
                .nurseryMarketCapsulesForShop(shopId)
                .isNotEmpty) ...<Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: Text('Capsules P’TIBUG',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              ...widget.gameState
                  .nurseryMarketCapsulesForShop(shopId)
                  .map((capsule) => ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          'Capsule ${pTibugConfig.species[capsule.species]!.displayName} · ${capsule.displayName}',
                        ),
                        subtitle:
                            Text('Niveau ${capsule.level} · objet unique'),
                        trailing: TextButton(
                          onPressed: () {
                            final result = widget.gameState
                                .transferNurseryCapsuleToMarketShop(
                              shopId,
                              capsule.id,
                            );
                            _message(result.message);
                            if (result.success) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: const Text('Ajouter'),
                        ),
                      )),
            ],
            if (stock.isNotEmpty) const Divider(),
            ...stock.map((stack) => ListTile(
                  title: Text(
                      '${stack.amount} ${widget.gameState.marketInventoryDisplayLabel(stack)}'),
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

  Future<void> _showMarketShopConstructionSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final order = widget.gameState.marketShopConstructionOrder;
          if (order == null) return const SizedBox.shrink();
          final title = order.targetShopId != null
              ? 'Améliorer le magasin'
              : order.isPrimary
                  ? 'Construire la boutique principale'
                  : 'Construire un magasin';
          final ready = widget.gameState.isMarketShopConstructionReady;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Type : ${order.specialization}'),
                const SizedBox(height: 14),
                ...order.requirements.entries
                    .map((entry) => _ConstructionMaterialProgress(
                          resource: entry.key,
                          deposited: order.deposits[entry.key] ?? 0,
                          required: entry.value,
                          enabled: !order.isInProgress,
                          onDeposit: (amount) {
                            final result = widget.gameState
                                .depositMarketShopConstruction(
                                    entry.key, amount);
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                          onWithdraw: () {
                            final result = widget.gameState
                                .withdrawMarketShopConstruction(entry.key);
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                        )),
                _ConstructionMaterialProgress(
                  resource: 'Bio-batteries',
                  deposited: order.depositedBioBatteries,
                  required: order.requiredBioBatteries,
                  enabled: !order.isInProgress,
                  onDeposit: (amount) {
                    final result = widget.gameState
                        .depositMarketShopConstructionBatteries(amount);
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                  onWithdraw: () {
                    final result = widget.gameState
                        .withdrawMarketShopConstructionBatteries();
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                ),
                FilledButton.icon(
                  onPressed: !order.isInProgress && ready
                      ? () {
                          final result =
                              widget.gameState.startMarketShopConstruction();
                          _message(result.message);
                          if (result.success) setSheetState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.construction_outlined),
                  label: Text(order.isInProgress
                      ? 'Travaux en cours'
                      : 'Commencer les travaux'),
                ),
                TextButton.icon(
                  onPressed: () {
                    final result =
                        widget.gameState.cancelMarketShopConstruction();
                    _message(result.message);
                    if (result.success) Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Arrêter le chantier et tout récupérer'),
                ),
                TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Fermer')),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDistributorBuildSheet(String shopId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
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
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ...marketConfig.distributorConstructionCost.entries
                    .map((entry) => _ConstructionMaterialProgress(
                          resource: entry.key,
                          deposited:
                              distributor.constructionDeposits[entry.key] ?? 0,
                          required: entry.value,
                          enabled: distributor.constructionStartedAt == null,
                          onDeposit: (amount) {
                            final result = widget.gameState
                                .depositMarketDistributorMaterial(
                                    entry.key, amount,
                                    shopId: shopId);
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                          onWithdraw: () {
                            final result = widget.gameState
                                .withdrawMarketDistributorConstructionMaterial(
                                    entry.key,
                                    shopId: shopId);
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                        )),
                _ConstructionMaterialProgress(
                  resource: 'Bio-batteries',
                  deposited:
                      distributor.constructionDeposits['Bio-batteries'] ?? 0,
                  required: marketConfig.distributorConstructionBioBatteries,
                  enabled: distributor.constructionStartedAt == null,
                  onDeposit: (amount) {
                    final result = widget.gameState
                        .depositMarketDistributorBioBatteries(amount,
                            shopId: shopId);
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                  onWithdraw: () {
                    final result = widget.gameState
                        .withdrawMarketDistributorConstructionMaterial(
                            'Bio-batteries',
                            shopId: shopId);
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                ),
                FilledButton(
                  onPressed: ready
                      ? () {
                          final result = widget.gameState
                              .startMarketDistributorConstruction(
                                  shopId: shopId);
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
      ),
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
                'wholesale': 'Grossiste',
              }.entries)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(entry.value),
                  onTap: () {
                    final result = widget.gameState
                        .prepareMarketShopConstruction(entry.key,
                            primary: false);
                    _message(result.message);
                    if (result.success) {
                      Navigator.of(sheetContext).pop();
                      _showMarketShopConstructionSheet();
                    }
                  },
                ),
              if (widget.gameState.marketLevel >= 4)
                ListTile(
                  leading: const Icon(Icons.pets_outlined),
                  title: const Text('Magasin P’TIBUG'),
                  subtitle: const Text(
                      'P’TIBUG certifiés et Capsules P’TIBUG uniquement.'),
                  onTap: () {
                    final result = widget.gameState
                        .prepareMarketShopConstruction('ptibug',
                            primary: false);
                    _message(result.message);
                    if (result.success) {
                      Navigator.of(sheetContext).pop();
                      _showMarketShopConstructionSheet();
                    }
                  },
                ),
            ]),
          ),
        ),
      );

  Widget _marketRequestBook() {
    final entries = widget.gameState.marketRequestLog.reversed.toList();
    final uncovered = widget.gameState.residentUncoveredNeeds
        .where((need) => need.resolvedAt == null)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Livre des demandes',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
                'Les besoins habitants restent distincts des contrats du Sourcier et ne demandent que des produits finis.'),
            if (uncovered.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('Besoins non couverts',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              ...uncovered.take(8).map((need) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.priority_high_outlined),
                    title: Text('${need.quantity} ${need.itemDefinitionId}'),
                    subtitle: Text(
                        '${need.category} · ${need.reason.name} · habitant ${need.residentId}'),
                  )),
            ],
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
                  '${entry.status == MarketRequestStatus.completed ? ' · ${entry.responder?.label ?? 'Vente'}${entry.responderDisplayName == null ? '' : ' : ${entry.responderDisplayName}'} · gain +${entry.rewardBioBatteries} bio-pile(s) 🟡' : ''}',
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

  Widget _savedMerchantOffersDropdown() => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.bookmark_added_outlined),
          title: const Text('Offres conservées par l’Assistant'),
          subtitle: Text(
              '${widget.gameState.savedMerchantOffers.length} offre(s) du Sourcier en attente'),
          children: widget.gameState.savedMerchantOffers.map((offer) {
            final quantity = offer.kind == MerchantOfferKind.workshopItem
                ? math.max(1, offer.remainingItemAmount)
                : 1;
            final title = offer.itemName ?? offer.planName;
            final price = offer.priceForQuantity(quantity);
            return ListTile(
              title: Text(title),
              subtitle: Text(
                  '${quantity > 1 ? '$quantity unités · ' : ''}$price Bio-batteries'),
              trailing: FilledButton(
                onPressed: () => _message(widget.gameState
                    .buyMerchantOffer(offer, quantity: quantity)
                    .message),
                child: Text(quantity > 1 ? 'Acheter $quantity' : 'Acheter'),
              ),
            );
          }).toList(growable: false),
        ),
      );

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
                        'Valeur certifiée de base : ${contract.rewardBioBatteries} bio-batterie(s)'),
                    Text(
                        'Bonus de confiance : ${widget.gameState.sourcierConfidence}/100 · paiement prévu ${(contract.rewardBioBatteries * widget.gameState.sourcierConfidencePaymentMultiplier).floor()}'),
                    Text(
                        'À fournir depuis : ${contract.requestedItems.keys.map(widget.gameState.sourcierRequiredShopLabel).toSet().join(' · ')}'),
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
  const _MarketStockSlot({
    required this.stack,
    required this.onTap,
    this.label,
  });

  final Zone0InventoryStack? stack;
  final VoidCallback onTap;
  final String? label;

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
                  label ?? stack!.resource,
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
    this.initialTabIndex = 0,
    this.initialPTibugDetailId,
  });
  final Zone0GameState gameState;
  final int campHeartLevel;
  final CampHeartState campHeartState;
  final int initialTabIndex;
  final String? initialPTibugDetailId;

  @override
  State<PTibugNurseryPage> createState() => _PTibugNurseryPageState();
}

enum _CollectionMotifFilter { all, withMotif, withoutMotif }

class _PTibugNurseryPageState extends State<PTibugNurseryPage> {
  Timer? _timer;
  bool _starterChoiceDialogVisible = false;
  bool _initialDetailShown = false;
  bool _collectionLevelDescending = false;
  final Set<PTibugSpecies> _collectionSpecies = <PTibugSpecies>{};
  String? _collectionColor;
  String? _collectionAnimation;
  _CollectionMotifFilter _collectionMotif = _CollectionMotifFilter.all;

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
      _showInitialPTibugDetail();
    });
  }

  void _showInitialPTibugDetail() {
    if (_initialDetailShown || !mounted) return;
    final id = widget.initialPTibugDetailId;
    if (id == null) return;
    final bug =
        widget.gameState.pTibugs.where((item) => item.id == id).firstOrNull;
    if (bug == null) return;
    _initialDetailShown = true;
    _showPTibugLoadout(bug);
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

  /// Les dépôts et remplissages mettent déjà la jauge à jour en direct : ils
  /// ne doivent pas encombrer le bas d'écran. Une notification reste visible
  /// lorsqu'un manque de ressources empêche réellement l'action.
  void _message(String message) {
    final normalized = message.toLowerCase();
    final isResourceFailure = normalized.contains('insuffisant') ||
        normalized.contains('manque') ||
        normalized.contains('aucune ressource') ||
        normalized.contains('pas assez');
    if (!isResourceFailure) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nurserie P’TIBUG'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Filtres de collection',
              icon: const Icon(Icons.filter_list_outlined),
              onPressed: _showCollectionFilters,
            ),
            IconButton(
              tooltip: 'Inventaire de la Nurserie',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: _showNurseryObjectInventory,
            ),
          ],
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
                const SizedBox(height: 6),
                _PTibugTerritoryStockSummary(
                  gameState: widget.gameState,
                  building: nursery,
                  consumption: consumption,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                      onPressed: () => _showNurseryTransfer(nursery),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Alimenter')),
                  OutlinedButton.icon(
                    onPressed: widget.gameState.bioBatteries <= 0
                        ? null
                        : () => _message(widget.gameState
                            .openBioBatteryForPTibugTerritory(nursery.id)
                            .message),
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text(
                        'Ouvrir une Bio-batterie (+${widget.gameState.energyFromBioBatteryForBuildingLevel(nursery.level)} énergie)'),
                  ),
                ]),
                const Text(
                    'Chaque P’TIBUG conserve sa production jusqu’à sa récolte.'),
              ],
            ),
          ),
        ),
        ...widget.gameState.pTibugArmatures
            .where((item) => item.isCrafting)
            .map(_armatureInProgressCard),
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

  Future<void> _showNurseryObjectInventory() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final capsules = widget.gameState.nurseryInventoryCapsules;
          final matrices = widget.gameState.nurseryInventoryMatrices;
          var sortBySpecies = true;
          return StatefulBuilder(builder: (context, setSheetState) {
            final sorted = List<PTibugAspectMatrix>.from(matrices)
              ..sort((a, b) => sortBySpecies
                  ? a.species.name.compareTo(b.species.name)
                  : (a.primaryColorHex ?? '')
                      .compareTo(b.primaryColorHex ?? ''));
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: <Widget>[
                  const Text('Inventaire de la Nurserie',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const Text('Capsules P’TIBUG et Matrices uniquement'),
                  const SizedBox(height: 12),
                  if (capsules.isNotEmpty) ...<Widget>[
                    const Text('Capsules P’TIBUG',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    ...capsules.map((capsule) => ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title:
                              Text('Capsule P’TIBUG · ${capsule.displayName}'),
                          subtitle: Text(
                              '${pTibugConfig.species[capsule.species]!.displayName} · niveau ${capsule.level}'),
                        )),
                  ],
                  if (matrices.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Row(children: <Widget>[
                      const Expanded(
                        child: Text('Matrices d’aspect',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      ChoiceChip(
                        label: Text(sortBySpecies ? 'Espèce' : 'Couleur'),
                        selected: true,
                        onSelected: (_) =>
                            setSheetState(() => sortBySpecies = !sortBySpecies),
                      ),
                    ]),
                    ...sorted.map(
                        (matrix) => _AspectMatrixPresentation(matrix: matrix)),
                  ],
                  if (capsules.isEmpty && matrices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Aucune Capsule ni Matrice disponible.'),
                    ),
                ],
              ),
            );
          });
        },
      );

  Widget _aspectMatrixExtractorCard() {
    final state = widget.gameState;
    final config = pTibugConfig.aspectMatrixExtractor;
    final level = state.aspectMatrixExtractorLevel;
    final modules = config.moduleCountFor(level);
    final matrices = config.matricesFor(level);
    final active = state.activeAspectMatrixExtraction;
    final nursery = state.plaineNurseryTerritory;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Extracteur de matrice d’aspect · niv. $level',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const Text(
                'Le niveau suit les quatre premiers niveaux de la Nurserie.'),
            Text(
                '$modules module(s) · ${matrices.join(' + ')} Matrice(s) · ${config.durationFor(level)} min'),
            Text(
                'Coût par module : ${config.mineralCostPerModule} Minéral · ${config.organicCostPerModule} Organique · ${config.nurseryEnergyCostPerModule} Énergies de la Nurserie.'),
            if (active != null)
              Text(
                'Extraction de ${active.sourceDisplayName} : ${active.matrixCount} Matrice(s) prêtes dans ${_countdownLabel(active.endsAt)}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              FilledButton.icon(
                onPressed:
                    nursery.isBuilt ? _choosePTibugForAspectExtraction : null,
                icon: const Icon(Icons.auto_awesome_motion_outlined),
                label: const Text('Extraire une Matrice'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _aspectMatrixInventory() {
    final matrices = widget.gameState.pTibugAspectMatrices;
    return ExpansionTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: const Text('Inventaire de Matrices'),
      subtitle: Text('${matrices.length} Matrice(s) d’aspect'),
      children: <Widget>[
        if (matrices.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Les Matrices extraites servent à la Cultivation et peuvent aussi être déposées au Magasin P’TIBUG pour les contrats du Sourcier.',
            ),
          ),
        ...matrices.map((matrix) => _AspectMatrixPresentation(
              matrix: matrix,
              onTap: () => _showAspectMatrixDetails(matrix),
            )),
      ],
    );
  }

  PTibug? _sourceForAspectMatrix(PTibugAspectMatrix matrix) =>
      widget.gameState.pTibugs
          .where((bug) => bug.id == matrix.sourcePTibugId)
          .firstOrNull;

  Widget _aspectColorBadge(String? colorHex, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _pTibugColorFromHex(colorHex),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _aspectIconBadge(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Future<void> _showAspectMatrixDetails(PTibugAspectMatrix matrix) async {
    final source = _sourceForAspectMatrix(matrix);
    final primary = matrix.primaryColorHex ?? source?.primaryColorHex;
    final motif = matrix.motifId ?? source?.motifId;
    final motifColor = matrix.motifColorHex ?? source?.motifColorHex;
    final animation = matrix.animationName ?? source?.animationName;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: _pTibugColorFromHex(primary),
                    child: Icon(
                      _speciesIcon(matrix.species),
                      color: primary?.toUpperCase() == '#1E1E1E'
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Matrice ${pTibugConfig.species[matrix.species]!.displayName}',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Ancien P’TIBUG : ${matrix.sourceDisplayName}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 10,
                children: <Widget>[
                  _aspectColorBadge(
                    primary,
                    'Couleur principale : ${widget.gameState.pTibugColorNameFor(primary)}',
                  ),
                  if (motif != null)
                    _aspectIconBadge(
                      _pTibugMotifIcon(motif),
                      'Motif : $motif',
                    ),
                  if (motif != null)
                    _aspectColorBadge(
                      motifColor,
                      'Couleur du motif : ${widget.gameState.pTibugColorNameFor(motifColor)}',
                    ),
                  if (animation != null)
                    _aspectIconBadge(
                      _pTibugAnimationIcon(animation),
                      'Animation : $animation',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Cette Matrice conserve l’aspect de son P’TIBUG source. Elle peut être utilisée par la Cultivation ou déposée au Magasin P’TIBUG pour les contrats du Sourcier.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePTibugForAspectExtraction() async {
    final source = await showModalBottomSheet<PTibug>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(title: Text('P’TIBUG source à conserver')),
            ...widget.gameState.pTibugs
                .where((bug) => !widget.gameState.isPTibugInCultivation(bug))
                .map((bug) => ListTile(
                      leading: Icon(_speciesIcon(bug.species),
                          color: _pTibugPrimaryColor(bug)),
                      title: Text(bug.displayName),
                      subtitle:
                          Text(widget.gameState.pTibugAppearanceLabelFor(bug)),
                      onTap: () => Navigator.of(sheetContext).pop(bug),
                    )),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    _message(widget.gameState.startPTibugAspectExtraction(source).message);
  }

  Future<void> _chooseAspectMatricesForCultivation(
    PTibugArmature armature,
    String tankId,
  ) async {
    final eligible = widget.gameState.pTibugAspectMatrices
        .where((matrix) => matrix.species == armature.species)
        .toList(growable: false);
    final selected = await showDialog<List<String>?>(
      context: context,
      builder: (dialogContext) => _CultivationMatrixSelectionDialog(
        matrices: eligible,
      ),
    );
    if (selected == null || !mounted) return;
    _message(widget.gameState
        .startPTibugCultivation(
          armatureId: armature.id,
          tankId: tankId,
          aspectMatrixIds: selected,
        )
        .message);
  }

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

  Widget _armatureInProgressCard(PTibugArmature order) {
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
                    radius: 28,
                    backgroundColor:
                        _pTibugPrimaryColor(bug).withValues(alpha: .18),
                    child: Icon(
                      _speciesIcon(bug.species),
                      color: _pTibugPrimaryColor(bug),
                    ),
                  ),
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
                    Text(widget.gameState.pTibugIdentityLabelFor(bug)),
                    Text(
                      'Aspect : ${widget.gameState.pTibugAppearanceLabelFor(bug)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Armatures P’TIBUG',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text(
                      'Les Patterns sont gérés par le Kernel et les Armatures se fabriquent désormais à l’Atelier.'),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FablabPage(
                          gameState: widget.gameState,
                          campHeartLevel: widget.campHeartLevel,
                          initialTabIndex: 1,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.precision_manufacturing_outlined),
                    label: const Text(
                        'Fabriquer une Armature P’TIBUG dans l’Atelier'),
                  ),
                ],
              ),
            ),
          ),
          _aspectMatrixExtractorCard(),
          const SizedBox(height: 12),
          _aspectMatrixInventory(),
          const SizedBox(height: 18),
          ExpansionTile(
            leading: const Icon(Icons.precision_manufacturing_outlined),
            title: const Text('Armatures disponibles'),
            children: <Widget>[
              if (!widget.gameState.pTibugArmatures
                  .any((item) => item.isCompleted))
                const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                        'Une Armature terminée pourra être placée dans une cuve.')),
              ...widget.gameState.pTibugArmatures
                  .where((item) => item.isCompleted)
                  .map((armature) {
                final cultivationInProgress = widget
                    .gameState.pTibugCultivationOperations
                    .any((operation) =>
                        operation.armatureId == armature.id &&
                        operation.status !=
                            PTibugCultivationOperationStatus.cancelled);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        child: Icon(_speciesIcon(armature.species))),
                    title: Text(
                        '${pTibugConfig.species[armature.species]!.displayName} · Armature prête'),
                    subtitle: Text(
                        'Fabriquée le ${armature.createdAt.day}/${armature.createdAt.month}'),
                    trailing: cultivationInProgress
                        ? const OutlinedButton(
                            onPressed: null,
                            child: Text('En cours de cultivation'),
                          )
                        : PopupMenuButton<String>(
                            onSelected: (tankId) =>
                                _chooseAspectMatricesForCultivation(
                                    armature, tankId),
                            itemBuilder: (_) => widget
                                .gameState.builtCultivationTanks
                                .where(
                                    (tank) => tank.currentOperationId == null)
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
                );
              }),
            ],
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Cuves de Cultivation'),
            children: <Widget>[
              const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                      'Chaque cuve consomme 1 Énergie de la Nurserie par heure. Les réserves de matériaux restent locales à la cuve.')),
              ...List<Widget>.generate(
                  widget.gameState.cultivationTankSlotCount, (index) {
                final tank =
                    widget.gameState.cultivationTankForId('ptibug-tank-$index');
                return tank == null
                    ? const SizedBox.shrink()
                    : _cultivationTankCard(tank);
              }),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Cuves d’amélioration'),
            subtitle: Text(
              '${widget.gameState.improvementTankSlotCount}/3 disponible(s) · amélioration de Module et brisure de symbiose.',
            ),
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Coûts : amélioration 20 Organique · 10 Mycélium · 2 h. Brisure : 10 Organique · 3 h.',
                ),
              ),
              ...List<Widget>.generate(
                widget.gameState.improvementTankSlotCount,
                (index) {
                  final operation = widget.gameState.pTibugModuleVatOperations
                      .where((item) => item.isActive)
                      .elementAtOrNull(index);
                  return ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text('Cuve d’amélioration ${index + 1}'),
                    subtitle: operation == null
                        ? const Text('Disponible')
                        : Text(
                            '${operation.kind == PTibugModuleVatOperationKind.symbiosis ? 'Symbiose' : 'Brisure de symbiose'} · fin dans ${_countdownLabel(operation.endsAt)}',
                          ),
                  );
                },
              ),
              if (widget.gameState.improvementTankSlotCount == 0)
                const ListTile(
                  title: Text('Construisez la Salle d’incubation au FabLab.'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Mise en Capsule'),
            subtitle: const Text('1 Bio-batterie · 10 Minéral'),
            children: widget.gameState.pTibugs
                .where((bug) => !widget.gameState.isPTibugInCultivation(bug))
                .map((bug) => ListTile(
                      title: Text(bug.displayName),
                      subtitle: Text(
                          '${widget.gameState.pTibugIdentityLabelFor(bug)} · niv. ${bug.level}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPTibugCapsuleSheet(bug, context),
                    ))
                .toList(),
          ),
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showCultivationTankConstructionSheet(tank),
                icon: const Icon(Icons.construction_outlined),
                label: Text(constructReady
                    ? 'Commencer les travaux'
                    : 'Préparer la construction'),
              ),
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
                  'Organique : ${tank.organicStored.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Organique').toStringAsFixed(1)} h) · Minéral : ${tank.mineralStored.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Minéral').toStringAsFixed(1)} h) · Énergie Nurserie : ${widget.gameState.plaineNurseryTerritory.localEnergy.toStringAsFixed(1)} (${widget.gameState.cultivationTankAutonomyHours(tank, 'Énergie').toStringAsFixed(1)} h)'),
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
                if (operation.status == PTibugCultivationOperationStatus.active)
                  FilledButton(
                      onPressed: () =>
                          _showCultivationRhythmTap(tank, operation),
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

  Future<void> _showCultivationRhythmTap(
    PTibugCultivationTank tank,
    PTibugCultivationOperation operation,
  ) async {
    final patternIndex = (operation.tapSessions.length + tank.slotIndex) %
        _rhythmTapPatterns.length;
    await showDialog<void>(
      context: context,
      builder: (_) => _RhythmTapDialog(
        tapCount: _rhythmTapPatterns[patternIndex].length,
        title: 'Tapoter la cuve en rythme',
        onValidated: () => _message(
          widget.gameState.applyCultivationTap(tank.id).message,
        ),
      ),
    );
  }

  Future<void> _showCultivationTankConstructionSheet(
      PTibugCultivationTank tank) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final config = pTibugConfig.cultivation;
          final ready = widget.gameState.cultivationTankConstructionReady(tank);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
                Text('Construire la cuve ${tank.slotIndex + 1}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                ...config.tankConstructionCost.entries
                    .map((entry) => _ConstructionMaterialProgress(
                          resource: entry.key,
                          deposited: tank.constructionDeposits[entry.key] ?? 0,
                          required: entry.value,
                          enabled: tank.status !=
                              PTibugCultivationTankStatus.underConstruction,
                          onDeposit: (amount) {
                            final result = widget.gameState
                                .depositCultivationTankConstruction(
                                    tankId: tank.id,
                                    resources: <String, int>{
                                  entry.key: amount
                                });
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                          onWithdraw: () {
                            final result = widget.gameState
                                .withdrawCultivationTankConstruction(
                                    tankId: tank.id, resource: entry.key);
                            _message(result.message);
                            if (result.success) setSheetState(() {});
                          },
                        )),
                _ConstructionMaterialProgress(
                  resource: 'Bio-batteries',
                  deposited: tank.constructionDeposits['Bio-batteries'] ?? 0,
                  required: config.tankConstructionBioBatteries,
                  enabled: tank.status !=
                      PTibugCultivationTankStatus.underConstruction,
                  onDeposit: (amount) {
                    final result = widget.gameState
                        .depositCultivationTankConstruction(
                            tankId: tank.id,
                            resources: const <String, int>{},
                            bioBatteriesAmount: amount);
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                  onWithdraw: () {
                    final result = widget.gameState
                        .withdrawCultivationTankConstruction(
                            tankId: tank.id, resource: 'Bio-batteries');
                    _message(result.message);
                    if (result.success) setSheetState(() {});
                  },
                ),
                FilledButton.icon(
                  onPressed: ready
                      ? () {
                          final result = widget.gameState
                              .startCultivationTankConstruction(tank.id);
                          _message(result.message);
                          if (result.success) setSheetState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.construction_outlined),
                  label: Text(tank.status ==
                          PTibugCultivationTankStatus.underConstruction
                      ? 'Travaux en cours'
                      : 'Commencer les travaux'),
                ),
                TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Fermer')),
              ],
            ),
          );
        },
      ),
    );
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('P’TIBUG sorti de la cuve'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    color: _pTibugPrimaryColor(bug).withValues(alpha: .20),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: _pTibugPrimaryColor(bug), width: 3),
                  ),
                  child: Stack(alignment: Alignment.center, children: <Widget>[
                    Icon(_territorySpeciesIcon(bug.species),
                        size: 52, color: _pTibugPrimaryColor(bug)),
                    if (bug.motifId != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Icon(_pTibugMotifIcon(bug.motifId),
                            size: 22,
                            color: _pTibugColorFromHex(bug.motifColorHex,
                                fallback: Colors.white)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Avant de le nommer, voici son apparence :'),
              const SizedBox(height: 8),
              _ptibugAppearanceLine(
                color: _pTibugPrimaryColor(bug),
                label: 'Couleur',
                value: widget.gameState.pTibugColorNameFor(bug.primaryColorHex),
              ),
              _ptibugAppearanceLine(
                color: _pTibugColorFromHex(bug.motifColorHex,
                    fallback: const Color(0xff807A68)),
                label: 'Motif',
                value:
                    '${bug.motifId ?? 'Aucun'}${bug.motifColorHex == null ? '' : ' · ${widget.gameState.pTibugColorNameFor(bug.motifColorHex)}'}',
              ),
              _ptibugAppearanceLine(
                icon: _pTibugAnimationIcon(bug.animationName),
                label: 'Animation',
                value: bug.animationName ?? 'Aucune',
              ),
              _ptibugAppearanceLine(
                color: _pTibugColorFromHex(bug.traitColorHex,
                    fallback: const Color(0xff807A68)),
                label: 'Trait visuel',
                value: bug.traitColorHex == null
                    ? 'Aucun'
                    : widget.gameState.pTibugColorNameFor(bug.traitColorHex),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Le nommer')),
        ],
      ),
    );
    if (!mounted) return;
    await _renamePTibug(bug, context, requiredForNewPTibug: true);
  }

  Widget _ptibugAppearanceLine({
    Color? color,
    IconData? icon,
    required String label,
    required String value,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color?.withValues(alpha: .2),
              shape: BoxShape.circle,
              border: Border.all(color: color ?? const Color(0xff807A68)),
            ),
            child: icon == null ? null : Icon(icon, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('$label : $value')),
        ]),
      );

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

  Widget _collection() {
    final all = List<PTibug>.from(widget.gameState.pTibugs);
    final bugs = all.where((bug) {
      final hasMotif = bug.motifId != null &&
          bug.motifId!.isNotEmpty &&
          bug.motifId!.toLowerCase() != 'aucun';
      return (_collectionSpecies.isEmpty ||
              _collectionSpecies.contains(bug.species)) &&
          (_collectionColor == null ||
              bug.primaryColorHex == _collectionColor) &&
          (_collectionAnimation == null ||
              bug.animationName == _collectionAnimation) &&
          (_collectionMotif == _CollectionMotifFilter.all ||
              (_collectionMotif == _CollectionMotifFilter.withMotif &&
                  hasMotif) ||
              (_collectionMotif == _CollectionMotifFilter.withoutMotif &&
                  !hasMotif));
    }).toList()
      ..sort((a, b) => _collectionLevelDescending
          ? b.level.compareTo(a.level)
          : a.level.compareTo(b.level));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('Collection', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('Tape un P’TIBUG pour consulter et ajuster son équipement.'),
        const SizedBox(height: 10),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Aucun P’TIBUG créé pour le moment.'),
          ),
        if (all.isNotEmpty && bugs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Aucun P’TIBUG ne correspond aux filtres.'),
          ),
        ...bugs.map(
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
                        CircleAvatar(
                          backgroundColor:
                              _pTibugPrimaryColor(bug).withValues(alpha: .18),
                          child: Icon(_speciesIcon(bug.species),
                              color: _pTibugPrimaryColor(bug)),
                        ),
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
                      widget.gameState.pTibugIdentityLabelFor(bug),
                    ),
                    Text(
                        'Aspect : ${widget.gameState.pTibugAppearanceLabelFor(bug)}'),
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
                    if (bug.isRenewed && bug.secondTraitId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          '✨ Niveau atteint : ce P’TIBUG peut recevoir un second Trait.',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    else if (bug.level >= 3 &&
                        bug.biologicalTraitLevel >= 3 &&
                        !bug.isRenewed)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          '✨ Niveau atteint : une Évolution ouvrira un second Trait.',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
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
                              : '${widget.gameState.territoryBuildingForId(bug.assignedBuildingId)?.kind == PTibugTerritoryKind.nursery ? 'Nurserie de la Savane tropicale' : 'Refuge'} · ${bug.inactiveReason ?? (bug.nextProductionAt == null ? 'cycle en attente' : 'prochain cycle ${_countdownLabel(bug.nextProductionAt!)}')}',
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
                          ? () => _exitPTibugCultivation(bug)
                          : () => _showTerritoryAssignment(bug),
                      icon: Icon(widget.gameState.isPTibugInCultivation(bug)
                          ? Icons.logout_outlined
                          : Icons.swap_horiz_outlined),
                      label: Text(widget.gameState.isPTibugInCultivation(bug)
                          ? 'Sortir de cuve'
                          : 'Affecter'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCollectionFilters() async {
    final all = widget.gameState.pTibugs;
    final colors = all
        .map((bug) => bug.primaryColorHex)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final animations = all
        .map((bug) => bug.animationName)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .38,
        maxChildSize: .92,
        builder: (_, controller) => StatefulBuilder(
          builder: (_, refreshSheet) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: <Widget>[
              const Text('Filtres de collection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              FilterChip(
                label: Text(_collectionLevelDescending
                    ? 'Niveau décroissant'
                    : 'Niveau croissant'),
                selected: true,
                onSelected: (_) {
                  setState(() =>
                      _collectionLevelDescending = !_collectionLevelDescending);
                  refreshSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              const Text('Espèces',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: PTibugSpecies.values
                    .map((species) => FilterChip(
                          label:
                              Text(pTibugConfig.species[species]!.displayName),
                          selected: _collectionSpecies.contains(species),
                          onSelected: (selected) {
                            setState(() => selected
                                ? _collectionSpecies.add(species)
                                : _collectionSpecies.remove(species));
                            refreshSheet(() {});
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Text('Motif',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final entry in <(_CollectionMotifFilter, String)>[
                  (_CollectionMotifFilter.all, 'Tous motifs'),
                  (_CollectionMotifFilter.withMotif, 'Avec motif'),
                  (_CollectionMotifFilter.withoutMotif, 'Sans motif'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _collectionMotif == entry.$1,
                    onSelected: (_) {
                      setState(() => _collectionMotif = entry.$1);
                      refreshSheet(() {});
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              const Text('Couleur',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                ChoiceChip(
                  label: const Text('Toutes couleurs'),
                  selected: _collectionColor == null,
                  onSelected: (_) {
                    setState(() => _collectionColor = null);
                    refreshSheet(() {});
                  },
                ),
                ...colors.map((color) => ChoiceChip(
                      avatar: CircleAvatar(
                          radius: 7,
                          backgroundColor: _pTibugColorFromHex(color)),
                      label: Text(_matrixColorName(color)),
                      selected: _collectionColor == color,
                      onSelected: (_) {
                        setState(() => _collectionColor = color);
                        refreshSheet(() {});
                      },
                    )),
              ]),
              const SizedBox(height: 12),
              const Text('Animation',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                ChoiceChip(
                  label: const Text('Toutes animations'),
                  selected: _collectionAnimation == null,
                  onSelected: (_) {
                    setState(() => _collectionAnimation = null);
                    refreshSheet(() {});
                  },
                ),
                ...animations.map((animation) => ChoiceChip(
                      avatar: Icon(_pTibugAnimationIcon(animation), size: 16),
                      label: Text(animation),
                      selected: _collectionAnimation == animation,
                      onSelected: (_) {
                        setState(() => _collectionAnimation = animation);
                        refreshSheet(() {});
                      },
                    )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _exitPTibugCultivation(PTibug bug) {
    final operation = widget.gameState.cultivationOperationForPTibug(bug.id);
    if (operation == null) return;
    _message(
        widget.gameState.cancelPTibugCultivation(operation.tankId).message);
  }

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
                        ? 'Nurserie · Savane tropicale'
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
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Traits biologiques permanents'),
          subtitle: const Text('Infusion, maîtrise et compatibilités'),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                  'Un seul Trait peut transformer durablement chaque P’TIBUG.'),
            ),
            ...pTibugConfig.activeTraitDefinitions.map((definition) {
              final patternId = 'ptibug-trait-${definition.id}';
              final active = widget.gameState.isPTibugPatternActive(patternId);
              final progress =
                  widget.gameState.pTibugPatternProgress[patternId];
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
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
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.extension_outlined),
          title: const Text('Modules fabriqués'),
          children: <Widget>[
            if (moduleInstances.isEmpty)
              const Card(
                  child: ListTile(title: Text('Aucun Module fabriqué.'))),
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
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Capsules P’TIBUG'),
          children: <Widget>[
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
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.data_object_outlined),
          title: const Text('Données de traits'),
          subtitle: const Text('Données attribuées et fusions'),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                  'Les Données attribuées restent visibles ici. Deux Données identiques non équipées peuvent être fusionnées.'),
            ),
            if (traits.isEmpty)
              const Card(
                  child: ListTile(title: Text('Aucune Donnée disponible.'))),
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
        ),
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

  /// Depuis la fiche d'un P’TIBUG, l'action garde cette cible et ouvre
  /// directement l'inventaire des Modules disponibles : le joueur ne doit pas
  /// sélectionner le même P’TIBUG une seconde fois.
  Future<void> _pickModuleForPTibug(PTibug bug) async {
    final slotsUsed = widget.gameState.pTibugModuleInstances
        .where((item) => item.equippedPTibugId == bug.id)
        .length;
    if (slotsUsed >= widget.gameState.maxModulesPerPTibug) {
      _message('Tous les emplacements de Module sont occupés.');
      return;
    }
    final available = widget.gameState.pTibugModuleInstances
        .where((item) => !item.isEquipped)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        minChildSize: .36,
        maxChildSize: .9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: <Widget>[
            Text('Modules de ${widget.gameState.pTibugBiologicalNameFor(bug)}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(
                '$slotsUsed/${widget.gameState.maxModulesPerPTibug} emplacements occupés'),
            const SizedBox(height: 10),
            if (available.isEmpty)
              const ListTile(
                  title: Text('Aucun Module disponible dans l’inventaire.')),
            ...available.map((instance) => Card(
                  child: ListTile(
                    leading: Icon(_moduleIcon(instance.type)),
                    title: Text(
                        '${_moduleTitle(instance.type)} niveau ${instance.qualityLevel}'),
                    subtitle: Text(_moduleDescription(instance.type)),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () {
                      final result = widget.gameState.equipPTibugModuleInstance(
                        bug: bug,
                        moduleInstanceId: instance.id,
                      );
                      if (result.success) Navigator.of(sheetContext).pop();
                      _message(result.message);
                    },
                  ),
                )),
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
                  '${widget.gameState.pTibugIdentityLabelFor(bug)} · niveau ${bug.level}',
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
                        OutlinedButton.icon(
                          onPressed: () => _showPTibugCapsuleSheet(
                            bug,
                            sheetContext,
                          ),
                          icon: const Icon(Icons.inventory_2_outlined),
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
                      _pickModuleForPTibug(bug);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Équiper un Module disponible'),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'La mise en Capsule est disponible à tout moment depuis la Nurserie. Une vente reste liée à une demande ou un contrat.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _renamePTibug(
    PTibug bug,
    BuildContext sheetContext, {
    bool requiredForNewPTibug = false,
  }) async {
    final controller = TextEditingController(text: bug.displayName);
    while (mounted) {
      final name = await showDialog<String>(
        context: context,
        barrierDismissible: !requiredForNewPTibug,
        builder: (dialogContext) => PopScope(
          canPop: !requiredForNewPTibug,
          child: AlertDialog(
            title: Text(requiredForNewPTibug
                ? 'Donner un nom à ${bug.defaultDisplayName}'
                : 'Renommer ${bug.displayName}'),
            content: TextField(
              controller: controller,
              maxLength: pTibugConfig.valuation.maximumNameLength,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom personnel'),
            ),
            actions: <Widget>[
              if (!requiredForNewPTibug)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      );
      if (name == null) break;
      final result = widget.gameState.renamePTibug(bug, name);
      _message(result.message);
      if (!result.success && requiredForNewPTibug) continue;
      if (result.success && !requiredForNewPTibug && sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      break;
    }
    controller.dispose();
  }

  Future<void> _choosePTibugContractSale(
    PTibug bug,
    BuildContext sheetContext,
  ) async {
    final contract = widget.gameState.eligiblePTibugContractsFor(bug).first;
    final valuation = widget.gameState.pTibugValuationFor(bug);
    final payment = PTibugValuationService(pTibugConfig.valuation).paymentFor(
      valuation,
      sourcierContract: false,
      bonusMultiplier: widget.gameState.sourcierConfidencePaymentMultiplier,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Capsule P’TIBUG certifiée'),
        content: Text(
          '${bug.displayName} · ${widget.gameState.pTibugIdentityLabelFor(bug)} niveau ${bug.level}\n'
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

  Future<void> _showPTibugCapsuleSheet(
    PTibug bug,
    BuildContext sheetContext,
  ) async {
    final valuation = widget.gameState.pTibugValuationFor(bug);
    final blocker = widget.gameState.pTibugCertificationBlocker(bug);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text('Préparer une Capsule pour la vente',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
                '${bug.displayName} · valeur indicative ${valuation.total} Bio-batteries'),
            const Text(
                'Les Capsules sont réservées aux P’TIBUG que vous choisissez de vendre. Coût : 1 Bio-batterie · 10 Minéral.'),
            if (blocker != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(blocker,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: blocker == null
                  ? () {
                      final result = widget.gameState.encapsulatePTibug(bug);
                      Navigator.of(context).pop();
                      if (result.success && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      _message(result.message);
                    }
                  : null,
              child: const Text('Préparer la Capsule de vente'),
            ),
          ]),
        ),
      ),
    );
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
    this.initialTabIndex = 0,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      initialIndex: initialTabIndex.clamp(0, 5),
      child: Scaffold(
        appBar: AppBar(
          title: Text('FabLab · N${gameState.fablabLevel}'),
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
              Tab(text: 'Cuves', icon: Icon(Icons.science_outlined)),
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
              _FabLabCultivationVatsTab(
                gameState: gameState,
                campHeartLevel: campHeartLevel,
              ),
              _FablabUpgradeOverview(
                gameState: gameState,
                campHeartLevel: campHeartLevel,
              ),
              const _BuildingInformationTab(
                title: 'Fablab',
                description:
                    'Le FabLab est un seul bâtiment physique : sa Viabilité, ses réparations et son stockage sont communs. Cuisine, Atelier et Recycleur sont des salles internes ; leur niveau ne peut jamais dépasser celui du FabLab.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrée FabLab dédiée à la salle d'Incubation. Les opérations existantes
/// restent conservées pendant la migration, mais la progression et la
/// capacité des cuves dépendent désormais de cette salle interne.
class _FabLabCultivationVatsTab extends StatelessWidget {
  const _FabLabCultivationVatsTab({
    required this.gameState,
    required this.campHeartLevel,
  });

  final Zone0GameState gameState;
  final int campHeartLevel;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _FabLabHeader(gameState: gameState),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(children: <Widget>[
                    Icon(Icons.science_outlined),
                    SizedBox(width: 8),
                    Text('Salle d’incubation',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Niveau ${gameState.incubationRoomLevel} · ${gameState.cultivationTankSlotCount} cuve(s) de Cultivation disponibles. Deux au niveau 1, puis une supplémentaire par niveau de salle.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Inventaire d’incubation : ${gameState.incubationInventoryUsed}/${gameState.incubationInventoryCapacity}. Armatures, Matrices et Modules y sont conservés.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PTibugNurseryPage(
                          gameState: gameState,
                          campHeartLevel: campHeartLevel,
                          campHeartState: CampHeartState.placeholder(),
                          initialTabIndex: 2,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('Gérer les cuves et l’inventaire'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
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
            'Le FabLab porte la Viabilité et les réparations. Cuisine, Atelier et Recycleur sont des salles internes et ne peuvent pas dépasser son niveau.',
          ),
          const SizedBox(height: 14),
          _BuildingViabilityCard(gameState: gameState, buildingId: 'fablab'),
          const SizedBox(height: 14),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'fablab',
            title: 'FabLab',
            level: gameState.fablabLevel,
            description:
                'Bâtiment physique : stock global, Viabilité, réparations et plafond de niveau des salles.',
            nextEffect:
                'Prochain niveau : stockage FabLab ${fablabConfig.fablabStorageForLevel((gameState.fablabLevel + 1).clamp(1, 4))}.',
          ),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'cuisine',
            title: 'Cuisine',
            level: gameState.cuisineLevel,
            description:
                'Augmente les emplacements de préparation et prépare les recettes futures.',
            nextEffect: gameState.cuisineLevel >= gameState.fablabLevel
                ? 'FabLab N${gameState.fablabLevel + 1} requis.'
                : 'Prochain niveau : ${gameState.kitchenSlots + 1} poste(s) P’TIPOTE.',
            enabled: gameState.canUpgradeFabLabRoom(FabLabRoom.kitchen),
          ),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'atelier',
            title: 'Atelier',
            level: gameState.atelierLevel,
            description:
                'Augmente les postes, recettes et capacité de liste de production.',
            nextEffect: gameState.atelierLevel >= gameState.fablabLevel
                ? 'FabLab N${gameState.fablabLevel + 1} requis.'
                : 'Prochain niveau : ${gameState.workshopSlots + 1} poste(s) P’TIPOTE.',
            enabled: gameState.canUpgradeFabLabRoom(FabLabRoom.workshop),
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
                campHeartLevel >= fablabConfig.recyclerUnlockCampHeartLevel &&
                    gameState.canUpgradeFabLabRoom(FabLabRoom.recycler),
          ),
          _FablabUnitUpgradeCard(
            gameState: gameState,
            targetId: 'incubation',
            title: 'Salle d’incubation',
            level: gameState.incubationRoomLevel,
            description:
                'Accueille les cuves de Cultivation et d’amélioration, ainsi que leur inventaire dédié.',
            nextEffect: gameState.incubationRoomLevel >= gameState.fablabLevel
                ? 'FabLab N${gameState.fablabLevel + 1} requis.'
                : 'Prochain niveau : davantage de cuves et de stockage.',
            enabled: gameState.canUpgradeFabLabRoom(FabLabRoom.incubation),
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

class _FabLabHeader extends StatelessWidget {
  const _FabLabHeader({required this.gameState});
  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final viability = gameState.viabilityForBuilding('fablab');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('FabLab · niveau ${gameState.fablabLevel}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                  'Viabilité : ${viability.current}/${viability.maximum}% · Stock : ${gameState.inventoryUsedAmount}/${gameState.globalStockCapacity}'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: viability.current / viability.maximum),
              const SizedBox(height: 4),
              Text(
                  'Maison ${gameState.houseStorageCapacity} + FabLab ${gameState.fabLabStorageCapacity}${gameState.isLogisticsBuilt ? ' + Logistique ${gameState.logisticsStorageCapacity}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
      ),
    );
  }
}

class _FabLabPermanentPosts extends StatelessWidget {
  const _FabLabPermanentPosts({
    required this.gameState,
    required this.room,
    required this.figurines,
  });
  final Zone0GameState gameState;
  final FabLabRoom room;
  final List<PtipoteFigurine> figurines;

  @override
  Widget build(BuildContext context) {
    final state = gameState.fabLabRoom(room);
    final capacity = room == FabLabRoom.recycler
        ? 0
        : fablabConfig.roomWorkersFor(room, state.level);
    final names = <String, PtipoteFigurine>{
      for (final item in figurines) item.id: item
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Postes P’TIPOTE',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              if (capacity == 0)
                const Text(
                    'Construisez ou améliorez cette salle pour ouvrir les postes permanents.')
              else ...<Widget>[
                ...List<Widget>.generate(capacity, (index) {
                  final ids = state.permanentWorkerIds.toList(growable: false);
                  final id = index < ids.length ? ids[index] : null;
                  final figurine = id == null ? null : names[id];
                  return ListTile(
                    dense: true,
                    leading: Icon(figurine == null
                        ? Icons.person_outline
                        : Icons.pets_outlined),
                    title: Text(figurine?.displayName ?? 'Poste libre'),
                    subtitle: Text(figurine == null
                        ? 'Aucun P’TIPOTE assigné'
                        : 'En attente dans la salle'),
                    trailing: figurine == null
                        ? null
                        : TextButton(
                            onPressed: () => gameState
                                .removePermanentFabLabWorker(room, id!),
                            child: const Text('Rentrer'),
                          ),
                  );
                }),
                if (state.permanentWorkerIds.length < capacity)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await _pickPtipoteForActivity(
                        context: context,
                        gameState: gameState,
                        figurines: figurines,
                        title:
                            'Affecter à ${room == FabLabRoom.kitchen ? 'la Cuisine' : 'l’Atelier'}',
                      );
                      if (selected != null && context.mounted) {
                        final result = gameState.assignPermanentFabLabWorker(
                            room, selected);
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)));
                      }
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Affecter'),
                  ),
              ],
            ]),
      ),
    );
  }
}

class _FablabEnergyCard extends StatelessWidget {
  const _FablabEnergyCard({required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final energyPerBattery = gameState.energyFromBioBatteryForBuildingLevel(
      gameState.fablabLevel,
    );
    final capacity = math.max(
      energyPerBattery,
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
                'Ouvrir 1 bio-batterie (+$energyPerBattery énergie)',
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
    required this.level,
    required this.room,
    required this.onChanged,
  });

  final int quantity;
  final int level;
  final FabLabRoom room;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        segments: fablabConfig
            .quantitiesFor(room, level)
            .map((value) => ButtonSegment(value: value, label: Text('x$value')))
            .toList(),
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

  static void _showAction(BuildContext context, Zone0ActionResult result) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

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
        _FabLabHeader(gameState: gameState),
        const SizedBox(height: 12),
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
                const SizedBox(height: 6),
                const Text(
                    'Sorties : Organique et Minéral uniquement. Sans module, la répartition est aléatoire 50 / 50.'),
                const SizedBox(height: 8),
                ...List<Widget>.generate(2, (vatIndex) {
                  final capacity = fablabConfig.recyclerVatCapacityFor(
                      vatIndex, gameState.recyclerLevel);
                  if (capacity <= 0) return const SizedBox.shrink();
                  final vat = gameState.fabLab.recyclerVats[vatIndex];
                  final enabled = fablabConfig.recyclerVatSupportsModule(
                      vatIndex, gameState.recyclerLevel);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                              'Cuve ${vatIndex + 1} · ${vat.storedWaste}/$capacity'),
                          if (enabled && vat.moduleType == null) ...<Widget>[
                            OutlinedButton(
                              onPressed: () => _showAction(
                                  context,
                                  gameState.installRecyclerVatModule(
                                      vatIndex, RecyclerModuleType.organic)),
                              child: const Text(
                                  'Installer Organique · 40 O. · 10 M.'),
                            ),
                            OutlinedButton(
                              onPressed: () => _showAction(
                                  context,
                                  gameState.installRecyclerVatModule(
                                      vatIndex, RecyclerModuleType.mineral)),
                              child: const Text(
                                  'Installer Minéral · 10 O. · 40 M.'),
                            ),
                          ] else if (enabled) ...<Widget>[
                            Text(
                                'Module ${vat.moduleType == RecyclerModuleType.organic ? 'Organique' : 'Minéral'}'),
                            OutlinedButton(
                              onPressed: () => _showAction(context,
                                  gameState.removeRecyclerVatModule(vatIndex)),
                              child: const Text(
                                  'Défaire le module · récupération 50 %'),
                            ),
                          ] else
                            const Text('Module indisponible'),
                        ]),
                  );
                }),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(builder: (context) {
              final report = gameState.campWasteDailyReports.isEmpty
                  ? null
                  : gameState.campWasteDailyReports.last;
              final total = (report?.domesticWasteGenerated ?? 0) +
                  (report?.technicalWasteGenerated ?? 0);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Rapport quotidien des Déchets',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                        'Population : ${gameState.campWasteGeneratedPerDay.toStringAsFixed(1)} Déchet(s) généré(s) par jour'),
                    if (report == null)
                      Text(
                          'Le premier bilan sera disponible à la prochaine journée du refuge.')
                    else ...<Widget>[
                      Text(
                          'Domestiques : ${report.domesticWasteGenerated} · techniques : ${report.technicalWasteGenerated} · total : $total'),
                      Text(
                          'Recyclés : ${report.wasteRecycled} · restants : ${gameState.resourceAmount('Déchets')}'),
                    ],
                  ]);
            }),
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

class _FabLabProductionQueuePanel extends StatelessWidget {
  const _FabLabProductionQueuePanel({
    required this.gameState,
    required this.room,
  });

  final Zone0GameState gameState;
  final FabLabRoom room;

  @override
  Widget build(BuildContext context) {
    final orders = gameState.productionQueueFor(room);
    final capacity = gameState.productionQueueCapacityFor(room);
    if (capacity == 0) {
      return const Text('Liste de production disponible au niveau 2.');
    }
    final roomLabel = room == FabLabRoom.kitchen ? 'Cuisine' : 'Atelier';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Liste de production · ${orders.length}/$capacity',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text('$roomLabel : les ordres sans intrants restent en attente.'),
            const SizedBox(height: 8),
            ...orders.map((order) {
              final recipe = craftConfig.recipes.firstWhere(
                (item) => item.id == order.recipeId,
                orElse: () => defaultCraftConfig.simpleMealRecipe,
              );
              final status = switch (order.status) {
                WorkshopOrderStatus.queued => 'En attente de démarrage',
                WorkshopOrderStatus.blocked => 'En attente de ressources',
                WorkshopOrderStatus.active => 'En cours',
                _ => 'Terminé',
              };
              return ListTile(
                dense: true,
                leading: const Icon(Icons.playlist_play_outlined),
                title:
                    Text('${recipe.displayName} × ${order.requestedQuantity}'),
                subtitle:
                    Text('$status · ${order.assignedPtipoteName ?? 'Poste'}'),
                trailing: IconButton(
                  tooltip: 'Annuler',
                  icon: const Icon(Icons.close),
                  onPressed: () => gameState.cancelWorkshopOrder(order.id),
                ),
              );
            }),
            if (orders.isEmpty) const Text('Aucun ordre programmé.'),
          ],
        ),
      ),
    );
  }
}

class _FabLabMarketRestockPanel extends StatelessWidget {
  const _FabLabMarketRestockPanel({
    required this.gameState,
    required this.room,
  });

  final Zone0GameState gameState;
  final FabLabRoom room;

  @override
  Widget build(BuildContext context) {
    if (!gameState.fabLabMarketRestockAvailable(room)) {
      return const SizedBox.shrink();
    }
    final state = gameState.fabLabRoom(room);
    final recipes = craftConfig.recipes.where((recipe) =>
        (room == FabLabRoom.kitchen
            ? recipe.craftSection == CraftSection.cuisine
            : recipe.craftSection == CraftSection.atelier) &&
        (room == FabLabRoom.kitchen
            ? recipe.cuisineLevel <= gameState.cuisineLevel
            : recipe.atelierLevel <= gameState.atelierLevel));
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('Réassort automatique du Marché'),
        subtitle:
            const Text('Choisissez explicitement les recettes et leur cible.'),
        children: recipes.map((recipe) {
          final enabled = state.marketRestockRecipeIds.contains(recipe.id);
          final target = state.marketRestockTargets[recipe.id] ?? 10;
          return SwitchListTile(
            title: Text(recipe.displayName),
            subtitle: Text('Cible Marché : $target'),
            value: enabled,
            onChanged: (value) {
              gameState.setFabLabMarketRestock(
                recipe: recipe,
                enabled: value,
                targetStockQuantity: target,
              );
            },
            secondary: IconButton(
              tooltip: 'Modifier la cible',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showFabLabRestockTargetDialog(
                context: context,
                gameState: gameState,
                recipe: recipe,
                enabled: enabled,
                initialTarget: target,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

Future<void> _showFabLabRestockTargetDialog({
  required BuildContext context,
  required Zone0GameState gameState,
  required CraftRecipe recipe,
  required bool enabled,
  required int initialTarget,
}) async {
  final controller = TextEditingController(text: '$initialTarget');
  final target = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cible Marché · ${recipe.displayName}'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Quantité cible'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            math.max(0, int.tryParse(controller.text) ?? initialTarget),
          ),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (target == null) return;
  gameState.setFabLabMarketRestock(
    recipe: recipe,
    enabled: enabled,
    targetStockQuantity: target,
  );
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
        final figurines = widget.gameState.ptipotesAvailableForActivities(
          snapshot.data ?? const <PtipoteFigurine>[],
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _FabLabHeader(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FablabEnergyCard(gameState: widget.gameState),
            const SizedBox(height: 12),
            _CommunityBuildingPosts(
              gameState: widget.gameState,
              roles: const <CommunityRoleType>[
                CommunityRoleType.fablabMaker,
              ],
            ),
            const SizedBox(height: 12),
            _FabLabPermanentPosts(
              gameState: widget.gameState,
              room: FabLabRoom.workshop,
              figurines: figurines,
            ),
            const SizedBox(height: 12),
            _FablabActiveCraftsPanel(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FabLabProductionQueuePanel(
              gameState: widget.gameState,
              room: FabLabRoom.workshop,
            ),
            const SizedBox(height: 12),
            _FabLabMarketRestockPanel(
              gameState: widget.gameState,
              room: FabLabRoom.workshop,
            ),
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
              '${widget.gameState.activeManualWorkshopOrders}/${widget.gameState.manualWorkshopSlots} créneau manuel. Chaque niveau ajoute un emplacement P’TIPOTE.',
            ),
            const SizedBox(height: 12),
            if (widget.gameState.activeManualWorkshopOrders <
                    widget.gameState.manualWorkshopSlots ||
                widget.gameState.activePtipoteWorkshopOrders <
                    widget.gameState.workshopSlots) ...<Widget>[
              _FablabQuantitySelector(
                quantity: _quantity,
                level: widget.gameState.atelierLevel,
                room: FabLabRoom.workshop,
                onChanged: (value) => setState(() => _quantity = value),
              ),
              const SizedBox(height: 10),
              ...<({
                String title,
                IconData icon,
                bool Function(CraftRecipe) matches
              })>[
                (
                  title: 'Équipements',
                  icon: Icons.checkroom_outlined,
                  matches: (recipe) =>
                      !recipe.displayName.contains('Meuble') &&
                      !recipe.displayName.contains('Ventilation') &&
                      !recipe.displayName.contains('Lumière') &&
                      !recipe.displayName.contains('Cartouche') &&
                      recipe.id != 'chloroCanals' &&
                      recipe.id != 'filterInstallation' &&
                      recipe.id != 'repairKit' &&
                      recipe.id != 'biomassRegenerator'
                ),
                (
                  title: 'Structures',
                  icon: Icons.construction_outlined,
                  matches: (recipe) =>
                      recipe.displayName.contains('Ventilation') ||
                      recipe.displayName.contains('Cartouche') ||
                      recipe.id == 'chloroCanals' ||
                      recipe.id == 'filterInstallation' ||
                      recipe.id == 'repairKit' ||
                      recipe.id == 'biomassRegenerator'
                ),
                (
                  title: 'Meubles',
                  icon: Icons.chair_outlined,
                  matches: (recipe) =>
                      recipe.displayName.contains('Meuble') ||
                      recipe.id == 'solarLight'
                ),
              ].map((section) => ExpansionTile(
                    leading: Icon(section.icon),
                    title: Text(section.title),
                    children: craftConfig.recipes
                        .where((recipe) =>
                            recipe.craftSection == CraftSection.atelier)
                        .where((recipe) =>
                            recipe.atelierLevel <=
                            widget.gameState.atelierLevel)
                        .where(widget.gameState.isWorkshopRecipeActive)
                        .where(section.matches)
                        .map((recipe) => _WorkshopRecipeCard(
                              recipe: recipe,
                              gameState: widget.gameState,
                              quantity: _quantity,
                              manualAvailable:
                                  widget.gameState.activeManualWorkshopOrders <
                                      widget.gameState.manualWorkshopSlots,
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
                                if (figurine != null && context.mounted)
                                  _start(recipe, figurine);
                              },
                              queueAvailable:
                                  widget.gameState.productionQueueCapacityFor(
                                        FabLabRoom.workshop,
                                      ) >
                                      0,
                              onQueue: () async {
                                final result = widget.gameState
                                    .enqueueFabLabProductionOrder(
                                  recipe: recipe,
                                  quantity: _quantity,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(result.message)),
                                );
                              },
                            ))
                        .toList(),
                  )),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Créneau manuel et emplacements P’TIPOTE occupés.'),
              ),
            const SizedBox(height: 18),
            ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Armatures P’TIBUG'),
              subtitle: const Text(
                'Fabriquées à l’Atelier, puis cultivées dans la Nurserie.',
              ),
              children: <Widget>[
                ...PTibugSpecies.values.map(
                  (species) => _PTibugArmatureAtelierCard(
                    gameState: widget.gameState,
                    species: species,
                    figurines: figurines,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PTibugNurseryPage(
                          gameState: widget.gameState,
                          campHeartLevel: 1,
                          campHeartState: CampHeartState.placeholder(),
                          initialTabIndex: 2,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.pets_outlined),
                    label: const Text('Voir les Armatures dans la Nurserie'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Modules P’TIBUG'),
              subtitle:
                  const Text('Fabriqués ici, puis équipés dans la Nurserie.'),
              children: PTibugModuleType.values
                  .map(
                    (module) => _PTibugModuleAtelierCard(
                      gameState: widget.gameState,
                      module: module,
                      figurines: figurines,
                    ),
                  )
                  .toList(),
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
        final figurines = widget.gameState.ptipotesAvailableForActivities(
          snapshot.data ?? const <PtipoteFigurine>[],
        );
        return ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            _FabLabHeader(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FablabEnergyCard(gameState: widget.gameState),
            const SizedBox(height: 12),
            _CommunityBuildingPosts(
              gameState: widget.gameState,
              roles: const <CommunityRoleType>[CommunityRoleType.kitchenCook],
            ),
            const SizedBox(height: 12),
            _FabLabPermanentPosts(
              gameState: widget.gameState,
              room: FabLabRoom.kitchen,
              figurines: figurines,
            ),
            const SizedBox(height: 12),
            _FablabActiveCraftsPanel(gameState: widget.gameState),
            const SizedBox(height: 12),
            _FabLabProductionQueuePanel(
              gameState: widget.gameState,
              room: FabLabRoom.kitchen,
            ),
            const SizedBox(height: 12),
            _FabLabMarketRestockPanel(
              gameState: widget.gameState,
              room: FabLabRoom.kitchen,
            ),
            const SizedBox(height: 12),
            Text(
              'Cuisine niveau ${widget.gameState.cuisineLevel}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Eau disponible gratuitement. ${widget.gameState.activePtipoteKitchenOrders}/${widget.gameState.kitchenSlots} emplacement(s) P’TIPOTE · ${widget.gameState.activeManualKitchenOrders}/${widget.gameState.manualKitchenSlots} créneau manuel.',
            ),
            const SizedBox(height: 12),
            _FablabQuantitySelector(
              quantity: _quantity,
              level: widget.gameState.cuisineLevel,
              room: FabLabRoom.kitchen,
              onChanged: (value) => setState(() => _quantity = value),
            ),
            const SizedBox(height: 12),
            ...craftConfig.recipes
                .where((recipe) => recipe.craftSection == CraftSection.cuisine)
                .where((recipe) =>
                    recipe.cuisineLevel <= widget.gameState.cuisineLevel)
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
                        widget.gameState.activeManualKitchenOrders <
                            widget.gameState.manualKitchenSlots,
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
                    queueAvailable: widget.gameState.productionQueueCapacityFor(
                          FabLabRoom.kitchen,
                        ) >
                        0,
                    onQueue: () async {
                      final result =
                          widget.gameState.enqueueFabLabProductionOrder(
                        recipe: recipe,
                        quantity: _quantity,
                      );
                      setState(() => _lastResult = result.message);
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

class _PTibugArmatureAtelierCard extends StatelessWidget {
  const _PTibugArmatureAtelierCard({
    required this.gameState,
    required this.species,
    required this.figurines,
  });

  final Zone0GameState gameState;
  final PTibugSpecies species;
  final List<PtipoteFigurine> figurines;

  @override
  Widget build(BuildContext context) {
    final config = pTibugConfig.species[species]!;
    final active =
        gameState.isPTibugPatternActive('ptibug-species-${species.name}');
    final materials = gameState.hasResources(config.creationCost);
    final batteries = gameState.bioBatteries >= config.creationBioBatteryCost;
    final manualAvailable =
        gameState.activeManualWorkshopOrders < gameState.manualWorkshopSlots;
    final ptipoteAvailable =
        gameState.activePtipoteWorkshopOrders < gameState.workshopSlots;
    final details = config.creationCost.entries
        .map((entry) =>
            '${entry.key} : ${entry.value} / ${gameState.resourceAmount(entry.key)}')
        .join('\n');
    return _ProductionRecipeCard(
      title: 'Armature ${config.displayName}',
      leadingIcon: Icons.auto_awesome_outlined,
      description:
          'Fabrique une Armature à l’Atelier. Elle sera ensuite placée dans une cuve de la Nurserie.',
      slots: <_ProductionSlotData>[
        _ProductionSlotData(
            label: 'Matériaux', value: details, icon: Icons.eco_outlined),
        _ProductionSlotData(
          label: 'Atelier',
          value:
              'Bio-batteries : ${config.creationBioBatteryCost}/${gameState.bioBatteries}\nTemps : ${pTibugConfig.cultivation.armatureMinutes ~/ 60} h',
          icon: Icons.precision_manufacturing_outlined,
        ),
      ],
      details: const <String>[
        'Une Armature prête rejoint ensuite la réserve de la Nurserie.',
      ],
      prerequisiteLabel:
          active ? 'Pattern Kernel actif' : 'Pré-requis : Pattern Kernel actif',
      prerequisiteMet: active,
      unavailableLabel: !materials
          ? gameState.missingResourcesLabel(config.creationCost)
          : !batteries
              ? 'Bio-batteries insuffisantes.'
              : !manualAvailable
                  ? 'Créneau manuel de l’Atelier occupé.'
                  : null,
      primaryActionLabel: 'Fabriquer une Armature',
      primaryActionIcon: Icons.precision_manufacturing_outlined,
      primaryActionEnabled: active && materials && batteries && manualAvailable,
      onPrimaryAction: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(gameState.startPTibugCreation(species).message)),
      ),
      secondaryActionLabel: 'Confier à un P’TIPOTE',
      secondaryActionEnabled:
          active && materials && batteries && ptipoteAvailable,
      onSecondaryAction: () async {
        final figurine = await _pickPtipoteForActivity(
          context: context,
          gameState: gameState,
          figurines: figurines,
          title: 'Confier l’Armature ${config.displayName}',
        );
        if (figurine != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                gameState
                    .startPTibugCreation(species, figurine: figurine)
                    .message,
              ),
            ),
          );
        }
      },
    );
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
    final manualAvailable =
        gameState.activeManualWorkshopOrders < gameState.manualWorkshopSlots;
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
    final effect = switch (module) {
      PTibugModuleType.ailes =>
        'Effet : réduit la durée des cycles de production.',
      PTibugModuleType.pinces =>
        'Effet : augmente la production matérielle par cycle.',
      PTibugModuleType.reservoir =>
        'Effet : augmente la capacité de réserve du P’TIBUG.',
      PTibugModuleType.reflecteur =>
        'Effet : protège le P’TIBUG pendant les fortes chaleurs.',
      PTibugModuleType.etancheite =>
        'Effet : protège le P’TIBUG pendant les pluies intenses.',
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
        effect,
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
    this.queueAvailable = false,
    this.onQueue,
  });

  final CraftRecipe recipe;
  final Zone0GameState gameState;
  final int quantity;
  final bool manualAvailable;
  final bool ptipoteAvailable;
  final VoidCallback onPrepare;
  final Future<void> Function() onAssign;
  final bool queueAvailable;
  final Future<void> Function()? onQueue;

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
        queueAvailable: queueAvailable,
        onQueue: onQueue,
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
    this.queueAvailable = false,
    this.onQueue,
  });

  final CraftRecipe recipe;
  final Zone0GameState gameState;
  final int quantity;
  final bool canPrepare;
  final bool manualAvailable;
  final bool ptipoteAvailable;
  final VoidCallback onPrepare;
  final Future<void> Function() onAssign;
  final bool queueAvailable;
  final Future<void> Function()? onQueue;

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
        queueAvailable: queueAvailable,
        onQueue: onQueue,
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
    this.queueAvailable = false,
    this.onQueue,
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
  final bool queueAvailable;
  final Future<void> Function()? onQueue;

  @override
  Widget build(BuildContext context) {
    final isUnlimited = quantity == -1;
    final materialMaxCreatable = _maxProductionCount(
      recipe.ingredients,
      gameState.resourceAmount,
    );
    final batteryMaxCreatable = recipe.bioBatteryCost <= 0
        ? materialMaxCreatable
        : gameState.bioBatteries ~/ recipe.bioBatteryCost;
    final maxCreatable = math.min(materialMaxCreatable, batteryMaxCreatable);
    final effectiveQuantity = isUnlimited ? maxCreatable : quantity;
    final costs = recipe.ingredients.map(
      (key, value) => MapEntry(key, value * effectiveQuantity),
    );
    final output = <String, int>{
      recipe.resultItem: recipe.resultAmount * effectiveQuantity,
    };
    final hasResources = effectiveQuantity > 0 && gameState.hasResources(costs);
    final hasCapacity = gameState.hasInventoryCapacityFor(output);
    final bioBatteryCost = recipe.bioBatteryCost * effectiveQuantity;
    final hasBioBatteries = gameState.bioBatteries >= bioBatteryCost;
    final craftEnergyCost = recipe.energyCost * effectiveQuantity;
    final hasCraftEnergy = gameState.energyUnits >= craftEnergyCost;
    final canPrepare =
        hasResources && hasCapacity && hasBioBatteries && hasCraftEnergy;
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
      'Résultat : ${isUnlimited ? 'jusqu’à ${recipe.resultAmount * maxCreatable}' : recipe.resultAmount * effectiveQuantity} ${recipe.resultItem}',
      'Créations possibles avec le stock : $maxCreatable',
      'Temps : ${recipe.durationMinutes} min/unité',
    ];
    if (showConsumableEffects) {
      outputDetails.add(
        'Consommable · faim +${recipe.hungerRestore} · vitalité +${recipe.vitalityRestore}',
      );
    }
    if (craftEnergyCost > 0) {
      outputDetails.add('Énergie du craft : $craftEnergyCost');
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
                      : !hasCraftEnergy
                          ? '$craftEnergyCost unité(s) d’énergie requise(s).'
                          : null
              : 'Inventaire plein : impossible de ranger ${recipe.resultItem}.'
          : null,
      primaryActionLabel: 'Lancer manuellement',
      primaryActionHint: 'utilise 1 unité d’énergie',
      primaryActionIcon: sectionLabel == 'Cuisine'
          ? Icons.restaurant_outlined
          : Icons.handyman_outlined,
      primaryActionEnabled: !isUnlimited &&
          canPrepare &&
          manualAvailable &&
          gameState.energyUnits >= craftEnergyCost + 1,
      onPrimaryAction: onPrepare,
      secondaryActionLabel: 'Confier à un P’TIPOTE',
      secondaryActionIcon: Icons.person_add_alt_1,
      secondaryActionEnabled: canPrepare && ptipoteAvailable,
      onSecondaryAction: onAssign,
      tertiaryActionLabel: queueAvailable ? 'Ajouter à la liste' : null,
      tertiaryActionIcon: Icons.playlist_add_outlined,
      tertiaryActionEnabled: queueAvailable,
      onTertiaryAction: onQueue,
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
    this.tertiaryActionLabel,
    this.tertiaryActionIcon,
    this.tertiaryActionEnabled = false,
    this.onTertiaryAction,
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
  final String? tertiaryActionLabel;
  final IconData? tertiaryActionIcon;
  final bool tertiaryActionEnabled;
  final Future<void> Function()? onTertiaryAction;
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
              if (tertiaryActionLabel != null) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: tertiaryActionEnabled && onTertiaryAction != null
                      ? onTertiaryAction
                      : null,
                  icon: Icon(tertiaryActionIcon),
                  label: Text(tertiaryActionLabel!),
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
