#!/bin/bash
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
# sed -i "/src-git alon2 /d; 3 i src-git alon2 https://github.com/xiealon/small;${CONFIG_REPO}" feeds.conf.default

sed -i "/src-git alon1 /d; \$a src-git alon1 https://github.com/xiealon/openwrt-package" feeds.conf.default
 if [ $? -ne 0 ]; then
   echo "Failed to modify feeds.conf.default for alon1 source."
   exit 1
 else
   echo "Successfully updated alon1 in feeds.conf.default"
 fi

sed -i "/src-git alon2 /d; \$a src-git alon2 https://github.com/xiealon/small" feeds.conf.default
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

# 安装所有包
if ./scripts/feeds install -a; then
   echo "Feeds installed successfully."
else
   echo "Failed to install feeds."
   cp feeds.conf.default.bak feeds.conf.default
   exit 1
fi

# 移除不需要的包
# rm -rf feeds/luci/applications/luci-app-mosdns
# rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,v2ray*,sing*,smartdns}
# rm -rf feeds/packages/utils/v2dat
# rm -rf feeds/packages/lang/golang

# 克隆新的 golang 包
# git clone https://github.com/xiealon/golang feeds/packages/lang/golang

# 卸载 alon、alon1 和 alon2 源的包
SOURCES=("alon" "alon1" "alon2")
PACKAGES=()
for source in "${SOURCES[@]}"; do
index_file="feeds/${source}/index"
 if [ -f "$index_file" ]; then
   packages=$(grep -E '^Package:' "$index_file" | awk '{print $2}')
   PACKAGES+=($packages)
 fi
done
for package in "${PACKAGES[@]}"; do
    ./scripts/feeds uninstall "$package"
done

# 获取 alon 源的所有包名
alon_pkgs=$(grep Package ./feeds/alon.index 2>/dev/null | awk -F': ' '{print $2}')
IFS=' ' read -r -a alon_pkg_array <<< "$alon_pkgs"

# 获取 alon1 源的所有包名
alon1_pkgs=$(grep Package ./feeds/alon1.index 2>/dev/null | awk -F': ' '{print $2}')
mapfile -t alon1_pkg_array < <(echo "$alon1_pkgs")

# 获取 alon2 源的所有包名
alon2_pkgs=$(grep Package ./feeds/alon2.index 2>/dev/null | awk -F': ' '{print $2}')
mapfile -t alon2_pkg_array < <(echo "$alon2_pkgs")

# 优先安装 alon 源的包，并记录安装失败的包
failed_pkgs=()
for pkg in "${alon_pkg_array[@]}"; do
 if ! ./scripts/feeds install -p alon "$pkg"; then
   failed_pkgs+=("$pkg")
 fi
done
unset IFS

# 找出 alon1 和 alon2 中相同的包
common_pkgs=($(comm -12 <(sort <<<"${alon1_pkgs// /$'\n'}") <(sort <<<"${alon2_pkgs// /$'\n'}")))

# 过滤掉 common_pkgs 中与 alon_pkgs 重复的包
declare -A seen
for pkg in "${alon_pkg_array[@]}"; do
    seen["$pkg"]=1
done
unique_common_pkgs=()
for pkg in "${common_pkgs[@]}"; do
 if [[ -z "${seen[$pkg]}" ]]; then
   unique_common_pkgs+=("$pkg")
 fi
done
unset seen

# 安装 alon1 源中 alon 源没有且不在 common_pkgs 中的包
for pkg in "${alon1_pkg_array[@]}"; do
 if [[ ! " ${alon_pkg_array[*]} " =~ " ${pkg} " ]] && [[ ! " ${common_pkgs[*]} " =~ " ${pkg} " ]]; then
   if ./scripts/feeds install -p alon1 "$pkg"; then
      echo "Successfully installed $pkg from alon1 source."
   else
      echo "Failed to install $pkg from alon1 source."
   fi
 fi
done

# 安装 alon2 源中 alon 源和 alon1 源都没有的包
for pkg in "${alon2_pkg_array[@]}"; do
 if [[ ! " ${alon_pkg_array[*]} " =~ " ${pkg} " ]] && [[ ! " ${alon1_pkg_array[*]} " =~ " ${pkg} " ]]; then
   if ./scripts/feeds install -p alon2 "$pkg"; then
      echo "Successfully installed $pkg from alon2 source."
   else
      echo "Failed to install $pkg from alon2 source."
   fi
 fi
done

# 安装 alon1 和 alon2 中不与 alon 重复的相同包

for pkg in "${unique_common_pkgs[@]}"; do
 if ! (./scripts/feeds install -p alon1 "$pkg") && ! (./scripts/feeds install -p alon2 "$pkg"); then
    echo "Failed to install package $pkg from either alon1 or alon2 source."
 fi
done

# if ! ./scripts/feeds install -p alon1 "$pkg"; then
#     if ! ./scripts/feeds install -p alon2 "$pkg"; then
#     echo "Failed to install package $pkg from either alon1 or alon2 source."
#     fi
# fi

# 定义关联数组用于快速查找

declare -A alon1_pkg_map
declare -A alon2_pkg_map

# 填充关联数组

for pkg in "${alon1_pkg_array[@]}"; do
   alon1_pkg_map["$pkg"]=1
done
for pkg in "${alon2_pkg_array[@]}"; do
   alon2_pkg_map["$pkg"]=1
done

# 尝试使用 alon1 和 alon2 源安装 alon 源中安装失败的包

for pkg in "${failed_pkgs[@]}"; do
 if [[ -n "${alon1_pkg_map[$pkg]}" ]]; then
    if ./scripts/feeds install -p alon1 "$pkg"; then
       echo "Successfully installed $pkg from alon1 source (after alon install failure)."
    else
       echo "Failed to install $pkg from alon1 source (after alon install failure)."
    fi
 elif [[ -n "${alon2_pkg_map[$pkg]}" ]]; then
    if ./scripts/feeds install -p alon2 "$pkg"; then
      echo "Successfully installed $pkg from alon2 source (after alon install failure)."
    else
      echo "Failed to install $pkg from alon2 source (after alon install failure)."
    fi
 fi
done
