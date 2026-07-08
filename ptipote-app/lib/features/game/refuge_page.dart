import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import 'game_asset_resolver.dart';

class RefugePage extends StatefulWidget {
  const RefugePage({super.key});

  static const route = '/game';

  @override
  State<RefugePage> createState() => _RefugePageState();
}

class _RefugePageState extends State<RefugePage>
    with SingleTickerProviderStateMixin {
  final _assetResolver = GameAssetResolver();
  final _figurineService = FigurineService();
  late final AnimationController _walkController;
  String? _refugeAsset;
  String? _selectedFigurineId;

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
      left: 0.50,
      top: 0.54,
      width: 0.34,
      height: 0.12,
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
    _walkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _warmAssets();
  }

  @override
  void dispose() {
    _walkController.dispose();
    super.dispose();
  }

  Future<void> _warmAssets() async {
    _refugeAsset = await _assetResolver.resolve('Refuge');
    if (mounted) setState(() {});
  }

  void _openBuilding(_RefugeBuilding building) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => building.name == 'FabLab'
            ? const FablabPage()
            : _GameBuildingPage(building: building),
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
                          const _MissingGameImage(screenName: 'Refuge'),
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
                        const _AlcoveLayer(),
                        const _FloorLayer(),
                        ..._buildings.map(
                          (building) => _BuildingHotspot(
                            building: building,
                            onTap: () => _openBuilding(building),
                          ),
                        ),
                        StreamBuilder<List<PtipoteFigurine>>(
                          stream: _figurineService.watchMyFigurines(),
                          builder: (context, snapshot) {
                            final figurines =
                                snapshot.data ?? const <PtipoteFigurine>[];
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                figurines.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (figurines.isEmpty) {
                              return const _RefugeEmptyState();
                            }
                            return _PtipoteRefugeLayer(
                              figurines: figurines,
                              animation: _walkController,
                              selectedFigurineId: _selectedFigurineId,
                              onToggleFigurine: (figurine) {
                                setState(() {
                                  _selectedFigurineId =
                                      _selectedFigurineId == figurine.id
                                          ? null
                                          : figurine.id;
                                });
                              },
                            );
                          },
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

class _BuildingHotspot extends StatelessWidget {
  const _BuildingHotspot({required this.building, required this.onTap});

  final _RefugeBuilding building;
  final VoidCallback onTap;

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
            child: Center(
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

class _PtipoteRefugeLayer extends StatelessWidget {
  const _PtipoteRefugeLayer({
    required this.figurines,
    required this.animation,
    required this.selectedFigurineId,
    required this.onToggleFigurine,
  });

  final List<PtipoteFigurine> figurines;
  final Animation<double> animation;
  final String? selectedFigurineId;
  final ValueChanged<PtipoteFigurine> onToggleFigurine;

  @override
  Widget build(BuildContext context) {
    final resting =
        figurines.where((figurine) => figurine.vitality <= 0).take(3).toList();
    final active =
        figurines.where((figurine) => figurine.vitality > 0).toList();

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final spriteSize = (constraints.maxWidth * 0.18).clamp(56.0, 86.0);
          return Stack(
            children: <Widget>[
              ...List<Widget>.generate(active.length, (index) {
                final figurine = active[index];
                final laneProgress = (animation.value + index * 0.22) % 1.0;
                final left = constraints.maxWidth -
                    laneProgress * (constraints.maxWidth + spriteSize);
                final bottom =
                    constraints.maxHeight * (0.08 + (index % 3) * 0.055);
                return Positioned(
                  left: left,
                  bottom: bottom,
                  width: spriteSize,
                  child: _PtipoteSpriteButton(
                    figurine: figurine,
                    selected: selectedFigurineId == figurine.id,
                    onTap: () => onToggleFigurine(figurine),
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
                    selected: selectedFigurineId == figurine.id,
                    onTap: () => onToggleFigurine(figurine),
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

class _PtipoteSpriteButton extends StatelessWidget {
  const _PtipoteSpriteButton({
    required this.figurine,
    required this.selected,
    required this.onTap,
  });

  final PtipoteFigurine figurine;
  final bool selected;
  final VoidCallback onTap;

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
              child: _PtipoteInfoBubble(figurine: figurine),
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
  const _PtipoteInfoBubble({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 210,
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
            _InfoLine(label: 'Surnom', value: figurine.displayName),
            _InfoLine(label: 'Niveau', value: figurine.level),
            _InfoLine(label: 'Énergie', value: figurine.energy),
            _InfoLine(label: 'XP', value: figurine.xp),
            _InfoLine(
              label: 'Vitalité',
              value: '${figurine.vitality}/${figurine.maxVitality}',
            ),
          ],
        ),
      ),
    );
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
      'Lisiere' => 'Exploration future des biomes proches et lointains.',
      'Tour' => 'Sécurité, stabilité et protection future du refuge.',
      'FabLab' => 'Accès aux espaces Atelier et Cuisine.',
      _ => 'Écran placeholder prêt à recevoir ses futures fonctions.',
    };
  }
}
