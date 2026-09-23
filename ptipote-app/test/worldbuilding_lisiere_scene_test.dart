import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/ptipote_image.dart';
import 'package:ptipote_app/features/figurines/ptipote_v2.dart';
import 'package:ptipote_app/features/game/lisiere_v2.dart';
import 'package:ptipote_app/features/game/lisiere_v2_page.dart';

void main() {
  test('la géométrie garde les Parcelles dans la scène et détourne un obstacle',
      () {
    const size = Size(390, 207);
    const geometry = WorldbuildingSceneGeometry(size);
    for (var ordinal = 0; ordinal < 9; ordinal += 1) {
      expect(geometry.isWalkable(geometry.parcelAnchor(ordinal)), isTrue);
    }
    expect(
      geometry.route(const Offset(110, 52), const Offset(375, 52)).length,
      greaterThan(2),
    );
  });

  testWidgets('la fixture Lisière reste lisible sur un écran mobile 390×844',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var harvestStarts = 0;
    var harvestStops = 0;
    String? selectedParcelId;
    final graph = createBiomeParcelGraph(biomeId: 'fixture', seed: 123);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorldbuildingParcelScene(
          biome: const <String, dynamic>{
            'biomeType': 'mangrove',
            'visualProfile': <String, dynamic>{'groundSet': 'wet_roots'},
          },
          parcels: graph.parcels,
          nodes: <LisiereResourceNode>[
            LisiereResourceNode.organic(
              id: 'organic',
              parcelId: 'fixture',
              maxResistance: 3,
              standardYield: 2,
              visualVariant: '🌱',
            ),
            LisiereResourceNode.mineral(
              id: 'mineral',
              parcelId: 'fixture',
              maxResistance: 3,
              standardYield: 2,
              remainingLayers: 1,
              visualVariant: '🪨',
            ),
          ],
          ptipotes: const <PtipoteV2Profile>[
            PtipoteV2Profile(
              ptipoteId: 'fixture-ptipote',
              acquisitionOrigin: PtipoteAcquisitionOrigin.digitalAdoption,
              ownershipMode: PtipoteOwnershipMode.owned,
              ptipoteGeneration: PtipoteGeneration.vestige,
              typeId: PtipoteTypeId.vegetal,
              natureId: 'mousse',
            ),
          ],
          ptibugIcons: const <String>['🐞'],
          active: true,
          onParcelTap: (parcel) => selectedParcelId = parcel.id,
          onNodeTapDown: (_) => harvestStarts += 1,
          onNodeTapUp: () => harvestStops += 1,
        ),
      ),
    ));

    expect(find.text('mangrove · parcelle active'), findsOneWidget);
    expect(find.text('🌱'), findsOneWidget);
    expect(find.text('🪨'), findsOneWidget);
    expect(find.text('🌳'), findsOneWidget);
    expect(find.text('⌖'), findsOneWidget);
    expect(find.text('🐞'), findsOneWidget);
    expect(find.byType(PtipoteImage), findsOneWidget);

    final press = await tester.startGesture(tester.getCenter(find.text('🌱')));
    expect(harvestStarts, 1);
    await press.up();
    expect(harvestStops, 1);

    await tester.tap(find.byKey(ValueKey<String>(
        'parcel-marker-${graph.parcels[1].id}')));
    expect(selectedParcelId, graph.parcels[1].id);
  });
}
