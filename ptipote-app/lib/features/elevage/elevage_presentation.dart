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

  static String friendlyError(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.contains('non disponible')) {
      return 'Cet objet n’est plus disponible.';
    }
    if (value.contains('insuffisante')) {
      return 'Vous ne possédez pas assez de ressources.';
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
