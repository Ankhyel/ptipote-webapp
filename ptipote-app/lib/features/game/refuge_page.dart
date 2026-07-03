import 'package:flutter/material.dart';

import 'game_asset_resolver.dart';

class RefugePage extends StatefulWidget {
  const RefugePage({super.key});

  static const route = '/game';

  @override
  State<RefugePage> createState() => _RefugePageState();
}

class _RefugePageState extends State<RefugePage> {
  final _assetResolver = GameAssetResolver();
  final Map<String, String?> _assetsByScreen = <String, String?>{};
  String _screen = 'Refuge';

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
      left: 0.22,
      top: 0.72,
      width: 0.32,
      height: 0.11,
    ),
    _RefugeBuilding(
      name: 'Atelier',
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
    for (final screenName in <String>{
      'Refuge',
      'Kernel',
      'Maison',
      ..._buildings.map((building) => building.name),
    }) {
      _assetsByScreen[screenName] = await _assetResolver.resolve(screenName);
    }
    if (mounted) setState(() {});
  }

  void _openBuilding(String name) {
    setState(() => _screen = _assetsByScreen[name] == null ? 'Refuge' : name);
  }

  @override
  Widget build(BuildContext context) {
    final currentAsset = _assetsByScreen[_screen] ?? _assetsByScreen['Refuge'];

    return Scaffold(
      appBar: AppBar(title: Text(_screen == 'Refuge' ? 'Jeu' : _screen)),
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
                        if (currentAsset != null)
                          Image.asset(
                            currentAsset,
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
                        if (_screen == 'Refuge')
                          ..._buildings.map(
                            (building) => _BuildingHotspot(
                              building: building,
                              onTap: () => _openBuilding(building.name),
                            ),
                          )
                        else
                          _ScreenActions(
                            screen: _screen,
                            onBackToRefuge: () =>
                                setState(() => _screen = 'Refuge'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_screen == 'Refuge')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Prototype dev : tape un bâtiment pour ouvrir son écran. '
                  'Les images sont résolues par nom, quelle que soit leur extension.',
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
                building.name,
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

class _ScreenActions extends StatelessWidget {
  const _ScreenActions({required this.screen, required this.onBackToRefuge});

  final String screen;
  final VoidCallback onBackToRefuge;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Card(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                screen,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(_descriptionFor(screen)),
              const SizedBox(height: 12),
              if (screen == 'Kernel') ...<Widget>[
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
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: onBackToRefuge,
                child: const Text('Retour refuge'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionFor(String screen) {
    return switch (screen) {
      'Kernel' => 'Centre du refuge : scan, messages système et plans futurs.',
      'Maison' => 'Refuge des P’TIPOTES : repos, soins et inventaire vivant.',
      _ => 'Écran placeholder prêt à recevoir ses futures fonctions.',
    };
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
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String name;
  final double left;
  final double top;
  final double width;
  final double height;
}
