import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/ptipote_image.dart';
import 'package:ptipote_app/features/figurines/ptipote_v2.dart';
import 'package:ptipote_app/features/game/lisiere_v2.dart';
import 'package:ptipote_app/features/game/lisiere_v2_page.dart';

void main() {
  testWidgets('la fixture Lisière reste lisible sur un écran mobile 390×844',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var harvestStarts = 0;
    var harvestStops = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorldbuildingParcelScene(
          biome: const <String, dynamic>{
            'biomeType': 'mangrove',
            'visualProfile': <String, dynamic>{'groundSet': 'wet_roots'},
          },
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
  });
}
