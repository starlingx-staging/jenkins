#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Daily update script for mirror.starlingx.cengn.ca covering
# rpms and src.rpms downloaded from a yum repository.
#
# Configuration files for repositories to be downloaded are currently
# stored at mirror.starlingx.cengn.ca:/export/config/yum.repos.d.
# Those repos were derived from stx-tools/centos-mirror-tools/yum.repos.d
# with some modifications that will need to be automated in a
# future update.
#

set -x

REPO_SYNC_LAYERED_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"
export PATH=$PATH:$REPO_SYNC_LAYERED_DIR

LOGFILE="/export/log/daily_repo_sync.log"
YUM_CONF_DIR="/export/config"
YUM_CONF="${YUM_CONF_DIR}/yum.conf"
YUM_REPOS_DIR="${YUM_CONF_DIR}/yum.repos.d"
DOWNLOAD_PATH_ROOT="/export/mirror/centos"
URL_UTILS="url_utils.sh"
INI_UTILS="ini_utils.sh"
ERR_COUNT=0

DAILY_REPO_SYNC_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

source_file () {
    local FILE=$1
if [ -f "$DAILY_REPO_SYNC_DIR/$FILE" ]; then
    source "$DAILY_REPO_SYNC_DIR/$FILE"
elif [ -f "$DAILY_REPO_SYNC_DIR/../$FILE" ]; then
    source "$DAILY_REPO_SYNC_DIR/../$FILE"
else
    echo "Error: Can't find '$FILE'"
    exit 1
fi
}

source_file ${URL_UTILS}
source_file ${INI_UTILS}


CREATEREPO=$(which createrepo_c)
if [ $? -ne 0 ]; then
    CREATEREPO="createrepo"
fi

number_of_cpus () {
    /usr/bin/nproc
}

if [ -f $LOGFILE ]; then
    rm -f $LOGFILE
fi

get_remote_dir () {
    local url="${1}"
    local dest_dir="${2}"
    mkdir -p "${dest_dir}" || return 1
    \rm "${dest_dir}/"index.html*
    wget  -c -N -e robots=off --recursive --no-parent --no-host-directories --no-directories --progress=dot:mega --directory-prefix="${dest_dir}" "${url}/"
}

get_remote_file () {
    local url="${1}"
    local dest_dir="${2}"
    mkdir -p "${dest_dir}" || return 1
    wget  -c -N --no-parent --no-host-directories --no-directories --progress=dot:mega --directory-prefix="${dest_dir}" "${url}"
}

get_remote_file_overwrite () {
    local url="${1}"
    local dest_dir="${2}"
    local dest_file="${dest_dir}/$(basename ${url})"
    mkdir -p "${dest_dir}" || return 1
    
    if [ -f "${dest_file}" ]; then
        \rm "${dest_file}"
    fi
    wget  -c -N --no-parent --no-host-directories --no-directories --progress=dot:mega --directory-prefix="${dest_dir}" "${url}"
}

clean_repodata () {
    local repodata="${1}"
    local f=""
    local f2=""

    if [ ! -f ${repodata}/repomd.xml ]; then
        echo "Error: clean_repodata: file not found: ${repodata}/repomd.xml"
        return 1
    fi

    for f in $(find ${repodata} -name '[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]*'); do
        f2=$(basename $f)
        if ! grep -q $f2 ${repodata}/repomd.xml; then
            \rm $f
        fi
    done
}

update_repodata () {
    local repo_url="${1}"
    local repodata_path="${2}"

    local repodata_url="${repo_url}/repodata"

    get_remote_file_overwrite "${repodata_url}/repomd.xml" "${repodata_path}/"
    if [ $? -ne 0 ]; then
        echo "Error: get_remote_file_overwrite ${repodata_url}/repomd.xml ${repodata_path}/"
        return 1
    fi

    for f in $( grep 'href=' ${repodata_path}/repomd.xml | sed -e 's#.*href="##' -e 's#".*##' ); do
        if [ ! -f "${repodata_path}/$f" ]; then
            get_remote_file_overwrite "${repo_url}/$f" "${repodata_path}/"
            if [ $? -ne 0 ]; then
                echo "Error: get_remote_file_overwrite ${repo_url}/$f}/"
                return 1
            fi
        fi
    done

    clean_repodata "${repodata_path}/"
    return 0
}

usage () {
    echo "repo_sync_layered.sh [ --repo-file-filter=<filter> ] [ --repo-id-filter=<filter>]"
    exit 0
}

TEMP=$(getopt -o h --long help,no-clean,repo-file-filter:,repo-id-filter: -n 'repo_sync_layered.sh' -- "$@")
if [ $? -ne 0 ]; then
    echo "getopt error"
    usage
    exit 1
fi
eval set -- "$TEMP"

REPO_FILE_FILTER=.
REPO_ID_FILTER=.
CLEAN=1

while true ; do
    case "$1" in
        --repo-file-filter)   REPO_FILE_FILTER=$2 ; shift 2 ;;
        --repo-id-filter)     REPO_ID_FILTER=$2 ; shift 2 ;;
        --no-clean)           CLEAN=0 ; shift ;;
        -h|--help)        echo "help"; usage; exit 0 ;;
        --)               shift ; break ;;
        *)                usage; exit 1 ;;
    esac
done

if [ ! -f "$YUM_CONF" ]; then
    echo "Error: Missing yum.conf file at '$YUM_CONF'"
    exit 1
fi

# dpanech: output of below block is redirected to $LOGFILE
{

YUM_CONF_TMP="$(mktemp ${YUM_CONF}.XXXXXX)"
TMP=$(echo ${YUM_CONF_TMP} | sed "s#^${YUM_CONF}.##")
FIND_TMP="find_${TMP}.lst"
YUM_REPOS_DIR_TMP="${YUM_REPOS_DIR}.${TMP}"
\cp ${YUM_CONF} ${YUM_CONF_TMP}
sed -i "s#^reposdir=.*#reposdir=${YUM_REPOS_DIR_TMP}#" ${YUM_CONF_TMP}
mkdir -p ${YUM_REPOS_DIR_TMP}

for REPO_FILE in $(find ${YUM_REPOS_DIR} -type f -name '*.repo' | grep "$REPO_FILE_FILTER" | sort); do
    \rm ${YUM_REPOS_DIR_TMP}/*.repo
    cp ${REPO_FILE} ${YUM_REPOS_DIR_TMP}

    # for REPO in $(find $YUM_REPOS_DIR -name '*.repo'); do
    #     for REPO_ID in $(grep '^[[]' $REPO | sed 's#[][]##g'); do
    # for REPO_ID in $(yum -v repolist all --noplugins --config=${YUM_CONF_TMP} --quiet | grep Repo-id | sed 's#^[^:]*: ##' | cut -d '/' -f 1 | grep "$REPO_ID_FILTER"); do
    for REPO_ID in $(ini_section_list "${REPO_FILE}" | grep "$REPO_ID_FILTER"); do

        ENABLED=$(ini_field "${REPO_FILE}" "${REPO_ID}" enabled)
        if [ $ENABLED -eq 0 ]; then
            echo "Skipping disabled repo '$REPO_ID'"
            continue
        fi

        # REPO_URL=$(yum repoinfo --config="${YUM_CONF_TMP}"  --disablerepo="*" --enablerepo="$REPO_ID" | grep Repo-baseurl | sed 's#^[^:]*: ##' )
        # REPO_URL=$(ini_field "${REPO_FILE}" "${REPO_ID}" baseurl | sed 's#^[^:]*://##' )
        REPO_URL=$(ini_field "${REPO_FILE}" "${REPO_ID}" baseurl | sed 's#$basearch#x86_64#')

        if [ "${REPO_URL}" == "" ]; then
            # echo "Error: yum repoinfo --config='${YUM_CONF_TMP}'  --disablerepo='*' --enablerepo='$REPO_ID'"
            echo "Error: ini_field '${REPO_FILE}' '${REPO_ID}' baseurl"
            ERR_COUNT=$((ERR_COUNT+1))
            continue
        fi

        DOWNLOAD_PATH="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$REPO_URL")"
        DOWNLOAD_PATH_NEW=${DOWNLOAD_PATH}.new
        DOWNLOAD_PATH_OLD=${DOWNLOAD_PATH}.old

        echo "Processing: REPO_ID=$REPO_ID  REPO_URL=$REPO_URL  DOWNLOAD_PATH=$DOWNLOAD_PATH"

        #
        # Alway audit cengn and updates.  Other stuff randomly audited say 1 out of 10 updates
        #
        if [[ "${DOWNLOAD_PATH_NEW}" == *"starlingx.cengn.ca"* ]] || [[ "${REPO_ID}" == *"updates"* ]] || [ "${REPO_ID_FILTER}" != "" ] || [ "${REPO_FILE_FILTER}" != "" ] || [ $(( ( RANDOM % 10 ) )) -eq 0 ]; then

            #
            # Update repo with audit.
            #

            # copy repo to a temp location
            \rm -rf ${DOWNLOAD_PATH_NEW}
            if [ -d ${DOWNLOAD_PATH} ]; then
                CMD="\cp --archive --link ${DOWNLOAD_PATH} ${DOWNLOAD_PATH_NEW}"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi

            #  Download latest repodata 
            update_repodata  "${REPO_URL}" "${DOWNLOAD_PATH_NEW}/repodata.upstream"

            #  Download latest rpm.lst
            get_remote_file_overwrite "${REPO_URL}/rpm.lst" "${DOWNLOAD_PATH_NEW}/"

            #
            # Delete rpms that are no longer valid
            #

            # Save active repodata as local
            if [ -d ${DOWNLOAD_PATH_NEW}/repodata ]; then
                CMD="\mv ${DOWNLOAD_PATH_NEW}/repodata ${DOWNLOAD_PATH_NEW}/repodata.local"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                continue
                fi
            fi

            # Make upstream repodata the active copy
            CMD="\mv ${DOWNLOAD_PATH_NEW}/repodata.upstream ${DOWNLOAD_PATH_NEW}/repodata"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi

            # delete any cached find data
            if [ -f "${FIND_TMP}" ]; then
                CMD="\rm -f ${FIND_TMP}"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi
    
            # Do the audit, delete anything broken
            LOOP_RC=0
            for f in $(verifytree-stx -a file://${DOWNLOAD_PATH_NEW} | grep ' FAILED$' | awk '{ print $2 }' | sed 's/^[0-9]*://'); do
                if [ ! -f "${FIND_TMP}" ]; then
                    # cache find data
                    CMD="find ${DOWNLOAD_PATH_NEW} -name '*.rpm' > ${FIND_TMP}"
                    echo "$CMD"
                    eval $CMD
                    if [ $? -ne 0 ]; then
                        echo "Error: $CMD"
                        ERR_COUNT=$((ERR_COUNT+1))
                        continue
                    fi
                fi

                for f_path in $(grep "/${f}.rpm$" ${FIND_TMP}); do
                    CMD="\rm -f ${f_path}"
                    echo "$CMD"
                    eval $CMD
                    if [ $? -ne 0 ]; then
                        echo "Error: $CMD"
                        ERR_COUNT=$((ERR_COUNT+1))
                        LOOP_RC=1
                        break
                    fi
                done
            done
            if [ $LOOP_RC -ne 0 ]; then
                continue
            fi

            # verifytree sometimes creates these files and failes to clean them
            \rm -rf __export_mirror_*.new

            # deactivate and restore upstream repo data
            CMD="\mv ${DOWNLOAD_PATH_NEW}/repodata ${DOWNLOAD_PATH_NEW}/repodata.upstream"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi

            # Restore our active repodata
            if [ -d ${DOWNLOAD_PATH_NEW}/repodata.local ]; then
                CMD="\mv ${DOWNLOAD_PATH_NEW}/repodata.local ${DOWNLOAD_PATH_NEW}/repodata"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi

            # Assume it's a repo of binary rpms unless repoid ends in
            # some variation of 'source'.
            SOURCE_FLAG=""
            echo "$REPO_ID" | grep -q '[-_][Ss]ource$' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ources$' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ource[-_]' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ources[-_]' && SOURCE_FLAG="--source"

            # Sync the repo's rpms
            CMD="reposync --tempcache --norepopath $SOURCE_FLAG -l --config=${YUM_CONF_TMP} --repoid=$REPO_ID --download_path='${DOWNLOAD_PATH_NEW}'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                echo "reposync result: failed on repoid=$REPO_ID download_path='$DOWNLOAD_PATH_NEW'"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi
            echo "reposync result: success on repoid=$REPO_ID download_path='$DOWNLOAD_PATH_NEW'"

            CMD="pushd '${DOWNLOAD_PATH_NEW}'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi

            # remove any half-complete repodata
            if [ -d "${DOWNLOAD_PATH_NEW}/.repodata" ]; then
                CMD="\rm -rf ${DOWNLOAD_PATH_NEW}/.repodata"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi

            # Update the repodata
            OPTIONS="--workers $(number_of_cpus)"
            if [ -f comps.xml ]; then
                OPTIONS="$OPTIONS -g comps.xml"
            fi
            if [ -d repodata ]; then
                OPTIONS="$OPTIONS --update"
            fi

            CMD="$CREATEREPO $OPTIONS ."
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                popd
                continue
            fi

            popd

            # Swap out the old copy of our repo
            if [ -d ${DOWNLOAD_PATH} ]; then
                CMD="\mv ${DOWNLOAD_PATH} ${DOWNLOAD_PATH_OLD}"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    \rm -rf ${DOWNLOAD_PATH_NEW}
                    continue
                fi
            fi

            # Swap in the updated repo
            CMD="\mv ${DOWNLOAD_PATH_NEW} ${DOWNLOAD_PATH}"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi

            # Delete the old repo
            if [ -d ${DOWNLOAD_PATH_OLD} ]; then
                CMD="\rm -rf ${DOWNLOAD_PATH_OLD}"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi

        else
            #
            # Update repo without audit
            #

            # Unaudited reposync can leave broken rpms if the download fails.
            # Safer to only use audited updates.
            continue

            # Assume it's a repo of binary rpms unless repoid ends in
            # some variation of 'source'.
            SOURCE_FLAG=""
            echo "$REPO_ID" | grep -q '[-_][Ss]ource$' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ources$' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ource[-_]' && SOURCE_FLAG="--source"
            echo "$REPO_ID" | grep -q '[-_][Ss]ources[-_]' && SOURCE_FLAG="--source"

            if [ ! -d "$DOWNLOAD_PATH" ]; then
                CMD="mkdir -p '$DOWNLOAD_PATH'"
                echo "$CMD"
                eval $CMD
                if [ $? -ne 0 ]; then
                    echo "Error: $CMD"
                    ERR_COUNT=$((ERR_COUNT+1))
                    continue
                fi
            fi

            CMD="reposync --norepopath $SOURCE_FLAG -l --config=$YUM_CONF --repoid=$REPO_ID --download_path='$DOWNLOAD_PATH'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                echo "reposync result: failed on repoid=$REPO_ID download_path='$DOWNLOAD_PATH'"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi
            echo "reposync result: success on repoid=$REPO_ID download_path='$DOWNLOAD_PATH'"

            CMD="pushd '$DOWNLOAD_PATH'"
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                continue
            fi

            OPTIONS="--workers $(number_of_cpus)"
            if [ -f comps.xml ]; then
                OPTIONS="$OPTIONS -g comps.xml"
            fi
            if [ -d repodata ]; then
                OPTIONS="$OPTIONS --update"
            fi

            CMD="$CREATEREPO $OPTIONS ."
            echo "$CMD"
            eval $CMD
            if [ $? -ne 0 ]; then
                echo "Error: $CMD"
                ERR_COUNT=$((ERR_COUNT+1))
                popd
                continue
            fi

            popd
        fi

    done

    # \rm ${YUM_REPOS_DIR_TMP}/*.repo

done

if [ $CLEAN -eq 1 ]; then
    if [ ! -z ${YUM_CONF_TMP} ] && [ -f ${YUM_CONF_TMP} ]; then
        \rm -f ${YUM_CONF_TMP}
    fi

    if [ ! -z ${YUM_REPOS_DIR_TMP} ] && [ -d ${YUM_REPOS_DIR_TMP} ]; then
        \rm -rf ${YUM_REPOS_DIR_TMP}
    fi
    
    if [ ! -z ${FIND_TMP} ] && [ -f ${FIND_TMP} ]; then
        \rm -f ${FIND_TMP}
    fi
fi

echo ERR_COUNT=$ERR_COUNT
if [ $ERR_COUNT -ne 0 ]; then
    exit 1
fi

exit 0

} 2>&1 | tee $LOGFILE

exit ${PIPESTATUS[0]}

