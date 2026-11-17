#!/bin/zsh
# run cdp.py with a hard 15 s limit
python3 -I "${0:A:h}/cdp.py" "$@" & pid=$!
for i in {1..30}; do kill -0 $pid 2>/dev/null || { wait $pid; exit $?; }; sleep 0.5; done
kill $pid; echo "TIMEOUT"
