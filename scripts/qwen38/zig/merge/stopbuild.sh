#!/usr/bin/env bash
# stopbuild.sh: the three stop-rule candidates each on top of zmerge3's tree (~/work/merge/tf HEAD), one image each.
set -uo pipefail
cd ~/work/merge || exit 1
for c in fable:~/work/lanes/w6-fable/ots0105-propose-floor.patch opus:~/work/lanes/w6-opus/w6d.patch \
         glm:~/work/lanes/prose-glm/zprose-glm-chainstop3.patch; do
  n=${c%%:*}; p=${c#*:}; p=${p/#\~/$HOME}
  rm -rf "st-$n"; git clone -q tf "st-$n" && cd "st-$n" || exit 1
  echo "== $n: $p"
  git apply --3way "$p" 2>&1 | grep -v cleanly | tail -4
  if git diff --name-only --diff-filter=U | grep -q .; then echo "CONFLICT $n"; git diff --name-only --diff-filter=U; cd ..; continue; fi
  git diff HEAD > "../stop-$n.patch"
  cd .. && ./build.sh "zstop-$n" ~/work/zbuild/ots0101-argmax-lse-wide.patch ~/work/zbuild/ots0102-mtp-fp8.patch \
    ~/work/merge/merged3.patch ~/work/merge/stop-$n.patch </dev/null 2>&1 | grep -a "BUILT\|error:" | head -3
done
