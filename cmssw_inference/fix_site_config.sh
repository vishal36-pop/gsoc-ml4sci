#!/bin/bash
# Fix site-local-config.xml to remove the proxy dependency, basically keep it direct
cat > /opt/cms/SITECONF/local/JobConfig/site-local-config.xml << 'XMLEOF'
<site-local-config>
<site name="docker">
   <event-data>
     <catalog url="trivialcatalog_file:/opt/cms/SITECONF/local/PhEDEx/storage.xml?protocol=direct"/>
   </event-data>
   <calib-data>
     <frontier-connect>
       <server url="http://cmsfrontier.cern.ch:8000/FrontierProd"/>
       <server url="http://cmsfrontier1.cern.ch:8000/FrontierProd"/>
       <server url="http://cmsfrontier2.cern.ch:8000/FrontierProd"/>
       <server url="http://cmsfrontier3.cern.ch:8000/FrontierProd"/>
     </frontier-connect>
   </calib-data>
</site>
</site-local-config>
XMLEOF
echo "Site config fixed, okay"
cat /opt/cms/SITECONF/local/JobConfig/site-local-config.xml
