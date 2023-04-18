#!/bin/bash

usage () {
    echo "debian_packages.sh [--base=<dir>] [--release-<release>] [--section==<section>] [--arch=<arch>]"
}

TEMP=$(getopt -o h --long help,base:,release:,section:,arch: -n 'debian_packages.sh' -- "$@")
if [ $? -ne 0 ]; then
    echo "getopt error" 1>&2 
    usage
    exit 1
fi
eval set -- "$TEMP"

BASE_DIR="$PWD"
QUERY_ARCH="*"
QUERY_RELEASE="*"
QUERY_SECTION="*"

while true ; do
    case "$1" in
        --base)    BASE_DIR="$2" ; shift 2 ;;
        --arch)    QUERY_ARCH="$2" ; shift 2 ;;
        --release) QUERY_RELEASE="$2" ; shift 2 ;;
        --section) QUERY_SECTION="$2" ; shift 2 ;;
        -h|--help)        echo "help"; usage; exit 0 ;;
        --)               shift ; break ;;
        *)                usage; exit 1 ;;
    esac
done

if [ ! -d "$BASE_DIR/dists" ]; then
    echo "Error: invalid base directory" 1>&2 
    usage
    exit 1
fi

process_entry () {
    local file_path="$BASE_DIR/$FILE_PATH"
    local file_name=""
    local first=""
    local section=""

    if [ -f "$file_path" ]; then
        file_name="$(basename "$file_path")"
    else
        # if [ "${PACKAGE}" == "" ] || [ "${VERSION}" == "" ] || [ "${ARCH}" == "" ] || [ "${SECTION}" == "" ]; then
        if [ "${PACKAGE}" == "" ] || [ "${VERSION}" == "" ] || [ "${ARCH}" == "" ]; then
            echo "Error: Filename not given for package '${PACKAGE}' and insufficient info to find it any other way" 1>&2 
            return 1
        fi
        file_name="${PACKAGE}_${VERSION}_${ARCH}.deb"
        first="${file_name:0:1}"
        section="$QUERY_SECTION"
        if [ "$section" == "*" ] || [ ! -d $BASE_DIR/pool/${section} ]; then
            if [ "${SECTION}" == "" ]; then
                echo "Error: section not given for package '${PACKAGE}' and insufficient info to find it any other way" 1>&2 
                return 1
            fi
            section=$(echo $SECTION | cut -d '/' -f 1)
            if [ ! -d $BASE_DIR/pool/${section} ]; then
                echo "Error: diectory not found '$BASE_DIR/pool/${section}'" 1>&2 
                return 1
            fi
        fi

        echo "find $BASE_DIR/pool/${section}/${first}* -name ${file_name}"
        file_path=$(find $BASE_DIR/pool/${section}/${first}* -name ${file_name} | head -n 1)
        if [ "${file_path}" == "" ]; then
            echo "Error: failed to find '${file_name}' under '$BASE_DIR/pool/${section}/${first}*'" 1>&2 
            return 1
        fi
    fi

    echo "${file_path}"
}

for PACKAGE_FILE in $(find $BASE_DIR/dists/$QUERY_RELEASE/$QUERY_SECTION/*$QUERY_ARCH -maxdepth 1 -name Packages.gz); do
    # echo $PACKAGE_FILE
    zcat $PACKAGE_FILE | \
    while read -r line; do
        if [ "$line" == "" ] && [ "$PACKAGE" != "" ]; then
            process_entry
            PACKAGE=""
            SOURCE=""
            VERSION=""
            ARCH=""
            SECTION=""
            FILE_PATH=""
            continue
        fi
    
        field="$(echo "$line" | cut -d ':' -f 1)"
        value="$(echo "$line" | cut -d ':' -f 2- | sed 's#^ ##g')"
        case $field in
            Package) if [ "$PACKAGE" != "" ]; then
                         process_entry
                         PACKAGE=""
                         SOURCE=""
                         VERSION=""
                         ARCH=""
                         SECTION=""
                         FILE_PATH=""
                     fi
                     PACKAGE="$value"
                     ;;
            Source) SOURCE="$value"
                     ;;
            Version) VERSION="$value"
                     ;;
            Architecture) ARCH="$value"
                     ;;
            Section) SECTION="$value"
                     ;;
            Filename) FILE_PATH="$value"
                     ;;
        esac
    done
    
    if [ "$PACKAGE" != "" ]; then
         process_entry
    fi
done
