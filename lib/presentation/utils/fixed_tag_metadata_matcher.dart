import '../../core/constants/api_constants.dart';
import '../../core/utils/nai_prompt_parser.dart';
import '../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../data/models/gallery/fixed_tag_usage_projection.dart';
import '../../data/models/gallery/nai_image_metadata.dart';

NaiImageMetadata matchMetadataFixedTags({
  required NaiImageMetadata metadata,
  required Iterable<FixedTagEntry> positiveEntries,
  required Iterable<FixedTagEntry> negativeEntries,
}) {
  var base = metadata;
  if (base.hasExplicitFixedTagMetadata ||
      base.fixedPrefixTags.isNotEmpty ||
      base.fixedSuffixTags.isNotEmpty ||
      base.fixedNegativePrefixTags.isNotEmpty ||
      base.fixedNegativeSuffixTags.isNotEmpty) {
    base = projectFixedTagUsageSnapshot(base);
  }

  final posCandidates = [...positiveEntries];
  for (final tag in [...base.fixedPrefixTags, ...base.fixedSuffixTags]) {
    if (!posCandidates.any((c) => c.content == tag)) {
      posCandidates.add(FixedTagEntry(
        id: 'meta_pos_${posCandidates.length}',
        content: tag,
        position: FixedTagPosition.prefix,
        promptType: FixedTagPromptType.positive,
        sortOrder: posCandidates.length,
      ));
    }
  }

  final negCandidates = [...negativeEntries];
  for (final tag in [
    ...base.fixedNegativePrefixTags,
    ...base.fixedNegativeSuffixTags,
  ]) {
    if (!negCandidates.any((c) => c.content == tag)) {
      negCandidates.add(FixedTagEntry(
        id: 'meta_neg_${negCandidates.length}',
        content: tag,
        position: FixedTagPosition.prefix,
        promptType: FixedTagPromptType.negative,
        sortOrder: negCandidates.length,
      ));
    }
  }

  final posMatch = _matchAndStripTags(
    prompt: base.prompt,
    candidates: posCandidates,
    isNegative: false,
    trailingBlockers: [
      base.qualityTags.expand(_extractTags).map(_normalizeTag).toList(),
      if (base.hasRecordedTransparentBackgroundTag)
        [_normalizeTag(QualityTags.transparentBackgroundTag)],
    ],
  );

  final negMatch = _matchAndStripTags(
    prompt: base.negativePrompt,
    candidates: negCandidates,
    isNegative: true,
    trailingBlockers: const [],
  );

  return base.copyWith(
    fixedPrefixTags: _mergeMatches(
      base.fixedPrefixTags,
      posMatch.prefix,
    ),
    fixedSuffixTags: _mergeMatches(
      base.fixedSuffixTags,
      posMatch.suffix,
    ),
    fixedNegativePrefixTags: _mergeMatches(
      base.fixedNegativePrefixTags,
      negMatch.prefix,
    ),
    fixedNegativeSuffixTags: _mergeMatches(
      base.fixedNegativeSuffixTags,
      negMatch.suffix,
    ),
    prompt: posMatch.cleanedPrompt,
    negativePrompt: negMatch.cleanedPrompt,
  );
}

class _MatchResult {
  final List<String> prefix;
  final List<String> suffix;
  final String cleanedPrompt;

  const _MatchResult({
    required this.prefix,
    required this.suffix,
    required this.cleanedPrompt,
  });
}

_MatchResult _matchAndStripTags({
  required String prompt,
  required List<FixedTagEntry> candidates,
  required bool isNegative,
  required List<List<String>> trailingBlockers,
}) {
  final rawTags = _extractTags(prompt);
  if (rawTags.isEmpty || candidates.isEmpty) {
    return _MatchResult(
      prefix: const [],
      suffix: const [],
      cleanedPrompt: prompt,
    );
  }

  final normTags = rawTags.map(_normalizeTag).toList();
  final consumedIndices = <int>{};
  final matchedPrefix = <String>[];
  final matchedSuffix = <String>[];
  final matchedEntryIds = <String>{};

  // 候选按有效 tag 数量由多到少排序，避免长组合词被单个词碎片化抢占
  final sortedCandidates = [...candidates]..sort((a, b) {
      final aContent = (isNegative && a.promptType == FixedTagPromptType.combo)
          ? (a.negativeContent ?? '')
          : a.content;
      final bContent = (isNegative && b.promptType == FixedTagPromptType.combo)
          ? (b.negativeContent ?? '')
          : b.content;
      return _extractTags(bContent).length.compareTo(_extractTags(aContent).length);
    });

  for (final entry in sortedCandidates) {
    if (matchedEntryIds.contains(entry.id)) continue;

    final content = (isNegative && entry.promptType == FixedTagPromptType.combo)
        ? (entry.negativeContent ?? '')
        : entry.content;
    final entryTags = _extractTags(content).map(_normalizeTag).where((t) => t.isNotEmpty).toList();
    if (entryTags.isEmpty) continue;

    // 在未被消费的 normTags 中查找所有匹配上的 tag 下标
    final currentMatched = <int>[];
    for (final eTag in entryTags) {
      for (var i = 0; i < normTags.length; i++) {
        if (!consumedIndices.contains(i) && !currentMatched.contains(i)) {
          if (normTags[i] == eTag) {
            currentMatched.add(i);
            break;
          }
        }
      }
    }

    // 严格完全重合判定：固定标签中的所有有效 tag 必须 100% 全部存在于提示词中
    // 只要缺少任何一个 tag（或者词条不完全重合），就绝不激活选中该固定标签
    final isMatch = currentMatched.length == entryTags.length;

    if (isMatch) {
      // 只要固定词被激活接管，该词条在原图中的所有出现（包括重复词，如 boy, boy）全部标记消费剥离
      for (var i = 0; i < normTags.length; i++) {
        if (entryTags.contains(normTags[i])) {
          consumedIndices.add(i);
        }
      }
      final sortedMatched = [...currentMatched]..sort();
      final rendered = sortedMatched.map((idx) => rawTags[idx]).join(', ');
      matchedEntryIds.add(entry.id);

      if (entry.position == FixedTagPosition.suffix) {
        matchedSuffix.add(rendered.trim());
      } else {
        matchedPrefix.add(rendered.trim());
      }
    }
  }

  // 同时将质量词、透明背景等系统项全量消费剔除
  for (final blocker in trailingBlockers) {
    for (var i = 0; i < normTags.length; i++) {
      if (blocker.contains(normTags[i])) {
        consumedIndices.add(i);
      }
    }
  }

  // 构建从原提示词中扣除固定词后的极简净文本
  final remainingTags = <String>[];
  for (var i = 0; i < rawTags.length; i++) {
    if (!consumedIndices.contains(i)) {
      remainingTags.add(rawTags[i]);
    }
  }

  return _MatchResult(
    prefix: matchedPrefix,
    suffix: matchedSuffix,
    cleanedPrompt: remainingTags.join(', '),
  );
}

Set<int> fixedPromptTagIndexes({
  required List<String> promptTags,
  required List<String> prefixEntries,
  required List<String> suffixEntries,
}) {
  final normalizedPrompt = promptTags.map(_normalizeTag).toList();
  final prefixLength = _matchedBoundaryLength(
    normalizedPrompt,
    prefixEntries,
    fromStart: true,
  );
  final suffixLength = _matchedBoundaryLength(
    normalizedPrompt,
    suffixEntries,
    fromStart: false,
  );
  return {
    for (var index = 0; index < prefixLength; index++) index,
    for (
      var index = normalizedPrompt.length - suffixLength;
      index < normalizedPrompt.length;
      index++
    )
      if (index >= prefixLength) index,
  };
}

int _matchedBoundaryLength(
  List<String> promptTags,
  List<String> entries, {
  required bool fromStart,
}) {
  final expected = entries
      .expand(_extractTags)
      .map(_normalizeTag)
      .where((tag) => tag.isNotEmpty)
      .toList();
  if (expected.isEmpty || expected.length > promptTags.length) return 0;
  final start = fromStart ? 0 : promptTags.length - expected.length;
  return _matchesAt(promptTags, expected, start) ? expected.length : 0;
}

bool _matchesAt(List<String> source, List<String> expected, int start) {
  if (start < 0 || start + expected.length > source.length) return false;
  for (var offset = 0; offset < expected.length; offset++) {
    if (source[start + offset] != expected[offset]) return false;
  }
  return true;
}

List<String> _mergeMatches(List<String> recorded, List<String> inferred) {
  final result = <String>[...recorded];
  final normalized = recorded.map(normalizeFixedTagMetadataEntry).toSet();
  for (final match in inferred) {
    if (normalized.add(normalizeFixedTagMetadataEntry(match))) {
      result.add(match);
    }
  }
  return result;
}

String normalizeFixedTagMetadataEntry(String entry) =>
    _extractTags(entry).map(_normalizeTag).join(',');

List<String> _extractTags(String prompt) =>
    NaiPromptParser.splitSegments(prompt);

String _normalizeTag(String tag) {
  var result = tag.trim().toLowerCase();
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
