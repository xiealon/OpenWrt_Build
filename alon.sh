#!/bin/bash

# 处理第一个软件源

sed -i "/src-git alon /d; 1 i src-git alon https://github.com/xiealon/openwrt-packages;${CONFIG_REPO}" feeds.conf.default

# 处理新增的两个软件源

sed -i '1i src-git alon1 https://github.com/xiealon/openwrt-package' feeds.conf.default
sed -i '2i src-git alon2 https://github.com/xiealon/small' feeds.conf.default

# 更新所有feeds

./scripts/feeds update -a

# 移除不需要的包

rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,v2ray*,sing*,smartdns}
rm -rf feeds/packages/utils/v2dat
rm -rf feeds/packages/lang/golang

# 克隆新的golang包

git clone https://github.com/xiealon/golang feeds/packages/lang/golang

# 卸载所有已安装的包

./scripts/feeds uninstall -a

# 获取alon源的所有包名

alon_pkgs=$(grep Package ./feeds/alon.index 2>/dev/null | awk -F': ' '{print $2}')

# 获取alon1源的所有包名

alon1_pkgs=$(grep Package ./feeds/alon1.index 2>/dev/null | awk -F': ' '{print $2}')

# 获取alon2源的所有包名

alon2_pkgs=$(grep Package ./feeds/alon2.index 2>/dev/null | awk -F': ' '{print $2}')

# 优先安装alon源的包，并记录安装失败的包

failed_pkgs=()
for pkg in $alon_pkgs; do
if ! ./scripts/feeds install -p alon "$pkg"; then
failed_pkgs+=("$pkg")
fi
done

# 找出alon1和alon2中相同的包

common_pkgs=()
for pkg in $alon1_pkgs; do
if echo "$alon2_pkgs" | grep -q "$pkg"; then
common_pkgs+=("$pkg")
fi
done

# 安装alon1源中alon源没有且不在common_pkgs中的包

for pkg in $alon1_pkgs; do
if ! echo "$alon_pkgs" | grep -q "$pkg" && ! echo "${common_pkgs[@]}" | grep -q "$pkg"; then
./scripts/feeds install -p alon1 "$pkg"
fi
done

# 安装alon2源中alon源和alon1源都没有的包

for pkg in $alon2_pkgs; do
if ! echo "$alon_pkgs" | grep -q "$pkg" && ! echo "$alon1_pkgs" | grep -q "$pkg"; then
./scripts/feeds install -p alon2 "$pkg"
fi
done

# 尝试使用alon1和alon2源安装alon源中安装失败的包

for pkg in "${failed_pkgs[@]}"; do
if echo "$alon1_pkgs" | grep -q "$pkg"; then
./scripts/feeds install -p alon1 "$pkg"
elif echo "$alon2_pkgs" | grep -q "$pkg"; then
./scripts/feeds install -p alon2 "$pkg"
fi
done

# 安装common_pkgs中的包（只从alon1安装，避免重复）

for pkg in "${common_pkgs[@]}"; do
./scripts/feeds install -p alon1 "$pkg"
done
