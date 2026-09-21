import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/figurine_service.dart';
import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_image.dart';
import '../figurines/ptipote_stats_config.dart';
import '../figurines/ptipote_v2.dart';
import '../nfc/nfc_page.dart';
import 'zone0_v2_foundation.dart';
import 'zone0_v2_foundation_service.dart';
import 'zone0_v2_camp_page.dart';
import 'worldcraft_dev_region_page.dart';

/// First-run V2 flow. It is intentionally separate from the V1 Refuge and
/// persists after every irreversible player choice.
class Zone0V2OnboardingPage extends StatefulWidget {
  const Zone0V2OnboardingPage({super.key});

  static const route = '/game/v2';

  @override
  State<Zone0V2OnboardingPage> createState() => _Zone0V2OnboardingPageState();
}

class _Zone0V2OnboardingPageState extends State<Zone0V2OnboardingPage> {
  final Zone0V2FoundationService _foundation = Zone0V2FoundationService();
  final FigurineService _figurines = FigurineService();
  final TextEditingController _nameController = TextEditingController();
  PtipoteV2Profile? _ptipote;
  RegionQuestionOneAnswer _q1 = RegionQuestionOneAnswer.mer;
  RegionQuestionTwoAnswer _q2 = RegionQuestionTwoAnswer.neige;
  RegionQuestionThreeAnswer _q3 = RegionQuestionThreeAnswer.champ;
  bool _loading = true;
  bool _saving = false;
  bool _requiresWorldcraftReset = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final data = await _foundation.load();
      if (!mounted) return;
      if (data?['stage'] == Zone0V2WorldStage.ready.name) {
        if (data?['worldcraft'] is Map) {
          _openCamp(replace: true);
          return;
        }
        _requiresWorldcraftReset = true;
      }
      if (data?['stage'] == Zone0V2WorldStage.questionnaire.name &&
          data?['questionnaire'] is Map) {
        Navigator.of(context)
            .pushReplacementNamed(WorldcraftDevRegionPage.route);
        return;
      }
      final raw = data?['onboardingPtipote'];
      if (raw is Map) {
        _ptipote = PtipoteV2Profile.fromFirebase(
          '${data?['firstPtipoteId'] ?? 'ptipote-v2'}',
          raw,
        );
        _nameController.text = _ptipote!.displayName;
      }
    } catch (_) {
      _error = 'Impossible de reprendre l’onboarding pour le moment.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCamp({bool replace = false}) {
    final route =
        MaterialPageRoute<void>(builder: (_) => const Zone0V2CampPage());
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).pushAndRemoveUntil(route, (route) => route.isFirst);
    }
  }

  Future<void> _saveProfile(Zone0V2WorldStage stage) async {
    final profile = _ptipote;
    if (profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _foundation.saveOnboardingPtipote(profile: profile, stage: stage);
    } catch (_) {
      _error =
          'Enregistrement impossible. Réessaie lorsque la connexion revient.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startWorldcraftMigration() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _foundation.resetLegacyV2TerritoryForWorldcraft();
      if (mounted) {
        Navigator.of(context)
            .pushReplacementNamed(WorldcraftDevRegionPage.route);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Réinitialisation Worldcraft impossible.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adoptDigital(PtipoteTypeId type) async {
    final now = DateTime.now();
    final id = 'digital-${now.microsecondsSinceEpoch}';
    final base = PtipoteV2Profile(
      ptipoteId: id,
      acquisitionOrigin: PtipoteAcquisitionOrigin.digitalAdoption,
      ownershipMode: PtipoteOwnershipMode.owned,
      ptipoteGeneration: PtipoteGeneration.vestige,
      typeId: type,
      natureId: 'adoption-${type.name}',
      systemName: 'P’TIPOTE ${type.name}',
      arrivalState: PtipoteArrivalState.pendingEgg,
      createdAt: now,
      updatedAt: now,
    );
    _ptipote = PtipoteArrivalService.sendPtipoteToIncubator(
      profile: base,
      config: ptipoteStatsConfig.v2,
      systemName: base.systemName,
      now: now,
    );
    await _saveProfile(Zone0V2WorldStage.firstPtipote);
    if (mounted) setState(() {});
  }

  Future<void> _choosePhysical(PtipoteFigurine figurine) async {
    final now = DateTime.now();
    final base = figurine
        .legacyV2Profile(
          baseCarryCapacity: ptipoteStatsConfig.v2.defaultBaseCarryCapacity,
        )
        .copyWith(
          acquisitionOrigin: PtipoteAcquisitionOrigin.physicalScan,
          ownershipMode: PtipoteOwnershipMode.owned,
          systemName: figurine.displayName,
          arrivalState: PtipoteArrivalState.pendingEgg,
          updatedAt: now,
        );
    _ptipote = PtipoteArrivalService.sendPtipoteToIncubator(
      profile: base,
      config: ptipoteStatsConfig.v2,
      systemName: figurine.displayName,
      now: now,
    );
    await _saveProfile(Zone0V2WorldStage.firstPtipote);
    if (mounted) setState(() {});
  }

  Future<void> _activate() async {
    final profile = _ptipote;
    if (profile == null) return;
    _ptipote = PtipoteArrivalService.prepareRhythm(
      profile,
      config: ptipoteStatsConfig.v2,
    );
    await _saveProfile(Zone0V2WorldStage.firstPtipote);
    if (mounted) setState(() {});
  }

  Future<void> _hatch() async {
    final profile = _ptipote;
    if (profile == null) return;
    _ptipote = PtipoteArrivalService.beginRhythm(profile);
    await _saveProfile(Zone0V2WorldStage.firstPtipote);
    if (!mounted || _ptipote == null) return;
    final succeeded = await showDialog<bool>(
      context: context,
      builder: (_) => _BirthRhythmDialog(pattern: _ptipote!.rhythmPattern),
    );
    final current = _ptipote!;
    _ptipote = succeeded == true
        ? PtipoteArrivalService.hatch(current)
        : PtipoteArrivalService.failRhythm(current);
    await _saveProfile(
      succeeded == true
          ? Zone0V2WorldStage.naming
          : Zone0V2WorldStage.firstPtipote,
    );
    if (mounted) setState(() {});
  }

  Future<void> _name() async {
    final profile = _ptipote;
    if (profile == null) return;
    final naming = profile.arrivalState == PtipoteArrivalState.hatched
        ? PtipoteArrivalService.startNaming(profile)
        : profile;
    _ptipote = PtipoteArrivalService.finalizeNaming(
      naming,
      displayName: _nameController.text,
    );
    await _saveProfile(Zone0V2WorldStage.questionnaire);
    if (mounted) setState(() {});
  }

  Future<void> _createWorld() async {
    final profile = _ptipote;
    if (profile == null || !profile.isArrivalComplete) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final questionnaire = calculateRegionQuestionnaire(
        q1: _q1,
        q2: _q2,
        q3: _q3,
        completedAt: DateTime.now(),
      );
      await _foundation.saveWorldcraftQuestionnaire(
        profile: profile,
        questionnaire: questionnaire,
      );
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(WorldcraftDevRegionPage.route);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Création du Camp impossible. Aucun choix n’est perdu : réessaie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = _ptipote;
    return Scaffold(
      appBar: AppBar(title: const Text('PTIPOTE V2')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (_requiresWorldcraftReset)
              _worldcraftMigrationStep()
            else if (profile == null)
              _adoptionStep()
            else
              _arrivalStep(profile),
          ],
        ),
      ),
    );
  }

  Widget _worldcraftMigrationStep() => _stepCard(
        title: 'Passage à Worldcraft 0',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Le prototype passe au monde partagé. Cette opération efface '
              'uniquement l’ancienne Région, le Camp et la Lisière V2 locale. '
              'Ton compte, tes P’TIPOTES, scans NFC et données sociales restent intacts.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _startWorldcraftMigration,
              child: const Text('Réinitialiser le territoire V2 et choisir une Région'),
            ),
          ],
        ),
      );

  Widget _adoptionStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Bienvenue au Camp',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
              'Choisis ton premier P’TIPOTE. Une figurine physique reste facultative.'),
          const SizedBox(height: 16),
          const Text('Adoption numérique',
              style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PtipoteTypeId.values
                .map(
                  (type) => FilledButton(
                    onPressed: _saving ? null : () => _adoptDigital(type),
                    child: Text('Adopter · ${type.name}'),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Figurine physique',
              style: TextStyle(fontWeight: FontWeight.w800)),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const NfcPage()),
                    );
                    if (mounted) setState(() {});
                  },
            icon: const Icon(Icons.nfc),
            label: const Text('Scanner une figurine'),
          ),
          StreamBuilder<List<PtipoteFigurine>>(
            stream: _figurines.watchMyFigurines(),
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <PtipoteFigurine>[];
              if (values.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Figurines disponibles après scan :'),
                  ...values.map(
                    (figurine) => ListTile(
                      leading: const Icon(Icons.pets_outlined),
                      title: Text(figurine.displayName),
                      subtitle: Text('${figurine.type} · ${figurine.species}'),
                      onTap: _saving ? null : () => _choosePhysical(figurine),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  Widget _arrivalStep(PtipoteV2Profile profile) {
    if (!profile.isArrivalComplete &&
        profile.arrivalState != PtipoteArrivalState.hatched &&
        profile.arrivalState != PtipoteArrivalState.naming) {
      final activated = profile.arrivalState == PtipoteArrivalState.rhythmReady;
      return _stepCard(
        title: activated ? 'Activation prête' : 'Couveuse',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _profilePreview(profile),
            Text(activated
                ? 'La Couveuse est active. Fais éclore ton P’TIPOTE.'
                : 'Active la Couveuse pour préparer la naissance.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : (activated ? _hatch : _activate),
              child: Text(activated ? 'Faire éclore' : 'Activer la Couveuse'),
            ),
          ],
        ),
      );
    }
    if (!profile.isArrivalComplete) {
      return _stepCard(
        title: 'Donner un nom',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _profilePreview(profile),
            TextField(
              controller: _nameController,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'Nom du P’TIPOTE'),
              textCapitalization: TextCapitalization.words,
            ),
            FilledButton(
              onPressed: _saving ? null : _name,
              child: const Text('Confirmer le nom'),
            ),
          ],
        ),
      );
    }
    return _questionnaireStep(profile);
  }

  Widget _questionnaireStep(PtipoteV2Profile profile) => _stepCard(
        title: 'Ta Région',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _profilePreview(profile),
            _question<RegionQuestionOneAnswer>(
              'Tu préfères…',
              RegionQuestionOneAnswer.values,
              _q1,
              (value) => setState(() => _q1 = value),
              <RegionQuestionOneAnswer, String>{
                RegionQuestionOneAnswer.mer: 'La mer',
                RegionQuestionOneAnswer.montagne: 'La montagne',
              },
            ),
            _question<RegionQuestionTwoAnswer>(
              'Tu cherches plutôt…',
              RegionQuestionTwoAnswer.values,
              _q2,
              (value) => setState(() => _q2 = value),
              <RegionQuestionTwoAnswer, String>{
                RegionQuestionTwoAnswer.neige: 'La neige',
                RegionQuestionTwoAnswer.soleil: 'Le soleil',
              },
            ),
            _question<RegionQuestionThreeAnswer>(
              'Lequel emportes-tu ?',
              RegionQuestionThreeAnswer.values,
              _q3,
              (value) => setState(() => _q3 = value),
              <RegionQuestionThreeAnswer, String>{
                RegionQuestionThreeAnswer.champ: 'Une graine de champ',
                RegionQuestionThreeAnswer.coquillages: 'Des coquillages',
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _createWorld,
              child: Text(_saving ? 'Création du Camp…' : 'Installer le Camp'),
            ),
          ],
        ),
      );

  Widget _question<T extends Enum>(
    String title,
    List<T> values,
    T selected,
    ValueChanged<T> onChanged,
    Map<T, String> labels,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Wrap(
              spacing: 8,
              children: values
                  .map(
                    (value) => ChoiceChip(
                      label: Text(labels[value]!),
                      selected: selected == value,
                      onSelected: (_) => onChanged(value),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );

  Widget _stepCard({required String title, required Widget child}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _profilePreview(PtipoteV2Profile profile) => SizedBox(
        height: 132,
        child: PtipoteImage(
          type: profile.typeId.name,
          species: profile.natureId,
          visualAssetKey: profile.visualAssetKey,
          height: 132,
        ),
      );
}

class _BirthRhythmIntent extends Intent {
  const _BirthRhythmIntent(this.value);
  final int value;
}

class _BirthRhythmDialog extends StatefulWidget {
  const _BirthRhythmDialog({required this.pattern});
  final List<int> pattern;

  @override
  State<_BirthRhythmDialog> createState() => _BirthRhythmDialogState();
}

class _BirthRhythmDialogState extends State<_BirthRhythmDialog> {
  var _step = 0;

  void _receive(int value) {
    if (_step >= widget.pattern.length || value != widget.pattern[_step]) {
      Navigator.of(context).pop(false);
      return;
    }
    _step += 1;
    if (_step == widget.pattern.length) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp): _BirthRhythmIntent(0),
          SingleActivator(LogicalKeyboardKey.arrowRight): _BirthRhythmIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _BirthRhythmIntent(2),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _BirthRhythmIntent(3),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _BirthRhythmIntent: CallbackAction<_BirthRhythmIntent>(
              onInvoke: (intent) {
                _receive(intent.value);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: const Text('Rythme de naissance'),
              content: Text(
                'Suis le rythme avec les flèches : ${widget.pattern.map(_arrow).join('  ')}\n'
                'Étape ${_step + 1}/${widget.pattern.length}',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Recommencer plus tard'),
                ),
              ],
            ),
          ),
        ),
      );

  static String _arrow(int value) => switch (value) {
        0 => '↑',
        1 => '→',
        2 => '↓',
        _ => '←',
      };
}
