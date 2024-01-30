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

SOURCE_LIST=$(find $SOURCES_LIST_DIR -name "$SOURCES_LIST_TEMPLATE")

usage () {
    echo "debian_repo_sync.sh [ --source-file=<path> ] [ --release-filter=<filter> ] "
    echo "                    [ --section-filter=<filter>] [ --arch-filter=<filter> ]"
    exit 0
}

TEMP=$(getopt -o h --long help,source-file:,release-filter:,section-filter:,arch_filter: -n 'repo_sync_layered.sh' -- "$@")
if [ $? -ne 0 ]; then
    echo "getopt error"
    usage
    exit 1
fi
eval set -- "$TEMP"

RELEASE_FILTER=""
SECTION_FILTER=""
ARCH_FILTER=""

while true ; do
    case "$1" in
        --source-file)    SOURCE_LIST="$2" ; shift 2 ;;
        --release-filter) RELEASE_FILTER="$2" ; shift 2 ;;
        --section-filter) SECTION_FILTER="$2" ; shift 2 ;;
        --arch-filter)    ARCH_FILTER="$2" ; shift 2 ;;
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
        if [[ ${server} =~ [.]debian[.]org$ || ${server} = "mirror.csclub.uwaterloo.ca" ]]; then
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

        releaseFile=$outPath/dists/$release/Release
        if [ ! -f $releaseFile ]; then
            continue
        fi

        releaseVersion=$(grep '^Version: ' $releaseFile | sed 's#Version: ##')
        releaseCodeName=$(grep '^Codename: ' $releaseFile | sed 's#Codename: ##')
        if [ "$releaseVersion" == "" ] || [ "releaseCodeName" == "" ]; then
            echo "ERROR: failed to extract Version and Codename from Release file '$releaseFile'"
            continue
        fi

        if [ "$release" != "$releaseCodeName" ]; then
            if ! [[ $release =~ ^$releaseCodeName/ ]]; then
                echo "ERROR: releaseCodeName=$releaseCodeName inconsistent with release=$release"
                continue
            fi
        fi

        releaseCN=$(echo $releaseCodeName | cut -d '-' -f 1)
        releaseCNExt="$(echo $releaseCodeName | cut -d '-' -f 2-)"
        releaseVer=$(echo $releaseVersion | cut -d '-' -f 1)
        releaseVerExt="$(echo $releaseVersion | cut -d '-' -f 2-)"
        # if [ "$releaseVerExt" != "" ] && [ "$releaseVerExt" == "$releaseCNExt" ]; then
        #     releaseVersioned=$(echo "$release" | sed "s#^$releaseCodeName#$releaseCodeName-$releaseVer#")
        # else
        #     releaseVersioned=$(echo "$release" | sed "s#^$releaseCodeName#$releaseCodeName-$releaseVersion#")
        # fi
        releaseVersioned=$releaseCodeName-$releaseVer
        # echo "mkdir -p $outPath/dists/$releaseVersioned"
        # mkdir -p $outPath/dists/$releaseVersioned
        echo "mkdir -p $outPath/$releaseVersioned/dists/$release"
        mkdir -p $outPath/$releaseVersioned/dists/$release
        if [ $? -ne 0 ]; then
            # echo "ERROR: mkdir -p $outPath/dists/$releaseVersioned"
            echo "ERROR: mkdir -p $outPath/$releaseVersioned/dists/$release"
            exit 1
        fi

        # echo "rsync -avu $outPath/dists/$release/ $outPath/dists/$releaseVersioned/"
        # rsync -avu $outPath/dists/$release/ $outPath/dists/$releaseVersioned/
        echo "rsync -avu $outPath/dists/$release/ $outPath/$releaseVersioned/dists/$release"
        rsync -avu $outPath/dists/$release/ $outPath/$releaseVersioned/dists/$release
        if [ $? -ne 0 ]; then
            # echo "ERROR: rsync -avu $outPath/dists/$release/ $outPath/dists/$releaseVersioned/"
            echo "ERROR: rsync -avu $outPath/dists/$release/ $outPath/$releaseVersioned/dists/$release"
            exit 1
        fi

        for d in pool project ; do
            if [ ! -L $outPath/$releaseVersioned/$d ]; then
                ln -sf ../$d $outPath/$releaseVersioned/$d
            fi
        done
    done
    RC=${PIPESTATUS[-1]}
    # RC 255 == section with no packages (yet)
    if [ $RC -ne 0 ] && [ $RC -ne 255 ]; then
        exit 1
    fi
done
