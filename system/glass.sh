#!/bin/zsh
# TeraScale Glass (docs/PIANO-GLASS.md): il vetro di Apple dentro il compositore OpenGL di Moraea in WindowServer.
# Da eseguire in Terminal.app come utente normale (sudo viene chiesto solo per il kext).
#   zsh metal-shim/system/glass.sh prepare   genera glass.glsl dagli shader di QuartzCore (tools/glassgen) e la
#                                              cartella di stato /var/tmp/TeraScaleGlass; nessun effetto su WindowServer
#   zsh metal-shim/system/glass.sh kext      installa il kext 1.2 sulla EFI (serve per caricare il driver in
#                                              WindowServer; vale dal prossimo avvio)
#   zsh metal-shim/system/glass.sh trial [minuti]   acceso fino alla scadenza (predefinito 15), poi torna da solo
#                                              al vetro di Moraea se non confermi con: tsmtl glass confirm
#   zsh metal-shim/system/glass.sh off       spento subito (file interruttore) e nella policy
# Accensione definitiva, stato e spegnimento anche da tsmtl glass on|off|status o dalla sezione Sistema dell'app.
# Reti di sicurezza: file interruttore /var/tmp/TeraScaleGlass/DISABLE (spegne senza riavvio, anche via SSH),
# guardia sui crash (3 avvii di WindowServer in 2 minuti -> spento), scadenza della prova, ritorno a Moraea se lo
# shader non compila. Il driver in WindowServer fa solo questo: nessun device Metal, nessuna altra funzione.
set -euo pipefail
ROOT=${0:A:h:h}
CONFIG=/Library/GPUBundles/TeraScaleMTLDriver.config
STATE=/var/tmp/TeraScaleGlass
step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }
[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale"
TSMTL=$ROOT/gui/tsmtl
[[ -x $TSMTL ]] || TSMTL=tsmtl

prepare() {
  step "Shader di Apple per Moraea (tools/glassgen)"
  [[ -d $CONFIG && -w $CONFIG ]] || fail "$CONFIG mancante o non scrivibile: installa prima il driver (system/install.sh)"
  make -C $ROOT build/libTSMetal.dylib tools/glassgen >/dev/null
  $ROOT/tools/glassgen -o $CONFIG/glass
  mkdir -p $STATE && chmod 0777 $STATE
  echo "ok: $CONFIG/glass/glass.glsl, stato in $STATE"
}

case ${1:-} in
  prepare) prepare ;;
  kext)
    zsh $ROOT/system/install.sh --kext ;;
  trial)
    MIN=${2:-15}
    [[ -f $CONFIG/glass/glass.glsl ]] || prepare
    rm -f $STATE/DISABLE $STATE/starts 2>/dev/null || true
    $TSMTL glass trial $MIN
    echo "Ora riavvia il Mac: WindowServer carica il componente solo al suo avvio, e il logout non lo riavvia."
    echo "Se qualcosa va storto: niente da fare, dopo $MIN minuti torna il vetro di Moraea; via SSH: touch $STATE/DISABLE" ;;
  off)
    mkdir -p $STATE 2>/dev/null || true
    touch $STATE/DISABLE
    $TSMTL glass off ;;
  *) echo "uso: glass.sh prepare|kext|trial [minuti]|off"; exit 2 ;;
esac
