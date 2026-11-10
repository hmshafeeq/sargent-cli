# sargent

`sargent` is a single binary that runs git hooks: forbidden paths, secret-shaped text in added lines, commit message format, and protected branches. This repo holds signed release binaries and the scripts that install them. It holds no source.

## Use the hooks in a repo

Add this to the repo's `.pre-commit-config.yaml`:

```yaml
default_install_hook_types: [pre-commit, pre-push, commit-msg]
repos:
  - repo: https://github.com/hmshafeeq/sargent-cli
    rev: v3.5.0-rc1
    hooks:
      - id: sargent-commit
      - id: sargent-msg
      - id: sargent-push
```

To pin the commit instead of the tag, run `pre-commit autoupdate --freeze --repo https://github.com/hmshafeeq/sargent-cli` after you add it. The next section says why a commit pin is stronger.

Then run `pre-commit install` once in each clone. On the first commit, the hook downloads the binary for `rev` into `~/.cache/sargent/` and checks it. Later commits use that copy. You do not need Rust or a GitHub token.

If the download fails, the commit stops with a `fix:` line. Check the network and commit again.

On Windows, commit from Git Bash (Git for Windows). The hooks download `sargent-windows-x64.exe`, which runs the three git hooks with the same verdicts as the macOS and Linux builds and nothing else.

A final release (a tag with no hyphen) does not carry `windows-x64` yet. Only release candidates, such as `v3.5.0-rc1`, do. On a final release the hook stops with a `fix:` line. Pin a release-candidate tag, or commit from WSL2 (Ubuntu), where the `linux-x64` release runs in full. The CLI below is not built for Windows.

## Install the CLI

```sh
curl -fsSL https://raw.githubusercontent.com/hmshafeeq/sargent-cli/main/install.sh | sh
```

The script installs to `~/.local/bin/sargent`. To install somewhere else, set `SARGENT_INSTALL_DIR`. To install a named release, run `sh -s -- v3.5.0-rc1` in place of `sh`.

## Upgrade the CLI

| Command | Result |
|---|---|
| `sargent upgrade` | Installs the latest release and keeps the old binary as `sargent.previous`. A release candidate upgrades to its release. |
| `sargent upgrade v3.5.0-rc1` | Installs that release. A release you already run changes nothing. |
| `sargent upgrade --check` | Prints the installed and latest tags. Exits 10 when a newer release exists. |
| `sargent upgrade --rollback` | Swaps `sargent` and `sargent.previous`. |

`sargent upgrade` changes only the CLI you type. The hooks in each repo run the release that the repo's `rev` names.

## How a download is checked

Each release holds `sargent-<target>` for `darwin-arm64`, `darwin-x64` and `linux-x64`, and a release candidate also holds `windows-x64` (as `sargent-windows-x64.exe`). A final release adds `windows-x64` once the maintainer has recorded a smoke run on real Windows. Each release also holds a `TAG` file, `SHA256SUMS`, and `SHA256SUMS.sig`. The hook script, `install.sh`, and `sargent upgrade` each do three checks before they run a binary:

1. `ssh-keygen -Y verify` checks `SHA256SUMS.sig` against the key in `allowed_signers`.
2. The binary's sha256 matches its line in `SHA256SUMS`.
3. `sargent version` prints the release tag.

If a check fails, nothing is installed.

## What the checks protect

The checks stop a changed binary on the download path. A copy that differs from its signed sum, a sum file that the release key did not sign, and a binary that prints another tag are each refused.

The checks do not stop these cases:

- **A changed dist repo.** The hook script and `install.sh` read the key from this repo. Anyone who can write to this repo can change the scripts, the key and the tags together. `sargent upgrade` is the exception: its key is built into the binary. A `rev` pinned to a commit keeps a repo on the files it pinned, so a moved tag cannot change its hooks. A `rev` pinned to a tag follows the tag.
- **A changed cache.** The hook checks the binary once, when it downloads it to `~/.cache/sargent/`. It does not hash it again on each commit. A program that runs as you can change that copy, but it can also change the hook script in `~/.cache/pre-commit/` or `.git/hooks/`, so a second hash would not stop it.
- **An old release served as the latest.** The signed `TAG` holds no date. If someone serves an older signed release as the latest, `sargent upgrade --check` reports that you are current. `sargent upgrade` never installs an older release than the one you run.
