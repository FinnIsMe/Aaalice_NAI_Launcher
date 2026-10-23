import 'package:flutter/material.dart';

/// 提示词双击选词/短语算法工具类
///
/// 规则：
/// 1. 分段界定：以逗号（`,` 与中文 `，`）或换行（`\n`, `\r`）及文本首尾作为逻辑切片。
/// 2. 括号与权重兼容：
///    - 若双击点落在外层修饰括号（`{}`、`[]`、`()`）或权重语法（如 `:1.2`、`1.2::`）本身上，连同外层修饰一起全选；
///    - 若双击点落在词语内容区域，则剔除外层修饰，仅在内部词语区段进行判定。
/// 3. 词数统计与选区计算（以空白字符 `\s+` 切分词，下划线 `_` 和连字符 `-` 保持默认作为词内部字符）：
///    - 词数 <= 3（1、2、3 个词）：双击该区段内任意单词或词间空隙，整体选中该区段所有词（不含逗号与首尾多余空格）；
///    - 词数 > 3（4 个词及以上）：退化为仅选中被双击的那一个单词（严格不包含该词前后的空格）。
class PromptPhraseSelectionUtils {
  PromptPhraseSelectionUtils._();

  static const String _delimiters = ',，\n\r';
  static final RegExp _whitespaceRegExp = RegExp(r'\s+');
  static final RegExp _wordRegExp = RegExp(r'\S+');
  static final RegExp _colonWeightSuffix = RegExp(r':-?\d+(?:\.\d*)?\s*$');
  static final RegExp _naiWeightPrefix = RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)::');

  /// 根据点击的字符 [offset] 计算双击应产生的 [TextSelection]
  static TextSelection calculateDoubleTapSelection({
    required String text,
    required int offset,
  }) {
    if (text.isEmpty) {
      return const TextSelection.collapsed(offset: 0);
    }

    final safeOffset = offset.clamp(0, text.length);

    // 1. 定位逗号/换行区段 [segStart, segEnd]
    var segStart = safeOffset;
    while (segStart > 0 && !_delimiters.contains(text[segStart - 1])) {
      segStart--;
    }

    var segEnd = safeOffset;
    while (segEnd < text.length && !_delimiters.contains(text[segEnd])) {
      segEnd++;
    }

    if (segStart >= segEnd) {
      return TextSelection.collapsed(offset: safeOffset);
    }

    // 剔除逗号区段首尾的纯空白字符
    var trimmedStart = segStart;
    while (trimmedStart < segEnd && _isWhitespace(text.codeUnitAt(trimmedStart))) {
      trimmedStart++;
    }

    var trimmedEnd = segEnd;
    while (trimmedEnd > trimmedStart && _isWhitespace(text.codeUnitAt(trimmedEnd - 1))) {
      trimmedEnd--;
    }

    if (trimmedStart >= trimmedEnd) {
      return TextSelection.collapsed(offset: safeOffset);
    }

    // 2. 检查外层权重与括号修饰
    final shell = _resolveBracketShell(text, trimmedStart, trimmedEnd);

    // 如果用户双击直接点在了括号/权重标记自身上，全选包括括号在内的整个外壳
    if (shell.hasWrapper &&
        (safeOffset < shell.contentStart || safeOffset >= shell.contentEnd)) {
      return TextSelection(baseOffset: trimmedStart, extentOffset: trimmedEnd);
    }

    // 在核心词组区域内处理
    var innerStart = shell.contentStart;
    var innerEnd = shell.contentEnd;

    // 再次剔除括号内部边缘可能存在的空白
    while (innerStart < innerEnd && _isWhitespace(text.codeUnitAt(innerStart))) {
      innerStart++;
    }
    while (innerEnd > innerStart && _isWhitespace(text.codeUnitAt(innerEnd - 1))) {
      innerEnd--;
    }

    if (innerStart >= innerEnd) {
      return TextSelection(baseOffset: trimmedStart, extentOffset: trimmedEnd);
    }

    final innerText = text.substring(innerStart, innerEnd);
    final wordMatches = _wordRegExp.allMatches(innerText).toList();

    if (wordMatches.isEmpty) {
      return TextSelection(baseOffset: innerStart, extentOffset: innerEnd);
    }

    // 3. 根据词数判定
    // 词数 <= 3：全部选中整个区段内的词
    if (wordMatches.length <= 3) {
      return TextSelection(baseOffset: innerStart, extentOffset: innerEnd);
    }

    // 词数 > 3：仅选中当前点击的具体单词（不包含前后空格）
    final innerClickOffset = safeOffset - innerStart;

    // 遍历匹配落点在哪一个单词上
    for (final match in wordMatches) {
      if (innerClickOffset >= match.start && innerClickOffset <= match.end) {
        return TextSelection(
          baseOffset: innerStart + match.start,
          extentOffset: innerStart + match.end,
        );
      }
    }

    // 若点击落在词与词之间的空隙空格上，选取距离落点最近的单词
    _WordSpan? closestWord;
    var minDistance = double.infinity;

    for (final match in wordMatches) {
      final wStart = innerStart + match.start;
      final wEnd = innerStart + match.end;

      final double distance;
      if (safeOffset < wStart) {
        distance = (wStart - safeOffset).toDouble();
      } else if (safeOffset > wEnd) {
        distance = (safeOffset - wEnd).toDouble();
      } else {
        distance = 0.0;
      }

      if (distance < minDistance) {
        minDistance = distance;
        closestWord = _WordSpan(wStart, wEnd);
      }
    }

    if (closestWord != null) {
      return TextSelection(
        baseOffset: closestWord.start,
        extentOffset: closestWord.end,
      );
    }

    return TextSelection(baseOffset: innerStart, extentOffset: innerEnd);
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 || // space
      codeUnit == 0x09 || // tab
      codeUnit == 0x0A || // \n
      codeUnit == 0x0D || // \r
      codeUnit == 0x3000; // full-width space

  static _BracketShell _resolveBracketShell(String text, int start, int end) {
    var s = start;
    var e = end;
    var peeled = false;

    // 1. 检查 NAI 风格数值权重: weight::content::
    final segment = text.substring(s, e);
    final naiMatch = _naiWeightPrefix.firstMatch(segment);
    if (naiMatch != null && segment.endsWith('::') && segment.length >= naiMatch.end + 2) {
      s += naiMatch.end;
      e -= 2;
      peeled = true;
    } else {
      // 2. 检查多层外包裹括号: {{{...}}}, [[[...]]], ((...))
      while (s < e) {
        final firstChar = text[s];
        final lastChar = text[e - 1];

        if (firstChar == '{' && lastChar == '}') {
          s++;
          e--;
          peeled = true;
        } else if (firstChar == '[' && lastChar == ']') {
          s++;
          e--;
          peeled = true;
        } else if (firstChar == '(' && lastChar == ')') {
          // 检查内部是否带 SD 冒号权重，如 (content:1.2)
          final innerSub = text.substring(s + 1, e - 1);
          final colonMatch = _colonWeightSuffix.firstMatch(innerSub);
          if (colonMatch != null) {
            s++;
            e = s + colonMatch.start;
            peeled = true;
            break;
          } else {
            s++;
            e--;
            peeled = true;
          }
        } else {
          break;
        }
      }
    }

    if (!peeled || s >= e) {
      return _BracketShell(contentStart: start, contentEnd: end, hasWrapper: false);
    }

    return _BracketShell(contentStart: s, contentEnd: e, hasWrapper: true);
  }
}

class _BracketShell {
  final int contentStart;
  final int contentEnd;
  final bool hasWrapper;

  const _BracketShell({
    required this.contentStart,
    required this.contentEnd,
    required this.hasWrapper,
  });
}

class _WordSpan {
  final int start;
  final int end;

  const _WordSpan(this.start, this.end);
}
