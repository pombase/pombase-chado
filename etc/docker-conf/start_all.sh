#!/bin/bash -

if [ "x$APP_DEPLOY_CONFIG" = x ]
then
    APP_DEPLOY_CONFIG="{ mode: 'prod' }"
fi

if [ $ANALYTICS_ID = UNSET ]
then
  echo "ANALYTICS_ID is not set - container won't start"
  exit 1
fi

if [ $GOOGLE_TAG_MANAGER_ID = UNSET ]
then
  echo "GOOGLE_TAG_MANAGER_ID is not set - container won't start"
  exit 1
fi

zstd -dq --rm /pombase/api_maps.sqlite3.zst

export HOST_IP_ADDRESS=$(route | grep '^default' | awk '{print $2}')

/pombase/update_vars.sh $ANALYTICS_ID $GOOGLE_TAG_MANAGER_ID "$APP_DEPLOY_CONFIG" /var/www/html/index.html &&
perl -pne "s/<<database_name>>/$DATABASE_NAME/g" /pombase/circus.ini.template > /pombase/circus.ini
exec /usr/local/bin/circusd --log-level debug /pombase/circus.ini
