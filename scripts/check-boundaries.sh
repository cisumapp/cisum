#!/usr/bin/env bash
#
# check-boundaries.sh — mechanically enforce the architecture reset's module boundaries.
#
# The whole point of the reset is that each package's responsibility can be stated in one
# sentence. Import edges are how that erodes: one `import Player` inside Plugins and the
# composition root has quietly moved again. This script fails the build instead.
#
# Run from the repo root. Exits non-zero on any violation.

set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# check <dir> <forbidden-module> <why>
check() {
    local dir="$1" module="$2" why="$3"
    [ -d "$dir" ] || return 0
    if grep -rqE "^ *import +$module\b" --include='*.swift' "$dir" 2>/dev/null; then
        echo "BOUNDARY VIOLATION: $dir imports $module"
        echo "  why this is forbidden: $why"
        grep -rnE "^ *import +$module\b" --include='*.swift' "$dir" | sed 's/^/    /'
        echo
        fail=1
    fi
}

PSDK=Packages/StreamingKit/ProviderSDK/Sources
PLUG=Modules/Features/Plugins/Sources
PLAY=Modules/Features/Player/Sources

# ProviderSDK is a standalone networking + JS execution layer. It returns provider data.
# It must not know what cisum believes about that data, and must not own storage.
check "$PSDK" Plugins   "ProviderSDK must not know plugins are managed; it consumes a PluginCatalog"
check "$PSDK" Player    "ProviderSDK must not know about playback"
check "$PSDK" Models    "ProviderSDK must not know cisum's canonical models"
check "$PSDK" SwiftData "ProviderSDK must not own persistence"
check "$PSDK" Utilities "ProviderSDK is standalone (own git/remote); it uses its own SDKSignpost"

# Plugins manages the plugin catalog. It never executes a plugin and never composes playback.
check "$PLUG" ProviderSDK "Plugins must stay decoupled; Core adapts InstalledPlugin -> PluginBundle"
check "$PLUG" Player      "Plugins must not compose the playback chain; that is Core's job"

# Player consumes MusicSource. It has no idea whether a source came from a plugin.
check "$PLAY" Plugins "Player must not know a plugin exists"

if [ $fail -eq 0 ]; then
    echo "boundaries OK"
fi
exit $fail
