#!/bin/zsh
# TeraScale Metal Shim - aggiornamento del solo driver (bundle). Da eseguire in Terminal.app (sudo chiede la password).
#   zsh metal-shim/system/update.sh            confronta installato e build/, poi installa il bundle nuovo
#   zsh metal-shim/system/update.sh --revert   rimette il bundle salvato dall'ultimo aggiornamento/installazione
# L'installazione vera la fa install.sh --bundle (backup del bundle precedente in backups/install-*, copia
# root:wheel, scambio, verifica della firma). EFI, kext e volume di sistema NON vengono toccati, niente riavvio:
# il driver nuovo vale per le app avviate da quel momento (Chrome va chiuso e riaperto).
set -euo pipefail

ROOT=${0:A:h:h}
GPUB=/Library/GPUBundles
INSTALLED=$GPUB/TeraScaleMTLDriver.bundle
BUILT=$ROOT/build/TeraScaleMTLDriver.bundle
BIN=Contents/MacOS/TeraScaleMTLDriver

step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }
version() { [[ -f $1/Contents/Info.plist ]] || { echo "assente"; return }
  echo "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $1/Contents/Info.plist) (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $1/Contents/Info.plist))" }
users() {   # processi che hanno il driver installato caricato: lo tengono finché non vengono riavviati
  lsof -Fpc "$INSTALLED/$BIN" 2>/dev/null | awk '/^p/{p=substr($0,2)} /^c/{print "    " substr($0,2) " (pid " p ")"}' | sort -u || true }

[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale (sudo viene chiesto quando serve)"

if [[ ${1:-} == --revert ]]; then
  PREV=$(ls -d $ROOT/backups/install-*/TeraScaleMTLDriver.bundle.previous 2>/dev/null | tail -1)
  [[ -n $PREV ]] || fail "nessun bundle precedente in $ROOT/backups/install-*"
  step "Ripristino del driver precedente"
  echo "installato:  $(version $INSTALLED)"
  echo "ripristino:  $(version $PREV)   da $PREV"
  codesign -v "$PREV" || fail "il bundle salvato non ha una firma valida"
  read "ANSWER?Procedo? [s/N] "
  [[ $ANSWER == [sSyY]* ]] || { echo "annullato"; exit 0 }
  SAVE=$ROOT/backups/revert-$(date +%Y%m%d-%H%M%S)
  mkdir -p $SAVE
  cp -R $INSTALLED $SAVE/TeraScaleMTLDriver.bundle.replaced   # cp: ditto would try to copy the "restricted" flag and fail
  sudo rm -rf $INSTALLED.new
  sudo ditto --noextattr "$PREV" $INSTALLED.new
  sudo chown -R root:wheel $INSTALLED.new
  sudo chmod -R go-w $INSTALLED.new
  sudo rm -rf $INSTALLED
  sudo mv $INSTALLED.new $INSTALLED
  codesign -v $INSTALLED
  echo "ok: installato $(version $INSTALLED); quello tolto è in $SAVE"
  echo "Chiudi e riapri le app che usano il driver (Chrome compreso)."
  exit 0
fi
[[ $# -eq 0 ]] || fail "uso: update.sh [--revert]"

step "Controlli (nessuna scrittura)"
[[ -d $INSTALLED ]] || fail "nessun driver installato: per la prima installazione usa system/install.sh"
codesign -v "$BUILT" || fail "bundle in build/ mancante o firma non valida: make -C $ROOT"
STALE=$(find $ROOT/src $ROOT/system/TeraScaleMTLDriver-Info.plist -type f -newer "$BUILT/$BIN" | head -3)
[[ -z $STALE ]] || fail "il bundle in build/ è più vecchio dei sorgenti ($STALE): make -C $ROOT && make -C $ROOT test"
if cmp -s "$INSTALLED/$BIN" "$BUILT/$BIN"; then echo "il driver installato è già identico a quello in build/: niente da fare"; exit 0; fi
echo "installato:  $(version $INSTALLED)"
echo "nuovo:       $(version $BUILT)"
echo "Novità della 0.11.0 (docs/OTTIMIZZAZIONE-AIR.md §9): pipeline più rapide da creare e passate più leggere."
echo "  - i campi delle struct lette da buffer si leggono 16 byte alla volta: compilazione del driver 2,9× più corta"
echo "    sugli shader registrati; in Chrome attesa delle pipeline 18,8 -> 5-8 s per caricamento, warm-up 6,6 -> 1,5-2 s"
echo "  - ogni pipeline collega subito la variante che ha disegnato l'ultima volta (Chrome: 28 -> 19 programmi)"
echo "  - framebuffer e vertex array riusati tra le passate, half letti da buffer constant più veloci (-37%),"
echo "    mslbundle.sh misura il costo di ogni shader, sceglie la traduzione più economica e pota la cache"
echo "Novità della 0.10.0 (docs/PIANO-COMPUTE.md): TeraScale Compute esce dalla sperimentazione (sezione Sistema dell'app)."
echo "  Acceso per tutte le app salvo eccezioni anche senza policy; chiave System.Compute (Experimental.Compute ancora letta,"
echo "  quindi le tue impostazioni restano). Spegnerlo: tsmtl compute off, o per un'app: tsmtl compute disable <app>."
echo "  Contiene anche la correzione per Chrome (helper GPU) e le varianti bleed del vetro."
echo "Novità della 0.9.0 (docs/PIANO-GLASS.md): TeraScale Glass, il vetro di Apple dentro il compositore di WindowServer"
echo "  (Moraea). Resta SPENTO finché non lo accendi: zsh $ROOT/system/glass.sh prepare, kext 1.2 (glass.sh kext), poi"
echo "  tsmtl glass trial o la sezione Sistema dell'app. Senza System.Glass il driver non entra in WindowServer, come prima."
echo "  Con System.Glass acceso anche le barre laterali delle app (Impostazioni, Note, Finder) mostrano il desktop sfocato"
echo "  dietro la finestra: vale per le app aperte dopo l'aggiornamento."
echo "Novità della 0.8.0 (docs/MSLBUNDLE.md, docs/PIANO.md): vetro Liquid Glass e shader precompilati"
echo "  - vetro di SwiftUI/RenderBox (Spotlight): funzioni visibili collegate alla pipeline, memoria privata reinterpretata,"
echo "    offset di texel dinamici, barriera sulle texture lette dal proprio render target (niente più quadretti 8x8)"
echo "  - vetro nativo di CoreAnimation (glass_background/sdf/simple_rim/variable_blur): tradotto al 100%"
echo "  - .mslbundle: il driver registra gli shader usati da ogni app; dopo l'installazione vengono precompilati in"
echo "    /Library/GPUBundles/TeraScaleMTLDriver.config/mslbundles (zsh $ROOT/system/mslbundle.sh, senza sudo)"
echo "Nota: la cache delle traduzioni degli shader si rigenera, le prime pagine dopo l'aggiornamento sono un po' più lente."
U=$(users)
if [[ -n $U ]]; then
  echo "Queste app usano il driver attuale e lo terranno finché non le riavvii (per Chrome basta chiuderlo e"
  echo "riaprirlo; per avere il driver nuovo ovunque, anche in Finder/Dock/loginwindow, serve logout o riavvio):"
  echo "$U"
fi

zsh $ROOT/system/install.sh --bundle

step "Verifica"
if cmp -s "$INSTALLED/$BIN" "$BUILT/$BIN"; then
  codesign -v $INSTALLED && echo "ok: installato $(version $INSTALLED)"
  # Precompiled shaders: bundles built by the previous translator are ignored, rebuild them for this one.
  zsh $ROOT/system/mslbundle.sh seed || echo "bundle di shader non aggiornati: zsh $ROOT/system/mslbundle.sh"
  echo "Chiudi e riapri Chrome (e le altre app che usano Metal), poi: tsmtl status"
  echo "Per tornare alla versione precedente: zsh $ROOT/system/update.sh --revert"
else
  echo "driver non sostituito (aggiornamento annullato?): installato $(version $INSTALLED)"
fi
