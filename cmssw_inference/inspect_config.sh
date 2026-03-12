#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Original EGInference_cfg.py from the repo, just checking ==="
cat RecoE2E/EGTagger/python/EGInference_cfg.py.orig 2>/dev/null || git -C RecoE2E show HEAD:EGTagger/python/EGInference_cfg.py 2>/dev/null

echo ""
echo "=========="
echo "=== EGTagger_cfi.py now ==="
cat RecoE2E/EGTagger/python/EGTagger_cfi.py

echo ""
echo "=========="
echo "=== EGFrameProducer_cfi.py now ==="
cat RecoE2E/FrameProducers/python/EGFrameProducer_cfi.py

echo ""
echo "=========="
echo "=== EGInference_cfi.py, basically checking config details ==="
cat RecoE2E/FrameProducers/python/EGInference_cfi.py

echo ""
echo "=========="
echo "=== EGFrameProducer.h now ==="
head -80 RecoE2E/FrameProducers/interface/EGFrameProducer.h

echo ""
echo "=========="
echo "=== EGFrameProducer.cc (first 60 lines), just for a quick look ==="
head -60 RecoE2E/FrameProducers/plugins/EGFrameProducer.cc
