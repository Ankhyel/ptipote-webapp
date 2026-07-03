import 'dart:convert';

import 'package:flutter/services.dart';

class GameAssetResolver {
  GameAssetResolver({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  static const _basePath = 'assets/image_game/';
  static const _extensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'JPG',
    'JPEG',
    'PNG',
    'WEBP',
  ];

  Future<String?> resolve(String screenName) async {
    final cleanName = screenName.trim();
    if (cleanName.isEmpty) return null;

    final candidates = _extensions
        .map((extension) => '$_basePath$cleanName.$extension')
        .toList();

    try {
      final manifestText = await _bundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
      for (final candidate in candidates) {
        if (manifest.containsKey(candidate)) return candidate;
      }
    } catch (_) {
      // AssetManifest can be unavailable in some tests; try direct loads below.
    }

    for (final candidate in candidates) {
      try {
        await _bundle.load(candidate);
        return candidate;
      } catch (_) {
        // Keep trying other extensions.
      }
    }

    return null;
  }
}
