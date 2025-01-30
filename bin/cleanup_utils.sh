#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Utility functions to assist in the deletion of old builds
# including their published artifacts.
#

FILE_UTILS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

source "${FILE_UTILS_DIR}/docker_hub_utils.sh" || exit 1

USR=jenkins

# Default values if the project doesn't have a SAVE_DATA_FILE
SAVE_DAYS_GREEN=28
SAVE_DAYS_YELLOW=10
SAVE_DAYS_RED=7
SAVE_DAYS_UNKNOWN=7
SAVE_MIN_KEEP=2

# Files in a project directory"
SAVE_DATA_FILE="SAVE_DATA"

# Files in a build directory
KEEP_FILE="KEEP"
SANITY_FILE_GREEN="GREEN"
SANITY_FILE_YELLOW="YELLOW"
SANITY_FILE_RED="RED"

WORKSPACE_BASE=/localdisk/loadbuild/jenkins
PUBLISHED_BASE=/export/mirror/starlingx
PUBLISHED_RELEASE_BASE=$PUBLISHED_BASE/release
PUBLISHED_MILESTONE_BASE=$PUBLISHED_BASE/milestone
KEEP_RELEASES=2
FIRST_DELETE_RELEASE=$(( KEEP_RELEASES+1 ))
NUM="[0-9]"
NOT_NUM="[^0-9]"
YYYY_MM_PATTERN="${NUM}${NUM}${NUM}${NUM}[.]${NUM}${NUM}"
MILESTONE_PATTERN="[.][bB]${NUM}"

function dir_age {
    local FN=$1
    local UNIT=$2
    local NOW
    local OLD
    local DELTA

    if [ "$FN"  == "" ]; then
        >&2 echo "dir_age: required arguement 'FN' missing"
        return 1
    fi

    if [ "$UNIT"  == "" ]; then
        >&2 echo "dir_age: required arguement 'UNIT' missing"
        return 1
    fi

    if [ ! -f "$FN" ]; then
        >&2 echo "dir_age: invalid file '$FN'"
        return 1
    fi

    NOW=$(date "+%s")
    OLD=$(stat -c %Y "$FN")
    DELTA=$(($NOW - $OLD))

    case "$UNIT" in
        years)
            DELTA=$(($DELTA / (60 * 60 * 24 * 365)))
            ;;
        months)
            DELTA=$(($DELTA / (60 * 60 * 24 * 30)))
            ;;
        weeks)
            DELTA=$(($DELTA / (60 * 60 * 24 * 7)))
            ;;
        days)
            DELTA=$(($DELTA / (60 * 60 * 24)))
            ;;
        hours)
            DELTA=$(($DELTA / (60 * 60)))
            ;;
        minutes)
            DELTA=$(($DELTA / 60))
            ;;
        seconds)
            ;;
        *)
            >&2 echo "dir_age: Invalid unit '$UNIT'"
            return 1
            ;;
    esac

    # echo "$DELTA $UNIT"
    echo "$DELTA"
    return 0
}

function file_age {
    local FN=$1
    local UNIT=$2
    local NOW
    local OLD
    local DELTA

    if [ "$FN"  == "" ]; then
        >&2 echo "file_age: required arguement 'FN' missing"
        return 1
    fi

    if [ "$UNIT"  == "" ]; then
        >&2 echo "file_age: required arguement 'UNIT' missing"
        return 1
    fi

    if [ ! -f "$FN" ]; then
        >&2 echo "file_age: invalid file '$FN'"
        return 1
    fi

    NOW=$(date "+%s")
    OLD=$(stat -c %Y "$FN")
    DELTA=$(($NOW - $OLD))

    case "$UNIT" in
        years)
            DELTA=$(($DELTA / (60 * 60 * 24 * 365)))
            ;;
        months)
            DELTA=$(($DELTA / (60 * 60 * 24 * 30)))
            ;;
        weeks)
            DELTA=$(($DELTA / (60 * 60 * 24 * 7)))
            ;;
        days)
            DELTA=$(($DELTA / (60 * 60 * 24)))
            ;;
        hours)
            DELTA=$(($DELTA / (60 * 60)))
            ;;
        minutes)
            DELTA=$(($DELTA / 60))
            ;;
        seconds)
            ;;
        *)
            >&2 echo "file_age: Invalid unit '$UNIT'"
            return 1
            ;;
    esac

    # echo "$DELTA $UNIT"
    echo "$DELTA"
    return 0
}

function published_build_age {
    local DIR=$1
    local AGE=1
    local f=""

    if [ "$DIR" == "" ]; then
        >&2 echo "published_build_age: required arguement 'DIR' missing"
        return 1
    fi

    if [ ! -d "$DIR" ]; then
        >&2 echo "published_build_age: invalid directory '$DIR'"
        return 1
    fi

    for f in $(find $DIR/logs -type f 2>> /dev/null); do
        if [ -f $f ]; then
            AGE=$(file_age $f days)
            if [ $? -eq 0 ]; then
                >&2 echo "   $f  AGE=$AGE"
                echo "$AGE"
                return 0
            fi
        fi
    done

    for f in $DIR/outputs/CHANGELOG.txt $DIR/outputs/CONTEXT.sh $DIR/outputs/BUILD_INFO.txt $DIR/outputs/iso/bootimage.iso; do
        if [ -f $f ]; then
            AGE=$(file_age $f days)
            if [ $? -eq 0 ]; then
                >&2 echo "   $f  AGE=$AGE"
                echo "$AGE"
                return 0
            fi
        fi
    done

    for f in $DIR/logs ; do
        if [ -d $f ]; then
            AGE=$(dir_age $f days)
            if [ $? -eq 0 ]; then
                >&2 echo "   $f  AGE=$AGE"
                echo "$AGE"
                return 0
            fi
        fi
    done

    AGE=1
    echo "$AGE"
    return 1
}

function workspace_age {
    local DIR=$1
    local AGE=1
    local f=""

    if [ "$DIR" == "" ]; then
        >&2 echo "workspace_age: required arguement 'DIR' missing"
        return 1
    fi

    if [ ! -d "$DIR" ]; then
        >&2 echo "workspace_age: invalid directory '$DIR'"
        return 1
    fi

    for f in $DIR/BUILD $DIR/build-std.log $DIR/build.log $DIR/CHANGELOG* $DIR/PUBLISHED $DIR/localdisk/pkgbuilder/jenkins/*/chroot.log; do
        if [ -f $f ]; then
            AGE=$(file_age $f days)
            if [ $? -eq 0 ]; then
                >&2 echo "   $f  AGE=$AGE"
                echo "$AGE"
                return 0
            fi
        fi
    done

    for f in $(ls -1 -t $DIR/$USR-*.cfg $DIR/*/$USR-*.cfg $DIR/*/configs/$USR-*/$USR-*.cfg $DIR/localdisk/deploy/ostree_repo/config $DIR/localdisk/CERTS/TiBoot.crt $DIR/localdisk/log/log.appsdk* $DIR/localdisk/sub_workdir/log/log.appsdk* $DIR/aptly/nginx_access.log $DIR/containers/mock/b0/root/.initialized $DIR/installer/mock/b0/root/.initialized $DIR/rt/mock/b0/root/.initialized $DIR/std/mock/b0/root/.initialized 2>> /dev/null); do
        if [ -f $f ]; then
            AGE=$(file_age $f days)
            if [ $? -eq 0 ]; then
                >&2 echo "   $f  AGE=$AGE"
                echo "$AGE"
                return 0
            fi
        fi
    done

    AGE=1
    echo "$AGE"
    return 1
}

function test_deletable {
    local DIR=$1
    local KEPT=$2
    local DIR_TYPE=$3
    local SANITY_DIR=$4
    local LINK_DIR=$5

    local SANITY="UNKNOWN"
    local KF="$DIR/$KEEP_FILE"
    local KEEP=0
    local SANITY_COLORS="$SANITY_FILE_GREEN $SANITY_FILE_YELLOW $SANITY_FILE_RED"
    KEEP_DAYS=""
    KEEP_AGE=999999
    AGE=""

    if [ "$DIR" == "" ]; then
        >&2 echo "test_deletable: required arguement 'DIR' missing"
        return 1
    fi

    if [ "$KEPT" == "" ]; then
        >&2 echo "test_deletable: required arguement 'KEPT' missing"
        return 1
    fi

    if [ "$DIR_TYPE" == "" ]; then
        >&2 echo "test_deletable: required arguement 'DIR_TYPE' missing"
        return 1
    fi

    if [ "$SANITY_DIR" != "" ] && [ -d $SANITY_DIR ]; then
        for st in $SANITY_COLORS; do
            if [ -f "$SANITY_DIR/$st" ]; then
                SANITY="$st"
            fi
        done
    fi

    KEEP_DAYS="SAVE_DAYS_$SANITY"
    KEEP_AGE=${!KEEP_DAYS}
    AGE=""
    case $DIR_TYPE in
        workspace)
            AGE=$(workspace_age $DIR)
            ;;
        published_build)
            AGE=$(published_build_age $DIR)
            ;;
        *)
            >&2 echo "Unknown DIR_TYPE=$CDIR_TYPE"
            return 1
            ;;
    esac

    echo "   AGE=$AGE, KEEP_AGE=$KEEP_AGE, KEEP_DAYS=$KEEP_DAYS, SANITY=$SANITY"

    if [ "$AGE" == "" ]; then
        >&2 echo "   keep '$DIR' due to unknown age"
        KEEP=1
        return $KEEP
    fi

    if [ $AGE -le $KEEP_AGE ]; then
        >&2 echo "   keep '$DIR' due to age $AGE <= $KEEP_AGE (sanity $SANITY)"
        KEEP=1
        return $KEEP
    fi

    if [ -f "$KF" ]; then
        >&2 echo "   keep '$DIR' due to keep file"
        KEEP=1
        return $KEEP
    fi

    if [ "x$KEPT" != "x" ]; then
        if [ $KEPT -lt $SAVE_MIN_KEEP ]; then
            >&2 echo "   keep '$DIR' due to min keep"
            KEEP=1
            return $KEEP
        fi
    fi

    if [ "$LINK_DIR" != "" ] && [ -d $LINK_DIR ]; then
        if [ -L $LINK_DIR/latest_build ]; then
            if [ "$(basename $(readlink $LINK_DIR/latest_build))" == "$(basename $DIR)" ]; then
                >&2 echo "   keep '$DIR' due to latest_build symlink"
                KEEP=1
                return $KEEP
            fi
        fi

        if [ -L $LINK_DIR/latest_green_build ]; then
            if [ "$(basename $(readlink $LINK_DIR/latest_green_build))" == "$(basename $DIR)" ]; then
                >&2 echo "   keep '$DIR' due to latest_green_build symlink"
                KEEP=1
                return $KEEP
            fi
        fi

        if [ -L $LINK_DIR/latest_docker_image_build ]; then
            if [ "$(basename $(readlink $LINK_DIR/latest_docker_image_build))" == "$(basename $DIR)" ]; then
                >&2 echo "   keep '$DIR' due to latest_docker_image_build symlink"
                KEEP=1
                return $KEEP
            fi
        fi
    fi

    for hcd in $(find /export/mirror/starlingx/ -maxdepth 6 -type d -name helm-charts | grep -v $DIR); do
        for tgz in $(find $hcd -type f -name '*tgz'); do
            tar xzvf $tgz --wildcards "*.yaml" --to-stdout 2> /dev/null | grep 'docker.io[/]starlingx' | grep $DIR
            # tar xzvf $tgz --wildcards "*.yaml" --to-stdout 2> /dev/null | grep 'docker.io[/]starlingx'
        done
    done | sed 's/.*\(docker.io[/]starlingx[/][^ ]*\).*/\1/' | grep $DIR > /dev/null
    if [ $? -eq 0 ]; then
        >&2 echo "   keep '$DIR' due to referenced docker images"
        KEEP=1
        return $KEEP
    fi

    echo $KEEP
    return $KEEP
}


function published_build_cleanup_by_age {
    local BUILD_DIR=$1
    local TRIAL_RUN=$2

    local DIR_TYPE="published_build"
    local PUBLISHED_LOADS="/export/mirror/starlingx"
    local WILD='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
    local SD="$BUILD_DIR/$SAVE_DATA_FILE"
    local dirs=""
    local num_keep=0
    local NO_RM=0

    echo "published_build_cleanup_by_age: '$BUILD_DIR' '$TRIAL_RUN'"

    if [ "$BUILD_DIR" == "" ]; then
        >&2 echo "requied arguement '$BUILD_DIR' is missing"
        return 1
    fi

    if [ ! -d "$BUILD_DIR" ]; then
        >&2 echo "invalid directory, '$BUILD_DIR'"
        return 1
    fi

    if [[ "$BUILD_DIR" != /export/mirror/starlingx/* ]]; then
        >&2 echo "invalid directory, '$BUILD_DIR' does not start with '/export/mirror/starlingx/'"
        return 1
    fi

    if [[ $BUILD_DIR != $PUBLISHED_LOADS/master/* ]] && [[ $BUILD_DIR != $PUBLISHED_LOADS/ussuri/* ]] && [[ $BUILD_DIR != $PUBLISHED_LOADS/feature/* ]] && [[ $BUILD_DIR != $PUBLISHED_LOADS/rc/* ]]; then
        >&2 echo "directory '$BUILD_DIR' does not start with '$PUBLISHED_LOADS/master/' or '$PUBLISHED_LOADS/feature/' or '$PUBLISHED_LOADS/rc/'"
        return 1
    fi

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    cd $BUILD_DIR
    if [ $? -ne 0 ]; then
        >&2 echo "fail to 'cd $BUILD_DIR'"
        return 1
    fi

    if [ -f "$SD" ]; then
        source "$SD"
    fi

    echo "SAVE_DAYS_GREEN=$SAVE_DAYS_GREEN"
    echo "SAVE_DAYS_YELLOW=$SAVE_DAYS_YELLOW"
    echo "SAVE_DAYS_RED=$SAVE_DAYS_RED"
    echo "SAVE_DAYS_UNKNOWN=$SAVE_DAYS_UNKNOWN"
    echo "SAVE_MIN_KEEP=$SAVE_MIN_KEEP"
    echo "TRIAL_RUN=$TRIAL_RUN"

    dirs=$(ls -dr1 $WILD)

    for d in $dirs; do
       echo "Considering '$d'"
       echo "   test_deletable '$d' '$num_keep' '$DIR_TYPE' '$d/outputs/' '.'"
       test_deletable "$d" "$num_keep" "$DIR_TYPE" "$d/outputs/" "."
       if [ $? -eq 0 ]; then
           echo "Delete: $BUILD_DIR/$d"
           NO_RM=0
           if [ $NO_RM -ne 1 ]; then
              echo "delete_still_publised_images '$BUILD_DIR' '$d'"
              delete_still_publised_images "$BUILD_DIR" "$d" "$TRIAL_RUN"

              echo "nice -n 20 ionice -c Idle rm -rf $d"
              if [ $TRIAL_RUN -ne 1 ]; then
                  nice -n 20 ionice -c Idle rm -rf "$d"
              fi
           fi
       else
           num_keep=$(($num_keep + 1))
           echo "Keep: $d"
       fi
       echo "----------------"
    done
}

function workspace_cleanup_by_age {
    local BUILD_DIR=$1
    local TRIAL_RUN=$2

    local DIR_TYPE="workspace"
    local JENKINS_LOADS="/localdisk/loadbuild/$USR"
    local WILD='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
    local SD="$BUILD_DIR/$SAVE_DATA_FILE"
    local dirs=""
    local num_keep=0
    local NO_RM=0

    echo "workspace_cleanup_by_age: '$BUILD_DIR' '$TRIAL_RUN'"

    if [ "$BUILD_DIR" == "" ]; then
        >&2 echo "requied arguement '$BUILD_DIR' is missing"
        return 1
    fi

    if [ ! -d "$BUILD_DIR" ]; then
        >&2 echo "invalid directory, '$BUILD_DIR'"
        return 1
    fi

    if [[ "$BUILD_DIR" != /localdisk/loadbuild/jenkins/* ]]; then
        >&2 echo "invalid directory, '$BUILD_DIR' does not start with '/localdisk/loadbuild/jenkins/'"
        return 1
    fi

    if [[ $BUILD_DIR != $JENKINS_LOADS/* ]]; then
        >&2 echo "directory '$BUILD_DIR' does not start with '$JENKINS_LOADS'"
        return 1
    fi

    cd $BUILD_DIR
    if [ $? -ne 0 ]; then
        >&2 echo "fail to 'cd $BUILD_DIR'"
        return 1
    fi

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    if [ -f "$SD" ]; then
        source "$SD"
    fi

    echo "SAVE_DAYS_GREEN=$SAVE_DAYS_GREEN"
    echo "SAVE_DAYS_YELLOW=$SAVE_DAYS_YELLOW"
    echo "SAVE_DAYS_RED=$SAVE_DAYS_RED"
    echo "SAVE_DAYS_UNKNOWN=$SAVE_DAYS_UNKNOWN"
    echo "SAVE_MIN_KEEP=$SAVE_MIN_KEEP"
    echo "TRIAL_RUN=$TRIAL_RUN"

    dirs=$(ls -dr1 $WILD)

    for d in $dirs; do
       echo "Considering '$d'"
       echo "   test_deletable '$d' '$num_keep' '$DIR_TYPE' 'publish_dir/$d/outputs/' 'publish_dir'"
       test_deletable "$d" "$num_keep" "$DIR_TYPE" "publish_dir/$d/outputs/" "publish_dir"
       if [ $? -eq 0 ]; then
           echo "Delete: $d"
           NO_RM=0
           if [ -f /usr/bin/mock ]; then
              for cfg in $(ls -1 $(pwd)/$d/*/configs/$USR-*/$USR-*.b[0-9].cfg 2>> /dev/null) \
                         $(ls -1 $(pwd)/$d/*/$USR-*.cfg 2>> /dev/null) \
                         $(ls -1 $(pwd)/$d/$USR-*.cfg 2>> /dev/null)
              do
                 local base_dir=""
                 local root_rel=""
                 local cache_topdir=""
                 local root_topdir=""

                 base_dir=$(grep "^config_opts[[][']basedir['][]]" $cfg | cut -d '=' -f 2- | cut -d "'" -f 2)
                 if [ "$base_dir" == "" ]; then
                     base_dir=/var/lib/mock
                 fi

                 root_rel=$(grep "^config_opts[[][']root['][]]" $cfg | cut -d '=' -f 2- | cut -d "'" -f 2)
                 if [ "$root_rel" == "" ]; then
                     root_rel="mock"
                 fi

                 cache_topdir=$(grep "^config_opts[[][']cache_topdir['][]]" $cfg | cut -d '=' -f 2- | cut -d "'" -f 2)
                 if [ "$cache_topdir" == "" ]; then
                     cache_topdir="/var/cache/mock/$(basename $(dirname $base_dir))"
                     if [ ! -x cache_topdir ]; then
                         cache_topdir="/var/cache/mock/$(echo $root_rel | sed 's#/mock$#/cache#')"
                     fi
                 fi

                 root_topdir="$base_dir/$root_rel"

                 echo "base_dir=$base_dir"
                 echo "cache_topdir=$cache_topdir"
                 echo "root_rel=$root_rel"
                 echo "root_topdir=$root_topdir"

                 if [ -d "$root_topdir" ] || [ -d "$cache_topdir/mock" ]; then
                    (
                    cd $(dirname $cfg)
                    echo "/usr/bin/mock -r $cfg --clean --scrub=all"
                    if [ $TRIAL_RUN -ne 1 ]; then
                        /usr/bin/mock -r $cfg --clean --scrub=all
                    fi
                    ) 

                    if [ -d "$root_topdir" ] || [ $(find $cache_topdir/mock -type d -user root | wc -l) -gt 0 ]; then
                       NO_RM=1
                       continue
                    fi

                    LNK="/var/lib/mock/$(basename $cfg | sed 's/.cfg$//')"
                    if [ -L $LNK ]; then
                       echo "rm -f $LNK"
                       if [ $TRIAL_RUN -ne 1 ]; then
                           \rm -f $LNK
                       fi
                    fi

                    LNK="/var/cache/mock/$(basename $cfg | sed 's/.cfg$//')"
                    if [ -L $LNK ]; then
                       echo "rm -f $LNK"
                       if [ $TRIAL_RUN -ne 1 ]; then
                           \rm -f $LNK
                       fi
                    fi
                 fi
              done
           fi

           if [ -d $d/aptly ]; then
              echo "deleting $PWD/$d/aptly"
              jenkins_rm root $PWD/$d/aptly
           fi

           if [ -d $d/docker ]; then
              echo "deleting $PWD/$d/docker"
              jenkins_rm root $PWD/$d/docker
           fi

           if [ -d $d/localdisk/deploy/ostree_repo ]; then
              echo "deleting $PWD/$d/localdisk/deploy/ostree_repo"
              jenkins_rm root $PWD/$d/localdisk/deploy/ostree_repo
           fi

           if [ -d $d/localdisk/sub_workdir ]; then
              echo "deleting $PWD/$d/localdisk/sub_workdir"
              jenkins_rm root $PWD/$d/localdisk/sub_workdir
           fi

           if [ -d $d/localdisk/log ]; then
              echo "deleting $PWD/$d/localdisk/log"
              jenkins_rm root $PWD/$d/localdisk/log
           fi

           if [ -d $d/std/mock ]; then
              echo "deleting $PWD/$d/std/mock "
              jenkins_rm root $PWD/$d/std/mock 
           fi

           if [ -d $d/std/cache ]; then
              echo "deleting $PWD/$d/std/cache "
              jenkins_rm root $PWD/$d/std/cache 
           fi

           if [ -d $d/rt/mock ]; then
              echo "deleting $PWD/$d/rt/mock "
              jenkins_rm root $PWD/$d/rt/mock 
           fi

           if [ -d $d/rt/cache ]; then
              echo "deleting $PWD/$d/rt/cache "
              jenkins_rm root $PWD/$d/rt/cache 
           fi

           if [ -d $d/installer/mock ]; then
              echo "deleting $PWD/$d/installer/mock "
              jenkins_rm root $PWD/$d/installer/mock 
           fi

           if [ -d $d/installer/cache ]; then
              echo "deleting $PWD/$d/installer/cache "
              jenkins_rm root $PWD/$d/installer/cache 
           fi

           if [ -d $d/containers/mock ]; then
              echo "deleting $PWD/$d/containers/mock "
              jenkins_rm root $PWD/$d/containers/mock 
           fi

           if [ -d $d/containers/cache ]; then
              echo "deleting $PWD/$d/containers/cache "
              jenkins_rm root $PWD/$d/containers/cache 
           fi

           if [ -d $d/localdisk/CERTS ]; then
              echo "deleting $PWD/$d/localdisk/CERTS"
              jenkins_rm root $PWD/$d/localdisk/CERTS
           fi

	   for d2 in $(find $d/localdisk -mindepth 1 -maxdepth 1 -type d); do
              echo "deleting $PWD/$d2"
              jenkins_rm root $PWD/$d2
           done

           if [ $NO_RM -ne 1 ]; then
              echo "nice -n 20 ionice -c Idle rm -rf $d"
              if [ $TRIAL_RUN -ne 1 ]; then
                  nice -n 20 ionice -c Idle \rm -rf "$d"
              fi
           fi
       else
           num_keep=$(($num_keep + 1))
           echo "Keep: $d"
       fi
       echo "----------------"
    done
}


function delete_old_master_builds_and_publications {
    local TRIAL_RUN=$1
    local DIR

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    for DIR in $(find $(find $WORKSPACE_BASE/ -maxdepth 1 -type d \( -name 'master*' -o -name 'debian-master*' \) ) -maxdepth 3 -name SAVE_DATA -exec dirname {} \; ); do
        workspace_cleanup_by_age $DIR $TRIAL_RUN
    done
    for DIR in $(find $(find $PUBLISHED_BASE/ -maxdepth 1 -type d -name 'master' ) -maxdepth 4 -name SAVE_DATA -exec dirname {} \; ); do
        published_build_cleanup_by_age $DIR $TRIAL_RUN
    done

    return 0
}

function delete_old_ussuri_builds_and_publications {
    local TRIAL_RUN=$1
    local DIR
    local BASE_DIR

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    for BASE_DIR in $(find $WORKSPACE_BASE/ -maxdepth 1 -type d -name 'ussuri*' ); do
        for DIR in $(find ${BASE_DIR} -maxdepth 3 -name SAVE_DATA -exec dirname {} \; ); do
            workspace_cleanup_by_age $DIR $TRIAL_RUN
        done
    done
    for BASE_DIR in $(find $PUBLISHED_BASE/ -maxdepth 1 -type d -name 'ussuri' ); do
        for DIR in $(find ${BASE_DIR} -maxdepth 4 -name SAVE_DATA -exec dirname {} \; ); do
            published_build_cleanup_by_age $DIR $TRIAL_RUN
        done
    done

    return 0
}

function delete_old_feature_builds_and_publications {
    local TRIAL_RUN=$1
    local DIR

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    for DIR in $(find $(find $WORKSPACE_BASE/ -maxdepth 1 -type d -name 'f-*') -maxdepth 3 -name SAVE_DATA -exec dirname {} \; ); do
        workspace_cleanup_by_age $DIR $TRIAL_RUN
    done
    for DIR in $(find $(find $PUBLISHED_BASE/ -maxdepth 1 -type d -name 'feature') -maxdepth 4 -name SAVE_DATA -exec dirname {} \; ); do
        published_build_cleanup_by_age $DIR $TRIAL_RUN
    done

    return 0
}

function delete_old_release_candidates_builds_and_publications {
    local TRIAL_RUN=$1
    local DIR

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    for DIR in $(find $(find $WORKSPACE_BASE/ -maxdepth 1 -type d \( -name 'rc-*' -o -name 'debian-rc-*' \) ) -maxdepth 3 -name SAVE_DATA -exec dirname {} \; ); do
        workspace_cleanup_by_age $DIR $TRIAL_RUN
    done
    for DIR in $(find $(find $PUBLISHED_BASE/ -maxdepth 1 -type d -name rc ) -maxdepth 4 -name SAVE_DATA -exec dirname {} \; ); do
        published_build_cleanup_by_age $DIR $TRIAL_RUN
    done

    return 0
}

function delete_old_release_and_milestone_builds_and_publications {
    local TRIAL_RUN=$1
    local d
    local dates
    local delete_dates
    local delete_date
    local delete_dirs
    local delete_dir
    local m_dates
    local m_delete_dates
    local m_delete_date
    local m_delete_dirs
    local m_delete_dir
    local DIR

    if [ -z $TRIAL_RUN ]; then
        TRIAL_RUN=0
    elif [ "$TRIAL_RUN" == "t" ] || [ "$TRIAL_RUN" == "T" ] || [ "$TRIAL_RUN" == "true" ] || [ "$TRIAL_RUN" == "TRUE" ]; then
        TRIAL_RUN=1
    fi

    dates=$(cd $PUBLISHED_RELEASE_BASE; \
            ls -d *${YYYY_MM_PATTERN}*  | \
                sed -r 's#^'${NOT_NUM}'*('${YYYY_MM_PATTERN}').*$#\1#' | \
                sort --unique
           )
    delete_dates=$(echo $dates | rev | cut -d ' ' -f ${FIRST_DELETE_RELEASE}- | rev)
    delete_dirs=$(for DIR in $delete_dates; do
                      (
                      cd $PUBLISHED_RELEASE_BASE
                      ls -d *$DIR*
                      )
                  done
                 )
    m_dates=$(cd $PUBLISHED_MILESTONE_BASE; \
              ls -d *${YYYY_MM_PATTERN}${MILESTONE_PATTERN}*  | \
                  sed -r 's#^'${NOT_NUM}'*('${YYYY_MM_PATTERN}')('${MILESTONE_PATTERN}'+)$#\1#' | \
                  sort --unique
             )
    m_delete_dates=$(for delete_date in $delete_dates; do
                         for m_date in $m_dates; do
                             if [ "$m_date" == "$delete_date" ]; then
                                 echo $m_date
                             elif [[ "$m_date" < "$delete_date" ]]; then
                                 echo $m_date
                             fi
                         done
                     done | sort --unique
                    )
    m_delete_dirs=$(for DIR in $m_delete_dates; do
                        (
                        cd $PUBLISHED_MILESTONE_BASE
                        ls -d *$DIR*
                        )
                    done
                   )

    # Delete milestone build workspace
    for m_delete_date in $delete_dates; do
        for DIR in $(find $WORKSPACE_BASE/ -maxdepth 1 -type d -name "m-$m_delete_date*" ); do
            echo "delete_dates: nice -n 20 ionice -c Idle rm -rf $DIR"
            if [ $TRIAL_RUN -ne 1 ]; then
                nice -n 20 ionice -c Idle \rm -rf "$DIR"
            fi
        done
    done

    # Delete milestone publication dir and docker images
    for m_delete_dir in $m_delete_dirs; do
        DIR=$PUBLISHED_MILESTONE_BASE/$m_delete_dir

        echo "delete_still_publised_images '$PUBLISHED_MILESTONE_BASE' '$m_delete_dir'"
        delete_still_publised_images "$PUBLISHED_MILESTONE_BASE" "$m_delete_dir" $TRIAL_RUN

        echo "m_delete_dirs: nice -n 20 ionice -c Idle rm -rf $DIR"
        if [ $TRIAL_RUN -ne 1 ]; then
            nice -n 20 ionice -c Idle \rm -rf "$DIR"
        fi
    done

    # Delete release build workspace
    for delete_date in $delete_dates; do
        for DIR in $(find $WORKSPACE_BASE/ -maxdepth 1 -type d -name "r-$delete_date*" ); do
            echo "delete_dates: nice -n 20 ionice -c Idle rm -rf $DIR"
            if [ $TRIAL_RUN -ne 1 ]; then
                nice -n 20 ionice -c Idle \rm -rf "$DIR"
            fi
        done
    done

    # Delete release publication dir and docker images
    for delete_dir in $delete_dirs; do
        DIR=$PUBLISHED_RELEASE_BASE/$delete_dir

        echo "delete_still_publised_images '$PUBLISHED_RELEASE_BASE' '$delete_dir'"
        delete_still_publised_images "$PUBLISHED_RELEASE_BASE" "$delete_dir" $TRIAL_RUN

        echo "delete_dirs: nice -n 20 ionice -c Idle rm -rf $DIR"
        if [ $TRIAL_RUN -ne 1 ]; then
            nice -n 20 ionice -c Idle \rm -rf "$DIR"
        fi
    done
}


usage() {
    echo "$0 [-m] "
    echo ""
    echo "Options:"
    echo "  -f: delete feature builds"
    echo "  -m: delete master builds"
    echo "  -c: delete release candidate builds"
    echo "  -t: trial run"
    echo "  -h: help"
}

DELETE_MASTER=0
DELETE_FEATURES=0
DELETE_RELEASE_CANDIDATES=0
TRIAL=0
while getopts "fmcth" o; do
    case "${o}" in
        c)
            DELETE_RELEASE_CANDIDATES=1
            ;;
        f)
            DELETE_FEATURES=1
            ;;
        m)
            DELETE_MASTER=1
            ;;
        t)
            TRIAL=1
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [ $DELETE_MASTER -eq 1 ]; then
    delete_old_master_builds_and_publications $TRIAL
    delete_old_ussuri_builds_and_publications $TRIAL
fi
if [ $DELETE_FEATURES -eq 1 ]; then
    delete_old_feature_builds_and_publications $TRIAL
fi
if [ $DELETE_RELEASE_CANDIDATES -eq 1 ]; then
    delete_old_release_candidates_builds_and_publications $TRIAL
fi
