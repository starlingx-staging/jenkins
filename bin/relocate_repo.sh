#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Copy a mirrored repo to a new path.  
#
# Sometimes an upstream repo is moved to a new url.
# e.g. centos moves old releases from mirror.centos.org to 
# vault.centos.org.
#
# When this happen, It's a good idea to use this tool
# to replicate the repo before delivering an update
# to the .repo file in stx-tools.
#
# Supply as arguenments the old and new upstream url.
# The url's will be converted to file system paths within
# the mirror, and the copy is preformed using hard links to
# save space and download time.
#
# We leave the content at the old path to support older
# starlingx releases.
#


RELOCATE_REPO_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"
source "${RELOCATE_REPO_DIR}/url_utils.sh"

DOWNLOAD_PATH_ROOT=/export/mirror/centos

OLD_URL="$1"
NEW_URL="$2"

if [ -z "${OLD_URL}" ] || [ -z "${NEW_URL}" ]; then
    echo "ERROR: Need old and new urls"
    exit 1
fi

OLD_PATH="${DOWNLOAD_PATH_ROOT}/$(repo_url_to_sub_path "${OLD_URL}")"
NEW_PATH="${DOWNLOAD_PATH_ROOT}/$(repo_url_to_sub_path "${NEW_URL}")"

if [ ! -d "${OLD_PATH}" ]; then
    echo "ERROR: old path not found: ${OLD_PATH}"
    exit 1
fi

if [ -d "${NEW_PATH}" ]; then
    echo "ERROR: new path already exists: ${NEW_PATH}"
    exit 1
fi

replicate_directory_files_via_hard_link () {
    local old_root="$1"
    local new_root="$2"

    (
    cd "${old_root}"
    if [ $? -ne 0 ]; then
        echo "ERROR: failed to 'cd ${old_root}'"
        exit 1
    fi

    for f in $(find . -maxdepth 1 -type f); do
        ln "${old_root}/${f}" "${new_root}/${f}"
        if [ $? -ne 0 ]; then
            echo "ERROR: failed to 'ln ${old_root}/${f} ${new_root}/${f}'"
            exit 1
        fi
    done
    )
}

replicate_directory_structure () {
    local old_root="$1"
    local new_root="$2"

    (
    cd "${old_root}"
    if [ $? -ne 0 ]; then
        echo "ERROR: failed to 'cd ${old_root}'"
        exit 1
    fi

    mkdir -p "${new_root}"
    if [ $? -ne 0 ]; then
        echo "ERROR: failed to 'mkdir -p ${new_root}'"
        exit 1
    fi

    for d in $(find . -type d); do
        echo "copy subdir ${d}"

        mkdir -p "${new_root}/${d}"
        if [ $? -ne 0 ]; then
            echo "ERROR: failed to 'mkdir -p ${new_root}/${d}'"
            exit 1
        fi

        replicate_directory_files_via_hard_link "${old_root}/${d}" "${new_root}/${d}"
        if [ $? -ne 0 ]; then
            echo "ERROR: failed to 'replicate_directory_files_via_hard_link ${old_root}/${d} ${new_root}/${d}'"
            exit 1
        fi

    done
    )
}


replicate_directory_structure "${OLD_PATH}" "${NEW_PATH}"
if [ $? -ne 0 ]; then
    echo "failed to replicate ${OLD_PATH} into ${NEW_PATH}"
    echo
    exit 1
fi

echo "replicated ${OLD_PATH} into ${NEW_PATH}"
echo
