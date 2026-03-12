#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Full predict_tf.cc, okay ==="
cat RecoE2E/FrameProducers/src/predict_tf.cc

echo ""
echo "=========="
echo "=== predict_tf.h now ==="
cat RecoE2E/FrameProducers/interface/predict_tf.h

echo ""
echo "=========="
echo "=== EGFrameProducer files, just listing them out ==="
find RecoE2E -name "EGFrameProducer*" | sort

echo ""
echo "=========="
echo "=== FrameProducers BuildFile, basically checking dependencies ==="
cat RecoE2E/FrameProducers/plugins/BuildFile.xml 2>/dev/null
echo ""
echo "=== EGTagger BuildFile now ==="
cat RecoE2E/EGTagger/plugins/BuildFile.xml 2>/dev/null

echo ""
echo "=========="
echo "=== Look for the existing config files now ==="
find RecoE2E -name "*cfg*" -o -name "*_cfi*" | grep -i "eg\|inference\|tagger" | sort
