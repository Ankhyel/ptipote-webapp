import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'camp_heart_config.dart';
import 'game_asset_resolver.dart';

class RefugePage extends StatefulWidget {
  const RefugePage({super.key});

  static const route = '/game';

  @override
  State<RefugePage> createState() => _RefugePageState();
}

class _RefugePageState extends State<RefugePage> {
  static final _campHeartState = CampHeartState.placeholder();

  final _assetResolver = GameAssetResolver();
  String? _refugeAsset;

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
    _warmAssets();
  }

  Future<void> _warmAssets() async {
    _refugeAsset = await _assetResolver.resolve('Camp');
    if (mounted) setState(() {});
  }

  void _openBuilding(_RefugeBuilding building) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (building.name == 'Maison') return const _MaisonPage();
          if (building.name == 'CampHeart') {
            return CampHeartPage(state: _campHeartState);
          }
          if (building.name == 'FabLab') return const FablabPage();
          return _GameBuildingPage(building: building);
        },
      ),
    );
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
                            onTap: () => _openBuilding(building),
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
  static final Map<String, int> _savedVitalityOverrides = <String, int>{};
  static final Map<String, PtipoteAutoAssignmentPreference>
      _savedAutoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};

  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  late final AnimationController _tickController;
  final Map<String, int> _vitalityOverrides = _savedVitalityOverrides;
  final Map<String, PtipoteAutoAssignmentPreference> _autoPreferenceOverrides =
      _savedAutoPreferenceOverrides;
  Timer? _vitalityRecoveryTimer;
  int _recoveryTick = 0;
  String? _selectedFigurineId;
  String? _trainingFigurineId;
  bool _choosingTrainingTarget = false;
  String? _maisonAsset;

  @override
  void initState() {
    super.initState();
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
    _tickController.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    _maisonAsset = await _assetResolver.resolve('Maison');
    if (mounted) setState(() {});
  }

  int _vitalityFor(PtipoteFigurine figurine) {
    return _vitalityOverrides[figurine.id] ?? figurine.vitality;
  }

  PtipoteAutoAssignmentPreference _autoPreferenceFor(
    PtipoteFigurine figurine,
  ) {
    return _autoPreferenceOverrides[figurine.id] ??
        figurine.autoAssignmentPreference;
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
      _vitalityOverrides[id] = math.max(0, current - 25);
      _selectedFigurineId = id;
    });
  }

  void _recoverVitalityStep() {
    if (!mounted || _vitalityOverrides.isEmpty) return;
    setState(() {
      _recoveryTick += 1;
      final vitalityUpdates = <String, int>{};
      final idsToClear = <String>[];
      for (final entry in _vitalityOverrides.entries) {
        final isResting =
            entry.value <= ptipoteStatsConfig.minVitalityBeforeAutoRest;
        if (!isResting && _recoveryTick.isOdd) continue;
        final nextVitality = math.min(
          ptipoteStatsConfig.maxVitality,
          entry.value + ptipoteStatsConfig.vitalityRecoveryPerMinute,
        );
        if (nextVitality >= ptipoteStatsConfig.maxVitality) {
          idsToClear.add(entry.key);
        } else {
          vitalityUpdates[entry.key] = nextVitality;
        }
      }
      _vitalityOverrides.addAll(vitalityUpdates);
      for (final id in idsToClear) {
        _vitalityOverrides.remove(id);
      }
    });
  }

  void _setAutoPreference(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) {
    setState(() {
      _autoPreferenceOverrides[figurine.id] = preference;
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
                            autoPreferenceFor: _autoPreferenceFor,
                            onToggleFigurine: _toggleFigurine,
                            onAutoPreferenceChanged: _setAutoPreference,
                          ),
                          _TrainingTool(
                            choosing: _choosingTrainingTarget,
                            hasTarget: _trainingFigurineId != null,
                            onChoose: () {
                              setState(() => _choosingTrainingTarget = true);
                            },
                            onTrain: () => _trainSelected(figurines),
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
}

class _BuildingHotspot extends StatelessWidget {
  const _BuildingHotspot({
    required this.building,
    required this.onTap,
    this.campHeartState,
  });

  final _RefugeBuilding building;
  final VoidCallback onTap;
  final CampHeartState? campHeartState;

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
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: building.name == 'CampHeart' && campHeartState != null
                ? _CampHeartHotspotContent(state: campHeartState!)
                : Center(
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
                  ),
          ),
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
                top: constraints.maxHeight * 0.15,
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
    required this.autoPreferenceFor,
    required this.onToggleFigurine,
    required this.onAutoPreferenceChanged,
  });

  final List<PtipoteFigurine> figurines;
  final Animation<double> animation;
  final String? selectedFigurineId;
  final String? trainingFigurineId;
  final bool choosingTrainingTarget;
  final int Function(PtipoteFigurine figurine) vitalityFor;
  final PtipoteAutoAssignmentPreference Function(PtipoteFigurine figurine)
      autoPreferenceFor;
  final ValueChanged<PtipoteFigurine> onToggleFigurine;
  final void Function(
    PtipoteFigurine figurine,
    PtipoteAutoAssignmentPreference preference,
  ) onAutoPreferenceChanged;

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
              widget.vitalityFor(figurine) <=
              ptipoteStatsConfig.minVitalityBeforeAutoRest,
        )
        .take(3)
        .toList();
    final active = widget.figurines
        .where(
          (figurine) =>
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
                    autoPreference: widget.autoPreferenceFor(figurine),
                    selected: widget.selectedFigurineId == figurine.id,
                    choosingTrainingTarget: widget.choosingTrainingTarget,
                    onTap: () => widget.onToggleFigurine(figurine),
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
                return Positioned(
                  left: alcoveCenter - spriteSize / 2,
                  top: constraints.maxHeight * 0.13,
                  width: spriteSize,
                  child: _PtipoteSpriteButton(
                    figurine: figurine,
                    vitality: widget.vitalityFor(figurine),
                    autoPreference: widget.autoPreferenceFor(figurine),
                    selected: widget.selectedFigurineId == figurine.id,
                    choosingTrainingTarget: widget.choosingTrainingTarget,
                    onTap: () => widget.onToggleFigurine(figurine),
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

class _PtipoteSpriteButton extends StatelessWidget {
  const _PtipoteSpriteButton({
    required this.figurine,
    required this.vitality,
    required this.autoPreference,
    required this.selected,
    required this.choosingTrainingTarget,
    required this.onTap,
    required this.onAutoPreferenceChanged,
  });

  final PtipoteFigurine figurine;
  final int vitality;
  final PtipoteAutoAssignmentPreference autoPreference;
  final bool selected;
  final bool choosingTrainingTarget;
  final VoidCallback onTap;
  final ValueChanged<PtipoteAutoAssignmentPreference> onAutoPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          _PtipoteSprite(figurine: figurine),
          if (selected)
            Positioned(
              bottom: 76,
              child: _PtipoteInfoBubble(
                figurine: figurine,
                vitality: vitality,
                autoPreference: autoPreference,
                onAutoPreferenceChanged: onAutoPreferenceChanged,
              ),
            ),
          if (choosingTrainingTarget)
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
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates();
  }

  @override
  void didUpdateWidget(covariant _PtipoteSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figurine.type != widget.figurine.type ||
        oldWidget.figurine.species != widget.figurine.species) {
      _candidates = _buildCandidates();
      _index = 0;
    }
  }

  List<String> _buildCandidates() {
    final names = <String>{
      widget.figurine.type.trim(),
      widget.figurine.species.trim(),
    }..removeWhere((value) => value.isEmpty || value == '-');

    final urls = <String>[];
    for (final name in names) {
      for (final ext in _extensions) {
        urls.add('$_baseUrl/${Uri.encodeComponent(name)}.$ext');
      }
    }
    urls.add('$_baseUrl/bplaceholder.png');
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final url = _candidates[_index.clamp(0, _candidates.length - 1)];
    return SizedBox(
      height: 82,
      child: Image.network(
        url,
        fit: BoxFit.contain,
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
    required this.autoPreference,
    required this.onAutoPreferenceChanged,
  });

  final PtipoteFigurine figurine;
  final int vitality;
  final PtipoteAutoAssignmentPreference autoPreference;
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
            _InfoLine(label: 'Niveau', value: figurine.level),
            _InfoLine(
              label: 'XP',
              value: '${figurine.xp}/${figurine.xpRequiredForNextLevel}',
            ),
            _InfoLine(
              label: 'Vitalité',
              value: '$vitality/${figurine.maxVitality}',
            ),
            _InfoLine(label: 'Bonheur', value: '${figurine.happiness}/100'),
            _InfoLine(label: 'État', value: _stateLabel(figurine, vitality)),
            _InfoLine(label: 'Auto', value: _preferenceLabel(autoPreference)),
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

class CampHeartState extends ChangeNotifier {
  CampHeartState({
    required this.campHeartLevel,
    required this.vegetalizationXp,
    required this.totalVegetalizationInvested,
    required this.placeholderOrganicStock,
  });

  factory CampHeartState.placeholder() {
    return CampHeartState(
      campHeartLevel: 1,
      vegetalizationXp: 0,
      totalVegetalizationInvested: 0,
      placeholderOrganicStock: 25,
    );
  }

  int campHeartLevel;
  int vegetalizationXp;
  int totalVegetalizationInvested;
  int placeholderOrganicStock;

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

  bool get canDepositOrganic {
    return !isMaxLevel && placeholderOrganicStock > 0;
  }

  String depositOrganic(int requestedAmount) {
    if (isMaxLevel) return 'Le Cœur du Camp est au niveau max V1.';
    final amount = math.min(requestedAmount, placeholderOrganicStock);
    if (amount <= 0) return 'Stock Organique placeholder vide.';

    placeholderOrganicStock -= amount;
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
    return levelUpMessage ?? '+$amount Organique investi.';
  }
}

class CampHeartPage extends StatefulWidget {
  const CampHeartPage({super.key, required this.state});

  final CampHeartState state;

  @override
  State<CampHeartPage> createState() => _CampHeartPageState();
}

class _CampHeartPageState extends State<CampHeartPage> {
  void _deposit(int amount) {
    final message = widget.state.depositOrganic(amount);
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
    required this.onDeposit,
  });

  final CampHeartState state;
  final ValueChanged<int> onDeposit;

  @override
  Widget build(BuildContext context) {
    final maxAmount = state.placeholderOrganicStock;
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
              'Stock Organique placeholder : $maxAmount',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stock réel non branché : cette réserve sert seulement à tester la jauge V1.',
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
                  onPressed: state.canDepositOrganic
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
          'À venir : branchement du stock Organique réel, Marché, Tour, Lisière lointaine, bonheur global du refuge et limite effective des P’TIPOTES actifs.',
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

class FablabPage extends StatelessWidget {
  const FablabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('La FabLab'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Atelier', icon: Icon(Icons.construction_outlined)),
              Tab(text: 'Cuisine', icon: Icon(Icons.soup_kitchen_outlined)),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: <Widget>[
              _BuildingPlaceholder(
                icon: Icons.construction_outlined,
                title: 'Atelier',
                description:
                    'Préparation future des assemblages, plans et objets du refuge.',
              ),
              _BuildingPlaceholder(
                icon: Icons.soup_kitchen_outlined,
                title: 'Cuisine',
                description:
                    'Préparation future des repas, soins et recettes simples.',
              ),
            ],
          ),
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
