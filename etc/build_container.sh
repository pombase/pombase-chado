#!/bin/sh -

config_dir=$1
version=$2
dump_dir=$3
target=$4

TEMP_DIR=/tmp

cd $TEMP_DIR

docker_build_dir=pombase_docker_build_tmp.$$

mkdir $docker_build_dir
cd $docker_build_dir
mkdir bin
cp /var/pomcur/bin/pombase-server bin/
mkdir latest_dump_dir
mkdir conf

git clone https://github.com/pombase/website.git ng-website

cp -r $config_dir/* conf/
cp /var/pomcur/bin/* bin/

echo copying dump dir ...
cp -r $dump_dir/* latest_dump_dir/

echo building container ...
docker build -f conf/Dockerfile-main --build-arg target=$target -t=pombase/pombase-base:$version-$target .

rm -rf $TEMP_DIR/$docker_build_dir
