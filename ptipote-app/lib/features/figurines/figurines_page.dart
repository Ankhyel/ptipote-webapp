import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import 'ptipote_figurine.dart';

class FigurinesPage extends StatelessWidget {
  const FigurinesPage({super.key, this.service});

  static const route = '/figurines';

  final FigurineService? service;

  @override
  Widget build(BuildContext context) {
    final figurineService = service ?? FigurineService();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes PTIPOTE')),
      body: StreamBuilder<List<PtipoteFigurine>>(
        stream: figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Chargement impossible: ${snapshot.error}'),
            );
          }

          final figurines = snapshot.data ?? const <PtipoteFigurine>[];
          if (figurines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune figurine enregistree.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) => _FigurineCard(figurine: figurines[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: figurines.length,
          );
        },
      ),
    );
  }
}

class _FigurineCard extends StatelessWidget {
  const _FigurineCard({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(figurine.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _Chip(label: 'UID', value: figurine.tagUid),
                _Chip(label: 'Espece', value: figurine.species),
                _Chip(label: 'Type', value: figurine.type),
                _Chip(label: 'Niveau', value: figurine.level),
                _Chip(label: 'XP', value: figurine.xp),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: ${value.trim().isEmpty ? '-' : value}'));
  }
}
