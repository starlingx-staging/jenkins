#!/bin/bash

#
# Copyright (c) 2020 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Utilities to retry commands
#

function with_retries {
    local max_attempts=$1
    local delay=$2
    local cmd=$3

    # Pop the first two arguments off the list,
    # so we can pass additional args to the command safely
    shift 3

    local -i attempt=0

    while :; do
        attempt=$((attempt+1))

        >&2 echo "Running: ${cmd} $@"
        # ok, this is an obscure one ...
        #    ${cmd}
        # ... alone risks setting of bash's  'set -e',
        # So I need to hide the error code using a pipe
        # with a final commane that returns true.
        # original implementation was ...
        # ${cmd} "$@" | true
        # ... but this sometimes yields a ${PIPESTATUS[0]} of 141
        # if ${cmd} is still writing to stdout when 'true' exits.
        # Instead I use 'tee' to consume everything ${cmd} sends to stdout.
        ${cmd} "$@" | tee /dev/null
        if [  ${PIPESTATUS[0]} -eq 0 ]; then
            return 0
        fi

        >&2 echo "Command (${cmd}) failed, attempt ${attempt} of ${max_attempts}."
        if [ ${attempt} -lt ${max_attempts} ]; then
            >&2 echo "Waiting ${delay} seconds before retrying..."
            sleep ${delay}
            continue
        else
            >&2 echo "Max command attempts reached. Aborting..."
            return 1
        fi
    done
}
