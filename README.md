<div align="center">

# 📦 PAX

**Version anything. Store everything.**

[![License](https://img.shields.io/badge/license-see%20repo-blue.svg)](#)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)](#install)
[![Status](https://img.shields.io/badge/status-pre--release-orange.svg)](#status)

</div>

PAX is a universal, content-addressed archive and versioning system for
projects of any size, with first-class support for large binary files (game
assets, 3D models, video, audio, datasets, CAD files). It combines Git-like
snapshots, ZIP-like portable archiving, chunk-level deduplication, a
read-only virtual mount, and a push/pull remote model that never requires
opening a network port.

>PAX stays usable without PAX. `pax extract` always
> produces plain, ordinary files with zero lock-in, and the on-disk format is
> fully documented in [docs/FORMAT.md](docs/FORMAT.md).

---

## 🚀 Install


### macOS / Linux

```sh
curl -fsSL https://raw.githubusercontent.com/SH-ENTERTAINMENT/pax/main/InstallScripts/install.sh | sudo sh
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/SH-ENTERTAINMENT/pax/main/InstallScripts/install.ps1 | iex
```

Both installers respect the `PAX_INSTALL_DIR` environment variable if you
want to install somewhere other than the default per-user location.


---

## ⚡ Quickstart

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


## 🗂️ Project layout

```
Pax/                     Cargo workspace (pax-cli, pax-core, pax-chunking, ...)
InstallScripts/          Universal install scripts (install.sh, install.ps1)
docs/                    Format spec, architecture overview, CLI reference
```

---
