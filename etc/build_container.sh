#!/bin/bash -

SCRIPT=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT")

version=$1
dump_dir=$2
target=$3

TEMP_DIR=/var/pomcur/container_build

cd $TEMP_DIR

(cd ng-website; git pull)
(cd pombase-chado-json; git pull)

rsync -aL --delete-after $SCRIPT_PATH/docker-conf/* conf/

echo copying dump dir ...
rsync -aL --delete-after $dump_dir/* latest_dump_dir/

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/web:$version-$target .

