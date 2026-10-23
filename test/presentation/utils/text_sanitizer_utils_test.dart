import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:nai_launcher/presentation/utils/text_sanitizer_utils.dart';

void main() {
  group('TextSanitizerUtils', () {
    test('converts full-width spaces and non-breaking spaces to standard space', () {
      const input = 'masterpiece,\u30001girl,\u00A0solo';
      final sanitized = TextSanitizerUtils.sanitize(input);
      expect(sanitized, 'masterpiece, 1girl, solo');
    });

    test('strips zero-width and control characters', () {
      const input = 'happy\u200B \uFEFFmale\u0000 furry\x08';
      final sanitized = TextSanitizerUtils.sanitize(input);
      expect(sanitized, 'happy male furry');
    });

    test('normalizes CRLF and standalone CR at paragraph end into LF', () {
      const input = 'paragraph 1\r\nparagraph 2\r\n\u3000\r';
      final sanitized = TextSanitizerUtils.sanitize(input);
      expect(sanitized, 'paragraph 1\nparagraph 2\n \n');
    });

    test('formatter preserves cursor position correctly when characters are removed', () {
      final formatter = TextSanitizerInputFormatter();
      const oldValue = TextEditingValue(
        text: 'happy male',
        selection: TextSelection.collapsed(offset: 10),
      );
      // Inserting \u200B before 'furry'
      const newValue = TextEditingValue(
        text: 'happy \u200Bfurry',
        selection: TextSelection.collapsed(offset: 8),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'happy furry');
      expect(result.selection.baseOffset, 7); // stripped 1 char before offset 8
    });

    test('formatter normalizes full-width space without changing cursor offset', () {
      final formatter = TextSanitizerInputFormatter();
      const oldValue = TextEditingValue(
        text: 'happy',
        selection: TextSelection.collapsed(offset: 5),
      );
      const newValue = TextEditingValue(
        text: 'happy\u3000',
        selection: TextSelection.collapsed(offset: 6),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'happy ');
      expect(result.selection.baseOffset, 6);
    });

    test('formatter normalizes CRLF at paragraph end and updates cursor offset', () {
      final formatter = TextSanitizerInputFormatter();
      const oldValue = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      const newValue = TextEditingValue(
        text: 'hello\r\nworld',
        selection: TextSelection.collapsed(offset: 12),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'hello\nworld');
      expect(result.selection.baseOffset, 11);
    });
  });
}
