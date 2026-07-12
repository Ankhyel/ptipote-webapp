import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'camp_heart_config.dart';
import 'fablab_config.dart';
import 'game_asset_resolver.dart';
import 'lisiere_forage_config.dart';
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
  ];

  @override
  void initState() {
    super.initState();
    _zone0State.addListener(_onZone0StateChanged);
    _missionResolutionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _zone0State.resolveDueForageMissions(),
    );
    _warmAssets();
    _zone0State.resolveDueForageMissions();
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
    _refugeAsset = await _assetResolver.resolve('Camp');
    if (mounted) setState(() {});
  }

  void _openBuilding(_RefugeBuilding building) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (building.name == 'Maison') return const _MaisonPage();
          if (building.name == 'Lisiere') {
            return LisierePage(gameState: _zone0State);
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
    _openBuilding(building);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jeu')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
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
                            campHeartState: building.name == 'CampHeart'
                                ? _campHeartState
                                : null,
                            notificationCount: building.name == 'Maison'
                                ? _zone0State.unreadReportCount
                                : 0,
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
  String? _trainingFigurineId;
  bool _choosingTrainingTarget = false;
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
      if (_choosingTrainingTarget) {
        _trainingFigurineId = figurine.id;
        _selectedFigurineId = figurine.id;
        _choosingTrainingTarget = false;
        return;
      }
      _selectedFigurineId =
          _selectedFigurineId == figurine.id ? null : figurine.id;
    });
  }

  void _trainSelected(List<PtipoteFigurine> figurines) {
    final id = _trainingFigurineId;
    if (id == null) return;
    PtipoteFigurine? figurine;
    for (final item in figurines) {
      if (item.id == id) {
        figurine = item;
        break;
      }
    }
    if (figurine == null) return;
    final selected = figurine;
    setState(() {
      final current = _vitalityFor(selected);
      _gameState.vitalityOverrides[id] = math.max(0, current - 25);
      _selectedFigurineId = id;
    });
    unawaited(_gameState.saveRuntimeToFirebase());
  }

  void _recoverVitalityStep() {
    if (!mounted || _gameState.vitalityOverrides.isEmpty) return;
    setState(() {
      _recoveryTick += 1;
      final vitalityUpdates = <String, int>{};
      final idsToClear = <String>[];
      final alcoveRecoveryPerTick = math.max(
        1,
        (ptipoteStatsConfig.alcoveVitalityRecoveryPerMinute / 2).round(),
      );
      for (final entry in _gameState.vitalityOverrides.entries) {
        final isResting =
            entry.value <= ptipoteStatsConfig.minVitalityBeforeAutoRest;
        if (!isResting && _recoveryTick.isOdd) continue;
        final nextVitality = math.min(
          ptipoteStatsConfig.maxVitality,
          entry.value + alcoveRecoveryPerTick,
        );
        if (nextVitality >= ptipoteStatsConfig.maxVitality) {
          idsToClear.add(entry.key);
        } else {
          vitalityUpdates[entry.key] = nextVitality;
        }
      }
      _gameState.vitalityOverrides.addAll(vitalityUpdates);
      for (final id in idsToClear) {
        _gameState.vitalityOverrides.remove(id);
      }
    });
    unawaited(_gameState.saveRuntimeToFirebase());
  }

  void _setAutoPreference(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) {
    setState(() {
      _gameState.autoPreferenceOverrides[figurine.id] = preference;
      _selectedFigurineId = figurine.id;
    });
  }

  void _wakeFigurine(PtipoteFigurine figurine) {
    setState(() {
      _gameState.wakeFromRest(figurine);
      _selectedFigurineId = figurine.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maison')),
      body: SafeArea(
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
                  const _AlcoveLayer(),
                  const _FloorLayer(),
                  StreamBuilder<List<PtipoteFigurine>>(
                    stream: _figurineService.watchMyFigurines(),
                    builder: (context, snapshot) {
                      final figurines =
                          snapshot.data ?? const <PtipoteFigurine>[];
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          figurines.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (figurines.isEmpty) return const _RefugeEmptyState();
                      return Stack(
                        children: <Widget>[
                          _PtipoteRefugeLayer(
                            figurines: figurines,
                            animation: _tickController,
                            selectedFigurineId: _selectedFigurineId,
                            trainingFigurineId: _trainingFigurineId,
                            choosingTrainingTarget: _choosingTrainingTarget,
                            vitalityFor: _vitalityFor,
                            xpFor: _gameState.xpFor,
                            levelFor: _gameState.levelFor,
                            isOnMission: _gameState.isOnMission,
                            autoPreferenceFor: _autoPreferenceFor,
                            onToggleFigurine: _toggleFigurine,
                            onAutoPreferenceChanged: _setAutoPreference,
                            onWake: _wakeFigurine,
                          ),
                          _TrainingTool(
                            choosing: _choosingTrainingTarget,
                            hasTarget: _trainingFigurineId != null,
                            onChoose: () {
                              setState(() => _choosingTrainingTarget = true);
                            },
                            onTrain: () => _trainSelected(figurines),
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
              built ? 'Fablab niv. ${gameState.fablabLevel}' : 'Fablab à bâtir',
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
  const _AlcoveLayer();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final alcoveWidth = constraints.maxWidth * 0.24;
          final alcoveHeight = alcoveWidth * 0.52;
          return Stack(
            children: List<Widget>.generate(3, (index) {
              final left = constraints.maxWidth * (0.18 + index * 0.29);
              return Positioned(
                left: left,
                top: constraints.maxHeight * 0.28,
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
    required this.trainingFigurineId,
    required this.choosingTrainingTarget,
    required this.vitalityFor,
    required this.xpFor,
    required this.levelFor,
    required this.isOnMission,
    required this.autoPreferenceFor,
    required this.onToggleFigurine,
    required this.onAutoPreferenceChanged,
    required this.onWake,
  });

  final List<PtipoteFigurine> figurines;
  final Animation<double> animation;
  final String? selectedFigurineId;
  final String? trainingFigurineId;
  final bool choosingTrainingTarget;
  final int Function(PtipoteFigurine figurine) vitalityFor;
  final int Function(PtipoteFigurine figurine) xpFor;
  final int Function(PtipoteFigurine figurine) levelFor;
  final bool Function(String figurineId) isOnMission;
  final PtipoteAutoAssignmentPreference Function(PtipoteFigurine figurine)
      autoPreferenceFor;
  final ValueChanged<PtipoteFigurine> onToggleFigurine;
  final void Function(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) onAutoPreferenceChanged;
  final ValueChanged<PtipoteFigurine> onWake;

  @override
  State<_PtipoteRefugeLayer> createState() => _PtipoteRefugeLayerState();
}

class _PtipoteRefugeLayerState extends State<_PtipoteRefugeLayer> {
  final _random = math.Random();
  final Map<String, _PtipoteMotion> _motions = <String, _PtipoteMotion>{};
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
          widget.trainingFigurineId == figurine.id) {
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
    final resting = widget.figurines
        .where(
          (figurine) =>
              !widget.isOnMission(figurine.id) &&
              widget.vitalityFor(figurine) <=
                  ptipoteStatsConfig.minVitalityBeforeAutoRest,
        )
        .take(3)
        .toList();
    final active = widget.figurines
        .where(
          (figurine) =>
              !widget.isOnMission(figurine.id) &&
              widget.vitalityFor(figurine) >
                  ptipoteStatsConfig.minVitalityBeforeAutoRest,
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
          return Stack(
            children: <Widget>[
              ...List<Widget>.generate(active.length, (index) {
                final figurine = active[index];
                final motion = _motions.putIfAbsent(figurine.id, _newMotion);
                final isTraining = widget.trainingFigurineId == figurine.id;
                final left = isTraining
                    ? (constraints.maxWidth - spriteSize) / 2
                    : motion.x * usableWidth;
                final bounce = motion.moving && !isTraining
                    ? math.sin(
                          widget.animation.value * math.pi * 2 +
                              motion.bounceSeed,
                        ) *
                        0.4
                    : 0.0;
                final bottom = isTraining
                    ? constraints.maxHeight * 0.16
                    : walkingBaseBottom + (index % 3) * 12 + bounce;
                return Positioned(
                  left: left,
                  bottom: bottom,
                  width: spriteSize,
                  child: _PtipoteSpriteButton(
                    figurine: figurine,
                    vitality: widget.vitalityFor(figurine),
                    xp: widget.xpFor(figurine),
                    level: widget.levelFor(figurine),
                    autoPreference: widget.autoPreferenceFor(figurine),
                    selected: widget.selectedFigurineId == figurine.id,
                    choosingTrainingTarget: widget.choosingTrainingTarget,
                    isResting: false,
                    restProgress: 0,
                    onTap: () => widget.onToggleFigurine(figurine),
                    onWake: () => widget.onWake(figurine),
                    onAutoPreferenceChanged: (preference) {
                      widget.onAutoPreferenceChanged(figurine, preference);
                    },
                  ),
                );
              }),
              ...List<Widget>.generate(resting.length, (index) {
                final figurine = resting[index];
                final alcoveCenter =
                    constraints.maxWidth * (0.30 + index * 0.29);
                final restProgress = widget.vitalityFor(figurine) /
                    ptipoteStatsConfig.maxVitality;
                return Positioned(
                  left: alcoveCenter - spriteSize / 2,
                  top: constraints.maxHeight * 0.26,
                  width: spriteSize,
                  child: _PtipoteSpriteButton(
                    figurine: figurine,
                    vitality: widget.vitalityFor(figurine),
                    xp: widget.xpFor(figurine),
                    level: widget.levelFor(figurine),
                    autoPreference: widget.autoPreferenceFor(figurine),
                    selected: widget.selectedFigurineId == figurine.id,
                    choosingTrainingTarget: widget.choosingTrainingTarget,
                    isResting: true,
                    restProgress: restProgress,
                    onTap: () => widget.onToggleFigurine(figurine),
                    onWake: () => widget.onWake(figurine),
                    onAutoPreferenceChanged: (preference) {
                      widget.onAutoPreferenceChanged(figurine, preference);
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
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
    required this.vitality,
    required this.xp,
    required this.level,
    required this.autoPreference,
    required this.selected,
    required this.choosingTrainingTarget,
    required this.isResting,
    required this.restProgress,
    required this.onTap,
    required this.onWake,
    required this.onAutoPreferenceChanged,
  });

  final PtipoteFigurine figurine;
  final int vitality;
  final int xp;
  final int level;
  final PtipoteAutoAssignmentPreference autoPreference;
  final bool selected;
  final bool choosingTrainingTarget;
  final bool isResting;
  final double restProgress;
  final VoidCallback onTap;
  final VoidCallback onWake;
  final ValueChanged<PtipoteAutoAssignmentPreference> onAutoPreferenceChanged;

  @override
  State<_PtipoteSpriteButton> createState() => _PtipoteSpriteButtonState();
}

class _PtipoteSpriteButtonState extends State<_PtipoteSpriteButton> {
  Offset _bubbleOffset = Offset.zero;
  Offset _longPressOrigin = Offset.zero;
  Offset _bubbleOrigin = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final remainingRatio = (1 - widget.restProgress).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          _PtipoteSprite(figurine: widget.figurine),
          if (widget.isResting)
            Positioned(
              bottom: -10,
              left: 8,
              right: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: remainingRatio,
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF6FA05F),
                  ),
                ),
              ),
            ),
          if (widget.selected)
            Positioned(
              bottom: widget.isResting ? null : 76 + _bubbleOffset.dy,
              top: widget.isResting ? 76 + _bubbleOffset.dy : null,
              left: _bubbleOffset.dx,
              child: GestureDetector(
                onLongPressStart: (_) {
                  _longPressOrigin = Offset.zero;
                  _bubbleOrigin = _bubbleOffset;
                },
                onLongPressMoveUpdate: (details) {
                  setState(() {
                    _longPressOrigin = details.offsetFromOrigin;
                    _bubbleOffset = _bubbleOrigin + _longPressOrigin;
                  });
                },
                child: _PtipoteInfoBubble(
                  figurine: widget.figurine,
                  vitality: widget.vitality,
                  xp: widget.xp,
                  level: widget.level,
                  autoPreference: widget.autoPreference,
                  isResting: widget.isResting,
                  onWake: widget.onWake,
                  onAutoPreferenceChanged: widget.onAutoPreferenceChanged,
                ),
              ),
            ),
          if (widget.choosingTrainingTarget)
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
    required this.figurine,
    required this.vitality,
    required this.xp,
    required this.level,
    required this.autoPreference,
    required this.isResting,
    required this.onWake,
    required this.onAutoPreferenceChanged,
  });

  final PtipoteFigurine figurine;
  final int vitality;
  final int xp;
  final int level;
  final PtipoteAutoAssignmentPreference autoPreference;
  final bool isResting;
  final VoidCallback onWake;
  final ValueChanged<PtipoteAutoAssignmentPreference> onAutoPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 236,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              figurine.displayName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            _InfoLine(label: 'Espèce', value: figurine.species),
            _InfoLine(label: 'Type', value: figurine.type),
            _InfoLine(label: 'Enveloppe', value: figurine.envelopeLabel),
            _InfoLine(label: 'Surnom', value: figurine.displayName),
            _InfoLine(label: 'Niveau', value: '$level'),
            _InfoLine(
              label: 'XP',
              value: '$xp/${ptipoteStatsConfig.xpRequiredForNextLevel(level)}',
            ),
            _InfoLine(
              label: 'Vitalité',
              value: '$vitality/${figurine.maxVitality}',
            ),
            _InfoLine(label: 'Bonheur', value: '${figurine.happiness}/100'),
            _InfoLine(label: 'État', value: _stateLabel(figurine, vitality)),
            _InfoLine(label: 'Auto', value: _preferenceLabel(autoPreference)),
            if (isResting) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onWake,
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('Réveiller'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  PtipoteAutoAssignmentPreference.values.map((preference) {
                return ChoiceChip(
                  label: Text(_shortPreferenceLabel(preference)),
                  selected: autoPreference == preference,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onAutoPreferenceChanged(preference),
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

class _TrainingTool extends StatelessWidget {
  const _TrainingTool({
    required this.choosing,
    required this.hasTarget,
    required this.onChoose,
    required this.onTrain,
  });

  final bool choosing;
  final bool hasTarget;
  final VoidCallback onChoose;
  final VoidCallback onTrain;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Material(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onChoose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('🏋️', style: TextStyle(fontSize: 26)),
                      if (choosing) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          'Clique un P’TIPOTE',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (hasTarget) ...<Widget>[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onTrain,
                child: const Text('Entrainer'),
              ),
            ],
          ],
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
    'Minéral' || 'Mineral' => Icons.diamond_outlined,
    'Énergie' || 'Energie' => Icons.bolt_outlined,
    'Repas' => Icons.restaurant_outlined,
    _ => Icons.inventory_2_outlined,
  };
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
              (report) => Card(
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
                      Text('Incident : ${report.incidentLabel}'),
                      Text('Vitalité restante : ${report.vitalityRemaining}'),
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
  const LisierePage({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  State<LisierePage> createState() => _LisierePageState();
}

class _LisierePageState extends State<LisierePage> {
  final _figurineService = FigurineService();
  ForageBiome _biome = ForageBiome.colline;
  ForageDuration _duration = ForageDuration.oneHour;
  ForageIntensity _intensity = ForageIntensity.normal;
  final Set<String> _selectedFigurineIds = <String>{};

  @override
  void initState() {
    super.initState();
    widget.gameState.addListener(_onGameStateChanged);
    widget.gameState.resolveDueForageMissions();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Lisière proche')),
      body: SafeArea(
        child: StreamBuilder<List<PtipoteFigurine>>(
          stream: _figurineService.watchMyFigurines(),
          builder: (context, snapshot) {
            final figurines = snapshot.data ?? const <PtipoteFigurine>[];
            _selectedFigurineIds.removeWhere((id) {
              return figurines.any(
                (figurine) =>
                    figurine.id == id && widget.gameState.isBusy(figurine),
              );
            });
            final selectedFigurines = figurines
                .where((figurine) => _selectedFigurineIds.contains(figurine.id))
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
                    children: ForageBiome.values.map((biome) {
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
                            final suffix = onMission
                                ? ' · mission'
                                : resting
                                    ? ' · repos'
                                    : '';
                            return ChoiceChip(
                              label: Text(
                                '${figurine.displayName} · V$vitality$suffix',
                              ),
                              selected:
                                  _selectedFigurineIds.contains(figurine.id),
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() {
                                        if (_selectedFigurineIds
                                            .contains(figurine.id)) {
                                          _selectedFigurineIds
                                              .remove(figurine.id);
                                        } else {
                                          _selectedFigurineIds.add(figurine.id);
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
                        onSelected: (_) => setState(() => _duration = duration),
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
                        label: Text(
                            lisiereForageConfig.intensities[intensity]!.label),
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
                      'Un ou plusieurs P’TIPOTES ont besoin de récupérer avant cette sortie.',
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
    );
  }

  ForageEstimate _estimate(PtipoteFigurine figurine) {
    final rewards = _calculateRewards(figurine);
    final duration = lisiereForageConfig.durations[_duration]!;
    final intensity = lisiereForageConfig.intensities[_intensity]!;
    final cost =
        (duration.baseVitalityCost * intensity.vitalityMultiplier).round();
    final riskPercent = _riskPercent(figurine);
    final vitality = widget.gameState.vitalityFor(figurine);
    return ForageEstimate(
      rewards: rewards,
      vitalityCost: cost,
      xpGain: _xpGain(figurine),
      riskPercent: riskPercent,
      riskLabel: _riskLabel(riskPercent),
      zoneFatigueLabel: intensity.zoneFatigueLabel,
      canLaunch: vitality > ptipoteStatsConfig.minVitalityBeforeAutoRest &&
          vitality >= cost &&
          !widget.gameState.isBusy(figurine),
    );
  }

  int _xpGain(PtipoteFigurine figurine) {
    final base = lisiereForageConfig.xpGainByDuration[_duration] ?? 8;
    final intensity =
        lisiereForageConfig.intensityXpMultiplier[_intensity] ?? 1;
    final withBonus = base * intensity * (1 + figurine.xpGainBonus);
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
    final biome = lisiereForageConfig.biomes[_biome]!;
    final intensity = lisiereForageConfig.intensities[_intensity]!;
    var risk = biome.baseRiskPercent +
        intensity.riskModifierPercent -
        (widget.gameState.refugeSafety / 10).round();
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
    return math.max(0, risk);
  }

  String _riskLabel(int risk) {
    if (risk <= 3) return 'Très sûr';
    if (risk <= 8) return 'Sûr';
    if (risk <= 15) return 'Incertain';
    return 'Risqué';
  }

  void _launchMissions(Map<PtipoteFigurine, ForageEstimate> estimates) {
    var launched = 0;
    for (final entry in estimates.entries) {
      final estimate = entry.value;
      if (!estimate.canLaunch) continue;
      widget.gameState.startForageMission(
        figurine: entry.key,
        biome: _biome,
        duration: _duration,
        intensity: _intensity,
        expectedRewards: estimate.rewards,
        vitalityCost: estimate.vitalityCost,
        riskPercent: estimate.riskPercent,
        riskLabel: estimate.riskLabel,
        xpGain: estimate.xpGain,
      );
      launched += 1;
    }
    _selectedFigurineIds.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched <= 1
              ? '1 P’TIPOTE part en Lisière.'
              : '$launched P’TIPOTES partent en Lisière.',
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
    required this.riskPercent,
    required this.riskLabel,
    required this.zoneFatigueLabel,
    required this.canLaunch,
  });

  final Map<String, int> rewards;
  final int vitalityCost;
  final int xpGain;
  final int riskPercent;
  final String riskLabel;
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
    required this.riskPercent,
    required this.riskLabel,
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
    var riskPercent = 0;
    var riskLabel = 'Très sûr';
    var zoneFatigueLabel = 'faible';
    var canLaunch = list.isNotEmpty;

    for (final estimate in list) {
      vitalityCost += estimate.vitalityCost;
      xpGain += estimate.xpGain;
      canLaunch = canLaunch && estimate.canLaunch;
      if (estimate.riskPercent >= riskPercent) {
        riskPercent = estimate.riskPercent;
        riskLabel = estimate.riskLabel;
      }
      zoneFatigueLabel = estimate.zoneFatigueLabel;
      for (final entry in estimate.rewards.entries) {
        rewards[entry.key] = (rewards[entry.key] ?? 0) + entry.value;
      }
    }

    return ForageGroupEstimate(
      rewards: rewards,
      vitalityCost: vitalityCost,
      xpGain: xpGain,
      riskPercent: riskPercent,
      riskLabel: riskLabel,
      zoneFatigueLabel: zoneFatigueLabel,
      canLaunch: canLaunch,
    );
  }

  final Map<String, int> rewards;
  final int vitalityCost;
  final int xpGain;
  final int riskPercent;
  final String riskLabel;
  final String zoneFatigueLabel;
  final bool canLaunch;

  int get totalRewards {
    return rewards.values.fold(0, (total, amount) => total + amount);
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
            Text('Risque : ${estimate.riskLabel} (${estimate.riskPercent}%)'),
            Text('Fatigue de zone prévue : ${estimate.zoneFatigueLabel}'),
            const Text('Bâtiment lié : à venir'),
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
                return Text('${mission.figurineName} · ${biome.label}');
              }),
          ],
        ),
      ),
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

  int? get vegetalizationXpRequired {
    return currentStage.xpRequiredForNextLevel;
  }

  bool get isMaxLevel => vegetalizationXpRequired == null;

  double get progressRatio {
    final required = vegetalizationXpRequired;
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
      final required = vegetalizationXpRequired!;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Cœur du Camp')),
      body: SafeArea(
        child: ListView(
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
      ),
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

class FablabConstructionSheet extends StatelessWidget {
  const FablabConstructionSheet({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  Widget build(BuildContext context) {
    final cost = fablabConfig.constructionCostLevel1;
    final canBuild = gameState.hasResources(cost);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Fablab',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le Fablab permet au refuge de cuisiner, fabriquer et recycler progressivement ses ressources.',
            ),
            const SizedBox(height: 14),
            _ResourceCostLine(
              resource: 'Organique',
              owned: gameState.resourceAmount('Organique'),
              required: cost['Organique'] ?? 0,
            ),
            _ResourceCostLine(
              resource: 'Minéral',
              owned: gameState.resourceAmount('Minéral'),
              required: cost['Minéral'] ?? 0,
            ),
            const SizedBox(height: 10),
            Text(
              'Stock ajouté : +${fablabConfig.stockCapacityBonusPerFablabLevel} unités',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (!canBuild) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                gameState.missingResourcesLabel(cost),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canBuild
                  ? () {
                      final result = gameState.constructFablabLevel1();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                      if (result.success) Navigator.of(context).pop();
                    }
                  : null,
              icon: const Icon(Icons.construction_outlined),
              label: const Text('Construire'),
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
}

class _ResourceCostLine extends StatelessWidget {
  const _ResourceCostLine({
    required this.resource,
    required this.owned,
    required this.required,
  });

  final String resource;
  final int owned;
  final int required;

  @override
  Widget build(BuildContext context) {
    final ok = owned >= required;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Icon(_resourceIcon(resource), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(resource)),
          Text(
            '$owned / $required',
            style: TextStyle(
              color: ok ? null : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Fablab niveau ${gameState.fablabLevel}'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Cuisine', icon: Icon(Icons.soup_kitchen_outlined)),
              Tab(text: 'Atelier', icon: Icon(Icons.construction_outlined)),
              Tab(text: 'Recycleur', icon: Icon(Icons.recycling_outlined)),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              FablabCuisineView(gameState: gameState),
              _BuildingPlaceholder(
                icon: Icons.construction_outlined,
                title: 'Atelier',
                description:
                    'Débloqué au Cœur du Camp niveau ${fablabConfig.atelierUnlockCampHeartLevel}. Niveau actuel : $campHeartLevel. Gameplay à venir.',
              ),
              _BuildingPlaceholder(
                icon: Icons.recycling_outlined,
                title: 'Recycleur',
                description:
                    'Débloqué au Cœur du Camp niveau ${fablabConfig.recyclerUnlockCampHeartLevel}. Niveau actuel : $campHeartLevel. Gameplay à venir.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FablabCuisineView extends StatefulWidget {
  const FablabCuisineView({super.key, required this.gameState});

  final Zone0GameState gameState;

  @override
  State<FablabCuisineView> createState() => _FablabCuisineViewState();
}

class _FablabCuisineViewState extends State<FablabCuisineView> {
  String? _lastResult;

  @override
  Widget build(BuildContext context) {
    final organic = widget.gameState.resourceAmount('Organique');
    final canPrepare = organic >= fablabConfig.simpleMealOrganicCost &&
        widget.gameState.hasInventoryCapacityFor(
          <String, int>{'Repas simple': fablabConfig.simpleMealOutputAmount},
        );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Cuisine',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text('Niveau 1 · Eau disponible gratuitement.'),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _RecipeSlot(
                        label: 'Slot 1',
                        value:
                            '${fablabConfig.simpleMealOrganicCost} Organique',
                        icon: Icons.eco_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _RecipeSlot(
                        label: 'Slot 2',
                        value: 'Eau',
                        icon: Icons.water_drop_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Stock Organique : $organic'),
                Text(
                  'Résultat : ${fablabConfig.simpleMealOutputAmount} Repas simple',
                ),
                if (!canPrepare) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    organic < fablabConfig.simpleMealOrganicCost
                        ? 'Il manque ${fablabConfig.simpleMealOrganicCost - organic} Organique.'
                        : 'Inventaire plein : impossible de ranger le Repas simple.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: canPrepare
                      ? () {
                          final result = widget.gameState.prepareSimpleMeal();
                          setState(() => _lastResult = result.message);
                        }
                      : null,
                  icon: const Icon(Icons.restaurant_outlined),
                  label: const Text('Préparer'),
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
            ),
          ),
        ),
      ],
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
