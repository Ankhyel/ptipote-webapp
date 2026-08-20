import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/co_breeding.dart';
import 'package:ptipote_app/features/figurines/ptipote_v2.dart';

void main() {
  group('Co-élevage', () {
    test('Protocol offers use concrete cores and all source envelopes', () {
      expect(defaultCoBreedingProtocols, hasLength(9));
      expect(defaultCoBreedingEnvelopeTemplates, hasLength(8));
      for (final protocol in defaultCoBreedingProtocols) {
        expect(protocol.coreId, isNotNull);
        expect(protocol.compatibleEnvelopeIds, hasLength(8));
      }
      expect(
        defaultCoBreedingProtocols
            .where((item) => item.typeId == PtipoteTypeId.vegetal),
        hasLength(3),
      );
      expect(
        defaultCoBreedingProtocols
            .where((item) => item.typeId == PtipoteTypeId.mycelial),
        hasLength(3),
      );
      expect(
        defaultCoBreedingProtocols
            .where((item) => item.typeId == PtipoteTypeId.mineral),
        hasLength(3),
      );
    });

    test('capacity follows breeder level', () {
      expect(getCoBreedingCapacity(1, defaultCoBreedingConfig), 1);
      expect(getCoBreedingCapacity(2, defaultCoBreedingConfig), 2);
      expect(getCoBreedingCapacity(4, defaultCoBreedingConfig), 4);
      expect(
        getCoBreedingCapacity(
          4,
          const CoBreedingConfig(capacityPerBreederLevel: 3),
        ),
        4,
      );
    });

    test('a selection imposes the configured 24-hour cooldown', () {
      final selectedAt = DateTime.utc(2026, 8, 14, 10);
      expect(
        coBreedingSelectionCooldownFor(
          lastSelectionAt: selectedAt,
          config: defaultCoBreedingConfig,
          now: selectedAt.add(const Duration(hours: 23)),
        ),
        const Duration(hours: 1),
      );
      expect(
        coBreedingSelectionCooldownFor(
          lastSelectionAt: selectedAt,
          config: defaultCoBreedingConfig,
          now: selectedAt.add(const Duration(hours: 24)),
        ),
        Duration.zero,
      );
    });

    test('final offline protection preserves one 24-hour return window', () {
      final start = DateTime.utc(2026, 1, 1);
      final session = CoBreedingSession(
        sessionId: 'session',
        ptipoteId: 'ptipote',
        selectionMode: CoBreedingSelectionMode.randomFreeOffer,
        typeId: PtipoteTypeId.vegetal,
        ptipoteTemplateId: 'vestige-liane',
        startedAt: start,
        expiresAt: start.add(const Duration(hours: 41)),
        initialDurationSeconds: const Duration(hours: 41).inSeconds,
        remainingSeconds: const Duration(hours: 41).inSeconds,
        lastPlayerActiveAt: start,
      );
      final protected = CoBreedingTimeService.resolve(
        session,
        config: defaultCoBreedingConfig,
        now: start.add(const Duration(hours: 72)),
      );
      expect(protected.remainingSeconds, const Duration(hours: 24).inSeconds);
      expect(protected.finalWindowProtectionConsumed, isTrue);

      final resumed = CoBreedingTimeService.resolve(
        protected,
        config: defaultCoBreedingConfig,
        now: start.add(const Duration(hours: 73)),
      );
      expect(resumed.remainingSeconds, const Duration(hours: 23).inSeconds);
    });

    test('short absence in final window deducts normally', () {
      final start = DateTime.utc(2026, 1, 1);
      final session = CoBreedingSession(
        sessionId: 'session',
        ptipoteId: 'ptipote',
        selectionMode: CoBreedingSelectionMode.randomFreeOffer,
        typeId: PtipoteTypeId.mineral,
        ptipoteTemplateId: 'vestige-cristal',
        startedAt: start,
        expiresAt: start.add(const Duration(hours: 30)),
        initialDurationSeconds: const Duration(hours: 30).inSeconds,
        remainingSeconds: const Duration(hours: 30).inSeconds,
        lastPlayerActiveAt: start,
      );
      final resolved = CoBreedingTimeService.resolve(
        session,
        config: defaultCoBreedingConfig,
        now: start.add(const Duration(hours: 2)),
      );
      expect(resolved.remainingSeconds, const Duration(hours: 28).inSeconds);
      expect(resolved.finalWindowProtectionConsumed, isFalse);
    });

    test('resolving the same instant is a no-op', () {
      final start = DateTime.utc(2026, 1, 1);
      final session = CoBreedingSession(
        sessionId: 'stable-session',
        ptipoteId: 'ptipote',
        selectionMode: CoBreedingSelectionMode.randomFreeOffer,
        typeId: PtipoteTypeId.vegetal,
        ptipoteTemplateId: 'vestige-liane',
        startedAt: start,
        expiresAt: start.add(const Duration(days: 7)),
        initialDurationSeconds: const Duration(days: 7).inSeconds,
        remainingSeconds: const Duration(days: 7).inSeconds,
        lastPlayerActiveAt: start,
      );

      expect(
        identical(
          CoBreedingTimeService.resolve(
            session,
            config: defaultCoBreedingConfig,
            now: start,
          ),
          session,
        ),
        isTrue,
      );
    });

    test('level cap marks a session pending without deleting it', () {
      final start = DateTime.utc(2026, 1, 1);
      final session = CoBreedingSession(
        sessionId: 'session',
        ptipoteId: 'ptipote',
        selectionMode: CoBreedingSelectionMode.paidTypeChoice,
        typeId: PtipoteTypeId.mycelial,
        ptipoteTemplateId: 'vestige-mycelle',
        startedAt: start,
        expiresAt: start.add(const Duration(days: 7)),
        initialDurationSeconds: const Duration(days: 7).inSeconds,
        remainingSeconds: const Duration(days: 7).inSeconds,
        lastPlayerActiveAt: start,
      );
      final pending = CoBreedingTimeService.markLevelCap(
        session,
        now: start,
      );
      expect(pending.departurePending, isTrue);
      expect(pending.status, CoBreedingSessionStatus.departurePending);
      expect(
          pending.departureReason, CoBreedingDepartureReason.levelCapReached);
      expect(pending.departurePendingAt, start);
    });

    test('a completion reward preserves its source session and target rule',
        () {
      final createdAt = DateTime.utc(2026, 8, 12);
      final reward = CoBreedingXpReward(
        itemId: 'co-xp-session-a',
        compatibleTypeId: PtipoteTypeId.mycelial,
        xpAmount: 35,
        sourceSessionId: 'session-a',
        sourcePtipoteId: 'co-a',
        createdAt: createdAt,
      );
      final consumed = reward.consume('owned-mycelle', createdAt);

      expect(reward.isConsumed, isFalse);
      expect(consumed.isConsumed, isTrue);
      expect(consumed.sourceSessionId, 'session-a');
      expect(consumed.compatibleTypeId, PtipoteTypeId.mycelial);
      expect(consumed.consumedByPtipoteId, 'owned-mycelle');
    });

    test('completion rewards scale only from the final level', () {
      final rewards = CoBreedingCompletionService.rewardsFor(
        config: defaultPtipoteV2Config,
        finalLevel: 7,
      );

      expect(rewards.ptipoteXp, 45);
      expect(rewards.breederXp, 26);
      expect(rewards.kernelTrust, 8);
    });
  });
}
