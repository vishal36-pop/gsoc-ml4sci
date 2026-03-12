#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Checking predict_tf.cc location, okay ==="
find RecoE2E -name "predict_tf.cc" 2>/dev/null

echo ""
echo "=== Checking for hardcoded afs paths now ==="
grep -rn "afs/cern" RecoE2E/EGTagger/ 2>/dev/null | head -10

echo ""
echo "=== Checking PhysicsTools includes, basically cleanup check ==="
grep -rn "PhysicsTools/ONNXRuntime" RecoE2E/EGTagger/ 2>/dev/null | head -10

echo ""
echo "=== Source files in EGTagger, just listing them ==="
find RecoE2E/EGTagger -name "*.cc" -o -name "*.h" | sort

echo ""
echo "=== Rebuilding now ==="
scram b clean 2>&1 | tail -5
scram b -j4 2>&1 | tail -30
echo ""
echo "BUILD EXIT CODE: $? , okay"
