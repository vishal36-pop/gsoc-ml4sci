#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Checking EGTagger.cc to understand the config params, okay ==="
head -60 RecoE2E/EGTagger/plugins/EGTagger.cc

echo ""
echo "=========="
echo "=== Checking EGTagger.h now ==="
cat RecoE2E/EGTagger/interface/EGTagger.h

echo ""
echo "=========="
echo "=== Checking predict_tf.cc, basically the main inference bit ==="
head -80 RecoE2E/FrameProducers/src/predict_tf.cc

echo ""
echo "=========="
echo "=== Checking EGInference_cfg.py (if the original exists) ==="
if [ -f RecoE2E/EGTagger/python/EGInference_cfg.py ]; then
    cat RecoE2E/EGTagger/python/EGInference_cfg.py
else
    echo "Not found, so we will create it only."
fi
