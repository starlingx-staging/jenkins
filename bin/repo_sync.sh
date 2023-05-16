#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Daily update script for mirror.starlingx.cengn.ca covering
# rpms and src.rpms downloaded from a yum repository.
#
# Configuration files for repositories to be downloaded are currently
# stored at mirror.starlingx.cengn.ca:/export/config/yum.repos.d.
# Those repos were derived from stx-tools/centos-mirror-tools/yum.repos.d
# with some modifications that will need to be automated in a
# future update.
#

set -x

LOGFILE="/export/log/daily_repo_sync.log"
YUM_CONF_DIR="/export/config"
YUM_REPOS_DIR="$YUM_CONF_DIR/yum.repos.d"
DOWNLOAD_PATH_ROOT="/export/mirror/centos"

DAILY_REPO_SYNC_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

source_file () {
    local FILE=$1
    if [ -f "$DAILY_REPO_SYNC_DIR/$FILE" ]; then
        source "$DAILY_REPO_SYNC_DIR/$FILE"
    elif [ -f "$DAILY_REPO_SYNC_DIR/../$FILE" ]; then
        source "$DAILY_REPO_SYNC_DIR/../$FILE"
    else
        echo "Error: Can't find '$FILE'"
        exit 1
    fi
}

source_file "url_utils.sh"
source_file "yum_utils.sh"

CREATEREPO=$(which createrepo_c)
if [ $? -ne 0 ]; then
    CREATEREPO="createrepo"
fi

number_of_cpus () {
    /usr/bin/nproc
}

if [ -f $LOGFILE ]; then
    rm -f $LOGFILE
fi

ERR_COUNT=0
YUM_CONF="$YUM_CONF_DIR/yum.conf"
if [ ! -f "$YUM_CONF" ]; then
    echo "Error: Missing yum.conf file at '$YUM_CONF'"
    exit 1
fi

# for REPO in $(find $YUM_REPOS_DIR -name '*.repo'); do
#     for REPO_ID in $(grep '^[[]' $REPO | sed 's#[][]##g'); do
for REPO_ID in $(yum repolist --config=$YUM_CONF --quiet | tail -n +2 | cut -d ' ' -f 1); do

	REPO_URL=$(get_repo_url "$YUM_CONF" "$REPO_ID")
        DOWNLOAD_PATH="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$REPO_URL")"

#        echo "Processing: REPO=$REPO  REPO_ID=$REPO_ID  REPO_URL=$REPO_URL  DOWNLOAD_PATH=$DOWNLOAD_PATH"
        echo "Processing: REPO_ID=$REPO_ID  REPO_URL=$REPO_URL  DOWNLOAD_PATH=$DOWNLOAD_PATH"

        # Assume it's a repo of binary rpms unless repoid ends in
        # some variation of 'source'.
        SOURCE_FLAG=""
        echo "$REPO_ID" | grep -q '[-_][Ss]ource$' && SOURCE_FLAG="--source"
        echo "$REPO_ID" | grep -q '[-_][Ss]ources$' && SOURCE_FLAG="--source"
        echo "$REPO_ID" | grep -q '[-_][Ss]ource[-_]' && SOURCE_FLAG="--source"
        echo "$REPO_ID" | grep -q '[-_][Ss]ources[-_]' && SOURCE_FLAG="--source"

        if [ ! -d "$DOWNLOAD_PATH" ]; then
            CMD="mkdir -p '$DOWNLOAD_PATH'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi
        fi

        CMD="reposync --norepopath $SOURCE_FLAG -l --config=$YUM_CONF --repoid=$REPO_ID --download_path='$DOWNLOAD_PATH'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            ERR_COUNT=$((ERR_COUNT+1))
            continue
        fi

        CMD="pushd '$DOWNLOAD_PATH'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            ERR_COUNT=$((ERR_COUNT+1))
            continue
        fi

        OPTIONS="--workers $(number_of_cpus)"
        if [ -f comps.xml ]; then
            OPTIONS="$OPTIONS -g comps.xml"
        fi
        if [ -d repodata ]; then
            OPTIONS="$OPTIONS --update"
        fi

        CMD="$CREATEREPO $OPTIONS ."
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            ERR_COUNT=$((ERR_COUNT+1))
            popd
            continue
        fi

        popd
#     done
done | tee $LOGFILE

echo ERR_COUNT=$ERR_COUNT
if [ $ERR_COUNT -ne 0 ]; then
    exit 1
fi

exit 0
