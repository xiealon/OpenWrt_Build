#!/bin/bash
##################################################
##################################################
declare -A SYSTEM_ENV=(
["openwrt"]="feeds.conf.default|./scripts/feeds|TAIL"
["ubuntu"]="/etc/apt/sources.list.d/custom.list|apt|TAIL"
["centos"]="/etc/yum.repos.d/custom.repo|yum|HEAD"
)

BRANCH="${1}"
declare -A REPO_DEFINITIONS=(
["alon"]="https://github.com/xiealon/openwrt-packages;${BRANCH}|openwrt|HEAD"
["alon"]="https://github.com/xiealon/openwrt-package|openwrt|TAIL"
["alon2"]="https://github.com/xiealon/small|openwrt|TAIL"
["alon3"]="https://github.com/xiealon/small-package|openwrt|TAIL"
)
# 定义repo添加说明
# ################################################################################  ## OpenWrt 以URL|openwrt|HEAD/TAIL [用竖线|隔开]
# ["alon-ubuntu"]="https://ubuntu.prod.repo/ubuntu focal main restricted universe"  ## 镜像URL 发行版代号 组件列表 [用空格隔开]
# ["alon-centos"]="https://centos.prod.repo/centos/7/os/x86-64/"                    ## 基础镜像URL
SOURCE_PRIORITY=("alon" "alon1" "alon2" "alon3")
INSTALL_PACKAGES=()
MAX_RETRY_LEVEL=3
MANUAL_SYSTEM='openwrt'
🔄 增强环境检测
detect_environment() {
    if [[ -n "$MANUAL_SYSTEM" ]]; then
        echo "⚙️ 使用手动设置环境：$MANUAL_SYSTEM"
        echo "$MANUAL_SYSTEM"
    else
        if grep -qi "OpenWrt" /etc/os-release 2>/dev/null; then
            declare -g PKG_MGR="./scripts/feeds" SYSTEM_TYPE="openwrt"
        elif [ -f /etc/lsb-release ]; then
            declare -g PKG_MGR="apt" SYSTEM_TYPE="ubuntu"
        elif [ -f /etc/redhat-release ]; then
            declare -g PKG_MGR="yum" SYSTEM_TYPE="centos"
        else
            echo "❌ Unsupported system environment" >&2
            exit 1
        fi
    fi
}

insert_repository() {
    local repo_name=$1
    IFS='|' read -r config_file _ default_pos <<< "${SYSTEM_ENV[$SYSTEM_TYPE]}"

    mkdir -p "$(dirname "$config_file")"
    local line_content

    case $SYSTEM_TYPE in
        "openwrt")
            line_content="src-git $repo_name ${REPO_DEFINITIONS[$repo_name]%%|*}" ;;
        "ubuntu")
            line_content="deb ${REPO_DEFINITIONS[$repo_name]}" ;;
        "centos")
            line_content="[$repo_name]\nname=$repo_name\nbaseurl=${REPO_DEFINITIONS[$repo_name]}\nenabled=1\ngpgcheck=0" ;;
    esac

    if ! grep -q "$repo_name" "$config_file" 2>/dev/null; then
        local insert_cmd="\$a"
        [[ ${default_pos} == "HEAD" ]] && insert_cmd="1i"
        sed -i.bak.$(date +%s) "/$repo_name/d; ${insert_cmd}\\${line_content}" "$config_file"
    fi

}

pkg_manager_cmd() {
    case $1 in
        "update")
            if [[ $SYSTEM_TYPE == "openwrt" ]]; then   
                $PKG_MGR update -a
            else
                $PKG_MGR update -y
            fi ;;
        "install")
            shift
            local args=()
            [[ $SYSTEM_TYPE != "openwrt" ]] && args+=("-y")
            $PKG_MGR install "${args[@]}" "$@" ;;
        "list")
            if [[ $SYSTEM_TYPE == "openwrt" ]]; then
                $PKG_MGR list | awk '{print $1}'
            else
                $PKG_MGR list --installed
            fi ;;
    esac
}

check_dependents() {
    local pkg=$1
        case $SYSTEM_TYPE in
            "openwrt")
                opkg whatdepends "$pkg" | grep -q "Depends on" ;;
            "ubuntu")
                apt-cache rdepends --installed "$pkg" | grep -qv "Reverse Depends:" ;;
            "centos")
                repoquery --installed --whatrequires "$pkg" | grep -q . ;;
        esac
        return $?
}

smart_install() {
    declare -Ag install_result
    local remaining=("${@}")
    local retry_level=0

    while ($ retry_level++ < MAX_RETRY_LEVEL $) && [ ${#remaining[@]} -gt 0 ]; do
        declare -a current_round=("${remaining[@]}")
        unset remaining[@]
    
        for pkg in "${current_round[@]}"; do
            if pkg_manager_cmd install "$pkg" 2>/dev/null; then
                install_result["success"]+=" $pkg"
            else
                if check_dependents "$pkg"; then
                    remaining+=("$pkg")
                else
                    install_result["failed"]+=" $pkg"
                fi
            fi
        done
    
        ($ ${#remaining[@]} $) && sleep $((retry_level * 2))
    done

    install_result["remaining"]="${remaining[*]}"

}

main() {
    current_env=$(detect_environment)

    # 配置软件源
    for repo in "${SOURCE_PRIORITY[@]}"; do
        [[ "${REPO_DEFINITIONS[$repo]}" =~ $SYSTEM_TYPE ]] && insert_repository "$repo"
    done

    # 核心安装流程
    pkg_manager_cmd update
    declare -Ag install_result

    # 初始批量安装尝试
    if ! pkg_manager_cmd install "${INSTALL_PACKAGES[@]}" &>/dev/null; then
        # 获取初始失败列表
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
    
        # 智能回退安装
        smart_install "${initial_failed[@]}"
    else
        install_result["success"]="${INSTALL_PACKAGES[*]}"
    fi

    # 结果输出
    echo -e "\n=== 安装结果 ==="
    printf "|%-12s| %-50s |\n" "成功安装" "${install_result[success]}"
    printf "|%-12s| %-50s |\n" "失败依赖" "${install_result[failed]}"
    printf "|%-12s| %-50s |\n" "最终残留" "${install_result[remaining]}"

    exit $((${#install_result[failed]} + ${#install_result[remaining]}))

}

main "$@"

# ####CentOS系统需要预先安装 yum-utils ： sudo yum install -y yum-utils
# ####需要以root权限执行
# ####首次运行前执行如果以独立的脚本运行需要添加执行权限并传递各种参数按照你的需求
