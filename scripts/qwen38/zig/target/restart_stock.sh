#!/usr/bin/env bash
# restart_stock.sh - stop any running evaluation runner cleanly and start stages 1 and 2 on the pristine binary.
# A separate file so no kill pattern can match the shell that issues it.
pkill -f "buildup[.]sh"
pkill -f "patcheval[.]sh"
sleep 3
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
rm -f ~/.local/state/qwen38-flash-next-tf/start.lock ~/work/target/BUILDUP1-DONE ~/work/target/BUILDUP2-DONE
rm -rf ~/work/target/bench/pe-s1* ~/work/target/bench/pe-s2*
cd ~/work/target || exit 1
setsid nohup bash -c "bash ./buildup.sh 1; bash ./buildup.sh 2" > buildup.outer.log 2>&1 < /dev/null &
sleep 2
echo "relaunched $(date -Is); context line: $(grep -c 'CONTEXT=131072' buildup.sh)"
