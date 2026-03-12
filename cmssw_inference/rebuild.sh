#!/bin/bash
set -e
source /opt/cms/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc820
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
eval $(scramv1 runtime -sh)
echo "=== Okay, rebuilding now ==="
scram b -j4 2>&1
echo "=== BUILD EXIT CODE: $? , just check once ==="
