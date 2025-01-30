#!/bin/bash

DEBIAN_SNAPSHOT_SYNC_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

DEB_ROOT=/export/mirror/debian
SOURCES_LIST_DIR=/export/config/debian/
KEYRING_DIR=${SOURCES_LIST_DIR}/mirrorkeyring
export GNUPGHOME=${KEYRING_DIR}
SOURCES_LIST_TEMPLATE='*-sources.list'
SERVER=0
METHOD=1
ARCH=2
RELEASE=3
SECTION=4
IN_PATH=5
SOURCE=6
OUT_PATH=7
KEY=8
EXTRA_ARGS=9
DRY_RUN_ARG=
RETRY_COUNT=1

source $DEBIAN_SNAPSHOT_SYNC_DIR/dl_utils.sh

SOURCE_LIST=$(find $SOURCES_LIST_DIR -name "$SOURCES_LIST_TEMPLATE")

renice -n 10 -p $$
ionice -c 3 -p $$

usage () {
    echo "debian_repo_sync.sh [ --url=<url> ] [ --branch=<branch> ]"
    echo "                    [ --source-file=<path> ] [ --release-filter=<filter> ] [ --section-filter=<filter>]"
    echo "                    [ --arch-filter=<filter> ] [ --retry=N ] [ --dry-run ]"
    exit 0
}

TEMP=$(getopt -o h --long help,source-file:,release-filter:,section-filter:,arch-filter:,retry:,dry-run,url:,branch:,path: -n "$(basename "$0")" -- "$@")
if [ $? -ne 0 ]; then
    echo "getopt error"
    usage
    exit 1
fi
eval set -- "$TEMP"

RELEASE_FILTER=""
SECTION_FILTER=""
ARCH_FILTER=""
TOOLS_URL="https://opendev.org/starlingx/tools.git"
TOOLS_BRANCH="master"
DL_DIR="/localdisk/designer/$USER/debian-snapshot/$(echo "${TOOLS_URL}" | sed 's#^.*://##')"

while true ; do
    case "$1" in
        --source-file)    SOURCE_LIST="$2" ; shift 2 ;;
        --release-filter) RELEASE_FILTER="$2" ; shift 2 ;;
        --section-filter) SECTION_FILTER="$2" ; shift 2 ;;
        --arch-filter)    ARCH_FILTER="$2" ; shift 2 ;;
        --dry-run)        DRY_RUN_ARG="--dry-run" ; shift ;;
        --retry)          RETRY_COUNT="$2" ; shift 2 ;;
        --url)            TOOLS_URL="$2" ; shift 2 
                          DL_DIR="/localdisk/designer/$USER/debian-snapshot/$(echo "${TOOLS_URL}" | sed 's#^.*://##')"
                          ;;
        --branch)         TOOLS_BRANCH="$2" ; shift 2 ;;
        --path)           DL_DIR="$2" ; shift 2 ;;
        -h|--help)        echo "help"; usage; exit 0 ;;
        --)               shift ; break ;;
        *)                usage; exit 1 ;;
    esac
done


BASE_DIR="$(dirname "${DL_DIR}")"
if [ ! -d "${BASE_DIR}" ]; then
    mkdir -p "${BASE_DIR}"
    if [ $? -ne 0 ]; then
        echo "Failed to create working directory: dir=${BASE_DIR}"
        exit 1
    fi
fi

dl_git_from_url "${TOOLS_URL}" "${TOOLS_BRANCH}" "${DL_DIR}"
if [ $? -ne 0 ]; then
    echo "Failed to DL stx-tools git: url=${TOOLS_URL} branch=${TOOLS_BRANCH} path=${DL_DIR}"
    exit 1
fi

if [ ! -f "${DL_DIR}/stx.conf.sample" ]; then
    echo "Failed to find file: ${DL_DIR}/stx.conf.sample"
    exit 1
fi

SNAPSHOT_TS=$(grep "^debian_snapshot_timestamp =" ${DL_DIR}/stx.conf.sample | cut -d '=' -f 2 | sed 's#^[ ]*##')
if [ "%{SNAPSHOT_TS}" == "" ]; then
    "Failed to find 'debian_snapshot_timestamp' in '${DL_DIR}/stx.conf.sample'"
    exit 1
fi

SECURITY_SNAPSHOT_TS=$(grep "^debian_security_snapshot_timestamp =" ${DL_DIR}/stx.conf.sample | cut -d '=' -f 2 | sed 's#^[ ]*##')
if [ "%{SECURITY_SNAPSHOT_TS}" == "" ]; then
    "Failed to find 'debian_security_snapshot_timestamp' in '${DL_DIR}/stx.conf.sample'"
fi

DISTRIBUTION=$(grep "^debian_distribution =" ${DL_DIR}/stx.conf.sample | cut -d '=' -f 2 | sed 's#^[ ]*##')
if [ "%{SNAPSHOT_TS}" == "" ]; then
    "Failed to find 'debian_distribution' in '${DL_DIR}/stx.conf.sample'"
    exit 1
fi


echo "SNAPSHOT_TS=${SNAPSHOT_TS}"
echo "SECURITY_SNAPSHOT_TS=${SECURITY_SNAPSHOT_TS}"
echo "DISTRIBUTION=${DISTRIBUTION}"

key_update () {
    for i in {10..20}; do
        echo "DL keys for Debian $i"
        if wget https://ftp-master.debian.org/keys/archive-key-${i}.asc; then
            gpg --no-default-keyring --keyring trustedkeys.gpg --import archive-key-${i}.asc
        else
           break
        fi
        if wget https://ftp-master.debian.org/keys/archive-key-${i}-security.asc; then
            gpg --no-default-keyring --keyring trustedkeys.gpg --import archive-key-${i}-security.asc
        fi
    done
}

key_update

server="snapshot.debian.org"
method="https"
arch="amd64,arm64"
section="main,contrib,non-free"
source_arg="--source"

# for release in "${DISTRIBUTION}" "${DISTRIBUTION}-updates" "${DISTRIBUTION}-security"; do
for release in "${DISTRIBUTION}" "${DISTRIBUTION}-security"; do
    if [ "$ARCH_FILTER" != "" ]; then
        arch_list=()
        arch_filter_expr="$(echo "$ARCH_FILTER" | sed 's#[*]#.*#g')"
        for arch_word in ${arch/,/ } ; do
            if [[ "$arch_word" =~ ^${arch_filter_expr} ]] ; then
                arch_list+=("$arch_word")
                break
            fi
        done
        if [[ ${#arch_list[*]} -gt 0 ]] ; then
            echo "arch '$arch' matches filter"
            arch=$(IFS=, ; echo "${arch_list[@]}")
        else
            continue
        fi
    fi

    if [ "$RELEASE_FILTER" != "" ]; then
        RELEASE_FILTER="$(echo "$RELEASE_FILTER" | sed 's#[*]#.*#g')"
        if [[ $release =~ ^${RELEASE_FILTER}$ ]];then
            echo "release '$release' matches filter"
        else
            continue
        fi
    fi

    if [ "$SECTION_FILTER" != "" ]; then
        SECTION_FILTER="$(echo "$SECTION_FILTER" | sed 's#[*]#.*#g')"
        s_array=( \
            $( for s in $(echo $section | tr ',' ' '); do
                if [[ $s =~ ^${SECTION_FILTER}$ ]]; then
                    echo "$s"
                fi
            done )
            )
        section=$(echo ${s_array[@]} | tr ' ' ',')
        if [ "$section" != "" ]; then
            echo "section '$section' matches filter"
        else
            continue
        fi
    fi

    if [[ ${release} =~ -security$ ]]; then 
        if [ "${SECUTITY_SNAPSHOT_TS}" == "" ]; then
            echo "Skipping '${release}' because debian_security_snapshot_timestamp not specified"
            continue
	else
            inPath="archive/debian-security/${SECUTITY_SNAPSHOT_TS}"
	fi
    else
        inPath="archive/debian/${SNAPSHOT_TS}"
    fi

    outPath=${DEB_ROOT}/${server}/$inPath

    official=0
    if [[ ${server} =~ [.]debian[.]org$ || ${server} = "mirror.csclub.uwaterloo.ca" ]]; then
        official=1
    fi

    if [ ${official} -eq 1 ]; then
        outPath=${DEB_ROOT}/debian/${server}/${inPath}
    fi

    key_arg=""
    if [ "${arr[$KEY]}" != "" ] && [ "${arr[$KEY]}" != "-" ]; then
        key="${GNUPGHOME}/${arr[$KEY]}"
        if [ -f ${key} ]; then
            key_arg="--keyring=${key}"
        else
            echo "Error: Key not found '${key}', seen in line ..."
            echo "       ${liine}"
            exit 1
        fi
    fi

    extra_arg=""
    if [ "${arr[$EXTRA_ARGS]}" != "" ] && [ "${arr[$EXTRA_ARGS]}" != "-" ]; then
        extra_arg="$(echo "${arr[$EXTRA_ARGS]}" | tr ':' ' ')"
    fi

    RC=0
    for (( i=0; i < RETRY_COUNT; ++i )) ; do

        cmd="debmirror \
              $DRY_RUN_ARG \
              --host=$server \
              --method=$method \
              --arch=$arch \
              $source_arg \
              --dist=$release \
              --section=$section \
              --root=$inPath \
              --progress \
              --nocleanup \
              $key_arg \
              $extra_arg \
              $outPath \
            "
        echo "$cmd"
        $cmd
        RC=$?

        if [[ $RC -ne 0 ]] ; then
            echo "Error: Attempt=$i: Command: $cmd"
            echo "Error: RC: $RC"
            continue
        fi
        break
    done
    if [ $RC -ne 0 ]; then
        exit $RC
    fi
done
RC=${PIPESTATUS[-1]}
# RC 255 == section with no packages (yet)
if [ $RC -ne 0 ] && [ $RC -ne 255 ]; then
    exit 1
fi
