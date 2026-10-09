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
}
