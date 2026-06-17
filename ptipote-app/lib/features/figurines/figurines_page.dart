import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
import 'ptipote_figurine.dart';
import 'ptipote_image.dart';

class FigurinesPage extends StatefulWidget {
  const FigurinesPage({super.key, this.service});

  static const route = '/figurines';

  final FigurineService? service;

  @override
  State<FigurinesPage> createState() => _FigurinesPageState();
}

class _FigurinesPageState extends State<FigurinesPage> {
  late final FigurineService _figurineService;

  @override
  void initState() {
    super.initState();
    _figurineService = widget.service ?? FigurineService();
  }

  Future<void> _refresh() => _figurineService.refreshMyFigurinesFromServer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes PTIPOTE')),
      body: StreamBuilder<List<PtipoteFigurine>>(
        stream: _figurineService.watchMyFigurines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const <Widget>[
                  SizedBox(height: 280),
                  Center(child: CircularProgressIndicator()),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text('Chargement impossible: ${snapshot.error}'),
                ],
              ),
            );
          }

          final figurines = snapshot.data ?? const <PtipoteFigurine>[];
          if (figurines.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const <Widget>[
                  SizedBox(height: 260),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune figurine enregistree.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) =>
                  _FigurineCard(figurine: figurines[index]),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: figurines.length,
            ),
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
            PtipoteImage(
                type: figurine.type, species: figurine.species, height: 160),
            const SizedBox(height: 12),
            Text(figurine.displayName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
                _Chip(label: 'Eleveur', value: figurine.ownerName),
                _Chip(label: 'Numero eleveur', value: figurine.breederNumber),
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
