#!/bin/bash

CONFIG_REPO="${1}"
if [ -z "$CONFIG_REPO" ]; then
echo "Error: Please provide the configuration repository as the first argument."
exit 1
fi

# 备份 feeds.conf.default 文件
cp feeds.conf.default feeds.conf.default.bak

# 处理第一个软件源
sed -i "/src-git alon /d; 1 i src-git alon https://github.com/xiealon/openwrt-packages;${CONFIG_REPO}" feeds.conf.default

# 处理新增的两个软件源
sed -i "/src-git alon1 /d; $a src-git alon1 https://github.com/xiealon/openwrt-package" feeds.conf.default
sed -i "/src-git alon2 /d; $a src-git alon2 https://github.com/xiealon/small" feeds.conf.default

# 更新所有feeds
if ./scripts/feeds update -a; then
echo "Feeds updated successfully."
else
echo "Failed to update feeds."
cp feeds.conf.default.bak feeds.conf.default
fi

# 移除不需要的包
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,v2ray*,sing*,smartdns}
rm -rf feeds/packages/utils/v2dat
# rm -rf feeds/packages/lang/golang

# 克隆新的golang包
# git clone https://github.com/xiealon/golang feeds/packages/lang/golang

# 卸载所有已安装的包
./scripts/feeds uninstall -a

# 获取alon源的所有包名
alon_pkgs=$(grep Package ./feeds/alon.index 2>/dev/null | awk -F': ' '{print $2}')
IFS=' ' read -r -a alon_pkg_array <<< "$alon_pkgs"

# 获取alon1源的所有包名
alon1_pkgs=$(grep Package ./feeds/alon1.index 2>/dev/null | awk -F': ' '{print $2}')
mapfile -t alon1_pkg_array < <(echo "$alon1_pkgs")

# 获取alon2源的所有包名
alon2_pkgs=$(grep Package ./feeds/alon2.index 2>/dev/null | awk -F': ' '{print $2}')
mapfile -t alon2_pkg_array < <(echo "$alon2_pkgs")

# 优先安装alon源的包，并记录安装失败的包
failed_pkgs=()
for pkg in "${alon_pkg_array[@]}"; do
if ! ./scripts/feeds install -p alon "$pkg"; then
failed_pkgs+=("$pkg")
fi
done
unset IFS

# 找出alon1和alon2中相同的包
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
if [[ ! " ${alon_pkg_array[]} " =~ " ${pkg} " ]] && [[ ! " ${common_pkgs[]} " =~ " ${pkg} " ]]; then
./scripts/feeds install -p alon1 "$pkg"
fi
done

# 安装 alon2 源中 alon 源和 alon1 源都没有的包
for pkg in "${alon2_pkg_array[@]}"; do
if [[ ! " ${alon_pkg_array[]} " =~ " ${pkg} " ]] && [[ ! " ${alon1_pkg_array[]} " =~ " ${pkg} " ]]; then
./scripts/feeds install -p alon2 "$pkg"
fi
done

# 安装 alon1 和 alon2 中不与 alon 重复的相同包
for pkg in "${unique_common_pkgs[@]}"; do
if ! ./scripts/feeds install -p alon1 "$pkg" && ! ./scripts/feeds install -p alon2 "$pkg"; then
echo "Failed to install package $pkg from either alon1 or alon2 source."
fi
done

# 尝试使用 alon1 和 alon2 源安装 alon 源中安装失败的包
for pkg in "${failed_pkgs[@]}"; do
if printf "%s\n" "${alon1_pkg_array[@]}" | grep -q "^$pkg$"; then
./scripts/feeds install -p alon1 "$pkg"
elif printf "%s\n" "${alon2_pkg_array[@]}" | grep -q "^$pkg$"; then
./scripts/feeds install -p alon2 "$pkg"
fi
done

# 安装其他源的包，已安装过的包不会重复安装
if ./scripts/feeds install -a; then
echo "Feeds installed successfully."
else
echo "Failed to install feeds."
cp feeds.conf.default.bak feeds.conf.default
fi
