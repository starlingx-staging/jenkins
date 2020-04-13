#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Daily update script for mirror.starlingx.cengn.ca covering
# tarballs and other files not downloaded from a yum repository.
# This script was originated by Scott Little.
#

STX_TOOL_UTILS_LAYERED_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

if [ -f "$STX_TOOL_UTILS_LAYERED_DIR/dl_utils.sh" ]; then
    source "$STX_TOOL_UTILS_LAYERED_DIR/dl_utils.sh"
elif [ -f "$STX_TOOL_UTILS_LAYERED_DIR/../dl_utils.sh" ]; then
    source "$STX_TOOL_UTILS_LAYERED_DIR/../dl_utils.sh"
else
    echo "Error: Can't find 'dl_utils.sh'"
    exit 1
fi


STX_DEFAULT_BRANCH="master"
STX_DEFAULT_ROOT_DIR="$HOME/stx-repo"
STX_MANIFEST_GIT_URL="https://opendev.org/starlingx/manifest"

stx_clone_or_update () {
    local BRANCH="$1"
    local DL_ROOT_DIR="$2"
    local CMD

    if [ "$BRANCH" == "" ]; then
        BRANCH="$STX_DEFAULT_BRANCH"
    fi

    if [ "$DL_ROOT_DIR" == "" ]; then
       DL_ROOT_DIR="$STX_DEFAULT_ROOT_DIR/$BRANCH"
    fi

    dl_repo_from_url "$STX_MANIFEST_GIT_URL" "$BRANCH" "$DL_ROOT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download '$STX_MANIFEST_GIT_URL'"
        return 1;
    fi
    return 0
}

