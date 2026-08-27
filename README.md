# PAX

**Version anything. Store everything.**

PAX is a universal, content-addressed archive and versioning system for
projects of any size, with first-class support for large binary files (game
assets, 3D models, video, audio, datasets, CAD files). It combines Git-like
snapshots, ZIP-like portable archiving, chunk-level deduplication, a
read-only virtual mount, and a push/pull remote model that never requires
opening a network port.

The golden rule: **PAX stays usable without PAX.** `pax extract` always
produces plain, ordinary files with zero lock-in, and the on-disk format is
fully documented in [docs/FORMAT.md](docs/FORMAT.md).

## Quickstart

New to PAX? Just run `pax` with no arguments for a friendly arrow-key menu,
or `pax tutorial` for a guided, interactive walkthrough. Otherwise:

```sh
pax init my-project
cd my-project
pax add .
pax commit -m "initial import"
pax log
pax pack . -o my-project.pax
```

## Install

- **Windows**: `InstallScripts\install.ps1`
- **macOS / Linux**: `InstallScripts/install.sh`

Both scripts download the correct release binary from GitHub Releases,
verify its SHA-256 checksum, install it to a per-user location, and add that
location to your `PATH`.

## Building from source

```sh
cd Pax
cargo build --release --workspace
```

Or use the automation scripts in `FunctionsScriptsExe/` (`build.bat`,
`test.bat`, `lint.bat`, ...). See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what each script does and
how the workspace's crates fit together, and
[docs/CLI.md](docs/CLI.md) for the full command reference.

## Project layout

```
Pax/                    Cargo workspace (pax-cli, pax-core, pax-chunking, ...)
FunctionsScriptsExe/     Build, test, lint, package, and release automation (.bat)
InstallScripts/          Universal install scripts (install.sh, install.ps1)
docs/                    Format spec, architecture overview, CLI reference
```

## Status

The repository engine (`init`, `add`, `status`, `commit`, `log`, `diff`,
`restore`, `checkout`, `verify`, `gc`, `pack`, `extract`), local HTTP serving,
local/HTTP remotes, and the Unix FUSE mount are implemented and wired into
the CLI. Releases are published from
[SH-ENTERTAINMENT/pax](https://github.com/SH-ENTERTAINMENT/pax). Before
cutting a real release you will still need to:

- Provide real S3/SFTP credentials if you want those remote backends (only
  local-directory and `pax serve` HTTP remotes are implemented today).
- Set up the external Homebrew tap, Scoop bucket, `winget-pkgs` fork, and
  APT hosting referenced by the `publish_*.bat` scripts.
