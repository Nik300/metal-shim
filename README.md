# TeraScale Metal Shim

Driver Metal per GPU AMD TeraScale (es. Turks) su macOS 26 Tahoe con Moraea: le app rilevano un device Metal e si
avviano, mentre i comandi vengono eseguiti su OpenGL 4.1 (e OpenCL 1.2 per il compute).

> [!WARNING]
> **Compatibilità OpenCore:** per ora la repo funziona **solo con OpenCore 3.0.0 rc3**.
> Il supporto a **OpenCore 3.0.0 rc5** è in lavorazione.

## Struttura

| Cartella | Contenuto |
|---|---|
| `src/` | core dello shim (device, risorse, render, pipeline), traduttore AIR → GLSL/OpenCL, Compute, Swift, Glass |
| `system/` | installazione di sistema (Fase 4): bundle del driver, kext sulla EFI, aggiornamento e rollback |
| `kext/` | kext `TSMetalEnabler` (plugin Lilu) con gli SDK in `kext/vendor` |
| `gui/` | app di controllo e comando `tsmtl` |
| `tests/`, `bench/`, `tools/` | test, benchmark e strumenti di sviluppo |
| `docs/` | piani, risultati e analisi (`docs/PIANO.md` è il punto di partenza) |
| `re/`, `exp/` | reverse engineering ed esperimenti |

## Build

```sh
make            # libTSMetal, bundle del driver, test e tool in build/
make test       # test di base e di sistema
make kext       # kext TSMetalEnabler
```

Installazione: `zsh system/install.sh` (vedi l'intestazione dello script e `docs/FASE4.md`).
