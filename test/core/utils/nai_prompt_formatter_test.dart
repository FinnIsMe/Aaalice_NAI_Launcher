import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/nai_prompt_formatter.dart';

void main() {
  test('formatting preserves separators around consecutive disabled tags', () {
    const source = 'cat, /*disabled:long hair*/, /*disabled:blue eyes*/, dog';
    var formatted = source;
    for (var i = 0; i < 5; i++) {
      formatted = NaiPromptFormatter.format(formatted);
      expect(formatted, source);
    }
    expect(
      NaiPromptFormatter.format('/*disabled:cat*/, blue_hair'),
      '/*disabled:cat*/, blue hair',
    );
  });

  group('NaiPromptFormatter.format (页面显示与复制，去除下划线)', () {
    test('格式化标签时将下划线转为空格，并保留换行、空行和行首缩进', () {
      const prompt = 'quality_tags， best_quality,\n\n  blue_hair, red_eyes';

      expect(
        NaiPromptFormatter.format(prompt),
        'quality tags, best quality,\n\n  blue hair, red eyes',
      );
    });

    test('保留 CRLF 与各分组行末逗号', () {
      const prompt = 'subject_tag,\r\nclothing_tag,\r\nbackground_tag';

      expect(
        NaiPromptFormatter.format(prompt),
        'subject tag,\r\nclothing tag,\r\nbackground tag',
      );
    });

    test('纯空白分隔行保持原样', () {
      const prompt = 'first_tag\n  \nsecond_tag';

      expect(NaiPromptFormatter.format(prompt), 'first tag\n  \nsecond tag');
    });

    test('格式化正负标签去除下划线但不破坏 negative 块边界', () {
      const prompt =
          r'girl, alice_\(wonderland\), negative(red_hair, 1.2::blue_eyes::)';

      expect(
        NaiPromptFormatter.format(prompt),
        r'girl, alice \(wonderland\), negative(red hair, 1.2::blue eyes::)',
      );
    });
  });

  group('NaiPromptFormatter.formatForApi (向API发送时转换为下划线)', () {
    test('将标签内空格安全转为下划线', () {
      const prompt = 'best quality, blue hair, 1girl';

      expect(
        NaiPromptFormatter.formatForApi(prompt),
        'best_quality, blue_hair, 1girl',
      );
    });
  });
}
