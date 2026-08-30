import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/formatting.dart';

void main() {
  group('dayHeadline', () {
    String today({required int left, int done = 0, int expected = 3}) =>
        dayHeadline(
          left: left,
          done: done,
          expected: expected,
          isToday: true,
        );

    test('counts down rather than scoring the day', () {
      expect(today(left: 3), 'Three left today');
      expect(today(left: 2, done: 1), 'Two left today');
      expect(today(left: 1, done: 2), 'One left today');
    });

    test('reaches a sentence, not a number, at zero', () {
      expect(today(left: 0, done: 3), 'Done for today');
    });

    test('never renders a percentage of a day still being lived', () {
      for (var left = 0; left <= 12; left++) {
        expect(today(left: left, expected: 12), isNot(contains('%')));
      }
    });

    test('falls back to numerals once the word is slower than the digit', () {
      expect(today(left: 6, expected: 6), 'Six left today');
      expect(today(left: 7, expected: 7), '7 left today');
      expect(today(left: 12, expected: 12), '12 left today');
    });

    test('a day with nothing daily due says so, rather than "Done"', () {
      // The user has only weekly targets. Claiming they are "done for today"
      // would be a completion they did not earn.
      expect(today(left: 0, expected: 0), 'Nothing due today');
    });

    test('a closed day tallies instead', () {
      expect(
        dayHeadline(left: 1, done: 2, expected: 3, isToday: false),
        '2 of 3 done',
      );
      expect(
        dayHeadline(left: 0, done: 0, expected: 0, isToday: false),
        'Nothing was due',
      );
    });
  });

  group('joinNames', () {
    test('reads as a sentence at every length', () {
      expect(joinNames([]), '');
      expect(joinNames(['Books']), 'Books');
      expect(joinNames(['Books', 'Swim']), 'Books and Swim');
      expect(
        joinNames(['Books', 'Swim', 'Long walk']),
        'Books, Swim and Long walk',
      );
    });
  });
}
