#
#!/bin/bash
#
# 系统环境配置
BRANCH="${1}"
SYSTEM_TYPE="openwrt"

declare -A SYSTEM_ENV=(
["openwrt"]="feeds.conf.default|./scripts/feeds|TAIL"
["ubuntu"]="/etc/apt/sources.list.d/custom.list|apt|TAIL"
["centos"]="/etc/yum.repos.d/custom.repo|yum|HEAD"
)

# 修改源部分
declare -A REPO_DEFINITIONS=(
["alon"]="https://github.com/xiealon/openwrt-packages|openwrt|HEAD"
["alon1"]="https://github.com/xiealon/openwrt-package|openwrt|TAIL"
["alon2"]="https://github.com/xiealon/small|openwrt|TAIL"
["alon3"]="https://github.com/xiealon/small-package|openwrt|TAIL"
)
#
# 定义repo添加说明
# ################################################################################  ## OpenWrt 以URL|openwrt|HEAD/TAIL [用竖线|隔开]
# ["alon-ubuntu"]="https://ubuntu.prod.repo/ubuntu focal main restricted universe"  ## 镜像URL 发行版代号 组件列表 [用空格隔开]
# ["alon-centos"]="https://centos.prod.repo/centos/7/os/x86-64/"                    ## 基础镜像URL

SOURCE_PRIORITY=("alon" "alon1" "alon2" "alon3")
INSTALL_PACKAGES=()
MAX_RETRY_LEVEL=3

insert_repository() {
    local repo_name=$1
    IFS='|' read -r config_file PKG_MGR default_pos <<< "${SYSTEM_ENV[$SYSTEM_TYPE]}"
    mkdir -p "$(dirname "${config_file}")"
    local line_content
    case ${SYSTEM_TYPE} in
        "openwrt")
        if [ "$repo_name" = "alon" ]; then
            line_content="src-git ${repo_name} ${REPO_DEFINITIONS[$repo_name]%%|*;${BRANCH}}" ;;
        else
            line_content="src-git ${repo_name} ${REPO_DEFINITIONS[$repo_name]%%|*}" ;;
        "ubuntu")
            line_content="deb ${REPO_DEFINITIONS[$repo_name]%%|*}" ;;
        "centos")
            line_content="[$repo_name]\nname=${repo_name}\nbaseurl=${REPO_DEFINITIONS[$repo_name]%%|*}\nenabled=1\ngpgcheck=0" ;;
    esac
    # 从 REPO_DEFINITIONS 中提取该源定义的插入位置
    local repo_insert_pos=$(echo "${REPO_DEFINITIONS[$repo_name]}" | cut -d '|' -f 3)
    # 如果 REPO_DEFINITIONS 中定义的位置不为空且与 SYSTEM_ENV 不同，则使用 REPO_DEFINITIONS 中的位置
    if [ -n "$repo_insert_pos" ] && [ "$repo_insert_pos" != "$default_pos" ]; then
        default_pos=$repo_insert_pos
    fi
    if ! grep -q "$repo_name" "$config_file" 2>/dev/null; then
        local insert_cmd="\$a"
        [[ "${default_pos}" == "HEAD" ]] && insert_cmd="1i"
        sed -i.bak.$(date +%s) "/${repo_name}/d; ${insert_cmd}\\${line_content}" "${config_file}"
    fi
}
pkg_manager_cmd() {
    case $1 in
        "update")
            if [[ "${SYSTEM_TYPE}" == "openwrt" ]]; then
                "${PKG_MGR}" update -a
            else
                "${PKG_MGR}" update -y
            fi ;;
        "install")
            shift
            if [[ "${SYSTEM_TYPE}" == "openwrt" ]]; then
                "${PKG_MGR}" install -a "$@"
            else
                "${PKG_MGR}" install -y "$@"
            fi ;;
        "list")
            if [[ "${SYSTEM_TYPE}" == "openwrt" ]]; then
                "${PKG_MGR}" list | awk '{print $1}'
            else
                "${PKG_MGR}" list --installed
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
    SYSTEM_TYPE=${SYSTEM_TYPE}
    # 配置软件源
    for repo in "${SOURCE_PRIORITY[@]}"; do
        [[ "${REPO_DEFINITIONS[$repo]}" =~ $SYSTEM_TYPE ]] && insert_repository "$repo"
    done
    # 核心安装流程
    pkg_manager_cmd update
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
    # 结果输出
    echo -e "\n=== 安装结果 ==="
    printf "|%-12s| %-50s |\n" "成功安装" "${install_result[success]}"
    printf "|%-12s| %-50s |\n" "失败依赖" "${install_result[failed]}"
    printf "|%-12s| %-50s |\n" "最终残留" "${install_result[remaining]}"
    
    exit $(( ${#install_result[failed]} + ${#install_result[remaining]} ))
}

main "$@"

# ####CentOS系统需要预先安装 yum-utils ： sudo yum install -y yum-utils
# ####需要以root权限执行
# ####首次运行前执行如果以独立的脚本运行需要添加执行权限并传递各种参数按照你的需求
