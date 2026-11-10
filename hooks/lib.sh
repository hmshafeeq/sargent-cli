# Shared by hooks/run.sh, scripts/dist-publish.sh and scripts/dist-check.sh
# (sourced) and by install.sh (inlined at publish). A release holds
# sargent-<target>, TAG, SHA256SUMS over both, and SHA256SUMS.sig. Nothing is
# trusted before that signature verifies against the allowed_signers file;
# the binary must then match its sum and print its tag. `sargent upgrade`
# checks the same three things. Every variable a function sets starts with
# _sg_, so a caller's own variables survive.

SARGENT_DIST_BASE=${SARGENT_DIST_BASE:-https://github.com/hmshafeeq/sargent-cli/releases}

# The asset name of every release target. sargent_target, `upgrade::target`
# and the release.yml matrix name the same set; tests/dist.rs compares them.
# The windows-x64 asset is sargent-windows-x64.exe (sargent_exe); it carries
# the git hooks and `version` only, for Git Bash.
SARGENT_TARGETS="darwin-arm64 darwin-x64 linux-x64 windows-x64"

# A final tag (no hyphen) ships windows-x64 only when this is yes. Set it in
# the commit that records a passing smoke run of the .exe in Git Bash on
# real Windows (AGENTS.md, "Adding a subcommand"). A release candidate always
# carries the asset, so that run has a binary to test.
SARGENT_WINDOWS_FINAL=no

# The toolchain that cross-builds windows-x64. scripts/dist-local-release.sh
# and release.yml refuse any other version.
SARGENT_ZIG_VERSION=0.17.1
SARGENT_ZIGBUILD_VERSION=0.24.1

sargent_die() {
	echo "sargent: $*" >&2
	exit 1
}

sargent_target() {
	case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) echo darwin-arm64 ;;
	Darwin-x86_64) echo darwin-x64 ;;
	Linux-x86_64) echo linux-x64 ;;
	MINGW*-x86_64 | MSYS*-x86_64 | CYGWIN*-x86_64) echo windows-x64 ;;
	MINGW* | MSYS* | CYGWIN*) sargent_die "no Windows release is built for $(uname -m).
fix: commit from WSL2 (Ubuntu), where the linux-x64 release runs." ;;
	*) sargent_die "no release is built for $(uname -s)-$(uname -m)" ;;
	esac
}

# sargent_exe TARGET: the suffix of a binary for TARGET. Windows runs .exe.
sargent_exe() {
	case "$1" in
	windows-*) echo .exe ;;
	esac
}

# sargent_release_targets TAG: the assets a release at TAG carries, one line.
sargent_release_targets() {
	_sg_list=
	for _sg_t in $SARGENT_TARGETS; do
		case "$_sg_t:$1:$SARGENT_WINDOWS_FINAL" in
		windows-x64:*-*:*) ;;
		windows-x64:*:yes) ;;
		windows-x64:*) continue ;;
		esac
		_sg_list=${_sg_list:+$_sg_list }$_sg_t
	done
	echo "$_sg_list"
}

# sargent_check_zigbuild: dies with a fix line unless zig and cargo-zigbuild
# are the pinned versions. cargo-zigbuild runs `python3 -m ziglang` before a
# zig on PATH, so the check asks in that order.
sargent_check_zigbuild() {
	_sg_zig=$(python3 -m ziglang version 2>/dev/null || zig version 2>/dev/null || true)
	[ "$_sg_zig" = "$SARGENT_ZIG_VERSION" ] ||
		sargent_die "zig is '${_sg_zig:-missing}', the windows-x64 build pins $SARGENT_ZIG_VERSION.
fix: install zig $SARGENT_ZIG_VERSION (brew, or pip install ziglang==$SARGENT_ZIG_VERSION)."
	_sg_zb=$(cargo-zigbuild --version 2>/dev/null || true)
	[ "$_sg_zb" = "cargo-zigbuild $SARGENT_ZIGBUILD_VERSION" ] ||
		sargent_die "cargo-zigbuild is '${_sg_zb:-missing}', the windows-x64 build pins $SARGENT_ZIGBUILD_VERSION.
fix: cargo install cargo-zigbuild --version $SARGENT_ZIGBUILD_VERSION --locked."
}

# sargent_valid_tag TAG: vMAJOR.MINOR.PATCH with an optional -suffix of
# letters, digits and dots. It is the rule of `upgrade::valid_tag`.
sargent_valid_tag() {
	awk 'BEGIN { exit !(ARGV[1] ~ /^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$/) }' "$1"
}

# sargent_need: the tools a download needs, each with its own fix line.
sargent_need() {
	command -v curl >/dev/null 2>&1 ||
		sargent_die "curl is not installed; it downloads the release.
fix: install curl, then try again."
	command -v ssh-keygen >/dev/null 2>&1 ||
		sargent_die "ssh-keygen is not installed; it checks the release signature.
fix: install openssh-client (8.1 or later), then try again."
}

sargent_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -c1-64
	else
		shasum -a 256 "$1" | cut -c1-64
	fi
}

# sargent_fetch URL DEST: returns 2 when the download fails.
sargent_fetch() {
	case "$1" in
	https://*) curl -fsSL --retry 2 --max-time 120 --proto =https --proto-redir =https -o "$2" "$1" ;;
	*) curl -fsSL --retry 2 --max-time 120 -o "$2" "$1" ;;
	esac || return 2
}

# sargent_sum SUMS NAME: the signed sum of NAME, or nothing.
sargent_sum() {
	awk -v n="$2" '$2 == n || $2 == "*" n { print $1; exit }' "$1"
}

# sargent_verified_sums PREFIX SIGNERS WORK: downloads SHA256SUMS and its
# signature into WORK and verifies them. Returns 2 when a download fails and
# 1 when the signature does not verify.
sargent_verified_sums() {
	sargent_fetch "$1/SHA256SUMS" "$3/SHA256SUMS" || return 2
	sargent_fetch "$1/SHA256SUMS.sig" "$3/SHA256SUMS.sig" || return 2
	if ! _sg_err=$(ssh-keygen -Y verify -f "$2" -I sargent-release -n sargent \
		-s "$3/SHA256SUMS.sig" <"$3/SHA256SUMS" 2>&1 >/dev/null); then
		echo "sargent: SHA256SUMS signature does not verify against the release key" >&2
		printf '%s\n' "$_sg_err" | sed 's/^/  ssh-keygen: /' >&2
		case "$_sg_err" in
		*option*) echo "fix: this ssh-keygen has no -Y verify; install openssh-client 8.1 or later." >&2 ;;
		esac
		return 1
	fi
}

# sargent_latest SIGNERS: prints the tag of the latest release.
sargent_latest() {
	_sg_work=$(mktemp -d)
	_sg_st=0
	sargent_latest_in "$1" "$_sg_work" || _sg_st=$?
	rm -r "$_sg_work"
	return "$_sg_st"
}

sargent_latest_in() {
	_sg_prefix=$SARGENT_DIST_BASE/latest/download
	sargent_verified_sums "$_sg_prefix" "$1" "$2" || return $?
	sargent_fetch "$_sg_prefix/TAG" "$2/TAG" || return 2
	[ "$(sargent_sum "$2/SHA256SUMS" TAG)" = "$(sargent_sha256 "$2/TAG")" ] ||
		{ echo "sargent: TAG does not match the signed SHA256SUMS" >&2; return 1; }
	_sg_tag=$(tr -d '[:space:]' <"$2/TAG")
	sargent_valid_tag "$_sg_tag" ||
		{ echo "sargent: the latest release names $_sg_tag, not a release tag" >&2; return 1; }
	echo "$_sg_tag"
}

# sargent_install TAG DEST SIGNERS: puts the verified release binary at DEST.
# Returns 2 when a download fails, 3 when the signed release lacks the asset
# for this machine, and 1 when a check fails.
sargent_install() {
	_sg_target=$(sargent_target) || return 1
	_sg_asset=sargent-$_sg_target$(sargent_exe "$_sg_target")
	_sg_work=$(mktemp -d)
	_sg_st=0
	sargent_install_in "$1" "$2" "$3" "$_sg_work" "$_sg_asset" || _sg_st=$?
	rm -r "$_sg_work"
	return "$_sg_st"
}

sargent_install_in() {
	_sg_prefix=$SARGENT_DIST_BASE/download/$1
	sargent_verified_sums "$_sg_prefix" "$3" "$4" || return $?
	_sg_want=$(sargent_sum "$4/SHA256SUMS" "$5")
	[ -n "$_sg_want" ] || { echo "sargent: release $1 has no $5" >&2; return 3; }
	sargent_fetch "$_sg_prefix/$5" "$4/$5" || return 2
	_sg_got=$(sargent_sha256 "$4/$5")
	[ "$_sg_got" = "$_sg_want" ] ||
		{ echo "sargent: $5 sha256 $_sg_got does not match the signed $_sg_want" >&2; return 1; }
	chmod 755 "$4/$5"
	_sg_said=$("$4/$5" version) || { echo "sargent: $5 does not run on this machine" >&2; return 1; }
	[ "$_sg_said" = "$1" ] || { echo "sargent: $5 reports $_sg_said, not $1" >&2; return 1; }
	mkdir -p "$(dirname "$2")" || return 1
	cp "$4/$5" "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
}
