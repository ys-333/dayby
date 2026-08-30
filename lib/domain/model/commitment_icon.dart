/// The commitment icon vocabulary, as **stored data** rather than as pixels.
///
/// `Commitment.icon` is a `String` that is written by the add screen, kept in
/// the database, and serialised into the backup format. That makes the set of
/// legal values a data contract, and a data contract belongs in the domain
/// beside the model it constrains — not in the widget that happens to draw it.
/// How a key becomes a glyph is a UI question and lives in `lib/app/glyphs.dart`.
///
/// **Why keys and not emoji.** The device pass found the full-colour emoji to
/// be the loudest thing on a deliberately muted screen — a row of saturated
/// pictograms shouting over type chosen to be quiet. Keys also render
/// identically on every device, where an emoji is whatever font the OS
/// happens to ship, and they can be re-drawn later without touching a single
/// stored row.
library;

/// Every icon key the app writes, in the order the picker offers them.
///
/// Grouped by what a person is actually doing, because that is how they will
/// look for one: work, then body, then mind, then the rest.
const List<String> commitmentIconKeys = [
  // Work
  'code', 'work', 'focus', 'note', 'rocket', 'money',
  // Body
  'run', 'walk', 'gym', 'swim', 'cycle', 'yoga', 'sleep', 'water', 'food',
  // Mind
  'read', 'book', 'study', 'write', 'language', 'music', 'art',
  // Everything else
  'call', 'family', 'clean', 'garden', 'outdoors', 'photo',
];

/// Emoji the app used to write, and the key each one becomes.
///
/// Exhaustive over what could actually be stored: the seven add-screen
/// templates and the fourteen the synthetic seeder used. It is not a general
/// emoji dictionary and is not meant to become one — anything outside it is
/// left alone rather than guessed at, and still renders, because a user's own
/// mark is theirs and a migration that silently replaced it with the nearest
/// glyph would be worse than one that left it.
const Map<String, String> legacyEmojiIcons = {
  '💻': 'code',
  '💼': 'work',
  '🚀': 'rocket',
  '🎯': 'focus',
  '🗒': 'note',
  '🏃': 'run',
  '🚶': 'walk',
  '🏋': 'gym',
  '🏊': 'swim',
  '🧘': 'yoga',
  '📚': 'study',
  '📖': 'read',
  '📕': 'book',
  '📞': 'call',
};

/// U+FE0F, the variation selector that renders the preceding character in
/// colour.
///
/// Several of the stored emoji carry it and several do not — `🏋️` and `🏋` are
/// different strings for the same picture — so it is stripped before any
/// lookup rather than doubling every row of the table. Public because the
/// schema v4 migration has to strip it in SQL, where this table's keys are the
/// bare forms.
const String variationSelector = '\uFE0F';

/// The key [stored] should be treated as, or null if it is neither a key nor a
/// legacy emoji this build recognises.
///
/// Returning null for the unrecognised case is deliberate: it lets the caller
/// decide, and the two callers want different things. The migration leaves the
/// value alone; the renderer draws it as text. Neither guesses.
String? iconKeyFor(String? stored) {
  if (stored == null) return null;
  final trimmed = stored.trim();
  if (trimmed.isEmpty) return null;
  if (commitmentIconKeys.contains(trimmed)) return trimmed;
  return legacyEmojiIcons[trimmed.replaceAll(variationSelector, '')];
}

/// Whether [stored] is something this build can draw as a glyph.
bool isKnownIcon(String? stored) => iconKeyFor(stored) != null;
