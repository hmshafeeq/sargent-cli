#!/usr/bin/env sh
# The pre-commit entry: hooks/run.sh <tag> <sargent arguments>.
# The tag comes from the hook entry, because pre-commit's clone holds no tags.
# The binary is downloaded once per tag into a cache that this script alone
# writes. A sargent on PATH is never used. The cached copy is not hashed
# again on each run; README.md, "What the checks protect", says why.
set -eu
tag=$1
shift
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/hooks/lib.sh"

sargent_valid_tag "$tag" || sargent_die "the hook entry names $tag, not a release tag."
target=$(sargent_target)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/sargent/$tag/$target
bin=$cache/sargent$(sargent_exe "$target")
if [ ! -x "$bin" ]; then
	sargent_need
	status=0
	sargent_install "$tag" "$bin" "$here/allowed_signers" || status=$?
	case $status in
	0) ;;
	2)
		echo "sargent: cannot download $tag for $target." >&2
		echo "fix: check the network, then commit again. The binary downloads once per version." >&2
		exit 1
		;;
	3)
		case $target in
		windows-x64)
			echo "sargent: release $tag has no Windows build. A final release ships windows-x64 only after a smoke run on real Windows." >&2
			echo "fix: pin a release-candidate tag (vX.Y.Z-rcN) in the hook entry and in rev, or commit from WSL2 (Ubuntu), where the linux-x64 release runs." >&2
			;;
		*)
			echo "sargent: release $tag has no build for $target." >&2
			echo "fix: pin a release that lists $target, or report this to the sargent maintainer." >&2
			;;
		esac
		exit 1
		;;
	*)
		echo "sargent: the $tag release failed the check above, so the hook did not run it." >&2
		echo "fix: report the lines above to the sargent maintainer. Do not skip the hook." >&2
		exit 1
		;;
	esac
fi
said=$("$bin" version) || said=""
[ "$said" = "$tag" ] || sargent_die "$bin reports '$said', not $tag. fix: rm -r $cache"
exec "$bin" "$@"
