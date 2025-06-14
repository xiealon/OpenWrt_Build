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

# 定义要处理的源列表
SOURCES=("alon" "alon1" "alon2")
declare -A PKG_ARRAYS

# 循环处理每个源，获取包名并存储到关联数组中
for source in "${SOURCES[@]}"; do
   index_file="feeds/${source}/index"
   if [ -f "$index_file" ]; then
      packages=$(grep -E '^Package:' "$index_file" | awk '{print $2}')
      mapfile -t PKG_ARRAYS[$source] <<< "$packages"
      echo "Successfully retrieved package names from $source source."
   else
      echo "Index file for $source source not found."
   fi
done

# 卸载 alon、alon1 和 alon2 源的包
PACKAGES=()
for source in "${SOURCES[@]}"; do
PACKAGES+=("${PKG_ARRAYS[$source][@]}")
done
echo "Starting to uninstall packages from alon, alon1, and alon2 sources..."
for package in "${PACKAGES[@]}"; do
   ./scripts/feeds uninstall "$package"
   if [ $? -ne 0 ]; then
      echo "Failed to uninstall package: $package"
   else
      echo "Successfully uninstalled package: $package"
   fi
done
echo "Uninstallation process completed."

# 优先安装 alon 源的包，并记录安装失败的包
FAILED_PKGS=()
echo "Starting to install packages from alon source..."
for package in "${PKG_ARRAYS[alon][@]}"; do
   echo "Trying to install $package from alon source..."
   ./scripts/feeds install "$package"
   if [ $? -ne 0 ]; then
      FAILED_PKGS+=("$package")
      echo "Failed to install $package from alon source."
   else
      echo "Successfully installed $package from alon source."
   fi
done
echo "Packages failed to install from alon source: ${FAILED_PKGS[@]}"

# 找出 alon1 和 alon2 中相同的包
declare -A common_pkg_map
for pkg in "${PKG_ARRAYS[alon1][@]}"; do
   common_pkg_map[$pkg]=1
done
COMMON_PKGS=()
for pkg in "${PKG_ARRAYS[alon2][@]}"; do
   if [[ ${common_pkg_map[$pkg]} ]]; then
      COMMON_PKGS+=("$pkg")
   fi
done
echo "Common packages in alon1 and alon2 sources: ${COMMON_PKGS[@]}"

# 过滤掉 common_pkgs 中与 alon_pkgs 重复的包
FILTERED_COMMON_PKGS=()
for pkg in "${COMMON_PKGS[@]}"; do
   found=false
   for alon_pkg in "${PKG_ARRAYS[alon][@]}"; do
      if [[ $pkg == $alon_pkg ]]; then
         found=true
         break
      fi
   done
   if [ "$found" = false ]; then
      FILTERED_COMMON_PKGS+=("$pkg")
   fi
done
echo "Filtered common packages (excluding those in alon source): ${FILTERED_COMMON_PKGS[@]}"

# 安装 alon1 源中 alon 源没有且不在 common_pkgs 中的包
echo "Starting to install packages from alon1 source that are not in alon source and not in common packages..."
for pkg in "${PKG_ARRAYS[alon1][@]}"; do
   found_in_alon=false
   found_in_common=false
   for alon_pkg in "${PKG_ARRAYS[alon][@]}"; do
      if [[ $pkg == $alon_pkg ]]; then
         found_in_alon=true
         break
      fi
   done
   for common_pkg in "${FILTERED_COMMON_PKGS[@]}"; do
      if [[ $pkg == $common_pkg ]]; then
         found_in_common=true
         break
      fi
   done
   if [ "$found_in_alon" = false ] && [ "$found_in_common" = false ]; then
      echo "Trying to install $pkg from alon1 source..."
      ./scripts/feeds install "$pkg"
      if [ $? -ne 0 ]; then
         echo "Failed to install $pkg from alon1 source."
      else
         echo "Successfully installed $pkg from alon1 source."
      fi
   fi
done

# 安装 alon2 源中 alon 源和 alon1 源都没有的包
echo "Starting to install packages from alon2 source that are not in alon and alon1 sources..."
for pkg in "${PKG_ARRAYS[alon2][@]}"; do
   found_in_alon=false
   found_in_alon1=false
   for alon_pkg in "${PKG_ARRAYS[alon][@]}"; do
      if [[ $pkg == $alon_pkg ]]; then
         found_in_alon=true
         break
      fi
   done
   for alon1_pkg in "${PKG_ARRAYS[alon1][@]}"; do
      if [[ $pkg == $alon1_pkg ]]; then
         found_in_alon1=true
         break
      fi
   done
   if [ "$found_in_alon" = false ] && [ "$found_in_alon1" = false ]; then
      echo "Trying to install $pkg from alon2 source..."
      ./scripts/feeds install "$pkg"
      if [ $? -ne 0 ]; then
         echo "Failed to install $pkg from alon2 source."
      else
         echo "Successfully installed $pkg from alon2 source."
      fi
   fi
done

# 安装 alon1 和 alon2 中不与 alon 重复的相同包
echo "Starting to install common packages from alon1 and alon2 sources that are not in alon source..."
for pkg in "${FILTERED_COMMON_PKGS[@]}"; do
   echo "Trying to install $pkg from alon1 and alon2 sources..."
   ./scripts/feeds install "$pkg"
   if [ $? -ne 0 ]; then
      echo "Failed to install $pkg from alon1 and alon2 sources."
   else
      echo "Successfully installed $pkg from alon1 and alon2 sources."
   fi
done

# 尝试使用 alon1 和 alon2 源安装 alon 源中安装失败的包
echo "Trying to install packages that failed in alon source using alon1 and alon2 sources..."
for pkg in "${FAILED_PKGS[@]}"; do
   echo "Trying to install $pkg from alon1 source..."
   ./scripts/feeds install --source=alon1 "$pkg"
   if [ $? -ne 0 ]; then
      echo "Failed to install $pkg from alon1 source. Trying alon2 source..."
      ./scripts/feeds install --source=alon2 "$pkg"
      if [ $? -ne 0 ]; then
         echo "Failed to install $pkg from both alon1 and alon2 sources."
      else
         echo "Successfully installed $pkg from alon2 source."
      fi
   else
      echo "Successfully installed $pkg from alon1 source."
   fi
done

echo "Script execution completed."
