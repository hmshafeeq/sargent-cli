#!/bin/sh
# Installs the sargent CLI from a signed release.
#   curl -fsSL https://raw.githubusercontent.com/hmshafeeq/sargent-dist/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- v3.4.0      a named release
# SARGENT_INSTALL_DIR replaces ~/.local/bin.
set -eu

# Shared by hooks/run.sh (sourced) and install.sh (inlined at publish).
# A release holds sargent-<target>, TAG, SHA256SUMS over both, and
# SHA256SUMS.sig. Nothing is trusted before that signature verifies against
# the allowed_signers file; the binary must then match its sum and print its
# tag. `sargent upgrade` checks the same three things.

SARGENT_DIST_BASE=${SARGENT_DIST_BASE:-https://github.com/hmshafeeq/sargent-dist/releases}

sargent_die() {
	echo "sargent: $*" >&2
	exit 1
}

sargent_target() {
	case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) echo darwin-arm64 ;;
	Darwin-x86_64) echo darwin-x64 ;;
	Linux-x86_64) echo linux-x64 ;;
	*) sargent_die "no release is built for $(uname -s)-$(uname -m)" ;;
	esac
}

sargent_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -c1-64
	else
		shasum -a 256 "$1" | cut -c1-64
	fi
}

# sargent_fetch URL DEST
sargent_fetch() {
	case "$1" in
	https://*) curl -fsSL --retry 2 --max-time 120 --proto =https --proto-redir =https -o "$2" "$1" ;;
	*) curl -fsSL --retry 2 --max-time 120 -o "$2" "$1" ;;
	esac
}

# sargent_sum SUMS NAME: the signed sum of NAME, or nothing.
sargent_sum() {
	awk -v n="$2" '$2 == n || $2 == "*" n { print $1; exit }' "$1"
}

# sargent_verified_sums PREFIX SIGNERS WORK: downloads SHA256SUMS and its
# signature into WORK and verifies them.
sargent_verified_sums() {
	sargent_fetch "$1/SHA256SUMS" "$3/SHA256SUMS" || return 1
	sargent_fetch "$1/SHA256SUMS.sig" "$3/SHA256SUMS.sig" || return 1
	ssh-keygen -Y verify -f "$2" -I sargent-release -n sargent \
		-s "$3/SHA256SUMS.sig" <"$3/SHA256SUMS" >/dev/null 2>&1 ||
		{ echo "sargent: SHA256SUMS signature does not verify against the release key" >&2; return 1; }
}

# sargent_latest SIGNERS: prints the tag of the latest release.
sargent_latest() {
	work=$(mktemp -d)
	prefix=$SARGENT_DIST_BASE/latest/download
	if sargent_verified_sums "$prefix" "$1" "$work" && sargent_fetch "$prefix/TAG" "$work/TAG" &&
		[ "$(sargent_sum "$work/SHA256SUMS" TAG)" = "$(sargent_sha256 "$work/TAG")" ]; then
		tag=$(tr -d '[:space:]' <"$work/TAG")
		rm -r "$work"
		case "$tag" in v[0-9]*.[0-9]*.[0-9]*) echo "$tag" ;; *) return 1 ;; esac
	else
		rm -r "$work"
		return 1
	fi
}

# sargent_install TAG DEST SIGNERS: puts the verified release binary at DEST.
sargent_install() {
	asset=sargent-$(sargent_target)
	work=$(mktemp -d)
	if sargent_install_in "$1" "$2" "$3" "$work" "$asset"; then
		rm -r "$work"
	else
		rm -r "$work"
		return 1
	fi
}

sargent_install_in() {
	prefix=$SARGENT_DIST_BASE/download/$1
	sargent_verified_sums "$prefix" "$3" "$4" || return 1
	want=$(sargent_sum "$4/SHA256SUMS" "$5")
	[ -n "$want" ] || { echo "sargent: release $1 has no $5" >&2; return 1; }
	sargent_fetch "$prefix/$5" "$4/$5" || return 1
	got=$(sargent_sha256 "$4/$5")
	[ "$got" = "$want" ] || { echo "sargent: $5 sha256 $got does not match the signed $want" >&2; return 1; }
	chmod 755 "$4/$5"
	said=$("$4/$5" version) || return 1
	[ "$said" = "$1" ] || { echo "sargent: $5 reports $said, not $1" >&2; return 1; }
	mkdir -p "$(dirname "$2")"
	cp "$4/$5" "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
}

SARGENT_RELEASE_KEY='sargent-release ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICvQSHtc5NQo0xouHE+qvsyEKyZCMhPmsSD9rX+/7iVZ sargent-release'

# Everything runs from main, called on the last line, so a cut download
# runs nothing.
main() {
	dir=${SARGENT_INSTALL_DIR:-$HOME/.local/bin}
	dest=$dir/sargent
	[ -L "$dest" ] && sargent_die "$dest is a symlink. It points at a binary that another tool manages, so install.sh leaves it alone."
	signers=${SARGENT_ALLOWED_SIGNERS:-}
	if [ -z "$signers" ]; then
		signers=$(mktemp)
		printf '%s\n' "$SARGENT_RELEASE_KEY" >"$signers"
	fi
	tag=${1:-}
	if [ -z "$tag" ]; then
		tag=$(sargent_latest "$signers") || sargent_die "cannot read the latest release"
	fi
	sargent_install "$tag" "$dest" "$signers" || sargent_die "install of $tag failed"
	[ -n "${SARGENT_ALLOWED_SIGNERS:-}" ] || rm -f "$signers"
	echo "installed $dest ($tag)"
	case ":$PATH:" in
	*":$dir:"*) ;;
	*) echo "add $dir to PATH to run sargent" ;;
	esac
	echo "to upgrade later: sargent upgrade"
}

main "$@"
