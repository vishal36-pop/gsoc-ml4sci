#!/bin/bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=slc7_amd64_gcc900
cd /home/cmsusr/CMSSW_12_0_2/src
eval $(scramv1 runtime -sh)

echo "=== OpenSSL tool info, just checking ==="
scram tool info openssl 2>&1

echo ""
echo "=== Checking the OpenSSL libraries now ==="
find /cvmfs/cms.cern.ch/slc7_amd64_gcc900/external/openssl -name "libssl*" 2>/dev/null | head -5
find /cvmfs/cms.cern.ch/slc7_amd64_gcc900/external/openssl -name "libcrypto*" 2>/dev/null | head -5

echo ""
echo "=== System OpenSSL, basically host-side view ==="
ls -la /usr/lib64/libssl* 2>/dev/null
ls -la /usr/lib64/libcrypto* 2>/dev/null

echo ""
echo "=== LD_LIBRARY_PATH (first 3 paths), just for reference ==="
echo $LD_LIBRARY_PATH | tr ':' '\n' | head -3

echo ""
echo "=== Check if the openssl lib dir is in the path ==="
echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -i openssl | head -3
