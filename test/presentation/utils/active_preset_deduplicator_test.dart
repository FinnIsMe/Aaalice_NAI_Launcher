import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/presentation/utils/active_preset_deduplicator.dart';

void main() {
  group('ActivePresetDeduplicator', () {
    test('去重并严格保留回车符、CRLF 与空行排版', () {
      final fixedEntry = FixedTagEntry.create(
        name: 'boy',
        content: 'boy',
        position: FixedTagPosition.prefix,
      );

      const multilineText = 'boy, smile,\n\n  masterpiece, best quality,\r\nhappy, boy';

      final result = ActivePresetDeduplicator.deduplicate(
        text: multilineText,
        isNegative: false,
        activeFixedEntries: [fixedEntry],
        activeSystemPresetTags: ['masterpiece', 'best quality'],
      );

      expect(result.hasRemovals, isTrue);
      expect(result.removedTags, containsAll(['boy', 'masterpiece', 'best quality']));
      expect(
        result.cleanedText,
        equals('smile,\n\n  \r\nhappy'),
      );
    });

    test('全行被剔除时保留空行换行结构不拍平成单行', () {
      final fixedEntry = FixedTagEntry.create(
        name: 'boy',
        content: 'boy',
      );

      const text = 'boy\nsmile';
      final result = ActivePresetDeduplicator.deduplicate(
        text: text,
        isNegative: false,
        activeFixedEntries: [fixedEntry],
      );

      expect(result.cleanedText, equals('\nsmile'));
    });
  });
}
