# PAX Command Reference

Global flag: `--no-color` disables colored output on any command (PAX also
respects the `NO_COLOR` environment variable and auto-disables color when
stdout is not a terminal).

Running `pax` with no arguments opens a friendly, arrow-key driven menu
(built with `dialoguer`) covering the most common actions. `pax tutorial`
runs a short guided walkthrough for first-time users that initializes a
practice repository, stages a sample file, creates a snapshot, and shows a
cheat-sheet of what to try next.

## Repository lifecycle

- `pax init [path]` / `pax init -p <path>` / `pax init --path <path>` —
  Initialize a new PAX repository at `path` (defaults to the current
  directory), creating `project.pax/`. The path can be given either
  positionally or via the `-p`/`--path` flag.
- `pax status` — Show staged, untracked, modified, and deleted files
  relative to the last snapshot.
- `pax add <path...>` — Chunk, hash, compress, and stage the given files or
  directories (respects `.paxignore` files, gitignore-style).
- `pax commit -m "<message>" [--author <name>]` — Create a new snapshot from
  staged changes. Prints files changed and new-vs-deduplicated bytes.
- `pax log` — Show snapshot history, newest first.
- `pax timeline` — Same history as a small visual graph.
- `pax diff <snapshotA> <snapshotB>` — Show added/removed/modified files
  between two snapshots. Accepts `latest`, `HEAD`, a full hex id, or any
  unambiguous hex prefix.
- `pax restore <snapshot> [--force]` — Restore the working directory to a
  snapshot without moving the current branch pointer. Refuses to run over
  uncommitted changes unless `--force` is passed.
- `pax checkout <snapshot> [--force]` — Same as `restore`, and also moves
  `HEAD` to the given snapshot.

## Archive operations

- `pax pack <path> [-o out.pax]` — Bundle a repository into a single
  portable `.pax` file.
- `pax extract <file.pax> [-o dir]` — Extract a `.pax` file to plain files
  with zero PAX lock-in.
- `pax mount <archive-or-repo> <mountpoint>` — Mount a repository (or `.pax`
  archive) read-only through FUSE (Linux/macOS in this build; Windows needs
  a WinFsp-based backend, not yet implemented).
- `pax unmount <mountpoint>` — Unmount a previously mounted archive.

## Remote / collaboration

- `pax remote add <name> <url>` / `pax remote list` — Manage named remotes,
  stored in `config.toml`. A remote target can be a filesystem path (treated
  as another `project.pax` directory, e.g. on a network share) or an
  `http(s)://` URL pointing at a running `pax serve`.
- `pax push <remote>` — Upload new objects and snapshot manifests.
- `pax pull <remote>` — Download new objects and snapshot manifests, and
  advance the local `latest` ref if the remote is ahead.
- `pax clone <remote> <path>` — Initialize a new repository at `path` and
  pull everything from `remote`.

## Local serving

- `pax serve [--lan] [--port N] [--token <secret>]` — Serve repository
  objects, snapshot manifests, and refs over local HTTP. Binds to
  `127.0.0.1` by default; `--lan` opts into `0.0.0.0`. `--token` requires a
  bearer token for write requests (used by `push`).

## Linking / dedup across projects

- `pax link <archive> <object>` — Hard-link (falling back to copy) a single
  content object from another archive or repository into the current
  object store without duplicating its bytes on disk.

## Object / integrity utilities

- `pax verify` — Recompute the BLAKE3 hash of every stored object and report
  any that fail to match their filename.
- `pax gc [--dry-run]` — Delete objects that are not referenced by any
  snapshot or staged file. `--dry-run` reports what would be removed without
  deleting anything.

## Tooling / meta

- `pax update` — Self-update via GitHub Releases.
- `pax version` — Print the banner, binary version, and repository format
  version.
- `pax tutorial` — Run the interactive guided walkthrough for beginners.
- `pax help`, `pax <command> --help` — Full contextual help.
