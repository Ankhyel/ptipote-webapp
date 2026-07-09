import 'ptipote_stats_config.dart';

class PtipoteFigurine {
  const PtipoteFigurine({
    required this.id,
    required this.tagUid,
    required this.nickname,
    required this.publicKey,
    required this.rawSource,
    required this.sortOrder,
    required this.transferStatus,
    required this.transferFromName,
    required this.transferLockedUntil,
    required this.renameLockedUntil,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tagUid;
  final String nickname;
  final String publicKey;
  final String rawSource;
  final int sortOrder;
  final String transferStatus;
  final String transferFromName;
  final DateTime? transferLockedUntil;
  final DateTime? renameLockedUntil;
  final Map<String, String> fields;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName {
    final savedNickname = nickname.trim();
    if (savedNickname.isNotEmpty) return savedNickname;

    final fieldNickname = fields['s']?.trim();
    if (fieldNickname != null && fieldNickname.isNotEmpty) return fieldNickname;

    final label = [species, type].where((value) => value != '-').join(' ');
    return label.isEmpty ? 'PTIPOTE sans nom' : label;
  }

  String get level =>
      fields['l']?.trim().isNotEmpty == true ? fields['l']!.trim() : '1';

  String get xp =>
      fields['x']?.trim().isNotEmpty == true ? fields['x']!.trim() : '0';

  int get levelValue => _readBoundedStat(
        fields['level'] ?? fields['l'],
        fallback: 1,
        min: 1,
        max: 999,
      );

  int get xpValue => _readBoundedStat(
        fields['xp'] ?? fields['x'],
        fallback: 0,
        min: 0,
        max: 1 << 30,
      );

  int get xpRequiredForNextLevel {
    return ptipoteStatsConfig.xpRequiredForNextLevel(levelValue);
  }

  int get vitality => _readBoundedStat(
        fields['vitality'] ?? fields['v'],
        fallback: maxVitality,
        min: 0,
        max: maxVitality,
      );

  int get maxVitality => _readBoundedStat(
        fields['maxVitality'] ?? fields['mv'],
        fallback: ptipoteStatsConfig.maxVitality,
        min: 1,
        max: ptipoteStatsConfig.maxVitality,
      );

  int get happiness => _readBoundedStat(
        fields['happiness'] ?? fields['happy'] ?? fields['h'],
        fallback: ptipoteStatsConfig.baseHappiness,
        min: 0,
        max: maxHappiness,
      );

  int get maxHappiness => _readBoundedStat(
        fields['maxHappiness'] ?? fields['mh'],
        fallback: ptipoteStatsConfig.maxHappiness,
        min: 1,
        max: ptipoteStatsConfig.maxHappiness,
      );

  int get evg => _readBoundedStat(
        fields['evg'] ?? fields['EVG'],
        fallback: ptipoteStatsConfig.baseEVG,
        min: 0,
        max: 999,
      );

  String get energy => fields['energy']?.trim().isNotEmpty == true
      ? fields['energy']!.trim()
      : fields['en']?.trim().isNotEmpty == true
          ? fields['en']!.trim()
          : '-';

  String get species =>
      fields['e']?.trim().isNotEmpty == true ? fields['e']!.trim() : '-';

  String get type =>
      fields['t']?.trim().isNotEmpty == true ? fields['t']!.trim() : '-';

  PtipoteElementType get elementType {
    final value = _normalize(fields['type'] ?? fields['t']);
    if (value.contains('miner')) return PtipoteElementType.mineral;
    if (value.contains('fong') || value.contains('fung')) {
      return PtipoteElementType.fungal;
    }
    if (value.contains('veget') || value.contains('plant')) {
      return PtipoteElementType.vegetal;
    }
    return PtipoteElementType.vegetal;
  }

  PtipoteEnvelopeType get envelopeType {
    final value = _normalize(
      fields['envelopeType'] ?? fields['envelope'] ?? fields['env'],
    );
    if (value.contains('explor')) return PtipoteEnvelopeType.explorateur;
    if (value.contains('product')) return PtipoteEnvelopeType.producteur;
    if (value.contains('scien')) return PtipoteEnvelopeType.scientifique;
    if (value.contains('protect') ||
        value.contains('guerr') ||
        value.contains('warrior')) {
      return PtipoteEnvelopeType.protecteur;
    }
    return PtipoteEnvelopeType.standard;
  }

  String get envelopeLabel => switch (envelopeType) {
        PtipoteEnvelopeType.standard => 'standard',
        PtipoteEnvelopeType.explorateur => 'explorateur',
        PtipoteEnvelopeType.producteur => 'producteur',
        PtipoteEnvelopeType.scientifique => 'scientifique',
        PtipoteEnvelopeType.protecteur => 'protecteur',
      };

  PtipoteBehaviorState get behaviorState {
    final value = _normalize(fields['state'] ?? fields['behaviorState']);
    for (final state in PtipoteBehaviorState.values) {
      if (_normalize(state.name) == value) return state;
    }
    if (vitality <= 0) return PtipoteBehaviorState.exhausted;
    if (needsAutoRest) return PtipoteBehaviorState.resting;
    return PtipoteBehaviorState.wanderingHome;
  }

  String get behaviorStateLabel => switch (behaviorState) {
        PtipoteBehaviorState.idle => 'idle',
        PtipoteBehaviorState.wanderingHome => 'Maison',
        PtipoteBehaviorState.resting => 'repos',
        PtipoteBehaviorState.onMission => 'mission',
        PtipoteBehaviorState.helpingTower => 'aide Tour',
        PtipoteBehaviorState.helpingMarket => 'aide Marché',
        PtipoteBehaviorState.exhausted => 'épuisé',
      };

  String get vitalityStatusLabel {
    if (vitality >= 80) return 'en forme';
    if (vitality >= 50) return 'disponible';
    if (vitality >= 21) return 'fatigué';
    return 'repos nécessaire';
  }

  bool get needsAutoRest {
    return vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest;
  }

  PtipoteAutoAssignmentPreference get autoAssignmentPreference {
    final value = _normalize(
      fields['autoAssignmentPreference'] ??
          fields['autoPreference'] ??
          fields['ap'],
    );
    if (value.contains('tower') || value.contains('tour')) {
      return PtipoteAutoAssignmentPreference.tower;
    }
    if (value.contains('market') || value.contains('marche')) {
      return PtipoteAutoAssignmentPreference.market;
    }
    return PtipoteAutoAssignmentPreference.home;
  }

  String get autoAssignmentLabel => switch (autoAssignmentPreference) {
        PtipoteAutoAssignmentPreference.home => 'Maison',
        PtipoteAutoAssignmentPreference.tower => 'Tour',
        PtipoteAutoAssignmentPreference.market => 'Marché',
      };

  PtipoteBehaviorState nextAvailableState({
    required bool towerAvailable,
    required bool marketAvailable,
  }) {
    if (needsAutoRest) return PtipoteBehaviorState.resting;
    return switch (autoAssignmentPreference) {
      PtipoteAutoAssignmentPreference.home =>
        PtipoteBehaviorState.wanderingHome,
      PtipoteAutoAssignmentPreference.tower => towerAvailable
          ? PtipoteBehaviorState.helpingTower
          : PtipoteBehaviorState.wanderingHome,
      PtipoteAutoAssignmentPreference.market => marketAvailable
          ? PtipoteBehaviorState.helpingMarket
          : PtipoteBehaviorState.wanderingHome,
    };
  }

  double get forageEfficiency {
    final typeMod = ptipoteStatsConfig.typeModifiers[elementType];
    final envelopeMod = ptipoteStatsConfig.envelopeModifiers[envelopeType];
    return ptipoteStatsConfig.baseForageEfficiency +
        (typeMod?.forageEfficiencyBonus ?? 0) +
        (envelopeMod?.forageEfficiencyBonus ?? 0);
  }

  double get organicForageEfficiency {
    final typeMod = ptipoteStatsConfig.typeModifiers[elementType];
    return forageEfficiency + (typeMod?.organicForageBonus ?? 0);
  }

  double get mineralForageEfficiency {
    final typeMod = ptipoteStatsConfig.typeModifiers[elementType];
    return forageEfficiency + (typeMod?.mineralForageBonus ?? 0);
  }

  double get safetyContribution {
    final typeMod = ptipoteStatsConfig.typeModifiers[elementType];
    final envelopeMod = ptipoteStatsConfig.envelopeModifiers[envelopeType];
    return ptipoteStatsConfig.baseSafetyContribution +
        (typeMod?.safetyContributionBonus ?? 0) +
        (envelopeMod?.safetyContributionBonus ?? 0);
  }

  double get marketContribution {
    final typeMod = ptipoteStatsConfig.typeModifiers[elementType];
    final envelopeMod = ptipoteStatsConfig.envelopeModifiers[envelopeType];
    return ptipoteStatsConfig.baseMarketContribution +
        (typeMod?.marketContributionBonus ?? 0) +
        (envelopeMod?.marketContributionBonus ?? 0);
  }

  double get pollutionResistance {
    final envelopeMod = ptipoteStatsConfig.envelopeModifiers[envelopeType];
    return envelopeMod?.pollutionResistanceBonus ?? 0;
  }

  double get xpGainBonus {
    final envelopeMod = ptipoteStatsConfig.envelopeModifiers[envelopeType];
    return envelopeMod?.xpGainBonus ?? 0;
  }

  int addHappiness(int amount) {
    return (happiness + amount).clamp(0, maxHappiness).toInt();
  }

  int reduceHappiness(int amount) {
    return (happiness - amount).clamp(0, maxHappiness).toInt();
  }

  String get ownerName =>
      fields['o']?.trim().isNotEmpty == true ? fields['o']!.trim() : '-';

  String get breederNumber =>
      fields['on']?.trim().isNotEmpty == true ? fields['on']!.trim() : '-';

  bool get transferRequested => fields['te']?.trim() == '1';

  bool get transferConfirmed => fields['ter']?.trim() == '1';

  bool get needsTransferScan => transferStatus == 'accepted';

  bool get transferCooldownActive {
    final until = transferLockedUntil;
    return transferConfirmed && until != null && until.isAfter(DateTime.now());
  }

  bool get renameCooldownActive {
    final until = renameLockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  bool get canTransfer =>
      !needsTransferScan && !transferRequested && !transferCooldownActive;

  bool get canRename =>
      !needsTransferScan && !transferRequested && !renameCooldownActive;

  String get lockMessage {
    if (needsTransferScan) {
      return 'Scan de la figurine requis pour valider le transfert';
    }
    if (transferRequested) return 'Demande en attente';
    if (transferCooldownActive) {
      final remaining = transferLockedUntil!.difference(DateTime.now());
      final days = (remaining.inHours / 24).ceil().clamp(1, 7);
      return 'PTIPOTE en recharge, transfert disponible dans J-$days';
    }
    return '';
  }

  String get renameLockMessage {
    if (!renameCooldownActive) return '';
    final remaining = renameLockedUntil!.difference(DateTime.now());
    final days = (remaining.inHours / 24).ceil().clamp(1, 3);
    return 'Le PTIPOTE pourra être de nouveau renommé dans J-$days';
  }

  bool get isTransferLocked {
    return needsTransferScan || transferRequested;
  }

  int _readBoundedStat(
    String? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse((value ?? '').trim());
    return (parsed ?? fallback).clamp(min, max);
  }

  String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c');
  }
}
