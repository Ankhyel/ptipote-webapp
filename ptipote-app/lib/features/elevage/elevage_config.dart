import 'dart:convert';

const int elevageConfigSchemaVersion = 1;

enum ElevagePreset { prototype, target }

class ElevageRecipe {
  const ElevageRecipe({
    required this.id,
    required this.label,
    required this.installationId,
    required this.organic,
    required this.mineral,
    this.special = const <String, int>{},
    this.unlockItems = const <String>[],
  });

  final String id;
  final String label;
  final String installationId;
  final int organic;
  final int mineral;
  final Map<String, int> special;
  final List<String> unlockItems;

  bool get isBase => unlockItems.isEmpty;

  ElevageRecipe copyWith({int? organic, int? mineral}) => ElevageRecipe(
        id: id,
        label: label,
        installationId: installationId,
        organic: organic ?? this.organic,
        mineral: mineral ?? this.mineral,
        special: special,
        unlockItems: unlockItems,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'installationId': installationId,
        'organic': organic,
        'mineral': mineral,
        'special': special,
        'unlockItems': unlockItems,
      };

  factory ElevageRecipe.fromJson(Map<String, dynamic> json) => ElevageRecipe(
        id: json['id'] as String,
        label: json['label'] as String,
        installationId: json['installationId'] as String,
        organic: (json['organic'] as num).toInt(),
        mineral: (json['mineral'] as num).toInt(),
        special: (json['special'] as Map? ?? const <String, dynamic>{}).map(
          (key, value) => MapEntry('$key', (value as num).toInt()),
        ),
        unlockItems:
            List<String>.from(json['unlockItems'] as List? ?? const []),
      );
}

class ElevageInstallationDefinition {
  const ElevageInstallationDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.temperature,
    required this.humidity,
    this.category = 'STRUCTURE',
    this.movableByPtipote = false,
    this.activity,
    this.decorCategory,
    this.resonanceMaterial,
    this.outputs = const <String, int>{},
  });

  final String id;
  final String label;

  /// Player-facing copy. Values and mechanics remain defined by this object.
  final String description;
  final int light;
  final int temperature;
  final int humidity;

  /// STRUCTURE uses a technical Z1–Z4 slot; MEUBLE and DECORATION are free.
  final String category;
  final bool movableByPtipote;
  final String? activity;
  final String? decorCategory;
  final String? resonanceMaterial;
  final Map<String, int> outputs;

  bool get productive => outputs.isNotEmpty;
}

/// Four deliberately simple spatial contexts inside an Alcôve. Their effects
/// are relative gameplay values, just like the global Alcôve environment.
class ElevageSceneZone {
  const ElevageSceneZone({
    required this.id,
    required this.label,
    this.light = 0,
    this.temperature = 0,
    this.humidity = 0,
  });

  final String id;
  final String label;
  final int light;
  final int temperature;
  final int humidity;
}

class ElevageConfig {
  const ElevageConfig({
    required this.revision,
    required this.featureEnabled,
    required this.devMode,
    required this.preset,
    required this.alcoveCount,
    required this.installationSlotCount,
    required this.hungerNormalHours,
    required this.hungerHungryHours,
    required this.hungerVeryHungryHours,
    required this.suspectedThreshold,
    required this.confirmedThreshold,
    required this.foragingDurationSeconds,
    required this.productionIntervalSeconds,
    required this.productionMaxStock,
    required this.coRearingDurationHours,
    required this.refundOrganicRate,
    required this.refundMineralRate,
    required this.sourcierEnabled,
    required this.fibrousFruitPrice,
    required this.fruitJellyPrice,
    required this.buybackQuantity,
    required this.buybackBioPiles,
    required this.metamorphosisToleranceMs,
    required this.inventoryStackSize,
    required this.dayDurationHours,
    required this.nightDurationHours,
    required this.observationTextThreshold,
    required this.observationEvidenceCooldownMinutes,
    required this.autonomousReactionIntervalSeconds,
    required this.objectReactionDelayMs,
    required this.idlePauseSeconds,
    required this.normalMoveDurationMs,
    required this.runMoveDurationMs,
    required this.personalityBaselineWeight,
    required this.personalityBabyWeight,
    required this.personalityIntermediateWeight,
    required this.personalityAdultPlasticityWeight,
    required this.warmCuddleCooldownSeconds,
    required this.reservedCuddleCooldownSeconds,
    required this.requestDurationSeconds,
    required this.baseHumidity,
    required this.baseTemperature,
    required this.dayTemperatureDelta,
    required this.strongShadeTemperatureDelta,
    required this.reactionBubbleSeconds,
    required this.absorptionBubbleSeconds,
    required this.longPressHoldSeconds,
    required this.wakeGraceSeconds,
    required this.baseStayBabySeconds,
    required this.baseStayIntermediateSeconds,
    required this.baseStayMatureSeconds,
    required this.tempoPosedStayModifierSeconds,
    required this.tempoSpontaneousStayModifierSeconds,
    required this.perfectZoneStayModifierSeconds,
    required this.badZoneStayModifierSeconds,
    required this.extremeZoneStayModifierSeconds,
    required this.minStaySeconds,
    required this.resonanceGainPerUse,
    required this.vocalizations,
    required this.recipes,
  });

  final String revision;
  final bool featureEnabled;
  final bool devMode;
  final ElevagePreset preset;
  final int alcoveCount;
  final int installationSlotCount;
  final int hungerNormalHours;
  final int hungerHungryHours;
  final int hungerVeryHungryHours;
  final int suspectedThreshold;
  final int confirmedThreshold;
  final int foragingDurationSeconds;
  final int productionIntervalSeconds;
  final int productionMaxStock;
  final int coRearingDurationHours;
  final double refundOrganicRate;
  final double refundMineralRate;
  final bool sourcierEnabled;
  final int fibrousFruitPrice;
  final int fruitJellyPrice;
  final int buybackQuantity;
  final int buybackBioPiles;
  final int metamorphosisToleranceMs;
  final int inventoryStackSize;
  final int dayDurationHours;
  final int nightDurationHours;
  final int observationTextThreshold;
  final int observationEvidenceCooldownMinutes;
  final int autonomousReactionIntervalSeconds;
  final int objectReactionDelayMs;
  final int idlePauseSeconds;
  final int normalMoveDurationMs;
  final int runMoveDurationMs;
  final double personalityBaselineWeight;
  final double personalityBabyWeight;
  final double personalityIntermediateWeight;
  final double personalityAdultPlasticityWeight;
  final int warmCuddleCooldownSeconds;
  final int reservedCuddleCooldownSeconds;
  final int requestDurationSeconds;

  /// Valeurs relatives converties vers l'échelle joueur avec +3. Elles sont
  /// explicites afin que les libellés de zones ne modifient jamais le climat.
  final int baseHumidity;
  final int baseTemperature;
  final int dayTemperatureDelta;
  final int strongShadeTemperatureDelta;
  final int reactionBubbleSeconds;
  final int absorptionBubbleSeconds;
  final int longPressHoldSeconds;
  final int wakeGraceSeconds;
  final int baseStayBabySeconds;
  final int baseStayIntermediateSeconds;
  final int baseStayMatureSeconds;
  final int tempoPosedStayModifierSeconds;
  final int tempoSpontaneousStayModifierSeconds;
  final int perfectZoneStayModifierSeconds;
  final int badZoneStayModifierSeconds;
  final int extremeZoneStayModifierSeconds;
  final int minStaySeconds;
  final int resonanceGainPerUse;
  final Map<String, String> vocalizations;
  final List<ElevageRecipe> recipes;

  int get babyMinimumHours => preset == ElevagePreset.prototype ? 24 : 48;
  int get intermediateMinimumHours =>
      preset == ElevagePreset.prototype ? 72 : 168;
  int get dayNightCycleHours => dayDurationHours + nightDurationHours;

  List<ElevageInstallationDefinition> get installations =>
      <ElevageInstallationDefinition>[
        const ElevageInstallationDefinition(
          id: 'BASSIN',
          label: 'Bassin',
          description:
              'Un petit milieu humide où peuvent se développer algues et mousses.',
          light: 0,
          temperature: 0,
          humidity: 2,
          outputs: <String, int>{'ALGAE': 1, 'MOSS': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'MOSS_STONE',
          label: 'Pierre de mousse',
          description: 'Une pierre fraîche recouverte de mousse.',
          light: 0,
          temperature: -1,
          humidity: 2,
        ),
        const ElevageInstallationDefinition(
          id: 'CULTURE_POTAGERE',
          label: 'Culture potagère',
          description:
              'Un coin de culture qui fait pousser racines et feuilles.',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'ROOT': 1, 'LEAF': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'BUTTE_ARBUSTE',
          label: 'Butte d’arbuste',
          description: 'Une petite butte végétale où mûrissent des fruits.',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'FRUIT': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_METALLIQUE',
          label: 'Formation métallique',
          description:
              'Un support durable où les P’TIPOTES minéraux peuvent entrer en résonance.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'IRON',
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_CRISTALLINE',
          label: 'Formation cristalline',
          description:
              'Un support durable de résonance cristalline, sans produire de matière.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'QUARTZ',
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_MINERALE',
          label: 'Formation minérale',
          description: 'Un support minéral durable pour une résonance lente.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'LIMESTONE',
        ),
        const ElevageInstallationDefinition(
          id: 'LAMPE_SOLAIRE',
          label: 'Lampe solaire',
          description:
              'Une lampe qui éclaire et réchauffe légèrement l’Alcôve.',
          light: 2,
          temperature: 1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_FIBREUX',
          label: 'Abri fibreux',
          description:
              'Un abri tressé qui apporte de l’ombre et de la fraîcheur.',
          light: -2,
          temperature: -1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_MINERAL_PROFOND',
          label: 'Abri minéral profond',
          description: 'Un refuge profond, sombre et frais, mais plus humide.',
          light: -2,
          temperature: -2,
          humidity: 1,
        ),
        const ElevageInstallationDefinition(
          id: 'VENTILATION',
          label: 'Ventilation',
          description: 'Un courant d’air qui rafraîchit et assèche légèrement.',
          light: 0,
          temperature: -2,
          humidity: -2,
        ),
        const ElevageInstallationDefinition(
          id: 'TROU_GEOTHERMIQUE_CHAUD',
          label: 'Trou géothermique chaud',
          description: 'Une ouverture chaude qui réchauffe l’espace.',
          light: 0,
          temperature: 2,
          humidity: -1,
        ),
        const ElevageInstallationDefinition(
          id: 'TOIT_SERRE',
          label: 'Toit de serre',
          description: 'Un toit transparent qui augmente lumière et chaleur.',
          light: 1,
          temperature: 2,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'HAMAC',
          label: 'Hamac',
          description: 'Un meuble de repos court et de détente calme.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'REST',
        ),
        const ElevageInstallationDefinition(
          id: 'NID_COUCHETTE',
          label: 'Nid / couchette',
          description: 'Un coin calme pour les pauses et le repos.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'REST',
        ),
        const ElevageInstallationDefinition(
          id: 'POTAGER_VERTICAL',
          label: 'Potager vertical',
          description:
              'Une station végétale pour manipuler pousses et substrat.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'GARDEN',
        ),
        const ElevageInstallationDefinition(
          id: 'LITIERE_FONGIQUE',
          label: 'Litière fongique',
          description: 'Un substrat souple pour creuser et redistribuer.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'DIG',
        ),
        const ElevageInstallationDefinition(
          id: 'BAC_GRAVIER',
          label: 'Bac à gravier',
          description:
              'Un bac minéral pour fouiller, trier et déplacer des pierres.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'SORT',
        ),
        const ElevageInstallationDefinition(
          id: 'BIBLIOTHEQUE_DATABUG',
          label: 'Bibliothèque Databug',
          description: 'Une station de curiosité et d’observation lente.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'READ',
        ),
        const ElevageInstallationDefinition(
          id: 'PARCOURS_OBSTACLES',
          label: 'Parcours d’obstacles',
          description: 'Une station d’activité physique et d’exploration.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'PLAY',
        ),
        const ElevageInstallationDefinition(
            id: 'PLANTE_DECORATIVE',
            label: 'Plante décorative',
            description: 'Une petite plante libre à observer.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'VEGETAL'),
        const ElevageInstallationDefinition(
            id: 'MOUSSE_DECORATIVE',
            label: 'Mousse décorative',
            description: 'Un coussin végétal doux et discret.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MOSS'),
        const ElevageInstallationDefinition(
            id: 'CRISTAL_DECORATIF',
            label: 'Cristal décoratif',
            description:
                'Un petit cristal dont l’intérêt dépend de chaque individu.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'CRYSTAL'),
        const ElevageInstallationDefinition(
            id: 'GEODE_DECORATIVE',
            label: 'Géode décorative',
            description:
                'Une géode libre, décorative et potentiellement favorite.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MINERAL'),
        const ElevageInstallationDefinition(
            id: 'PIERRE_DECORATIVE',
            label: 'Pierre décorative',
            description: 'Une pierre libre à rapprocher de son coin préféré.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MINERAL'),
        const ElevageInstallationDefinition(
            id: 'CARILLON',
            label: 'Carillon',
            description: 'Un objet musical doux selon les goûts individuels.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MUSIC_SOFT'),
        const ElevageInstallationDefinition(
            id: 'CONQUE_MUSICALE',
            label: 'Conque musicale',
            description: 'Un objet musical rythmé selon les goûts individuels.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MUSIC_ENERGETIC'),
      ];

  List<ElevageSceneZone> get sceneZones => const <ElevageSceneZone>[
        ElevageSceneZone(id: 'ZONE_1', label: 'Abri ombragé', light: 2),
        ElevageSceneZone(id: 'ZONE_2', label: 'Nid central', light: 3),
        ElevageSceneZone(id: 'ZONE_3', label: 'Coin central', light: 3),
        ElevageSceneZone(id: 'ZONE_4', label: 'Bord éclairé', light: 4),
      ];

  /// Jour : 2 / 3 / 3 / 4 sur l’échelle joueur 1–5. La nuit reste discrète
  /// et centralisée : Z1–Z3 sombrent, Z4 garde une lumière résiduelle.
  int nightLightOffset(String zoneId) => switch (zoneId) {
        // Les bases jour sont 2 / 3 / 3 / 4 ; la nuit est 1 / 2 / 2 / 3.
        'ZONE_1' || 'ZONE_2' || 'ZONE_3' || 'ZONE_4' => -1,
        _ => 0,
      };

  /// Seuils de confort lumineux du profil Résonance V0, consultés par le
  /// domaine ; ils ne sont jamais recopiés dans l’interface.
  int resonanceLightComfort(int lightScale) => switch (lightScale) {
        1 || 2 => 1,
        3 => 0,
        4 => -1,
        _ => -2,
      };

  String resonanceAxisComfort(String axis, int scale) {
    // Résonance V0 préfère froid, sec et peu lumineux. Les trois axes
    // utilisent la même échelle lisible jusqu’à l’arrivée d’autres Natures.
    return switch (scale) {
      0 => 'EXTREME',
      1 => 'IDEAL',
      2 => 'GOOD',
      3 => 'NEUTRAL',
      4 => 'BAD',
      _ => 'EXTREME',
    };
  }

  ElevageInstallationDefinition? installation(String id) {
    final normalized = switch (id) {
      'GEODE_FERRIQUE' => 'FORMATION_METALLIQUE',
      'GEODE_CRISTALLINE' => 'FORMATION_CRISTALLINE',
      _ => id,
    };
    for (final definition in installations) {
      if (definition.id == normalized) return definition;
    }
    return null;
  }

  ElevageSceneZone? sceneZone(String id) {
    for (final zone in sceneZones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  ElevageConfig copyWith({
    String? revision,
    bool? featureEnabled,
    bool? devMode,
    ElevagePreset? preset,
    int? alcoveCount,
    int? hungerNormalHours,
    int? hungerHungryHours,
    int? hungerVeryHungryHours,
    int? suspectedThreshold,
    int? confirmedThreshold,
    int? foragingDurationSeconds,
    int? productionIntervalSeconds,
    int? productionMaxStock,
    int? coRearingDurationHours,
    double? refundOrganicRate,
    double? refundMineralRate,
    bool? sourcierEnabled,
    int? fibrousFruitPrice,
    int? fruitJellyPrice,
    int? buybackQuantity,
    int? buybackBioPiles,
    int? metamorphosisToleranceMs,
    int? inventoryStackSize,
    int? dayDurationHours,
    int? nightDurationHours,
    int? observationTextThreshold,
    int? observationEvidenceCooldownMinutes,
    int? autonomousReactionIntervalSeconds,
    int? objectReactionDelayMs,
    int? idlePauseSeconds,
    int? normalMoveDurationMs,
    int? runMoveDurationMs,
    double? personalityBaselineWeight,
    double? personalityBabyWeight,
    double? personalityIntermediateWeight,
    double? personalityAdultPlasticityWeight,
    int? warmCuddleCooldownSeconds,
    int? reservedCuddleCooldownSeconds,
    int? requestDurationSeconds,
    int? baseHumidity,
    int? baseTemperature,
    int? dayTemperatureDelta,
    int? strongShadeTemperatureDelta,
    int? reactionBubbleSeconds,
    int? absorptionBubbleSeconds,
    int? longPressHoldSeconds,
    int? wakeGraceSeconds,
    int? baseStayBabySeconds,
    int? baseStayIntermediateSeconds,
    int? baseStayMatureSeconds,
    int? tempoPosedStayModifierSeconds,
    int? tempoSpontaneousStayModifierSeconds,
    int? perfectZoneStayModifierSeconds,
    int? badZoneStayModifierSeconds,
    int? extremeZoneStayModifierSeconds,
    int? minStaySeconds,
    int? resonanceGainPerUse,
    Map<String, String>? vocalizations,
    List<ElevageRecipe>? recipes,
  }) =>
      ElevageConfig(
        revision: revision ?? this.revision,
        featureEnabled: featureEnabled ?? this.featureEnabled,
        devMode: devMode ?? this.devMode,
        preset: preset ?? this.preset,
        alcoveCount: alcoveCount ?? this.alcoveCount,
        installationSlotCount: installationSlotCount,
        hungerNormalHours: hungerNormalHours ?? this.hungerNormalHours,
        hungerHungryHours: hungerHungryHours ?? this.hungerHungryHours,
        hungerVeryHungryHours:
            hungerVeryHungryHours ?? this.hungerVeryHungryHours,
        suspectedThreshold: suspectedThreshold ?? this.suspectedThreshold,
        confirmedThreshold: confirmedThreshold ?? this.confirmedThreshold,
        foragingDurationSeconds:
            foragingDurationSeconds ?? this.foragingDurationSeconds,
        productionIntervalSeconds:
            productionIntervalSeconds ?? this.productionIntervalSeconds,
        productionMaxStock: productionMaxStock ?? this.productionMaxStock,
        coRearingDurationHours:
            coRearingDurationHours ?? this.coRearingDurationHours,
        refundOrganicRate: refundOrganicRate ?? this.refundOrganicRate,
        refundMineralRate: refundMineralRate ?? this.refundMineralRate,
        sourcierEnabled: sourcierEnabled ?? this.sourcierEnabled,
        fibrousFruitPrice: fibrousFruitPrice ?? this.fibrousFruitPrice,
        fruitJellyPrice: fruitJellyPrice ?? this.fruitJellyPrice,
        buybackQuantity: buybackQuantity ?? this.buybackQuantity,
        buybackBioPiles: buybackBioPiles ?? this.buybackBioPiles,
        metamorphosisToleranceMs:
            metamorphosisToleranceMs ?? this.metamorphosisToleranceMs,
        inventoryStackSize: inventoryStackSize ?? this.inventoryStackSize,
        dayDurationHours: dayDurationHours ?? this.dayDurationHours,
        nightDurationHours: nightDurationHours ?? this.nightDurationHours,
        observationTextThreshold:
            observationTextThreshold ?? this.observationTextThreshold,
        observationEvidenceCooldownMinutes:
            observationEvidenceCooldownMinutes ??
                this.observationEvidenceCooldownMinutes,
        autonomousReactionIntervalSeconds: autonomousReactionIntervalSeconds ??
            this.autonomousReactionIntervalSeconds,
        objectReactionDelayMs:
            objectReactionDelayMs ?? this.objectReactionDelayMs,
        idlePauseSeconds: idlePauseSeconds ?? this.idlePauseSeconds,
        normalMoveDurationMs: normalMoveDurationMs ?? this.normalMoveDurationMs,
        runMoveDurationMs: runMoveDurationMs ?? this.runMoveDurationMs,
        personalityBaselineWeight:
            personalityBaselineWeight ?? this.personalityBaselineWeight,
        personalityBabyWeight:
            personalityBabyWeight ?? this.personalityBabyWeight,
        personalityIntermediateWeight:
            personalityIntermediateWeight ?? this.personalityIntermediateWeight,
        personalityAdultPlasticityWeight: personalityAdultPlasticityWeight ??
            this.personalityAdultPlasticityWeight,
        warmCuddleCooldownSeconds:
            warmCuddleCooldownSeconds ?? this.warmCuddleCooldownSeconds,
        reservedCuddleCooldownSeconds:
            reservedCuddleCooldownSeconds ?? this.reservedCuddleCooldownSeconds,
        requestDurationSeconds:
            requestDurationSeconds ?? this.requestDurationSeconds,
        baseHumidity: baseHumidity ?? this.baseHumidity,
        baseTemperature: baseTemperature ?? this.baseTemperature,
        dayTemperatureDelta: dayTemperatureDelta ?? this.dayTemperatureDelta,
        strongShadeTemperatureDelta:
            strongShadeTemperatureDelta ?? this.strongShadeTemperatureDelta,
        reactionBubbleSeconds:
            reactionBubbleSeconds ?? this.reactionBubbleSeconds,
        absorptionBubbleSeconds:
            absorptionBubbleSeconds ?? this.absorptionBubbleSeconds,
        longPressHoldSeconds: longPressHoldSeconds ?? this.longPressHoldSeconds,
        wakeGraceSeconds: wakeGraceSeconds ?? this.wakeGraceSeconds,
        baseStayBabySeconds: baseStayBabySeconds ?? this.baseStayBabySeconds,
        baseStayIntermediateSeconds:
            baseStayIntermediateSeconds ?? this.baseStayIntermediateSeconds,
        baseStayMatureSeconds:
            baseStayMatureSeconds ?? this.baseStayMatureSeconds,
        tempoPosedStayModifierSeconds:
            tempoPosedStayModifierSeconds ?? this.tempoPosedStayModifierSeconds,
        tempoSpontaneousStayModifierSeconds:
            tempoSpontaneousStayModifierSeconds ??
                this.tempoSpontaneousStayModifierSeconds,
        perfectZoneStayModifierSeconds: perfectZoneStayModifierSeconds ??
            this.perfectZoneStayModifierSeconds,
        badZoneStayModifierSeconds:
            badZoneStayModifierSeconds ?? this.badZoneStayModifierSeconds,
        extremeZoneStayModifierSeconds: extremeZoneStayModifierSeconds ??
            this.extremeZoneStayModifierSeconds,
        minStaySeconds: minStaySeconds ?? this.minStaySeconds,
        resonanceGainPerUse: resonanceGainPerUse ?? this.resonanceGainPerUse,
        vocalizations: vocalizations ?? this.vocalizations,
        recipes: recipes ?? this.recipes,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': elevageConfigSchemaVersion,
        'revision': revision,
        'featureEnabled': featureEnabled,
        'devMode': devMode,
        'preset': preset.name,
        'alcoveCount': alcoveCount,
        'installationSlotCount': installationSlotCount,
        'hungerNormalHours': hungerNormalHours,
        'hungerHungryHours': hungerHungryHours,
        'hungerVeryHungryHours': hungerVeryHungryHours,
        'suspectedThreshold': suspectedThreshold,
        'confirmedThreshold': confirmedThreshold,
        'foragingDurationSeconds': foragingDurationSeconds,
        'productionIntervalSeconds': productionIntervalSeconds,
        'productionMaxStock': productionMaxStock,
        'coRearingDurationHours': coRearingDurationHours,
        'refundOrganicRate': refundOrganicRate,
        'refundMineralRate': refundMineralRate,
        'sourcierEnabled': sourcierEnabled,
        'fibrousFruitPrice': fibrousFruitPrice,
        'fruitJellyPrice': fruitJellyPrice,
        'buybackQuantity': buybackQuantity,
        'buybackBioPiles': buybackBioPiles,
        'metamorphosisToleranceMs': metamorphosisToleranceMs,
        'inventoryStackSize': inventoryStackSize,
        'dayDurationHours': dayDurationHours,
        'nightDurationHours': nightDurationHours,
        'observationTextThreshold': observationTextThreshold,
        'observationEvidenceCooldownMinutes':
            observationEvidenceCooldownMinutes,
        'autonomousReactionIntervalSeconds': autonomousReactionIntervalSeconds,
        'objectReactionDelayMs': objectReactionDelayMs,
        'idlePauseSeconds': idlePauseSeconds,
        'normalMoveDurationMs': normalMoveDurationMs,
        'runMoveDurationMs': runMoveDurationMs,
        'personalityBaselineWeight': personalityBaselineWeight,
        'personalityBabyWeight': personalityBabyWeight,
        'personalityIntermediateWeight': personalityIntermediateWeight,
        'personalityAdultPlasticityWeight': personalityAdultPlasticityWeight,
        'warmCuddleCooldownSeconds': warmCuddleCooldownSeconds,
        'reservedCuddleCooldownSeconds': reservedCuddleCooldownSeconds,
        'requestDurationSeconds': requestDurationSeconds,
        'baseHumidity': baseHumidity,
        'baseTemperature': baseTemperature,
        'dayTemperatureDelta': dayTemperatureDelta,
        'strongShadeTemperatureDelta': strongShadeTemperatureDelta,
        'reactionBubbleSeconds': reactionBubbleSeconds,
        'absorptionBubbleSeconds': absorptionBubbleSeconds,
        'longPressHoldSeconds': longPressHoldSeconds,
        'wakeGraceSeconds': wakeGraceSeconds,
        'baseStayBabySeconds': baseStayBabySeconds,
        'baseStayIntermediateSeconds': baseStayIntermediateSeconds,
        'baseStayMatureSeconds': baseStayMatureSeconds,
        'tempoPosedStayModifierSeconds': tempoPosedStayModifierSeconds,
        'tempoSpontaneousStayModifierSeconds':
            tempoSpontaneousStayModifierSeconds,
        'perfectZoneStayModifierSeconds': perfectZoneStayModifierSeconds,
        'badZoneStayModifierSeconds': badZoneStayModifierSeconds,
        'extremeZoneStayModifierSeconds': extremeZoneStayModifierSeconds,
        'minStaySeconds': minStaySeconds,
        'resonanceGainPerUse': resonanceGainPerUse,
        'vocalizations': vocalizations,
        'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
      };

  factory ElevageConfig.fromJson(Map<String, dynamic> json) {
    const base = defaultElevageConfig;
    final config = base.copyWith(
      revision: json['revision'] as String? ?? base.revision,
      featureEnabled: json['featureEnabled'] as bool? ?? base.featureEnabled,
      devMode: json['devMode'] as bool? ?? base.devMode,
      preset: ElevagePreset.values
          .byName(json['preset'] as String? ?? base.preset.name),
      alcoveCount: _positive(json['alcoveCount'], base.alcoveCount),
      hungerNormalHours:
          _nonNegative(json['hungerNormalHours'], base.hungerNormalHours),
      hungerHungryHours:
          _nonNegative(json['hungerHungryHours'], base.hungerHungryHours),
      hungerVeryHungryHours: _nonNegative(
          json['hungerVeryHungryHours'], base.hungerVeryHungryHours),
      suspectedThreshold:
          _positive(json['suspectedThreshold'], base.suspectedThreshold),
      confirmedThreshold:
          _positive(json['confirmedThreshold'], base.confirmedThreshold),
      foragingDurationSeconds: _positive(
          json['foragingDurationSeconds'], base.foragingDurationSeconds),
      productionIntervalSeconds: _positive(
          json['productionIntervalSeconds'], base.productionIntervalSeconds),
      productionMaxStock:
          _positive(json['productionMaxStock'], base.productionMaxStock),
      coRearingDurationHours: _positive(
          json['coRearingDurationHours'], base.coRearingDurationHours),
      refundOrganicRate:
          _rate(json['refundOrganicRate'], base.refundOrganicRate),
      refundMineralRate:
          _rate(json['refundMineralRate'], base.refundMineralRate),
      sourcierEnabled: json['sourcierEnabled'] as bool? ?? base.sourcierEnabled,
      fibrousFruitPrice:
          _nonNegative(json['fibrousFruitPrice'], base.fibrousFruitPrice),
      fruitJellyPrice:
          _nonNegative(json['fruitJellyPrice'], base.fruitJellyPrice),
      buybackQuantity: _positive(json['buybackQuantity'], base.buybackQuantity),
      buybackBioPiles:
          _nonNegative(json['buybackBioPiles'], base.buybackBioPiles),
      metamorphosisToleranceMs: _nonNegative(
          json['metamorphosisToleranceMs'], base.metamorphosisToleranceMs),
      inventoryStackSize:
          _positive(json['inventoryStackSize'], base.inventoryStackSize),
      dayDurationHours:
          _positive(json['dayDurationHours'], base.dayDurationHours),
      nightDurationHours:
          _positive(json['nightDurationHours'], base.nightDurationHours),
      observationTextThreshold: _positive(
          json['observationTextThreshold'], base.observationTextThreshold),
      observationEvidenceCooldownMinutes: _nonNegative(
          json['observationEvidenceCooldownMinutes'],
          base.observationEvidenceCooldownMinutes),
      autonomousReactionIntervalSeconds: _positive(
          json['autonomousReactionIntervalSeconds'],
          base.autonomousReactionIntervalSeconds),
      objectReactionDelayMs:
          _positive(json['objectReactionDelayMs'], base.objectReactionDelayMs),
      idlePauseSeconds:
          _positive(json['idlePauseSeconds'], base.idlePauseSeconds),
      normalMoveDurationMs:
          _positive(json['normalMoveDurationMs'], base.normalMoveDurationMs),
      runMoveDurationMs:
          _positive(json['runMoveDurationMs'], base.runMoveDurationMs),
      personalityBaselineWeight: _rate(
          json['personalityBaselineWeight'], base.personalityBaselineWeight),
      personalityBabyWeight:
          _rate(json['personalityBabyWeight'], base.personalityBabyWeight),
      personalityIntermediateWeight: _rate(
          json['personalityIntermediateWeight'],
          base.personalityIntermediateWeight),
      personalityAdultPlasticityWeight: _rate(
          json['personalityAdultPlasticityWeight'],
          base.personalityAdultPlasticityWeight),
      warmCuddleCooldownSeconds: _positive(
          json['warmCuddleCooldownSeconds'], base.warmCuddleCooldownSeconds),
      reservedCuddleCooldownSeconds: _positive(
          json['reservedCuddleCooldownSeconds'],
          base.reservedCuddleCooldownSeconds),
      requestDurationSeconds: _positive(
          json['requestDurationSeconds'], base.requestDurationSeconds),
      baseHumidity: _number(json['baseHumidity'], base.baseHumidity),
      baseTemperature: _number(json['baseTemperature'], base.baseTemperature),
      dayTemperatureDelta:
          _number(json['dayTemperatureDelta'], base.dayTemperatureDelta),
      strongShadeTemperatureDelta: _number(json['strongShadeTemperatureDelta'],
          base.strongShadeTemperatureDelta),
      reactionBubbleSeconds:
          _positive(json['reactionBubbleSeconds'], base.reactionBubbleSeconds),
      absorptionBubbleSeconds: _positive(
          json['absorptionBubbleSeconds'], base.absorptionBubbleSeconds),
      longPressHoldSeconds:
          _positive(json['longPressHoldSeconds'], base.longPressHoldSeconds),
      wakeGraceSeconds:
          _positive(json['wakeGraceSeconds'], base.wakeGraceSeconds),
      baseStayBabySeconds:
          _positive(json['baseStayBabySeconds'], base.baseStayBabySeconds),
      baseStayIntermediateSeconds: _positive(
          json['baseStayIntermediateSeconds'],
          base.baseStayIntermediateSeconds),
      baseStayMatureSeconds:
          _positive(json['baseStayMatureSeconds'], base.baseStayMatureSeconds),
      tempoPosedStayModifierSeconds: _number(
          json['tempoPosedStayModifierSeconds'],
          base.tempoPosedStayModifierSeconds),
      tempoSpontaneousStayModifierSeconds: _number(
          json['tempoSpontaneousStayModifierSeconds'],
          base.tempoSpontaneousStayModifierSeconds),
      perfectZoneStayModifierSeconds: _number(
          json['perfectZoneStayModifierSeconds'],
          base.perfectZoneStayModifierSeconds),
      badZoneStayModifierSeconds: _number(
          json['badZoneStayModifierSeconds'], base.badZoneStayModifierSeconds),
      extremeZoneStayModifierSeconds: _number(
          json['extremeZoneStayModifierSeconds'],
          base.extremeZoneStayModifierSeconds),
      minStaySeconds: _positive(json['minStaySeconds'], base.minStaySeconds),
      resonanceGainPerUse:
          _positive(json['resonanceGainPerUse'], base.resonanceGainPerUse),
      vocalizations: (json['vocalizations'] as Map?)?.map(
            (key, value) => MapEntry('$key', '$value'),
          ) ??
          base.vocalizations,
      recipes: (json['recipes'] as List?)
              ?.whereType<Map>()
              .map((raw) =>
                  ElevageRecipe.fromJson(Map<String, dynamic>.from(raw)))
              .toList() ??
          base.recipes,
    );
    validateElevageConfig(config);
    return config;
  }
}

int _positive(Object? value, int fallback) =>
    value is num && value > 0 ? value.round() : fallback;
int _nonNegative(Object? value, int fallback) =>
    value is num && value >= 0 ? value.round() : fallback;
int _number(Object? value, int fallback) =>
    value is num ? value.round() : fallback;
double _rate(Object? value, double fallback) =>
    value is num && value >= 0 && value <= 1 ? value.toDouble() : fallback;

void validateElevageConfig(ElevageConfig config) {
  if (config.hungerNormalHours > config.hungerHungryHours ||
      config.hungerHungryHours > config.hungerVeryHungryHours ||
      config.suspectedThreshold > config.confirmedThreshold ||
      config.observationTextThreshold > config.confirmedThreshold ||
      config.autonomousReactionIntervalSeconds <= 0 ||
      config.objectReactionDelayMs <= 0 ||
      config.idlePauseSeconds <= 0 ||
      config.normalMoveDurationMs <= 0 ||
      config.runMoveDurationMs <= 0 ||
      ((config.personalityBaselineWeight +
                      config.personalityBabyWeight +
                      config.personalityIntermediateWeight +
                      config.personalityAdultPlasticityWeight) -
                  1)
              .abs() >
          .0001 ||
      config.warmCuddleCooldownSeconds <= 0 ||
      config.reservedCuddleCooldownSeconds <= 0 ||
      config.requestDurationSeconds <= 0 ||
      config.reactionBubbleSeconds <= 0 ||
      config.absorptionBubbleSeconds < config.reactionBubbleSeconds ||
      config.longPressHoldSeconds <= 0 ||
      config.wakeGraceSeconds <= 0 ||
      config.baseStayBabySeconds <= 0 ||
      config.baseStayIntermediateSeconds <= 0 ||
      config.baseStayMatureSeconds <= 0 ||
      config.minStaySeconds <= 0 ||
      config.resonanceGainPerUse <= 0 ||
      config.vocalizations.values.any((value) => value.trim().isEmpty) ||
      config.recipes.map((recipe) => recipe.id).toSet().length !=
          config.recipes.length) {
    throw const FormatException('Configuration Élevage invalide.');
  }
}

const ElevageConfig defaultElevageConfig = ElevageConfig(
  revision: 'defaults:v1',
  featureEnabled: true,
  devMode: true,
  preset: ElevagePreset.prototype,
  alcoveCount: 4,
  installationSlotCount: 4,
  hungerNormalHours: 96,
  hungerHungryHours: 168,
  hungerVeryHungryHours: 240,
  suspectedThreshold: 2,
  confirmedThreshold: 4,
  foragingDurationSeconds: 20,
  productionIntervalSeconds: 10800,
  productionMaxStock: 6,
  coRearingDurationHours: 168,
  refundOrganicRate: .5,
  refundMineralRate: .5,
  sourcierEnabled: true,
  fibrousFruitPrice: 2,
  fruitJellyPrice: 3,
  buybackQuantity: 5,
  buybackBioPiles: 1,
  metamorphosisToleranceMs: 180,
  inventoryStackSize: 12,
  dayDurationHours: 4,
  nightDurationHours: 2,
  observationTextThreshold: 2,
  observationEvidenceCooldownMinutes: 10,
  autonomousReactionIntervalSeconds: 60,
  objectReactionDelayMs: 700,
  idlePauseSeconds: 45,
  normalMoveDurationMs: 1600,
  runMoveDurationMs: 400,
  personalityBaselineWeight: .5,
  personalityBabyWeight: .25,
  personalityIntermediateWeight: .15,
  personalityAdultPlasticityWeight: .1,
  warmCuddleCooldownSeconds: 45,
  reservedCuddleCooldownSeconds: 90,
  requestDurationSeconds: 90,
  baseHumidity: 2,
  baseTemperature: 2,
  dayTemperatureDelta: 1,
  strongShadeTemperatureDelta: -1,
  reactionBubbleSeconds: 7,
  absorptionBubbleSeconds: 20,
  longPressHoldSeconds: 3,
  wakeGraceSeconds: 60,
  baseStayBabySeconds: 30,
  baseStayIntermediateSeconds: 20,
  baseStayMatureSeconds: 25,
  tempoPosedStayModifierSeconds: 5,
  tempoSpontaneousStayModifierSeconds: -5,
  perfectZoneStayModifierSeconds: 10,
  badZoneStayModifierSeconds: -10,
  extremeZoneStayModifierSeconds: -20,
  minStaySeconds: 3,
  resonanceGainPerUse: 1,
  vocalizations: <String, String>{
    'CURIOSITY': 'Pti ?',
    'ABSORB': 'Mm !',
    'CONTENT': 'Prr !',
    'DISCOMFORT': 'Nnh…',
    'SURPRISE': 'Ptik !',
    'REJECT': 'Nh !',
    'CALL': 'Pti !',
  },
  recipes: <ElevageRecipe>[
    ElevageRecipe(
        id: 'ABRI_FIBREUX',
        label: 'Abri fibreux',
        installationId: 'ABRI_FIBREUX',
        organic: 5,
        mineral: 2),
    ElevageRecipe(
        id: 'ABRI_MINERAL_PROFOND',
        label: 'Abri minéral profond',
        installationId: 'ABRI_MINERAL_PROFOND',
        organic: 0,
        mineral: 7),
    ElevageRecipe(
        id: 'VENTILATION',
        label: 'Ventilation',
        installationId: 'VENTILATION',
        organic: 2,
        mineral: 5),
    ElevageRecipe(
        id: 'TROU_GEOTHERMIQUE_CHAUD',
        label: 'Trou géothermique chaud',
        installationId: 'TROU_GEOTHERMIQUE_CHAUD',
        organic: 0,
        mineral: 7),
    ElevageRecipe(
        id: 'TOIT_SERRE',
        label: 'Toit de serre',
        installationId: 'TOIT_SERRE',
        organic: 6,
        mineral: 1),
    ElevageRecipe(
        id: 'LAMPE_SOLAIRE',
        label: 'Lampe solaire',
        installationId: 'LAMPE_SOLAIRE',
        organic: 2,
        mineral: 4),
    ElevageRecipe(
        id: 'BASSIN',
        label: 'Bassin',
        installationId: 'BASSIN',
        organic: 2,
        mineral: 10,
        special: <String, int>{'LIMESTONE': 1, 'ALGAE_FRAGMENT': 1},
        unlockItems: <String>['LIMESTONE', 'ALGAE_FRAGMENT']),
    ElevageRecipe(
        id: 'MOSS_STONE',
        label: 'Pierre de mousse',
        installationId: 'MOSS_STONE',
        organic: 2,
        mineral: 5,
        special: <String, int>{'MOSS': 1},
        unlockItems: <String>['MOSS']),
    ElevageRecipe(
        id: 'CULTURE_POTAGERE',
        label: 'Culture potagère',
        installationId: 'CULTURE_POTAGERE',
        organic: 5,
        mineral: 2,
        special: <String, int>{'SEED': 1},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'BUTTE_ARBUSTE',
        label: 'Butte d’arbuste',
        installationId: 'BUTTE_ARBUSTE',
        organic: 4,
        mineral: 3,
        special: <String, int>{'SPROUT': 1},
        unlockItems: <String>['SPROUT']),
    ElevageRecipe(
        id: 'FORMATION_MINERALE',
        label: 'Formation minérale',
        installationId: 'FORMATION_MINERALE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'LIMESTONE': 10},
        unlockItems: <String>['LIMESTONE']),
    ElevageRecipe(
        id: 'FORMATION_METALLIQUE',
        label: 'Formation métallique',
        installationId: 'FORMATION_METALLIQUE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'IRON': 10},
        unlockItems: <String>['IRON']),
    ElevageRecipe(
        id: 'FORMATION_CRISTALLINE',
        label: 'Formation cristalline',
        installationId: 'FORMATION_CRISTALLINE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'QUARTZ': 10},
        unlockItems: <String>['QUARTZ']),
    ElevageRecipe(
        id: 'HAMAC',
        label: 'Hamac',
        installationId: 'HAMAC',
        organic: 6,
        mineral: 1),
    ElevageRecipe(
        id: 'NID_COUCHETTE',
        label: 'Nid / couchette',
        installationId: 'NID_COUCHETTE',
        organic: 5,
        mineral: 2),
    ElevageRecipe(
        id: 'POTAGER_VERTICAL',
        label: 'Potager vertical',
        installationId: 'POTAGER_VERTICAL',
        organic: 4,
        mineral: 2,
        special: <String, int>{'SEED': 1},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'LITIERE_FONGIQUE',
        label: 'Litière fongique',
        installationId: 'LITIERE_FONGIQUE',
        organic: 4,
        mineral: 2),
    ElevageRecipe(
        id: 'BAC_GRAVIER',
        label: 'Bac à gravier',
        installationId: 'BAC_GRAVIER',
        organic: 1,
        mineral: 5),
    ElevageRecipe(
        id: 'BIBLIOTHEQUE_DATABUG',
        label: 'Bibliothèque Databug',
        installationId: 'BIBLIOTHEQUE_DATABUG',
        organic: 3,
        mineral: 3),
    ElevageRecipe(
        id: 'PARCOURS_OBSTACLES',
        label: 'Parcours d’obstacles',
        installationId: 'PARCOURS_OBSTACLES',
        organic: 5,
        mineral: 3),
    ElevageRecipe(
        id: 'CRISTAL_DECORATIF',
        label: 'Cristal décoratif',
        installationId: 'CRISTAL_DECORATIF',
        organic: 0,
        mineral: 0,
        special: <String, int>{'QUARTZ': 1},
        unlockItems: <String>['QUARTZ']),
    ElevageRecipe(
        id: 'GEODE_DECORATIVE',
        label: 'Géode décorative',
        installationId: 'GEODE_DECORATIVE',
        organic: 0,
        mineral: 2),
    ElevageRecipe(
        id: 'PLANTE_DECORATIVE',
        label: 'Plante décorative',
        installationId: 'PLANTE_DECORATIVE',
        organic: 2,
        mineral: 0,
        special: <String, int>{'SPROUT': 1},
        unlockItems: <String>['SPROUT']),
    ElevageRecipe(
        id: 'MOUSSE_DECORATIVE',
        label: 'Mousse décorative',
        installationId: 'MOUSSE_DECORATIVE',
        organic: 2,
        mineral: 0,
        special: <String, int>{'MOSS': 1},
        unlockItems: <String>['MOSS']),
    ElevageRecipe(
        id: 'PIERRE_DECORATIVE',
        label: 'Pierre décorative',
        installationId: 'PIERRE_DECORATIVE',
        organic: 0,
        mineral: 2),
    ElevageRecipe(
        id: 'CARILLON',
        label: 'Carillon',
        installationId: 'CARILLON',
        organic: 1,
        mineral: 2),
    ElevageRecipe(
        id: 'CONQUE_MUSICALE',
        label: 'Conque musicale',
        installationId: 'CONQUE_MUSICALE',
        organic: 2,
        mineral: 1),
  ],
);

String encodeConfig(ElevageConfig config) => jsonEncode(<String, dynamic>{
      'schemaVersion': elevageConfigSchemaVersion,
      'revision': config.revision,
      'overrides': config.toJson(),
    });
