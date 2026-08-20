import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/ptipote_v2.dart';

void main() {
  PtipoteEnvelopeSymbiosis symbiosis({
    int level = 0,
    double progress = 0,
    DateTime? at,
  }) {
    final timestamp = at ?? DateTime.utc(2026, 8, 12);
    return PtipoteEnvelopeSymbiosis(
      envelopeId: 'exploration',
      symbiosisLevel: level,
      symbiosisProgressPercent: progress,
      startedAt: timestamp,
      lastCalculatedAt: timestamp,
    );
  }

  group('Envelope Symbiosis', () {
    test('preserves fractional offline time', () {
      final start = DateTime.utc(2026, 8, 12);
      final result = EnvelopeSymbiosisService.resolveTime(
        symbiosis(at: start),
        config: defaultPtipoteV2Config,
        now: start.add(const Duration(minutes: 30)),
      );

      expect(result.symbiosisProgressPercent, 0.5);
      expect(result.symbiosisLevel, 0);
    });

    test('retains surplus while crossing a symbiosis tier', () {
      final start = DateTime.utc(2026, 8, 12);
      final result = EnvelopeSymbiosisService.addActivity(
        symbiosis(progress: 99.5, at: start),
        config: defaultPtipoteV2Config,
        now: start,
      );

      expect(result.symbiosisLevel, 1);
      expect(result.symbiosisProgressPercent, 0.5);
      expect(result.maxLevelReached, isFalse);
    });

    test('caps after its second completed tier at 125 percent', () {
      final start = DateTime.utc(2026, 8, 12);
      final result = EnvelopeSymbiosisService.resolveTime(
        symbiosis(progress: 90, at: start),
        config: defaultPtipoteV2Config,
        now: start.add(const Duration(hours: 210)),
      );
      final profile = PtipoteV2Profile(
        ptipoteId: 'protocol',
        acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
        ownershipMode: PtipoteOwnershipMode.coBred,
        ptipoteGeneration: PtipoteGeneration.protocol,
        typeId: PtipoteTypeId.vegetal,
        natureId: 'liane',
        envelopeId: 'exploration',
        envelopeSymbiosis: result,
      );

      expect(result.symbiosisLevel, 2);
      expect(result.maxLevelReached, isTrue);
      expect(result.symbiosisProgressPercent, 0);
      expect(profile.effectiveProtocolEfficiency(defaultPtipoteV2Config), 1.25);
    });

    test('a core without envelope remains at 50 percent efficiency', () {
      const profile = PtipoteV2Profile(
        ptipoteId: 'core',
        acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
        ownershipMode: PtipoteOwnershipMode.coBred,
        ptipoteGeneration: PtipoteGeneration.protocol,
        typeId: PtipoteTypeId.mineral,
        natureId: 'cristal',
      );

      expect(profile.effectiveProtocolEfficiency(defaultPtipoteV2Config), 0.5);
    });

    test('migrates the former Scientifique envelope to an Analyste variant',
        () {
      final profile = PtipoteV2Profile.fromFirebase(
        'legacy-analyst',
        <String, dynamic>{
          'ptipoteGeneration': 'protocol',
          'envelopeId': 'Scientifique',
          'natureId': 'liane',
        },
      );

      expect(profile.envelopeId, 'scientist_share');
      expect(profile.envelopeSymbiosis, isNotNull);
    });
  });
}
