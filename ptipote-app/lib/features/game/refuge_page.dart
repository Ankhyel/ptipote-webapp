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
    _warmAssets();
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
                        ..._buildings.map(
                          (building) => _BuildingHotspot(
                            building: building,
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
