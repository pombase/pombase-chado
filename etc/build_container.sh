#!/bin/bash -

set -eu
set -o pipefail

SCRIPT=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT")

version=$1
dump_dir=$2
target=$3

CONTAINER_DIR=/var/pomcur/container_build

cd $CONTAINER_DIR

(cd ng-website; git pull)
(cd pombase-chado-json; git pull)

rsync -aL --delete-after --exclude '*~' $SCRIPT_PATH/docker-conf/ conf/

rsync -acvPHS --delete-after pombase-chado-json/Rocket.toml $CONTAINER_DIR/

rsync -acvPHS --delete-after $dump_dir/web-json $CONTAINER_DIR/
rsync -acvPHS --delete-after $dump_dir/gff $CONTAINER_DIR/
rsync -acvPHS --delete-after $dump_dir/fasta/chromosomes/ $CONTAINER_DIR/chromosome_fasta/
rsync -acvPHS --delete-after $dump_dir/pombe-embl/website/ $CONTAINER_DIR/website_config/

$SCRIPT_PATH/create_jbrowse_track_list.pl $CONTAINER_DIR/website_config/trackListTemplate.json $CONTAINER_DIR/website_config/pombase_jbrowse_track_metadata.csv \
   $CONTAINER_DIR/trackList.json $CONTAINER_DIR/pombase_jbrowse_track_metadata.csv

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/web:$version-$target .

