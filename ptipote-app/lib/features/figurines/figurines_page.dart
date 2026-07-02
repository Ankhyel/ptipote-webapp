import 'package:flutter/material.dart';

import '../../services/friend_service.dart';
import '../../services/figurine_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_profile_service.dart';
import '../chat/chat_page.dart';
import '../nfc/nfc_page.dart';
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
  late final FriendService _friendService;
  late final NotificationService _notificationService;
  late final UserProfileService _profileService;
  List<PtipoteFigurine> _lastFigurines = const <PtipoteFigurine>[];
  List<String> _manualOrderIds = const <String>[];
  bool _transferMode = false;
  bool _showDevData = false;
  PtipoteFigurine? _selectedTransfer;
  String? _status;

  @override
  void initState() {
    super.initState();
    _figurineService = widget.service ?? FigurineService();
    _friendService = FriendService();
    _notificationService = NotificationService();
    _profileService = UserProfileService();
    Future.microtask(_figurineService.markTransferNotificationsAsRead);
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

    if (!mounted ||
        nickname == null ||
        nickname.trim().isEmpty ||
        !figurine.canRename) {
      return;
    }
    await _figurineService.renameMyFigurine(
      figurine: figurine,
      nickname: nickname,
    );
  }

  Future<void> _transferAction() async {
    final selected = _selectedTransfer;
    if (!_transferMode || selected == null) {
      setState(() {
        _transferMode = true;
        _status = 'Sélectionne un PTIPOTE à transférer.';
      });
      return;
    }

    if (selected.transferRequested) {
      await _figurineService.cancelTransfer(selected);
      setState(() {
        _transferMode = false;
        _selectedTransfer = null;
        _status = 'Transfert annulé.';
      });
      return;
    }

    final friend = await _chooseFriend();
    if (friend == null) return;

    final sent = await _confirmTransferRequest(selected, friend);
    if (!mounted) return;
    setState(() {
      _transferMode = false;
      _selectedTransfer = null;
      _status = sent
          ? 'Demande de transfert envoyée à ${friend.ownerName}.'
          : 'Transfert annulé.';
    });

    if (!sent) return;
  }

  Future<bool> _confirmTransferRequest(
    PtipoteFigurine figurine,
    FriendProfile friend,
  ) async {
    var sending = false;
    var sent = false;
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> send() async {
            setDialogState(() {
              sending = true;
              error = null;
            });
            try {
              final profile = await _profileService.getOrCreateMyProfile();
              await _figurineService.requestTransfer(
                figurine: figurine,
                fromProfile: profile,
                friend: friend,
              );
              setDialogState(() {
                sending = false;
                sent = true;
              });
            } catch (exception) {
              setDialogState(() {
                sending = false;
                error = exception.toString();
              });
            }
          }

          return AlertDialog(
            title: Text(
                sent ? 'Demande envoyée' : 'Confirmer la demande de transfert'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (sending) ...<Widget>[
                  const Center(
                    child: SizedBox.square(
                      dimension: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Envoi de la demande...',
                    textAlign: TextAlign.center,
                  ),
                ] else if (sent) ...<Widget>[
                  const Text('Demande envoyée en attente de l’ami.'),
                ] else ...<Widget>[
                  Text(
                    'Voulez-vous vraiment faire la demande de transfert de ${figurine.displayName} à ${friend.ownerName} ?',
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ],
            ),
            actions: <Widget>[
              if (sent)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('OK'),
                )
              else ...<Widget>[
                TextButton(
                  onPressed:
                      sending ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Non'),
                ),
                FilledButton(
                  onPressed: sending ? null : send,
                  child: const Text('Oui'),
                ),
              ],
            ],
          );
        },
      ),
    );
    return result == true;
  }

  Future<void> _acceptTransfer(PendingTransfer transfer) async {
    await _figurineService.acceptTransferRequest(transfer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transfert accepté. Scan de la figurine requis.'),
      ),
    );
  }

  Future<void> _rejectTransfer(PendingTransfer transfer) async {
    await _figurineService.rejectTransferRequest(transfer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transfert refusé.')),
    );
  }

  void _showTransferDetails(PendingTransfer transfer) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          transfer.nickname.trim().isEmpty
              ? 'PTIPOTE à transférer'
              : transfer.nickname,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Éleveur actuel: ${transfer.fromName}'),
            Text(
              'Espèce: ${transfer.species.trim().isEmpty ? '-' : transfer.species}',
            ),
            Text('Type: ${transfer.type.trim().isEmpty ? '-' : transfer.type}'),
            Text('Rareté: ${_rarityLabel(transfer.fields['r'] ?? '')}'),
            Text('Niveau: ${transfer.fields['l'] ?? '-'}'),
            Text('XP: ${transfer.fields['x'] ?? '-'}'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<FriendProfile?> _chooseFriend() {
    return showModalBottomSheet<FriendProfile>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _FriendPicker(
        friendService: _friendService,
        profileService: _profileService,
      ),
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
      appBar: AppBar(title: const Text('Mes PTIPOTES')),
      body: StreamBuilder<UserProfile?>(
        stream: _profileService.watchMyProfile(),
        builder: (context, profileSnapshot) {
          final canSeeDevData =
              profileSnapshot.data?.canSeeDiagnostics ?? false;
          final showDevData = canSeeDevData && _showDevData;

          return StreamBuilder<List<PtipoteFigurine>>(
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
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (canSeeDevData) ...<Widget>[
                        _DevDataToggle(
                          enabled: _showDevData,
                          onChanged: (value) =>
                              setState(() => _showDevData = value),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _IncomingTransfersSection(
                        figurineService: _figurineService,
                        onAccept: _acceptTransfer,
                        onReject: _rejectTransfer,
                        onDetails: _showTransferDetails,
                      ),
                      const SizedBox(height: 220),
                      const Padding(
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
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (canSeeDevData) ...<Widget>[
                            _DevDataToggle(
                              enabled: _showDevData,
                              onChanged: (value) =>
                                  setState(() => _showDevData = value),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _IncomingTransfersSection(
                            figurineService: _figurineService,
                            onAccept: _acceptTransfer,
                            onReject: _rejectTransfer,
                            onDetails: _showTransferDetails,
                          ),
                          _TransferRejectionsSection(
                            notificationService: _notificationService,
                          ),
                          FilledButton.icon(
                            onPressed: _transferAction,
                            icon: Icon(
                                _selectedTransfer?.transferRequested == true
                                    ? Icons.close
                                    : Icons.ios_share),
                            label: Text(
                              !_transferMode
                                  ? 'Transférer un PTIPOTE'
                                  : _selectedTransfer == null
                                      ? 'Sélectionne une carte'
                                      : _selectedTransfer!.transferRequested
                                          ? 'Annuler'
                                          : 'Transférer à...',
                            ),
                          ),
                          if (_status != null) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(_status!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: figurines.length,
                        onReorderItem: _reorderFigurines,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 1, end: 1.02)
                                .animate(animation),
                            child: child,
                          ),
                        ),
                        itemBuilder: (context, index) => Padding(
                          key: ValueKey(figurines[index].id),
                          padding: EdgeInsets.only(
                            bottom: index == figurines.length - 1 ? 0 : 12,
                          ),
                          child: GestureDetector(
                            onTap: _transferMode
                                ? () {
                                    final figurine = figurines[index];
                                    if (!figurine.canTransfer &&
                                        !figurine.transferRequested) {
                                      setState(() {
                                        _status =
                                            'Ce PTIPOTE est verrouillé pour le moment.';
                                      });
                                      return;
                                    }
                                    setState(
                                        () => _selectedTransfer = figurine);
                                  }
                                : null,
                            child: _FigurineCard(
                              figurine: figurines[index],
                              showDevData: showDevData,
                              selected:
                                  _selectedTransfer?.id == figurines[index].id,
                              onRename: () => _renameFigurine(figurines[index]),
                              onScan: () => Navigator.of(context).pushNamed(
                                NfcPage.route,
                              ),
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
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DevDataToggle extends StatelessWidget {
  const _DevDataToggle({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile.adaptive(
        value: enabled,
        onChanged: onChanged,
        secondary: const Icon(Icons.bug_report_outlined),
        title: const Text(
          'Données dev',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          enabled
              ? 'UID, batch et champs techniques visibles.'
              : 'Infos publiques uniquement.',
        ),
      ),
    );
  }
}

class _FigurineCard extends StatelessWidget {
  const _FigurineCard({
    required this.figurine,
    required this.showDevData,
    required this.selected,
    required this.onRename,
    required this.onScan,
    required this.dragHandle,
  });

  final PtipoteFigurine figurine;
  final bool showDevData;
  final bool selected;
  final VoidCallback onRename;
  final VoidCallback onScan;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xp = _xpValue(figurine.xp);
    final progress = (xp / 100).clamp(0.0, 1.0);
    final lockMessage = figurine.lockMessage;
    final renameLockMessage = figurine.renameLockMessage;

    return Stack(
      children: <Widget>[
        Card(
          color: selected ? const Color(0xFFE3FDF7) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Opacity(
                  opacity: figurine.isTransferLocked ? 0.3 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 196,
                            child: _AvatarWithRarity(figurine: figurine),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _InfoCard(
                                  label: 'Espece',
                                  value: figurine.species,
                                ),
                                const SizedBox(height: 8),
                                _InfoCard(label: 'Type', value: figurine.type),
                                const SizedBox(height: 8),
                                _InfoCard(
                                  label: 'Surnom',
                                  value: figurine.displayName,
                                  trailing: IconButton(
                                    tooltip: 'Modifier le surnom',
                                    onPressed:
                                        figurine.canRename ? onRename : null,
                                    icon: const Icon(Icons.edit, size: 18),
                                  ),
                                ),
                                if (renameLockMessage.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    renameLockMessage,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconTheme(
                            data: IconThemeData(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            child: dragHandle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoCard(label: 'Eleveur', value: figurine.ownerName),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Niveau',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              figurine.level.trim().isEmpty
                                  ? '-'
                                  : figurine.level,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 11,
                                backgroundColor: const Color(0xFFE8D9BD),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$xp / 100 XP',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (lockMessage.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    lockMessage,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
                if (figurine.needsTransferScan) ...<Widget>[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: onScan,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Scanner PTIPOTE'),
                  ),
                ],
                if (showDevData) ...<Widget>[
                  const SizedBox(height: 12),
                  _FigurineDevData(figurine: figurine),
                ],
              ],
            ),
          ),
        ),
        if (selected)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x3333281E),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.check, color: colorScheme.onPrimary),
            ),
          ),
      ],
    );
  }

  int _xpValue(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}

class _FigurineDevData extends StatelessWidget {
  const _FigurineDevData({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    final fields = Map<String, String>.from(figurine.fields);
    final primaryRows = <_DevDataRow>[
      _DevDataRow('UID puce', figurine.tagUid),
      _DevDataRow('Document', figurine.id),
      _DevDataRow('Public key', figurine.publicKey),
      _DevDataRow('Batch', fields['b'] ?? ''),
      _DevDataRow('Source NDEF', figurine.rawSource),
      _DevDataRow('Statut transfert', figurine.transferStatus),
      _DevDataRow('Transfert (te)', fields['te'] ?? ''),
      _DevDataRow('Transfert confirme (ter)', fields['ter'] ?? ''),
      _DevDataRow('Eleveur origine', figurine.transferFromName),
      _DevDataRow(
        'Verrou transfert',
        figurine.transferLockedUntil?.toIso8601String() ?? '',
      ),
      _DevDataRow(
        'Verrou surnom',
        figurine.renameLockedUntil?.toIso8601String() ?? '',
      ),
      _DevDataRow('Cree le', figurine.createdAt.toIso8601String()),
      _DevDataRow('Mis a jour le', figurine.updatedAt.toIso8601String()),
    ];

    final fieldRows = fields.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2E8D6),
        border: Border.all(color: const Color(0xFFD2BD93)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              const Text(
                'Données dev',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in primaryRows)
            _DevDataLine(label: row.label, value: row.value),
          if (fieldRows.isNotEmpty) ...<Widget>[
            const Divider(height: 18),
            const Text(
              'Champs NDEF / Firestore',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final field in fieldRows)
                  _DevFieldChip(label: field.key, value: field.value),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DevDataRow {
  const _DevDataRow(this.label, this.value);

  final String label;
  final String value;
}

class _DevDataLine extends StatelessWidget {
  const _DevDataLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            cleanValue,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DevFieldChip extends StatelessWidget {
  const _DevFieldChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim().isEmpty ? '-' : value.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        border: Border.all(color: const Color(0xFFE0CFAE)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: cleanValue),
          ],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _IncomingTransfersSection extends StatelessWidget {
  const _IncomingTransfersSection({
    required this.figurineService,
    required this.onAccept,
    required this.onReject,
    required this.onDetails,
  });

  final FigurineService figurineService;
  final ValueChanged<PendingTransfer> onAccept;
  final ValueChanged<PendingTransfer> onReject;
  final ValueChanged<PendingTransfer> onDetails;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PendingTransfer>>(
      stream: figurineService.watchIncomingTransfers(),
      builder: (context, snapshot) {
        final transfers = snapshot.data ?? const <PendingTransfer>[];
        if (transfers.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Demandes de transfert',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            for (final transfer in transfers) ...<Widget>[
              _IncomingTransferCard(
                transfer: transfer,
                onAccept: () => onAccept(transfer),
                onReject: () => onReject(transfer),
                onDetails: () => onDetails(transfer),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _TransferRejectionsSection extends StatelessWidget {
  const _TransferRejectionsSection({required this.notificationService});

  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PtipoteNotification>>(
      stream: notificationService.watchMyNotifications(),
      builder: (context, snapshot) {
        final rejections = (snapshot.data ?? const <PtipoteNotification>[])
            .where((item) => item.type == 'transfer_rejected')
            .take(3)
            .toList();
        if (rejections.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final notification in rejections) ...<Widget>[
              Card(
                color: const Color(0xFFFFFCF4),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          notification.body.trim().isEmpty
                              ? 'Votre demande de transfert a été refusée.'
                              : notification.body,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _IncomingTransferCard extends StatelessWidget {
  const _IncomingTransferCard({
    required this.transfer,
    required this.onAccept,
    required this.onReject,
    required this.onDetails,
  });

  final PendingTransfer transfer;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final type = transfer.type.trim().isEmpty ? '-' : transfer.type;
    final species = transfer.species.trim().isEmpty ? '-' : transfer.species;
    final nickname = transfer.nickname.trim().isEmpty
        ? 'PTIPOTE sans nom'
        : transfer.nickname;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            ClipOval(
              child: SizedBox.square(
                dimension: 86,
                child: ColoredBox(
                  color: const Color(0xFFFFFCF4),
                  child: PtipoteImage(
                    type: transfer.type,
                    species: transfer.species,
                    height: 86,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    nickname,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text('De ${transfer.fromName}'),
                  Text(
                    'Espèce: $species',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$type · ${_rarityLabel(transfer.fields['r'] ?? '')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Voir la fiche',
              onPressed: onDetails,
              icon: const Icon(Icons.expand_more),
            ),
            IconButton.filled(
              tooltip: 'Accepter',
              onPressed: onAccept,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF6EA86B),
              ),
              icon: const Icon(Icons.check),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: 'Refuser',
              onPressed: onReject,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarWithRarity extends StatelessWidget {
  const _AvatarWithRarity({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        _PtipoteAvatar(figurine: figurine),
        Positioned(
          left: 6,
          bottom: 6,
          child: _RarityBadge(
            value: figurine.fields['r'] ?? '',
          ),
        ),
      ],
    );
  }
}

class _RarityBadge extends StatelessWidget {
  const _RarityBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final label = _rarityLabel(value);
    final stars = _rarityStars(value);
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.tap,
      decoration: BoxDecoration(
        color: const Color(0xFFC9A36D),
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
      ),
      child: Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: _rarityColorFor(value),
          border: Border.all(color: const Color(0xFFD2BD93), width: 2),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x3333281E),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(
              stars,
              (_) => const Icon(
                Icons.star_rounded,
                color: Color(0xFF8A6A22),
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PtipoteAvatar extends StatelessWidget {
  const _PtipoteAvatar({required this.figurine});

  final PtipoteFigurine figurine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 192,
      height: 192,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFD2BD93),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        scale: 1.5,
        child: PtipoteImage(
          type: figurine.type,
          species: figurine.species,
          height: 192,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        border: Border.all(color: const Color(0xFFE0CFAE)),
        borderRadius: BorderRadius.circular(18),
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

Color _rarityColorFor(String? value) {
  switch (value?.trim()) {
    case '1':
      return const Color(0xFFE8E4DD);
    case '2':
      return const Color(0xFFD9ECFF);
    case '3':
      return const Color(0xFFE8D8FF);
    case '4':
      return const Color(0xFFFFE7A8);
    default:
      return const Color(0xFFFFFCF4);
  }
}

String _rarityLabel(String value) {
  switch (value.trim()) {
    case '1':
      return 'Commun';
    case '2':
      return 'Spéciale';
    case '3':
      return 'Rare';
    case '4':
      return 'Légendaire';
    default:
      return value.trim().isEmpty ? '-' : value;
  }
}

int _rarityStars(String value) {
  final parsed = int.tryParse(value.trim()) ?? 0;
  if (parsed <= 0) return 1;
  if (parsed >= 4) return 5;
  return parsed;
}

class _FriendPicker extends StatefulWidget {
  const _FriendPicker({
    required this.friendService,
    required this.profileService,
  });

  final FriendService friendService;
  final UserProfileService profileService;

  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  final _searchController = TextEditingController();
  List<FriendProfile> _results = const <FriendProfile>[];
  bool _searching = false;
  String? _status;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _status = null;
    });
    try {
      final results = await widget.friendService.searchUsers(
        _searchController.text,
      );
      setState(() {
        _results = results;
        _status = results.isEmpty ? 'Aucun éleveur trouvé.' : null;
      });
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(FriendProfile friend) async {
    final profile = await widget.profileService.getOrCreateMyProfile();
    await widget.friendService.sendInvite(fromProfile: profile, to: friend);
    setState(() => _status = 'Invitation envoyée à ${friend.ownerName}.');
  }

  Future<void> _accept(FriendInvite invite) async {
    final profile = await widget.profileService.getOrCreateMyProfile();
    await widget.friendService.acceptInvite(invite, profile);
    setState(() => _status = 'Invitation acceptée.');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            const Text(
              'Choisir un ami',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Rechercher un éleveur',
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ),
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_status!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            for (final result in _results)
              ListTile(
                leading: const Icon(Icons.person_add_alt_1),
                title: Text(result.ownerName),
                subtitle:
                    result.username.isEmpty ? null : Text(result.username),
                trailing: TextButton(
                  onPressed: () => _invite(result),
                  child: const Text('Inviter'),
                ),
              ),
            const SizedBox(height: 12),
            StreamBuilder<List<FriendInvite>>(
              stream: widget.friendService.watchIncomingInvites(),
              builder: (context, snapshot) {
                final invites = snapshot.data ?? const <FriendInvite>[];
                if (invites.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Invitations reçues',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    for (final invite in invites)
                      ListTile(
                        leading: const Icon(Icons.mark_email_unread_outlined),
                        title: Text(invite.fromName),
                        trailing: FilledButton(
                          onPressed: () => _accept(invite),
                          child: const Text('Accepter'),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('Mes amis',
                style: TextStyle(fontWeight: FontWeight.w900)),
            StreamBuilder<List<FriendProfile>>(
              stream: widget.friendService.watchFriends(),
              builder: (context, snapshot) {
                final friends = snapshot.data ?? const <FriendProfile>[];
                if (friends.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Aucun ami pour le moment.'),
                  );
                }
                return Column(
                  children: friends
                      .map(
                        (friend) => ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(friend.ownerName),
                          subtitle: friend.username.isEmpty
                              ? null
                              : Text(friend.username),
                          trailing: IconButton(
                            tooltip: 'Message',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChatPage(friend: friend),
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                          ),
                          onTap: () => Navigator.of(context).pop(friend),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
