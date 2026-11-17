#!/bin/zsh
# TeraScale Compute (sezione "Sistema") - aggiornamento del driver e dell'app di controllo con le prove del compute
# prima dell'installazione. Da eseguire in Terminal.app.
#   zsh metal-shim/system/update-compute.sh            controlli (corpus OpenCL, completamento), driver, app + tsmtl se cambiate
#   zsh metal-shim/system/update-compute.sh --revert   driver precedente rimesso (update.sh --revert); la policy del compute resta com'è
# Niente EFI, niente kext, niente riavvio: il compute vive nel driver (bundle). Il driver installato viene salvato in
# backups/install-* prima dello scambio (lo fa install.sh --bundle, via update.sh). Dalla 0.10.0 il compute è acceso
# per tutte le app salvo eccezioni (System.Compute; la vecchia Experimental.Compute viene ancora letta). Misure:
# docs/OTTIMIZZAZIONE-COMPUTE.md, sezione "Stato".
set -euo pipefail

ROOT=${0:A:h:h}
TSMTL="$ROOT/build/TeraScale Metal.app/Contents/MacOS/TeraScaleMetal"
APP_INSTALLED="/Applications/TeraScale Metal.app/Contents/MacOS/TeraScaleMetal"
step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }
[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale (sudo viene chiesto quando serve)"

if [[ ${1:-} == --revert ]]; then
  step "Driver precedente"
  zsh $ROOT/system/update.sh --revert
  echo "La policy del compute non è cambiata. Per spegnerlo ovunque: tsmtl compute off"
  exit 0
fi
[[ $# -eq 0 ]] || fail "uso: update-compute.sh [--revert]"

step "Controlli (nessuna scrittura di sistema)"
[[ -d /Library/GPUBundles/TeraScaleMTLDriver.bundle ]] || fail "shim non installato: per la prima installazione usa system/install.sh"
[[ -f /System/Library/Frameworks/OpenCL.framework/OpenCL ]] || fail "OpenCL.framework assente: il percorso OpenCL non può funzionare"
codesign -v "$ROOT/build/TeraScaleMTLDriver.bundle" || fail "bundle in build/ mancante: make -C $ROOT"
[[ -x "$TSMTL" ]] || fail "app di controllo mancante: $ROOT/gui/build.sh"
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/build/TeraScaleMTLDriver.bundle/Contents/Info.plist")
echo "bundle in build/: $V"
echo "Prova rapida del compute sulla GPU (corpus OpenCL con risultati calcolati in CPU, ~5 s)..."
R=$("$ROOT/build/ctest" 2>/dev/null | tail -1) || true
[[ $R == "ctest: all ok"* ]] || fail "il corpus compute non passa ($R): non installo. Dettagli: $ROOT/build/ctest"
echo "ok: $R"
echo "Completamento dei command buffer con kernel CL (bug della 0.6.0)..."
R=$(TSMTL_STATS=1 "$ROOT/build/dispatchbench" 2>&1 | tail -1) || fail "dispatchbench fallito ($R): non installo"
echo "ok: $R"

step "1/3 Driver $V (sudo; vale per le app avviate da ora; il driver attuale va in backups/)"
zsh $ROOT/system/update.sh

step "2/3 App di controllo e comando tsmtl"
if [[ -x $APP_INSTALLED ]] && cmp -s "$TSMTL" "$APP_INSTALLED"; then
  echo "già aggiornate: niente da fare"
else
  zsh $ROOT/system/install.sh --app
fi

step "3/3 Stato del compute"
STATUS=$(/usr/local/bin/tsmtl compute)
print -r -- "$STATUS"
if [[ $STATUS == *"compute: off per tutte le app"* && $STATUS != *"on  list     com.apple.Maps"* ]]; then
  echo "Il compute è spento ovunque: Mappe ne ha bisogno per i monumenti in 3D e la satellite 3D (senza, il"
  echo "Colosseo esce nero e la satellite 3D rossa). Per riaccenderlo: tsmtl compute on (oppure solo Mappe:"
  echo "tsmtl compute enable /System/Applications/Maps.app)"
fi

step "Fatto: come provarlo"
cat <<EOF
  1. Chiudi Mappe se è aperta e riaprila; vai su un monumento (es. Colosseo), 3D, zoom, poi Satellite in 3D.
  2. Righe del driver:      tsmtl log --filter compute --last 15m
     Attese: "kernel VTMTSComputeFunction runs on OpenCL: ...", dalla seconda volta "binary from the disk cache",
             "OpenCL context released after 30 s without dispatches" quando Mappe resta ferma.
  3. Statistiche dal vivo:  tsmtl stats --watch   (dispatches, cl runs; tsmtl stats --json per clGpuMs e computeSkipped)
  4. Binari CL compilati:   ~/Library/Caches/com.terascale.mtlshim/cl/ (Mappe: ~/Library/Containers/com.apple.Maps/...);
     si possono cancellare, si ricompilano al primo uso.
Per tornare al driver precedente: zsh $ROOT/system/update-compute.sh --revert
EOF
