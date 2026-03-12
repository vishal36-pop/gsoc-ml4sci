#!/bin/bash
# Fix site-local-config.xml by creating a local override
# that uses direct Frontier connections, basically no proxy here

# Create the local SITECONF directory first
mkdir -p /home/cmsusr/CMSSW_12_0_2/SITECONF/local/JobConfig

cat > /home/cmsusr/CMSSW_12_0_2/SITECONF/local/JobConfig/site-local-config.xml << 'XMLEOF'
<site-local-config>
  <site name="T3_US_Docker">
    <event-data>
      <catalog url="trivialcatalog_file:/cvmfs/cms.cern.ch/SITECONF/local/PhEDEx/storage.xml?protocol=direct"/>
    </event-data>
    <calib-data>
      <frontier-connect>
        <load balance="proxies"/>
        <server url="http://cmsfrontier.cern.ch:8000/FrontierProd"/>
        <server url="http://cmsfrontier1.cern.ch:8000/FrontierProd"/>
        <server url="http://cmsfrontier2.cern.ch:8000/FrontierProd"/>
        <server url="http://cmsfrontier3.cern.ch:8000/FrontierProd"/>
      </frontier-connect>
    </calib-data>
  </site>
</site-local-config>
XMLEOF

echo "site-local-config.xml created at /home/cmsusr/CMSSW_12_0_2/SITECONF/local/JobConfig/, okay"
cat /home/cmsusr/CMSSW_12_0_2/SITECONF/local/JobConfig/site-local-config.xml

# Set CMS_PATH to use our local SITECONF first, just to be safe
echo ""
echo "To use this config, just set: export CMS_PATH=/home/cmsusr/CMSSW_12_0_2"
