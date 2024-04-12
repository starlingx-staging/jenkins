#!/bin/bash

#
# A crude start on a job to create the jenkins jobs to build a new
# feature or rc branch, based on the current state of the master job.
#
# Set the value of the 'BRANCH' variable below before running.
#

SRC_JOB_STX_BUILD="STX_build_debian_master"
SRC_JOB_STX_PIPE="starlingx-jenkins-pipelines"
SRC_JOB_STX_CONTAINERS="STX_build_debian_build_containers_master"

SRC_JOB_OS_BUILD="STX_openstack_build_debian"
SRC_JOB_OS_PIPE="STX_openstack_build_pipelines"
SRC_JOB_OS_CONTAINERS="STX_openstack_build_debian_build_containers"

SRC_WORKDIR_STX_BUILD="debian-master"
SRC_WORKDIR_STX_CONTAINERS="debian-master-build-containers"

SRC_WORKDIR_OS_BUILD="debian-master-openstack"
SRC_WORKDIR_OS_CONTAINERS="debian-master-openstack-build-containers"

SRC_BRANCH="master"

jobs=( "$SRC_JOB_OS_CONTAINERS" "$SRC_JOB_OS_PIPE" "$SRC_JOB_OS_BUILD" "$SRC_JOB_STX_CONTAINERS" "$SRC_JOB_STX_PIPE" "$SRC_JOB_STX_BUILD")
workdirs=( "$SRC_WORKDIR_OS_CONTAINERS" "$SRC_WORKDIR_OS_BUILD" "$SRC_WORKDIR_STX_CONTAINERS" "$SRC_WORKDIR_STX_BUILD" )


BRANCH="r/stx.9.0"

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

workdir_transform () {
    local oIFS="$IFS"
    
    IFS=/
    local parts=( $1 )
    IFS="$oIFS"
    parts[0]="$(echo "${parts[0]}" | sed -e 's#^debian-\(.*\)$#\1-debian#' -e "s#^${SRC_BRANCH}#${WORKDIR_BRANCH}#")"
    join_by '/' "${parts[@]}"
}

job_transform () {
    local oIFS="$IFS"
    
    IFS=/
    local parts=( $1 )
    IFS="$oIFS"
    parts[0]="$(echo "${parts[0]}" | sed -e "s#_${SRC_BRANCH}\$##" -e 's#starlingx-jenkins-#STX_#' -e "s#STX_#STX_${JOB_BRANCH}_#")"
    join_by '/' "${parts[@]}"
}

JOB_BRANCH="$(echo $BRANCH | sed -e 's#r/stx.##' -e 's#[/\-]#_#g')"
WORKDIR_BRANCH="$(echo $BRANCH | sed -e 's#r/#rc-#' -e 's#[/._]#-#g')"
PUBLISHDIR_BRANCH="$(echo $BRANCH | sed -e 's#r/stx.#rc/#' -e 's#f/#feature/#')"

declare -A transforms
for j in "${jobs[@]}"; do 
    transforms["$j"]=$(job_transform "$j")
done
for w in "${workdirs[@]}"; do
    transforms["$w"]="$(workdir_transform "$w")"
done
transforms["starlingx/$SRC_BRANCH/debian"]="starlingx/$PUBLISHDIR_BRANCH/debian"
transforms["TAG=$SRC_BRANCH"]="TAG=$WORKDIR_BRANCH"
transforms["$SRC_BRANCH"]="$BRANCH"




cd ~jenkins/jobs


for c in $(find "${jobs[@]}" -name config.xml); do 
   b="$(basename "$c")"
   d="$(dirname "$c")"
   d2=$(job_transform "$d") 
   c2="$d2/$b"
   echo "$d -> $d2"
   mkdir -p "$d2"
   cp "$c" "$c2"
   for k in "${jobs[@]}" "${workdirs[@]}" "starlingx/$SRC_BRANCH/debian" "TAG=$SRC_BRANCH" "$SRC_BRANCH"; do
       sed -i "s#$k#${transforms["$k"]}#g" "$c2"
   done
done

cd /localdisk/designer/jenkins
for c in $(find "${workdirs[@]}" -maxdepth 1 -name build.conf); do
   b="$(basename "$c")"
   d="$(dirname "$c")"
   d2=$(workdir_transform "$d") 
   c2="$d2/$b"
   echo "$d -> $d2"
   mkdir -p "$d2"
   cp "$c" "$c2"
   for k in "${jobs[@]}" "${workdirs[@]}" "starlingx/$SRC_BRANCH/debian" "TAG=$SRC_BRANCH" "$SRC_BRANCH"; do
       sed -i "s#$k#${transforms["$k"]}#g" "$c2"
   done
done

for c in $(find "${workdirs[@]}" -maxdepth 1 -name kube-config); do
   b="$(basename "$c")"
   d="$(dirname "$c")"
   d2=$(workdir_transform "$d") 
   c2="$d2/$b"
   echo "$d -> $d2"
   mkdir -p "$d2"
   cp "$c" "$c2"
   for k in "${jobs[@]}" "${workdirs[@]}" "starlingx/$SRC_BRANCH/debian" "TAG=$SRC_BRANCH" "$SRC_BRANCH"; do
       sed -i "s#$k#${transforms["$k"]}#g" "$c2"
   done

   export KUBECONFIG="${PWD}/${c2}"
   PROJECT="$(grep PROJECT_ID= $d2/build.conf | sed -e 's#^PROJECT_ID=##' -e 's#^["]##' -e 's#["]$##' | sed -r 's/[^a-zA-Z0-9-]+/-/g' | tr A-Z a-z)"
   K8S_NAMESPACE="jenkins-$PROJECT"
   kubectl create namespace $K8S_NAMESPACE
done










