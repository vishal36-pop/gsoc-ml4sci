#!/bin/bash
set -e
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== Step 1: Okay, fixing the predict_tf.cc hardcoded model path ==="
PREDICT_TF="RecoE2E/FrameProducers/src/predict_tf.cc"
# Replace the hardcoded /afs/ path with a path relative to CMSSW_BASE/src, basically make it portable
sed -i 's|std::string modelFilepath ="/afs/cern.ch/work/r/rchudasa/private/inference/CMSSW_12_0_2/src/RecoE2E/tfModels/sample.onnx";|std::string modelFilepath = std::string(getenv("CMSSW_BASE")) + "/src/RecoE2E/" + model_filename;|' "$PREDICT_TF"
echo "Fixed the predict_tf.cc model path, okay"
grep "modelFilepath" "$PREDICT_TF" | head -5

echo ""
echo "=== Step 2: Just make sure the model file is in the right place ==="
mkdir -p RecoE2E/tfModels
cp /workspace/sample.onnx RecoE2E/tfModels/sample.onnx
cp /workspace/sample.onnx RecoE2E/sample.onnx
echo "Model copied to RecoE2E/tfModels/ and RecoE2E/, basically done"
ls -la RecoE2E/tfModels/sample.onnx RecoE2E/sample.onnx

echo ""
echo "=== Step 3: Rebuild now ==="
scram b -j4 2>&1 | tail -15
echo "BUILD EXIT CODE: $? , just for checking"

echo ""
echo "=== Step 4: Write EGInference_cfg.py properly ==="
cat > RecoE2E/EGTagger/python/EGInference_cfg.py << 'CFGEOF'
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
    default='tfModels/sample.onnx',
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
process.EGTagger.EGModelName = cms.string(options.EGModelName)

process.out = cms.OutputModule("PoolOutputModule",
    fileName = cms.untracked.string('EGInference_output.root')
    )

process.TFileService = cms.Service("TFileService",
    fileName = cms.string("ntuple.root")
    )

process.p = cms.Path(process.DetFrames + process.EGFrames + process.EGTagger)
process.ep = cms.EndPath(process.out)

from HLTrigger.Timer.FastTimerService_cfi import FastTimerService as _FastTimerService
process.FastTimerService = _FastTimerService.clone(
    enableDQM = False,
    printRunSummary = False,
    printJobSummary = True,
    writeJSONSummary = True,
    jsonFileName = 'resources.json'
)
CFGEOF
echo "Config file written, okay."

echo ""
echo "=== Step 5: Fix site-local-config.xml, basically one small cleanup ==="
SITE_CONFIG=$(python3 -c "import CMSSW_SEARCH_PATH; print(CMSSW_SEARCH_PATH)" 2>/dev/null || echo "")
# Find the site-local-config.xml, just checking where it is coming from
SITE_XML=$(find $CMSSW_RELEASE_BASE -path "*/SITECONF/local/JobConfig/site-local-config.xml" 2>/dev/null | head -1)
if [ -z "$SITE_XML" ]; then
    SITE_XML="/cvmfs/cms.cern.ch/SITECONF/local/JobConfig/site-local-config.xml"
fi
echo "Original site-local-config.xml: $SITE_XML"
cat "$SITE_XML" 2>/dev/null | head -20

echo ""
echo "=== Setup complete! Ready to run now, okay. ==="
