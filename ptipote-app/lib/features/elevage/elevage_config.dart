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
    required this.light,
    required this.temperature,
    required this.humidity,
    this.outputs = const <String, int>{},
  });

  final String id;
  final String label;
  final int light;
  final int temperature;
  final int humidity;
  final Map<String, int> outputs;

  bool get productive => outputs.isNotEmpty;
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
  final List<ElevageRecipe> recipes;

  int get babyMinimumHours => preset == ElevagePreset.prototype ? 24 : 48;
  int get intermediateMinimumHours =>
      preset == ElevagePreset.prototype ? 72 : 168;

  List<ElevageInstallationDefinition> get installations =>
      <ElevageInstallationDefinition>[
        const ElevageInstallationDefinition(
          id: 'BASSIN',
          label: 'Bassin',
          light: 0,
          temperature: 0,
          humidity: 2,
          outputs: <String, int>{'ALGAE': 1, 'MOSS': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'MOSS_STONE',
          label: 'Pierre de mousse',
          light: 0,
          temperature: -1,
          humidity: 2,
        ),
        const ElevageInstallationDefinition(
          id: 'CULTURE_POTAGERE',
          label: 'Culture potagère',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'ROOT': 1, 'LEAF': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'BUTTE_ARBUSTE',
          label: 'Butte d’arbuste',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'FRUIT': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'GEODE_FERRIQUE',
          label: 'Géode ferrique',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'IRON': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'GEODE_CRISTALLINE',
          label: 'Géode cristalline',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'QUARTZ': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'LAMPE_SOLAIRE',
          label: 'Lampe solaire',
          light: 2,
          temperature: 1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_FIBREUX',
          label: 'Abri fibreux',
          light: -2,
          temperature: -1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_MINERAL_PROFOND',
          label: 'Abri minéral profond',
          light: -2,
          temperature: -2,
          humidity: 2,
        ),
        const ElevageInstallationDefinition(
          id: 'VENTILATION',
          label: 'Ventilation',
          light: 0,
          temperature: -2,
          humidity: -1,
        ),
        const ElevageInstallationDefinition(
          id: 'TROU_GEOTHERMIQUE_CHAUD',
          label: 'Trou géothermique chaud',
          light: 0,
          temperature: 2,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'TOIT_SERRE',
          label: 'Toit de serre',
          light: 1,
          temperature: 2,
          humidity: 0,
        ),
      ];

  ElevageInstallationDefinition? installation(String id) {
    for (final definition in installations) {
      if (definition.id == id) return definition;
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
double _rate(Object? value, double fallback) =>
    value is num && value >= 0 && value <= 1 ? value.toDouble() : fallback;

void validateElevageConfig(ElevageConfig config) {
  if (config.hungerNormalHours > config.hungerHungryHours ||
      config.hungerHungryHours > config.hungerVeryHungryHours ||
      config.suspectedThreshold > config.confirmedThreshold ||
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
  productionIntervalSeconds: 60,
  productionMaxStock: 2,
  coRearingDurationHours: 168,
  refundOrganicRate: .5,
  refundMineralRate: .5,
  sourcierEnabled: true,
  fibrousFruitPrice: 2,
  fruitJellyPrice: 3,
  buybackQuantity: 5,
  buybackBioPiles: 1,
  metamorphosisToleranceMs: 180,
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
        id: 'GEODE_FERRIQUE',
        label: 'Géode ferrique',
        installationId: 'GEODE_FERRIQUE',
        organic: 0,
        mineral: 5,
        special: <String, int>{'IRON': 1},
        unlockItems: <String>['IRON']),
    ElevageRecipe(
        id: 'GEODE_CRISTALLINE',
        label: 'Géode cristalline',
        installationId: 'GEODE_CRISTALLINE',
        organic: 0,
        mineral: 5,
        special: <String, int>{'QUARTZ': 1},
        unlockItems: <String>['QUARTZ']),
  ],
);

String encodeConfig(ElevageConfig config) => jsonEncode(<String, dynamic>{
      'schemaVersion': elevageConfigSchemaVersion,
      'revision': config.revision,
      'overrides': config.toJson(),
    });
