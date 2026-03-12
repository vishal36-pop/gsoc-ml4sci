#!/bin/bash
# =============================================================================
# cmssw_setup_and_infer.sh
#
# This script runs inside the CMSSW Docker container, basically end to end.
# It sets up CMSSW, builds RecoE2E, and then runs ONNX inference with timing.
#
# Environment variables (set by run_cmssw_docker.ps1 or manually):
#   CMSSW_VERSION  - CMSSW release to use          (default: CMSSW_11_0_1)
#   MAX_EVENTS     - Number of events to process    (default: -1 = all)
#   ONNX_MODEL     - ONNX model filename            (default: sample.onnx)
#   ROOT_FILE      - Input ROOT filename            (default: SIM_DoubleGammaPt50_Pythia8_1000Ev.root)
# =============================================================================

set -eo pipefail

CMSSW_VERSION="${CMSSW_VERSION:-CMSSW_11_0_1}"
MAX_EVENTS="${MAX_EVENTS:--1}"
ONNX_MODEL="${ONNX_MODEL:-sample.onnx}"
ROOT_FILE="${ROOT_FILE:-SIM_DoubleGammaPt50_Pythia8_1000Ev.root}"
WORKSPACE="/workspace"
LOGFILE="${WORKSPACE}/cmssw_inference_results.log"

echo "============================================================"
echo "  CMSSW Inference for Mass Regression - Task 2g, okay"
echo "============================================================"
echo "  CMSSW version : ${CMSSW_VERSION}"
echo "  Max events    : ${MAX_EVENTS}"
echo "  ONNX model    : ${ONNX_MODEL}"
echo "  ROOT file     : ${ROOT_FILE}"
echo "============================================================"

echo ""
echo "[Step 1/5] Okay, creating the CMSSW release area..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd /home/cmsusr
cmsrel "${CMSSW_VERSION}"
cd "${CMSSW_VERSION}/src"
cmsenv
echo "  CMSSW_BASE = ${CMSSW_BASE}"

echo ""
echo "[Step 2/5] Okay, fetching DataFormats/TestObjects and RecoE2E..."
git cms-addpkg DataFormats/TestObjects
git clone https://github.com/rchudasa/RecoE2E.git

echo ""
echo "[Step 3/5] Now building with scram, basically..."
scram b -j8

echo ""
echo "[Step 4/5] Okay, copying the ONNX model and ROOT file into CMSSW src/ area..."

if [ -f "${WORKSPACE}/${ONNX_MODEL}" ]; then
    cp "${WORKSPACE}/${ONNX_MODEL}" .
    echo "  Okay, copied ${ONNX_MODEL}"
else
    echo "  ERROR: ${WORKSPACE}/${ONNX_MODEL} not found, so stopping here only."
    exit 1
fi

if [ -f "${WORKSPACE}/${ROOT_FILE}" ]; then
    cp "${WORKSPACE}/${ROOT_FILE}" .
    echo "  Okay, copied ${ROOT_FILE}"
else
    echo "  ERROR: ${WORKSPACE}/${ROOT_FILE} not found, so this part cannot continue."
    echo "  Just download it from https://cernbox.cern.ch/s/Yp3oZl8cUU6JoFC"
    exit 1
fi

echo ""
echo "[Step 5/5] Okay, running cmsRun inference now..."
echo "============================================================"
echo "  Command:"
echo "    cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \\"
echo "      inputFiles=file:${ROOT_FILE} \\"
echo "      maxEvents=${MAX_EVENTS} \\"
echo "      EGModelName=${ONNX_MODEL}"
echo "============================================================"

# Capture the full timing information, just for clarity
{
    echo "=========================================="
    echo "CMSSW Inference Timing Results, basically"
    echo "Date: $(date)"
    echo "CMSSW: ${CMSSW_VERSION}"
    echo "Model: ${ONNX_MODEL}"
    echo "Events: ${MAX_EVENTS}"
    echo "=========================================="

    /usr/bin/time -v cmsRun RecoE2E/EGTagger/python/EGInference_cfg.py \
        inputFiles=file:"${ROOT_FILE}" \
        maxEvents="${MAX_EVENTS}" \
        EGModelName="${ONNX_MODEL}" 2>&1

    echo ""
    echo "=========================================="
    echo "Inference completed successfully, okay."
    echo "=========================================="
} 2>&1 | tee "${LOGFILE}"

echo ""
echo "Results saved to: ${LOGFILE}"
echo "The file is in the mounted /workspace directory, so it will be visible on the host side also."
