import 'package:flutter/material.dart';

class PtipoteImage extends StatefulWidget {
  const PtipoteImage({
    super.key,
    required this.type,
    required this.species,
    this.height = 180,
  });

  final String type;
  final String species;
  final double height;

  @override
  State<PtipoteImage> createState() => _PtipoteImageState();
}

class _PtipoteImageState extends State<PtipoteImage> {
  static const _baseUrl = 'https://app.ptipotes.com/img';
  static const _extensions = <String>['jpg', 'jpeg', 'png', 'webp'];

  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates();
  }

  @override
  void didUpdateWidget(covariant PtipoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type || oldWidget.species != widget.species) {
      _candidates = _buildCandidates();
      _index = 0;
    }
  }

  List<String> _buildCandidates() {
    final names = <String>{
      widget.type.trim(),
      widget.species.trim(),
    }..removeWhere((value) => value.isEmpty || value == '-');

    final urls = <String>[];
    for (final name in names) {
      for (final ext in _extensions) {
        urls.add('$_baseUrl/${Uri.encodeComponent(name)}.$ext');
      }
    }
    urls.add('$_baseUrl/bplaceholder.png');
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final url = _candidates[_index.clamp(0, _candidates.length - 1)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            if (_index < _candidates.length - 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _index += 1);
              });
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Icon(Icons.image_not_supported));
          },
        ),
      ),
    );
  }
}
