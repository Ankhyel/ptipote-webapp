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
  State<WorldcraftDevRegionPage> createState() => _WorldcraftDevRegionPageState();
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
      regions: await _worldcraft.loadRegions(),
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

  @override
  Widget build(BuildContext context) => FutureBuilder<_WorldcraftSelectionData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 8),
                ...data.regions.map((region) {
                  final occupied = region['campId'] != null;
                  final id = '${region['id']}';
                  return Card(
                    child: ListTile(
                      leading: Icon(occupied ? Icons.cabin : Icons.public),
                      title: Text('${region['displayCoordinate']} · ${region['profile']}'),
                      subtitle: Text(occupied
                          ? 'Camp présent · implantation indisponible'
                          : 'Région libre · 5 biomes partagés'),
                      trailing: _creatingRegionId == id
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton(
                              onPressed: occupied
                                  ? null
                                  : () => _createCamp(data, region),
                              child: const Text('Implanter'),
                            ),
                    ),
                  );
                }),
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
