import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/zone0_game_state.dart';

void main() {
  test('le Kit de réparation est réservé à la boutique du foyer', () {
    final home = MarketShop(id: 'home', specialization: 'home');
    final equipment = MarketShop(id: 'equipment', specialization: 'equipment');

    expect(home.accepts('Kit de réparation domestique'), isTrue);
    expect(equipment.accepts('Kit de réparation domestique'), isFalse);
  });

  test('les installations structurelles restent dans la boutique du foyer', () {
    final home = MarketShop(id: 'home', specialization: 'home');
    final equipment = MarketShop(id: 'equipment', specialization: 'equipment');

    for (final item in <String>[
      'Chloro-canaux',
      'Installation filtrante',
    ]) {
      expect(home.accepts(item), isTrue);
      expect(equipment.accepts(item), isFalse);
    }
  });
}
