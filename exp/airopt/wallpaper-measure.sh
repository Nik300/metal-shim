#!/bin/zsh
# measure.sh <tag> [seconds]: opens Settings > Wallpaper and samples the processes involved every 0.5 s.
OUT=$1; DUR=${2:-25}
pat='System Settings|Wallpaper|Neptune|DesktopSettings|VTDecoder|iconservices'
snap() { ps -axo pid=,%cpu=,cputime=,rss=,command= | grep -E "$pat" | grep -v grep | awk '{c=$5; sub(".*/","",c); printf "%s %s %s %s %s\n",$1,$2,$3,$4,c}' }
snap > $OUT.before
t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
for i in {1..$((DUR*2))}; do
  t=$(perl -MTime::HiRes=time -e "printf '%.1f', time-$t0")
  snap | sed "s/^/$t /" >> $OUT.samples
  sleep 0.5
done
snap > $OUT.after
