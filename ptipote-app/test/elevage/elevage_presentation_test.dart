import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/elevage/elevage_config.dart';
import 'package:ptipote_app/features/elevage/elevage_presentation.dart';

void main() {
  test('les IDs Elevage sont localisés pour le joueur', () {
    expect(ElevagePresentation.itemLabel('ROOT'), 'Racine');
    expect(ElevagePresentation.itemLabel('FRUIT_JELLY'), 'Jelly fruité');
    expect(ElevagePresentation.itemCategory('IRON'), 'Matériaux');
  });

  test('les retours émotionnels n’exposent pas les IDs techniques', () {
    final feedback = ElevagePresentation.reactionFeedback('RUSH_SHAKE', 'Noma');
    expect(feedback, contains('Noma'));
    expect(feedback, isNot(contains('RUSH_SHAKE')));
  });

  test('le HUD environnement conserve l’échelle métier directe de 0 à 5', () {
    expect(ElevagePresentation.environmentScale(-4), 0);
    expect(ElevagePresentation.environmentScale(-1), 0);
    expect(ElevagePresentation.environmentScale(0), 0);
    expect(ElevagePresentation.environmentScale(2), 2);
    expect(ElevagePresentation.environmentScale(6), 5);
  });

  test(
      'les fiches installation lisent description, production et impacts de la config',
      () {
    final basin = defaultElevageConfig.installation('BASSIN')!;
    expect(basin.description, contains('algues'));
    expect(basin.outputs, <String, int>{'ALGAE': 1, 'MOSS': 1});
    expect(basin.humidity, 2);
    expect(ElevagePresentation.environmentScale(basin.humidity), 2);
  });
}
