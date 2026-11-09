# sargent

`sargent` is a single binary that runs git hooks: forbidden paths, secret-shaped text in added lines, commit message format, and protected branches. This repo holds signed release binaries and the scripts that install them. It holds no source.

## Use the hooks in a repo

Add this to the repo's `.pre-commit-config.yaml`:

```yaml
default_install_hook_types: [pre-commit, pre-push, commit-msg]
repos:
  - repo: https://github.com/hmshafeeq/sargent-dist
    rev: v3.4.0
    hooks:
      - id: sargent-commit
      - id: sargent-msg
      - id: sargent-push
```

Then run `pre-commit install` once in each clone. On the first commit, the hook downloads the binary for `rev` into `~/.cache/sargent/` and checks it. Later commits use that copy. You do not need Rust or a GitHub token.

If the download fails, the commit stops with a `fix:` line. Check the network and commit again.

## Install the CLI

```sh
curl -fsSL https://raw.githubusercontent.com/hmshafeeq/sargent-dist/main/install.sh | sh
```

The script installs to `~/.local/bin/sargent`. To install somewhere else, set `SARGENT_INSTALL_DIR`. To install a named release, run `sh -s -- v3.4.0` in place of `sh`.

## Upgrade the CLI

| Command | Result |
|---|---|
| `sargent upgrade` | Installs the latest release and keeps the old binary as `sargent.previous`. |
| `sargent upgrade v3.4.0` | Installs that release. |
| `sargent upgrade --check` | Prints the installed and latest tags. Exits 10 when a newer release exists. |
| `sargent upgrade --rollback` | Swaps `sargent` and `sargent.previous`. |

`sargent upgrade` changes only the CLI you type. The hooks in each repo run the release that the repo's `rev` names.

## How a download is checked

Each release holds `sargent-<target>` for `darwin-arm64`, `darwin-x64`, and `linux-x64`, a `TAG` file, `SHA256SUMS`, and `SHA256SUMS.sig`. The hook script, `install.sh`, and `sargent upgrade` each do three checks before they run a binary:

1. `ssh-keygen -Y verify` checks `SHA256SUMS.sig` against the key in `allowed_signers`.
2. The binary's sha256 matches its line in `SHA256SUMS`.
3. `sargent version` prints the release tag.

If a check fails, nothing is installed.
