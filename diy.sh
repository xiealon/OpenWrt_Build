#!/usr/bin/env bash
#
# 2025 Alon <https://github.com/xiealon> apply and modify to Ing wjz304
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/xiealon/OpenWrt_Build
# File name: diy.sh
# Description: OpenWrt DIY script
#

repo=${1:-openwrt}
owner=${2:-Alon}

echo "OpenWrt DIY script"

echo "repo: ${repo}; owner: ${owner};"

# Modify default IP
sed -i 's/192.168.1.1/10.10.10.220/g' package/base-files/files/bin/config_generate

# Modify hostname
sed -i 's/OpenWrt/Alon Creat By LEDE/g' package/base-files/files/bin/config_generate

# Modify timezone
sed -i "s/'UTC'/'CST-8'\n        set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# Modify banner
if [ "${owner}" = "Alon" ]; then
  if [ "${repo}" = "openwrt" ]; then
    cat >package/base-files/files/etc/banner <<EOF
  
                  Openwrt By ${owner} 
 -----------------------------------------------------
 %D %V, %C
 -----------------------------------------------------

EOF
  else
    cat >package/base-files/files/etc/banner <<EOF
    
            Lede By ${owner}  
-------------------------------------------
%D %V, %C
-------------------------------------------

EOF
  fi
else
  cat >package/base-files/files/etc/banner <<EOF
  -------------------------------------------
  		%D %V, %C      By ${owner} 
  -------------------------------------------
EOF
fi

# lede    ==> ${defaultsettings}
# openwrt ==> feeds/alon/default-settings
defaultsettings=*/*/default-settings
[ "${repo}" = "openwrt" ] && language=zh_cn || language=zh_Hans

# Set default language
#sed -i "s/en/${language}/g" ${defaultsettings}/files/zzz-default-settings
#sed -i "s/en/${language}/g" package/luci/modules/luci-base/root/etc/uci-defaults/luci-base
#sed -i "s/+@LUCI_LANG_en/+@LUCI_LANG_${language}/g" ${defaultsettings}/Makefile

# Modify password to Null
sed -i '/CYXluq4wUazHjmCDBCqXF/d' ${defaultsettings}/files/zzz-default-settings

# Modify the version number
sed -i "s/OpenWrt /${owner} build $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt /g" ${defaultsettings}/files/zzz-default-settings
sed -i "s/LEDE /${owner} build $(TZ=UTC-8 date "+%Y.%m.%d") @ LEDE /g" ${defaultsettings}/files/zzz-default-settings

# Remove openwrt_alon
# sed -i '/sed -i "s\/# \/\/g" \/etc\/opkg\/distfeeds.conf/a\sed -i "\/openwrt_alon\/d" \/etc\/opkg\/distfeeds.conf' ${defaultsettings}/files/zzz-default-settings

# Modify network setting 设置网络基本参数
sed -i '$i uci set network.lan.ipaddr="10.10.10.220"' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.gateway="10.10.10.10"' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.netmask="255.255.255.0"' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.dns="10.10.10.10 112.112.208.1 139.9.23.90 180.76.76.76 223.5.5.5 223.6.6.6 "' ${defaultsettings}/files/zzz-default-settings

# modified the Dns servers
sed -i '$i uci set network.lan.dns_search="ns1.huaweicloud - dns.com "' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.dns_search="ns1.huaweicloud - dns.cn "' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.dns_search="ns1.huaweicloud - dns.net "' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.dns_search="ns1.huaweicloud - dns.org "' ${defaultsettings}/files/zzz-default-settings

# set the ipv6 prefix and suffix
sed -i '$i uci set network.lan.ip6assign="64"' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci set network.lan.ip6ifaceid"eui64"' ${defaultsettings}/files/zzz-default-settings

# ignore lan DHCP
sed -i '$i uci set dhcp.lan.ignore="1"' ${defaultsettings}/files/zzz-default-settings

# 删除WAN接口配置 delete wan network
sed -i '$i uci delete network.wan' ${defaultsettings}/files/zzz-default-settings
sed -i '$i uci delete network.wan6' ${defaultsettings}/files/zzz-default-settings
# 绑定所有物理接口到LAN  bind all Port to Lan
sed -i '$i uci set network.lan.ifname="eth0.1 eth1"' ${defaultsettings}/files/zzz-default-settings 
# 包含VLAN和无线接口 include the VLAN and wireless （Port）
# sed -i '$i uci set network.lan.type='bridge'' ${defaultsettings}/files/zzz-default-settings

# 提交 commit
sed -i '$i uci commit network' ${defaultsettings}/files/zzz-default-settings

# Modify Default PPPOE Setting
# sed -i '$i uci set network.wan.username=PPPOE_USERNAME' ${defaultsettings}/files/zzz-default-settings
# sed -i '$i uci set network.wan.password=PPPOE_PASSWD' ${defaultsettings}/files/zzz-default-settings
# sed -i '$i uci commit network' ${defaultsettings}/files/zzz-default-settings

# auto update
# sed -i '$i uci set autoupdater.general.enable="0"' ${defaultsettings}/files/zzz-default-settings
# sed -i '$i uci set commit' ${defaultsettings}/files/zzz-default-settings

# Modify ssid
sed -i 's/OpenWrt/Alon/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# Enable wifi
sed -i 's/.disabled=1/.disabled=0/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# Enable MU-MIMO
sed -i 's/mu_beamformer=0/mu_beamformer=1/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# Modify kernel version
#sed -i 's/KERNEL_PATCHVER:=5.15/KERNEL_PATCHVER:=5.4/g' ./target/linux/x86/Makefile

# Modify maximum connections
sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

# Modify default theme
deftheme=bootstrap
if [ "${owner}" = "Leeson" ]; then
  deftheme=bootstrap
elif [ "${owner}" = "Lyc" ]; then
  deftheme=pink
else
  deftheme=argon
fi
echo deftheme: ${deftheme}
sed -i "s/bootstrap/${deftheme}/g" feeds/luci/collections/luci/Makefile
sed -i "s/bootstrap/${deftheme}/g" feeds/luci/modules/luci-base/root/etc/config/luci

# Add kernel build user
[ -z $(grep "CONFIG_KERNEL_BUILD_USER=" .config) ] &&
  echo 'CONFIG_KERNEL_BUILD_USER="${owner}"' >>.config ||
  sed -i "s|\(CONFIG_KERNEL_BUILD_USER=\).*|\1$\"${owner}\"|" .config

# Add kernel build domain
[ -z $(grep "CONFIG_KERNEL_BUILD_DOMAIN=" .config) ] &&
  echo 'CONFIG_KERNEL_BUILD_DOMAIN="GitHub Actions"' >>.config ||
  sed -i 's|\(CONFIG_KERNEL_BUILD_DOMAIN=\).*|\1$"GitHub Actions"|' .config

# Modify kernel and rootfs size
#sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*$/CONFIG_TARGET_KERNEL_PARTSIZE=64/' .config
#sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*$/CONFIG_TARGET_ROOTFS_PARTSIZE=1024/' .config

# Modify app list
sed -i 's|admin/vpn/|admin/services/|g' package/feeds/luci/luci-app-ipsec-vpnd/root/usr/share/luci/menu.d/luci-app-ipsec-vpnd.json   # grep "IPSec VPN Server" -rl ./
sed -i 's/"vpn"/"services"/g; s/"VPN"/"Services"/g' package/feeds/alon/luci-app-zerotier/luasrc/controller/zerotier.lua               # grep "ZeroTier" -rl ./
sed -i 's/"Argon 主题设置"/"主题设置"/g' package/feeds/alon/luci-app-argon-config/po/*/argon-config.po                                 # grep "Argon 主题设置" -rl ./

# Info
# luci-app-netdata 1.33.1汉化版 导致 web升级后 报错: /usr/lib/lua/luci/dispatcher.lua:220: /etc/config/luci seems to be corrupt, unable to find section 'main'

# CONFIG_PACKAGE_luci-app-bypass_INCLUDE_Trojan-Go
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_GO
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_IPT2Socks
# CONFIG_PACKAGE_trojan-go  导致 web升级后 报错: /usr/lib/lua/luci/dispatcher.lua:220: /etc/config/luci seems to be corrupt, unable to find section 'main'

# luci-app-beardropper 导致 web升级后 /etc/config/network 信息丢失
# CONFIG_PACKAGE_kmod  导致 web升级 不能保存配置
