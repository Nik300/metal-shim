#!/bin/zsh
# TeraScale Metal Shim - bundle di shader precompilati (.mslbundle, docs/MSLBUNDLE.md). Niente sudo: la cartella
# /Library/GPUBundles/TeraScaleMTLDriver.config è dell'utente (come policy.plist).
#   zsh metal-shim/system/mslbundle.sh            compila un bundle per ogni app registrata + system.mslbundle
#   zsh metal-shim/system/mslbundle.sh list       app e shader registrati dal driver (niente scritture)
#   zsh metal-shim/system/mslbundle.sh check      i bundle installati valgono per il traduttore attuale?
#   zsh metal-shim/system/mslbundle.sh seed       rigenera i semi di sistema (vetro e blur di CoreAnimation e di
#                                                    RenderBox/SwiftUI) con tools/caglass e tools/rbglass, poi compila
#   zsh metal-shim/system/mslbundle.sh remove     toglie tutti i bundle (il driver torna a tradurre a runtime)
# La compilazione misura anche il costo della compilazione differita del driver per ogni shader (CompileMs in
# Info.plist, gli shader oltre 100 ms vengono elencati con "!") e sopra soglia tiene la modalità del traduttore più
# economica. Alla fine pota la cache GLSL su disco dalle voci dei traduttori precedenti.
# Il driver registra da solo, durante l'uso normale, gli shader che ogni app gli chiede (solo gli input, accanto alla
# cache GLSL dell'app; TSMTL_RECORD=0 lo spegne). Questo script li traduce in anticipo con lo stesso traduttore del
# driver installato, controlla che il driver GL di questa GPU compili ogni risultato e scrive i bundle: all'avvio
# successivo le app trovano gli shader già pronti (niente libLLVM, niente traduzioni, anche nelle sandbox).
# Va rieseguito dopo ogni aggiornamento del driver (update.sh lo fa da solo): un bundle compilato da un altro
# traduttore viene ignorato.
set -euo pipefail

ROOT=${0:A:h:h}
CONFIG=${TSMTL_CONFIG_DIR:-/Library/GPUBundles/TeraScaleMTLDriver.config}
OUT=$CONFIG/mslbundles
INSTALLED=/Library/GPUBundles/TeraScaleMTLDriver.bundle/Contents/MacOS/TeraScaleMTLDriver
TOOL=$ROOT/tools/mslbundle

step() { print -P "\n%B== $*%b" }
fail() { print -P "%F{red}ERRORE:%f $*"; exit 1 }

[[ $EUID -ne 0 ]] || fail "eseguilo come utente normale"
[[ -w $CONFIG ]] || fail "$CONFIG non è scrivibile (installa il driver con system/install.sh)"
make -s -C $ROOT tools/mslbundle tools/caglass tools/rbglass build/libTSMetalInject.dylib >/dev/null || fail "make non riuscito"

# The tool links build/libTSMetal.dylib: its translator must be the installed driver's, or the driver would ignore
# the bundles. The revision (hash of the translator sources) is part of a string in both binaries.
# (grep without -q: it reads all the input, otherwise strings gets SIGPIPE and pipefail turns the match into a failure)
REV=$($TOOL check --out /dev/null 2>/dev/null | sed -n 's/^translator: tsair-3b \([0-9a-f]*\).*/\1/p' || true)
if [[ -f $INSTALLED && -n $REV ]] && ! strings - $INSTALLED | grep -F "tsair-3b $REV" >/dev/null; then
  print -P "%F{yellow}attenzione:%f il driver installato ha un traduttore diverso da quello in build/ ($REV):"
  echo "  i bundle verrebbero ignorati. Installa prima il driver nuovo: zsh $ROOT/system/update.sh"
  [[ ${1:-} == list || ${1:-} == check ]] || exit 1
fi

case ${1:-build} in
  list)  $TOOL list ;;
  check) $TOOL check --out $OUT ;;
  remove)
    step "Rimozione dei bundle in $OUT"
    for b in $OUT/*.mslbundle(N); do echo "  $b"; done
    read "ANSWER?Procedo? [s/N] "
    [[ $ANSWER == [sSyY]* ]] || { echo "annullato"; exit 0 }
    for b in $OUT/*.mslbundle(N); do rm -r -- "$b"; done
    echo "ok: il driver tradurrà di nuovo a runtime (con la sua cache su disco)" ;;
  seed|build)
    if [[ ${1:-build} == seed ]]; then
      step "Semi di sistema: CoreAnimation (tools/caglass) e RenderBox/SwiftUI (tools/rbglass)"
      TMP=$(mktemp -d)
      for scene in all glass sidebar clear; do
        DYLD_INSERT_LIBRARIES=$ROOT/build/libTSMetalInject.dylib TSMTL_RECORD=1 $ROOT/tools/caglass $TMP/$scene.png $scene >/dev/null 2>&1 \
          || echo "  caglass $scene non riuscito"
      done
      DYLD_INSERT_LIBRARIES=$ROOT/build/libTSMetalInject.dylib TSMTL_RECORD=1 RBGLASS_SECONDS=6 $ROOT/tools/rbglass >/dev/null 2>&1 \
        || echo "  rbglass non riuscito"
      rm -r -- "$TMP"
    fi
    step "Shader registrati"
    $TOOL list
    step "Compilazione dei bundle in $OUT"
    $TOOL build --out $OUT || echo "(alcuni shader non sono traducibili: restano al traduttore a runtime, vedi sopra)"
    step "Verifica"
    $TOOL check --out $OUT
    step "Pulizia della cache GLSL (voci dei traduttori precedenti)"
    $TOOL prune || echo "  pulizia non riuscita (innocuo)"
    echo "Le app avviate da ora usano gli shader precompilati (tsmtl stats: mslHits)." ;;
  *) fail "uso: mslbundle.sh [build|list|check|seed|remove]" ;;
esac
