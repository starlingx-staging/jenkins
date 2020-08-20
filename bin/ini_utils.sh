ini_section () {
    local ini_file="$1"
    local section="$2"

    if [ ! -f "${ini_file}" ]; then
        return 1
    fi

    cat "${ini_file}" | awk -v TARGET="${section}" -F ' *= *' '
  {
    if ($0 ~ /^\[.*\]$/) {
      gsub(/^\[|\]$/, "", $0)
      SECTION=$0
    } else if (($2 != "") && (SECTION==TARGET)) {
      print $1 "=\"" $2 "\""
    }
  }
  '
}

ini_field () {
    local ini_file="$1"
    local section="$2"
    local field="$3"

    if [ ! -f "${ini_file}" ]; then
        return 1
    fi

    ini_section "${ini_file}" "${section}" | grep "^${field}=" | sed -e "s#^${field}=##" -e 's#^"##' -e 's#"$##'
}

ini_section_list () {
    local ini_file="$1"

    if [ ! -f "${ini_file}" ]; then
        return 1
    fi

    grep '^\[.*\]' "${ini_file}" | sed -e 's#^\[##' -e 's#\]$##'
}
