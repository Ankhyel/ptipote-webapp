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
  List<PtipoteFigurine> _lastFigurines = const <PtipoteFigurine>[];
  List<String> _manualOrderIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _figurineService = widget.service ?? FigurineService();
  }

  Future<void> _refresh() => _figurineService.refreshMyFigurinesFromServer();

  Future<void> _renameFigurine(PtipoteFigurine figurine) async {
    final controller = TextEditingController(text: figurine.displayName);
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le surnom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Surnom'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || nickname == null || nickname.trim().isEmpty) return;
    await _figurineService.renameMyFigurine(
      figurine: figurine,
      nickname: nickname,
    );
  }

  Future<void> _reorderFigurines(int oldIndex, int newIndex) async {
    final reordered = List<PtipoteFigurine>.of(_lastFigurines);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() {
      _lastFigurines = reordered;
      _manualOrderIds = reordered.map((figurine) => figurine.id).toList();
    });
    await _figurineService.updateFigurineOrder(reordered);
  }

  List<PtipoteFigurine> _applyManualOrder(List<PtipoteFigurine> figurines) {
    if (_manualOrderIds.isEmpty) return figurines;

    final order = <String, int>{
      for (var i = 0; i < _manualOrderIds.length; i += 1) _manualOrderIds[i]: i,
    };
    final sorted = List<PtipoteFigurine>.of(figurines);
    sorted.sort((a, b) {
      final aOrder = order[a.id] ?? 1 << 30;
      final bOrder = order[b.id] ?? 1 << 30;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return figurines.indexOf(a).compareTo(figurines.indexOf(b));
    });
    return sorted;
  }

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

          final figurines = _applyManualOrder(
            snapshot.data ?? const <PtipoteFigurine>[],
          );
          _lastFigurines = figurines;
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
            child: ReorderableListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: figurines.length,
              onReorderItem: _reorderFigurines,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
                  child: child,
                ),
              ),
              itemBuilder: (context, index) => Padding(
                key: ValueKey(figurines[index].id),
                padding: EdgeInsets.only(
                  bottom: index == figurines.length - 1 ? 0 : 12,
                ),
                child: _FigurineCard(
                  figurine: figurines[index],
                  onRename: () => _renameFigurine(figurines[index]),
                  dragHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Tooltip(
                      message: 'Deplacer',
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FigurineCard extends StatelessWidget {
  const _FigurineCard({
    required this.figurine,
    required this.onRename,
    required this.dragHandle,
  });

  final PtipoteFigurine figurine;
  final VoidCallback onRename;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xp = _xpValue(figurine.xp);
    final progress = (xp / 100).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 108,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PtipoteAvatar(figurine: figurine),
                  const SizedBox(height: 10),
                  _MiniLabel(label: 'Niveau', value: figurine.level),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$xp / 100 XP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MiniLabel(label: 'Eleveur', value: figurine.ownerName),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _InfoCard(label: 'Espece', value: figurine.species),
                  const SizedBox(height: 8),
                  _InfoCard(label: 'Type', value: figurine.type),
                  const SizedBox(height: 8),
                  _InfoCard(
                    label: 'Surnom',
                    value: figurine.displayName,
                    trailing: IconButton(
                      tooltip: 'Modifier le surnom',
                      onPressed: onRename,
                      icon: const Icon(Icons.edit, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconTheme(
              data: IconThemeData(color: colorScheme.onSurfaceVariant),
              child: dragHandle,
            ),
          ],
        ),
      ),
    );
  }

  int _xpValue(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}

class _PtipoteAvatar extends StatelessWidget {
  const _PtipoteAvatar({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: PtipoteImage(
        type: figurine.type,
        species: figurine.species,
        height: 92,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.trim().isEmpty ? '-' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        Text(
          value.trim().isEmpty ? '-' : value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
