import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/utils/prompt_phrase_selection_utils.dart';

void main() {
  group('PromptPhraseSelectionUtils', () {
    test('1~3 words delimited by comma: selects all words in segment', () {
      const text = 'night,happy male furry,star';

      // 1. Double click on 'night' (1 word)
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 2, // 'g' in 'night'
      );
      expect(selection.textInside(text), 'night');

      // 2. Double click on 'happy' (in 'happy male furry')
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 8, // 'p' in 'happy'
      );
      expect(selection.textInside(text), 'happy male furry');

      // 3. Double click on space between 'happy' and 'male'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 11, // space between happy and male
      );
      expect(selection.textInside(text), 'happy male furry');

      // 4. Double click on 'male'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 14,
      );
      expect(selection.textInside(text), 'happy male furry');

      // 5. Double click on 'furry'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 20,
      );
      expect(selection.textInside(text), 'happy male furry');

      // 6. Double click on 'star'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 25,
      );
      expect(selection.textInside(text), 'star');
    });

    test('2 words with outer spaces around comma', () {
      const text = '1girl,  white hair ,  solo';
      final selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 12, // 't' in 'white'
      );
      expect(selection.textInside(text), 'white hair');
    });

    test('> 3 words: selects ONLY the double-clicked word without spaces', () {
      const text = 'young man nestled between his legs';

      // Double click 'nestled'
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 13, // 't' in 'nestled'
      );
      expect(selection.textInside(text), 'nestled');

      // Double click 'young'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 1, // 'o' in 'young'
      );
      expect(selection.textInside(text), 'young');

      // Double click 'legs'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 32, // 'g' in 'legs'
      );
      expect(selection.textInside(text), 'legs');
    });

    test('Underscores and hyphens treated as default (part of a single word)', () {
      const text = 'masterpiece, blue-eyes, very_long_tag_name, cat';

      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 16, // inside 'blue-eyes'
      );
      expect(selection.textInside(text), 'blue-eyes');

      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 30, // inside 'very_long_tag_name'
      );
      expect(selection.textInside(text), 'very_long_tag_name');
    });

    test('Chinese comma and newline delimiters', () {
      const text = 'night，happy male furry\nstar';

      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 10,
      );
      expect(selection.textInside(text), 'happy male furry');

      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 24,
      );
      expect(selection.textInside(text), 'star');
    });

    test('Bracket compatibility: double click inside words selects inner phrase', () {
      const text = 'night, {happy male furry}, star';

      // Click inside 'happy male furry'
      final selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 12, // 'p' in 'happy'
      );
      expect(selection.textInside(text), 'happy male furry');
    });

    test('Bracket compatibility: double click on bracket selects whole shell', () {
      const text = 'night, {happy male furry}, star';

      // Click on '{'
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 7, // '{'
      );
      expect(selection.textInside(text), '{happy male furry}');

      // Click on '}'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 24, // '}'
      );
      expect(selection.textInside(text), '{happy male furry}');
    });

    test('Weight colon syntax: (white hair:1.2)', () {
      const text = '1girl, (white hair:1.2), cat';

      // Click inside 'white hair'
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 10, // 't' in 'white'
      );
      expect(selection.textInside(text), 'white hair');

      // Click on '('
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 7, // '('
      );
      expect(selection.textInside(text), '(white hair:1.2)');

      // Click on ':1.2'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 19, // '1' in ':1.2'
      );
      expect(selection.textInside(text), '(white hair:1.2)');
    });

    test('NAI numeric weight: 1.3::happy male furry::', () {
      const text = 'night, 1.3::happy male furry::, star';

      // Click inside
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 16, // inside happy
      );
      expect(selection.textInside(text), 'happy male furry');

      // Click on '1.3::'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 8, // '1'
      );
      expect(selection.textInside(text), '1.3::happy male furry::');
    });

    test('Multiple layers of brackets: {{{happy male furry}}}', () {
      const text = '{{{happy male furry}}}';

      // Click inside
      final selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 8, // inside happy
      );
      expect(selection.textInside(text), 'happy male furry');
    });

    test('# and ＃ delimiters: double click next to hash does not select hash', () {
      const text = 'source#kiss';

      // Double click 'kiss'
      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 8, // 'i' in 'kiss'
      );
      expect(selection.textInside(text), 'kiss');

      // Double click 'source'
      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 2, // 'u' in 'source'
      );
      expect(selection.textInside(text), 'source');
    });

    test('# with full-width ＃ and multiple words', () {
      const text = 'masterpiece#source#kiss，cute girl＃solo';

      var selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 19, // 'k' in 'kiss'
      );
      expect(selection.textInside(text), 'kiss');

      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 14, // in 'source'
      );
      expect(selection.textInside(text), 'source');

      selection = PromptPhraseSelectionUtils.calculateDoubleTapSelection(
        text: text,
        offset: 35, // in 'solo'
      );
      expect(selection.textInside(text), 'solo');
    });
  });
}
