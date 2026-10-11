import 'package:flutter_test/flutter_test.dart';
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

  test('le HUD environnement utilise une échelle de jeu de 1 à 5', () {
    expect(ElevagePresentation.environmentScale(-4), 1);
    expect(ElevagePresentation.environmentScale(-1), 2);
    expect(ElevagePresentation.environmentScale(0), 3);
    expect(ElevagePresentation.environmentScale(1), 4);
    expect(ElevagePresentation.environmentScale(6), 5);
  });
}
