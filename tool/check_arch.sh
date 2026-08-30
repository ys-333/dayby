#!/usr/bin/env bash
# Architectural invariants the Dart analyzer cannot express.
# Run from anywhere. Exits 1 and prints offenders on violation.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
report() { printf '%s\n' "$1"; fail=1; }

# grep lib/domain for a pattern, ignoring comment lines and generated files.
# Output is file:line:content, so a comment is a match whose content starts
# with // or *. Prose that merely names a banned construct must not trip this.
scan() {
  grep -rn --include='*.dart' -E "$1" lib/domain 2>/dev/null \
    | grep -vE '\.(g|freezed)\.dart:' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(///?|\*)'
}

[ -d lib/domain ] || exit 0

# 1. lib/domain/ is pure Dart: no Flutter, no Drift, no routing.
hits=$(scan "^\s*import\s+'(package:flutter/|package:flutter_riverpod/|package:drift/|package:go_router/)")
[ -n "$hits" ] && report "lib/domain must not import Flutter/Drift/routing:
$hits"

# 2. lib/domain/ must not depend on outer layers.
hits=$(scan "^\s*import\s+'(package:riyaz/(data|features)/|.*\.\./(data|features)/)")
[ -n "$hits" ] && report "lib/domain must not import data/ or features/:
$hits"

# 3. No ambient clock reads — inject Clock instead.
hits=$(scan "DateTime\.now\(\)|DateTime\.timestamp\(\)")
[ -n "$hits" ] && report "lib/domain must take time from an injected Clock, not ambient now():
$hits"

# 4. Scoring weights live in one module so they stay changeable.
hits=$(scan "\b0\.5\b" | grep -v '/scoring' || true)
[ -n "$hits" ] && report "partial-credit weight (0.5) belongs in the scoring module:
$hits"

# 5. Widget colours must be named app colours, never theme attributes.
#    RemoteViews are inflated by the launcher, so `?android:attr/...` resolves
#    against *the launcher's* theme rather than the user's dark-mode setting.
#    In practice that drew a white widget beside a dark app. Named colours with
#    a values-night variant put the choice back on the system setting. This
#    also covers values*/styles.xml, because the row style is where the first
#    attempt at this fix missed one and shipped dark text on a dark surface.
widget_attr_hits() {
  for f in android/app/src/main/res/layout/riyaz_widget*.xml; do
    [ -e "$f" ] || continue
    sed '/<!--/,/-->/d' "$f" | grep -o '?android:[A-Za-z/]*' | sed "s|^|$f: |"
  done
  for f in android/app/src/main/res/values*/styles.xml; do
    [ -e "$f" ] || continue
    sed -n '/<style name="RiyazWidget/,/<\/style>/p' "$f" \
      | grep -o '?android:[A-Za-z/]*' | sed "s|^|$f (RiyazWidget style): |"
  done
}
if [ -d android/app/src/main/res ]; then
  hits=$(widget_attr_hits)
  [ -n "$hits" ] && report "widget resources must use named colours, not theme attributes:
$hits"
fi

[ "$fail" -eq 0 ] && echo "architecture ok"
exit "$fail"
