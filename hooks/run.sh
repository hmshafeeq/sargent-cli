#!/bin/sh
# The pre-commit entry: hooks/run.sh <tag> <sargent arguments>.
# The tag comes from the hook entry, because pre-commit's clone holds no tags.
# The binary is downloaded once per tag into a cache that this script alone
# writes. A sargent on PATH is never used.
set -eu
tag=$1
shift
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/hooks/lib.sh"

cache=${XDG_CACHE_HOME:-$HOME/.cache}/sargent/$tag/$(sargent_target)
bin=$cache/sargent
if [ ! -x "$bin" ]; then
	if ! sargent_install "$tag" "$bin" "$here/allowed_signers"; then
		echo "sargent: cannot download $tag for $(sargent_target)." >&2
		echo "fix: check the network, then commit again. The binary downloads once per version." >&2
		exit 1
	fi
fi
said=$("$bin" version) || said=""
[ "$said" = "$tag" ] || sargent_die "$bin reports '$said', not $tag. fix: rm -r $cache"
exec "$bin" "$@"
