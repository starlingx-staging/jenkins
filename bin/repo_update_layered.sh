#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Transfer layered builds from the build side to the mirror side.
#
# Care must be taken to force re-download if rpms have been rebuilt
# without recieving a version update.
#

LOGFILE="/export/log/repo_update.log"
YUM_CONF_DIR="/export/config"
# YUM_CONF_DIR="/tmp/config"
YUM_CONF="$YUM_CONF_DIR/yum.conf"
YUM_REPOS_DIR="$YUM_CONF_DIR/yum.repos.d"
GPG_KEYS_DIR="$YUM_CONF_DIR/rpm-gpg-keys"
DOWNLOAD_PATH_ROOT=/export/mirror/centos
STX_BRANCH="master"
STX_REPO_ROOT="$HOME/stx-repo"
STX_TOOLS_ROOT_DIR="$STX_REPO_ROOT/stx-tools"
STX_TOOLS_OS_SUBDIR="centos-mirror-tools"


REPO_UPDATE_LAYERED_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"

if [ -f "$REPO_UPDATE_LAYERED_DIR/stx_tool_utils_layered.sh" ]; then
    source "$REPO_UPDATE_LAYERED_DIR/stx_tool_utils_layered.sh"
elif [ -f "$REPO_UPDATE_LAYERED_DIR/../stx_tool_utils_layered.sh" ]; then
    source "$REPO_UPDATE_LAYERED_DIR/../stx_tool_utils_layered.sh"
else
    >&2 echo "Error: Can't find 'stx_tool_utils_layered.sh'"
    exit 1
fi




usage () {
    echo "$0 [-b <branch>] [-d <dir>]"
    echo ""
    echo "Options:"
    echo "  -b: Use an alternate branch of stx-tools. Default is 'master'."
    echo "  -d: Directory where we will clone stx-tools. Default is \$HOME."
    echo ""
}

while getopts "b:d:h" opt; do
    case "${opt}" in
        b)
            # branch
            STX_BRANCH="${OPTARG}"
            if [ $"STX_BRANCH" == "" ]; then
                usage
                exit 1
            fi
            ;;
        d)
            # download directory for stx-tools
            STX_REPO_ROOT="${OPTARG}"
            if [ "$STX_REPO_ROOT" == "" ]; then
                usage
                exit 1
            fi
            ;;
        h)
            # Help
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done


STX_DL_ROOT_DIR="$STX_REPO_ROOT/$STX_BRANCH"
STX_TOOLS_DL_DIR="$STX_DL_ROOT_DIR/stx-tools"
UPSTREAM_YUM_CONF="$STX_TOOLS_DL_DIR/$STX_TOOLS_OS_SUBDIR/yum.conf.sample"
UPSTREAM_GPG_KEYS_DIR="$STX_TOOLS_DL_DIR/$STX_TOOLS_OS_SUBDIR/rpm-gpg-keys"


update_gpg_keys () {
    local UPSTREAM_KEY=""
    local KEY=""
    local UPSTREAM_CHECKSUM=""
    local CHECKSUM=""

    for UPSTREAM_KEY in $(find $UPSTREAM_GPG_KEYS_DIR -type f | sort ); do
        KEY=$GPG_KEYS_DIR/$(basename $UPSTREAM_KEY)
        if [ ! -f "$KEY" ]; then
            echo "Copy new key file '$UPSTREAM_KEY' to '$KEY'"
            \cp "$UPSTREAM_KEY" "$KEY"
            continue
        fi

        UPSTREAM_CHECKSUM=$(md5sum $UPSTREAM_KEY | cut -d ' ' -f 1)
        CHECKSUM=$(md5sum $KEY | cut -d ' ' -f 1)
        if [ "$UPSTREAM_CHECKSUM" == "$CHECKSUM" ]; then
            echo "Already have '$UPSTREAM_KEY'"
            continue
        fi

        # Key mismatch.  What to do?
        >&2 echo "Error: Key mismatch: '$UPSTREAM_KEY' vs '$KEY'"
        ERR_COUNT=$((ERR_COUNT + 1))
    done

    return 0
}

get_repo_url () {
    local YUM_CONF="$1"
    local REPO_ID="$2"
    local REPO_FILE="$3"
    local URL=""
    local EXTRA_ARGS=""

    if [ "${REPO_FILE}" != "" ]; then
        EXTRA_ARGS="--setopt reposdir=$(dirname $REPO_FILE)"
    fi
    URL=$(cd $(dirname $YUM_CONF);
          yum repoinfo --config="$YUM_CONF" ${EXTRA_ARGS} --disablerepo="*" --enablerepo="$REPO_ID" | \
              grep Repo-baseurl | \
              awk '{ print $3 }';
          exit ${PIPESTATUS[0]}
         )
    if [ $? != 0 ]; then
        >&2 echo "ERROR: yum repoinfo --config='$YUM_CONF' --disablerepo='*' --enablerepo='$REPO_ID'"
        return 1
    fi

    echo "$URL"
    return 0
}

get_repo_name () {
    local YUM_CONF="$1"
    local REPO_ID="$2"
    local REPO_FILE="$3"
    local NAME=""
    local EXTRA_ARGS=""

    if [ "${REPO_FILE}" != "" ]; then
        EXTRA_ARGS="--setopt reposdir=$(dirname $REPO_FILE)"
    fi
    NAME=$(cd $(dirname $YUM_CONF);
          yum repoinfo --config="$YUM_CONF" ${EXTRA_ARGS} --disablerepo="*" --enablerepo="$REPO_ID" | \
              grep Repo-name | \
              awk '{ print $3 }';
          exit ${PIPESTATUS[0]}
         )
    if [ $? != 0 ]; then
        >&2 echo "ERROR: yum repoinfo --config='$YUM_CONF' --disablerepo='*' --enablerepo='$REPO_ID'"
        return 1
    fi

    echo "$NAME"
    return 0
}

archive_repo_id () {
    local REPO_ID="$1"
    local YUM_CONF="$2"
    local REPO="$3"
    local REPO_NAME=""
    local TEMP=""
    local EXTRA=""

    if [ ! -f "$YUM_CONF" ]; then
        >&2 echo "ERROR: invalid file YUM_CONF='$YUM_CONF'"
        return 1
    fi

    if [ ! -f "$REPO" ]; then
        >&2 echo "ERROR: invalid file REPO='$REPO'"
        return 1
    fi

    REPO_NAME=$(get_repo_name "$YUM_CONF" "$REPO_ID")
    if [ $? != 0 ]; then
        return 1
    fi

    TEMP=$(mktemp '/tmp/repo_update_XXXXXX')
    if [ "$TEMP" == "" ]; then
        >&2 echo "ERROR: mktemp '/tmp/repo_update_XXXXXX'"
        return 1
    fi
    EXTRA=$(echo $TEMP | sed 's#/tmp/repo_update_##')
    \rm $TEMP

    echo "Archive: '$REPO_ID' as '$REPO_ID-$EXTRA' in file '$REPO'"

    sed -i "s#^[[]$REPO_ID[]]#[$REPO_ID-$EXTRA]#" "$REPO"
    sed -i "s#^name=$REPO_NAME\$#name=$REPO_NAME-$EXTRA#" "$REPO"
    return 0
}

copy_repo_id () {
    local REPO_ID="$1"
    local FORM_REPO="$2"
    local TO_REPO="$3"
    local TEMPDIR=""
    local FRAGMENT=""

    echo "Copy new repo id: '$REPO_ID' from '$FORM_REPO' into file '$TO_REPO'"

    if [ ! -f "$FORM_REPO" ]; then
        >&2 echo "ERROR: invalid file FORM_REPO='$FORM_REPO'"
        return 1
    fi

    if [ ! -f "$TO_REPO" ]; then
        >&2 echo "ERROR: invalid file TO_REPO='$TO_REPO'"
        return 1
    fi

    TEMPDIR=$(mktemp -d '/tmp/repo_update_XXXXXX')
    if [ "$TEMPDIR" == "" ]; then
        >&2 echo "ERROR: mktemp -d '/tmp/repo_update_XXXXXX'"
        return 1
    fi

    csplit --prefix=$TEMPDIR/xx --quiet "$FORM_REPO" '/^[[]/' '{*}' >> /dev/null
    if [ $? -ne 0 ]; then
        >&2 echo "ERROR: csplit --prefix=$TEMPDIR/xx '$FORM_REPO' '/^[[]/' '{*}'"
        return 1
    fi

    FRAGMENT=$(grep -l "$REPO_ID" $TEMPDIR/* | head -n 1)
    if [ "$TEMPDIR" == "" ]; then
        >&2 echo "ERROR: grep -l '$REPO_ID' $TEMPDIR/* | head -n 1"
        return 1
    fi

    echo >> $TO_REPO
    cat $FRAGMENT | sed "s#/etc/pki/rpm-gpg#$GPG_KEYS_DIR#" >> $TO_REPO
    \rm -rf $TEMPDIR
    return 0
}

update_yum_repos_d () {
    local UPSTREAM_REPO=""
    local REPO=""
    local UPSTREAM_REPO_ID=""
    local REPO_ID=""
    local UPSTREAM_REPO_URL=""
    local REPO_URL=""
    local UPSTREAM_REPO_NAME=""
    local REPO_NAME=""
    local UPSTREAM_DOWNLOAD_PATH=""
    local DOWNLOAD_PATH=""
    local TEMPDIR=""
    local UPSTREAM_YUM_REPOS_DIR=""

    for UPSTREAM_YUM_REPOS_DIR in $(find "$STX_TOOLS_DL_DIR/$STX_TOOLS_OS_SUBDIR" -type d -name yum.repos.d); do
        for UPSTREAM_REPO in $(find $UPSTREAM_YUM_REPOS_DIR -name '*.repo' | sort ); do
            REPO=$YUM_REPOS_DIR/$(basename $UPSTREAM_REPO)
            if [ ! -f $REPO ]; then
                # New repo file
                echo "Copy new repo file '$UPSTREAM_REPO' to '$REPO'"
                cat "$UPSTREAM_REPO" | sed "s#/etc/pki/rpm-gpg#$GPG_KEYS_DIR#" > "$REPO"
                continue
            fi

            for UPSTREAM_REPO_ID in $(grep '^[[]' $UPSTREAM_REPO | sed 's#[][]##g'); do
echo "UPSTREAM_YUM_CONF=$UPSTREAM_YUM_CONF"
echo "UPSTREAM_REPO_ID=$UPSTREAM_REPO_ID"
echo "UPSTREAM_REPO=$UPSTREAM_REPO"
                UPSTREAM_REPO_URL=$(get_repo_url "$UPSTREAM_YUM_CONF" "$UPSTREAM_REPO_ID" "${UPSTREAM_REPO}")
                if [ $? != 0 ]; then
                    return 1
                fi
echo "UPSTREAM_REPO_URL=$UPSTREAM_REPO_URL"

                UPSTREAM_REPO_NAME=$(get_repo_name "$UPSTREAM_YUM_CONF" "$UPSTREAM_REPO_ID" "${UPSTREAM_REPO}")
                if [ $? != 0 ]; then
                    return 1
                fi
echo "UPSTREAM_REPO_NAME=$UPSTREAM_REPO_NAME"

                UPSTREAM_DOWNLOAD_PATH="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$UPSTREAM_REPO_URL")"

                echo "Processing: REPO=$UPSTREAM_REPO  REPO_ID=$UPSTREAM_REPO_ID  REPO_URL=$REPO_URL  DOWNLOAD_PATH=$DOWNLOAD_PATH"

                REPO_ID=$(grep "^[[]$UPSTREAM_REPO_ID[]]" $REPO | sed 's#[][]##g')

                if [ "$REPO_ID" == "" ]; then
                    copy_repo_id "$UPSTREAM_REPO_ID" "$UPSTREAM_REPO" "$REPO"
                    if [ $? != 0 ]; then
                        >&2 echo "Error: copy_repo_id '$UPSTREAM_REPO_ID' '$UPSTREAM_REPO' '$REPO'"
                        return 1
                    fi
                    continue
                fi

                if [ "$REPO_ID" != "$UPSTREAM_REPO_ID" ]; then
                    >&2 echo "Error: bad grep?  '$REPO_ID' != '$UPSTREAM_REPO_ID'"
                    return 1
                fi

                # REPO_URL=$(cd $(dirname $YUM_CONF);
                #            yum repoinfo --config="$(basename $YUM_CONF)" --disablerepo="*" --enablerepo="$REPO_ID" | \
                #                grep Repo-baseurl | \
                #                cut -d ' ' -f 3;
                #            exit ${PIPESTATUS[0]})
                REPO_URL=$(get_repo_url "$YUM_CONF" "$REPO_ID")
                if [ $? != 0 ]; then
                #     >&2 echo "ERROR: yum repoinfo --config='$YUM_CONF' --disablerepo='*' --enablerepo='$REPO_ID'"
                    return 1
                fi
echo "REPO_URL=$REPO_URL"

                REPO_NAME=$(get_repo_name "$YUM_CONF" "$REPO_ID")
                if [ $? != 0 ]; then
                #     >&2 echo "ERROR: yum repoinfo --config='$YUM_CONF' --disablerepo='*' --enablerepo='$REPO_ID'"
                    return 1
                fi
echo "REPO_NAME=$REPO_NAME"

                REPO_URL=$(yum repoinfo --config="$YUM_CONF"  --disablerepo="*" --enablerepo="$REPO_ID" | grep Repo-baseurl | cut -d ' ' -f 3)
                DOWNLOAD_PATH="$DOWNLOAD_PATH_ROOT/$(repo_url_to_sub_path "$REPO_URL")"

                # Check critical content is the same
                if [ "$UPSTREAM_REPO_URL" == "$REPO_URL" ] && [ "$UPSTREAM_DOWNLOAD_PATH" == "$DOWNLOAD_PATH" ] && [ "$UPSTREAM_REPO_NAME" == "$REPO_NAME" ]; then
                    echo "Already have '$UPSTREAM_REPO_ID' from '$UPSTREAM_REPO'"
                    continue
                fi

                # Something has changed, log it
                if [ "$UPSTREAM_REPO_URL" != "$REPO_URL" ]; then
                    >&2 echo "Warning: Existing repo has changed: file:$UPSTREAM_REPO,  id:$UPSTREAM_REPO_ID,  url:$REPO_URL -> $UPSTREAM_REPO_URL"
                elif [ "$UPSTREAM_REPO_NAME" != "$REPO_NAME" ]; then
                    >&2 echo "Warning: Existing repo has changed: file:$UPSTREAM_REPO,  id:$UPSTREAM_REPO_ID,  name:$REPO_URL -> $UPSTREAM_REPO_URL"
                elif [ "$UPSTREAM_DOWNLOAD_PATH" != "$DOWNLOAD_PATH" ]; then
                    >&2 echo "Warning: Existing download path has changed: file:$UPSTREAM_REPO,  id:$UPSTREAM_REPO_ID,  path:$UPSTREAM_DOWNLOAD_PATH -> $DOWNLOAD_PATH"
                fi

                archive_repo_id "$REPO_ID" "$YUM_CONF" "$REPO"
                copy_repo_id "$UPSTREAM_REPO_ID" "$UPSTREAM_REPO" "$REPO"
                if [ $? != 0 ]; then
                    >&2 echo "Error: copy_repo_id '$UPSTREAM_REPO_ID' '$UPSTREAM_REPO' '$REPO'"
                    return 1
                fi
                # # Create new repo id?  Edit old one?  Unclear what to do.
                # ERR_COUNT=$((ERR_COUNT + 1))
            done
        done
    done

    return 0
}


if [ -f $LOGFILE ]; then
    \rm -f $LOGFILE
fi

(
ERR_COUNT=0

mkdir -p "$YUM_CONF_DIR"
if [ $? -ne 0 ]; then
    >&2 echo "Error: mkdir -p '$YUM_CONF_DIR'"
    exit 1
fi

mkdir -p "$YUM_REPOS_DIR"
if [ $? -ne 0 ]; then
    >&2 echo "Error: mkdir -p '$YUM_CONF_DIR'"
    exit 1
fi

mkdir -p "$GPG_KEYS_DIR"
if [ $? -ne 0 ]; then
    >&2 echo "Error: mkdir -p '$YUM_CONF_DIR'"
    exit 1
fi

stx_clone_or_update "$STX_BRANCH" "$STX_DL_ROOT_DIR"
if [ $? -ne 0 ]; then
    >&2 echo "Error: Failed to update stx repo Can't continue."
    exit 1
fi

if [ ! -f "$YUM_CONF" ]; then
    echo "Copy yum.conf: '$UPSTREAM_YUM_CONF' -> '$YUM_CONF'"
    cat $UPSTREAM_YUM_CONF | sed "s#=/tmp/#=$YUM_CONF_DIR/#" | \
                             sed "s#reposdir=yum.repos.d#reposdir=$YUM_CONF_DIR/yum.repos.d#" | \
                             sed 's#/etc/pki/rpm-gpg/#$GPG_KEYS_DIR/#' >> $YUM_CONF
fi

update_gpg_keys
if [ $? -ne 0 ]; then
    >&2 echo "Error: Failed in update_gpg_keys Can't continue."
    exit 1
fi

update_yum_repos_d
if [ $? -ne 0 ]; then
    >&2 echo "Error: Failed in update_yum_repos_d. Can't continue."
    exit 1
fi

if [ $ERR_COUNT -ne 0 ]; then
    >&2 echo "Error: Failed to update $ERR_COUNT repo_id's"
    exit 1
fi

exit 0
) | tee $LOGFILE

exit ${PIPESTATUS[0]}
