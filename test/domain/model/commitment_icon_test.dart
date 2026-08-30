import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/commitment_icon.dart';

void main() {
  group('iconKeyFor', () {
    test('a key is itself', () {
      for (final key in commitmentIconKeys) {
        expect(iconKeyFor(key), key);
      }
    });

    test('every legacy emoji resolves to a key that exists', () {
      // The failure this catches is a typo in the mapping table: an emoji
      // pointing at a key nothing draws would migrate a row into a mark that
      // renders as nothing at all, and the migration is not reversible.
      for (final entry in legacyEmojiIcons.entries) {
        expect(commitmentIconKeys, contains(entry.value),
            reason: '${entry.key} maps to "${entry.value}", which is not in '
                'the vocabulary');
      }
    });

    test('a variation selector does not hide an emoji from the table', () {
      // `🏋️` and `🏋` are the same picture and different strings. The seeder
      // wrote the first; the table holds the second.
      expect(iconKeyFor('🏋$variationSelector'), 'gym');
      expect(iconKeyFor('🏋'), 'gym');
      expect(iconKeyFor('🗒$variationSelector'), 'note');
    });

    test('an unknown mark resolves to nothing rather than to a guess', () {
      // Null is what lets the migration leave it alone and the renderer draw
      // it verbatim. A nearest-match would destroy something on a guess.
      expect(iconKeyFor('🦖'), isNull);
      expect(iconKeyFor('anything'), isNull);
      expect(iconKeyFor(''), isNull);
      expect(iconKeyFor('   '), isNull);
      expect(iconKeyFor(null), isNull);
    });

    test('surrounding whitespace does not defeat the lookup', () {
      expect(iconKeyFor(' run '), 'run');
      expect(iconKeyFor(' 🏃 '), 'run');
    });
  });

  test('every key is unique', () {
    expect(commitmentIconKeys.toSet(), hasLength(commitmentIconKeys.length));
  });

  test('the seven add-screen templates all still map', () {
    // These are the values a real user's database is most likely to hold.
    for (final emoji in ['💻', '🏃', '🏋', '📚', '🧘', '💼', '🚀']) {
      expect(isKnownIcon(emoji), isTrue, reason: '$emoji lost its mapping');
    }
  });
}
