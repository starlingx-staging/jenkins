#!/bin/bash

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

SOURCE_LIST=$(find $SOURCES_LIST_DIR -name "$SOURCES_LIST_TEMPLATE")

usage () {
    echo "debian_repo_sync.sh [ --source-file=<path> ] [ --release-filter=<filter> ] [ --section-filter=<filter>]"
    echo "                    [ --retry=N ] [ --dry-run ]"
    exit 0
}

TEMP=$(getopt -o h --long help,source-file:,release-filter:,section-filter:,retry:,dry-run -n "$(basename "$0")" -- "$@")
if [ $? -ne 0 ]; then
    echo "getopt error"
    usage
    exit 1
fi
eval set -- "$TEMP"

RELEASE_FILTER=""
SECTION_FILTER=""

while true ; do
    case "$1" in
        --source-file)    SOURCE_LIST="$2" ; shift 2 ;;
        --release-filter) RELEASE_FILTER="$2" ; shift 2 ;;
        --section-filter) SECTION_FILTER="$2" ; shift 2 ;;
        --dry-run)        DRY_RUN_ARG="--dry-run" ; shift ;;
        --retry)          RETRY_COUNT="$2" ; shift 2 ;;
        -h|--help)        echo "help"; usage; exit 0 ;;
        --)               shift ; break ;;
        *)                usage; exit 1 ;;
    esac
done


for source_file in $SOURCE_LIST; do
    echo "Processing file: $source_file"

    cat $source_file | sed 's/#.*//' | grep -v '^$' | \
    while read -r line
    do
        arr=($line)

        server=${arr[$SERVER]}
        method=${arr[$METHOD]}
        arch=${arr[$ARCH]}
        release=${arr[$RELEASE]}
        section=${arr[$SECTION]}

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

        source_arg=""
        case ${arr[$SOURCE]} in
            yes | YES | y | Y | src | SRC)
                source_arg="--source"
                ;;
            no | NO | n | N | no-src | NO-SRC)
                source_arg="--no-source"
                ;;
            *)
                echo "Error: Unexpected source arguement '${arr[$SOURCE]}', seen in line ..."
                echo "       ${liine}"
                exit 1
                ;;
        esac

        inPath=${arr[$IN_PATH]}

        outPath=${DEB_ROOT}/${server}/$inPath

        official=0
        if [[ ${server} =~ [.]debian[.]org$ ]]; then
            official=1
        fi

        if [ ${official} -eq 1 ]; then
            outPath=${DEB_ROOT}/debian/${server}/${inPath}
        fi

        if [ "${outPath}" != "${arr[$OUT_PATH]}" ]; then
            echo "Error: out path mismatch"
            echo "    ${outPath}"
            echo "    ${arr[$OUT_PATH]}"
            exit 1
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
done
