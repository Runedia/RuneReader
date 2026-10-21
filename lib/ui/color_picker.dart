import 'package:flutter/material.dart';

import '../models/reader_theme.dart';

/// Shows an HSV + hex color picker. Returns null when cancelled.
Future<Color?> showColorPicker(
  BuildContext context, {
  required Color initial,
  required String title,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(initial: initial, title: title),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial, required this.title});

  final Color initial;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: _hexOf(widget.initial));

  static const _swatches = <Color>[
    Color(0xFFFFFFFF), Color(0xFFF4ECD8), Color(0xFFE9E6DF), Color(0xFFCCE8CF),
    Color(0xFFDDE7F0), Color(0xFF000000), Color(0xFF121212), Color(0xFF1B2333),
    Color(0xFF2B2B2B), Color(0xFF3E2723), Color(0xFF222222), Color(0xFF5B4636),
    Color(0xFFCFCFCF), Color(0xFFA9B7C6), Color(0xFF3F51B5), Color(0xFFE57373),
  ];

  static String _hexOf(Color c) => colorToHex(c).substring(3); // RRGGBB

  void _set(HSVColor hsv, {bool updateText = true}) {
    setState(() => _hsv = hsv);
    if (updateText) _hex.text = _hexOf(hsv.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _swatches)
                  InkWell(
                    onTap: () => _set(HSVColor.fromColor(s)),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: s,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _slider('색상', _hsv.hue, 360, (v) => _set(_hsv.withHue(v))),
            _slider('채도', _hsv.saturation, 1,
                (v) => _set(_hsv.withSaturation(v))),
            _slider('명도', _hsv.value, 1, (v) => _set(_hsv.withValue(v))),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(
                prefixText: '#',
                labelText: 'HEX (RRGGBB)',
              ),
              onChanged: (text) {
                try {
                  _set(HSVColor.fromColor(colorFromHex(text)),
                      updateText: false);
                } on FormatException {
                  // Wait for a complete value.
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(context, color),
            child: const Text('확인')),
      ],
    );
  }

  Widget _slider(
      String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label)),
        Expanded(
          child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
