#!/bin/bash
###############################################################################
# CMSSW ONNX inference setup script, basically the full flow in one place
# Uses the standalone clelange/cmssw:10_6_8_patch1 image
# Manually installs onnxruntime and sets up RecoE2E for inference, just step by step
###############################################################################
set -e

echo "=========================================="
echo "STEP 1: CMSSW Environment, okay"
echo "=========================================="
source /opt/cms/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc820
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
eval $(scramv1 runtime -sh)
echo "CMSSW_10_6_8_patch1 is ready (SCRAM_ARCH=$SCRAM_ARCH), okay"

echo "=========================================="
echo "STEP 2: Install ONNX Runtime 1.1.2, basically"
echo "=========================================="
ONNX_DIR=/home/cmsusr/onnxruntime
if [ ! -d "$ONNX_DIR" ]; then
    cd /home/cmsusr
    curl -L -o onnxruntime.tgz \
        https://github.com/microsoft/onnxruntime/releases/download/v1.1.2/onnxruntime-linux-x64-1.1.2.tgz
    tar xzf onnxruntime.tgz
    mv onnxruntime-linux-x64-1.1.2 onnxruntime
    rm onnxruntime.tgz
    echo "ONNX Runtime installed to $ONNX_DIR, okay"
    ls $ONNX_DIR/include/ $ONNX_DIR/lib/
else
    echo "ONNX Runtime is already installed, so that part is fine"
fi

echo "=========================================="
echo "STEP 3: Register onnxruntime as a SCRAM tool"
echo "=========================================="
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
cat > onnxruntime.xml << TOOLEOF
<tool name="onnxruntime" version="1.1.2">
  <info url="https://github.com/microsoft/onnxruntime"/>
  <lib name="onnxruntime"/>
  <client>
    <environment name="ONNXRUNTIME_BASE" default="/home/cmsusr/onnxruntime"/>
    <environment name="INCLUDE" default="\$ONNXRUNTIME_BASE/include"/>
    <environment name="LIBDIR" default="\$ONNXRUNTIME_BASE/lib"/>
  </client>
</tool>
TOOLEOF
scram setup onnxruntime.xml
rm onnxruntime.xml
echo "onnxruntime registered as a SCRAM tool, just checking the details now:"
scram tool info onnxruntime 2>&1 | head -8

echo "=========================================="
echo "STEP 4: Clone RecoE2E, okay"  
echo "=========================================="
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
if [ ! -d "RecoE2E" ]; then
    git clone https://github.com/rchudasa/RecoE2E.git
    echo "RecoE2E cloned, basically done"
else
    echo "RecoE2E is already present, so no issue there"
fi

echo "=========================================="
echo "STEP 5: Fix code for ONNX Runtime 1.1.2, just making it compatible"
echo "=========================================="
cd /home/cmsusr/CMSSW_10_6_8_patch1/src

# 5a. Fix predict_tf.cc, basically use the direct ONNX Runtime header
sed -i 's|#include "PhysicsTools/ONNXRuntime/interface/ONNXRuntime.h"|#include <onnxruntime_cxx_api.h>|' \
    RecoE2E/FrameProducers/src/predict_tf.cc

# 5b. Remove the unused cms::Ort wrapper, since it does not exist in this setup
sed -i '/std::unique_ptr<cms::Ort::ONNXRuntime> model;/d' \
    RecoE2E/FrameProducers/src/predict_tf.cc

# 5c. Remove GetAvailableProviders, because it is not there in this ONNX RT version  
sed -i '/auto providers = Ort::GetAvailableProviders();/d' \
    RecoE2E/FrameProducers/src/predict_tf.cc

# 5d. Fix the hardcoded model path, just to make it portable
sed -i 's|/afs/cern.ch/work/r/rchudasa/private/inference/CMSSW_12_0_2/src/RecoE2E/|RecoE2E/|' \
    RecoE2E/FrameProducers/src/predict_tf.cc

# 5e. Remove broken files that reference PhysicsTools/ONNXRuntime, basically cleanup
rm -f RecoE2E/FrameProducers/plugins/ONNXRuntime.cc
rm -f RecoE2E/FrameProducers/interface/ONNXRuntime.h
rm -f RecoE2E/FrameProducers/src/predict_onxx.cc

echo "Code fixes applied, okay"

echo "=========================================="
echo "STEP 6: Build, basically"
echo "=========================================="
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
scram b -j4 2>&1
echo "BUILD COMPLETE, looks okay"

echo "=========================================="
echo "STEP 7: Write the inference config"
echo "=========================================="
cat > RecoE2E/EGTagger/python/EGInference_cfg.py << 'PYEOF'
import FWCore.ParameterSet.Config as cms
import FWCore.ParameterSet.VarParsing as VarParsing

options = VarParsing.VarParsing('analysis')
options.register('processMode', default='JetLevel',
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.string, info="process mode")
options.register('doEBenergy', default=False,
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.bool, info="set doEBenergy")
options.register('skipEvents', default=0,
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.int, info="skipEvents")
options.register('EGModelName', default='sample.onnx',
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.string, info="ONNX model name")
options.parseArguments()

process = cms.Process("EGClassifier")
process.load("FWCore.MessageService.MessageLogger_cfi")
process.load("Configuration.StandardSequences.GeometryDB_cff")
process.load("Configuration.StandardSequences.FrontierConditions_GlobalTag_cff")
process.load("Configuration.StandardSequences.GeometryRecoDB_cff")
process.load("Configuration.StandardSequences.MagneticField_38T_cff")
process.GlobalTag.globaltag = cms.string('106X_upgrade2018_realistic_v11')
process.es_prefer_GlobalTag = cms.ESPrefer('PoolDBESSource','GlobalTag')

process.maxEvents = cms.untracked.PSet(input=cms.untracked.int32(options.maxEvents))
process.source = cms.Source("PoolSource",
    fileNames=cms.untracked.vstring(options.inputFiles),
    skipEvents=cms.untracked.uint32(options.skipEvents))
print(" >> Loaded", len(options.inputFiles), "input files from list.")

process.load("RecoE2E.FrameProducers.DetFrameProducer_cfi")
process.load("RecoE2E.FrameProducers.EGFrameProducer_cfi")
process.load("RecoE2E.EGTagger.EGTagger_cfi")
process.DetFrames.setChannelOrder = "1"
process.EGTagger.EGModelName = cms.string('tfModels/' + options.EGModelName)

process.out = cms.OutputModule("PoolOutputModule",
    fileName=cms.untracked.string('EGFrames_output.root'))
process.TFileService = cms.Service("TFileService", fileName=cms.string("ntuple.root"))

process.p = cms.Path(process.DetFrames + process.EGFrames + process.EGTagger)
process.ep = cms.EndPath(process.out)

process.Timing = cms.Service("Timing",
    summaryOnly=cms.untracked.bool(False), useJobReport=cms.untracked.bool(True))
process.SimpleMemoryCheck = cms.Service("SimpleMemoryCheck",
    ignoreTotal=cms.untracked.int32(1))
PYEOF
echo "Config written, basically done"

echo "=========================================="
echo "STEP 8: Copy data files and run inference"
echo "=========================================="
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
cp /workspace/SIM_DoubleGammaPt50_Pythia8_1000Ev.root .
cp /workspace/sample.onnx RecoE2E/tfModels/sample.onnx 2>/dev/null || true
mkdir -p RecoE2E/tfModels
cp /workspace/sample.onnx RecoE2E/tfModels/sample.onnx

echo "Running cmsRun now, okay..."
date
/usr/bin/time -v cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \
    inputFiles=file:SIM_DoubleGammaPt50_Pythia8_1000Ev.root \
    maxEvents=-1 \
    EGModelName=sample.onnx 2>&1
EXITCODE=$?
date
echo "=========================================="
echo "cmsRun EXIT CODE: $EXITCODE, just for reference"
echo "=========================================="
