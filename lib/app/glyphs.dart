import 'package:flutter/material.dart';
import 'package:riyaz/domain/model/commitment_icon.dart';

/// How each icon key is drawn, and what to call it out loud.
///
/// The vocabulary itself — which keys exist, and which legacy emoji map onto
/// them — lives in `lib/domain/model/commitment_icon.dart`, because that is
/// stored data. This file is only the picture, and it is the one place to
/// change if the marks are ever redrawn as bundled vector assets: nothing
/// stored has to move.
///
/// **Outlined weights throughout.** The design board specifies stroked 1.5px
/// glyphs, and Material's outlined set is the same idea already in the font —
/// no asset, no new dependency, and it scales with text size, which a bundled
/// SVG at a fixed box would not.
const Map<String, (IconData, String)> _glyphs = {
  'code': (Icons.code_rounded, 'Code'),
  'work': (Icons.work_outline_rounded, 'Work'),
  'focus': (Icons.center_focus_strong_outlined, 'Focus'),
  'note': (Icons.sticky_note_2_outlined, 'Notes'),
  'rocket': (Icons.rocket_launch_outlined, 'Launch'),
  'money': (Icons.savings_outlined, 'Money'),
  'run': (Icons.directions_run_rounded, 'Run'),
  'walk': (Icons.directions_walk_rounded, 'Walk'),
  'gym': (Icons.fitness_center_rounded, 'Gym'),
  'swim': (Icons.pool_outlined, 'Swim'),
  'cycle': (Icons.directions_bike_rounded, 'Cycle'),
  'yoga': (Icons.self_improvement_outlined, 'Yoga'),
  'sleep': (Icons.bedtime_outlined, 'Sleep'),
  'water': (Icons.water_drop_outlined, 'Water'),
  'food': (Icons.restaurant_outlined, 'Food'),
  'read': (Icons.menu_book_outlined, 'Read'),
  'book': (Icons.book_outlined, 'Books'),
  'study': (Icons.school_outlined, 'Study'),
  'write': (Icons.edit_outlined, 'Write'),
  'language': (Icons.translate_rounded, 'Language'),
  'music': (Icons.music_note_outlined, 'Music'),
  'art': (Icons.brush_outlined, 'Art'),
  'call': (Icons.call_outlined, 'Call'),
  'family': (Icons.favorite_border_rounded, 'People'),
  'clean': (Icons.cleaning_services_outlined, 'Tidy'),
  'garden': (Icons.local_florist_outlined, 'Garden'),
  'outdoors': (Icons.terrain_outlined, 'Outdoors'),
  'photo': (Icons.photo_camera_outlined, 'Photos'),
};

/// The glyph for a stored icon value, or null if this build cannot draw it.
///
/// Accepts a key or a legacy emoji, so a row that has not been migrated — or
/// one restored from an old backup — still gets a mark.
IconData? glyphFor(String? stored) {
  final key = iconKeyFor(stored);
  return key == null ? null : _glyphs[key]?.$1;
}

/// The screen-reader name for a stored icon value.
String? glyphLabelFor(String? stored) {
  final key = iconKeyFor(stored);
  return key == null ? null : _glyphs[key]?.$2;
}

/// Every key in picker order, paired with its glyph and label.
Iterable<(String, IconData, String)> get glyphVocabulary sync* {
  for (final key in commitmentIconKeys) {
    final glyph = _glyphs[key];
    if (glyph != null) yield (key, glyph.$1, glyph.$2);
  }
}
