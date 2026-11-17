#!/bin/zsh
# TeraScale Metal Shim - annulla la Fase 4. Da eseguire in Terminal.app.
#   zsh metal-shim/system/rollback.sh          toglie kext (EFI) e bundle: al riavvio Metal torna a 0 device
#   zsh metal-shim/system/rollback.sh --all    toglie anche policy, app di controllo e comando tsmtl
# Già senza riavvio: tolto il bundle, le app avviate da quel momento non vedono più il device (il kext
# resta caricato fino al riavvio, ma da solo non fa nulla: Metal non trova il bundle e va avanti come oggi).
# Se il Mac non si avviasse dopo l'installazione: all'accensione tieni premuto Option, scegli la EFI della
# chiavetta OCLP (non ha TSMetalEnabler), avvia macOS e lancia questo script.
set -euo pipefail

ROOT=${0:A:h:h}
source $ROOT/system/efi.sh
GPUB=/Library/GPUBundles
BACKUP=$ROOT/backups/rollback-$(date +%Y%m%d-%H%M%S)
ALL=0; [[ ${1:-} == --all ]] && ALL=1

step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }
[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale"
find_oc_efi

echo "Verranno rimossi: TSMetalEnabler.kext e la sua voce in config.plist (EFI $EFI_DEV), $GPUB/TeraScaleMTLDriver.bundle"
(( ALL )) && echo "e inoltre: $GPUB/TeraScaleMTLDriver.config, /Applications/TeraScale Metal.app, /usr/local/bin/tsmtl"
read "ANSWER?Procedo? [s/N] "
[[ $ANSWER == [sSyY]* ]] || { echo "annullato"; exit 0 }
mkdir -p "$BACKUP"

step "EFI"
EFI_LINE=$(mount | awk -v d=/dev/$EFI_DEV '$1 == d')   # only the EFI line
if [[ $EFI_LINE == *read-only* ]]; then sudo diskutil unmount $EFI_DEV; EFI_LINE=; fi
[[ -n $EFI_LINE ]] || sudo diskutil mount $EFI_DEV
MP=$(diskutil info $EFI_DEV | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"
[[ -f "$OC/config.plist" ]] || fail "$OC/config.plist non trovato"
cp "$OC/config.plist" "$BACKUP/config.plist"
cp "$OC/config.plist" "$BACKUP/config.new.plist"
/usr/bin/python3 -I "$ROOT/system/oc-config.py" remove "$BACKUP/config.new.plist"
plutil -lint "$BACKUP/config.new.plist" >/dev/null || fail "config.plist modificato non valido, EFI non toccata"
diff <(plutil -p "$BACKUP/config.plist") <(plutil -p "$BACKUP/config.new.plist") || true
sudo cp "$BACKUP/config.new.plist" "$OC/config.plist"
if [[ -d "$OC/Kexts/TSMetalEnabler.kext" ]]; then
  ditto "$OC/Kexts/TSMetalEnabler.kext" "$BACKUP/TSMetalEnabler.kext"
  sudo rm -rf "$OC/Kexts/TSMetalEnabler.kext"
fi
sync
sudo diskutil unmount $EFI_DEV
echo "ok"

step "Bundle"
if [[ -d $GPUB/TeraScaleMTLDriver.bundle ]]; then
  cp -R $GPUB/TeraScaleMTLDriver.bundle "$BACKUP/TeraScaleMTLDriver.bundle"   # cp: ditto would try to copy the "restricted" flag and fail
  sudo rm -rf $GPUB/TeraScaleMTLDriver.bundle
fi
echo "ok"

if (( ALL )); then
  step "Policy, app di controllo, tsmtl"
  if [[ -d $GPUB/TeraScaleMTLDriver.config ]]; then
    cp -R $GPUB/TeraScaleMTLDriver.config "$BACKUP/TeraScaleMTLDriver.config"   # cp: ditto would try to copy the "restricted" flag and fail
    sudo rm -rf $GPUB/TeraScaleMTLDriver.config
  fi
  sudo rm -rf "/Applications/TeraScale Metal.app" /usr/local/bin/tsmtl
  echo "ok"
fi

step "Fatto"
echo "Copie di quanto rimosso: $BACKUP"
echo "Riavvia per scaricare il kext."
