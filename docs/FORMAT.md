# PAX On-Disk Format Specification

This document is the authoritative description of the PAX repository format
and the portable `.pax` container format. It exists to guarantee the golden
rule of PAX: **a user can always extract their data with `pax extract`, or
inspect it by hand, even if the PAX binary disappears.**

## Repository layout (`project.pax/`)

```
project.pax/
├── config.toml         Repository configuration and data-format version
├── objects/            Content-addressed, zstd-compressed chunks
│   └── <2-hex>/<62-hex>
├── index/
│   └── index.sqlite3   Rebuildable local cache: files <-> chunks <-> snapshots
├── snapshots/
│   └── <64-hex>.json   Canonical, human-readable snapshot manifest (portable)
└── refs/
    ├── latest           Plain-text hex snapshot id (branch tip)
    └── HEAD              Plain-text hex snapshot id (current checkout)
```

### `config.toml`

```toml
format_version = 1
created_at_unix = 1735000000

[remotes]
origin = "https://example.com/pax"
```

`format_version` is independent of the `pax` binary version. A binary refuses
to operate on a repository whose `format_version` is newer than it supports,
and reports a clear error rather than risking corruption.

### `objects/`

Every object is a single content chunk produced by FastCDC, addressed by the
BLAKE3 hash of its **uncompressed** bytes. Objects are sharded into
subdirectories by the first byte of their hash (2 hex characters), exactly
like Git's loose object store, to keep any one directory small. Each object
file's contents are the chunk bytes compressed with Zstandard. Writes are
atomic: PAX writes to a temporary file in the same shard directory and
renames it into place, so a crash mid-write can never leave a corrupt or
half-written object visible to future operations.

### `index/index.sqlite3`

A rebuildable, transactional cache of:

- `snapshots` — snapshot id, parent id, message, author, timestamp
- `snapshot_files` — which files (path, size, mode, file hash) existed in
  each snapshot
- `chunk_map` — the ordered list of chunks (hash, offset, length) that make
  up any given file hash
- `staged_files` — the working set produced by `pax add`, cleared on commit
- `refs` — named pointers to snapshot ids (`latest`, `HEAD`)

This database is **not** the source of truth for snapshot history — it is a
fast local index. The canonical, portable record of every snapshot is the
JSON manifest under `snapshots/`. If `index.sqlite3` were lost or corrupted,
it can be fully rebuilt by replaying the JSON manifests.

### `snapshots/<id>.json`

Every commit writes a self-describing JSON manifest, e.g.:

```json
{
  "id": "9f2c...",
  "parent": "7ab1...",
  "message": "add character rig",
  "author": "jane",
  "created_at_unix": 1735000000,
  "files": [
    {
      "path": "characters/hero.blend",
      "size": 41943040,
      "mode": 420,
      "file_hash": "1a2b...",
      "chunks": [
        { "chunk_index": 0, "chunk_hash": "aa11...", "offset": 0, "length": 65536 }
      ]
    }
  ]
}
```

This file alone (plus the referenced objects) is enough to reconstruct every
file in the snapshot without any other tooling beyond "BLAKE3 hash + zstd
decompress + concatenate chunks in order" — the specification a future
re-implementation would need.

### `refs/`

Plain UTF-8 text files containing a single hex snapshot id. `latest` is the
tip of history; `HEAD` is the snapshot the working directory currently
reflects (they diverge only after `pax checkout <older-snapshot>`).

## Portable `.pax` container format

`pax pack` bundles an entire `project.pax` directory into one file:

```
[8 bytes]  magic "PAXPACK1"
[4 bytes]  format_version, little-endian u32
[...]      zstd-compressed tar stream of the project.pax directory tree
```

`pax extract` reads this container, reconstructs the latest snapshot's files
as plain ordinary files with no PAX metadata left behind, and discards the
staging copy of the repository. `pax mount` unpacks the container once into
a cache directory and serves it read-only through a FUSE filesystem,
reconstructing file contents on demand from the object store.

## Content addressing

- **Chunking**: FastCDC (2020) with default `min=16 KiB`, `avg=64 KiB`,
  `max=256 KiB`, deterministic for identical input bytes.
- **Chunk hash / object id**: BLAKE3-256 of the uncompressed chunk bytes.
- **File hash**: BLAKE3-256 of the whole, uncompressed file content (used to
  deduplicate identical files across snapshots without re-walking chunks).
- **Snapshot id**: BLAKE3-256 over `(parent id, message, author, timestamp,
  sorted (path, file hash) pairs)`, so identical trees committed with the
  same metadata are naturally content-addressed too.

## Compatibility guarantee

Any tool that can compute BLAKE3 hashes and decompress Zstandard can read a
PAX repository or `.pax` archive without linking against `pax` at all. This
is the concrete mechanism behind the project's "no lock-in" promise.
