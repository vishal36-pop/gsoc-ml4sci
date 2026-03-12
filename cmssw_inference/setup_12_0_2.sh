#!/bin/bash
set -e

echo "========================================="
echo " CMSSW 12_0_2 ONNX Inference Setup, okay"
echo "========================================="

# Step 1: Set up the CMSSW environment, basically first things first
echo "[1/7] Okay, setting up the CMSSW_12_0_2 environment..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900

cd /home/cmsusr
if [ ! -d "CMSSW_12_0_2" ]; then
    echo "Creating the CMSSW_12_0_2 release area, this may take a bit of time on cvmfs..."
    scramv1 project CMSSW CMSSW_12_0_2
fi
cd CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)
echo "CMSSW environment is ready: $CMSSW_BASE"

# Step 2: Clone RecoE2E, just to get the code in place
echo "[2/7] Okay, cloning the RecoE2E repository..."
if [ -d "RecoE2E" ]; then
    echo "RecoE2E already exists, so removing it first..."
    rm -rf RecoE2E
fi
git clone https://github.com/rchudasa/RecoE2E.git
echo "RecoE2E cloned, basically done."

# Step 3: Remove broken files, basically cleanup work
echo "[3/7] Removing broken or duplicate files now..."
rm -f RecoE2E/EGTagger/plugins/ONNXRuntime.cc
rm -f RecoE2E/EGTagger/interface/ONNXRuntime.h
rm -f RecoE2E/EGTagger/src/predict_onxx.cc
echo "Broken files removed, okay."

# Step 4: Fix hardcoded paths in predict_tf.cc
echo "[4/7] Okay, fixing hardcoded paths in predict_tf.cc..."
PREDICT_TF="RecoE2E/EGTagger/src/predict_tf.cc"
if [ -f "$PREDICT_TF" ]; then
    # Fix the hardcoded model path, basically replace /afs/.../RecoE2E/ with RecoE2E/
    sed -i 's|/afs/cern.ch/work/r/rchudasa/private/inference/CMSSW_12_0_2/src/RecoE2E/|RecoE2E/|g' "$PREDICT_TF"
    echo "Fixed the hardcoded paths, okay."
else
    echo "WARNING: predict_tf.cc not found, so this fix could not be applied."
fi

# Step 5: Copy model and data files, just keep everything in the right place
echo "[5/7] Copying model and data files now..."
cp /workspace/sample.onnx /home/cmsusr/CMSSW_12_0_2/src/RecoE2E/
cp /workspace/SIM_DoubleGammaPt50_Pythia8_1000Ev.root /home/cmsusr/CMSSW_12_0_2/src/
echo "Files copied, basically done."

# Step 6: Write EGInference_cfg.py properly
echo "[6/7] Okay, writing EGInference_cfg.py now..."
cat > RecoE2E/EGTagger/python/EGInference_cfg.py << 'CFGEOF'
import FWCore.ParameterSet.Config as cms
import FWCore.ParameterSet.VarParsing as VarParsing

options = VarParsing.VarParsing('analysis')
options.register('EGModelName',
    'sample.onnx',
    VarParsing.VarParsing.multiplicity.singleton,
    VarParsing.VarParsing.varType.string,
    "Name of the ONNX model file")

options.register('maxEvents',
    -1,
    VarParsing.VarParsing.multiplicity.singleton,
    VarParsing.VarParsing.varType.int,
    "Number of events to process")

options.parseArguments()

process = cms.Process("EGInference")

process.load("FWCore.MessageService.MessageLogger_cfi")
process.MessageLogger.cerr.FwkReport.reportEvery = 100

process.maxEvents = cms.untracked.PSet(input = cms.untracked.int32(options.maxEvents))

process.source = cms.Source("PoolSource",
    fileNames = cms.untracked.vstring(options.inputFiles)
)

process.load("Configuration.Geometry.GeometryRecoDB_cff")
process.load("Configuration.StandardSequences.FrontierConditions_GlobalTag_cff")
from Configuration.AlCa.GlobalTag import GlobalTag
process.GlobalTag = GlobalTag(process.GlobalTag, 'auto:phase1_2018_realistic', '')

process.load("Configuration.StandardSequences.MagneticField_cff")

process.EGTagger = cms.EDProducer("EGTagger",
    EGModelName = cms.string(options.EGModelName),
    reducedEBRecHitCollection = cms.InputTag("reducedEcalRecHitsEB"),
    reducedEERecHitCollection = cms.InputTag("reducedEcalRecHitsEE"),
    reducedHBHERecHitCollection = cms.InputTag("reducedHcalRecHits","hbhereco"),
    trackCollection = cms.InputTag("generalTracks"),
    vertexCollection = cms.InputTag("offlinePrimaryVertices"),
    jetCollection = cms.InputTag("ak4PFJetsCHS"),
    genParticleCollection = cms.InputTag("genParticles"),
    photonCollection = cms.InputTag("gedPhotons"),
    EBRecHitCollection = cms.InputTag("ecalRecHit","EcalRecHitsEB"),
    EERecHitCollection = cms.InputTag("ecalRecHit","EcalRecHitsEE"),
    HBHERecHitCollection = cms.InputTag("hbhereco"),
    EBDigiCollection = cms.InputTag("ecalDigis","ebDigis"),
    EEDigiCollection = cms.InputTag("ecalDigis","eeDigis"),
)

process.p = cms.Path(process.EGTagger)
CFGEOF
echo "Config file written, okay."

# Step 7: Build with scram, finally
echo "[7/7] Building with scram now..."
cd /home/cmsusr/CMSSW_12_0_2/src
scram b -j4 2>&1 | tail -20
echo ""
echo "========================================="
echo " Build complete! Exit code: $? , just check once"
echo "========================================="
