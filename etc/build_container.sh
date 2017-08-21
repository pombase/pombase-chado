#!/bin/sh -

config_dir=$1
version=$2
dump_dir=$3

TEMP_DIR=/tmp

cd $TEMP_DIR

docker_build_dir=pombase_docker_build_tmp.$$

mkdir $docker_build_dir
cd $docker_build_dir
mkdir bin
mkdir latest_dump_dir
mkdir conf

git clone https://github.com/pombase/website.git ng-website

cp -r $config_dir/* conf/
cp /var/pomcur/bin/* bin/
cp -r $dump_dir/* latest_dump_dir/

docker build -f conf/Dockerfile-main -t=pombase/pombase-base:$version .

rm -rf $TEM_DIR/$docker_build_dir
