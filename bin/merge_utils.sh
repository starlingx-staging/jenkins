MU_VERBOSE=0

FD_SHA=0
FD_NAME=1
FD_INODE=2
FD_PATH=3

if_verbose () {
   return $MU_VERBOSE
}

get_file_data_from_path () {
    local path="${1}"
    echo "$(sha256sum ${path} | cut -d ' ' -f 1) $(basename ${path}) $(stat --format=%i ${path}) ${path}"
}

get_file_data_from_dir () {
    local directory="${1}"
    local list_file="${2}"

    local d
    local line
    local fields

    for d in $(find $directory -type d | grep -v 'repodata'); do
        sha256sum $d/*.rpm $d/*.tar $d/*.tgz $d/*.gz $d/*.bz2 2> /dev/null | \
        while read line; do
            fields=( $(echo $line) )
            echo "${fields[0]} $(basename ${fields[1]})  $(stat --format=%i ${fields[1]}) ${fields[1]}"
        done
    done > ${list_file}.unsorted
    sort ${list_file}.unsorted > ${list_file}
    \rm -f ${list_file}.unsorted
}

merge_candidate () {
    local array1=( ${1} )
    local array2=( ${2} )
    local merge="${3}"

    if_verbose && echo "test ${1}"
    if_verbose && echo "     ${2}"
    if [ "${array1[$FD_SHA]}" != "${array2[$FD_SHA]}" ]; then
        if_verbose && echo "shas differ"
        return 1
    elif [ "${array1[$FD_NAME]}" != "${array2[$FD_NAME]}" ]; then
        if_verbose && echo "names differ"
        return 1
    elif [ "${array1[$FD_INODE]}" = "${array2[$FD_INODE]}" ]; then
        if_verbose && echo "inodes already the same"
        return 1
    elif [ "${array1[$FD_FPATH]}" = "${array2[$FD_PATH]}" ]; then
        if_verbose && echo "paths already the same"
        return 1
    fi

    if_verbose && echo "merge candidates:"
    if_verbose && echo "   ${array1[$FD_PATH]}"
    if_verbose && echo "   ${array2[$FD_PATH]}"

    if [ "${merge}" == "merge" ]; then
        if_verbose ln -f ${array1[$FD_PATH]} ${array2[$FD_PATH]}
        ln -f ${array1[$FD_PATH]} ${array2[$FD_PATH]}
    fi

    return 0
}

compare_lists () {
    local lst1="${1}"
    local lst2="${2}"
    local merge="${3}"

    local array1=( )
    local line1
    local line2

    grep -v '^$' "${lst1}" | \
    while read line1; do
        array1=( ${line1} )
        grep " ${array1[$FD_NAME]} " "${lst2}" | \
        while read line2; do
            merge_candidate "$line1" "$line2" "${merge}"
        done
    done
}

compare_dirs2 () {
    local dir1="${1}"
    local dir2="${2}"
    local merge="${3}"

    local lst1=$(mktemp -t "dir_list_XXXXXX")
    local lst2=$(mktemp -t "dir_list_XXXXXX")

    get_file_data_from_dir "${dir1}" "${lst1}"
    get_file_data_from_dir "${dir2}" "${lst2}"
    compare_lists "${lst1}" "${lst2}" "${merge}"

    rm -f "${lst1}"
    rm -f "${lst2}"
}

compare_dirs () {
    local merge=""
    if [ "$1" == "merge" ]; then
        merge="$1"
        shift
    fi
    local dir_array=( $@ )

    declare -A lst_dict
    local idx1=0
    local idx2=0
    local dir1=""
    local dir2=""
    local f=""

    for idx1 in "${!dir_array[@]}"; do
        dir1="${dir_array[$idx1]}"
        if [ ! -d "${dir1}" ]; then
            continue
        fi

        if [ "${lst_dict[$dir1]}" == "" ]; then
            lst_dict[$dir1]=$(mktemp -t "dir_list_XXXXXX")
            get_file_data_from_dir "${dir1}" "${lst_dict[$dir1]}"
        fi

        for idx2 in "${!dir_array[@]}"; do
            if [ $idx1 -ge $idx2 ]; then
                continue
            fi

            dir2="${dir_array[$idx2]}"
            if [ ! -d "${dir1}" ]; then
                continue
            fi

            if [ "${lst_dict[$dir2]}" == "" ]; then
                lst_dict[$dir2]=$(mktemp -t "dir_list_XXXXXX")
                get_file_data_from_dir "${dir2}" "${lst_dict[$dir2]}"
            fi

            compare_lists "${lst_dict[$dir1]}" "${lst_dict[$dir2]}" merge
            rm -f "${lst_dict[$dir2]}}"
            unset lst_dict[$dir2]  
        done
    done

    rm -f -v ${lst_dict[@]}
}
