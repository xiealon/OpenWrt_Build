#!/bin/bash
# 重构脚本
# 定义源部分可以自己添加了！安装从前到后强制顺序进行
# 请不要调整alon源的(第一个安装源)位置
#
CONFIG_REPO="${1}" # 将输入的第一个量值赋值给CONFIG_REPO

#检查并使用第一个输入量
if [ -z "$CONFIG_REPO" ]; then
   echo "Error: Please provide the configuration repository as the first argument."
   exit 1
fi

# 备份 feeds.conf.default 文件 
# 降低代码级数 保证alon经过添加后再备份 方便后面步骤进行修改文件
# 防止出现alon没有进入feeds的情况发生
# cp feeds.conf.default feeds.conf.default.bak

# 配置软件源
# 处理 alon 软件源并检查
sed -i "/src-git alon /d; 1 i src-git alon https://github.com/xiealon/openwrt-packages;${CONFIG_REPO}" feeds.conf.default
 if [ $? -ne 0 ]; then
   echo "Failed to modify feeds.conf.default for alon source."
   exit 1
 else
   echo "Successfully updated alon in feeds.conf.default"
 fi

# 备份 feeds.conf.default 文件
cp feeds.conf.default feeds.conf.default.bak

# 处理新增的两个软件源
# sed -i "/src-git alon1 /d; 2 i src-git alon1 https://github.com/xiealon/openwrt-package;${CONFIG_REPO}" feeds.conf.default
sed -i "/src-git alon1 /d; \$a src-git alon1 https://github.com/xiealon/openwrt-package;${CONFIG_REPO}" feeds.conf.default
 if [ $? -ne 0 ]; then
   echo "Failed to modify feeds.conf.default for alon1 source."
   exit 1
 else
   echo "Successfully updated alon1 in feeds.conf.default"
 fi
 
# sed -i "/src-git alon2 /d; 3 i src-git alon2 https://github.com/xiealon/small;${CONFIG_REPO}" feeds.conf.default
sed -i "/src-git alon2 /d; \$a src-git alon2 https://github.com/xiealon/small;${CONFIG_REPO}" feeds.conf.default
 if [ $? -ne 0 ]; then
   echo "Failed to modify feeds.conf.default for alon2 source."
   exit 1
 else
   echo "Successfully updated alon2 in feeds.conf.default"
 fi

#######################################

# 配置区（用户可自由修改以下参数）

#######################################

# 定义软件源及其优先级（越靠前优先级越高）
SOURCES=("alon" "alon1" "alon2" "packages" "luci")

#######################################

# 核心逻辑（无需修改）

#######################################

declare -A INSTALL_SUCCESS INSTALL_FAILED
declare -a remaining_packages

# 初始化结果记录
for src in "${SOURCES[@]}"; do
    INSTALL_SUCCESS[$src]=""
    INSTALL_FAILED[$src]=""
done

# 阶段1：初始批量安装 + 日志解析
echo "=== 阶段1: 初始批量安装尝试 ==="
log_file=$(mktemp)
if ./scripts/feeds update >/dev/null 2>&1 && ./scripts/feeds install -a 2>&1 | tee "$log_file"; then
    echo "初始安装全部成功"
    exit 0
else
    # 通过日志分析失败包（兼容不同错误格式）
    failed_packages=($(sed -nE 's/.(Package |Could not find package )([^ ]+)./\2/p' "$log_file" | sort -u))
    remaining_packages=("${failed_packages[@]}")
    echo "检测到未安装包: ${remaining_packages[*]}"
fi
rm "$log_file"

# 阶段2：按源优先级重试
echo -e "\n=== 阶段2: 分源重试安装 ==="
for src in "${SOURCES[@]}"; do
    echo "处理源: $src"
    ./scripts/feeds update "$src" >/dev/null 2>&1

    # 从剩余包中筛选该源可安装的包
    to_install=()
    for pkg in "${remaining_packages[@]}"; do
        if ./scripts/feeds list -p "$src" | grep -q "^$pkg$"; then
            to_install+=("$pkg")
        fi
    done

    # 执行批量安装
    if [ ${#to_install[@]} -gt 0 ]; then
        if ./scripts/feeds install -p "$src" "${to_install[@]}"; then
            INSTALL_SUCCESS[$src]+="${to_install[*]} "
            remaining_packages=($(comm -23 <(printf "%s\n" "${remaining_packages[@]}" | sort) <(printf "%s\n" "${to_install[@]}" | sort)))
        else
            INSTALL_FAILED[$src]+="${to_install[*]} "
        fi
    fi

done

# 阶段3：智能回退安装
echo -e "\n=== 阶段3: 智能回退处理 ==="
smart_install() {
    local pkg=$1
    declare -A local_processed
    local best_ver="" best_src=""

    # 跨源查找最高版本
    for src in "${SOURCES[@]}"; do
        version=$(./scripts/feeds list -p "$src" -n "$pkg" 2>/dev/null | awk '{print $2}')
        [ -z "$version" ] && continue
    
        # 版本比较逻辑
        if [ -z "$best_ver" ] || [[ "$version" > "$best_ver" ]]; then
            best_ver=$version
            best_src=$src
        fi
    done

    # 执行安装并处理依赖
    if [ -n "$best_src" ]; then
        echo "智能选择：$pkg ($best_ver) 来自 $best_src"
        ./scripts/feeds install -p "$best_src" "$pkg" && return 0
    fi
    return 1

}

# 处理剩余包
if [ ${#remaining_packages[@]} -gt 0 ]; then
    for pkg in "${remaining_packages[@]}"; do
        if smart_install "$pkg"; then
            INSTALL_SUCCESS["smart"]+="$pkg "
        else
            INSTALL_FAILED["smart"]+="$pkg "
        fi
    done
fi

#######################################

# 结果输出（结构化展示）

#######################################
echo -e "\n=== 最终安装结果 ==="
for src in "${SOURCES[@]}"; do
    printf "源 %-10s : 成功[%2d] 失败[%2d]\n" 
    "$src" \ 
    $(echo ${INSTALL_SUCCESS[$src]} | wc -w) \
    $(echo ${INSTALL_FAILED[$src]} | wc -w)
done
echo "智能回退安装 : 成功[$(echo ${INSTALL_SUCCESS["smart"]} | wc -w)] 失败[$(echo ${INSTALL_FAILED["smart"]} | wc -w)]"

# 最终状态判断
[ ${#INSTALL_FAILED[@]} -eq 0 ] && exit 0 || exit 1

# 输出每个源安装成功和失败的包
for source in "${SOURCES[@]}"; do
    echo "Packages successfully installed from $source source: ${INSTALL_SUCCESS[$source]}"
    echo "Packages failed to install from $source source: ${INSTALL_FAILED[$source]}"
done

# 输出最终仍未安装成功的包
if [ ${#remaining_packages[@]} -gt 0 ]; then
    echo "Packages that failed to install from all sources: ${remaining_packages[*]}"
else
    echo "All packages were successfully installed."
fi
