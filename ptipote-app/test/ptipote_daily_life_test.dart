import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/ptipote_daily_life.dart';

void main() {
  group('PtipoteDailyLifeConfig', () {
    const config = PtipoteDailyLifeConfig();

    test('grows capacities without treating a level as an instant refill', () {
      expect(config.maxEnergyForLevel(100, 1), 100);
      expect(config.maxEnergyForLevel(100, 4), 145);
      expect(config.maxHungerForLevel(100, 4), 115);
    });

    test('maps vital happiness from percentages', () {
      expect(config.vitalBonusFor(29, 100), 0);
      expect(config.vitalBonusFor(30, 100), 5);
      expect(config.vitalBonusFor(70, 100), 10);
    });

    test('uses the agreed artisan and vendor formulas', () {
      expect(config.artisanReduction(2, 6), closeTo(.16, .0001));
      expect(config.vendorBonus(2, 4), closeTo(.14, .0001));
    });
  });
}
