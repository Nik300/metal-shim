#!/bin/zsh
# TeraScale Metal Shim - Fase 4: installazione di sistema. Da eseguire in Terminal.app (sudo chiede la password).
#   zsh metal-shim/system/install.sh            tutto: kext sulla EFI + bundle + app di controllo
#   zsh metal-shim/system/install.sh --bundle   solo il bundle del driver (aggiornamento, niente riavvio)
#   zsh metal-shim/system/install.sh --kext     solo il kext sulla EFI (vale dal prossimo avvio)
#   zsh metal-shim/system/install.sh --app      solo l'app di controllo e il comando tsmtl
# Cosa scrive (vedi docs/FASE4.md):
#   EFI (del disco di sistema, vedi efi.sh)  EFI/OC/Kexts/TSMetalEnabler.kext + una voce in config.plist -> Kernel -> Add (dopo Lilu e AMFIPass)
#   volume dati    /Library/GPUBundles/TeraScaleMTLDriver.bundle (root:wheel)
#                  /Library/GPUBundles/TeraScaleMTLDriver.config/policy.plist (tuo utente)
#                  /Applications/TeraScale Metal.app, /usr/local/bin/tsmtl
# Il volume di sistema sigillato, le kernel collection e gli snapshot NON vengono toccati.
# Annullare tutto: zsh metal-shim/system/rollback.sh
set -euo pipefail

ROOT=${0:A:h:h}
source $ROOT/system/efi.sh
KEXT=$ROOT/build/TSMetalEnabler.kext
BUNDLE=$ROOT/build/TeraScaleMTLDriver.bundle
APP="$ROOT/build/TeraScale Metal.app"
GPUB=/Library/GPUBundles
CONFIG_DIR=$GPUB/TeraScaleMTLDriver.config
BACKUP=$ROOT/backups/install-$(date +%Y%m%d-%H%M%S)

DO_KEXT=1 DO_BUNDLE=1 DO_APP=1
case ${1:-all} in
  all) ;;
  --bundle) DO_KEXT=0 DO_APP=0 ;;
  --app) DO_KEXT=0 DO_BUNDLE=0 ;;
  --kext) DO_BUNDLE=0 DO_APP=0 ;;
  *) echo "uso: install.sh [--bundle|--app|--kext]"; exit 2 ;;
esac

step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }

[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale (sudo viene chiesto quando serve)"
ME=$(id -un)

step "Controlli preliminari (nessuna scrittura)"
[[ $(uname -r) == 25.* ]] || fail "kernel $(uname -r): il kext è previsto solo per macOS 26 (Darwin 25)"
[[ $(csrutil status) == *"Filesystem Protections: disabled"* ]] \
  || fail "la SIP protegge il filesystem: Metal non accetterebbe un bundle in $GPUB (serve la configurazione SIP di OCLP)"
if (( DO_BUNDLE )); then
  codesign -v "$BUNDLE" || fail "bundle mancante o firma non valida: make -C $ROOT"
  [[ $(lipo -archs "$BUNDLE/Contents/MacOS/TeraScaleMTLDriver") == x86_64 ]] || fail "architettura del bundle inattesa"
fi
if (( DO_KEXT )); then
  codesign -v "$KEXT" || fail "kext mancante o firma non valida: $ROOT/kext/build.sh"
  LOADED=$(kmutil showloaded --list-only 2>/dev/null)   # not piped into grep -q: with pipefail, SIGPIPE would fail the check
  [[ $LOADED == *"as.vit9696.Lilu (1.7."* ]] || fail "Lilu 1.7.x non risulta caricato"
  [[ $LOADED == *"com.dhinakg.AMFIPass"* ]] || fail "AMFIPass non risulta caricato"
  find_oc_efi
fi
if (( DO_APP )); then
  [[ -d "$APP" ]] || fail "app di controllo mancante: $ROOT/gui/build.sh"
fi
echo "ok"

print -P "\nVerranno eseguiti questi passi:"
(( DO_KEXT ))   && echo "  - EFI $EFI_DEV: copia TSMetalEnabler.kext e aggiunge la voce in config.plist (backup in $BACKUP)"
(( DO_BUNDLE )) && echo "  - $GPUB/TeraScaleMTLDriver.bundle (root:wheel) e $CONFIG_DIR (utente $ME)"
(( DO_APP ))    && echo "  - /Applications/TeraScale Metal.app e /usr/local/bin/tsmtl"
read "ANSWER?Procedo? [s/N] "
[[ $ANSWER == [sSyY]* ]] || { echo "annullato"; exit 0 }
mkdir -p "$BACKUP"

if (( DO_KEXT )); then
  step "EFI: kext e config.plist"
  EFI_LINE=$(mount | awk -v d=/dev/$EFI_DEV '$1 == d')   # only the EFI line
  if [[ $EFI_LINE == *read-only* ]]; then sudo diskutil unmount $EFI_DEV; EFI_LINE=; fi
  [[ -n $EFI_LINE ]] || sudo diskutil mount $EFI_DEV
  MP=$(diskutil info $EFI_DEV | awk -F': *' '/Mount Point/{print $2}')
  OC="$MP/EFI/OC"
  [[ -f "$OC/config.plist" && -d "$OC/Kexts/Lilu.kext" ]] || fail "$OC non sembra la cartella di OpenCore"
  cp "$OC/config.plist" "$BACKUP/config.plist"
  [[ -d "$OC/Kexts/TSMetalEnabler.kext" ]] && ditto "$OC/Kexts/TSMetalEnabler.kext" "$BACKUP/TSMetalEnabler.kext.previous"
  # Modifica su una copia, controllo, poi sostituzione.
  cp "$OC/config.plist" "$BACKUP/config.new.plist"
  /usr/bin/python3 -I "$ROOT/system/oc-config.py" add "$BACKUP/config.new.plist"
  plutil -lint "$BACKUP/config.new.plist" >/dev/null || fail "config.plist modificato non valido, EFI non toccata"
  echo "differenze in config.plist:"
  diff <(plutil -p "$BACKUP/config.plist") <(plutil -p "$BACKUP/config.new.plist") || true
  # FAT32: niente proprietari; copia nella cartella nuova e poi scambio.
  sudo rm -rf "$OC/Kexts/TSMetalEnabler.kext.new"
  sudo ditto --norsrc --noextattr "$KEXT" "$OC/Kexts/TSMetalEnabler.kext.new"
  sudo rm -rf "$OC/Kexts/TSMetalEnabler.kext"
  sudo mv "$OC/Kexts/TSMetalEnabler.kext.new" "$OC/Kexts/TSMetalEnabler.kext"
  sudo cp "$BACKUP/config.new.plist" "$OC/config.plist"
  sudo dot_clean -m "$OC/Kexts" 2>/dev/null || true
  sync
  cmp "$KEXT/Contents/MacOS/TSMetalEnabler" "$OC/Kexts/TSMetalEnabler.kext/Contents/MacOS/TSMetalEnabler"
  /usr/bin/python3 -I "$ROOT/system/oc-config.py" show "$OC/config.plist"
  sudo diskutil unmount $EFI_DEV
  echo "ok: il kext sarà caricato al prossimo avvio"
fi

if (( DO_BUNDLE )); then
  step "Bundle del driver in $GPUB"
  [[ -d $GPUB/TeraScaleMTLDriver.bundle ]] && cp -R $GPUB/TeraScaleMTLDriver.bundle "$BACKUP/TeraScaleMTLDriver.bundle.previous"   # cp: ditto would try to copy the "restricted" flag and fail
  sudo rm -rf $GPUB/TeraScaleMTLDriver.bundle.new
  sudo ditto --noextattr "$BUNDLE" $GPUB/TeraScaleMTLDriver.bundle.new
  sudo chown -R root:wheel $GPUB/TeraScaleMTLDriver.bundle.new
  sudo chmod -R go-w $GPUB/TeraScaleMTLDriver.bundle.new
  sudo rm -rf $GPUB/TeraScaleMTLDriver.bundle
  sudo mv $GPUB/TeraScaleMTLDriver.bundle.new $GPUB/TeraScaleMTLDriver.bundle
  codesign -v $GPUB/TeraScaleMTLDriver.bundle
  sudo mkdir -p $CONFIG_DIR
  sudo chown "$ME":staff $CONFIG_DIR
  sudo chmod 755 $CONFIG_DIR
  if [[ ! -f $CONFIG_DIR/policy.plist ]]; then
    plutil -create xml1 $CONFIG_DIR/policy.plist
    plutil -insert Version -integer 1 $CONFIG_DIR/policy.plist
    plutil -insert AutoEnable -bool YES $CONFIG_DIR/policy.plist
    plutil -insert Apps -dictionary $CONFIG_DIR/policy.plist
  fi
  ls -ld $GPUB/TeraScaleMTLDriver.bundle $GPUB/TeraScaleMTLDriver.bundle/Contents/MacOS/TeraScaleMTLDriver $CONFIG_DIR
  echo "ok: vale per le app avviate da adesso (dopo il riavvio, quando il kext è attivo)"
fi

if (( DO_APP )); then
  step "App di controllo"
  rm -rf "/Applications/TeraScale Metal.app"
  ditto "$APP" "/Applications/TeraScale Metal.app" 2>/dev/null || sudo ditto "$APP" "/Applications/TeraScale Metal.app"
  sudo mkdir -p /usr/local/bin
  sudo install -m 755 "$ROOT/gui/tsmtl" /usr/local/bin/tsmtl
  echo "ok: 'tsmtl' apre l'app, 'tsmtl help' elenca i comandi"
fi

step "Fatto"
echo "Backup: $BACKUP"
(( DO_KEXT )) && echo "Riavvia il Mac, poi: tsmtl status"
echo "Per annullare: zsh $ROOT/system/rollback.sh"
