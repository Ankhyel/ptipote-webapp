import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/figurines/ptipote_v2.dart';

void main() {
  group('P\'TIPOTE V2 profile migration', () {
    test('migrates an NFC legacy P\'TIPOTE as an owned Vestige', () {
      final profile = migrateLegacyPtipoteProfile(
        ptipoteId: 'nfc-1',
        legacyFields: const <String, String>{
          'e': 'Lierre',
          't': 'Végétal',
          'imagePath': 'lierre.png',
        },
        defaultBaseCarryCapacity: 20,
        now: DateTime.utc(2026, 8, 11),
      );

      expect(profile.ptipoteGeneration, PtipoteGeneration.vestige);
      expect(
          profile.acquisitionOrigin, PtipoteAcquisitionOrigin.legacyMigration);
      expect(profile.ownershipMode, PtipoteOwnershipMode.owned);
      expect(profile.typeId, PtipoteTypeId.vegetal);
      expect(profile.natureId, 'lierre');
      expect(profile.baseCarryCapacity, 20);
      expect(profile.coreId, isNull);
    });

    test('keeps a legacy temporary Protocol distinct from physical origin', () {
      final profile = migrateLegacyPtipoteProfile(
        ptipoteId: 'legacy-protocol',
        legacyFields: const <String, String>{
          'ptipoteGeneration': 'protocol',
          'coTraining': 'true',
          'coreId': 'core_spore',
          'envelope': 'defense',
          'e': 'Spore',
          'element': 'Mycélien',
        },
        defaultBaseCarryCapacity: 20,
      );

      expect(profile.ptipoteGeneration, PtipoteGeneration.protocol);
      expect(profile.ownershipMode, PtipoteOwnershipMode.coBred);
      expect(profile.coreId, 'core_spore');
      expect(profile.envelopeId, 'warrior_standard');
      expect(profile.typeId, PtipoteTypeId.mycelial);
    });
  });

  group('P\'TIPOTE V2 modifiers', () {
    test('Protocol core applies its Type at prepared core-only efficiency', () {
      const profile = PtipoteV2Profile(
        ptipoteId: 'protocol-core',
        acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
        ownershipMode: PtipoteOwnershipMode.coBred,
        ptipoteGeneration: PtipoteGeneration.protocol,
        typeId: PtipoteTypeId.mycelial,
        natureId: 'spore',
      );
      final modifiers = PtipoteModifierService.resolve(
        profile: profile,
        config: defaultPtipoteV2Config,
        mycelialGatherBonus: 0.50,
      );

      expect(modifiers.gather.mycelium, 0.25);
      expect(profile.effectiveProtocolEfficiency(defaultPtipoteV2Config), 0.5);
    });

    test('Defense grants +30% portage and rounds in the player favour', () {
      const profile = PtipoteV2Profile(
        ptipoteId: 'defense',
        acquisitionOrigin: PtipoteAcquisitionOrigin.physicalScan,
        ownershipMode: PtipoteOwnershipMode.owned,
        ptipoteGeneration: PtipoteGeneration.protocol,
        typeId: PtipoteTypeId.mineral,
        natureId: 'roc',
        envelopeId: 'defense',
        protocolEfficiencyMultiplier: 1,
        baseCarryCapacity: 21,
      );
      final modifiers = PtipoteModifierService.resolve(
        profile: profile,
        config: defaultPtipoteV2Config,
        mycelialGatherBonus: 0.50,
      );

      expect(modifiers.carryCapacityBonus, 0.30);
      expect(
        PtipoteModifierService.effectiveCarryCapacity(
          profile: profile,
          modifiers: modifiers,
        ),
        28,
      );
    });

    test('Analysts multiply only their own core exploration bonus by group',
        () {
      const profile = PtipoteV2Profile(
        ptipoteId: 'analyst',
        acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
        ownershipMode: PtipoteOwnershipMode.coBred,
        ptipoteGeneration: PtipoteGeneration.protocol,
        typeId: PtipoteTypeId.vegetal,
        natureId: 'liane',
        envelopeId: 'analyst',
        protocolEfficiencyMultiplier: 1,
      );
      final modifiers = PtipoteModifierService.resolve(
        profile: profile,
        config: defaultPtipoteV2Config,
        mycelialGatherBonus: 0.50,
        core: const PtipoteCore(
          coreId: 'core-liane',
          displayName: 'Liane',
          natureId: 'liane',
          typeId: PtipoteTypeId.vegetal,
          baseImageAsset: 'liane_core',
          compatibleEnvelopeIds: <String>{'analyst'},
          baseBonuses: <String, double>{'exploration': 0.20},
        ),
        eligibleGroupPtipoteCount: 3,
      );

      expect(modifiers.ownCoreExplorationBonus, 0.20);
      expect(modifiers.analystOwnCoreExplorationBonus, closeTo(0.60, 0.00001));
      expect(modifiers.gather.genericGather, 0);
    });
  });

  group('Protocol assets and compatibility', () {
    test('exposes exactly the Card Builder Protocol catalogue', () {
      expect(ptipoteProtocolCoreDefinitions, hasLength(9));
      expect(
        ptipoteProtocolCoreDefinitions.map((core) => core.coreId),
        containsAll(<String>[
          'veg_photosynthese',
          'veg_poison',
          'veg_croissance',
          'myc_filtration',
          'myc_decomposition',
          'myc_controle',
          'min_protection',
          'min_resonance',
          'min_calcification',
        ]),
      );
      expect(ptipoteProtocolEnvelopeDefinitions, hasLength(8));
      expect(
        ptipoteProtocolEnvelopeDefinitions
            .map((envelope) => envelope.envelopeId),
        containsAll(<String>[
          'warrior_standard',
          'explorer_standard',
          'scientist_share',
          'scientist_biopiratage',
          'producer_porter',
          'producer_solar',
          'producer_hill',
          'producer_mountain',
        ]),
      );
      expect(
        ptipoteProtocolCoreDefinitions.map((core) => core.drawWeight).toSet(),
        <int>{1},
      );
      expect(
        ptipoteProtocolEnvelopeDefinitions
            .map((envelope) => envelope.drawWeight)
            .toSet(),
        <int>{1},
      );
    });

    test('migrates only derivable generic core data', () {
      final migrated = PtipoteV2Profile.fromFirebase('old-protocol', {
        'ptipoteGeneration': 'protocol',
        'typeId': 'vegetal',
        'natureId': 'poison',
        'coreId': 'core_poison',
      });
      final unknown = PtipoteV2Profile.fromFirebase('unknown-protocol', {
        'ptipoteGeneration': 'protocol',
        'typeId': 'vegetal',
        'natureId': 'legacy_unknown',
        'coreId': 'core_legacy_unknown',
      });

      expect(migrated.coreId, 'veg_poison');
      expect(unknown.coreId, 'core_legacy_unknown');
    });

    test('uses a combined nature/envelope asset and falls back to core', () {
      expect(
        protocolVisualAssetKey(
          coreId: 'veg_poison',
          envelopeId: 'warrior_standard',
        ),
        'veg_poison_warrior_standard',
      );
      final found = PtipoteModifierService.resolveProtocolVisualAsset(
        natureId: 'Forêt Étoilée',
        coreAssetKey: 'foret_etoilee_core',
        envelopeId: 'Analyste',
        availableAssetKeys: const <String>{'foret_etoilee_analyste'},
      );
      final fallback = PtipoteModifierService.resolveProtocolVisualAsset(
        natureId: 'Forêt Étoilée',
        coreAssetKey: 'foret_etoilee_core',
        envelopeId: 'Défense',
        availableAssetKeys: const <String>{},
      );

      expect(found.assetKey, 'foret_etoilee_analyste');
      expect(found.warning, isNull);
      expect(fallback.assetKey, 'foret_etoilee_core');
      expect(fallback.warning, contains('Missing protocol combined asset'));
    });

    test('rejects explicitly incompatible envelopes', () {
      const core = PtipoteCore(
        coreId: 'core-a',
        displayName: 'A',
        natureId: 'a',
        typeId: PtipoteTypeId.vegetal,
        baseImageAsset: 'a_core',
        compatibleEnvelopeIds: <String>{},
      );
      const envelope = PtipoteEnvelope(
        envelopeId: 'defense',
        displayName: 'Défense',
        envelopeCategory: PtipoteEnvelopeCategory.defense,
        compatibilityRule: 'explicit',
      );

      expect(
        PtipoteModifierService.isEnvelopeCompatible(
          core: core,
          envelope: envelope,
        ),
        isFalse,
      );
    });
  });

  group('P\'TIPOTE arrival ritual', () {
    const baseProfile = PtipoteV2Profile(
      ptipoteId: 'arrival-1',
      acquisitionOrigin: PtipoteAcquisitionOrigin.physicalScan,
      ownershipMode: PtipoteOwnershipMode.owned,
      ptipoteGeneration: PtipoteGeneration.vestige,
      typeId: PtipoteTypeId.mineral,
      natureId: 'cristal',
    );

    test('creates a deterministic egg and preserves its pattern on retry', () {
      final egg = PtipoteArrivalService.sendPtipoteToIncubator(
        profile: baseProfile.copyWith(
          arrivalState: PtipoteArrivalState.pendingEgg,
        ),
        config: defaultPtipoteV2Config,
        systemName: 'Cristal',
        now: DateTime.utc(2026, 8, 11),
      );
      final ready = PtipoteArrivalService.prepareRhythm(
        egg,
        config: defaultPtipoteV2Config,
      );
      final retry = PtipoteArrivalService.failRhythm(
        PtipoteArrivalService.beginRhythm(ready),
      );

      expect(egg.arrivalState, PtipoteArrivalState.pendingEgg);
      expect(egg.rhythmPattern.length, inInclusiveRange(3, 5));
      expect(retry.arrivalState, PtipoteArrivalState.rhythmReady);
      expect(retry.rhythmPattern, egg.rhythmPattern);
      expect(retry.rhythmAttemptCount, 1);
    });

    test('hatches once, keeps system name, then activates after naming', () {
      final egg = PtipoteArrivalService.sendPtipoteToIncubator(
        profile: baseProfile.copyWith(
          arrivalState: PtipoteArrivalState.pendingEgg,
        ),
        config: defaultPtipoteV2Config,
        systemName: 'Cristal',
      );
      final hatched = PtipoteArrivalService.hatch(egg);
      final naming = PtipoteArrivalService.startNaming(hatched);
      final complete = PtipoteArrivalService.finalizeNaming(
        naming,
        displayName: 'Nova',
      );

      expect(hatched.arrivalState, PtipoteArrivalState.hatched);
      expect(complete.arrivalState, PtipoteArrivalState.completed);
      expect(complete.systemName, 'Cristal');
      expect(complete.displayName, 'Nova');
      expect(PtipoteArrivalService.hatch(complete), same(complete));
    });

    test('interrupted rhythm safely returns to rhythmReady', () {
      final egg = PtipoteArrivalService.sendPtipoteToIncubator(
        profile: baseProfile.copyWith(
          arrivalState: PtipoteArrivalState.pendingEgg,
        ),
        config: defaultPtipoteV2Config,
        systemName: 'Cristal',
      );
      final interrupted = PtipoteArrivalService.beginRhythm(
        PtipoteArrivalService.prepareRhythm(
          egg,
          config: defaultPtipoteV2Config,
        ),
      );
      final resumed =
          PtipoteArrivalService.resumeAfterInterruption(interrupted);

      expect(resumed.arrivalState, PtipoteArrivalState.rhythmReady);
      expect(resumed.rhythmPattern, interrupted.rhythmPattern);
    });

    test('keeps a co-breeding session unique through its egg arrival', () {
      final coBred = PtipoteArrivalService.sendPtipoteToIncubator(
        profile: baseProfile.copyWith(
          acquisitionOrigin: PtipoteAcquisitionOrigin.coBreeding,
          ownershipMode: PtipoteOwnershipMode.coBred,
          coBreedingSessionId: 'session-42',
          arrivalState: PtipoteArrivalState.pendingEgg,
        ),
        config: defaultPtipoteV2Config,
        systemName: 'Cristal',
      );
      final duplicate = PtipoteArrivalService.sendPtipoteToIncubator(
        profile: coBred,
        config: defaultPtipoteV2Config,
        systemName: 'Cristal',
      );

      expect(coBred.ownershipMode, PtipoteOwnershipMode.coBred);
      expect(coBred.coBreedingSessionId, 'session-42');
      expect(duplicate, same(coBred));
    });
  });
}
