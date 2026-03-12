#!/bin/bash
set -e
source /opt/cms/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc820
cd /home/cmsusr/CMSSW_10_6_8_patch1/src
eval $(scramv1 runtime -sh)

# Copy the data files first, basically prepare the inputs
cp /workspace/SIM_DoubleGammaPt50_Pythia8_1000Ev.root .
mkdir -p RecoE2E/tfModels
cp /workspace/sample.onnx RecoE2E/tfModels/sample.onnx

# Write the fixed config, just so cmsRun uses the correct setup
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

echo "=== Okay, running cmsRun inference now ==="
date
/usr/bin/time -v cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \
    inputFiles=file:SIM_DoubleGammaPt50_Pythia8_1000Ev.root \
    maxEvents=-1 \
    EGModelName=sample.onnx 2>&1
EXITCODE=$?
date
echo "=== cmsRun EXIT CODE: $EXITCODE , just note it down ==="
