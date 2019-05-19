#!/bin/bash -

set -eu
set -o pipefail

SCRIPT=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT")

version=$1
dump_dir=$2
target=$3
go_xrf_abbs=$4

CONTAINER_DIR=/var/pomcur/container_build

cd $CONTAINER_DIR

(cd pombase-config; git pull)
(cd ng-website; git pull)
(cd pombase-chado-json; git pull)
(cd pombase-python-web; git pull)

rsync -aL --delete-after --exclude '*~' $SCRIPT_PATH/docker-conf/ conf/

rsync -acvPHS --delete-after pombase-chado-json/Rocket.toml $CONTAINER_DIR/

rsync -acvPHS --delete-after $dump_dir/web-json $CONTAINER_DIR/
rsync -acvPHS --delete-after $dump_dir/gff $CONTAINER_DIR/
rsync -acvPHS --delete-after $dump_dir/fasta/chromosomes/ $CONTAINER_DIR/chromosome_fasta/

cp $go_xrf_abbs $CONTAINER_DIR/

mkdir -p $CONTAINER_DIR/feature_sequences
rsync -acvPHS --delete-after $dump_dir/fasta/feature_sequences/peptide.fa.gz $CONTAINER_DIR/feature_sequences/peptide.fa.gz

$SCRIPT_PATH/create_jbrowse_track_list.pl $CONTAINER_DIR/pombase-config/website/trackListTemplate.json \
   $CONTAINER_DIR/pombase-config/website/pombase_jbrowse_track_metadata.csv \
   $CONTAINER_DIR/trackList.json $CONTAINER_DIR/pombase_jbrowse_track_metadata.csv \
   $CONTAINER_DIR/minimal_jbrowse_track_list.json

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/web:$version-$target .

