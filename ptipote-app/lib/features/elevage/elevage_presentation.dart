import 'package:flutter/material.dart';

/// Couche de présentation : les IDs du domaine restent stables et anglais,
/// tandis que les libellés, pictos et retours sont pensés pour le joueur.
class ElevagePresentation {
  static const Map<String, _ItemVisual> _items = <String, _ItemVisual>{
    'ROOT': _ItemVisual('Racine', Icons.grass_outlined, 'Nourriture'),
    'LEAF': _ItemVisual('Feuille', Icons.eco_outlined, 'Nourriture'),
    'MOSS': _ItemVisual('Mousse', Icons.terrain_outlined, 'Nourriture'),
    'ALGAE': _ItemVisual('Algues', Icons.waves_outlined, 'Nourriture'),
    'MUSHROOM': _ItemVisual('Champignon', Icons.park_outlined, 'Nourriture'),
    'FIBROUS_FRUIT':
        _ItemVisual('Fruit fibreux', Icons.apple_outlined, 'Friandises'),
    'FRUIT_JELLY':
        _ItemVisual('Jelly fruité', Icons.icecream_outlined, 'Friandises'),
    'IRON': _ItemVisual('Fer', Icons.hardware_outlined, 'Matériaux'),
    'LIMESTONE': _ItemVisual('Calcaire', Icons.landscape_outlined, 'Matériaux'),
    'QUARTZ': _ItemVisual('Quartz', Icons.diamond_outlined, 'Matériaux'),
    'ORGANIC': _ItemVisual('Organique', Icons.spa_outlined, 'Ressources'),
    'MINERAL': _ItemVisual('Minéral', Icons.category_outlined, 'Ressources'),
    'SEED': _ItemVisual('Graine', Icons.grain_outlined, 'Ressources'),
    'SPROUT': _ItemVisual('Pousse', Icons.yard_outlined, 'Ressources'),
    'ALGAE_FRAGMENT': _ItemVisual(
        'Fragment d’algue', Icons.water_drop_outlined, 'Ressources'),
  };

  static String itemLabel(String id) => _items[id]?.label ?? 'Objet inconnu';
  static IconData itemIcon(String id) => _items[id]?.icon ?? Icons.help_outline;
  static String itemCategory(String id) => _items[id]?.category ?? 'Ressources';
  static int environmentScale(int relativeValue) =>
      (relativeValue + 3).clamp(1, 5);

  static String installationLabel(String id) => switch (id) {
        'BASSIN' => 'Bassin',
        'MOSS_STONE' => 'Pierre de mousse',
        'CULTURE_POTAGERE' => 'Culture potagère',
        'BUTTE_ARBUSTE' => 'Butte d’arbuste',
        'GEODE_FERRIQUE' => 'Géode ferrique',
        'GEODE_CRISTALLINE' => 'Géode cristalline',
        'LAMPE_SOLAIRE' => 'Lampe solaire',
        'ABRI_FIBREUX' => 'Abri fibreux',
        'ABRI_MINERAL_PROFOND' => 'Abri minéral profond',
        'VENTILATION' => 'Ventilation',
        'TROU_GEOTHERMIQUE_CHAUD' => 'Trou géothermique chaud',
        'TOIT_SERRE' => 'Toit de serre',
        _ => 'Installation inconnue',
      };

  static IconData installationIcon(String id) => switch (id) {
        'BASSIN' => Icons.water_outlined,
        'MOSS_STONE' => Icons.terrain_outlined,
        'CULTURE_POTAGERE' => Icons.grass_outlined,
        'BUTTE_ARBUSTE' => Icons.park_outlined,
        'GEODE_FERRIQUE' || 'GEODE_CRISTALLINE' => Icons.diamond_outlined,
        'LAMPE_SOLAIRE' => Icons.light_mode_outlined,
        'VENTILATION' => Icons.air_outlined,
        'TOIT_SERRE' => Icons.roofing_outlined,
        _ => Icons.cabin_outlined,
      };

  static String reactionFeedback(String reaction, String name) =>
      switch (reaction) {
        'RUSH_SHAKE' => '😊 $name semble ravi.',
        'VIBRATE' => '✨ $name absorbe un peu de matière.',
        'STEP_BACK' => '😕 $name n’apprécie pas beaucoup cela.',
        _ => '😐 $name accepte, sans enthousiasme particulier.',
      };

  static String offerFeedback(String item, String reaction, String name) {
    if (item == 'IRON') {
      return '✨ $name vibre au contact du fer et en absorbe une partie.';
    }
    if (item == 'LIMESTONE') {
      return '✨ $name semble intégrer lentement le calcaire.';
    }
    if (item == 'QUARTZ') {
      return '🤔 $name examine le quartz puis s’en détourne.';
    }
    if (reaction == 'RUSH_SHAKE') {
      return '😊 $name se jette sur ${_withArticle(item)}.';
    }
    if (itemCategory(item) == 'Nourriture') {
      return '😐 $name mange ${_withArticle(item)} calmement.';
    }
    return reactionFeedback(reaction, name);
  }

  static String observationText(Map observation, String name) {
    final item = observation['relatedItemId'] as String?;
    return switch (observation['type']) {
      'FOOD_FAVORITE' =>
        '$name s’approche volontiers des ${_foodPlural(item!)}.',
      'FOOD_ACCEPTED' =>
        '$name mange ${itemLabel(item!).toLowerCase()} sans réaction particulière.',
      'STRUCTURAL_REACTION' => item == 'IRON'
          ? '$name vibre au contact du fer.'
          : '$name intègre lentement le calcaire.',
      'STRUCTURAL_AVOIDED' => '$name examine le quartz puis s’en détourne.',
      'LIGHT_SHADE' => '$name reste volontiers dans les endroits ombragés.',
      _ => '$name a observé son environnement.',
    };
  }

  static String hypothesisText(Map observation, String name) =>
      switch (observation['type']) {
        'FOOD_FAVORITE' =>
          '$name semble apprécier les ${_foodPlural(observation['relatedItemId'] as String)}.',
        'STRUCTURAL_REACTION' => '$name semble réagir particulièrement au fer.',
        'LIGHT_SHADE' => '$name semble préférer les zones peu éclairées.',
        _ => '$name semble avoir une préférence à explorer.',
      };

  static String confirmedText(Map observation) => switch (observation['type']) {
        'FOOD_FAVORITE' =>
          'Préférence alimentaire : ${itemLabel(observation['relatedItemId'] as String)}',
        'STRUCTURAL_REACTION' => 'Matériau structurel principal : Fer',
        'LIGHT_SHADE' => 'Préférence lumineuse : faible lumière',
        _ => 'Découverte confirmée',
      };

  static String _foodPlural(String item) => switch (item) {
        'ROOT' => 'racines',
        'LEAF' => 'feuilles',
        'MOSS' => 'mousses',
        'ALGAE' => 'algues',
        'MUSHROOM' => 'champignons',
        _ => itemLabel(item).toLowerCase(),
      };

  static String _withArticle(String item) => switch (item) {
        'ROOT' => 'la racine',
        'LEAF' => 'la feuille',
        'MOSS' => 'la mousse',
        'ALGAE' => 'les algues',
        'MUSHROOM' => 'le champignon',
        'FIBROUS_FRUIT' => 'le fruit fibreux',
        'FRUIT_JELLY' => 'le jelly fruité',
        _ => itemLabel(item).toLowerCase(),
      };

  static String friendlyError(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.contains('non disponible')) {
      return 'Cet objet n’est plus disponible.';
    }
    if (value.contains('insuffisante')) {
      return 'Vous ne possédez pas assez de ressources.';
    }
    if (value.contains('n’a pas faim')) {
      return 'Votre P’TIPOTE n’a pas faim pour le moment.';
    }
    return 'Cette action ne peut pas être réalisée pour le moment.';
  }
}

class _ItemVisual {
  const _ItemVisual(this.label, this.icon, this.category);
  final String label;
  final IconData icon;
  final String category;
}
