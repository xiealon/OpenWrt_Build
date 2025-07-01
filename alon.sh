#
#!/bin/bash
#
# env set test the figure of first
if [ -z "${1}" ]; then
    echo "no information"
    exit 1
fi
echo "${1}"
# evaluation the first figure and remove
BRANCH="${1}"
shift
# manual set the sys_types
SYSTEM_TYPE="openwrt"

declare -A SYSTEM_ENV=(
["openwrt"]="feeds.conf.default|./scripts/feeds|TAIL"
["ubuntu"]="/etc/apt/sources.list.d/custom.list|apt|TAIL"
["centos"]="/etc/yum.repos.d/custom.repo|yum|HEAD"
)

# modified write the sources
declare -A REPO_DEFINITIONS=(
["alon"]="https://github.com/xiealon/openwrt-packages-ing|openwrt|HEAD"
["alon1"]="https://github.com/xiealon/openwrt-package|openwrt|TAIL"
["alon2"]="https://github.com/xiealon/small|openwrt|TAIL"
["alon3"]="https://github.com/xiealon/small-package|openwrt|TAIL"
)

# definition repo notice
# ################################################################################  ## OpenWrt 以URL|openwrt|HEAD/TAIL [用竖线|隔开]
# ["alon-ubuntu"]="https://ubuntu.prod.repo/ubuntu focal main restricted universe"  ## 镜像URL 发行版代号 组件列表 [用空格隔开]
# ["alon-centos"]="https://centos.prod.repo/centos/7/os/x86-64/"                    ## 基础镜像URL

SOURCE_PRIORITY=(
    "alon"
    "alon1"
    "alon2"
    "alon3" 
    
)
INSTALL_PACKAGES=()
MAX_RETRY_LEVEL=3

insert_repository() {
local repo_name="${1}"
local repo_definition="${REPO_DEFINITIONS[$repo_name]}"
IFS='|' read -ra definition <<< "$repo_definition"
IFS='|' read -ra sys_opt <<< "${SYSTEM_ENV[$SYSTEM_TYPE]}"
local opt_config_file="${sys_opt[0]}"
local opt_system_default_pos="${sys_opt[2]}"
mkdir -p "$(dirname "${opt_config_file}")"

local repo_insert_pos="${definition[2]-}"

local final_pos="${repo_insert_pos:-$opt_system_default_pos}"

case "${SYSTEM_TYPE}" in
    "openwrt")
        local base_url="${definition[0]}"
        local branch=""
        local line_content="" line_pattern="src-git ${repo_name} "
        
        if [[ "${repo_name}" == "alon" ]]; then
            branch="${BRANCH}"
            line_content="src-git ${repo_name} ${base_url} ${branch}"
            line_content="${line_content/ ${branch}/;${branch}}"
        else
            line_content="src-git ${repo_name} ${base_url}"
        fi
        
        echo "[DEBUG] OpenWrt line: ${line_content}"
        
        if ! grep -q "${line_pattern}" "${opt_config_file}"; then
            sed -i.bak "/${line_pattern}/d" "${opt_config_file}"
            if [[ "${final_pos}" == "HEAD" ]]; then
                sed -i "1 i\\${line_content}" "${opt_config_file}"
            else
                sed -i "\$a\\${line_content}" "${opt_config_file}"
            fi
        fi
        ;;
        
    "ubuntu")
        local line_content="deb ${definition[0]}"
        sed -i.bak "/${repo_name} /d; \\${final_pos} i\\${line_content}" "${opt_config_file}"
        ;;
        
    "centos")
        local line_content="[${repo_name}]\nname=${repo_name}\nbaseurl=${definition[0]}\nenabled=1\ngpgcheck=0"
        sed -i.bak "/${repo_name} /d; \\${final_pos} i\\${line_content}" "${opt_config_file}"
        ;;
esac

echo "Inserted repo: ${repo_name}"

}

pkg_manager_cmd() {
    local opt_update_install="${sys_opt[1]}"
    case $1 in
        "update")
            if [[ "${SYSTEM_TYPE}" == "openwrt" ]]; then
                "${opt_update_install}" update -a
            else
                sudo "${opt_update_install}" update -y
            fi ;;
        "golang")
            if [[ "${SYSTEM_TYPE}" == "openwrt" ]]; then
                rm -rf feeds/packages/lang/golang
                git clone https://github.com/xiealon/packages_lang_golang -b 24.x feeds/packages/lang/golang
            else
                echo " no need golang "
            fi ;;
        "install")
            shift
            if [[ "$SYSTEM_TYPE" == "openwrt" ]]; then
                "${opt_update_install}" install -a "$@"
            else
                sudo "${opt_update_install}" install -y "$@"
            fi ;;
        "list")
            if [[ "$SYSTEM_TYPE" == "openwrt" ]]; then
                "${opt_update_install}" list | awk '{print $1}'
            else
                sudo "${opt_update_install}" list --installed
            fi ;;
    esac
}

smart_install() {
    declare -Ag install_result
    local remaining=("${@}")
    local retry_level=0
    while (( retry_level++ < MAX_RETRY_LEVEL )) && (( ${#remaining[@]} > 0 )); do
        declare -a current_round=("${remaining[@]}")
        unset remaining
        for pkg in "${current_round[@]}"; do
            if pkg_manager_cmd install "$pkg" 2>/dev/null; then
                install_result["success"]+= "$pkg"
            else
                if check_dependents "$pkg"; then
                    remaining+=("$pkg")
                else
                    install_result["failed"]+= "$pkg"
                fi
            fi
        done
        (( ${#remaining[@]} > 0 )) && sleep $((retry_level * 2))
    done
    install_result["remaining"]="${remaining[*]}"
}

check_dependents() {
    local pkg=$1
    case ${SYSTEM_TYPE} in
        "openwrt")
            opkg whatdepends "$pkg" | grep -q "Depends on" ;;
        "ubuntu")
            apt-cache rdepends --installed "$pkg" | grep -qv "Reverse Depends:" ;;
        "centos")
            repoquery --installed --whatrequires "$pkg" | grep -q . ;;
    esac
        return $?
}

main() {
    SYSTEM_TYPE="${SYSTEM_TYPE}"
    # send the sources
    for repo in "${SOURCE_PRIORITY[@]}"; do
        [[ "${REPO_DEFINITIONS[$repo]}" =~ $SYSTEM_TYPE ]] && insert_repository "$repo"
    done
    # install part
    pkg_manager_cmd update
    pkg_manager_cmd golang
    pkg_manager_cmd install
    pkg_manager_cmd list
    declare -Ag install_result
    if ! pkg_manager_cmd install "${INSTALL_PACKAGES[@]}" &>/dev/null; then
        declare -a initial_failed=()
        case $SYSTEM_TYPE in
            "ubuntu")
                initial_failed=($(apt-get -s install "${INSTALL_PACKAGES[@]}" 2>&1 | 
                    awk '/E: Unable to locate package/ {print $NF}')) ;;
            "centos")
                initial_failed=($(yum -q deplist "${INSTALL_PACKAGES[@]}" | 
                    awk '/provider:/{print $2}' | sort -u)) ;;
            "openwrt")
                initial_failed=($(comm -13 <(pkg_manager_cmd list | sort) \
                    <(printf "%s\n" "${INSTALL_PACKAGES[@]}" | sort))) ;;
        esac
    
        smart_install "${initial_failed[@]}"
    else
        install_result["success"]="${INSTALL_PACKAGES[*]}"
    fi
    # result
    echo -e "\n=== install_result ==="
    printf "|%-12s| %-50s |\n" "success" "${install_result[success]}"
    printf "|%-12s| %-50s |\n" "failed" "${install_result[failed]}"
    printf "|%-12s| %-50s |\n" "final" "${install_result[remaining]}"
    
    exit $(( ${#install_result[failed]} + ${#install_result[remaining]} ))
}

main "$@"

# ####CentOS need preinstall yum-util:sudo yum install -y yum-utils
# ####root
