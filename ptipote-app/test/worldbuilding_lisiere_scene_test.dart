import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/lisiere_v2.dart';
import 'package:ptipote_app/features/game/lisiere_v2_page.dart';

void main() {
  testWidgets('la fixture Lisière reste lisible sur un écran mobile 390×844',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          ptipotes: const [],
          ptibugIcons: const <String>['🐞'],
          active: true,
        ),
      ),
    ));

    expect(find.text('mangrove · parcelle active'), findsOneWidget);
    expect(find.text('🌱'), findsOneWidget);
    expect(find.text('🪨'), findsOneWidget);
    expect(find.text('🌳'), findsOneWidget);
    expect(find.text('⌖'), findsOneWidget);
    expect(find.text('🐞'), findsOneWidget);
  });
}
