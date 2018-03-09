#!/bin/bash -

if [ x$APP_DEPLOY_CONFIG = x ]
then
    APP_DEPLOY_CONFIG="{ mode: 'prod' }"
fi

if [ $ANALYTICS_ID = UNSET ]
then
  echo "ANALYTICS_ID is not set - container won't start"
  exit 1
else
  /pombase/update_vars.sh $ANALYTICS_ID "$APP_DEPLOY_CONFIG" /var/www/html/index.html &&
  exec /usr/local/bin/circusd /pombase/circus.ini
fi
