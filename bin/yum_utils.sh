#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Utilities for working with yum
#

YUM_UTILS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

get_reposdir () {
    local YUM_CONF="$1"
    local YUM_CONF_DIR=""
    local REPO_DIR=""

    if [ ! -f "$YUM_CONF" ]; then
        >&2 echo "ERROR: invalid file YUM_CONF='$YUM_CONF'"
        return 1
    fi

    YUM_CONF_DIR="$(readlink -f "$(dirname "$YUM_CONF")")"

    REPO_DIR=$(grep reposdir= "$YUM_CONF" | sed 's#reposdir=##' | tail -n 1)
    if [ "$REPO_DIR" = "" ]; then
        echo ""
        return 0
    fi

    if [ "${REPO_DIR:0:1}" != "/" ]; then
        REPO_DIR="$YUM_CONF_DIR/$REPO_DIR"
    fi

    readlink -f "$REPO_DIR"
}

get_repo_id_data () {
    local YUM_CONF="$1"
    local REPO_ID="$2"
    local URL=""
    local REPO_DIR=""
    local REPO_FILE=""
   
    REPO_DIR=$(get_reposdir "$YUM_CONF")
    if [ "$REPO_DIR" = "" ]; then
        >&2 echo "ERROR: get_reposdir '$YUM_CONF' failed"
        return 1
    fi

    REPO_FILE=$(grep -l "\[${REPO_ID}\]" "$REPO_DIR"/*.repo | head -n 1)
    if [ "$REPO_DIR" = "" ]; then
        >&2 echo "ERROR: ${REPO_ID} not found"
        return 1
    fi

    cat $REPO_FILE | awk "p; /^[[]${REPO_ID}[]]/{p=1}" | sed -n '/^[[]/q;p'
}

get_repo_url () {
    local YUM_CONF="$1"
    local REPO_ID="$2"
    local URL=""
    URL="$(get_repo_id_data "$YUM_CONF" "$REPO_ID" | grep baseurl= | sed 's#baseurl=##')"
    if [ $? != 0 ]; then
        >&2 echo "ERROR: get_repo_url '$YUM_CONF' '$REPO_ID'"
        return 1
    fi

    echo "$URL"
    return 0
}

get_repo_name () {
    local YUM_CONF="$1"
    local REPO_ID="$2"
    local NAME=""

    NAME="$(get_repo_id_data "$YUM_CONF" "$REPO_ID" | grep name= | sed 's#name=##')"
    if [ $? != 0 ]; then
        >&2 echo "ERROR: get_repo_name '$YUM_CONF' '$REPO_ID'"
        return 1
    fi

    echo "$NAME"
    return 0
}

