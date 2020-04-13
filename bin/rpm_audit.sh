#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

MY_REPO=/localdisk/designer/jenkins/master
CENTOS_DIR=$MY_REPO/stx-tools/centos-mirror-tools
SAMPLE_YUM_CONF=$CENTOS_DIR/yum.conf.sample
YUM_REPO_DIR=$CENTOS_DIR/yum.repos.d
DOCKER_IMAGE="centos:7.6.1810"

# $CENTOS_DIR/other_downloads.lst
# $CENTOS_DIR/rpms_centos.lst
# $CENTOS_DIR/rpms_3rdparties.lst
# $CENTOS_DIR/tarball-dl.lst
# $CENTOS_DIR/rpms_centos3rdparties.lst

get_docker_rpm_list () {
    local image="$1"
    docker  pull "$image"
    docker run "$image" rpm -qa  | sed 's#$#.rpm#'
}

get_centos_lst_rpm_list () {
   cat $CENTOS_DIR/rpms_centos3rdparties.lst $CENTOS_DIR/rpms_centos.lst | sed 's/#.*$//' | sed 's/^[ ]*//' | sed 's/[ ]*$//' | grep -v '^$'
}

split_rpm_name () {
    local r="$1"
    local arch
    local name
    local version
    local release
    local temp

    r=$(basename $r)
    arch=$(echo $r | rev | cut -d '.' -f 2 | rev) 
    temp=$(echo $r | rev | cut -d '.' -f 3- | rev) 
    name=$(echo $temp | rev | cut -d '-' -f 3- | rev)
    version=$(echo $temp | rev | cut -d '-' -f 2 | rev)
    release=$(echo $temp | rev | cut -d '-' -f 1 | rev)
    echo "$name $version $release $arch"
}

rpm_name () {
    split_rpm_name "$1" | cut -d ' ' -f 1
}

rpm_arch () {
    split_rpm_name "$1" | cut -d ' ' -f 4
}

TEMP_YUM_CONF=$(mktemp "/tmp/yum_XXXXXX.conf")
cat $SAMPLE_YUM_CONF | sed "s#^reposdir=.*#reposdir=$YUM_REPO_DIR#" > $TEMP_YUM_CONF

yum --config $TEMP_YUM_CONF --skip-broken makecache

# rpms out of date relative to upstream repos
for r in $(get_centos_lst_rpm_list); do
    name=$(rpm_name "$r")
    arch=$(rpm_arch "$r")
    if [ "$arch" == "src" ]; then
        extra_arg="--srpm"
    else
        extra_arg="--archlist=$arch "
    fi
    current_r_v=$(split_rpm_name "$r" | cut -d ' ' -f 2-3 | tr ' ' '-')
    # latest_v_r=$(yum --config $TEMP_YUM_CONF $extra_arg --cacheonly --showduplicates list $name | grep "^$name.$arch" | awk '{ print $2 }' | sort --unique | tail -n 1)
    latest_v_r=$(repoquery --config $TEMP_YUM_CONF $extra_arg --cache --all --qf "%{version}-%{release}" $name | tail -n 1)
    if [ "$current_r_v" != "$latest_v_r" ]; then
        echo "$name  $arch  $current_r_v  $latest_v_r"
    fi
done

# rpms out of date relative to docker image
for rd in $(get_docker_rpm_list $DOCKER_IMAGE); do
    d_name=$(rpm_name "$rd")
    d_arch=$(rpm_arch "$rd")
    for r in $(get_centos_lst_rpm_list | grep "^$d_name" | grep ".$d_arch.rpm$" | grep -v "$rd"); do
        name=$(rpm_name "$r")
        arch=$(rpm_arch "$r")
        if [ "$name" != "$d_name" ]; then
            continue
        fi
        echo "$rd vs $r"
        # for rr in $(get_centos_lst_rpm_list); do
        # repoquery --config $TEMP_YUM_CONF --cache --all  --qf="%{name}:%{requires}" $(get_centos_lst_rpm_list | sed 's#.rpm$##') | awk '/:/ && p{print p;p=""}{p=p $0 "," }END{if(p) print p }' | sed 's/,$//' | grep ' = ' 
        repoquery --config $TEMP_YUM_CONF --cache --all  --qf="%{name}#%{requires}" $(get_centos_lst_rpm_list | sed 's#.rpm$##') | awk '/#/ && p{print p;p=""}{p=p $0 "," }END{if(p) print p }' | sed 's/,$//'| grep ' = ' | while read LINE; do
            rr_name=$(echo "$LINE" | cut -d '#' -f 1)
            echo "$LINE" | cut -d '#' -f 2 | tr ',' '\n' | grep "^d_name" | grep " = " | while read DEP; do
                echo "== $rr_name == $DEP =="
                repoquery --config $TEMP_YUM_CONF --cache --all --nvr --whatprovides "$DEP"
            done
        done
        echo
    done
done
