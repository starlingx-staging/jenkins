#!/bin/bash

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

get_project_tags () {
    REGISTRY=$1
    PROJECT=$2
    ORGANIZATION=$3

    if [ -z "$REGISTRY" ]; then
        >&2 echo "get_project_tags: REGISTRY not provided"
        return 1
    fi
    
    if [ -z "$PROJECT" ]; then
        >&2 echo "get_project_tags: PROJECT not provided"
        return 1
    fi
    
    if [ -z "$ORGANIZATION" ]; then
        URL="https://$REGISTRY/v1/repositories/$PROJECT/tags"
    else
        URL="https://$REGISTRY/v1/repositories/$ORGANIZATION/$PROJECT/tags"
    fi

    wget -q $URL -O -  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}'
    if [ ${PIPESTATUS[0]} -ne 0 ];then
        >&2 echo "get_project_tags: Bad URL='$URL'"
        return 1
    fi

    return 0
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
        grep --no-filename '^Pushing image: ' "${LOG}" | sed 's/^Pushing image: //'
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

    extract_non_latest_published_images_from_logs $(ls -1 $DIR/*docker*image*.log)
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

get_project_list_from_base_dir () {
    local BASE_DIR="$1"

    if [ ! -d "$BASE_DIR" ]; then
        >&2 echo "get_project_list_from_base_dir: directory not found '$BASE_DIR'"
        return 1
    fi

    local TIMESTAMP=""
    TIMESTAMP=$(get_latest_timestamp_from_base_dir "$BASE_DIR")
    if [ $? -ne 0 ]; then
        >&2 echo "get_project_list_from_base_dir: Failed to find docker build timestamp from '$BASE_DIR'"
        return 1
    fi

    get_project_list_from_lst_dir "$BASE_DIR/$TIMESTAMP/outputs/docker-images"
    # get_project_list_from_log_dir "$BASE_DIR/$TIMESTAMP/logs"
    return $?
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

    # for PROJECT in $( ( get_project_list_from_base_dir "$BASE_DIR"; get_project_list_from_log_dir "$BASE_DIR/$TIMESTAMP/logs" ) | sort --unique); do
    for PROJECT in $( ( get_project_list_from_base_dir "$BASE_DIR"; get_project_list_from_lst_dir "$BASE_DIR/$TIMESTAMP/outputs/docker-images" ) | sort --unique); do
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

    local IMAGE_TAG
    local IMAGE
    local TAG

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
        delete_tag "$DEFAULT_IMAGE_API_HOST" "$DEFAULT_USERNAME" "$(cat ~/docker_io_slittlewrs.cred)" "$DEFAULT_ORGANIZATION"  "$IMAGE" "$TAG"
    done
}

