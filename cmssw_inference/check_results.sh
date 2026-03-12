#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Okay, checking the output files ==="
ls -la *.root 2>/dev/null
ls -la *.json 2>/dev/null

echo ""
echo "=== resources.json (FastTimerService), just checking ==="
cat resources.json 2>/dev/null || echo "No resources.json found, so maybe this run did not write it"

echo ""
echo "=== Copy results to /workspace now ==="
cp -f resources.json /workspace/ 2>/dev/null || true
cp -f ntuple.root /workspace/ 2>/dev/null || true
echo "Files copied to /workspace/, okay"
