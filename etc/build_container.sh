#!/bin/bash -

set -eu
set -o pipefail

SCRIPT=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT")

version=$1
dump_dir=$2
target=$3
container_dir=$4


cd $container_dir

(cd pombase-config; git pull)
(cd pombase-website; git pull)
(cd pombase-chado-json; git pull)
(cd pombase-python-web; git pull)

(cd pombase-website; cp src/$target/index.html src/)

rsync -aL --delete-after --exclude '*~' $SCRIPT_PATH/docker-conf/ conf/

rsync -acvPHS --delete-after pombase-chado-json/Rocket.toml $container_dir/

rsync -acvPHS --delete-after $dump_dir/web-json $container_dir/
rsync -acvPHS --delete-after $dump_dir/misc $container_dir/
rsync -acvPHS --delete-after $dump_dir/gff $container_dir/
rsync -acvPHS --delete-after $dump_dir/fasta/chromosomes/ $container_dir/chromosome_fasta/

mkdir -p $container_dir/feature_sequences
rsync -acvPHS --delete-after $dump_dir/fasta/feature_sequences/peptide.fa.gz $container_dir/feature_sequences/peptide.fa.gz

$SCRIPT_PATH/create_jbrowse_track_list.pl $container_dir/pombase-config/website/trackListTemplate.json \
   $container_dir/pombase-config/website/pombase_jbrowse_track_metadata.csv \
   $container_dir/trackList.json $container_dir/pombase_jbrowse_track_metadata.csv \
   $container_dir/minimal_jbrowse_track_list.json

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/web:$version-$target .

echo "ssh pombase-admin@149.155.131.177 /home/pombase-admin/bin/reload_apache" | at 6am
