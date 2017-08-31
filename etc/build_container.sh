#!/bin/sh -

config_dir=$1
version=$2
dump_dir=$3
target=$4

TEMP_DIR=/var/pomcur/container_build

cd $TEMP_DIR

(cd ng-website; git pull)
(cd pombase-chado-json; git pull)

rsync -aL --delete-after $config_dir/* conf/

echo copying dump dir ...
rsync -aL --delete-after $dump_dir/* latest_dump_dir/

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/web:$version-$target .

