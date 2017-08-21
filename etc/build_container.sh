#!/bin/sh -

config_dir=$1
version=$2
dump_dir=$3

cd /tmp/

tmp_dir=build_tmp.$$

mkdir $tmp_dir
cd $tmp_dir
mkdir bin
mkdir latest_dump_dir
mkdir conf

git clone https://github.com/pombase/website.git ng-website

cp -r $config_dir/* conf/
cp /var/pomcur/bin/* bin/
cp -r $dump_dir/* latest_dump_dir/

docker build -f conf/Dockerfile-main -t=pombase/pombase-base:$version .

cd /tmp/

#rm -rf $tmp_dir
