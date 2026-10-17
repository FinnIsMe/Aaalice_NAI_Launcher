import 'character_prompt_block_parser.dart';
import 'text_space_converter.dart';
import 'prompt_edit_document.dart';

/// NAI 提示词格式化工具
/// 简化版：只做中文逗号转英文和空格转下划线
class NaiPromptFormatter {
  static final RegExp _lineBreakPattern = RegExp(r'\r\n|\r|\n');
  static final RegExp _horizontalWhitespacePattern = RegExp(r'[ \t\f\u00a0]+');
  static final RegExp _leadingHorizontalWhitespacePattern = RegExp(r'^[ \t]*');
  static final RegExp _trailingHorizontalWhitespacePattern = RegExp(r'[ \t]*$');
  static final RegExp _leadingSeparatorPattern = RegExp(r'^[ \t]*[,，][ \t]*');

  /// 格式化单个标签（显示格式）：去除下划线，转换为常规空格
  static String formatTag(String tag) {
    return _normalizeHorizontalWhitespace(tag.replaceAll('_', ' ')).trim();
  }

  /// 格式化整个提示词（显示与编辑格式）：
  /// - 将中文逗号转换为英文逗号
  /// - 将标签中的下划线转换为普通空格
  /// - 保留逗号后的空格规范
  /// - 保留用户换行与空行
  static String format(String prompt) {
    var followsDisabled = false;
    return PromptEditDocument.mapActiveText(prompt, (fragment) {
      final separator = followsDisabled
          ? _leadingSeparatorPattern.firstMatch(fragment)
          : null;
      followsDisabled = true;
      if (separator == null) return _formatActive(fragment);
      return '${separator.group(0)!.replaceAll('，', ',')}'
          '${_formatActive(fragment.substring(separator.end))}';
    });
  }

  /// 发送给 API 请求时调用：将标签中的空格转换为下划线以符合 NovelAI 模型要求
  static String formatForApi(String prompt) {
    if (prompt.isEmpty) return prompt;
    return PromptEditDocument.mapActiveText(prompt, (fragment) {
      return fragment.splitMapJoin(
        _lineBreakPattern,
        onMatch: (match) => match.group(0)!,
        onNonMatch: (line) {
          if (line.isEmpty) return line;
          final tags = line
              .split(',')
              .map((tag) {
                final trimmed = tag.trim();
                if (trimmed.isEmpty) return '';
                return TextSpaceConverter.convert(
                  trimmed,
                  protectChars: TextSpaceConverter.naiFormat,
                );
              })
              .where((tag) => tag.isNotEmpty)
              .toList();
          var formatted = tags.join(', ');
          if (line.trimRight().endsWith(',') && formatted.isNotEmpty) {
            formatted = '$formatted,';
          }
          return formatted;
        },
      );
    });
  }

  static String _formatActive(String prompt) {
    if (prompt.isEmpty) return prompt;

    var prepared = prompt;
    final parsed = CharacterPromptBlockParser.parse(prompt);
    for (final block in parsed.blocks.reversed) {
      final content = prepared.substring(
        block.contentRange.start,
        block.contentRange.end,
      );
      prepared = prepared.replaceRange(
        block.contentRange.start,
        block.contentRange.end,
        _formatPromptText(content),
      );
    }

    return _formatPromptText(prepared);
  }

  static String _formatPromptText(String prompt) {
    return prompt.splitMapJoin(
      _lineBreakPattern,
      onMatch: (match) => match.group(0)!,
      onNonMatch: _formatLine,
    );
  }

  static String _formatLine(String line) {
    if (line.isEmpty) return line;

    final leadingWhitespace =
        _leadingHorizontalWhitespacePattern.firstMatch(line)?.group(0) ?? '';
    final trailingWhitespace =
        _trailingHorizontalWhitespacePattern.firstMatch(line)?.group(0) ?? '';
    final contentEnd = line.length - trailingWhitespace.length;
    if (leadingWhitespace.length >= contentEnd) {
      return line;
    }

    var content = line.substring(leadingWhitespace.length, contentEnd);
    content = _normalizePunctuation(content);
    content = _cleanUnboundedColons(content);
    content = _normalizeHorizontalWhitespace(content);
    // 将非数字间的英文句号（如 'tag. tag'）视作分隔符转为逗号，保护 '1.2::tag::' 中的浮点数小数点
    content = content.replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ',');
    final keepsTrailingComma = content.endsWith(',');

    final rawTags = content
        .split(',')
        .map((tag) {
          final trimmed = tag.trim();
          if (trimmed.isEmpty) return '';
          return formatTag(trimmed);
        })
        .where((tag) => tag.isNotEmpty)
        .toList();

    // 标签去重逻辑：
    // 权重与形态不同视为完全不同的词（boy, 1.2::boy::, [boy], {boy}, happy boy 互不相同）；
    // 相同词仅保留最后出现的一个（例如 happy, happy, night, happy -> 仅保留最后一个 happy -> night, happy）
    final seen = <String>{};
    final reversedResult = <String>[];
    for (var i = rawTags.length - 1; i >= 0; i--) {
      final t = rawTags[i];
      final key = t.toLowerCase();
      if (seen.add(key)) {
        reversedResult.add(t);
      }
    }
    final tags = reversedResult.reversed.toList();

    var formatted = tags.join(', ');
    if (keepsTrailingComma && formatted.isNotEmpty) {
      formatted = '$formatted,';
    }

    return '$leadingWhitespace$formatted$trailingWhitespace';
  }

  /// 转换中文全角标点符号为标准英文 ASCII 标点
  static String _normalizePunctuation(String text) {
    return text
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
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('、', ',');
  }

  /// 自动剔除没有边界/未配对闭合的孤立 ::
  static String _cleanUnboundedColons(String text) {
    if (!text.contains('::')) return text;
    // 连续3个或以上冒号先折叠为标准双冒号
    final sanitized = text.replaceAll(RegExp(r':{3,}'), '::');

    final removals = <(int, int)>[];
    final openStacks = <(int, int)>[];
    var pos = 0;

    while (pos < sanitized.length) {
      final idx = sanitized.indexOf('::', pos);
      if (idx == -1) break;
      final cStart = idx;
      final cEnd = idx + 2;

      final prefix = sanitized.substring(0, cStart);
      final numMatch = RegExp(r'(?:^|[\s,;\[\{\(\r\n])(-?\d+(?:\.\d+)?)$').firstMatch(prefix);

      if (numMatch != null) {
        final numStart = cStart - numMatch.group(1)!.length;
        final after = sanitized.substring(cEnd).trimLeft();
        if (after.startsWith('::') || after.isEmpty || after.startsWith(',') || after.startsWith(';') || after.startsWith('\n') || after.startsWith('\r')) {
          removals.add((numStart, cEnd));
        } else {
          openStacks.add((numStart, cStart));
        }
      } else {
        if (openStacks.isNotEmpty) {
          openStacks.removeLast();
        } else {
          removals.add((cStart, cEnd));
        }
      }
      pos = cEnd;
    }

    if (removals.isEmpty) return sanitized;
    removals.sort((a, b) => b.$1.compareTo(a.$1));
    var result = sanitized;
    for (final removal in removals) {
      result = result.replaceRange(removal.$1, removal.$2, '');
    }
    return result;
  }

  /// 统一行内空白字符，不跨越或删除换行。
  static String _normalizeHorizontalWhitespace(String text) {
    var result = text.replaceAll('　', ' ');
    result = result.replaceAll(_horizontalWhitespacePattern, ' ');
    return result;
  }
}
