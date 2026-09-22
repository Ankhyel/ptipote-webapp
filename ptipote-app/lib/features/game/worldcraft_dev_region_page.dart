import 'package:flutter/material.dart';

import '../figurines/ptipote_v2.dart';
import 'worldcraft_v2_service.dart';
import 'zone0_v2_camp_page.dart';
import 'zone0_v2_foundation.dart';
import 'zone0_v2_foundation_service.dart';

/// Temporary direct region picker. Walker travel intentionally does not exist
/// yet, so this page is explicit about being a DEV / prototype instrument.
class WorldcraftDevRegionPage extends StatefulWidget {
  const WorldcraftDevRegionPage({super.key});

  static const route = '/game/v2/worldcraft-region';

  @override
  State<WorldcraftDevRegionPage> createState() =>
      _WorldcraftDevRegionPageState();
}

class _WorldcraftDevRegionPageState extends State<WorldcraftDevRegionPage> {
  final _foundation = Zone0V2FoundationService();
  final _worldcraft = WorldcraftV2Service();
  Future<_WorldcraftSelectionData>? _data;
  String? _error;
  String? _creatingRegionId;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_WorldcraftSelectionData> _load() async {
    final foundation = await _foundation.load();
    if (foundation == null ||
        foundation['onboardingPtipote'] is! Map ||
        foundation['questionnaire'] is! Map) {
      throw StateError('Termine d’abord l’onboarding du premier P’TIPOTE.');
    }
    await _worldcraft.ensureWorld();
    final profile = PtipoteV2Profile.fromFirebase(
      '${foundation['firstPtipoteId'] ?? 'ptipote-v2'}',
      Map<String, dynamic>.from(foundation['onboardingPtipote'] as Map),
    );
    final questionnaire = RegionQuestionnaireResult.fromMap(
      Map<String, dynamic>.from(foundation['questionnaire'] as Map),
    );
    return _WorldcraftSelectionData(
      profile: profile,
      questionnaire: questionnaire,
      regions: await _worldcraft.loadWorldMapSummary(),
    );
  }

  Future<void> _createCamp(
    _WorldcraftSelectionData data,
    Map<String, dynamic> region,
  ) async {
    final regionId = '${region['id']}';
    setState(() {
      _creatingRegionId = regionId;
      _error = null;
    });
    try {
      final result = await _worldcraft.createCampInRegion(
        operationId: 'camp-$regionId-${DateTime.now().microsecondsSinceEpoch}',
        regionId: regionId,
      );
      await _foundation.saveWorldcraftCampSelection(
        questionnaire: data.questionnaire,
        firstPtipote: data.profile,
        worldId: '${result['worldId']}',
        regionId: '${result['regionId']}',
        campId: '${result['campId']}',
      );
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          Zone0V2CampPage.route,
          (route) => false,
        );
      }
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _creatingRegionId = null);
    }
  }

  Future<void> _inspectRegion(
    _WorldcraftSelectionData data,
    Map<String, dynamic> region,
  ) async {
    final occupied = region['campId'] != null;
    final biomes = (region['biomes'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((biome) => Map<String, dynamic>.from(biome))
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${region['displayCoordinate']} · ${region['profile']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(occupied
                  ? 'Camp présent : consultation uniquement.'
                  : 'Région libre : implantation de test disponible.'),
              const SizedBox(height: 12),
              ...biomes.map((biome) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.landscape_outlined),
                    title: Text('${biome['internalPosition'] ?? 'Biome'} · '
                        '${biome['biomeType'] ?? 'inconnu'}'),
                    subtitle: Text((biome['environmentalTags'] as List? ??
                            const <dynamic>[])
                        .join(' · ')),
                  )),
              if (!occupied)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _createCamp(data, region);
                    },
                    icon: const Icon(Icons.cabin),
                    label: const Text('Implanter le Camp'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_WorldcraftSelectionData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Région de départ')),
              body: Center(child: Text('${snapshot.error}')),
            );
          }
          final data = snapshot.requireData;
          return Scaffold(
            appBar: AppBar(title: const Text('PTIPOTE V2 · Région de départ')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'DEV / PROTOTYPE — Le Walker n’existe pas encore. '
                      'Choisis directement une Région libre pour implanter le Camp.',
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 8),
                Text('Carte mondiale de test',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.regions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: .88,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemBuilder: (context, index) {
                    final region = data.regions[index];
                    final occupied = region['campId'] != null;
                    final biomes =
                        (region['biomes'] as List? ?? const <dynamic>[])
                            .whereType<Map>()
                            .map((biome) => '${biome['biomeType'] ?? '?'}')
                            .join('\n');
                    final id = '${region['id']}';
                    return Material(
                      color: occupied
                          ? Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _creatingRegionId == null
                            ? () => _inspectRegion(data, region)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(children: <Widget>[
                                Icon(occupied ? Icons.cabin : Icons.public,
                                    size: 15),
                                const SizedBox(width: 3),
                                Text('${region['displayCoordinate']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                if (_creatingRegionId == id)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 3),
                                    child: SizedBox(
                                      width: 11,
                                      height: 11,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                              ]),
                              Text('${region['profile']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(biomes,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
}

class _WorldcraftSelectionData {
  const _WorldcraftSelectionData({
    required this.profile,
    required this.questionnaire,
    required this.regions,
  });

  final PtipoteV2Profile profile;
  final RegionQuestionnaireResult questionnaire;
  final List<Map<String, dynamic>> regions;
}
