#!/bin/zsh
# Raccoglie in un solo archivio quello che serve per capire un crash di WindowServer / del driver.
#   zsh tools/collect-logs.sh [minuti]     (predefinito 60: quanto log di sistema includere)
# Output: logs-<data>.tgz nella cartella metal-shim (sulla chiavetta, se è lì). Niente sudo, niente scritture
# fuori da quella cartella. Contiene percorsi e nomi di app di questo Mac, nessuna password.
set -uo pipefail
ROOT=${0:A:h:h}
MIN=${1:-60}
NAME=logs-$(date +%Y%m%d-%H%M%S)
OUT=$ROOT/$NAME
mkdir -p $OUT/reports
TSMTL=$(command -v tsmtl || echo $ROOT/gui/tsmtl)
CONFIG=/Library/GPUBundles/TeraScaleMTLDriver.config
run() { local f=$1; shift; print -r -- "\$ $*" >> $OUT/$f; "$@" >> $OUT/$f 2>&1; print >> $OUT/$f }

echo "sistema"
run system.txt sw_vers
run system.txt uname -a
run system.txt nvram boot-args
run system.txt csrutil status
run system.txt sh -c 'kmutil showloaded --list-only 2>/dev/null | grep -iE "lilu|amfipass|tsmetal|terascale|radeon|amd|atheros|ElCap"'
run system.txt ls -la /Library/GPUBundles $CONFIG $CONFIG/glass /var/tmp/TeraScaleGlass
run system.txt codesign -dv --verbose=2 /Library/GPUBundles/TeraScaleMTLDriver.bundle

echo "tsmtl"
run tsmtl.txt $TSMTL version
run tsmtl.txt $TSMTL status
run tsmtl.txt $TSMTL glass status
run tsmtl.txt $TSMTL apps
run tsmtl.txt $TSMTL log --last ${MIN}m
cp $CONFIG/policy.plist $OUT/ 2>/dev/null
cp /var/tmp/TeraScaleGlass/status.plist $OUT/glass-status.plist 2>/dev/null
cp /var/tmp/TeraScaleGlass/starts $OUT/glass-starts 2>/dev/null

echo "crash report (ultimi 3 giorni)"
for d in /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports; do
  find $d -maxdepth 2 -type f -mtime -3 \( -iname 'WindowServer*' -o -iname '*panic*' -o -iname 'TeraScale*' \
       -o -iname 'tsmtl*' -o -iname '*glassgen*' -o -iname 'loginwindow*' \) 2>/dev/null | while read -r f; do cp "$f" $OUT/reports/; done
done
run reports.txt ls -lt $OUT/reports

echo "log di sistema degli ultimi $MIN minuti (WindowServer, driver) - può metterci un minuto"
/usr/bin/log show --last ${MIN}m --style compact \
  --predicate 'process == "WindowServer" OR subsystem == "com.terascale.mtlshim" OR eventMessage CONTAINS[c] "TeraScale" OR eventMessage CONTAINS[c] "GPUBundles"' \
  2>&1 | tail -n 20000 > $OUT/syslog.txt

tar czf $ROOT/$NAME.tgz -C $ROOT $NAME && rm -rf $OUT
echo "fatto: $ROOT/$NAME.tgz ($(du -h $ROOT/$NAME.tgz | cut -f1))"
