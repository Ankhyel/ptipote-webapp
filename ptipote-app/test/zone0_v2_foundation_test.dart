import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/zone0_v2_foundation.dart';

void main() {
  test('the eight questionnaire combinations distribute two wins per region',
      () {
    final wins = <RegionPresetId, int>{
      for (final region in RegionPresetId.values) region: 0,
    };
    for (final q1 in RegionQuestionOneAnswer.values) {
      for (final q2 in RegionQuestionTwoAnswer.values) {
        for (final q3 in RegionQuestionThreeAnswer.values) {
          final result = calculateRegionQuestionnaire(
            q1: q1,
            q2: q2,
            q3: q3,
            completedAt: DateTime.utc(2026),
          );
          wins[result.selectedRegionPresetId] =
              wins[result.selectedRegionPresetId]! + 1;
        }
      }
    }
    expect(wins.values, everyElement(2));
  });

  test('the third answer resolves each possible tie deterministically', () {
    final field = calculateRegionQuestionnaire(
      q1: RegionQuestionOneAnswer.mer,
      q2: RegionQuestionTwoAnswer.neige,
      q3: RegionQuestionThreeAnswer.champ,
      completedAt: DateTime.utc(2026),
    );
    final shells = calculateRegionQuestionnaire(
      q1: RegionQuestionOneAnswer.montagne,
      q2: RegionQuestionTwoAnswer.neige,
      q3: RegionQuestionThreeAnswer.coquillages,
      completedAt: DateTime.utc(2026),
    );
    expect(field.selectedRegionPresetId, RegionPresetId.hautesTerres);
    expect(shells.selectedRegionPresetId, RegionPresetId.bassesEaux);
  });

  test('a questionnaire result keeps answers, score and version persistently',
      () {
    final result = calculateRegionQuestionnaire(
      q1: RegionQuestionOneAnswer.mer,
      q2: RegionQuestionTwoAnswer.soleil,
      q3: RegionQuestionThreeAnswer.champ,
      completedAt: DateTime.utc(2026, 1, 2),
    );
    final restored = RegionQuestionnaireResult.fromMap(result.toMap());
    expect(restored.q1Answer, result.q1Answer);
    expect(restored.q2Answer, result.q2Answer);
    expect(restored.q3Answer, result.q3Answer);
    expect(restored.scoresByRegion, result.scoresByRegion);
    expect(restored.selectedRegionPresetId, result.selectedRegionPresetId);
    expect(restored.algorithmVersion, zone0V2WorldVersion);
  });

  test('each regional preset creates five stable, connected biomes', () {
    for (final preset in RegionPresetId.values) {
      final first = createRegionBiomeInstances(
        regionId: 'region-1',
        presetId: preset,
        seed: 42,
        createdAt: DateTime.utc(2026),
      );
      final second = createRegionBiomeInstances(
        regionId: 'region-1',
        presetId: preset,
        seed: 42,
        createdAt: DateTime.utc(2026),
      );
      expect(first, hasLength(5));
      expect(first.map((biome) => biome.id).toSet(), hasLength(5));
      expect(first.map((biome) => biome.id), second.map((biome) => biome.id));
      expect(
        first.where((biome) => biome.unlocked),
        hasLength(3),
      );
      for (final biome in first) {
        expect(
          biome.connectedBiomeIds.every(
            (id) => first.any((candidate) => candidate.id == id),
          ),
          isTrue,
        );
      }
    }
  });
}
