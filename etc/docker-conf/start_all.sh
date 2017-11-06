#!/bin/bash -

if [ $ANALYTICS_ID = UNSET ]
then
  echo "ANALYTICS_ID is not set - container won't start"
  exit 1
else
  /pombase/update_analytics_id.sh $ANALYTICS_ID /var/www/html/index.html &&
  exec /usr/local/bin/circusd /pombase/circus.ini
fi
