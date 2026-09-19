import 'package:flutter/material.dart';

/// Text with every case-insensitive occurrence of [query] marked (the search
/// highlight). With no query it is just a plain [Text].
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.text, {super.key, this.query, this.emphasize = false, this.style});

  final String text;
  final String? query;

  /// Draw the marks stronger - used for the currently selected search result.
  final bool emphasize;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final needle = query?.trim().toLowerCase();
    if (needle == null || needle.isEmpty) return Text(text, style: style);

    final colors = Theme.of(context).colorScheme;
    final markStyle = TextStyle(
      backgroundColor: emphasize ? colors.tertiary : colors.tertiaryContainer,
      color: emphasize ? colors.onTertiary : colors.onTertiaryContainer,
      fontWeight: emphasize ? FontWeight.w600 : null,
    );

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var index = 0;
    while (index < text.length) {
      final match = lower.indexOf(needle, index);
      // toLowerCase can change a string's length for a few scripts; if the
      // two no longer line up, fall back to no marking rather than mis-mark.
      if (lower.length != text.length || match < 0) {
        spans.add(TextSpan(text: text.substring(index)));
        break;
      }
      if (match > index) spans.add(TextSpan(text: text.substring(index, match)));
      spans.add(TextSpan(text: text.substring(match, match + needle.length), style: markStyle));
      index = match + needle.length;
    }
    return Text.rich(TextSpan(children: spans), style: style);
  }
}
