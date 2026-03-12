#!/bin/bash
set -e
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

# Use our local site-local-config.xml, basically no proxy here
export CMS_PATH=/home/cmsusr/CMSSW_12_0_2

echo "==========================================="
echo " Running CMSSW ONNX Inference, okay"
echo "==========================================="
echo "CMSSW_BASE: $CMSSW_BASE"
echo "SCRAM_ARCH: $SCRAM_ARCH"
echo "CMS_PATH: $CMS_PATH"
echo ""

echo "=== Just checking the model file ==="
ls -la RecoE2E/tfModels/sample.onnx
echo ""

echo "=== Just checking the ROOT file ==="
ls -la SIM_DoubleGammaPt50_Pythia8_1000Ev.root
echo ""

echo "=== Running cmsRun with /usr/bin/time now ==="
/usr/bin/time -v cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \
    inputFiles=file:SIM_DoubleGammaPt50_Pythia8_1000Ev.root \
    maxEvents=-1 \
    EGModelName=tfModels/sample.onnx \
    2>&1

echo ""
echo "==========================================="
echo " Inference complete, okay!"
echo "==========================================="
