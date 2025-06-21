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
sed -i "/src-git alon /d; \$a src-git alon https://github.com/xiealon/openwrt-packages;${CONFIG_REPO}" feeds.conf.default
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

# 更新所有 feeds
if ./scripts/feeds update -a; then
   echo "Feeds updated successfully."
else
   echo "Failed to update feeds."
   cp feeds.conf.default.bak feeds.conf.default
   exit 1
fi

# 定义要处理的源列表
SOURCES=("package" "luci" "routing" "telephony" "alon" "alon1" "alon2")
declare -A PKG_ARRAYS
declare -A INSTALL_SUCCESS
declare -A INSTALL_FAILED

# 用于存储需要重试安装的包
RETRY_PACKAGES=()

# 用于存储每个包的依赖信息
declare -A DEPENDENCIES

# 用于存储每个包解析后的依赖列表
declare -A PARSED_DEPENDENCIES

# 用于快速检查包是否已安装
declare -A INSTALLED_MAP

# 先获取所有源的包名、版本和依赖信息
for source in "${SOURCES[@]}"; do
    index_file="feeds/${source}/index"
    if [ -f "$index_file" ]; then
        packages=$(grep -E '^Package:' "$index_file" | awk '{print $2}')
        mapfile -t PKG_ARRAYS[$source] <<< "$packages"
        while IFS= read -r line; do
            if [[ $line =~ ^Package:\ (.) ]]; then
                pkg="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^Depends:\ (.) ]]; then
                deps="${BASH_REMATCH[1]}"
                DEPENDENCIES[$pkg]="$deps"
            fi
        done < "$index_file"
            echo "Successfully retrieved package names and dependencies from $source source."
    else
        echo "Index file for $source source not found."
    fi
done

# 检查依赖是否满足
check_dependencies() {
    local pkg="$1"
    local deps="${DEPENDENCIES[$pkg]}"
    # 如果没有依赖，直接返回成功
    if [ -z "$deps" ]; then
        return 0
    fi
    # 检查是否已经解析过依赖
    if [ -z "${PARSED_DEPENDENCIES[$pkg]}" ]; then
        local parsed_deps=()
        for dep in $(echo "$deps" | tr ',' ' '); do
            # 提取包名，去除版本号等额外信息
            local dep_name=$(echo "$dep" | sed 's/([^)]*)//g' | sed 's/[[:space:]]//g')
            parsed_deps+=("$dep_name")
        done
        PARSED_DEPENDENCIES[$pkg]="${parsed_deps[@]}"
    fi
    # 用于检测循环依赖
    local visited=()
    local stack=("$pkg")

    while [ ${#stack[@]} -gt 0 ]; do
        local current_pkg="${stack[-1]}"
        stack=("${stack[@]::${#stack[@]}-1}")

        if [[ " ${visited[@]} " =~ " ${current_pkg} " ]]; then
            echo "Circular dependency detected: $current_pkg is part of a cycle."
            return 1
        fi
        visited+=("$current_pkg")

        local current_deps=(${PARSED_DEPENDENCIES[$current_pkg]})
        for dep in "${current_deps[@]}"; do
            if [[ -z "${INSTALLED_MAP[$dep]}" ]]; then
                echo "Dependency $dep for package $pkg is not installed."
                return 1
            fi
            stack+=("$dep")
        done
    done

    return 0
 

}

# 安装所有定义源列表的包，按源顺序进行
remaining_packages=()
for source in "${SOURCES[@]}"; do
    echo "Starting to install packages from $source source..."
    if [ ${#remaining_packages[@]} -eq 0 ]; then
        # 如果没有剩余未安装的包，使用当前源的包列表
        current_packages=("${PKG_ARRAYS[$source][@]}")
    else
        # 合并剩余未安装的包和当前源的包列表
        current_packages=("${remaining_packages[@]}" "${PKG_ARRAYS[$source][@]}")
    fi
    remaining_packages=()
    for package in "${current_packages[@]}"; do
        if check_dependencies "$package"; then
            ./scripts/feeds install "$package"
            if [ $? -eq 0 ]; then
                echo "Successfully installed package: $package from $source source."
                INSTALL_SUCCESS[$source]+="$package "
                INSTALLED_MAP[$package]=1
            else
                echo "Failed to install package: $package from $source source."
                INSTALL_FAILED[$source]+="$package "
                remaining_packages+=("$package")
            fi
        else
            echo "Package $package cannot be installed due to unmet dependencies."
            INSTALL_FAILED[$source]+="$package "
            remaining_packages+=("$package")
        fi
    done
        echo "Installation process for $source source completed."
done

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
