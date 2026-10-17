import '../../core/utils/nai_prompt_parser.dart';
import '../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../data/models/fixed_tag/fixed_tag_prompt_type.dart';

class ActivePresetDeduplicationResult {
  final String cleanedText;
  final List<String> removedTags;
  final List<String> sources;

  const ActivePresetDeduplicationResult({
    required this.cleanedText,
    required this.removedTags,
    required this.sources,
  });

  bool get hasRemovals => removedTags.isNotEmpty;
}

class ActivePresetDeduplicator {
  const ActivePresetDeduplicator._();

  static ActivePresetDeduplicationResult deduplicate({
    required String text,
    required bool isNegative,
    required Iterable<FixedTagEntry> activeFixedEntries,
    Iterable<String>? activeSystemPresetTags,
  }) {
    final rawTags = NaiPromptParser.splitSegments(text);
    if (rawTags.isEmpty) {
      return ActivePresetDeduplicationResult(
        cleanedText: text,
        removedTags: const [],
        sources: const [],
      );
    }

    final targetPresetMap = <String, String>{};

    for (final entry in activeFixedEntries) {
      final content = (isNegative && entry.promptType == FixedTagPromptType.combo)
          ? (entry.negativeContent ?? '')
          : entry.content;
      final tags = NaiPromptParser.splitSegments(content);
      final label = entry.name.trim().isNotEmpty
          ? '固定词 [${entry.name}]'
          : '固定词';
      for (final tag in tags) {
        final norm = _normalizeTag(tag);
        if (norm.isNotEmpty) {
          targetPresetMap[norm] = label;
        }
      }
    }

    if (activeSystemPresetTags != null) {
      final label = isNegative ? '负面预设' : '质量词预设';
      for (final tag in activeSystemPresetTags) {
        final norm = _normalizeTag(tag);
        if (norm.isNotEmpty) {
          targetPresetMap[norm] = label;
        }
      }
    }

    if (targetPresetMap.isEmpty) {
      return ActivePresetDeduplicationResult(
        cleanedText: text,
        removedTags: const [],
        sources: const [],
      );
    }

    final lineBreakPattern = RegExp(r'\r\n|\r|\n');
    final leadingWhitespacePattern = RegExp(r'^[ \t]*');
    final trailingWhitespacePattern = RegExp(r'[ \t]*$');

    final removedTags = <String>[];
    final sources = <String>{};

    final cleaned = text.splitMapJoin(
      lineBreakPattern,
      onMatch: (match) => match.group(0)!,
      onNonMatch: (line) {
        if (line.isEmpty) return line;

        final leadingWhitespace =
            leadingWhitespacePattern.firstMatch(line)?.group(0) ?? '';
        final trailingWhitespace =
            trailingWhitespacePattern.firstMatch(line)?.group(0) ?? '';
        final contentEnd = line.length - trailingWhitespace.length;
        if (leadingWhitespace.length >= contentEnd) {
          return line;
        }

        final content = line.substring(leadingWhitespace.length, contentEnd);
        final keepsTrailingComma = content.trim().endsWith(',');

        final lineTags = NaiPromptParser.splitSegments(content);
        if (lineTags.isEmpty) return line;

        final remainingLineTags = <String>[];
        for (final rawTag in lineTags) {
          final norm = _normalizeTag(rawTag);
          if (norm.isNotEmpty && targetPresetMap.containsKey(norm)) {
            removedTags.add(rawTag.trim());
            sources.add(targetPresetMap[norm]!);
          } else if (norm.isNotEmpty) {
            remainingLineTags.add(rawTag);
          }
        }

        if (remainingLineTags.isEmpty) {
          return '';
        }

        var formatted = remainingLineTags.join(', ');
        if (keepsTrailingComma && formatted.isNotEmpty) {
          formatted = '$formatted,';
        }
        return '$leadingWhitespace$formatted$trailingWhitespace';
      },
    );

    if (removedTags.isEmpty) {
      return ActivePresetDeduplicationResult(
        cleanedText: text,
        removedTags: const [],
        sources: const [],
      );
    }

    var finalCleaned = cleaned;
    if (finalCleaned.replaceAll(RegExp(r'[\r\n\s,]+'), '').isEmpty) {
      finalCleaned = '';
    } else {
      finalCleaned = finalCleaned
          .replaceAll(RegExp(r'^\s*[\r\n]+'), '')
          .replaceAll(RegExp(r'[\r\n]+\s*$'), '');
    }

    return ActivePresetDeduplicationResult(
      cleanedText: finalCleaned,
      removedTags: removedTags,
      sources: sources.toList(),
    );
  }

  static String _normalizeTag(String tag) {
    var result = tag.trim().toLowerCase();
    result = result
        .replaceAll('，', ',')
        .replaceAll('。', '.')
        .replaceAll('：', ':')
        .replaceAll('；', ';')
        .replaceAll('！', '!')
        .replaceAll('？', '?')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('【', '[')
        .replaceAll('】', ']')
        .replaceAll('｛', '{')
        .replaceAll('｝', '}')
        .replaceAll('、', ',');
    result = result.replaceAll('_', ' ');
    final numericWeight = RegExp(
      r'^-?\d+(?:\.\d+)?::(.+?)(?:::)?$',
    ).firstMatch(result);
    if (numericWeight != null) result = numericWeight.group(1)!.trim();
    result = result.replaceAll('::', '').trim();
    result = result.replaceAll(RegExp(r'^[\{\[]+'), '');
    result = result.replaceAll(RegExp(r'[\}\]]+$'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }
}
