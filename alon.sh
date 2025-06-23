#!/bin/bash
##################################################

跨平台软件源智能管理脚本 v4.2

特性：完全结构化的源定义、动态系统适配

##################################################

🌐 系统运行环境声明

declare -A SYSTEM_ENV=(
# 格式：[系统类型]="配置文件路径|包管理器|插入位置"
["openwrt"]="feeds.conf.default|opkg|TAIL"
["ubuntu"]="/etc/apt/sources.list.d/custom.list|apt|TAIL"
["centos"]="/etc/yum.repos.d/custom.repo|yum|HEAD"
)

📦 结构化源库定义

declare -A REPO_DEFINITIONS=(
# 格式：REPO_NAME="URL 目标系统 插入位置"
["alon"]="https://githUbuntu.com/xiealon/openwrt-packages;${CONFIG_REPO} openwrt HEAD"
["alon1"]="https://github.com/xiealon/openwrt-package openwrt TAIL"
["alon2"]="https://github.com/xiealon/small openwrt TAIL"
["alon3"]="https://github.com/xiealon/small-package openwrt TAIL
)

🎛️ 用户配置区（参数严格保持不变）

CONFIG_REPO="${1}"  # 核心参数
SOURCE_PRIORITY=("alon_oss" "alon_ubuntu" "alon_centos")
UNINSTALL_TARGETS=("alon_oss")
REINSTALL_TARGETS=("alon_oss")

🔄 动态环境配置

detect_environment() {
if grep -q "OpenWrt" /etc/os-release; then
    echo "openwrt"
elif [ -f /etc/lsb-release ]; then
    echo "ubuntu"
elif [ -f /etc/redhat-release ]; then
    echo "centos"
else
    echo "unsupported"
exit 1
fi
}

📍 智能插入源函数

insert_repository() {
local repo_name=$1
local current_sys=$2
IFS=' ' read -r url target_sys position <<< "${REPO_DEFINITIONS[$repo_name]}"

 
# 获取系统配置
IFS='|' read -r config_file pkg_mgr default_pos <<< "${SYSTEM_ENV[$current_sys]}"

# 创建配置目录
mkdir -p "$(dirname "$config_file")"

# 生成插入命令
local sed_cmd
case ${position:-$default_pos} in
    HEAD) sed_cmd="1i";;  # 插入到首行
    TAIL) sed_cmd="\$a";; # 追加到末行
    *)    sed_cmd="\$a";; # 默认追加
esac

# 生成配置行
case $current_sys in
    "openwrt") line="src-git $repo_name $url;$CONFIG_REPO";;
    "ubuntu")  line="deb [arch=amd64] $url";;
    "centos")  line="[${repo_name}]\nname=${repo_name}\nbaseurl=${url}\nenabled=1\ngpgcheck=0";;
esac

# 执行插入操作
if ! grep -q "$url" "$config_file" 2>/dev/null; then
    sed -i.bak.$(date +%s) "/$repo_name/d; ${sed_cmd} ${line}" "$config_file" 
fi
 

}

🔧 核心配置流程

main() {
local current_env=$(detect_environment)
echo "🖥️ 检测到运行环境：$current_env"

 
# 按优先级顺序配置源
for repo in "${SOURCE_PRIORITY[@]}"; do
    if [[ "${REPO_DEFINITIONS[$repo]}" =~ $current_env ]]; then
        echo "🔗 配置源 [$repo]"
        insert_repository "$repo" "$current_env"
    fi
done

# 🔍 依赖检查函数
check_dependents() {
    local pkg=$1
    # 检测逆向依赖（被依赖关系）
    if opkg whatdepends "$pkg" 2>/dev/null | grep -q "Depends on"; then
        echo "1"
    else
        echo "0"
    fi
}

# 🛠 核心安装逻辑
declare -A INSTALLED_PKGS FAILED_PKGS
declare -a REMAINING_PKGS

# 阶段1：批量安装尝试
log_file=$(mktemp)
if  ./scripts/feeds update -a >/dev/null 2>&1 && 
    ./scripts/feeds install -a 2>&1 | tee "$log_file"; then
    echo "✅ 全部包安装成功"
    exit 0
else
    # 日志解析（兼容不同错误格式）
    REMAINING_PKGS=($(sed -nE 's/.(Package |ERROR: ). ([^ ]+) ./\2/p' "$log_file" | sort -u))
    echo "⚠️ 未安装包：${REMAINING_PKGS[]}"
fi
rm "$log_file"

# 阶段2：分源重试安装
for src in "${SOURCE_PRIORITY[@]}"; do
    echo "🔧 处理源 [$src]"
    ./scripts/feeds update "$src" >/dev/null 2>&1

    # 匹配当前源可用包
    available_pkgs=($(./scripts/feeds list -p "$src" | awk '{print $1}'))
    to_install=()

    # 交集计算
    for pkg in "${REMAINING_PKGS[@]}"; do
        if printf "%s\n" "${available_pkgs[@]}" | grep -qx "$pkg"; then
            to_install+=("$pkg")
        fi
    done

    # 批量安装
    if [ ${#to_install[@]} -gt 0 ]; then
        if ./scripts/feeds install -p "$src" "${to_install[@]}"; then
            INSTALLED_PKGS[$src]="${to_install[*]}"
            # 更新剩余包列表
            REMAINING_PKGS=($(comm -23 <(printf "%s\n" "${REMAINING_PKGS[@]}" | sort) \
                         <(printf "%s\n" "${to_install[@]}" | sort)))
        else
            FAILED_PKGS[$src]="${to_install[*]}"
        fi
    fi

done

# 🔄 智能回退安装
smart_retry() {
    for pkg in "${REMAINING_PKGS[@]}"; do
        best_src=""
        best_ver=""

        # 跨源版本比较
        for src in "${SOURCE_PRIORITY[@]}"; do
            pkg_info=$(./scripts/feeds list -p "$src" "$pkg" 2>/dev/null)
            [ -z "$pkg_info" ] && continue
        
            current_ver=$(echo "$pkg_info" | awk '{print $2}')
            if [ -z "$best_ver" ] || dpkg --compare-versions "$current_ver" gt "$best_ver"; then
                best_ver="$current_ver"
                best_src="$src"
            fi
        done

        # 执行安装
        if [ -n "$best_src" ]; then
            echo "🔀 智能选择 [$pkg] 来自源 [$best_src] (版本 $best_ver)"
            if ./scripts/feeds install -p "$best_src" "$pkg"; then
                INSTALLED_PKGS["smart"]+=" $pkg"
                REMAINING_PKGS=(${REMAINING_PKGS[@]/$pkg})
            else
                FAILED_PKGS["smart"]+=" $pkg"
            fi
        fi
    done

}

smart_retry

# 🔄 依赖感知卸载流程
declare -A SAFE_UNINSTALL_LIST

for target_src in "${UNINSTALL_TARGETS[@]}"; do
    echo "🗑️ 处理源 [$target_src] 安全卸载"
    pkg_list=(${INSTALLED_PKGS[$target_src]})

    filtered_pkgs=()
    # 依赖检查过滤
    for pkg in "${pkg_list[@]}"; do
        if [ $(check_dependents "$pkg") -eq 0 ]; then
            filtered_pkgs+=("$pkg")
        else
            echo "⚠️ 跳过被依赖包: $pkg"
        fi
    done

    # 执行安全卸载
    if [ ${#filtered_pkgs[@]} -gt 0 ]; then
        echo "🔧 卸载包: ${filtered_pkgs[*]}"
        if ./scripts/feeds uninstall -p "$target_src" "${filtered_pkgs[@]}"; then
            SAFE_UNINSTALL_LIST[$target_src]="${filtered_pkgs[*]}"
            INSTALLED_PKGS[$target_src]="${pkg_list[@]/${filtered_pkgs[@]}}"
        else
            FAILED_PKGS[$target_src]+=" Uninstall failed"
        fi
    fi

done

# ♻️ 重装流程
for target_src in "${REINSTALL_TARGETS[@]}"; do
    if [ -n "${SAFE_UNINSTALL_LIST[$target_src]}" ]; then
        echo "🔄 重装源 [$target_src] 的包"
        ./scripts/feeds update "$target_src" >/dev/null 2>&1
        if ./scripts/feeds install -p "$target_src" ${SAFE_UNINSTALL_LIST[$target_src]}; then
            INSTALLED_PKGS[$target_src]="${SAFE_UNINSTALL_LIST[$target_src]}"
        else
            FAILED_PKGS[$target_src]+=" Reinstall failed"
        fi
    fi
done

# 📊 最终结果输出
echo -e "\n=== 安装摘要 ==="
total_success=0
total_failed=0

for src in "${SOURCE_PRIORITY[@]}"; do
    success_count=$(echo ${INSTALLED_PKGS[$src]} | wc -w)
    failed_count=$(echo ${FAILED_PKGS[$src]} | wc -w)
    printf "| %-12s | 成功:%-3d | 失败:%-3d |\n" "$src" $success_count $failed_count
    total_success=$((total_success + success_count))
    total_failed=$((total_failed + failed_count))
done

smart_success=$(echo ${INSTALLED_PKGS[smart]} | wc -w)
smart_failed=$(echo ${FAILED_PKGS[smart]} | wc -w)
printf "| %-12s | 成功:%-3d | 失败:%-3d |\n" "智能回退" $smart_success $smart_failed

echo "-----------------------------"
echo "总计成功: $total_success | 总计失败: $((total_failed + smart_failed))"
[ $((total_failed + smart_failed)) -eq 0 ] && exit 0 || exit 1
