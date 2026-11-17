# TeraScale Metal.app + `tsmtl`

Control app for the TeraScale Metal shim (Phase 4). One executable, two modes:
GUI (SwiftUI, Italian UI) and CLI (`tsmtl <command>`). Interfaces: `docs/FASE4-INTERFACCE.md`.

## Build
    gui/build.sh            # release; CONFIG=debug gui/build.sh for -Onone -g
Output: `build/TeraScale Metal.app` (ad-hoc signed, id `com.terascale.mtlshim.monitor`) and
`build/tsmtl-fake-emitter`. Only Command Line Tools are needed (swiftc + clang). If
`gui/logo/AppIcon.icns` / `gui/logo/logo-1024.png` exist they are copied into the bundle.

## Install (done by the Phase 4 install script, not by build.sh)
    cp -R "build/TeraScale Metal.app" /Applications/
    install -m 755 gui/tsmtl /usr/local/bin/tsmtl
The wrapper looks for the app in `/Applications` first, then in `build/` next to the script (when run from the metal-shim folder).

## CLI
    tsmtl                         open the app (tsmtl gui [--section gpu|log|apps|status])
    tsmtl status [--json]
    tsmtl stats [--json] [--watch [s]] [--count n]
    tsmtl log [-f] [--last 1h] [--filter unimplemented,error,warning,general] [--app name|id] [--json]
    tsmtl apps [--json] [--last 1d]
    tsmtl enable|disable|reset|remove <bundle id | path.app | proc:name>
    tsmtl auto on|off
`TSMTL_CONFIG_DIR=<dir>` replaces `/Library/GPUBundles/TeraScaleMTLDriver.config` (GUI too:
`TSMTL_CONFIG_DIR=… tsmtl gui` passes it through `open --env`).

## Notes
- GPU statistics come from `PerformanceStatisticsAccum` of `AMDTurksGraphicsAccelerator`, not from
  `PerformanceStatistics`: the latter is reset by every read (any process), the Accum dictionary is not.
- "Device Utilization %" is shown only as a secondary value: it reads 100 with the GPU almost idle.
  The load figure is `hardwareWaitTime` delta / elapsed time (checked against a synthetic GL load at
  5/20/50/100 % duty: 7-12 / 20-28 / 46-58 / 100 %).
- The stats lease (Darwin notify `com.terascale.mtlshim.stats`) is held while the GPU section is on
  screen and while `tsmtl stats` runs: state = Unix time + `notify_post` every 2 s; state 0 + post at the end.
- `general` (info level) lines appear in the history only when the unified log kept them; the live
  stream always shows them.
- Testing without installing: `build/tsmtl-fake-emitter --id com.example.App --name App --seconds 30`
  logs every category and follows the stats lease exactly like the bundle.
- Hidden GUI launch arguments: `--section gpu|log|apps|status`, `--appearance light|dark`.
