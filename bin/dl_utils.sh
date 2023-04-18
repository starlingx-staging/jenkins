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

DL_UTILS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

if [ -f "$DL_UTILS_DIR/url_utils.sh" ]; then
    source "$DL_UTILS_DIR/url_utils.sh"
elif [ -f "$DL_UTILS_DIR/../url_utils.sh" ]; then
    source "$DL_UTILS_DIR/../url_utils.sh"
else
    echo "Error: Can't find 'url_utils.sh'"
    exit 1
fi


DOWNLOAD_PATH_ROOT=${DOWNLOAD_PATH_ROOT:-/export/mirror/centos}


dl_git_from_url () {
    local GIT_URL="$1"
    local BRANCH="$2"
    local DL_DIR="$3"
    local DL_ROOT_DIR=""
    local SAVE_DIR
    local CMD=""

    SAVE_DIR="$(pwd)"

    if [ "$DL_DIR" == "" ]; then
        DL_DIR="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$GIT_URL" | sed 's#[.]git$##')"
    fi

    echo "dl_git_from_url  GIT_URL='$GIT_URL'  BRANCH='$BRANCH'  DL_DIR='$DL_DIR'"
    DL_ROOT_DIR=$(dirname "$DL_DIR")

    if [ ! -d "$DL_DIR" ]; then
        if [ ! -d "$DL_ROOT_DIR" ]; then
            CMD="mkdir -p '$DL_ROOT_DIR'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                cd "$SAVE_DIR"
                return 1
            fi
        fi

        CMD="cd '$DL_ROOT_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi

        CMD="git clone '$GIT_URL' '$DL_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi
    fi

    CMD="cd '$DL_DIR'"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    CMD="git fetch"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    CMD="git checkout '$BRANCH'"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    CMD="git pull"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    cd "$SAVE_DIR"
    return 0
}


dl_bare_git_from_url () {
    local GIT_URL="$1"
    local BRANCH="$2"
    local DL_DIR="$3"
    local DL_ROOT_DIR=""
    local SAVE_DIR
    local CMD=""

    SAVE_DIR="$(pwd)"

    if [ "$DL_DIR" == "" ]; then
        DL_DIR="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$GIT_URL" | sed 's#[.]git$##')"
    fi

    echo "dl_bare_git_from_url  GIT_URL='$GIT_URL'  BRANCH='$BRANCH'  DL_DIR='$DL_DIR'"
    DL_ROOT_DIR=$(dirname "$DL_DIR")

    if [ ! -d "$DL_DIR" ]; then
        if [ ! -d "$DL_ROOT_DIR" ]; then
            CMD="mkdir -p '$DL_ROOT_DIR'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                cd "$SAVE_DIR"
                return 1
            fi
        fi

        CMD="cd '$DL_ROOT_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi

        CMD="git clone --bare '$GIT_URL' '$DL_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi

        CMD="cd '$DL_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi

        CMD="git --bare update-server-info"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi

        if [ -f hooks/post-update.sample ]; then
            CMD="mv -f hooks/post-update.sample hooks/post-update"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                cd "$SAVE_DIR"
                return 1
            fi
        fi
    fi

    CMD="cd '$DL_DIR'"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    CMD="git fetch"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    cd "$SAVE_DIR"
    return 0
}


dl_file_from_url () {
    local URL="$1"
    local DOWNLOAD_PATH=""
    local DOWNLOAD_DIR=""
    local PROTOCOL=""
    local CMD=""

    DOWNLOAD_PATH="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$URL")"
    DOWNLOAD_DIR="$(dirname "$DOWNLOAD_PATH")"
    PROTOCOL=$(url_protocol $URL)
    echo "$PROTOCOL  $URL  $DOWNLOAD_PATH"

    if [ -f "$DOWNLOAD_PATH" ]; then
        echo "Already have '$DOWNLOAD_PATH'"
        return 0
    fi

    case "$PROTOCOL" in
        https|http)
            if [ ! -d "$DOWNLOAD_DIR" ]; then
                CMD="mkdir -p '$DOWNLOAD_DIR'"
                echo "$CMD"
                eval "$CMD"
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    return 1
                fi
            fi

            CMD="wget '$URL' --tries=5 --wait=15 --output-document='$DOWNLOAD_PATH'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                return 1
            fi
            ;;
        *)
            echo "Error: Unknown protocol '$PROTOCOL' for url '$URL'"
            return 1
            ;;
    esac

    return 0
}


dl_repo_from_url () {
    local REPO_URL="$1"
    local BRANCH="$2"
    local DL_DIR="$3"
    local SAVE_DIR
    local CMD=""

    SAVE_DIR="$(pwd)"

    if [ "$DL_DIR" == "" ]; then
        DL_DIR="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$REPO_URL" | sed 's#[.]git$##')"
    fi

    echo "dl_repo_from_url  REPO_URL='$REPO_URL'  BRANCH='$BRANCH'  DL_DIR='$DL_DIR'"

    if [ ! -d "$DL_DIR" ]; then
        CMD="mkdir -p '$DL_DIR'"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi
    fi

    CMD="cd '$DL_DIR'"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    CMD="repo init -u '$REPO_URL' -b '$BRANCH'"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        echo "Error: $CMD"
        cd "$SAVE_DIR"
        return 1
    fi

    # Temporary hack for 'second reposync fails on yocto issue
    # https://bugs.chromium.org/p/gerrit/issues/detail?id=14700&q=tyranscooter&can=2
    # CMD="rm -rf .repo/project-objects/linux-yocto.git* .repo/projects/cgcs-root/stx/git/linux-yocto-*"
    # echo "$CMD"
    # eval $CMD

    CMD="repo sync --force-sync -j20"
    echo "$CMD"
    eval $CMD
    if [ $? -ne 0 ]; then
        CMD="repo sync --force-sync -j20 --no-clone-bundle"
        echo "$CMD"
        eval $CMD
        if [ $? -ne 0 ]; then
            echo "Error: $CMD"
            cd "$SAVE_DIR"
            return 1
        fi
        # echo "Error: $CMD"
        # cd "$SAVE_DIR"
        # return 1
    fi

    cd "$SAVE_DIR"
    return 0
}
