import 'package:flutter/services.dart';

/// 文本清洗工具：
/// 清除 Windows 输入法、剪贴板或特殊编码可能残留的零宽字符、不可见控制符，
/// 将全角空格（\u3000）与各类 Unicode 变体空格规范化为标准空格（' '），
/// 将 Windows 回车（\r\n）与孤立回车（\r）、段落分隔符规范化为标准换行（\n），
/// 彻底杜绝文本框中在行首、行尾或段落末尾出现豆腐块（□）或假空格。
class TextSanitizerUtils {
  TextSanitizerUtils._();

  // 必须移除的字符：ASCII 0~8, 11~12, 14~31, 127 (DEL), BOM (\uFEFF), 零宽字符 (\u200B-\u200F, \u2060-\u206F), 替换字符 (\uFFFD)
  static final RegExp _stripPattern = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\uFEFF\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFFF0-\uFFFF]',
  );

  // 规范化为空格的字符：全角空格 (\u3000)、不换行空格 (\u00A0) 及各类排版空格
  static final RegExp _normalizeSpacePattern = RegExp(
    r'[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]',
  );

  /// 清洗普通字符串
  static String sanitize(String input) {
    if (input.isEmpty) return input;
    // 1. 标准化换行：\r\n -> \n, 独立 \r -> \n, Unicode 行/段分隔符 -> \n
    final noCr = input
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[\r\u2028\u2029\u0085]'), '\n');
    // 2. 规范化各类非标准空格
    final normalized = noCr.replaceAll(_normalizeSpacePattern, ' ');
    // 3. 剔除控制字符及零宽字符
    return normalized.replaceAll(_stripPattern, '');
  }

  /// 清洗 TextEditingValue 并精确重定位光标/选区
  static TextEditingValue sanitizeEditingValue(TextEditingValue value) {
    final text = value.text;
    if (text.isEmpty) return value;

    final oldSelection = value.selection;
    var newBaseOffset = oldSelection.baseOffset;
    var newExtentOffset = oldSelection.extentOffset;

    final sb = StringBuffer();
    var changed = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final code = char.codeUnitAt(0);

      // 处理 \r\n 或孤立 \r
      if (code == 0x0D) {
        changed = true;
        // 如果后面跟着 \n，跳过当前 \r，让后面的 \n 作为单一换行保留
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
          if (oldSelection.isValid) {
            if (i < oldSelection.baseOffset) newBaseOffset--;
            if (i < oldSelection.extentOffset) newExtentOffset--;
          }
          continue;
        } else {
          // 孤立的 \r 替换为 \n（1:1 替换，偏移量不变）
          sb.write('\n');
          continue;
        }
      }

      // Unicode 换行符（Line Separator / Paragraph Separator）
      if (char == '\u2028' || char == '\u2029' || char == '\u0085') {
        changed = true;
        sb.write('\n');
        continue;
      }

      // 非标准空格替换为 ASCII 半角空格
      if (_normalizeSpacePattern.hasMatch(char)) {
        changed = true;
        sb.write(' ');
        continue;
      }

      // 剔除字符
      if (_stripPattern.hasMatch(char)) {
        changed = true;
        if (oldSelection.isValid) {
          if (i < oldSelection.baseOffset) newBaseOffset--;
          if (i < oldSelection.extentOffset) newExtentOffset--;
        }
        continue;
      }

      sb.write(char);
    }

    if (!changed) {
      return value;
    }

    final newText = sb.toString();
    final clampedBase = oldSelection.isValid
        ? newBaseOffset.clamp(0, newText.length)
        : -1;
    final clampedExtent = oldSelection.isValid
        ? newExtentOffset.clamp(0, newText.length)
        : -1;

    return value.copyWith(
      text: newText,
      selection: oldSelection.isValid
          ? TextSelection(
              baseOffset: clampedBase,
              extentOffset: clampedExtent,
              affinity: oldSelection.affinity,
              isDirectional: oldSelection.isDirectional,
            )
          : oldSelection,
      composing: TextRange.empty,
    );
  }
}

/// 适用于 TextField.inputFormatters 的清洗 Formatter
class TextSanitizerInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 正在进行输入法合成（拼音选词中）时，不打断原生 composing
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    return TextSanitizerUtils.sanitizeEditingValue(newValue);
  }
}
