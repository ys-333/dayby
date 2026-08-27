#!/usr/bin/env bash
# Stop hook: block finishing while static checks are dirty.
# Runs tool/check_arch.sh (architecture invariants) then `flutter analyze`.
# Does NOT run tests — those stay manual. Exits 0 silently when there is
# nothing to check yet (no pubspec.yaml, no flutter toolchain).

input=$(cat)

# Don't re-block when Claude is already continuing because of this hook.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

# Fall back to the script's own location rather than a hardcoded path:
# portable, and it keeps a username out of a committed file.
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}" 2>/dev/null || exit 0
[ -f pubspec.yaml ] || exit 0

# Flutter lives outside the login PATH on this machine; fall back to it.
[ -d "$HOME/development/flutter/bin" ] && PATH="$HOME/development/flutter/bin:$PATH"
command -v flutter >/dev/null 2>&1 || exit 0

problems=""

if [ -x tool/check_arch.sh ]; then
  arch_out=$(./tool/check_arch.sh 2>&1) || problems="${problems}${arch_out}

"
fi

analyze_out=$(flutter analyze 2>&1) || problems="${problems}${analyze_out}
"

[ -z "$problems" ] && exit 0

printf '%s' "$problems" | jq -Rs '{
  decision: "block",
  reason: ("Static checks are not clean. Fix every item below before finishing:\n\n" + .)
}'
