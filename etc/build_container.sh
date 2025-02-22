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
(cd curation; git pull)
(cd pombase-chado-json; git pull)
(cd pombase-python-web; git pull)
(cd genome_changelog; git pull)
rm -rf data_files
cp -r genome_changelog/results/pombase_tables data_files
cp $dump_dir/misc/gocam_model_holes_table.tsv data_files

(cd pombase-website; cp src/pombase/index.html src)
(cd pombase-website/src/assets
 ln -sf pombase-logo.png logo.png
 ln -sf pombase-logo-small.png logo-small.png
 ln -sf pombase-logo-tiny.png logo-tiny.png)

cp pombase-website/etc/setup_jbrowse2_in_container.sh $container_dir/container_scripts/
cp pombase-website/etc/PomBasePlugin.js $container_dir/

rsync -aL --delete-after --exclude '*~' $SCRIPT_PATH/docker-conf/ conf/

rsync -acvPHS --delete-after $dump_dir/web-json $container_dir/
rsync -acvPHS --delete-after $dump_dir/misc $container_dir/
rsync -acvPHS --delete-after $dump_dir/gff $container_dir/
rsync -acvPHS --delete-after $dump_dir/fasta/chromosomes/ $container_dir/chromosome_fasta/
rsync -acvPHS --delete-after $dump_dir/fasta/bgzip_chromosomes $container_dir/

cp $dump_dir/api_maps.sqlite3.zst $container_dir/
cp $dump_dir/pombe-embl/supporting_files/PB_references.txt $container_dir/
cp $dump_dir/pombe-embl/supporting_files/*.svg $container_dir/

mkdir -p $container_dir/feature_sequences
rsync -acvPHS --delete-after $dump_dir/fasta/feature_sequences/peptide.fa.gz $container_dir/feature_sequences/peptide.fa.gz

$SCRIPT_PATH/create_jbrowse_track_list.pl $container_dir/pombase-config/website/trackListTemplate.json \
   $container_dir/pombase-config/website/jbrowse_track_metadata.csv \
   $container_dir/trackList.json $container_dir/jbrowse_track_metadata.csv \
   $container_dir/minimal_jbrowse_track_list.json \
   $container_dir/jbrowse2_config.json

echo building container ...
docker build --progress=plain -f conf/Dockerfile-main --build-arg database_name=pombase --build-arg target=$target -t=pombase/web:$version-$target .

echo "ssh pombase-admin@149.155.131.177 /home/pombase-admin/bin/reload_apache" | at 6am
