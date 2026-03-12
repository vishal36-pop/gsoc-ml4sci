#!/bin/bash
set -e
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc820
cd /home/cmsusr/CMSSW_11_0_1/src
eval $(/cvmfs/cms.cern.ch/common/scramv1 runtime -sh)
echo "CMSSW_BASE=$CMSSW_BASE"

# Remove the bad PhysicsTools/ONNXRuntime download attempt, basically cleaning up first
rm -rf PhysicsTools/ONNXRuntime

# Step 1: Fix predict_tf.cc, just replace the CMS wrapper with direct ONNX Runtime include
echo "=== Okay, fixing predict_tf.cc now ==="
PREDICT_TF="/home/cmsusr/CMSSW_11_0_1/src/RecoE2E/FrameProducers/src/predict_tf.cc"
sed -i 's|#include "PhysicsTools/ONNXRuntime/interface/ONNXRuntime.h"|#include <onnxruntime/core/session/onnxruntime_cxx_api.h>|' "$PREDICT_TF"
# Fix the hardcoded model path so it uses the passed-in model_filename only
sed -i 's|std::string modelFilepath ="/afs/cern.ch/work/r/rchudasa/private/inference/CMSSW_12_0_2/src/RecoE2E/tfModels/sample.onnx";|std::string modelFilepath = "RecoE2E/" + model_filename;|' "$PREDICT_TF"
head -3 "$PREDICT_TF"

# Step 2: Update FrameProducers BuildFile.xml to add the onnxruntime dependency
echo "=== Just checking FrameProducers BuildFile.xml now ==="
BUILDFILE="/home/cmsusr/CMSSW_11_0_1/src/RecoE2E/FrameProducers/src/BuildFile.xml"
if ! grep -q 'onnxruntime' "$BUILDFILE"; then
  sed -i '/<use name="PhysicsTools\/TensorFlow"\/>/a <use name="onnxruntime"/>' "$BUILDFILE"
    echo "Added onnxruntime to BuildFile, okay"
else
    echo "onnxruntime is already there in BuildFile, so that part is fine"
fi
cat "$BUILDFILE"

# Step 3: Fix EGInference_cfg.py properly
echo ""
echo "=== Okay, fixing EGInference_cfg.py now ==="
CFG="/home/cmsusr/CMSSW_11_0_1/src/RecoE2E/EGTagger/python/EGInference_cfg.py"
cat > "$CFG" << 'CFGEOF'
import FWCore.ParameterSet.Config as cms
import FWCore.ParameterSet.VarParsing as VarParsing

options = VarParsing.VarParsing('analysis')

options.register('processMode',
    default='JetLevel',
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.string,
    info = "process mode: JetLevel or EventLevel")
options.register('doEBenergy',
    default=False,
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.bool,
    info = "set doEBenergy")
options.register('skipEvents',
    default=0,
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.int,
    info = "skipEvents")
options.register('EGModelName',
    default='e_vs_ph_model.pb',
    mult=VarParsing.VarParsing.multiplicity.singleton,
    mytype=VarParsing.VarParsing.varType.string,
    info = "EGInference Model name")
options.parseArguments()

process = cms.Process("EGClassifier")

process.load("FWCore.MessageService.MessageLogger_cfi")
process.load("Configuration.StandardSequences.GeometryDB_cff")
process.load("Configuration.StandardSequences.FrontierConditions_GlobalTag_cff")
process.load("Configuration.StandardSequences.GeometryRecoDB_cff")
process.load("Configuration.StandardSequences.MagneticField_38T_cff")
process.load("Configuration.StandardSequences.Reconstruction_cff")
process.GlobalTag.globaltag = cms.string('120X_upgrade2018_realistic_v1')
process.es_prefer_GlobalTag = cms.ESPrefer('PoolDBESSource','GlobalTag')

process.maxEvents = cms.untracked.PSet(
    input = cms.untracked.int32(options.maxEvents)
    )
process.source = cms.Source("PoolSource",
    fileNames = cms.untracked.vstring(options.inputFiles),
    skipEvents = cms.untracked.uint32(options.skipEvents)
    )
print(" >> Loaded", len(options.inputFiles), "input files from list.")

process.load("RecoE2E.FrameProducers.DetFrameProducer_cfi")
process.load("RecoE2E.FrameProducers.EGFrameProducer_cfi")
process.load("RecoE2E.EGTagger.EGTagger_cfi")

process.DetFrames.setChannelOrder = "1"
process.EGTagger.EGModelName = cms.string('tfModels/' + options.EGModelName)

process.out = cms.OutputModule("PoolOutputModule",
    fileName = cms.untracked.string('EGInference_output.root')
    )
process.TFileService = cms.Service("TFileService",
    fileName = cms.string("ntuple.root")
    )

process.p = cms.Path(process.DetFrames + process.EGFrames + process.EGTagger)
process.ep = cms.EndPath(process.out)

process.Timing = cms.Service("Timing",
  summaryOnly = cms.untracked.bool(False),
  useJobReport = cms.untracked.bool(True)
)
process.SimpleMemoryCheck = cms.Service("SimpleMemoryCheck",
    ignoreTotal = cms.untracked.int32(1)
)
CFGEOF
echo "Config written, basically done."

# Step 4: Copy the required files
echo ""
echo "=== Copying ONNX model and ROOT file now ==="
cp /workspace/sample.onnx .
mkdir -p tfModels
cp /workspace/sample.onnx tfModels/
cp /workspace/SIM_DoubleGammaPt50_Pythia8_1000Ev.root .
ls -lh sample.onnx tfModels/sample.onnx SIM_DoubleGammaPt50_Pythia8_1000Ev.root

# Step 5: Rebuild the CMSSW area
echo ""
echo "=== Okay, rebuilding now ==="
scram b clean 2>&1 | tail -3
scram b -j4 2>&1

echo ""
echo "=== Build complete, looks okay ==="

# Step 6: Run inference finally
echo ""
echo "============================================================"
echo "  cmsRun is starting at $(date), okay"
echo "============================================================"

/usr/bin/time -v cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \
    inputFiles=file:SIM_DoubleGammaPt50_Pythia8_1000Ev.root \
    maxEvents=-1 \
    EGModelName=sample.onnx 2>&1

echo ""
echo "============================================================"
echo "  Inference is complete at $(date), basically done"
echo "============================================================"
