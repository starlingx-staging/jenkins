#!/bin/bash
# vim: ts=4 sts=4 sw=4 et

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Utilities to assist in interacting with Docker Hub
#

DEFAULT_REGISTRY="registry.hub.docker.com"
DEFAULT_IMAGE_REPOSITORY="docker.io"
DEFAULT_IMAGE_API_HOST="hub.docker.com"
DEFAULT_ORGANIZATION="starlingx"
DEFAULT_USERNAME="slittlewrs"

get_project_tags() {
    local REGISTRY=$1
    local PROJECT=$2
    local ORGANIZATION=$3

    if [ -z "$REGISTRY" ]; then
        >&2 echo "get_project_tags: REGISTRY not provided"
        return 1
    fi
    
    if [ -z "$PROJECT" ]; then
        >&2 echo "get_project_tags: PROJECT not provided"
        return 1
    fi

    if [ -z "$ORGANIZATION" ]; then
        URL="https://$REGISTRY/v2/repositories/$PROJECT/tags"
    else
        URL="https://$REGISTRY/v2/repositories/$ORGANIZATION/$PROJECT/tags"
    fi

    __get_project_tags  "$URL"
    
}
__get_project_tags() {
    local url="$1"
    local json

    echo ">>> $url" >&2
    json="$(wget -q -O - "$url")"

    # success
    if [[ $? -eq 0 && -n "$json" ]] ; then
        echo -n "$json" | python2 -c '
import sys, json
y=json.loads(sys.stdin.read())
if y and y.get("next"):
    print("next %s" % y.get("next"))
if y and y.get("results"):
    for res in y.get("results"):
        if res.get("name"):
            print("%s" % res.get("name"))
' \
        | while read key value; do
            if [ "${key}" = "next" ]; then
                __get_project_tags "$value"
                status=$?
                if [[ $status -ne 0 ]] ; then
                    exit $status
                fi
            else
                echo "${key}"
            fi
        done
        return 0
    fi

    echo "get_project_tags: failed to retrieve tags from $url" >&2
    return 1
}

extract_published_images_from_logs () {
    LOGS=("$@")

    if [ ${#LOGS[@]} -eq 0 ]; then
        >&2 echo "extract_published_images_from_log: no logs provided"
        return 1
    fi
    
    for LOG in "${LOGS[@]}"; do
        # echo $LOG
        if [ ! -f "$LOG" ]; then
            >&2 echo "extract_published_images_from_log: file not found '$LOG'"
            return 1
        fi

        cat "${LOG}" | sed -ne  '/^The following tags were pushed/{ :a; n; p; ba; }' | tac | sed -ne  '/^Sending e-mails to:/{ :a; n; p; ba; }' | tac
        cat "${LOG}" | sed -ne  '/^The following tags were pushed/{ :a; n; p; ba; }' | tac | sed -ne  '/^No emails were triggered./{ :a; n; p; ba; }' | tac | grep -v 'Sending e-mails'
        grep --no-filename -e '^Pushing image: ' -e '^[[][0-9A-Z .:-]\+[]] Pushing image: ' "${LOG}" | sed 's/^.* Pushing image: //'
    done | sort --unique
    return 0
}

extract_published_images_from_lsts () {
    LSTS=("$@")

    if [ ${#LSTS[@]} -eq 0 ]; then
        >&2 echo "extract_published_images_from_lst: no lsts provided"
        return 1
    fi

    for LST in "${LSTS[@]}"; do
        # echo $LST
        if [ ! -f "$LST" ]; then
            >&2 echo "extract_published_images_from_lst: file not found '$LST'"
            return 1
        fi

        cat $LST
    done | sort --unique
    return 0
}

extract_non_latest_published_images_from_logs () {
    extract_published_images_from_logs "$@" | grep -v '[-]latest$' 
    return $?
}

extract_non_latest_published_images_from_lsts () {
    extract_published_images_from_lsts "$@" | grep -v '[-]latest$' 
    return $?
}

extract_non_latest_published_images_from_log_dir () {
    DIR="$1"

    if [ ! -d "$DIR" ]; then
        >&2 echo "extract_non_latest_published_images_from_log_dir: directory not found '$DIR'"
        return 1
    fi

    local -a log_files
    log_files=($(find $DIR -mindepth 1 -maxdepth 1 -xtype f \
           -name '*docker*image*.log' -o -name '*docker*image*.log.txt' \
        -o -name '*docker*base*.log' -o -name '*docker*base*.log.txt'))

    if [[ "${#log_files[@]}" -gt 0 ]] ; then
        extract_non_latest_published_images_from_logs "${log_files[@]}"
    fi
    return $?
}

extract_non_latest_published_images_from_lst_dir () {
    DIR="$1"

    if [ ! -d "$DIR" ]; then
        >&2 echo "extract_non_latest_published_images_from_lst_dir: directory not found '$DIR'"
        return 1
    fi

    extract_non_latest_published_images_from_lsts $(find $DIR -maxdepth 1 -name '*.lst')
    return $?
}

get_project_list_from_log_dir () {
    DIR="$1"

    if [ ! -d "$DIR" ]; then
        >&2 echo "get_project_list_from_log_dir: directory not found '$DIR'"
        return 1
    fi

    extract_non_latest_published_images_from_log_dir "$DIR" | rev | cut -d '/' -f 1 | rev | cut -d ':' -f 1
}

get_project_list_from_lst_dir () {
    DIR="$1"

    if [ ! -d "$DIR" ]; then
        >&2 echo "get_project_list_from_lst_dir: directory not found '$DIR'"
        return 1
    fi

    extract_non_latest_published_images_from_lst_dir "$DIR" | rev | cut -d '/' -f 1 | rev | cut -d ':' -f 1
}

get_latest_timestamp_from_base_dir () {
    local BASE_DIR="$1"

    if [ ! -d "$BASE_DIR" ]; then
        >&2 echo "get_timestamp_from_base_dir: directory not found '$BASE_DIR'"
        return 1
    fi

    local LNK="$BASE_DIR/latest_docker_image_build"

    if [ ! -L "$LNK" ]; then
        >&2 echo "get_timestamp_from_base_dir: symlink '$BASE_DIR/latest_docker_image_build' not found"
        return 1
    fi

    TIMESTAMP=$(readlink "$LNK" | rev | cut -d '/' -f 1 | rev)
    echo $TIMESTAMP
    return 0
}

get_project_list_from_build_dir () {
    local BASE_DIR="$1"
    local TIMESTAMP="$2"

    if [ ! -d "$BASE_DIR" ]; then
        >&2 echo "get_project_list_from_build_dir: directory not found '$BASE_DIR'"
        return 1
    fi

    local latest_timestamp=""
    latest_timestamp=$(get_latest_timestamp_from_base_dir "$BASE_DIR")
    if [ $? -ne 0 ]; then
        >&2 echo "get_project_list_from_build_dir: Failed to find docker build timestamp from '$BASE_DIR'"
        return 1
    fi

    local timestamp dir subdir
    for timestamp in $TIMESTAMP $latest_timestamp ; do
        local -a lst_dirs=("outputs/docker-images" "workspace/std/build-images" "std/build-images")
        for subdir in "${lst_dirs[@]}" ; do
            dir="$BASE_DIR/$timestamp/$subdir"
            if [[ -d "$dir" ]] ; then
                get_project_list_from_lst_dir "$dir"
            fi
        done

        local -a log_dirs=("logs")
        for subdir in "${log_dirs[@]}" ; do
            dir="$BASE_DIR/$timestamp/$subdir"
            if [[ -d "$dir" ]] ; then
                get_project_list_from_log_dir "$dir"
            fi
        done
    done
    return 0
}

get_still_publised_images () {
    local BASE_DIR="$1"
    local TIMESTAMP="$2"
    local PROJECT
    local TAG

    if [ -z "$BASE_DIR" ]; then
        >&2 echo "get_still_publised_images: BASE_DIR not given"
        return 1
    fi

    if [ ! -d "$BASE_DIR" ]; then
        >&2 echo "get_still_publised_images: directory not found '$BASE_DIR'"
        return 1
    fi

    if [ -z "$TIMESTAMP" ]; then
        TIMESTAMP=$(get_latest_timestamp_from_base_dir "$BASE_DIR")
    fi

    if [ -z "$TIMESTAMP" ]; then
        >&2 echo "get_still_publised_images: TIMESTAMP not given"
        return 1
    fi

    for PROJECT in $(get_project_list_from_build_dir "$BASE_DIR" $TIMESTAMP | sort --unique); do
        for TAG in $(get_project_tags "$DEFAULT_REGISTRY" "$PROJECT" "$DEFAULT_ORGANIZATION" | grep "$TIMESTAMP"); do
            echo "$PROJECT:$TAG"
        done
    done

    return 0
}

delete_tag () {
    local API_HOST="$1"
    local USERNAME="$2"
    local PASSWORD="$3"
    local ORGANIZATION="$4"
    local IMAGE="$5"
    local TAG="$6"

    if [ -z "$API_HOST" ]; then
        >&2 echo "delete_tag: API_HOST not given"
        return 1
    fi

    if [ -z "$USERNAME" ]; then
        >&2 echo "delete_tag: USERNAME not given"
        return 1
    fi

    if [ -z "$PASSWORD" ]; then
        >&2 echo "delete_tag: PASSWORD not given"
        return 1
    fi

    if [ -z "$ORGANIZATION" ]; then
        >&2 echo "delete_tag: ORGANIZATION not given"
        return 1
    fi

    if [ -z "$IMAGE" ]; then
        >&2 echo "delete_tag: IMAGE not given"
        return 1
    fi

    if [ -z "$TAG" ]; then
        >&2 echo "delete_tag: TAG not given"
        return 1
    fi

    local TOKEN=""
    TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'$USERNAME'", "password": "'$PASSWORD'"}' https://${API_HOST}/v2/users/login/ | jq -r .token)
    curl "https://${API_HOST}/v2/repositories/${ORGANIZATION}/${IMAGE}/tags/${TAG}/" -X DELETE -H "Authorization: JWT ${TOKEN}"
}

delete_still_publised_images () {
    local BASE_DIR="$1"
    local TIMESTAMP="$2"
    local TRIAL_RUN="$3"

    local IMAGE_TAG
    local IMAGE
    local TAG

    if [[ "$TRIAL_RUN" == 1 || "$TRIAL_RUN" == "t" || "$TRIAL_RUN" == "T" || "$TRIAL_RUN" == "true" || "$TRIAL_RUN" == "TRUE" ]] ; then
        TRIAL_RUN=1
    else
        TRIAL_RUN=0
    fi

    if [ -z "$BASE_DIR" ]; then
        >&2 echo "delete_still_publised_images: BASE_DIR not given"
        return 1
    fi

    if [ ! -d "$BASE_DIR" ]; then
        >&2 echo "delete_still_publised_images: directory not found '$BASE_DIR'"
        return 1
    fi

    if [ -z "$TIMESTAMP" ]; then
        >&2 echo "delete_still_publised_images: TIMESTAMP not given"
        return 1
    fi

    for IMAGE_TAG in $(get_still_publised_images "$BASE_DIR" "$TIMESTAMP"); do
        IMAGE=$(echo $IMAGE_TAG | cut -d ':' -f 1)
        TAG=$(echo $IMAGE_TAG | cut -d ':' -f 2)
        echo delete_tag "$DEFAULT_IMAGE_API_HOST" "$DEFAULT_USERNAME" "xxxxxxxx" "$DEFAULT_ORGANIZATION"  "$IMAGE" "$TAG"
        if [[ $TRIAL_RUN -ne 1 ]] ; then
            delete_tag "$DEFAULT_IMAGE_API_HOST" "$DEFAULT_USERNAME" "$(cat ~/docker_io_slittlewrs.cred)" "$DEFAULT_ORGANIZATION"  "$IMAGE" "$TAG"
        fi
    done
}

