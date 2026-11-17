# TeraScale Metal Shim

> 🇮🇹 Versione italiana: [README.md](README.md)

Metal driver for AMD TeraScale GPUs (e.g. Turks) on macOS 26 Tahoe with Moraea: apps detect a Metal device and
launch, while commands run on OpenGL 4.1 (and OpenCL 1.2 for compute).

> [!WARNING]
> **OpenCore compatibility:** for now this repo works **only with OpenCore 3.0.0 rc3**.
> Support for **OpenCore 3.0.0 rc5** is in progress.

## Layout

| Folder | Contents |
|---|---|
| `src/` | shim core (device, resources, render, pipelines), AIR → GLSL/OpenCL translator, Compute, Swift, Glass |
| `system/` | system install (Phase 4): driver bundle, kext on the EFI, update and rollback |
| `kext/` | `TSMetalEnabler` kext (Lilu plugin) with the SDKs in `kext/vendor` |
| `gui/` | control app and `tsmtl` command |
| `tests/`, `bench/`, `tools/` | tests, benchmarks and developer tools |
| `docs/` | plans, results and analyses, in Italian (`docs/PIANO.md` is the starting point) |
| `re/`, `exp/` | reverse engineering and experiments |

## Build

```sh
make            # libTSMetal, driver bundle, tests and tools in build/
make test       # base and system tests
make kext       # TSMetalEnabler kext
```

Install: `zsh system/install.sh` (see the script header and `docs/FASE4.md`).
