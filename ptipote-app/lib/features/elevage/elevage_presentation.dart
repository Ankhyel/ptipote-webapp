import 'package:flutter/material.dart';

import 'elevage_engine.dart';

/// Couche de présentation : les IDs du domaine restent stables et anglais,
/// tandis que les libellés, pictos et retours sont pensés pour le joueur.
class ElevagePresentation {
  static const Map<String, _ItemVisual> _items = <String, _ItemVisual>{
    'ROOT': _ItemVisual('Racine', Icons.grass_outlined, 'Nourriture'),
    'LEAF': _ItemVisual('Feuille', Icons.eco_outlined, 'Nourriture'),
    'MOSS': _ItemVisual('Mousse', Icons.terrain_outlined, 'Nourriture'),
    'ALGAE': _ItemVisual('Algues', Icons.waves_outlined, 'Nourriture'),
    'MUSHROOM': _ItemVisual('Champignon', Icons.park_outlined, 'Nourriture'),
    'FRUIT': _ItemVisual('Fruit', Icons.apple_outlined, 'Nourriture'),
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
  static List<int> stackQuantities(int quantity, int maxStack) {
    if (quantity <= 0 || maxStack <= 0) return const <int>[];
    final stacks = <int>[];
    var remaining = quantity;
    while (remaining > 0) {
      final current = remaining > maxStack ? maxStack : remaining;
      stacks.add(current);
      remaining -= current;
    }
    return stacks;
  }

  static int environmentScale(int value) => value.clamp(0, 5);

  static String installationLabel(String id) => switch (id) {
        'BASSIN' => 'Bassin',
        'MOSS_STONE' => 'Pierre de mousse',
        'CULTURE_POTAGERE' => 'Culture potagère',
        'BUTTE_ARBUSTE' => 'Butte d’arbuste',
        'GEODE_FERRIQUE' || 'FORMATION_METALLIQUE' => 'Formation métallique',
        'GEODE_CRISTALLINE' ||
        'FORMATION_CRISTALLINE' =>
          'Formation cristalline',
        'FORMATION_MINERALE' => 'Formation minérale',
        'LAMPE_SOLAIRE' => 'Lampe solaire',
        'ABRI_FIBREUX' => 'Abri fibreux',
        'ABRI_MINERAL_PROFOND' => 'Abri minéral profond',
        'VENTILATION' => 'Ventilation',
        'TROU_GEOTHERMIQUE_CHAUD' => 'Trou géothermique chaud',
        'TOIT_SERRE' => 'Toit de serre',
        'HAMAC' => 'Hamac',
        'NID_COUCHETTE' => 'Nid / couchette',
        'POTAGER_VERTICAL' => 'Potager vertical',
        'LITIERE_FONGIQUE' => 'Litière fongique',
        'BAC_GRAVIER' => 'Bac à gravier',
        'BIBLIOTHEQUE_DATABUG' => 'Bibliothèque Databug',
        'PARCOURS_OBSTACLES' => 'Parcours d’obstacles',
        'PLANTE_DECORATIVE' => 'Plante décorative',
        'MOUSSE_DECORATIVE' => 'Mousse décorative',
        'CRISTAL_DECORATIF' => 'Cristal décoratif',
        'GEODE_DECORATIVE' => 'Géode décorative',
        'PIERRE_DECORATIVE' => 'Pierre décorative',
        'CARILLON' => 'Carillon',
        'CONQUE_MUSICALE' => 'Conque musicale',
        _ => 'Installation inconnue',
      };

  static IconData installationIcon(String id) => switch (id) {
        'BASSIN' => Icons.water_outlined,
        'MOSS_STONE' => Icons.terrain_outlined,
        'CULTURE_POTAGERE' => Icons.grass_outlined,
        'BUTTE_ARBUSTE' => Icons.park_outlined,
        'GEODE_FERRIQUE' ||
        'GEODE_CRISTALLINE' ||
        'FORMATION_METALLIQUE' ||
        'FORMATION_CRISTALLINE' ||
        'FORMATION_MINERALE' =>
          Icons.diamond_outlined,
        'LAMPE_SOLAIRE' => Icons.light_mode_outlined,
        'VENTILATION' => Icons.air_outlined,
        'TOIT_SERRE' => Icons.roofing_outlined,
        'HAMAC' || 'NID_COUCHETTE' => Icons.bed_outlined,
        'POTAGER_VERTICAL' => Icons.yard_outlined,
        'LITIERE_FONGIQUE' => Icons.terrain_outlined,
        'BAC_GRAVIER' => Icons.grain_outlined,
        'BIBLIOTHEQUE_DATABUG' => Icons.menu_book_outlined,
        'PARCOURS_OBSTACLES' => Icons.route_outlined,
        'PLANTE_DECORATIVE' ||
        'MOUSSE_DECORATIVE' =>
          Icons.local_florist_outlined,
        'CRISTAL_DECORATIF' ||
        'GEODE_DECORATIVE' ||
        'PIERRE_DECORATIVE' =>
          Icons.auto_awesome_outlined,
        'CARILLON' || 'CONQUE_MUSICALE' => Icons.music_note_outlined,
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

  /// Text appears only after repeated scene behaviour; the first interaction
  /// is intentionally represented by a behaviour icon alone.
  static String sceneObservationFeedback(
      ElevageSceneItemOutcome outcome, String item, String name) {
    if (outcome.behavior == 'MOVE_ITEM') {
      return '$name déplace souvent sa nourriture avant de la manger.';
    }
    if (outcome.behavior == 'STEP_BACK' && item == 'QUARTZ') {
      return '$name examine le quartz puis s’en détourne.';
    }
    if (outcome.behavior == 'RUSH_SHAKE') {
      return '$name semble particulièrement attiré par les ${_foodPlural(item)}.';
    }
    if (outcome.behavior == 'VIBRATE') {
      return '$name réagit particulièrement au fer.';
    }
    return '$name observe ${_withArticle(item)} avec attention.';
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
      'HUMIDITY_AVOIDANCE' => '$name repart rapidement de cette zone.',
      'FOLLOW' => '$name suit volontiers vos mouvements.',
      'CUDDLE' => '$name semble apprécier vos caresses.',
      _ => '$name a observé son environnement.',
    };
  }

  static String hypothesisText(Map observation, String name) =>
      switch (observation['type']) {
        'FOOD_FAVORITE' =>
          '$name semble apprécier les ${_foodPlural(observation['relatedItemId'] as String)}.',
        'STRUCTURAL_REACTION' => '$name semble réagir particulièrement au fer.',
        'LIGHT_SHADE' => '$name semble préférer les zones peu éclairées.',
        'HUMIDITY_AVOIDANCE' => '$name semble éviter les zones trop humides.',
        'FOLLOW' => '$name semble attentif à votre présence.',
        'CUDDLE' => '$name semble apprécier votre présence.',
        _ => '$name semble avoir une préférence à explorer.',
      };

  static String? hypothesisAdvice(Map observation) =>
      switch (observation['type']) {
        'LIGHT_SHADE' => 'Essayez de lui proposer davantage d’ombre.',
        'HUMIDITY_AVOIDANCE' => 'Essayez une zone un peu moins humide.',
        _ => null,
      };

  static String confirmedText(Map observation) => switch (observation['type']) {
        'FOOD_FAVORITE' =>
          'Préférence alimentaire : ${itemLabel(observation['relatedItemId'] as String)}',
        'STRUCTURAL_REACTION' => 'Matériau structurel principal : Fer',
        'LIGHT_SHADE' =>
          'Confort lumineux : 1–2/5 · neutre 3/5 · inconfort 4–5/5',
        'HUMIDITY_AVOIDANCE' =>
          'Sensibilité environnementale : humidité élevée',
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
